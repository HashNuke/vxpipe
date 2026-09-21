# Deepgram voice selection

2026-09-21. Started from the clean worktree after Rime checkpoint `718bb9b4`. Deepgram's
official Flux TTS catalog states that each English voice uses a `flux-{voice}-en` model ID on
`/v2/speak`. Coda and Flux family names do not belong in the provider capability manifest;
session names are now `Deepgram.STTSession` and `Deepgram.TTSSession`. Flux-specific config and
wire decoding stay private to the adapter. The endpoint and protocol behavior did not change.

The selected call-spec form is `model: "flux"` plus `options.voice: "haley"`; the Deepgram
provider builds `flux-haley-en`. Valid voice syntax is checked before activation. Explicit full
model selections remain valid because published call-spec revisions may contain them and are
immutable. This is not a second runtime or a fallback; both forms use the same semantic session.
The rejected choices were forcing model-specific session module names and rewriting published
source revisions. The durable decision is in `docs/deepgram-voice-selection.md`.

The focused voice-selection test failed with unsupported capability before the implementation,
then passed with derived URI and malformed-voice checks. The demo-sample test likewise failed on
the old full model and passed when its call specs used the voice form. Inline activation passed
with `model: "flux"` and still resolved the prior `flux-haley-en` wire model. The Deepgram/session,
plan-startup and call-spec focused run passed 91 tests. Providers registry passed eight tests;
affected persistence tests passed 26. Root compilation with warnings as errors passed. A wider
Gateway focused run was stopped after several minutes of expected call-scenario logging so that
the implementation could continue; it is not counted as passing. Mechanical rename left unused
test aliases, which were removed. Final targeted and root gates remain pending.

The voice-only form was also tested red-green: `options: %{voice: "hannah"}` initially failed
because selection required an encoding, then passed after the provider supplied its existing
linear16 default. Demo and development samples now use only the voice option; inline activation
confirms the resolved 48 kHz output and unchanged wire model.

The affected Console demo/runtime tests passed 12/12; Gateway's outbound-phone and RTVI
boundary tests passed 6/6 and 3/3; the wider combined Gateway run was not allowed to claim a
result after being stopped. Root format check, compile with warnings as errors, strict Credo
(1,033 files, no issues), and unused-dependency check passed. A controlled four-scheduler,
32-session × 20-turn Deepgram TTS run completed 640/640 requests. Completion p50/p95/p99 was
0.921/1.985/4.466 ms; settlement was 1.299/2.339/5.377 ms. Both p99 values remain below the
accepted 4.622/5.582 ms baseline, though higher than the preceding idle Rime-checkpoint run.
The model/voice conversion itself is pure and its URL is asserted in the focused test. Full
umbrella verification remains a final milestone gate.
