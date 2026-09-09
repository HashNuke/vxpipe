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
