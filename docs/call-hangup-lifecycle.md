# Durable whole-call hangup

Status: implementation design for the [platform MCP milestone](../labnotes/milestones/platform-mcp-endpoint.md).
Durable cancellation intent, exact-supervisor monitoring, the generic engine
startup gate, runtime binding, cleanup reservation and completion persistence are
implemented.
Incoming gating, resource integration, reconciliation and HTTP/MCP hangup remain
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
are rejected. Web/outgoing admission binds durably before release; incoming
integration remains.

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

The implemented `Gateway.CallCleanup` prerequisite is a temporary supervised
process keyed by the canonical tenant/call/room/incarnation binding. `start_new`
is for freshly authorized admission; recovery uses `lookup` only. Application
integration must enforce that distinction durably; the process API alone cannot
prevent explicit recreation after lost membership.

Each registered supervision root retains its original semantic acknowledgement
owner. A different process cannot replace that owner or acknowledge its resource.
Sealing (also triggered by engine DOWN) closes registration. Completion requires
orderly exact-engine DOWN, orderly DOWN for every registered resource root, and
their semantic acknowledgements. Abnormal or `:noproc` exits remain unknown.
An owner lost before acknowledging also leaves unknown evidence; an already
accepted acknowledgement survives its owner. A surviving original owner can
resolve an unknown semantic outcome after orderly resource termination.

`observe` atomically subscribes and returns the current snapshot; change messages
let reconciliation wake without polling the owner. Callers must separately monitor
the owner for lost state. The first completion timestamp is retained, and owners
do not disappear automatically on completion. Retiring them after durable storage,
registering actual resource owners before effects and persisting cleanup-required
state are still integration work, not guarantees supplied by this component alone.

Incoming carriers already exist before answering. The implemented
`start_new(binding, {kind, root})` captures the admission caller and seeds that
resource and its original acknowledgement owner atomically during tracker
initialization, before an engine DOWN can seal empty membership. Incoming Leg must
use this entry point when tracking is wired. A missing exact engine fails startup
and leaves durable completion unknown while Leg retains its carrier cleanup
responsibility. Apply the same rule to any adopted resource with existing effects;
post-start registration is sufficient only when rejection prevents those effects.

### Local session and WebRTC registration

Sessions now accept a private cleanup binding and register before issuing their
credentials and carry the exact cleanup binding privately into their WebRTC
snapshots. A Session acknowledges only after its admission-release callback
succeeds. Failed releases retain supervised retry ownership. Managed sessions
monitor the claimant, bound connection and tracker even without a release
callback; tracker loss closes the local session and cannot recreate membership.

The WebRTC incarnation supervisor registers itself before starting children.
Because this tree has no independent carrier or durable-usage obligation, it can
acknowledge that fact at registration. This is not completion: the tracker must
still observe orderly termination of the entire tree and the exact engine
supervisor. Abnormal termination remains unknown. This avoids depending on a
child's `terminate/2` callback or an HTTP request's lifetime. Registration failure
prevents peer creation, media startup and engine attachment.

These hooks alone must not enable managed admission. Web calls can initiate
outgoing transfer legs outside those trees; initial and transfer carriers still
need registration, remote termination evidence and final-usage acknowledgement.
The durable reservation and tracker must exist before releasing the startup gate.
The Session/WebRTC hooks are implemented and locally verified. Production
admission does not yet supply the private binding; enabling it remains part of
the complete resource-wiring checkpoint.

Telnyx and Twilio media sockets now also monitor their exact room incarnation.
They reject startup against an unavailable or stale room and close on room
termination independently of the retained carrier owner. A carrier owner may
remain alive to reconcile an uncertain end command; it must not keep media open
after the room has stopped. This room-authority monitor controls socket lifetime,
not whole-supervisor completion or remote carrier termination. Socket and media
cleanup registration remain part of the resource integration work.

### Terminal projection and publication

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

`LegUsage` now retains the original bounded observation batch while keeping live
reporting. `persist_final/2` requires terminal usage and a retained terminal
observation, then stores each original value through Calls. It acknowledges only
matching stored observations (timestamp precision may normalize); any partial
failure leaves the same batch available for immutable retries. Managed usage
storage requires the exact verified incarnation and room. Failed-call storage is
allowed only for a managed call with cancellation intent and does not change its
lifecycle evidence. An `unknown` observation being stored is not proof that the
carrier ended. Carrier-owner integration must run persistence in its supervised
bounded work, retain context until success, and combine storage acknowledgement
with independent carrier/resource completion before acknowledging cleanup. That
integration is still pending.

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

The managed binding operation now reserves cleanup ownership in the existing
admission transaction. Migration `20261015000600` adds private
`gateway_cleanup_required` and `gateway_cleanup_completed_at` fields, defaulting
existing calls to legacy behavior. A managed binding distinguishes a one-time fresh reservation from an
existing reservation. Only the fresh admission can create a tracker; repeated
binding and running joins must look up surviving membership. A crash after the
reservation but before tracker creation leaves unknown evidence. Do not add these
fields to public create/update inputs or store process identifiers in the database.

`Calls.complete_call_cleanup(binding, completed_at, options)` now locks and
validates the exact tenant/call/room/incarnation, requires managed ownership, and
preserves the first completion timestamp. It reads cancellation intent under that
lock to select the API-hangup reason. Without intent, persist the acknowledgement and replay an
already-stored normal archive close, or await a later close. Keep normal archive
time/conflict rules; only acknowledged cancellation uses the observed cleanup
time as terminal time. A retry must reevaluate intent, which may arrive after
cleanup was acknowledged but before normal closure. Schema/reservation and
terminal-projection deferral are implemented together. Gateway integration must
land before managed admission is enabled. Existing writers must be drained
before rollout because they bypass this terminal gate.

Archive closure now commits while cleanup is pending: defer the terminal `ended`
state without rejecting the archive fact. Preserve valid outgoing lifecycle
metadata such as `dial_ended_at` and `outgoing_outcome`; the committed close fact
may not replay later. Handle cancelled-before-start closure before outgoing
start-time validation without inventing `started_at`. An admitting managed call
can close before any cancellation intent; a failed pre-start call needs intent
for the narrow close-fact exception. Closure may precede intent but cannot precede
creation. This does not generally allow failed web/incoming snapshots or other
facts. The archive adapter treats `call_not_started` as terminal discard, so
rejected earlier snapshots do not block close indefinitely; they remain archive
quality loss rather than successful writes.

Completion now requests publication after its transaction commits, including retries:
the current publication finalizer can consume the earlier archive-close trigger
while the call is not yet ended. Both publication-source reads and publication
writes now reject managed calls with pending cleanup, including failed calls.
Managed nonterminal calls whose cleanup is already acknowledged but whose normal
close has not arrived retain a retryable waiting result. Legacy nonterminal
behavior is preserved. The distinct `call_cleanup_pending` result keeps the
existing finalizer retrying:
a completion trigger can encounter an existing finalizer that already read the
pending state. Returning `call_not_ended` would let that older worker exit and
lose the wakeup. An archive close arriving after acknowledgement and cancellation
but before the completion retry also projects the retained API-cancellation time
under the archive lock. Normal conflicting close timestamps are rejected even
while cleanup is pending; completion does not silently select one conflicting
fact. Successful acknowledgement is persisted evidence only: Gateway resource
owners and reconciliation still need to supply that evidence and invoke this API.

Final carrier observations must be generated once and retained with their
immutable IDs for result-bearing usage-store retries. The current best-effort
reporter returning `:ok` is not a persistence acknowledgement. Managed usage must
match the non-null incarnation and room; permit failed-call cleanup only for the
matching cancelled incarnation. Verify archive-first/completion-first ordering,
reservation loss, rollback, exact binding, late archive tolerance and usage after
engine exit before exposing hangup.

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
