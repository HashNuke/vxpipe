# External room control

2026-09-23: Inspected the current external/hybrid STS path. The scoped session
and Morse provider support `input_activity`, and the STS capability exposes it,
but `RoomAuthority.InputTurns` only publishes selected human-STT signals and
never forwards activity to that capability. This leaves external/hybrid room
calls without the selected response-triggering boundary. Provider-controlled
embedded calls and capability-level external/hybrid tests do not cover it.

Recorded a design-review and implementation breakdown under the milestone's
open caller-publication gate before runtime edits. The design selects bound
human STT as the first room activity source, keeps transcript source independent
of response control, and rejects external/hybrid room selections without a
proven activity source. See `docs/sts-external-room-control.md` for alternatives,
authority requirements, and verification plan.

Focused red: added a compiled-room Morse external test with selected human STT.
After feeding STS PCM and the corresponding human-STT turn, the public caller
pair appears but no reply reaches the sink. From the Call Engine child:
`mix test test/vxpipe/call_engine/room_authority/sts_transcript_modes_test.exs:93 --seed 0`
exits 2, 1 test/1 expected failure, `STS reply did not reach the room sink`.
No runtime behavior has changed yet. Next: review the controller design, wire
only an authorized boundary, and expand lifecycle coverage. Hosted Google and
provider late-evidence gates remain separate.

Ordering dependency found during source inspection: the Speech channel has one
input slot and returns `:busy` for a concurrent activity command. STS ingress
owns a queue and a single outstanding PCM delivery. A room call directly into
`Capability.input_activity/2` can race accepted PCM and silently fail if not
handled; the design now requires a bounded ordered ingress/barrier. Human STT
and STS ingress remain separate lanes without a common frame watermark.

Independent Codex Astra xhigh design review found three additional prerequisites
(not reproduced runtime bug claims): selected STT may be dormant when transcript
demand is false; STT signals carry a transcript interval but no producer-side
STS epoch/audio interval, allowing already-emitted activity to be mislabeled
after hold or audio-only revoke/regrant; and `ResponseOrigins.prepare/1` skips
held/policy checks for descriptors without response-start support. Milestone
tasks and the decision/provider contract now explicitly keep these open.

Second red: compiled-room external and hybrid tests fail 2/2 with no sink
reply. The ingress-ordering contract test fails as expected because
`STSIngress.activity/4` does not yet exist; the child test exits 2, 1/1.
