# Durable whole-call hangup

Status: implementation design for the [platform MCP milestone](../labnotes/milestones/platform-mcp-endpoint.md).
Durable cancellation intent, exact-supervisor monitoring and the generic engine
startup gate are implemented.
Runtime admission binding, reconciliation and the HTTP/MCP hangup operation remain
unfinished; the complete lifecycle below is still the implementation contract.

## Decision and ownership

HTTP and MCP call the same authorized Calls operation. It persists cancellation
intent before asking Gateway to stop runtime resources. Persistence owns row
locking and terminal evidence; CallEngine owns exact-incarnation shutdown;
Gateway owns bounded reconciliation across those boundaries. No database
transaction waits for a provider or runtime process.

Store `hangup_requested_at` on the call, deriving public `ending` while cleanup
is outstanding. Avoid adding a database `ending` state or a second job system.
The existing call row is the durable work item. Repeated requests are safe.

Authorize the actual actor and tenant before looking up runtime resources. The
client supplies a public call ID; only the server resolves room and incarnation.
Neither a transport argument nor a stale runtime handle may select a replacement
incarnation for termination.

## Admission ordering

The engine prerequisite is available as `call_admission: {owner_pid, token_ref}`
on `CallEngine.start_call/2`, with `admit_call/4` and `cancel_call_admission/4`.
It reuses the existing owner-monitored outgoing gate. Legacy outgoing options,
APIs and submission acknowledgements remain supported; contradictory options
are rejected. Gateway still needs to bind admission durably before release.

The call-row lock orders cancellation, token issuance/redemption and admission.
A prepared call can become ended atomically. Later token operations and admission
must reject its cancellation. Do not revoke each token while holding the call
lock: redemption already locks token then call, so reversing that order would
introduce a deadlock.

Extend the existing owner-monitored pending admission mechanism to web and
incoming carrier startup. Start a gated room, bind its exact incarnation durably,
then release startup. The binding operation returns either admit or cancel:

- Cancellation committed before binding: retain the exact binding for cleanup,
  cancel the gated room and release no provider/carrier startup effects.
- Binding committed first: admission may already be in flight. Reconciliation
  stops that incarnation and cleans up its owned resources.

This binding is the ordering point. There is no claim that a database transaction
can prevent effects in a later process mailbox or an in-flight carrier request.
Repeated binding accepts only the same incarnation; it cannot replace ownership.
Late lifecycle projections must preserve cancellation intent and require that same
binding; a late started projection must not reopen a cancelled call.

`Calls.bind_call_admission(subject, incarnation_id, options)` preserves the subject
wrapper (web admission claim, incoming carrier claim or outgoing prepared call)
and validates its persisted ownership, pinned room and plan. It returns
`{:ok, :admit | :cancel, updated_subject}` and establishes immutable ownership.
When Gateway cleanup tracking is connected, the same binding transaction must
also set cleanup-required state for newly managed admission; it cannot be delayed
until after release or archive closure. This ownership metadata does not start
the call or prove cleanup completion.
The call-row lock establishes order; an unused binding timestamp is unnecessary.
Binding must not invent `started_at`, activate a durable carrier leg or change
lifecycle state merely to reserve runtime ownership. Web/outgoing startup then
synchronously records its started projection before releasing the gate. Incoming
calls retain their existing answered/media-event start time.

Running web joins also validate the complete, still-active admission claim before
joining or issuing a pending-transfer session. The engine must check the expected
incarnation inside the serialized join operation; a snapshot followed by an
unscoped join can race a replacement. A participant join failure does not terminate
an otherwise valid whole call.

Web admission must await binding before releasing startup or issuing a session.
Incoming carrier admission must bind and establish cleanup ownership before
activation/answer, including cancellation before an activation object exists.
Outgoing admission retains its existing ownership and submission acknowledgement
protocol, adding the same cancellation guard.

Incoming Leg retains the claimed carrier identity independently of activation.
Record and monitor the gated room before answering. Prepare activation context
before submitting the answer, and retain it on failure or unknown submission so
late results can be cancelled. Bind failure/cancellation must reject or end the
original carrier leg even when no activation result exists.

## Cleanup and terminal evidence

A supervised Gateway reconciler wakes after intent is committed and also scans
pending intent after restart. Work has bounded concurrency, deadlines and fair
traversal/backoff: an unresolved old call cannot starve later cancellations.
Request timeout or caller death does not discard intent or own the cleanup task.
Recovery never starts a room or dials a carrier to resolve uncertainty.

Use an exact-incarnation engine shutdown operation with a fixed API-requested
reason. Release participant sessions, carrier legs and owned workers through
normal lifecycle handling, preserving usage and archive draining. Pending Gateway
sessions also observe room termination.

`ended` requires one of these runtime proofs, plus completion acknowledgements
from any Gateway-owned sessions and carrier owners outside the engine subtree:

- Atomic cancellation while still prepared, before admission can claim it.
- Matching durable archive completion for the owned incarnation.
- Observed termination of the trusted exact incarnation supervisor, persisted
  against the same immutable binding and cancellation intent.

Gateway.OutgoingLeg is outside the engine subtree. Its starting/unknown carrier
state can require late adoption and retirement even after an engine stop. Keep
that cleanup tracked; engine shutdown or archive close alone must not report that
such a call has fully ended. If carrier termination cannot be established, retain
the documented unknown/unavailable outcome rather than claim remote success.
Closing admission must also close owner registration before the final cleanup
acknowledgement. Neither late registration nor a later archive projection may
bypass the required Gateway acknowledgements.

Use a dedicated Gateway cleanup owner for each newly managed call incarnation.
Existing Session, WebRTC, media and carrier supervisors retain their responsibilities.
The cleanup owner serializes resource registration and sealing; resources register
before effects, and sealing rejects further registrations. Completion requires
acknowledged outcomes plus termination of the registered local supervision trees.
Initial and transfer carrier legs both retain uncertain late-adoption cleanup.
A successful end command is acceptance, not an authenticated terminal callback.

Persist cleanup-required state with admission before effects, and bind completion
acknowledgements to that same incarnation. The incarnation is already a sufficient
generation identifier. Reconciliation can reconnect to a surviving owner, but
must not recreate an empty tracker after membership loss and call that success.
Missing membership/evidence remains unknown.

For newly managed calls, archive projection must defer `ended` until Gateway
completion even if archive close wins the race before a hangup request. Keep the
archive fact writable while terminal projection waits. Preserve the approved
already-ended, no-new-effects contract for existing terminal records; do not
retroactively claim that legacy rows acquired the new resource acknowledgements.

The current room monitor observes RoomAuthority, whose exit can precede subtree
cleanup. Add trusted exact-supervisor monitoring; a missing registry entry alone
is not completion evidence. Monitoring even a previously captured trusted PID
after it exits produces `:noproc`, which loses the exit reason. Require an
already-observed orderly `DOWN` or independent durable proof; `:noproc` alone
cannot justify `ended`.

Supervisor completion can acknowledge cancellation when archiving is disabled or
failed, provided the supervisor completed orderly shutdown. A killed/crashed
supervisor can exit before linked children finish and is not sufficient proof;
retain uncertainty until independent cleanup evidence is available. Record the
observed end time and a specific API-hangup terminal reason.
Later archive close for that same incarnation must still drain successfully even
if its timestamp differs. Restrict this exception to acknowledged cancellation;
retain normal conflicting-end protection.

Archive closure also needs reason classification. The subscriber begins draining
on any source supervisor termination, and a persisted `archive_stream_closed`
can contain `source_reason: "killed"` with `incomplete: false`. Queued-fact drain
and archive-quality counters do not prove child cleanup. Accept orderly runtime
completion evidence; abnormal source termination needs independent proof. Drain
timeout abandons pending work rather than manufacturing a successful closure.

Final carrier usage cannot rely on a send to an already-dead RoomAuthority.
Reuse the result-bearing `Calls.store_usage_observation/2` path with exact
call/room/incarnation validation and its existing immutable-ID deduplication.
Persist or retry final usage before acknowledging cleanup, while retaining normal
live-room archive reporting. Extend failed-call acceptance only for the matching
cancelled incarnation; do not silently discard unknown outgoing usage. This avoids
adding another engine shutdown phase solely to keep the usage reporter alive.

Owner death before binding can leave archive evidence. Establish one shared
durable archive ownership anchor under the call-row lock, validating the call's
room and exact incarnation across both facts and snapshots. Archive writes and
all started projections now use the same binding guard. A private
`incarnation_binding_verified` flag defaults to false for legacy rows; the first
successful binding validates both historical streams and sets the flag with the
anchor in one transaction. Conflicting history fails closed, including when a
legacy call already has a non-null incarnation. Later matching writes use the
verified anchor without rescanning growing history. Failed writes roll back both
the anchor and flag. This flag proves ownership validation, not resource cleanup.

Migration 20261015000500 adds that internal flag. Drain old application writers
before relying on the new invariant: older start/archive code can bypass these
checks even with the additive migration installed. Rolling back the migration
removes only the flag; established incarnation bindings remain intact.
Do not infer ownership from an arbitrary runtime lookup.
If restart leaves no
binding or completion evidence, report bounded unavailable/unknown rather than
inventing success. A failed/startup-unknown call may still have carrier cleanup
work and is not automatically safe to report as ended.

Cancellation before admission can leave `started_at` absent. The outgoing
lifecycle projector currently rejects archive close without a start time, before
the general call-end projection runs. Add a narrow cancellation-close path through
both projections; do not invent a start time or weaken normal outgoing ordering.

## Alternatives rejected

- Request-owned fire-and-forget cleanup loses work on request or VM death.
- An unscoped room stop can terminate a replacement incarnation.
- Marking ended before cleanup misreports active resources as terminated.
- Treating a missing runtime as proof confuses unavailable state with completion.
- A second admission framework duplicates existing owner monitors and gates.
- Persisting raw process IDs as restart evidence is invalid across runtime death.

## Verification and implementation order

`Calls.request_call_hangup/4` now persists intent with actual actor/tenant checks.
Its repository locks the selected call: an unclaimed prepared call can end,
while admitting/running/failed calls retain their lifecycle and first intent.
Token issue/redemption reject that intent under the same lock. This operation
does not stop a runtime. Migration `20261015000400` adds the nullable timestamp
and `api_hangup` terminal reason and must precede application rollout.

Focused verification passed 22 Calls tests, 57 Persistence compatibility tests
and two separate-connection SQL race tests. Tests cover cancellation-first and
redemption-first ordering, unusable outstanding tokens, failed outgoing uncertainty,
transaction rollback and invalid/noncanonical UUIDs before mutation. The latter
return not-found; persistence uses canonical public IDs.

The generic gate passed 33 focused engine tests and independent review. Tests
cover web/incoming deferred preparation, exact controller/token/incarnation,
controller death, cancellation, repeat release and outgoing acknowledgement
compatibility. All five root completion checks subsequently passed, including
the complete default umbrella suite with zero failures.

Web and outgoing admission now bind ownership and synchronously persist start
before releasing their startup gate. Running web joins use the exact bound
incarnation. Pre-release cancellation/persistence failure closes the owned gate
without projecting a generic failed state or issuing a session. The focused
Gateway selection passed 48 tests after nine expected red failures; independent
review found no blockers. Incoming activation still needs the same gate and
retained cleanup context. These prerequisites do not yet establish whole-call
cleanup or expose the HTTP/MCP hangup operation.

Implement and verify in coherent checkpoints:

1. Durable intent and immutable admission binding, with transaction barriers for
   prepared cancellation versus token issue/redemption and startup claims.
2. Generalized pending admission and exact-supervisor monitoring; prove no startup
   effects before an allowed binding and complete cleanup after release races.
3. Supervised reconciliation and shared HTTP/MCP adapters; prove recovery after
   request death and reconciler restart without redial or replacement termination.
4. Archive/session integration and end-to-end parity with local fixture providers
   and fake carriers. Cover archive disabled/failure, late archive close, owner
   death before binding, repeated ended requests and missing completion evidence.

Use explicit acknowledgements and process monitors rather than sleeps. Run the
root completion gates, plus Lean verification if implementation changes modeled
source-cutover or speech transitions. Keep the milestone unchecked until these
runtime acceptance cases pass.
