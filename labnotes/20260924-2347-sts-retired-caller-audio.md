# STS retired caller audio

## Discovery

An independent review reproduced a WebRTC callback stopping its Connection after
a successful STT delivery because a missing STS handle was classified as fatal.
The current media classification makes this fatal for a whole call: the STS lane
returns `{:error, :speech_to_speech_unavailable}` whenever its ingress process is
gone, `IncomingAudio.deliver/6` treats any non-drop error as `:unavailable`, and
the transport then stops the connection. The external/hybrid source cutover just
shipped retires and recreates the STS capability, so this window is now on the
normal path for those modes.

## Design/dependency review (before tests/runtime)

The room owns the STS allocation lifecycle; the transport owns caller media
forwarding. A per-frame STS push is therefore best-effort: an absent or closed
STS ingress means there is no authorised consumer for that audio, so the frame
is dropped and no reply can be produced. Dropping cannot bypass room authority:
the room's `STSIngress`/policy checks still gate every frame while an allocation
exists, and when none exists there is nothing to authorise.

"Required STS that genuinely failed" stays fail-closed at the admission
boundary. `ConnectionReadiness.prepare_binding/3` requires the exact STS ingress
resource when the participant demand includes `speech_to_speech?`:
`sts_resources/2` propagates `{:error, :speech_to_speech_unavailable}` from
`CallEngine.speech_to_speech_input_configuration/1` when the handle is missing,
and `validate_intervals/3` rejects a non-current interval with
`:policy_not_prepared`. A call whose required STS allocation is absent at
admission still fails. Mid-call provider failure is the room's decision
(`SpeechToSpeech.handle_unavailable` and the capability lifecycle), not the
transport's.

Minimal seam: add `:speech_to_speech_unavailable` to the per-frame drop reasons
in both transports' `IncomingAudio` classifiers. Other STS errors (malformed,
unsupported, wrong connection, sequence) remain fatal. No new protocol and no
runtime ordering change; the readiness gate is unchanged.

Verification: a focused transport regression for both WebRTC and telephony
proves that a retired STS ingress drops the STS lane while the independent human
STT lane still receives the frame and the media result is not fatal. A readiness
regression confirms a required-but-missing STS ingress still fails admission.

## Progress

- [x] Red: for both WebRTC and telephony, a retired STS ingress made
  `deliver/6` return `{:unavailable, ...}` (two focused failures).
- [x] Added `:speech_to_speech_unavailable` to the per-frame drop reasons in
  `webrtc/incoming_audio.ex` and `telephony/incoming_audio.ex`. The two reds are
  green and `sts_input_test.exs` passes 13/0.
- [x] Readiness distinction already covered: `telephony/media_session_test.exs`
  proves a selected STS with a nil handle returns
  `:speech_to_speech_unavailable` and a stale interval returns
  `:policy_not_prepared`. No new readiness test was needed.
- [x] Focused Gateway group passes 31/0 on seeds 0 and 1; full Gateway child
  suite passes 508/0 (7 excluded, seed 0). Root format, warnings-as-errors
  compile, strict Credo and unused-dependency checks pass.
- [x] Ten-call measured lane passes (3 tests, 0 failures) in 25.3s across
  `llm_tts`, `sts_provider` and `sts_output_stt`; report updated in
  `20260924-0219-room-source-cutover-load.jsonl`.
- [ ] Commit this slice.

## Limits

This changes only per-frame media classification. It does not change the room's
STS lifetime, the readiness admission gate, or the source-cutover protocol. It
does not prove remote playout or transport-level RTP delivery; it proves the
local transport no longer tears down the connection when the room has retired
the STS allocation.
