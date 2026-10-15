# Durable whole-call hangup

Status: implementation design for the [platform MCP milestone](../labnotes/milestones/platform-mcp-endpoint.md).
The lifecycle changes below are not implemented yet.

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

Web admission must await binding before releasing startup or issuing a session.
Incoming carrier admission must bind and establish cleanup ownership before
activation/answer, including cancellation before an activation object exists.
Outgoing admission retains its existing ownership and submission acknowledgement
protocol, adding the same cancellation guard.

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

The current room monitor observes RoomAuthority, whose exit can precede subtree
cleanup. Add trusted exact-supervisor monitoring; a missing registry entry alone
is not completion evidence. A previously captured trusted PID can be monitored
after exit, but an absent or unverified lookup cannot justify `ended`.

Supervisor completion can acknowledge cancellation when archiving is disabled or
failed. Record the observed end time and a specific API-hangup terminal reason.
Later archive close for that same incarnation must still drain successfully even
if its timestamp differs. Restrict this exception to acknowledged cancellation;
retain normal conflicting-end protection.

Owner death before binding can leave archive evidence. Establish one shared
durable archive ownership anchor under the call-row lock, validating the call's
room and exact incarnation across both facts and snapshots. Current archive
checks independently choose a first fact or snapshot and do not establish that
shared guarantee. Do not infer ownership from an arbitrary runtime lookup.
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

Read-only review confirmed the current web handler projects `mark_started` after
starting the runtime, incoming activation precedes its started projection, and
the current room monitor does not prove whole-supervisor termination. Independent
design review identified the ordering, lock-order and archive fallback constraints
above. This is design evidence, not runtime acceptance.

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
