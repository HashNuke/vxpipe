# Durable whole-call hangup

Status: implementation design for the [platform MCP milestone](../labnotes/milestones/platform-mcp-endpoint.md).
Durable cancellation intent, exact-supervisor monitoring, the generic engine
startup gate, runtime binding, cleanup reservation and completion persistence are
implemented.
Incoming gating, carrier resource tracking and reconciliation components are
implemented. Managed admission rollout remains unfinished. HTTP/MCP hangup adapters
now use the shared Gateway workflow. The complete lifecycle below remains the
implementation contract.

## Decision and ownership

`Gateway.CallHangup.request/4` now persists intent through Calls, wakes the existing
reconciler, and requests exact verified shutdown. HTTP and MCP share its projection
and fixed errors. Tracker reads are bounded; an unsealed tracker also exposes
uncertainty so known lost membership cannot be mistaken for accepted cleanup.
The persisted verification bit is part of the private PreparedCall projection.
Prepared/ended and unknown outcomes have domain, wire and persisted parity tests;
global managed admission configuration and full active-call acceptance remain due.

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
are rejected. Web, outgoing and incoming admission bind durably before release.

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

Incoming admission now uses that gate and retains the original authenticated
event, configured service, exact room and prepared activation before submitting
an answer. Carrier HTTP requests run as bounded work under the existing admission
task supervisor, leaving the Leg responsive to callbacks and room termination.
An authenticated answered/media-start event persists the start projection before
releasing the gate. Submission acceptance alone does not invent a start event.
The owner applies usage transitions to its current state, preserving callbacks
that arrived while the answer request was in flight.

Before binding that room, identify the incoming leg once and retain its initial
usage attempt. Identification validates the service but issues neither a media
token nor a carrier command. Answer preparation reuses the retained local leg ID
and observations. Cancellation before preparation therefore still has an attributed
attempt and uses that local ID alongside the original authenticated carrier control
ID. The Leg owns subsequent usage transitions; prepared contexts cannot replace
newer callback observations. Best-effort room reporting is not final persistence
evidence, which still requires an acknowledged store operation before cleanup can
be complete.

Room shutdown requests carrier termination without declaring it complete. A late
answer queues another end attempt if one is already in flight. Authenticated
termination and local room cancellation are separate evidence; a failed local
stop remains retryable. Duplicate durable admission claims do not adopt or end
another owner's resources. This incoming slice still uses the legacy binding
operation; managed reservation, carrier usage acknowledgement and tracker wiring
must land together before managed admission is enabled.

Incoming retirement now also waits for answer/end observers and their underlying
HTTP work to drain. Observer monitors are installed before operations start; result
delivery follows actual task termination, and the owner retains each observer
until its own DOWN. Abnormal observer loss remains unknown even when carrier end
and room shutdown have both been observed. A single retirement check retains
expired timers until drainage, and late answer results cannot modify already
terminal carrier usage. This closes local command lifetime handling; final usage
persistence and tracker acknowledgement remain required before managed completion.

## Cleanup and terminal evidence

A supervised Gateway reconciler wakes after intent is committed and also scans
pending intent after restart. Work has bounded concurrency, deadlines and fair
traversal/backoff: an unresolved old call cannot starve later cancellations.
Request timeout or caller death does not discard intent or own the cleanup task.
Recovery never starts a room or dials a carrier to resolve uncertainty.

Recovery discovery uses an internal bounded keyset scan over call rows, selecting
unended cancellation intent and unfinished managed cleanup (including normal
completion without a hangup). Each cycle captures an upper internal primary key
and advances past every returned row, including unresolved ones. At the end it
starts a new cycle. New inserts and rows becoming eligible behind the cursor are
therefore visited next cycle; this is a traversal watermark, not a database
snapshot. Continuous new admissions cannot extend one cycle indefinitely.

The scan returns only public ownership identifiers, the internal traversal key,
verified-binding and cleanup flags, and cancellation/completion timestamps. It
does not decode plans or load credentials. Unbound legacy intent stays visible
without manufacturing an incarnation; already-acknowledged cleanup with a later
intent stays eligible for terminal projection replay. Already-ended calls are
excluded. A partial index supports bounded pages of at most 100 rows. The scan
alone performs no shutdown or ownership reconstruction.

`CallCleanupReconciler` implements that traversal as a supervised-process child
with one bounded scan task and at most four row tasks by default. It retains at
most one page (25 rows by default; maximum 100). Each task installs its own
five-second deadline before work; completion releases its slot only after actual
DOWN. A timed-out row advances the current traversal and remains eligible next
cycle. Failed scans retry their current cursor with capped backoff. Coalesced wake
hints preserve a running cycle and request another pass after it finishes; restart
begins at the first cursor. No caller owns the scheduled tasks.

`CallCleanupRecovery` only stops a verified exact incarnation with durable hangup
intent. Pending normal cleanup alone does not stop an active call. Previously
stored cleanup completion replays its original timestamp through Calls even after
tracker retirement. Missing runtime/tracker evidence never creates membership or
writes completion. These components have focused local verification; application
supervision/configuration and hangup wake wiring remain pending with managed
admission rollout.

The engine now exposes `CallEngine.hangup_call/3` for the trusted tenant, room and
incarnation, with fixed authority shutdown reason `:api_hangup`. Existing
`end_call/3` retains its remote-hangup meaning. The incarnation check occurs inside
the serialized authority, so a stale request cannot terminate a replacement.
Successful submission is not whole-call completion: the engine supervision tree
and Gateway resources still require their separate completion evidence.
Release participant sessions, carrier legs and owned workers through
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

Outgoing initial and transfer owners now share cancellation handling. Disconnect
and transfer timeout abandon through the owner instead of killing a potentially
submitted leg. Known carrier control IDs remain immutable across partial REST
results and late callbacks. Cancellation revokes media admission, retains the
owner, and submits a bounded end command; accepted or rejected end requests do
not themselves prove termination. Late answered/media evidence requests another
end attempt, coalescing it while a prior request remains in flight.

Normal outgoing retirement waits for both command observers to terminate after
their underlying HTTP tasks drain. Abnormal observer loss retains uncertainty
even after a terminal carrier event, since the shared task supervisor may still
own the request. Expired legacy retention deadlines are retained until known
command drainage; unidentified abandoned attempts may then retire with unknown
usage, without asserting managed cleanup completion. Final usage persistence and
tracker acknowledgement still need wiring before managed admission is enabled.

Outgoing command startup now installs the caller's observer monitor before releasing
any carrier work. The paused observer monitors its owner and has a bounded startup
wait. Dial/end callers retain the returned monitor, so even an immediate normal
completion produces usable termination evidence rather than a late `:noproc`.

Outgoing preparation now validates the request and service and retains one usage
attempt before checking the deadline or reserving media. A definite pre-submission
failure therefore retains its original start/failure observations for final
persistence; invalid input creates neither usage nor media effects. Failed owners
that never reserved media preserve that failure through disconnect/abandonment.
This prepares the owner for final-usage acknowledgement but does not enable managed
tracking by itself.

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
The Session/WebRTC hooks are implemented and locally verified. Managed admission
now supplies the verified private binding from its refreshed durable claim, for
both newly started and running-call sessions. Runtime configuration now enables the complete composition when durable
persistence is configured. The active-call acceptance check remains a separate gate.

Telnyx and Twilio media sockets now also monitor their exact room incarnation.
They reject startup against an unavailable or stale room and close on room
termination independently of the retained carrier owner. A carrier owner may
remain alive to reconcile an uncertain end command; it must not keep media open
after the room has stopped. This room-authority monitor controls socket lifetime,
not whole-supervisor completion or remote carrier termination.

Media bindings now accept an optional private cleanup binding, validated against
their exact tenant, call, room and incarnation. The media connection supervisor
registers its entire root before starting children. Each provider socket registers
the actual WebSock process from its init callback, separately from the media tree.
Both acknowledge only the absence of independent carrier/usage obligations;
completion still waits for orderly root termination. Missing, sealed or mismatched
ownership rejects startup without constructing replacement tracking state.

The media session monitors the resolved tracker before attachment, independently
of its socket. Tracker loss closes the local media tree and socket. Repeated media
startup can reuse a root only when the existing session agrees on the complete
binding, socket owner, stream, tracker and root PID. A duplicate request cannot
adopt an existing untracked tree or a replacement connection sharing its ID.
Managed carrier owners supply this private binding alongside their reservation
and final-usage ownership. Admission scopes the supported outgoing connector per
call, including transfers initiated from web or incoming calls.

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

The owner-held `CarrierCleanup` helper now provides that registration and storage
protocol without creating another owner process. It attaches only to an existing
exact tracker, registers the original Leg, and retains one immutable terminal
usage batch. Persistence runs under the existing task supervisor; each worker
installs its own deadline before calling storage, so the bound survives Leg death.
A result alone cannot complete storage: the owner also waits for the worker DOWN.
Partial failure and timeout retry the same batch with capped backoff.

Only the original Leg can acknowledge its tracker membership, after storage is
confirmed, the current usage batch still matches, commands are drained, and the
Leg independently proves carrier termination or no submitted command. Unknown
usage can be stored without becoming carrier-completion proof. Tracker loss is
reported unavailable and never creates a replacement tracker. Both carrier owners now use these locally tested helper contracts. Managed
admission supplies their per-call scope; complete active-call acceptance remains
a separate integration gate.

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

## Completion persistence ownership

The cleanup tracker can persist its own completed evidence through
`Calls.complete_call_cleanup/3`, using one bounded supervised task. This remains
opt-in through explicit completion options on a fresh managed tracker; managed
admission supplies its Calls dependencies through those options. The reconciler discovers durable work and requests exact
shutdown; it does not reconstruct missing trackers or own their final retirement.

This avoids a recovery gap if an external reconciliation worker commits completion
then dies before retiring the tracker: completed rows correctly disappear from
the pending scan, so that orphan would no longer be discovered. Owner-held
persistence can retry the same binding and first completion timestamp while the
tracker survives. If it dies, there is no orphan tracker to retire; the database
either retains pending unknown work or already contains the committed proof.

Install the deadline inside the task before storage, retain mailbox responsiveness,
retry failures with capped backoff, and retire only after both acknowledged storage
and actual task termination. The Calls facade owns exact stored-result validation
and publication retriggering. Tracker status `complete` describes resource
evidence; public `ended` still requires durable projection.

A later hangup on a normally completed call may find durable cleanup completion
before normal archive closure. Replay completion using its stored timestamp even
if the tracker has retired. The pending scan already includes completed cleanup
with new cancellation intent; this branch must not require a replacement tracker.
Tests must cover successful commit followed by a lost task result, immutable
retry, requester death, and waiting for actual task DOWN before retirement. This
ownership contract now has focused tracker tests. Managed admission creates a
tracker only for a fresh durable reservation; an existing reservation must resolve
an existing open tracker. Runtime composition is enabled with durable persistence; complete integration
checks remain.

## Runtime composition

`Gateway.Application.http_options/1` composes managed admission for both standalone
Gateway and Console's embedded mount. With durable persistence configured, runtime
configuration enables the default admission backend and archive writer in development
and production, plus one named `CallCleanupReconciler` under Gateway's supervisor.
The reconciler runs even when Gateway's own HTTP listener is disabled.

Default incoming admission inherits archive/cleanup options while explicit incoming
overrides remain authoritative. Custom handlers/backends are preserved. Without
durable persistence the managed flag remains disabled; already managed persisted
calls still require their existing ownership when joined. Apply the additive
migrations and drain old application writers before rollout. This configuration
work does not establish that full active-call acceptance has passed.

## Carrier integration contracts

These are integration requirements identified from the existing owner paths; they
are not claims that managed admission is enabled.

Incoming admission must reserve and seed cleanup immediately after capturing the
exact gated room, before a local identity/usage failure can bypass ownership.
Allocate the retained usage identity before acting on the binding's admit/cancel
decision. If identity allocation fails, still end the original authenticated
carrier, but do not invent a usage batch or completion acknowledgement. A failure
to create the room leaves no trusted incarnation to reconstruct later.

Incoming owners now support this sequence behind the private `managed_cleanup`
option. The backend's managed startup marker is retained before binding, including
malformed or failed reservation responses. Fresh reservations seed the existing
carrier owner atomically; existing reservations only look up membership. Identity
and usage are retained before the admit/cancel/error decision, and media bindings
carry the exact cleanup identity. Missing identity/usage or a lost command observer
cannot acknowledge completion. Final storage plus authenticated carrier end,
authority closure and command drainage gate orderly retirement. Durable runtime configuration now enables the option. Incoming rooms receive
per-call outgoing connector scope so their transfer legs participate too.

Outgoing owners must validate their request and private connector scope, retain
usage, register with the existing exact tracker and monitor the room before reserving media or dispatching
a dial. Transfers need this room monitor too: the initial-leg lifecycle currently
supplies it only for initial dials. Room termination requests cancellation of the
original carrier; it does not prove that carrier termination has completed.
The private per-call connector scope must propagate through initial and transfer
requests and every media binding without becoming a caller-controlled field.

Track whether a dial command was dispatched. A `failed` owner status or a generic
adapter error is not proof that no carrier exists: an accepted HTTP response with
missing/malformed identifiers can return an error after creating the remote call.
Only pre-dispatch failure or an explicitly trustworthy provider rejection can
supply no-carrier proof. Ambiguous dispatched outcomes retain correlation for late
callbacks, and managed retirement cannot use the legacy unknown-retention timer
as completion evidence.

The outgoing owner now implements these rules behind private `cleanup_scope` and
`cleanup_options` connector settings supplied by managed admission.
Validation precedes usage allocation and effects. The existing tracker registration
and exact authority monitor are installed before media reservation or dial,
including transfer legs. Every reconstructed media binding retains the same exact
cleanup identity. Final storage and command-worker DOWN independently gate
acknowledgement; a dispatched error remains correlated and unknown.

An ended managed transfer owner retains its membership and stored usage until the
call authority closes. Tracker loss closes this owner's carrier/media resources,
then similarly retains unresolved ownership until independent authority closure;
it does not synthesize whole-call cancellation intent or a shutdown reason. The
tracker separately owns the proof that the complete engine supervision tree has
drained. This conservative retention avoids treating carrier-owner retirement as
proof about the rest of the call.

Both carrier owners now retry failed or uncertain end commands. Engine-only
reconciliation cannot recover such a failure after the authority is gone. Retry
ownership stays inside the original Leg: one coalesced timer with 250 ms initial
delay and 5 s capped backoff, no overlapping workers, and only after normal observer
DOWN proves the previous command task drained. Submission-start failure schedules
the same retry. An abnormal observer exit keeps drainage unknown and suppresses
automatic overlap. Retries retain the original control ID; missing outgoing
identity waits for authenticated adoption and never redials. Authenticated end
cancels retries. Accepted submission alone is not carrier-end proof. Only the
acceptance boolean is retained, not the raw provider response. Explicit late-answer
retries also repeat local cancellation with the original reason; timer-driven
carrier retries do not repeatedly invoke local shutdown.

Keep a private managed-ownership marker even when registration fails, so an owner
cannot accidentally fall back to legacy retirement. After validating the anchor
and options, the carrier helper retains owner-held persistence context when the
tracker is unavailable. That detached context can store usage but cannot
acknowledge or create membership. Its storage-only query also requires the
original owner, unchanged final batch and actual storage-worker termination.
On tracker loss, close the original resources. Once independent carrier end, local
room closure, command drainage and matching final-storage completion are proven,
the owner may retire without acknowledgement; the durable call remains unknown.
Missing usage or unsuccessful storage must not satisfy that retirement gate.

Normal managed preparation failure retains durable usage without a hangup
request. The failed-call storage exception now permits managed calls with the
exact verified room/incarnation. It persists the entire immutable batch, including
its initial observation, with existing deduplication. Storage leaves failed state,
cancellation intent, terminal timestamps, cleanup acknowledgement and publication
readiness unchanged. Legacy failed calls and missing/unverified/mismatched
ownership remain rejected. Focused tests cover whole-batch retry and unknown
terminal accounting separately from carrier completion; owner integration remains
pending.

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
review found no blockers. Incoming activation now has the same gate and retained
cleanup context. These prerequisites do not yet establish whole-call
cleanup. The shared HTTP/MCP hangup operation is implemented; complete active-call
acceptance remains required.

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

Active web acceptance now passes through real persisted canonical creation/token
issuance, managed admission, Session issuance and a connected local WebRTC peer.
Authorized HTTP hangup drains the Session, WebRTC root and tracker before the test
observes durable cleanup, archive closure and `ended` with `api_hangup`. Repeated
hangup is terminal and further tokens are denied. A second case removes the tracker,
waits for exact engine closure and verifies that recovery preserves unknown cleanup
without recreating membership. These tests use local human participants, with no
voice provider or external telephony. See the [acceptance commands](development/platform-mcp-acceptance.md#active-call-lifecycle-acceptance).

Final milestone acceptance completed on 2026-10-15. The current source passed all
five root gates, the full default umbrella suite, reference-client parity and the
selected local lifecycle/boundary lanes. The implementation milestone records the
requirement-by-requirement evidence and independent review. Deployment still requires
the migration/writer-drain ordering described above; no deployment was performed.
