# Scribe short answer and initial idle

## Scope and prior checkpoint

Continue ElevenLabs realtime STT/TTS acceptance after the owned STT session
checkpoint. Hosted-agent STS and AI gateway implementation remain deferred.
Scoped STT publication/startup, room integration and Console acceptance remain
pending. Keep selected paid cases separate; do not repeat cases that already pass.

## Short answer evidence

Add a missing-sample generation/reuse contract to the provider-owned Deepgram
test fixture helper before implementing it. The initial focused test fails
because `ensure_short!/1` is absent (seed 155469). After implementation the helper
file passes five tests, zero failures, seed 127300. The sample uses the fixed public phrase
"Yes." with the existing `aura-2-thalia-en` selection, raw 16 kHz mono S16LE PCM,
and no appended silence. Existing fixtures remain unchanged. Reusing a saved
short sample performs no credential read or TTS request.

Run only the new brief-first-answer ElevenLabs live case against the unchanged
STT adapter: one test, zero failures, one excluded, 3.0 seconds, seed 902523.
The missing sample requires one Deepgram TTS request and is saved for reuse.
The case establishes one genuine local onset and matching local-gap end with
recognized fixture text and acoustic input below two seconds. This observation
does not justify adding padding for short answers.

Generated sample review: 19,200 bytes / 600 ms, peak amplitude 18,232, RMS
2,417.82, zero clipped samples. Source phrase is fixed public test text; the
selected live recognizer identifies the expected word. No listening review was
performed or claimed.

## Initial idle failure

Add a distinct live case that prepares the allocation, waits thirty seconds
without submitting caller audio, then streams the reused brief-answer sample
with observed trailing quiet input. Use an explicit timer/receive deadline.
Against the unchanged adapter it fails: one test, one failure, two excluded,
30.6 seconds, seed 762412. The first submitted audio is rejected as `:closed`.
This proves loss of prepared readiness within the tested idle window, but does
not establish the server's exact disconnect deadline or reason.

The provider's [event reference](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/event-reference)
documents `insufficient_audio_activity`. Its
[wire reference](https://elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime)
describes a separate server-output keepalive option dependent on streamed silent
audio; that option does not alone maintain a client that sends no audio.

Investigate an empty, noncommitting input message as connection maintenance.
Keep it separate from accepted caller PCM, detector observations, acoustic
duration and recognition segment budgets. Do not manufacture silence or text.
First add a local wire regression; then re-run only the previously failing
idle case. Passing the thirty-second check proves that bounded window only.

## Repair evidence

The smallest local wire regression first fails because the shared transport
sends a WebSocket ping instead of the provider input protocol message: one
test, one failure, seed 235927. Add an optional socket callback for the keepalive
frame, leaving ordinary ping behavior as its default. Scribe opts into a ten-second
cadence and returns empty noncommitting input. Its audio API still rejects
empty PCM; this is connection maintenance, not accepted caller audio.

The first attempted green command excludes the integration-tagged file: zero
tests, three excluded. Correct the invocation to include the integration lane.
The wire/peer-close/privacy group then passes 29 tests, zero failures, seed
477328, including the existing TTS ping contract. The repaired selected idle
case passes one test, zero failures, two excluded, 32.3 seconds, seed 892995.
No Deepgram request is needed because the saved short sample is reused. Neither
the earlier short-answer case nor the passing two-turn case is re-run.

Shared socket callback changes require full umbrella verification before this
checkpoint is committed. Scoped STT service and room work remains next.

## Final checkpoint verification

All five root gates pass on the final runtime/test source: format, compilation
with warnings as errors, strict Credo (1,176 source files, no issues), default
umbrella tests and unused-dependency checking. The terminal umbrella run reports
3,014 tests, zero failures and 96 exclusions, seed 844978. Its CallEngine group
passes 1,806 tests; Gateway passes 522. The existing Lean build/oracle/replay
lane also passes one test, zero failures, seed 665060. All 155 local Markdown
links in the changed documents resolve. The fixed short sample's current
SHA-256 is `876c3f3910bce423ef1c3e38233533cf564126e2e8987f3af5c23d441e603329`.

This checkpoint proves short-answer and bounded initial-idle behavior. Next,
register the existing owned STT session through scoped credentials, compile its
private runtime from published calls, expose STT capability/model metadata,
and verify actual room behavior. Include long-turn acceptance covering protocol
maintenance during a manual segment and final recognition. Previously passing
paid cases remain excluded unless a concrete new interaction needs verification.
The provider-expansion milestone stays incomplete.
