# Morse audio providers

## Scope and baseline

Milestone 3 adds opt-in local MorseCodeSTT and MorseCodeTTS implementations through the existing
speech capability contracts. It must preserve the room, turn, output-sink, queue, interruption
and provider-registry boundaries; it is not ordinary-speech recognition and does not change the
default hosted providers. The starting tree has provider-neutral capability processes, but their
provider callbacks assume remote-style connection data. The smallest likely adaptation is to let
an in-process transport receive structured local connection data rather than inventing a URL.

## Normative reference check

The in-force ITU-R M.1677-1 recommendation was checked before fixtures were written. Annex 1
defines the International Morse alphabet and specifies a dash as three dot units, one unit between
marks in a character, three units between characters, and seven units between words. The initial
implementation includes the recommendation's ASCII letters, figures, and directly representable
punctuation. It deliberately uses a separate 14-unit local end gap because the ITU word spacing
does not define an application utterance boundary.

The deterministic PCM defaults are 16 kHz, one signed little-endian 16-bit channel, a 700 Hz tone,
60 ms dot units and amplitude 4096 (one eighth of full scale). Detection uses 10 ms analysis
windows, a bounded threshold and a 100 Hz frequency tolerance. Configuration caps text at 256
bytes, encoded audio at 8 MiB and one undecided utterance at 60 seconds; configured maxima are
themselves bounded.

## Checkpoint 1: independent codec foundation

The first test file defined two independent expectations before any codec module existed:

- normalized `ET A` must produce literal tone/silence runs with ITU spacing and the local end gap;
- a hand-authored square-wave `SOS 2` signal must decode after being split repeatedly at odd byte
  boundaries, including in the middle of a PCM sample.

The red run reported both codec modules missing. The implementation added separate alphabet,
configuration, encoder and incremental decoder responsibilities. The encoder renders sine PCM;
the reference fixture renders square PCM from a literal signal plan, so encoder and decoder bugs
cannot validate each other. The decoder holds at most one partial analysis window plus bounded
utterance state, rejects a wrong tone/timing, and supports an explicit flush for the final tail.

The green focused command passes `2 tests, 0 failures`. Its first pass exposed a default-argument
compiler warning in `Config.new/1`; a function header removed that warning, and
`mix compile --warnings-as-errors` from the owning child now passes. Full alphabet, invalid input,
size, flush, silence and tolerance tests remain before transport integration. The complete owning
child suite passes `119 tests, 0 failures (1 excluded)`.

## Checkpoint 2: complete codec boundary cases

The next test expansion enumerated every directly represented ASCII letter, figure and punctuation
signal from the ITU table, then exercised invalid configuration, text/audio types, UTF-8, unsupported
characters/signals, input/output limits, silence, explicit/repeated flush, a split final PCM sample,
wrong frequency, invalid mark timing, a one-window timing tolerance and the 60-second undecided-
signal bound. The first run had two failures: a non-binary decoder input raised a function-clause
error, and invalid UTF-8 reached the alphabet lookup and returned the less accurate unsupported-
character error. The public codec boundary now maps those cases to `:invalid_audio` and
`:invalid_text` without raising.

The expanded focused suite passes `8 tests, 0 failures`, and the owning child compiles with warnings
as errors. The complete owning child suite passes `125 tests, 0 failures (1 excluded)`. This
completes the independent known-signal and arbitrary-chunk/tail test requirements.
The encoder remains bounded but materializes one complete request; incremental transport emission
and pending-output bounds will be addressed with the local provider adapters rather than claimed
here.

## Checkpoint 3: resumable encoder output

Inspection of the gateway's real audio egress showed a bounded packet queue. Sending one complete
Morse reply at provider speed would either fill that queue for long replies or require synthesis to
block before an interruption can be observed. The next red test therefore required a resumable
encoder state; it failed because `Encoder.start/2` and `Encoder.next/2` were absent.

The encoder now validates and plans a bounded request once, then renders at most the caller's
requested sample count while preserving its current tone/silence run and sine phase. The one-shot
helper drains this same path in fixed internal chunks. The test cuts `ET A` every 137 samples and
proves more than ten bounded chunks concatenate byte-for-byte to the existing expected signal,
then observes stable exhaustion. This gives the upcoming transport a discardable state rather than
an 8 MiB PCM allocation. The focused suite passes `9 tests, 0 failures`; warnings-as-errors compile
and the full owning child suite pass with `126 tests, 0 failures (1 excluded)`.

## Checkpoint 4: provider-neutral local connection data

The provider behaviors previously typed `connection_options/1` as a map that always contained a
remote URL and headers. Supplying those fields for an in-process codec would create a pretend
endpoint. The new red provider tests required both local providers to return `%{config: config}`
with no URL while still exposing the existing media and control/signal contracts; both tests
failed because the modules were absent.

`MorseCodeSTT` now translates bounded local JSON control messages into the same normalized STT
signals used by the room. `MorseCodeTTS` emits the existing speak/flush/interrupt commands,
normalizes lifecycle signals, and validates bounded audio frames. Both reuse the codec Config
struct, and the provider-neutral connection callback types now accept arbitrary structured maps.
Deepgram continues returning its URL/header map unchanged.

The focused provider suite passes `2 tests, 0 failures`; warnings-as-errors compile and the full
owning child suite pass with `128 tests, 0 failures (1 excluded)`. Transport processes, runtime
selection and default settings remain untouched.

## Checkpoint 5: in-process speech transports

The next red tests started the real `SpeechToText` and `TextToSpeech` capability GenServers with
local transport modules that did not yet exist. They require PCM split repeatedly on odd byte
boundaries to become one attributed `SOS` turn, a short `ET` reply to drain as more than ten
bounded audio frames through the ordinary output sink, and interruption of a paced long reply to
discard its remaining encoder state before a replacement begins.

`MorseCodeSTT.Transport` owns one incremental decoder and emits only the provider adapter's
ordinary connected/start/update/end/error control payloads. `MorseCodeTTS.Transport` owns one
pending text request, one resumable encoder and at most one unacknowledged output frame. The
default 20 ms chunks are scheduled at real time; a private zero-delay option is used only to keep
deterministic tests fast. Scheduled emissions carry a generation, so interruption invalidates any
already queued message and clears the old encoder without bypassing the existing capability's
playback interruption result.

The focused suite passes `3 tests, 0 failures`. The collected TTS frames independently decode to
`ET`, and the paced interruption test observes the replacement frame followed by no stale old
frame. `mix compile --warnings-as-errors && mix test` in `apps/vxpipe_call_engine` passes `131
tests, 0 failures (1 excluded)`. Registry/default configuration remains unchanged; definition
selection and whole-room verification are the next checkpoint.

## Checkpoint 6: closed alternate-provider selection

One runtime setting per speech kind previously meant `PlanStartup` could accept only a profile
whose provider module exactly matched the application default. The new red definition-driven
test supplied a valid Morse profile plus a closed alternative runtime alongside unchanged
Deepgram defaults. Startup rejected it at the caller's STT selection, confirming that profile
compilation alone did not accidentally authorize an implementation.

Each existing STT/TTS setting may now carry a `:providers` map keyed by provider module. Startup
first checks the top-level/default provider, then performs an exact lookup in that map. The chosen
entry must be enabled and structurally valid; no external string is converted to a module or
atom. Provider construction still merges application-owned private options with the compiled
public profile only after this lookup. The legacy application-default room path is unchanged.

Development config now registers both local provider modules and the corresponding closed
capability profiles without selecting them as sample defaults. The focused test moved from the
expected unsupported-STT failure to green and proves both local runtime values plus unchanged
Deepgram defaults. The complete definition-driven file passes `11 tests, 0 failures`. A later
development-config probe with placeholder secrets confirms both registry entries load, and the
complete owning child passes `132 tests, 0 failures (1 excluded)`. A later checkpoint must make
the trusted sample opt into both Morse profiles without demanding a Deepgram credential, then
prove the room audio loop.

## Checkpoint 7: definition-driven room audio loop

The room acceptance test builds the schema-versioned call definition and invocation through the
real compiler, with only the Morse profiles and the existing local model fixture in its closed
registries. Application configuration disables both hosted defaults and exposes only local
alternate runtimes. It starts the resulting call, attaches its entry caller, pushes `SOS` PCM
through `CallEngine.push_audio/2`, and observes the normal audio-turn start, final transcription
and completion events with the caller/connection correlation intact.

The fixture response `OK` then reaches the real local TTS capability and ordinary acknowledged
output sink. The test collects more than ten bounded frames, concatenates them, and decodes the
audio with a separate decoder instance before reporting playout complete and observing the
correlated agent-turn completion. No speech API key, socket module or network listener appears
in this setup.

The initial run failed after audio output had already completed because the test expected
`TextOutput.participant_id` to name the caller. Inspection of the owning room constructor
confirmed the established contract: output `participant_id` is the producing agent and
`source_participant_id` is the originating human. Updating only that expectation made the
focused test pass (`1 test, 0 failures`). The remaining proof work is repeated turns, long output,
explicit provider failures, opt-in sample configuration, documentation and milestone-wide gates.
A warnings-as-errors compile and the complete owning child suite pass with `133 tests, 0 failures
(1 excluded)`.

## Checkpoint 8: repeated, long, backpressured and invalid boundaries

The transport acceptance tests now send `SOS` and `ET` consecutively through one STT capability.
They observe exactly one start/final boundary per input, monotonically increasing provider turn
indexes (`0`, then `1`), and no text carried into the next utterance. The whole-room test likewise
runs a second audio input after completing the first output and proves a fresh correlation ID,
provider turn index `1`, preserved caller/agent attribution, and a second completed local reply.

The prior short TTS drain was strengthened to `PACK MY BOX WITH FIVE DOZEN JUGS`; it finishes in
more than 100 frames, every frame remains at or below the configured 20 ms/640-byte bound, and the
concatenated signal decodes without truncation. A blocked sink observes one frame and no second
frame before acknowledgement. The interruption test now collects the entire replacement, decodes
it as `E`, and completes its normal playback lifecycle after proving no stale prior frame arrived.

Finally, unsupported `%` text and a 1,200 Hz tone sent to the 700 Hz STT configuration produce
explicit local provider errors. The owning capability reports failure and terminates while no
invalid TTS audio is emitted. The local transport suite passes `6 tests, 0 failures`; the combined
transport/room run passes `7 tests, 0 failures`. Full child and umbrella gates will be rerun after
the remaining configuration and documentation work. The current warnings-as-errors compile and
complete owning child suite pass with `136 tests, 0 failures (1 excluded)`.

## Checkpoint 9: credential-free Console profile and contract documentation

The browser's negotiated incoming audio is Opus at 48 kHz, while Morse STT deliberately accepts
linear16. Selecting it for the sample would make the first microphone packet fail rather than
prove recognition. The development `morse` profile therefore removes browser STT and selects
48 kHz Morse TTS for typed input. Pairing it with `VXPIPE_DEV_MODEL_FIXTURE=true` starts the
sample without either hosted provider credential. The ordinary Deepgram profiles remain the
default and no provider selector was added to client input or the responsive Console.

This is runtime/configuration work, so the repository rule permits skipping a new red behavior
test. Three configuration probes supplied stronger boundary evidence: the default still selects
and enables Deepgram; `morse` loads with both credential variables absent, disables both hosted
defaults, omits browser STT, and selects the 48 kHz TTS profile; an unknown setting exits with the
documented fixed error. No secret value was printed or stored.

The root and Console-assets READMEs describe the typed audible test. The call-engine README now
records the exact alphabet, whitespace/case normalization, 1:3 mark and 1:3:7 spacing ratios,
14-unit local utterance gap, PCM format/sample rates, frequency/amplitude/window/tolerance
defaults, input/audio/duration bounds, explicit errors, one-frame backpressure, interruption
semantics, and the direct-PCM room command. Architecture now describes the implementation rather
than the old plan. It explicitly separates direct PCM from Opus, microphone DSP, acoustic echo,
ordinary speech and general noise robustness.

## Checkpoint 10: bounded Morse observability

The existing Telemetry normalizer mapped both new modules to `:other`, which made local speech
indistinguishable from an unknown integration. Red tests attached to the real engine event
contract and submitted the projected event to the Console reporter. They observed `:other` and a
missing `:morse` aggregate respectively.

Both `MorseCodeSTT` and `MorseCodeTTS` now map to one fixed `:morse` provider label. The Console
reporter's allowlist includes only that added atom; arbitrary strings still collapse to `:other`.
The focused green run passes engine `2 tests, 0 failures` and Console `6 tests, 0 failures` for
first-audio timing and a controlled STT unavailable count. Only duration/count, capability,
provider and safe failure category enter the aggregate—no transcript, PCM, call identity or raw
provider error. Architecture's documented closed provider set now matches the implementation.

The first complete umbrella test run exposed one test synchronization race: after the local TTS
failure notification arrived, process teardown sometimes exceeded ExUnit's 100 ms default under
parallel load. The test still uses a process monitor and exact `:provider_failed` reason, now with
the project's ordinary one-second asynchronous bound; no production timing changed. The rerun
passes formatting, warnings-as-errors, call engine `137 tests, 0 failures (1 excluded)`, gateway
`46 tests, 0 failures (4 excluded)`, Console `19 tests, 0 failures`, and
`mix deps.unlock --check-unused`.

## Completion verification

The subsequent Console delivery checkpoint moved the unchanged React sample under Phoenix's
esbuild watcher and made Phoenix/Bandit the single HTTPS server on Tailscale port 4000. The Morse
development profile remains application-selected and credential-free. Chromium rendered its
desktop and mobile creation states and initialized the Pipecat console on the new origin. The
required `agent-browser` command was unavailable, so this inspection used installed headless
Chromium through its DevTools protocol. One earlier clean attempt reached client and agent
`READY`; later headless retries hit ICE instability and do not supply extra media evidence.

The direct-PCM definition-driven room test remains the authoritative full Morse round trip: an
independent signal fixture traverses real room STT, transcript, agent fixture, TTS and output-sink
boundaries, and independent decoding verifies the response. Together with the focused long-drain,
backpressure, interruption, repeated-turn, failure and Telemetry tests, it covers every acceptance
item without claiming that browser Opus or ordinary speech is supported Morse input.

Final gates after the Console change pass formatting, warnings-as-errors, unused-dependency
checking, frontend `3 tests, 0 failures`, and umbrella suites with call engine `137 tests,
0 failures (1 excluded)`, gateway `46 tests, 0 failures (4 excluded)`, and Console `20 tests,
0 failures`. Milestone 3 is complete; Call Variables is next.
