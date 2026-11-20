# Passive diagnostics runtime limits

> Architecture revision, 2026-11-19: [participant-owned room service](participant-vad-room-service.md)
> supersedes agent-selected discovery/ownership. The room-service cutover is
> implemented; performance and live acceptance remain open. See the
> [milestone](../../labnotes/milestones/passive-call-latency-diagnostics.md) for current acceptance.

These are implemented defaults and authority rules, not measured capacity or an
accuracy claim. The [milestone](../../labnotes/milestones/passive-call-latency-diagnostics.md)
tracks the remaining application, performance and live acceptance gates.

## Call-start settings snapshot

User-approved contract, 2026-11-20: the database-persisted installation setting
is read once when a new call starts. The immutable enabled value and revision
belong to that call and survive optional room-service restarts. Existing calls
retain their initial choice; later saves affect subsequent calls only. A missing,
failed or invalid initial read disables diagnostics for that call without failing
the call. It does not retry later and unexpectedly enable collection mid-call.

The read has a bounded 250 ms deadline and runs in a per-call task before
submitting the room to its shared supervisor. This replaces global polling, settings leases, invalidation hints and
cross-worker acknowledgement/status tracking. There is no distributed effective
state to confirm. The settings UI reports ordinary persistence success or errors,
with its existing toggle label and no new explanatory copy.

Source ownership, attachment admission, bounded handoffs, collector lifetimes and
room teardown still fence diagnostic work. Those lifecycle constraints are
independent of the immutable setting. Historical summaries retain bounded drain.

Rejected alternative: immediate changes to active calls require propagation and
revocation machinery that the user explicitly removed from this benchmark's
scope. The implementation checkpoint records focused old-call/new-call tests,
including persisted updates and source replacement in configured calls.

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
Linked input and collector handoffs share a sticky overflow flag, independently
of their local count/byte counters and first retirement cause. Input saturation
therefore persists `observer_overloaded` even if the source retires before the
collector finishes. The flag is published before local overflow can trigger
worker retirement; it adds no queue or retry. Unrelated/new runs have separate
flags. Queue release/re-admission semantics remain unchanged.
Shared inference and persistence are outside the room lifecycle. The optional
room diagnostics subtree owns its source workers and stops with its room.
Callbacks offer bounded work and do not wait for model initialization or database
persistence.

Sources: Engine `Diagnostics.CallSettings`,
`SourceSupervisor`, `AttachmentLease`, `CaptureHandoff`, `RoomService`,
`LiveReport`; Calls `Diagnostics.Supervisor` and `Writer`.

The [measurement plan](latency-diagnostics-measurement-plan.md) records the
in-process isolation choice, native failure limits and predeclared load budgets.
These budgets have not yet been measured and do not establish supported capacity.

## Verification boundaries

Focused call-start tests verify that enabled and disabled calls retain their
snapshots across later database changes, new calls see the new persisted value,
and unavailable initial reads remain disabled for that call. Obsolete peer-clock,
lease-expiry and propagation tests are removed with the old implementation.

Focused handoff, inference-admission, source-supervision and writer tests exercise
retained count/byte budgets, blocked resources, task cancellation, finite retries
and drain. Configured Scribe fixtures verify mode/source wiring without changing
operational inference or provider delivery. Model-accuracy and numerical inference
coverage are not additional acceptance requirements.
