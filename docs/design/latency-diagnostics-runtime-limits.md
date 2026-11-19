# Passive diagnostics runtime limits

> Architecture revision, 2026-11-19: [participant-owned room service](participant-vad-room-service.md)
> supersedes agent-selected discovery/ownership. The room-service cutover is
> implemented; performance and live acceptance remain open. See the
> [milestone](../../labnotes/milestones/passive-call-latency-diagnostics.md) for current acceptance.

These are implemented defaults and authority rules, not measured capacity or an
accuracy claim. The [milestone](../../labnotes/milestones/passive-call-latency-diagnostics.md)
tracks the remaining load, accuracy, effective-status UI and live acceptance gates.

## Settings authority across workers

Each worker reads the durable, versioned installation setting through an isolated
reader and local projection. A successful enabled read grants authority for at most
3,000 ms **from the read's local monotonic start**, not from response arrival.
Workers never compare monotonic timestamps from different VMs.

The projection polls every 1,000 ms with one outstanding read. Responses taking
1,000 ms or more are discarded. A blocked read retains that single slot; it cannot
create an expanding set of replacement reads. Unknown settings, read failure,
revision conflict and expiry deny capture. Older revisions cannot restore enabled
authority. A new enabled revision can start a fresh observation epoch.

Invalidation is a coalesced local hint, not a claim that every worker received a
broadcast. Other workers observe the durable setting through polling. If a worker
misses a hint or cannot refresh, its previous enable expires at its own deadline.
A suspended projection does not prevent direct grant readers from observing expiry.
An API write alone therefore cannot truthfully report an immediate distributed stop.
The UI must retain applying/unknown until acknowledgements or a valid expiry proof
establish the requested effective state; that integration remains open.

Capture checks authority before admission and again before consuming work/results.
Source workers check their grant every 250 ms for cleanup. The three-second lease
bounds valid authority, not hard real-time scheduling or native thread termination.
A stalled process/projection may delay cleanup but cannot accept expired work on
resuming while its underlying monotonic clock continues advancing. Host suspension
is subject to the clock-progress caveat below. Historical
summaries may finish their separately bounded persistence drain after capture stops.

Rejected alternatives are unbounded retries, wall-clock comparisons across workers,
and relying solely on a push notification. Each could leave a stale enable active
or increase resource use during an outage.

## Default resource and deadline bounds

| Boundary | Implemented default |
| --- | --- |
| Room source reconciliation | One pending source probe per room service; 250 ms scan interval |
| Source/collector capacity | 16 per node; validated configurable range 1–32 |
| Attachment startup lease | 500 ms; unresolved admission retains its permit |
| Capture handoff | 64 packets and 262,144 charged bytes per handoff, including in-flight work |
| Discovery handoff | 2 packets and 4,096 bytes |
| Diagnostic inference | One concurrent job; configurable up to min(source capacity, 8) |
| Model load | 15,000 ms deadline; lazy, outside call admission |
| Inference | 2,000 ms deadline; one outstanding job per source |
| Live report retention | 1,024 packets and 1,048,576 charged bytes per collector |
| Writer pool / write-task pool | 64 each per node |
| Writer retained queue | 128 records and 1,048,576 charged bytes per writer, including in-flight work |
| Write attempts | At most 2; 1,000 ms per attempt; 50 ms retry delay |
| Writer shutdown drain | 2,000 ms; discard remaining diagnostic work after deadline |

These limits apply to their named boundaries; they are not a total process-memory
budget. Copied payloads, model tensors, allocator overhead and multiple workers
require the separate measured load gate. Saturation drops or marks diagnostics
incomplete rather than changing provider input, commits or call-control decisions.
Shared inference and persistence are outside the room lifecycle. The optional
room diagnostics subtree owns its source workers and stops with its room.
Callbacks offer bounded work and do not wait for model initialization or database
persistence.

Sources: Engine `Diagnostics.SettingsLease`, `SettingsProjection`,
`SourceSupervisor`, `AttachmentLease`, `CaptureHandoff`, `RoomService`,
`LiveReport`; Calls `Diagnostics.Supervisor` and `Writer`.

The [measurement plan](latency-diagnostics-measurement-plan.md) records the
in-process isolation choice, native failure limits and predeclared load budgets.
These budgets have not yet been measured and do not establish supported capacity.

## Verification boundaries

`settings_peer_test.exs` runs two isolated BEAM VMs with independent controlled
clocks and real settings projections. Controlled loader snapshots simulate the
same durable revision on each worker. One worker gets a hint while stalled; the
other misses it and expires at exactly 3,000 ms. It also rejects a stale enabled
revision after reconnect. This proves per-worker authority semantics; it does not
measure network/database propagation latency or prove the settings UI is complete.

Focused handoff, inference-admission, source-supervision and writer tests exercise
retained count/byte budgets, blocked resources, task cancellation, finite retries
and drain. Configured Scribe fixtures separately prove mode selection, toggles and
source replacement without changing operational inference or provider delivery.

## Effective-status integration contract under review

The settings API currently returns the saved setting only. The UI may refresh an
explicit applying status, but must not invent applied status from its own timer.
A local worker acknowledgement cannot certify an unknown set of remote workers.

A proposed expiry proof would observe an authoritative disabled revision R, wait
at least the maximum lease grace, then **start a new authoritative read** and
require exactly R again. A read merely completing after the deadline is not enough:
it could have captured R before a concurrent enable and returned late. Reads must
use the primary store and a fresh transaction snapshot. Errors, conflicting values,
newer revisions and process restart invalidate proof; late replies cannot restore
it. Every API node would maintain its own proof, so load balancing could delay,
but never accelerate, confirmation.

This proposal is not implemented or accepted as an unconditional global proof.
Independent monotonic clock origins are safe, but independent elapsed-time rates
and host suspension are not interchangeable. A tracker advancing three seconds
cannot prove a suspended worker's clock advanced three seconds. See Erlang's
[time correction documentation](https://www.erlang.org/doc/apps/erts/time_correction.html).
A lease-based global confirmation requires a documented clock-progress/rate bound
and a conservative grace including drift and timestamp resolution. Without that
operating guarantee, report applying/unknown or collect acknowledgements from all
registered capture authorities; connected-node discovery alone is not membership.

An eventual applied-disable claim means capture authority is revoked, not that
all suspended processes/native tasks have terminated or historical persistence has
drained. Enabled status must describe saved collection permission, not promise
that every eligible call has model readiness, capacity or complete coverage.
