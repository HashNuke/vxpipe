# Diagnostic settings transitions

## Audit and remaining integration gap

Audited milestone C's capture-authority transitions against the room-service path.
The existing configured report-storage failure cases affect the latency repository,
not the installation settings reader. Component tests already injected unavailable
settings reads, but they did not compose the real settings adapter with a configured
call. Added two acceptance cases, local operational Silero off/on, to close that gap.
No production code changed.

Each case persists a turn, retains the input handoff and monitors its worker,
then removes the installation settings row inside the test sandbox. The real
`DiagnosticsSettingsStore.snapshot/0` returns unavailable; no invalidation hint is
sent, so ordinary polling must discover it. The old worker exits, capture is
revoked and diagnostic capacity drains before another turn is sent. That turn's
provider PCM, operational inference (when enabled), transcription and response
continue, with no diagnostic row.

Restoring the same enabled row/revision allows normal polling/reconciliation to
start a new run and capture epoch. The old handoff remains revoked. After room
teardown the stored set contains exactly the pre-error and recovered turns; the
intermediate turn is absent. The interrupted run remains incomplete with
`lease_expired`. Final duplicate/control/resource assertions run after drain.

This is a real settings-store unavailable result, not a physical PostgreSQL
partition or a global stop acknowledgement. The optional report writer remains
independent and can finish historical evidence. No provider network connection,
Telnyx change or deployed installation mutation is used.

## Contract-to-evidence audit

| Requirement | Evidence and boundary |
| --- | --- |
| Active/new calls off/on and re-enable | Configured four-mode cases and repeated 20-cycle cases per local VAD mode. Off has no worker/run; re-enable starts a fresh run; existing operational Silero continues. |
| Unknown, stale, malformed or conflicting settings | SettingsLease and SettingsProjection tests deny new grants and invalidate stale authority; newer disable cannot be reversed by an older reply. |
| Read failure and recovery | New configured real-store cases plus projection tests for timeout, failed read and same-revision recovery. |
| Reader/projection restart | Fresh read required; old queued capture cannot revive at the same revision. Room-service restart separately reconciles source ownership. |
| Disconnected/stalled worker | SettingsPeer uses two real BEAM VMs with controlled independent clock origins; a worker missing the invalidation hint and unable to refresh expires locally. This models lost refresh/hints, not real network propagation time. Source-port loss tests retire observation while speech continues. |
| No call/environment override of off | Runtime config provides the snapshot loader and resource plumbing, not an enable knob. RoomSupervisor validates its supported options; RoomService requires SettingsProjection.grant and handoff admission/consumption recheck it. Configured local VAD on with collection off still creates no diagnostics. |
| Queued audio and historical summaries | Projection restart/recovery and Collector revocation tests reject stale queued evidence. Configured lifecycle cases reread only the enabled turns after complete teardown; the new cases preserve the pre-error turn while excluding the unavailable period. |
| Partial evidence remains explicit | LiveReport tests distinguish absent, pending and incomplete acoustic coverage and retain partial-start/reset/gap evidence. Coverage tests limit completeness to the selected capture window, never the whole call. |

This audit concerns local capture authority and its composed room/persistence path.
It does not prove global effective-disable status: that remains a separate unchecked
milestone task, including its unresolved clock-progress assumption.

## Verification

- Engine settings lease/projection/peer, room service, live report and capture
  handoff selection: 85/85 pass, seed 687220, 6.3 seconds.
- Calls collector, attachment and coverage selection: 25/25 pass, seed 108899.
- New configured cases: 2/2 pass, seed 420707, 16.7 seconds. They test existing
  behavior and needed no implementation change or initial runtime red test.
- Final combined four-mode plus settings-unavailable configured selection: 6/6
  pass, seed 639291, 26.6 seconds.
- Root format, warnings-as-errors compile, strict Credo and unused-lock checks
  pass. Independent Astra xhigh final review is clean, including this audit;
  its two new configured cases pass 2/2, seed 358317, 16.2 seconds.

Full-suite, performance, acoustic accuracy, global effective-status and live
acceptance remain separate. No full suite or deployment is claimed here.
