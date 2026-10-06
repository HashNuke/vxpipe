# Engine-owned native STS opening

An opening is an agent operation, distinct from caller text or audio. The room calls
`SpeechToSpeech.begin_opening/2` after its media/startup gate. Only the room owner can
start it; a held or unready capability rejects it. Successful admission records the
once-only flag. The operation travels through the existing bounded ordered input slot
as `generated` or `fixed` with nonempty valid UTF-8 text, limited to 4,096 bytes.

For response-start providers, the command carries the same accepted engine response
context used for ordinary input. Output still needs policy admission, allocation and
epoch correlation, output credit, and playback settlement. Legacy turn providers emit
`opening_started` only for the exact admitted command after its submission evidence.
That private event authorizes the ordinary output-admission path; it creates neither
a caller transcript nor an accepted caller-input archive fact.

## Provider boundaries

Morse turn and duplex STS emit deterministic generated `HELLO`, or encode the exact fixed
text, without its ordinary caller-input `RECEIVED` reply. Room tests decode actual PCM,
settle playback, and observe only the agent transcript. They also prove no ringing
speech and no second opener from a repeated answer report.

Google's fixture adapter submits an engine-owned realtime text cue. It does not open a
caller text turn; native input-transcription echoes are ignored while no real caller
exists. Generated output follows the normal credited streaming path. Both legacy and
response-start profiles have focused coverage.

For fixed Google output, a prompt alone is insufficient. The adapter holds PCM and
output transcription until the generation boundary. Only a complete transcript exactly
equal to the requested text releases output. Missing, additional or different text,
interruption, unexpected tools, a caller start, or overflow fails the allocation without
releasing unverified audio. No trimming or punctuation/case normalization is applied.
The private assembly is bounded to 4,096 fragments and 2 MiB PCM; validated fragments
are combined into at most sixteen 128 KiB output chunks, preserving PCM byte order and
the existing queue and credit limits. A pending opening cannot be replaced by another cue.

This is validation of provider-reported transcription, not independent recognition of
the spoken waveform or proof that a remote party heard it. Google remains unadvertised
behind its existing hosted interoperability gate. These tests make no Google API calls.

Providers without the optional opening callback return `unsupported_operation`, with
no fallback to caller text. `wait_for_input` uses no opening operation and retains its
existing behavior.

Current official [GPT-Live session guidance](https://developers.openai.com/api/docs/guides/live-conversations)
uses a once-only `session.instructions.append` after session startup to request a
greeting, keeping input audio running, including silence. Its acknowledgment confirms
instruction acceptance, not exact wording or playback. Commentary can paraphrase.
Checked 2026-10-05 using the OpenAI Docs skill; no hosted request was made.

The GPT-Live adapter now submits that native instruction once, retaining the original
engine context until its first real output burst. Later real silence input may advance
the duplex timeline without rebinding the greeting. Local command acceptance is not
reported as provider-confirmed input submission and creates no caller transcript.
Generated audio uses ordinary response admission and credited playback.

Fixed GPT-Live output uses the profile's existing energy-gap acoustic boundary. A private
segmenter collects one burst frame by frame, without room playback authority, until the
gap closes it. Its complete aligned transcript must equal the requested text, and its
transcript end must fit the captured PCM duration. Only then does the adapter announce
a response and await ordinary room admission. Missing, different or unalignable text,
caller speech, hold, delegation, connection loss, or a fenced thirty-second deadline
fails without releasing unverified audio or reseeding it. Late transcript additions to
the verified burst also fail. Delayed unalignable transcription can therefore reject
an otherwise correct greeting; the adapter does not guess that it was spoken correctly.

Collection is bounded to 2 MiB total received PCM and 4,096 transcript fragments. Text
cannot exceed the requested byte length. Verified PCM is coalesced into at most sixteen
128 KiB credited chunks; ordinary streaming keeps its existing 96 KiB queue bound.
The provider's existing 2,000-byte trusted instruction limit also applies to the fixed
cue, including its instruction prefix. A longer cue fails before sending rather than
truncating the requested wording. Transcript validation remains provider evidence,
not independent waveform recognition, remote hearing proof, or hosted interoperability.

## Alternatives and implications

Using ordinary `push_text` was rejected because it creates caller turn/transcript
evidence and changes Morse output. Adding hidden LLM or TTS selections to an STS plan
was rejected because it changes the approved capability/dependency contract. Treating
a model instruction as proof of fixed output was rejected because the model can add
or alter words. Unbounded buffering was rejected because withheld native output must
have a finite memory cost and a clear failure boundary.

Google's official [Live API capabilities](https://ai.google.dev/gemini-api/docs/live-api/capabilities)
documents realtime text input and text-triggered audio. Using that wire mechanism for
an engine-owned cue does not turn it into caller evidence in Vxpipe. Checked 2026-10-05.

## Verification

The initial room tests failed with missing generated audio and fixed `RECEIVED GOOD
DAY`. The new session operation initially failed as undefined. Google opening tests
failed as unsupported; a second cue was initially accepted; a fragmented fixed opening
initially exceeded the normal sixteen-chunk buffer. Each failure preceded its fix.

The focused session, Google, outgoing room and affected readiness tests pass: 84 tests,
zero failures, seed 34032. Broader speech regression found one 100 ms readiness-fixture
timeout; it now waits with an explicit one-second bound. All five final root gates pass: format, warnings-as-errors compilation, strict Credo
(1,193 source files), unused dependencies, and 3,134 tests with zero failures across all
nine applications (98 excluded, seed 269987). The final Lean build, oracle check and
Elixir replay also pass. This is the earlier turn-opening checkpoint's evidence.

Duplex regressions now pass: 161 tests, zero failures, seed 546518. Reds preceded native
Morse duplex support, GPT-Live generated/fixed commands, fixed-output lifecycle handling,
idle completion, and immutable opening origins. Strict Credo (1,196 files) and Lean
build/oracle/replay also pass. All final root gates pass: formatting, warnings-as-errors
compilation, strict Credo, unused dependencies, and 3,143 tests with zero failures,
98 excluded, seed 949782 across nine applications. D3 is accepted. Live E subsequently passed
both carrier directions and the unanswered gate, with 3,156 root tests passing; see the
[duplex labnotes](../labnotes/20261005-0318-duplex-sts-opening.md) for checkpoint evidence.
