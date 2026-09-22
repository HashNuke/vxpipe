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
