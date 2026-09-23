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

Ordered-control prerequisite: added `STSIngress.activity/4` with a bounded
single-credit queue shared with PCM. It carries the supplied room epoch and scoped
caller input/output audio intervals, preserves valid controls across unrelated
transcript policy changes, retires queued controls on hold/revocation, and
counts only audio in dropped-frame metrics. A rejected delivered control ends
the ingress, whose monitored owner then fails closed. Capability delivery now
rechecks bound ingress, epoch, snapshot, presence and both audio routes even
for Morse descriptors without response-start context. Direct activity also
rejects hold and egress denial. The direct hold test first failed with `:ok`
instead of `{:error, :held}` and now passes.

Current focused evidence: Call Engine ingress/capability/origins group passes
80/0 (seed 0) before the final direct-activity additions; the complete
capability file then passes 42/0. Child warnings-as-errors compile passes.
Independent code review is pending. This does not yet select/demand human STT,
stamp STT producer provenance, or wire room activity. The compiled-room reds
therefore remain expected and are not part of this prerequisite's green claim.

The direct hold red was accompanied by a direct egress-denial regression; both
now pass. After moving the cohesive activity submission path into
`Capability.SpeechToSpeech.Input` to retain the strict module-size boundary,
the ingress/capability/origins group passes 82/0 (seed 0). The capability file
is 781 lines, below the strict 800-line limit. Runtime code review is still
pending; no broader acceptance claim yet.

While proving bound-ingress delivery, inspection of Morse's provider state
after `SpeechToSpeech.hold/1` showed `external_started?` still true. This is a
reproducible internal observation, not yet proof of a user-visible wrong reply.
The milestone now asks for a public consequence test and a provider-side
retirement decision before any hold/release acceptance claim.

Independent Astra xhigh code review reproduced four issues in the provisional
ordered seam: hold/in-flight activity rejection terminates the ingress and
capability; direct capability activity bypasses bound ingress ordering; a nil
ingress envelope reaches `send(nil, ...)`; and a malformed internal activity
call reaches map field access. The milestone records each before fixes. Their
focused reds and repair evidence follow in this labnote.

Reproduced all four locally before changing handlers: malformed internal
activity raised `KeyError` in `STSIngress.current_activity_intervals?/2`;
direct activity returned `:ok` with a bound, suspended ingress; a nil ingress
activity envelope raised `send(nil, ...)` in the capability; and hold queued
before activity caused `SpeechToSpeech.release/2` to return `{:error,
:unavailable}` after ingress/capability termination. The four focused tests
failed 1/1 and 3/3 respectively. The repair validates internal payload shape,
blocks direct activity when an ingress owns input, guards the reply destination,
and treats an activity rejection as benign only after its exact epoch/interval/
route authority was retired. A rejection while current still fails closed.
Four focused tests now pass 4/0; the ingress/capability/origins group passes
86/0 (seed 0). A second independent review of the updated diff is pending.

Second Astra xhigh pass cleared the original four but reproduced a capability-
first policy-revocation ordering race. A queued control rejected by the
capability's newer snapshot arrives at an ingress still on the old policy, so
`current_activity?/2` treats it as a fatal current rejection. The milestone
records this before a focused red/fix. Reviewer saw one origins-test failure
in a broad 86-test run that passed on isolated same-seed rerun; attribution is
not established and it is not counted as a finding for this change.

Formal capability-first revocation red: suspend the capability, queue external
start/end in the ingress, then apply output-denial revision 1 to the capability
before ingress receives it. After resuming and draining the acknowledged first
control, `:sys.get_state(ingress)` exits `:activity_rejected` (focused 1/1
failure). The capability now includes its applied policy revision on stale/
denied activity acknowledgements. The ingress treats an error as retired when
its own authority already retired the control or the capability has a strictly
newer policy; same-revision current rejection still terminates the input owner.
The focused red is green, the owning group passes 87/0 (seed 0), and child
warnings-as-errors compile passes. Final review is pending.

Next prerequisite traced without edits: `Readiness.Inventory.connection_demands/4`
uses `SpeechToTextDemand.required?/2` to omit selected STT when there is no
transcript demand. `Capability.SpeechToText.State.initial_demand/2` and
`demanded?/2`, plus `Media.Ingress` policy handling, use the same transcript-only
predicate. `PlanStartup.connection_speech_to_text/3` builds a
`SpeechToTextRuntime` which `RoomSupervisor` passes to
`RoomCapabilitySupervisor.start_speech_to_text/7`. An explicit controller-agent
identity needs to flow through these boundaries so readiness, provider session
and ingress agree; changing only the inventory would advertise a dormant
recognizer as ready. This remains an open next checkpoint, not part of the
ordered-control commit.

Final scoped Astra xhigh review found no remaining concrete defect in the
ordered ingress/capability seam after eight in-memory probes. The owning
ingress/capability/origins group passed 87/0 with seeds 0 and 1. The milestone
now marks only this prerequisite complete; room wiring, STT activity demand,
producer provenance, and provider hold retirement remain open.

Post-commit root `mix credo --strict` found `validate_activity/5` complexity 21
against limit 20. Recorded a milestone cleanup task, split participant-presence
and bidirectional-route predicates without changing check order or error
results, then reran the owning 87 tests (seed 0, 0 failures) and root Credo
(no issues). This is a follow-up checkpoint to `a224ccfe`.

Selected-STT demand checkpoint: readiness inventory first failed a focused
external-STS/no-transcript assertion (25 tests, one expected failure). The
entry receiver is the only agent eligible for the current room STS allocation;
the first test revision accidentally selected a different agent and was fixed
before implementation proof. `SpeechToTextActivitySource` now extracts the
entry caller/receiver external or hybrid selection. Shared demand also requires
both participants present and bidirectional audio permission. The agent id is
carried in `SpeechToTextRuntime` through room startup to capability and ingress;
the readiness inventory and private transfer use the same rule. Capability
policy preparation and ingress compare demand changes in addition to the STT
transcript interval, so audio-only revoke/regrant retires and restarts the
recognizer. The 87-test demand/capability/ingress/inventory/plan/room group
passes with seed 0. Room controller retirement when demand vanishes, producer
signal provenance, and provider hold state remain open. Independent code
review is pending; no root-gate or commit claim yet.

Astra xhigh reproduced a prepared-policy race the first local group did not
cover. Its method was a bounded in-memory ExUnit probe: load the existing STT
capability test fixture with `MIX_ENV=test mix run --no-compile -e`, inject one
temporary test into the source string, and run only that test without editing
files. The probe prepared activity-only STT while the selected agent was
prospective, applied a restrictive audio-only policy revision that left the
STT transcript interval unchanged, then refreshed the candidate. The old
prepared transport remained and refresh returned `:preparation_conflict`.
For future teammate cycles, turn such a probe into an owning focused test,
record its expected red, then repair and rerun the relevant group. Here the
formal STT capability test failed 1/1 on that exact conflict. The repair
invalidates a pending preparation if the selected agent's presence or either
direction of its audio route changes, while preserving unrelated membership
rebasing; the focused test passes and the six-file group passes 88/0, seed 0.
Independent Astra xhigh re-review found no remaining reproduced defect: the
original provider retires, refresh succeeds, regrant starts a new session,
unrelated membership/recording changes retain token/generation/readiness, and
transfer refresh avoids the old conflict. The six-file group passes 88/0 on
seeds 0 and 1. The broader room-controller, provenance and hold gates remain
open.

Producer-provenance research for the next checkpoint: `SpeechToText.handle_signal/2`
currently sets only the STT transcript `policy_revision` on the outgoing
`Signal`, then sends it asynchronously to the room. `State.event/2` rejects
events from a closed/stale semantic session, but the STS input epoch is owned
by `RoomAuthority.SpeechToSpeech` and is not present in the signal. Audio-only
route revoke/regrant can leave STT running when transcript demand remains;
therefore stamping audio intervals on a late event alone would not prove the
audio that caused it was admitted in that interval. The milestone now splits
this open prerequisite into producer stamping, session/ingress fencing on
audio-authority change, and hold/release lifecycle coordination. This is a
design investigation, not implementation or acceptance evidence.

Astra xhigh read-only provenance design review found that native STT events
already carry allocation generation and turn reference but `Signal` drops them.
It also traced the ingress-to-capability PCM envelope: it has no allocation
generation, so an already-sent old frame can reach a new provider after queue
clear. The reviewer did not run tests; these are source-backed design gaps,
not independently reproduced runtime defect claims. The chosen candidate is
an immutable activity binding per native allocation, acknowledged ingress
cutover, checked provider retirement before new control input, and exact room
matching; see `docs/sts-activity-provenance.md` for tradeoffs and gates.

Focused provider-retention red: with selected activity STT and transcript
retention still on, an audio-only route denial left the old STT provider alive
and started no replacement (one test, one expected failure). The scoped change
uses the selected source/agent presence and two route decisions—not a global
policy revision—to trigger live-session replacement, prepared-policy
replacement and ingress queue reset. The focused test and the adjacent 83-test
STT/demand/ingress/readiness/room group pass (seed 0). This is not evidence for
late-signal isolation, in-flight PCM fencing or hold/release safety; those
remain open.

Astra xhigh scoped code review of the route-reset diff found no concrete
regression: 39 tests passed with seed 0 and eight additional in-memory probes
covered both route directions, provider termination, unrelated policy rebase,
prepared adoption and ingress queue clearing. The owning capability test also
proves an unrelated recording-only revision does not restart the selected
recognizer. This review explicitly did not claim generation-qualified PCM,
emitted-signal provenance or hold safety.
