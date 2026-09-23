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

Ingress-to-capability PCM cutover red: a focused STT capability test captured
the actual `Media.Ingress` delivery envelope before selected audio-route loss,
replaced the STT provider while transcripts still demanded recognition, then
delivered that old envelope. The old PCM reached the replacement provider
(focused 1/1 expected failure). The provisional interval proof now captures
the ingress policy's STT, source audio-input and source audio-output intervals
with each asynchronous envelope; the capability compares them to its current
snapshot before provider delivery and acknowledges stale work as policy-denied.
The test also verifies a fresh envelope in the new interval still reaches the
provider. The adjacent ingress/capability/room group passes 57/0 (seed 0).
This is policy-interval proof only: allocation-generation qualification,
pre-reopen frame cutoffs, coordinated hold and frozen STT signal provenance
remain open. Astra xhigh review of this scoped change is pending.

The scoped Astra xhigh review reproduced an integration-test mismatch:
`apps/vxpipe_gateway/test/vxpipe/gateway/media/sts_input_test.exs` still
expected the four-field STT audio envelope. A parent rerun confirmed four
failures in 11 tests before changing the assertions. The three Gateway
patterns now account for the interval field, including the negative
credit-isolation assertion; the 11-test file passes with seed 0. The Call
Engine ingress/capability/room group passes 57/0 on seeds 0 and 1. The
reviewer separately ran 37 tests and seven in-memory probes of missing,
malformed and stale proof, both enforcer orders, route directions and fresh
delivery without reproducing a runtime bypass. Gateway also passes 11/0 on
seed 1. Astra xhigh re-reviewed the Gateway repair and cleared the scoped
change with no remaining reproduced actionable issue: Gateway 11/0 and STT
ingress/capability 30/0, both seed 0. The parent generation/hold cutoff
remains open.

Producer-side signal provenance red: a selected activity STT emitted a
`turn_started` signal without its native allocation generation, turn reference
or source audio intervals (focused 1/1 expected KeyError). The scoped change
copies `Speech.Event` generation/turn reference and current source audio
intervals into the private signal immediately after native event acknowledgement.
The focused test now passes and checks matching start/transcript/end origin,
unchanged origin through an unrelated membership revision, a fresh generation
after audio-only revoke/regrant, and unchanged captured old evidence. The
adjacent ingress/capability/room group passes 58/0 on seeds 0 and 1. Astra
xhigh scoped review is pending. This is not the STS epoch binding, native PCM
cutover or room-control acceptance.

Astra xhigh reviewed the metadata slice with 23 passing focused tests and
five in-memory probes. It reproduced one important limit: suspend the STT
capability, enqueue a recording-only policy change, then emit a native end
from the still-live provider before resuming. The native end remained on the
old allocation, but capability-emission stamping assigned the new audio-input
interval. This is not true audio-origin proof. The issue was recorded in the
milestone before the follow-up behavior change. A focused owning test repeated
the exact queued-native-event sequence and failed 1/1: no replacement started,
and the old end was published under input interval 1. The shared selected-
activity authority check now also compares scoped source audio-input/output
intervals, so recording-only changes retire the old provider and discard its
queued event. The focused test passes and the adjacent 61-test demand/ingress/
capability/room group passes on seeds 0 and 1. This intentionally supersedes
the earlier recording-only no-restart expectation for selected activity STT;
non-selected STT behavior is unchanged. Independent review of this follow-up
found no remaining reproduced actionable defect. Astra xhigh ran 76 tests
and 15 in-memory probes (seed 0) covering both policy-enforcer orders,
prepared recording-policy replacement/rebase/adoption, intervening interval
invalidation, ingress queue clearing, stale envelopes/acknowledgements and
legacy non-selected behavior. It did not claim native PCM generation/cutoff,
checked retirement, hold or room-control acceptance.

Morse external hold consequence red: a real external `:started` boundary and
encoded `HI` PCM left provider input pending; capability hold/release blocked
the old end while held but did not retire provider-side activity. An `:ended`
boundary after release emitted `{:test_audio_output_finish, sink, turn}` for
the old reply (focused 1/1 expected failure). This is a caller-visible leak,
not merely `external_started?` introspection. The milestone records an
acknowledged cancel-or-fail requirement before implementation. Astra xhigh
design review found that resetting Morse fields alone is insufficient because
a native end may already be queued. It recommended the smaller interim safety
contract: close admission, fence playback, then retire a dirty external/hybrid
STS allocation unless both provider quiescence and native-event retirement
are proven. An accepted end does not by itself clear dirtiness; idle Google
reuse needs more than no active output. Reusable cancellation requires an
acknowledged provider discard and native-event barrier as a later gate. No
implementation or green hold claim exists yet.

Fail-closed hold red/green: focused Morse external, Morse hybrid PCM-only and
Google fake-wire active-external tests each failed because `hold/1` still
returned `:ok`, then passed after a bounded provider-plus-channel quiescence
check. The owning capability holds STS ingress and fences output first; the
provider reports whether it can emit future old-input evidence; the native
channel independently requires no awaiting/pending event or input command.
Any missing/negative proof stops the capability as `:unsafe_hold`, so release
cannot replay old input. Morse's public provider wrapper now delegates its
native quiescence check; Google uses its existing settled-idle resumption
predicate. A synthetic context probe reports quiescence only when it has no
autonomous held command, preserving origin-fence tests without pretending
real active audio is safe. A focused suspended-capability test confirms an
unacknowledged native input event overrides that provider's idle claim. The
seven-file STS capability/ingress/room-adjacent group initially passed 203/0
on seeds 0 and 1. Astra xhigh review then reproduced two failures: text-tool
completion cleared a buffered hybrid PCM decoder's `input_dirty?`, allowing
hold/release to replay old audio, and a fully settled Morse output record
remained in `output`, rejecting otherwise safe idle hold. Two focused tests
failed 2/2 for those reasons. Text completion now leaves audio decoder,
input-turn and dirtiness state untouched; only audio completion retires those
fields. Morse retires a completed output only on the matching turn/output
settlement notice, including a test that a wrong output reference does not
retire it. A bound-ingress test also queues an external end behind hold and
confirms the dirty capability closes before a new epoch can release. The
nine-file adjacent group passes 213/0 on seeds 0 and 1. Astra xhigh re-review
cleared both Morse fixes but reproduced the response-capacity test's
hold-before-ack race: one focused run failed because the newly correct native
idle gate rejected hold while 16 response events were still being delivered.
The test now synchronizes Channel and Capability after each native event and
asserts all 16 responses are pending before expecting hold to retire them.
The original focused test failed immediately; the test-only repair passed 30
repetitions on seed 0 and 50 on seed 1, and the nine-file group again passed
213/0 on both seeds. Astra xhigh cleared the scoped hold and capacity-test
changes (21/0 additional checks, including forced backlog). Its separate
broader-file run saw `EXIT killed` in an unchanged overflow test; I could not
reproduce that with 20 focused repetitions or full-file seeds 0 and 1. My
repeated full-file run did reproduce a different old test-ordering assertion:
the queued-response retry test inspected two pending turns before the third
native event had been acknowledged. A test-only two-event Channel/Capability
barrier now passes 100 focused repetitions and 20 full-file repetitions on
seed 1. Astra xhigh forced-backlog review cleared that test-only barrier.

The reviewer's `EXIT killed` later recurred in a concurrent nine-file run:
the test synchronously called a probe on the same tree it intentionally
stopped at caller-overflow, so it sometimes died before replying. The test
now sends the emit request without awaiting that doomed reply and still
requires `:pending_caller_overflow`, no rejected caller event forwarded to
the room owner, and the monitored capability DOWN. A separate nine-file run
missed the STS session helper's `:ready` event at ExUnit's 100-ms default;
`Session.start/2` allows 5 seconds, so the helper's exact-session/owner ready
assertions now use that existing bounded startup budget. No runtime timeout
changed. The nine-file group passes 213/0 on seeds 0 and 1 after both test
changes, and Astra xhigh cleared their scoped review, including simulated
suppressed terminal probe replies. Active-turn reuse, hosted Google, full
room lifecycle and final gates remain open.

Post-commit `a540af9c` gates: root format, warnings-as-errors compile and
unused-lock checks pass. Strict Credo reports two project-owned size failures:
Channel 803 lines and Google STS session 805 versus an 800-line limit. Root
`mix test` stops before the Persistence suite because local PostgreSQL SCRAM
has no password configured; this is not a passing umbrella test gate. A
separate mechanical repair moves the new Channel input-idle predicate into
STSInput and Google's bounded reusable-input predicate into STSResumption.
Channel is now 798 lines, Google STS session 799, and the ten-file adjacent
group including Google fake-wire provider tests passes 251/0 on seeds 0 and 1.
Astra xhigh cleared the predicate move after 175 scoped checks on both seeds,
including equivalence probes. Post-commit `816fba9a` root format,
warnings-as-errors compile, strict Credo (1,095 source files, no issues) and
unused-lock checks pass. Root `mix test` still stops before Persistence at
the same local PostgreSQL SCRAM password configuration, not a passing suite.
The two deliberately red compiled-room external/hybrid tests remain outside
this checkpoint.

The next room-control prerequisite is a bounded current-origin input-binding
query on selected STT. A focused red failed because `activity_origin` was
absent; the capability now exposes its ready native allocation generation,
source audio-input/output intervals and selected agent only while activity
is demanded. An unrelated policy rebase retains the origin; audio-route
denial removes it; regrant creates a new generation/interval. A ready
transcript-only recognizer has no origin. The four-file adjacent group passed
63/0 on seeds 0 and 1 before the review follow-ups below.

Astra xhigh reproduced two scoped query defects: a ready prepared replacement
advertised its candidate generation before adoption, and a canceled native
allocation remained visible while capability closure was delayed. I added
the prepared regression to the existing policy-preparation test and confirmed
it failed on the candidate generation, then cleared `activity_origin` only
for pending preparation; an adopted resource still exposes the current
generation. The cancellation regression suspends ScopeControl, disconnects
the fake transport, waits for native Channel DOWN and confirms the allocation
token is invalid before querying. It failed with the canceled generation,
then passed after the query checked `Allocation.valid?/1`. Neither case is
yet room acceptance or ingress PCM cutover. The prepared-adoption check passes;
the four-file adjacent group passes 64/0 on seeds 0 and 1. Astra xhigh scoped
re-review found no remaining concrete defect after 71/0 checks on both seeds
and seven in-memory probes, including prepared/adopted and canceled query
forms. This clearance does not cover PCM cutover, hold or room control.

Commit `711b863d` contains this query checkpoint and its tests/docs. Post-commit
root format, warnings-as-errors compile, strict Credo (1,095 files, no issues)
and unused-lock checks pass. Root `mix test` again stops before the Persistence
suite because PostgreSQL SCRAM requires a local password that is not configured;
do not count this as a passing umbrella test gate. The intentionally red
compiled-room external/hybrid tests remain unstaged for the next slice.

Next design/red checkpoint: the two compiled-room external/hybrid focused
tests still fail 2/2 because selected human-STT end does not deliver a reply
to the STS room sink. Before room wiring, I added a focused selected-STT PCM
test requiring native allocation generation on an otherwise current-interval
envelope. It failed 1/1: capability acknowledged `:ok` and the fake provider
received the payload. This test is deliberately uncommitted/red pending the
matching ingress-admission implementation.

Astra xhigh read-only cutover review reproduced a separate old-frame relabel:
a delayed frame with its pre-replacement origin was rejected, but querying
origin after replacement labeled that same old frame with the new generation
and intervals and allowed delivery. The design therefore uses room-owned
close/retire/readiness/open acknowledgement, explicit admission installed in
ingress, immutable admission captured at enqueue, capability generation check,
and an upstream received-before-open fence. Per-frame origin queries are not
cutover proof and can block a media caller. This design review is separate
from implementation acceptance; both enforcer orders and hold/reopen remain
unproven.

Generation-bound PCM checkpoint in progress: focused capability red accepted
selected activity audio with current policy intervals but no native generation
and forwarded it to the fake provider. A focused ingress red dispatched selected
audio before any origin was bound. Capability now requires an exact valid native
allocation generation for selected activity while preserving transcript-only
envelopes. RoomAuthority synchronizes the selected STT capability's current
origin to ingress at connection binding, connected notification and STS input
readiness; ingress freezes origin plus intervals when enqueueing and stays
closed without an origin. A policy change preserves only an origin whose
source audio intervals and selected native-audio demand remain current. The
four-file Call Engine adjacent group passes 66/0 on seeds 0 and 1;
provider-controlled compiled-room modes pass 4/0, and Gateway's STS input
file passes 11/0. The
external/hybrid compiled-room tests still fail 2/2 at missing STT→STS turn
control. Initial scoped review findings are below; no hold/reopen or
source-time fence is claimed.

Readiness follow-up: selected ingress reported `:ready` while origin was
unbound and `push` silently stayed closed. A focused red proved that mismatch;
readiness and admission now share the same native-audio-origin policy check.
The focused test passes and compiled external/hybrid calls still reach their
original missing-reply assertion, so this did not create a startup deadlock in
that path. The five-file adjacent group passed 92/0 on seed 1. A concurrent
seed-0 group run hit the existing test helper's default 100-ms fake transport
start assertion while another Mix process held the build lock; the isolated
test passed on seed 0. The later uncontended owner groups below pass on seeds
0 and 1; the exact five-file seed-0 command was not repeated.

Scoped Astra xhigh review reproduced two remaining P2 gaps: ingress readiness
could stay `:ready` with a stale bound native generation after same-interval
replacement, and conflating native PCM demand with STS activity demand stopped
selected-STT transcription after agent-to-human route denial. Before repair,
focused reds failed at the intended assertions: stale origin reported `:ready`,
and the current STT binding lacked an `audio_origin` despite continued transcript
demand. The implementation now exposes distinct `audio_origin` and
`activity_origin` (the latter stays nil without bidirectional authority), binds
the former to ingress, and compares its generation to the current provider
binding during readiness observation. Both focused reds pass; an additional
actual same-interval replacement test passes before and after rebinding. The
adjacent ingress/capability/readiness/room-identity group passes 76/0 on seed
0 and seed 1. Another media-policy/room/STT-ingress group passes 46/0 on seed
0. The combined group including compiled-room external/hybrid tests passes
73/75; those same two pre-existing red room tests still stop at missing STS
reply. Scoped Astra xhigh re-review found no reproduced actionable defect
after 47 focused tests/probes and eight edge checks, including route direction,
enforcer order, malformed proof, prepared-origin privacy and stale
acknowledgements.
Full hold/reopen source-time fencing remains open.

Post-commit `a50b78bc` umbrella checks: `mix format --check-formatted`,
`mix compile --warnings-as-errors`, `mix credo --strict` (1,097 files, no
issues), and `mix deps.unlock --check-unused` all exit 0. Root `mix test`
stops before tests while creating the Persistence test database: local
PostgreSQL SCRAM authentication has no configured password. No credential was
added or logged. The two external/hybrid compiled-room tests remain separate
deliberate reds, unstaged from this checkpoint.

Next ingress-cutover primitive (uncommitted): focused red for missing
`Ingress.close/1` failed at the undefined function; a second red reproduced
pre-binding source audio being accepted with a newly bound generation. Ingress
now clears selected origin, queued PCM and in-flight credit on close, sets an
inclusive monotonic-ms receive-time cutoff on fresh origin binding or explicit
reopen, and rejects older/equal `AudioFrame.received_at` before queueing.
Repeated `open/1` while already open preserves the cutoff; a stale pre-close
acknowledgement cannot release new in-flight credit. The Call Engine
ingress/capability/readiness group passes 68/0 on seeds 0 and 1; room STS call
and ingress tests pass 24/0 on seed 0; Gateway STS input passes 11/0 on seed 0.
WebRTC and telephony Gateway paths preserve `received_at` after frame
construction; Gateway room-audio ingress already uses the same inclusive
cutoff convention. Astra xhigh scoped review cleared the ingress primitive
after 43 focused tests, four probes and 18 Gateway checks. It separately
reproduced the upstream limitation: suspend a callback-delegating process,
queue raw WebRTC/telephony media before reopen, close/rebind/open ingress,
then resume the process. Both handlers assign `received_at` after the cutoff
and dispatch the old payload; supplying its original timestamp instead causes
`{:error, :stale_frame}`. This is not room-coordinated hold/release admission
or complete producer provenance. The Gateway source-time fence is now an
explicit unchecked subtask in the milestone, not a regression attributed to
the ingress primitive.

Post-commit `05b02718` root format, warnings-as-errors compile, strict Credo
(1,097 files, no issues) and unused-dependency checks exit 0. Root `mix test`
again stops before tests while creating the Persistence test database because
local PostgreSQL SCRAM has no configured password. No credential was changed.
