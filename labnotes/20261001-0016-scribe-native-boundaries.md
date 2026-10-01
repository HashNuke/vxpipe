# Scribe native boundary preparation

## Intent and current scope

Continue the provider-expansion goal under the user-approved ElevenLabs realtime
STT/TTS scope. The previous goal turn made progress by removing uncommitted STS
work and synchronizing the milestone. Shared Gemini/OpenAI STS contracts remain
unchanged. Current Scribe protocol preparation is not conversational STT admission.

## Primary-source review and decision

The current [event reference](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/event-reference)
still documents partial and committed transcript events without an activity-start
notification. The [commit guide](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/transcripts-and-commit-strategies)
documents VAD silence commits and shows explicit threshold/duration settings.
Its approximately 36-second buffer explanation is under manual mode; it does
not settle long-input behavior in VAD mode. The
[wire reference](https://elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime)
exposes these query settings but no commit reason, activity event or correlated
input boundary. The [SDK configuration type](https://github.com/elevenlabs/elevenlabs-js/blob/main/src/wrapper/realtime/connection.ts)
makes individual returned VAD fields optional. None of this proves room admission.

Fix the native probe's settings to the published example: 1.5-second silence,
0.4 detection threshold and 100 ms minimum speech/silence. Manual mode remains
unchanged. When returned, the VAD acknowledgement must match each requested value;
missing optional echoes remain acceptable. Do not add public tuning options,
model/configuration environment variables, or infer barge-in from transcript text.
The existing separately selected VAD case now uses this request profile implicitly
through Scribe configuration; its line selection and bounded PCM remain unchanged.

## Red-green evidence

The focused request test first fails because VAD thresholds are missing from the
query. A new acknowledgement test fails because conflicting returned thresholds
are accepted: ten tests, two failures, seed 148150. The red result is recorded
from ExUnit output; a shell diagnostic subsequently printing the log returns
zero and is not evidence that ExUnit passed.

A fixed provider profile shared by query generation and mode-aware optional
acknowledgement validation makes all ten offline tests pass, seed 945928. After
formatting, the final current-source run passes ten tests, zero failures, seed
413021. This loads current credential/Scribe/socket sources with only the unchanged
Socket behaviour supplied by a compiled module. It uses neither network nor Mix
startup. It does not prove compiled socket integration or the umbrella suite.

Root format verification passes. Direct static Credo inspects 1,167 source files
with 38 checks and no issues. Its static Mix project startup does not replace
any required root gate or disable the TCP restriction.

## Execution barriers and next required work

The four remaining root commands are invoked from the umbrella root. Compilation
with warnings as errors, strict Mix Credo and default tests each fail before
project work because Mix.PubSub cannot open its TCP socket (`:eperm`). The
unused-dependency command fails at TCP-based lock acquisition for the same reason.
No live runner or paid case is invoked under this restriction. No speech state
machine or source cutover changes, so this protocol checkpoint does not require
another Lean run. No UI capability is added.

For the possible missing local speech-activity responsibility, an isolated Python
inspection finds NumPy available, but ONNX Runtime, ONNX and Torch absent. A
bounded public-source curl request for the pinned Silero wrapper fails DNS
resolution before download. No model/runtime artifact is installed, no inference
or performance experiment runs, and no dependency is selected. Web documentation
retrieval does not provide execution evidence for classifier feasibility.

Git metadata remains declared read-only with no escalation, so no stage, commit
or push is attempted. The unrelated user content configuration is preserved.
After this bounded preparation, the next acceptance steps require external-state
changes: permitted Mix/socket/DNS execution and writable Git metadata. Once
available, run only the new selected VAD case, establish long-input endpoint
semantics and verified genuine speech onset, then implement and verify owning
session, room, scoped publication and Console support. Do not advertise STT early
or repeat already passing paid cases. The milestone remains unchecked.

The execution restriction has recurred across at least three consecutive goal
turns. Offline scope cleanup and fixed-profile work made concrete progress, but
required live validation and detector feasibility now cannot proceed here.
The remaining goal is blocked on environment access, not complete; ElevenLabs
STS remains deferred by explicit user scope rather than by this blocker.
