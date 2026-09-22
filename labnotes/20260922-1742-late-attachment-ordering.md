# Late attachment ordering

Follow-up to e543d969; parent requests bounded diagnosis of the remaining
five-participant late-attachment timeout. No native overlap while the parent's
Gateway root gate runs. Proposal and continuity commits remain unchanged.

Recorded tasks in the milestone before adding tests or changing runtime.
The failing final combined run reached test line 698, waiting for transfer.active,
after both continuous private revisions and returned-listener audio passed.
The same case subsequently passed with diagnostic logging; this is not a repair.

Inspect three boundaries first: room inventory becomes visible before transport
readiness, adopted release captures/holds new output, and fixture sideband waits
consume unrelated messages. Capture an authoritative worker result rather than
inferring cause from the final timeout. Keep existing deadlines and release gates.

Read-only findings:

- The recovery failures earlier in the combined log belong to the two outbound
  phone rooms during cleanup, not the failing WebRTC handoff. They are not causal
  evidence for this timeout.
- HandoffGate.hold calls RoomAudioEgress.OutputGate.change before collecting new
  readiness. OutputGate requires the shared output to be ready. However native
  WebRTC AudioEgress readiness depends on its track/PID, not ICE connection state;
  therefore "transport connecting makes hold fail" is not established by this path.
- A more specific possible race exists around negotiation descriptors:
  ConnectionReadiness.prepare_binding collects transport resources even when the
  transport is preparing; WebRTC Readiness.report includes negotiated codec/track
  configuration in the descriptor. NegotiatedAudio reports no media before
  negotiation. ConnectionReadiness.validate_result rechecks the full binding,
  including negotiation_revision, and returns connection_changed on a concurrent
  negotiation. If negotiation follows capture, Collector correctly rejects the
  changed descriptor as binding_changed. HumanMediaHandoff's adopted preparation
  retries room_changed/stale_candidate/missing connection, not connection_changed
  or binding_changed. This is a candidate ordering race, NOT yet a reproduction.
- The fixture connects the late monitor through an HTTP offer while release is
  already waiting for its room attachment. Attachment precedes negotiation in
  ConnectionSupervisor. The room inventory may therefore expose that connection
  during this interval. Existing snapshots must not be weakened to conceal it.

Next bounded experiment once the parent Gateway gate is terminal: trace sends
from the exact phase PID (not global function tracing), capture only its
vxpipe_transfer_handoff_result stage/result, and correlate that with the captured
late connection negotiation revision and collector failure. Restore tracing in an
after clause. Use one five-participant case, seed 0, two schedulers, no broad loop.
If the result identifies descriptor churn, design a controlled pause at the
attachment/negotiation boundary and an owning-child red before runtime repair.
No new runtime/test change or test run in this inspection checkpoint. No new
architecture permission is currently needed; native verification is deferred only
to honor the explicit no-overlap instruction. Prior continuity review has priority.

Parent released native work after its Gateway lane finished. Review repairs are
now committed as 39f16427 (117 focused engine checks plus seven final review
cases green). Begin the recorded single-case native diagnostic on that checkpoint:
trace only the owning phase's sends during late attachment, summarize stage/result
without dumping prepared graphs, then disable tracing even on assertion failure.

First diagnostic reproduces transfer.active timeout (one test/one failure, 168.6s).
No phase handoff result was traced by the assertion deadline. This does not yet
support a terminal descriptor-rejection diagnosis: distinguish a pending release
from incomplete observation. Next single-case diagnostic adds the already-planned
worker stack/current stage, collector snapshots, progress metadata and late output
generation/held/RTP sequence evidence. No production change or timeout widening.

Second bounded diagnostic: one case passes (166.8s). Exact traced sequence:
preparing/media at elapsed 11570ms, preparing/media at 11790ms, preparing/no
blockers at 11896ms, cue at 11913ms, release ok. Late output was generation 14,
unheld, RTP sequence 14. By the subsequent scope observation the phase had already
completed; no pending-worker/collector state was available. Final conversation
assertions passed. This does not explain the preceding failure or establish the
negotiation hypothesis. No further unmodified retry is justified as repair proof.

Both diagnostic runs used the Gateway child command below, with two schedulers:

```sh
mix test test/vxpipe/gateway/http/human_transfer_webrtc_test.exs \
  --name-pattern 'five-participant handoff retains' --seed 0 --trace
```

Temporary tracing/helpers were removed completely after the two runs. The test
and runtime remain at 39f16427. Both native handles are terminal; parent was told
the Gateway lane is free. Parent independently owns the newly reviewed exact
support-connection-DOWN pre-barrier classification repair; do not duplicate it.

Next controlled experiment design: ConnectionSupervisor starts the connection,
then synchronously binds the claimed Session, then negotiates. A fixture-local
system debug acknowledgement at that exact Session bind call can hold negotiation
while the connection is visible to the room, without pausing RoomAuthority or
changing runtime gates. Observe the handoff worker/collector at that boundary
before releasing the bind, keeping the original deadline. This is not yet built
or verified; coordinate the next native slot with the parent's umbrella lane.

Parent authorizes building the controlled fixture now, without Mix/native
execution while root 69330 is live. Recorded the exact task breakdown first.
Only the HTTP offer runs in a supervised task; client peer ownership stays with
the test. Intercept the exact claimed Session bind call, not a global function or
room process. Observe the release worker receiving a collector report whose
blockers include the late transport, confirm that collector contains the same
pre-negotiation descriptor and the native output is held, then release negotiation.
Trace the phase's terminal result separately so a failure is not misreported as
pending readiness. All diagnostic waits stay bounded and the original handoff
deadline plus existing three-second acceptance assertion remain unchanged.
The fixture is intentionally unverified until the parent releases a native slot;
no runtime changes or claimed repair follow from writing it.

Fixture implementation now exists, unexecuted and uncommitted. The existing
five-participant case gains a controlled_late_attachment tag and uses the owned
Session-bind pause only for its final listener. Other connect calls keep their
ordinary synchronous offer path. Test peer ownership remains in the test process;
only that HTTP offer runs under a named supervised task owner. Scoped traces are
removed in after; the Session bind is released and its debug handler removed in
after. Both acknowledgement waits and the fixture pause are bounded at one second;
neither the handoff deadline nor the acceptance wait is increased. Static diff
inspection/check passes; formatting, compilation and native execution are deferred
to the released slot. A written fixture is not reproduction or repair evidence.

While native execution remains held, parent root 69330 independently reproduces
the same late failure: runtime-integration umbrella log lines 22264-22269 show
test line 698 awaiting transfer.active for 3000ms. This is the post-attachment
boundary, not the earlier returned-listener tone or private revision assertions.
No new run was started. The fixture remains uncommitted; no live handles.

After parent released one controlled case, the first invocation stopped during
compilation: the new helper omitted the plan argument to issue_session/3. Fixed
that fixture-only arity error before starting the actual controlled case. No
runtime ordering evidence or test execution occurred in the compile-failed attempt.

Controlled case handle 85837 is terminal exit 2: one test, one failure, 67 excluded,
166.6 seconds. Command from the Gateway child, with ERL_FLAGS='+S 2:2':

```sh
mix test test/vxpipe/gateway/http/human_transfer_webrtc_test.exs \
  --only controlled_late_attachment --seed 0 --trace
```

The Session-bind boundary was reached, and all pre-negotiation assertions passed:
release worker received the late transport collector report; the same resource was
in the collector; negotiation revision was zero; output was held; the phase worker,
stage, and original absolute deadline were unchanged. Releasing bind allowed the
offer to finish, but the existing 3000ms transfer.active assertion failed. Scoped
phase evidence was exactly `{:release, {:error, :binding_changed}}`; worker stack
lookup returned nil after termination. This distinguishes terminal descriptor
failure from the earlier no-terminal-result observation. The run log's failure
excerpt is lines 297-304 of the controlled-session-bind-red2 log.

No production change, green claim, or further native execution. The parent was
notified that the handle is terminal and the native lane is free. The one-case
authorization is consumed. This is the controlled red for the negotiation race;
the fixture is still uncommitted pending a coherent verified repair. Source review
confirms HumanMediaHandoff retries stale_candidate/room_changed on the closed side
of adopted release, but descriptor failure escapes. Before implementation, the
milestone now records tracing the precise preparation/collector ownership path,
safe fresh recapture and cleanup, owning-child coverage, and coordinated green.

Parent authorized the narrow production repair plus owning-child RGR, holding
native green for a separate slot. Design review: use existing authoritative
Preparation.run and Collector.reconcile only on the adopted, closed-gate path.
Reconciliation cancels the old probe batch, fences old replies by batch identity,
removes old descriptor monitors and requires fresh evidence for replaced bindings.
Unchanged bindings retain evidence. Reject simply clearing collector failure or
accepting a mismatched report; do not retry any post-release failure. No new
registry, policy transition change or normative ownership architecture is needed.

Owning-child regression extends the existing deferred-adoption cue-barrier test
with adopt_binding_change. While adoption is acknowledged as pending, renew the
caller transport descriptor without changing policy, then resume adoption. Require
a new drained cue, original deadline, retained connection actors and speech provider,
and successful activation. Existing connection_generation partial-release test
remains the countercase: after any release starts, the same change closes the room.

RED (unmodified production): one test, one failure, 20.7s; the room exits with
handoff_release_failed rather than reaching the fresh cue barrier. GREEN after the
small HumanMediaHandoff change: one test, zero failures, 23.8s. Both commands run
from the Call Engine child with ERL_FLAGS='+S 2:2':

```sh
mix test test/vxpipe/call_engine/human_web_transfer_room_test.exs \
  --only outcome:adopt_binding_change --seed 0
```

The production change recaptures/reconciles before restarting adopted release
preparation on binding_changed, and handles the same mismatch while the adopted
preparation collector is waiting. Pre-adoption and post-release failure handling
are unchanged. Formatting passes. A bounded room/collector/barrier regression group
is running; native green remains held. The Gateway fixture observes actual owner
messages and actual descriptor/hold state, does not inject successful readiness,
and leaves the existing final audio/conversation assertions intact.

Bounded regression handle 59516 is terminal exit 0: 66 tests, zero failures,
55.6s. Same owning child and two-scheduler environment, command:

```sh
mix test test/vxpipe/call_engine/human_web_transfer_room_test.exs \
  test/vxpipe/call_engine/readiness/collector_test.exs \
  test/vxpipe/call_engine/readiness/barrier_test.exs --seed 0
```

This includes all existing partial-release fatal outcomes, real deadline expiry,
cue loss, relevant/unrelated policy refresh and collector stale-evidence checks.
No Gateway/native run followed the controlled red. Native green is the remaining
verification gate and must use a parent-released slot, not an unmodified retry.

Final static checks: umbrella formatting check passes; strict Credo checks 1076
files with no issues; git diff --check passes. No full umbrella suite was run.

Parent released the controlled native green at committed checkpoint 1e3d114f.
Handle 57827 is terminal exit 2: one test, one failure, 67 excluded, 164.0s.
The exact controlled command above ran with two schedulers and unchanged fixture
and deadlines. Failure differs from the causal red: await_bound_listener/4 rejects
a collector report with failure binding_changed before releasing Session bind.
It has not yet established the required late-listener acknowledgement. Phase
evidence reports no_terminal_result_observed, and the worker stack is actively in
Preparation.run -> prepare_current_graph -> refresh_preparation ->
validate_adopted_release. The log is controlled-session-bind-green, failure lines
153-166. Do not describe this run as green or as another terminal handoff failure.

This exposes fixture overconstraint: a failed descriptor report is not a terminal
phase result now that the closed-gate owner can recapture it. The fixture already
observes actual phase terminal results separately, but rejects every failed
collector notification before selecting the late-listener descriptor. Recorded
the task to require current acknowledged late evidence without conflating these
two lifetimes, retaining the original bounded pause and terminal-phase detection.
No fixture/production changes or rerun in this evidence checkpoint. Parent notified
that the native handle is terminal and the lane is free. Independent review of
1e3d114f remains in progress; native acceptance remains open.

Parent approves the recorded fixture-only correction and one controlled native
verification after commit. The fixture now captures the actual pre-negotiation
late resource before waiting; accepts an acknowledgement only when the traced
preparing report equals the collector's current published snapshot, contains the
late blocker, and its current barrier contains that exact preparing descriptor.
Only binding_changed failed-descriptor notifications may be superseded during
recapture; other failures and phase terminal results still fail immediately.
Every receive-loop iteration checks the original bounded deadline, so persistent
failure cannot evade expiry through repeated notifications. Existing revision-zero,
held output, same worker/stage/deadline and three-second activation checks remain.
Production is unchanged. This does not identify the cause of all prior timeouts.

Fixture static verification: formatting and diff checks pass; strict Credo checks
1076 files with no issues. Commit precedes the single authorized native run.

Fixture correction committed as ebc8287f. The one authorized controlled native
verification is terminal: handle 96667, exit 0, one test, zero failures, 67 excluded,
169.8s. Log: controlled-session-bind-current-green. Gateway child command:

```sh
ERL_FLAGS='+S 2:2' mix test \
  test/vxpipe/gateway/http/human_transfer_webrtc_test.exs \
  --only controlled_late_attachment --seed 0 --trace
```

The current acknowledged late descriptor, preparing collector entry, negotiation
revision zero, held output and same worker/stage/deadline checks all pass. The
original one-second Session pause and three-second activation assertion are
unchanged. Transfer progress, final cue/audio and conversation assertions pass.
No runtime changes after 1e3d114f; this completes native green for that controlled
binding_changed reproduction with the corrected fixture. It does not establish
that all earlier no-terminal-result timeouts share this cause. Parent notified
immediately that no native handle remains live; serial integrated root acceptance
remains parent-owned. No unmodified retries or full umbrella run were performed.
