# Initial outgoing call lifetime

The initial outgoing entry has its own dial lifetime. The engine prepares the handler
before submitting one provider-neutral phone request. The request pins the room
incarnation, callee and service reference; it also carries the room owner and an opaque
attempt reference used only inside the runtime. It contains no provider credentials.
Transfer dialing retains its separate admission and cancellation behavior.

`RoomDialSupervisor` owns one submission worker per outgoing room. The worker calls
the host connector while RoomAuthority remains responsive to its ring timer and
carrier reports. `RoomAuthority.OutgoingCall` owns the absolute deadline, submission
result, leg-owner monitor and initial outcome. It verifies callback correlation and
checks the deadline on callbacks as well as on the timer message, so a delayed timer
cannot allow a late answer to revive the attempt. The room's readiness budget includes
the ring budget, and first-message speech requires an accepted submission and the
callee's ordinary media attachment.

The Gateway leg monitors the room independently of the submission worker. Room loss
or initial disconnect cancels a known provider leg. An unknown submission retains
its owner for the configured media-token lifetime to adopt and cancel a late signed
identity. A timeout while the provider request is pending returns unknown; it does
not kill that owner and lose late acceptance cleanup. Initial cancellation is queued
asynchronously, then processed when the provider request returns. The existing voice
clients disable request retries. The implementation cannot cancel a remote leg whose
provider identity remains unknown through the cleanup window; it records uncertainty
and does not redial.

Configured answering-machine detection holds initial media until classification.
A physical answer cancels ringing while classification is pending. A machine result
ends the attempted leg before attachment or greeting. Human or unknown classification
permits an answered call; unknown is not recorded as proof of a human. Disabled
detection permits the ordinary answer/media path. Transfer detection continues to
use the existing recipient acceptance protocol.

## Decisions and implications

- Reusing transfer preparation was rejected because it makes the initial callee a
  private transfer destination and requires transfer acceptance. Initial media joins
  through the existing ordinary connection boundary instead.
- A synchronous dial inside RoomAuthority was rejected because it blocks deadline
  handling. The submission worker is scoped to the room supervisor, and the Gateway
  owner separately observes room loss even if submission is still in progress.
- Retrying an unknown request or destroying its owner on timeout was rejected because
  either can create an extra remote call or lose the only late cleanup correlation.
- Resetting the ring timer on carrier progress was rejected. One local deadline covers
  submission through physical answer; classification/media use the readiness budget.

## Verification and remaining work

Focused tests went red before the new contracts were implemented. The engine group
passed 64 tests covering outgoing entry, existing lifecycle/transfer behavior and
opening audio. Gateway passed 27 tests covering outcome correlation, main media
admission, machine detection, room-owner loss and late uncertain-submission cleanup.
Format, compilation with warnings as errors, strict Credo and dependency checks passed.
The full umbrella suite passed: 3,078 tests, zero failures across all nine applications.

The HTTP operation and its submission acknowledgement are implemented in the checkpoint
below. Archive/details/inspection project the outgoing outcome and timestamps through the
D6 checkpoint below. Native STS opening is tracked in the [opening decision](native-sts-opening.md);
turn Morse and Google fixture support pass focused and final root/Lean verification.
Duplex support and the three carrier acceptance cases subsequently passed; see the final
[milestone evidence](milestones/outgoing-calls-and-live-telephony.md#e-live-acceptance-and-incoming-hangup-repair-2026-10-05).
The [milestone](milestones/outgoing-calls-and-live-telephony.md) tracks these contracts
and the two answered carrier calls plus one non-answer live acceptance.

## Durable admission checkpoint

Calls now claims a published outgoing revision without issuing a join token. The record
starts in `admitting`; HTTP/runtime integration owns the transition to running or
failed. The persistence adapter invokes the existing fresh credential authorization
inside its insertion transaction, retaining its locks through commit.

Idempotency uses a tenant-wide opaque key (1–256 bytes) and SHA-256 of canonical JSON
containing the call-spec ID and initial variables. Map ordering does not affect the
digest. A replay returns the original record before compiling a new plan or consulting
a newer publication; it never creates a second admission. Unique-index conflicts are
resolved after rollback by fetching that tenant's record and comparing digests.

Selecting the largest revision or the most recent publication timestamp was rejected:
operators can republish an older revision. The repository reads the specification's
explicit publication pointer. The original immutable revision remains pinned to each
call. Rebuilding a plan on replay was rejected because publication or credential changes
must not turn a lost-response retry into a fresh call.

Focused evidence: six Calls workflow tests, including eight concurrent same-key
requests; four PostgreSQL tests for no-token storage, transaction authorization,
rollback recovery, and publication selection. HTTP submission acknowledgement and
outcome projection remain open and are not claimed by this checkpoint. All root gates
passed with the admission slice: 3,088 tests, zero failures, seed 303119.

Embedded hosts implementing the repository ports need three new operations:
`CallSpecRepository.fetch_published_revision/3`, `CallRepository.fetch_outgoing_by_key/3`,
and `CallRepository.claim_outgoing_call/3`. The claim returns either `{:ok, call}`,
`{:duplicate, original_call}`, or an error. The adapter must run its authorization
callback inside the same transaction/context as the credential repositories. The
Gateway must start runtime work only for a new successful claim; a duplicate is a
read of the existing call even while it is admitting, running or ended.

Direction remains a plan property. Admission uses the existing `telephony` invocation
transport rather than introducing another transport for outgoing calls, because both
incoming and outgoing phone legs use the same media transport and credential guards.

## HTTP submission checkpoint

`POST /api/tenants/:tenant_key/call-specs/:call_spec_id/outgoing-calls` uses the
existing configured call-admission backend, with tenant `calls`-scope authentication
and no browser CORS grant. A new claim is started once; a duplicate returns the original
record directly, including when the first request is still preparing or dialing.
See the [user request contract](operator-api-key-authoring.md#starting-an-outgoing-call).

The Gateway installs an opaque submission token and a deferred startup controller
before creating the room. The pending room admits no input and reports startup preparing.
Gateway monitors that exact incarnation and synchronously persists its running state,
then releases preparation. This orders durable start before handler preparation and
provider dialing. Projection failure cancels the unopened room without a carrier request.
Controller loss before release also ends the pending room. After release, room supervision
owns the call; loss of the HTTP controller does not undo an accepted submission.

The engine acknowledges accepted or unknown submission before any terminal exit. An
authenticated carrier answer/end report can acknowledge acceptance before a still-pending
worker returns, so an immediate busy/hangup cannot erase the HTTP result. The token allows
one acknowledgement; release replay does not prepare or submit a second time. HTTP waits
for this result, returning `201` with the durable call even when the room promptly exits.
An explicit submission/start failure returns `503`; an unconfirmed bounded wait returns
`outgoing_submission_unknown` with `retryable: false`. Neither path automatically redials.

Starting preparation before persisting the incarnation was rejected because a fast dial
or room closure could reach archive projection before a running record existed. Polling
room state after submission was rejected because the room may have already ended. Keeping
the controller monitor after release was rejected because an HTTP disconnect must not
destroy a carrier call whose submission may have succeeded.

Embedded repositories additionally implement `mark_outgoing_call_started/4` and
`mark_outgoing_call_failed/4`. Projection locks the tenant-scoped record and compares its
immutable plan digest and outgoing direction. Start replay requires the same incarnation;
failure projection preserves a previously ended/failed record rather than overwriting
its first terminal reason. Outgoing outcome/timestamp projection is implemented below.

Focused verification: 69 engine regressions, 50 Gateway regressions, seven Calls workflow
tests and five PostgreSQL workflow tests passed. Startup diagnostic assertions now bind
the exact lifecycle process; asynchronous readiness cancellation waits use an explicit
one-second bound. The suspended-peer cutover fixture retains its expiry check with a
one-second deadline; the carrier recovery-speech fixture retains its speech/audio assertions
with a five-second wait. Both fake carrier harnesses passed together: 26 tests, zero failures.

All root gates passed: format, compilation with warnings as errors, strict Credo, unused
dependency checks, and 3,104 tests with zero failures across nine applications (98 excluded,
seed 755205). Lean build, oracle check and Elixir replay also passed. Two earlier full runs
failed existing timing-sensitive fixtures; those failures and focused rechecks are recorded
in the [HTTP labnotes](../labnotes/20261005-0102-outgoing-http-submission.md). No paid provider
lane was selected. D5 is accepted; native STS opening and live carrier acceptance remain
open. D6 is accepted in the following checkpoint.

## Outgoing lifecycle projection

The engine emits three bounded archive facts: `outgoing_dial_submitted` with an empty
payload, `outgoing_call_answered` with `outcome: answered`, and `outgoing_dial_ended` with
one of the seven approved outcomes. They are also visible through live inspection.
Calls rejects additional payload keys and unknown outcomes. No dial request, destination,
credential, idempotency key or provider response is copied into these facts.

Persistence projects facts in the same transaction that archives them, holding the call
row lock and checking tenant, call and incarnation correlation. It retains the first
submission, answer and dial end times. Answered calls retain `answered` after hangup;
a terminal non-answer outcome cannot be changed by a late answer or conflicting end.
The SQL constraint requires start <= submission <= answer/end, and requires an answered
outcome whenever an answer timestamp exists. Duplicate delivery does not change the row.

Archive closure completes a submitted dial when room termination prevented the engine's
ordinary end fact. An existing answer is retained; otherwise an unclassified interruption
is `unknown`. A known preparation failure records `failed` without inventing dial times.
Closure after HTTP failure accepts evidence while preserving the failed call's first
terminal state/reason. The default closure clock now retains microseconds, matching durable
start timestamps and avoiding an immediate close appearing earlier through rounding.

Call-details lifecycle and database inspection expose `outgoing_outcome`,
`dial_submitted_at`, `answered_at`, and `dial_ended_at`. Times are UTC and nullable until
observed. Inspection keeps its existing millisecond JSON representation; stored values
and call-details timestamps retain microseconds. Historical incoming inspection keeps
its existing call-object shape. Archive projection is asynchronous and bounded; these
fields describe retained local evidence rather than a carrier delivery guarantee.

Projecting raw carrier responses was rejected because it exposes private/provider data
and makes public inspection depend on carrier-specific formats. Replacing outcomes on
every callback was rejected because late delivery must not revive a terminal attempt.
Treating abrupt room death as `no_answer` was rejected because remote submission/answer
may have happened without retained evidence; `unknown` expresses that uncertainty.

Focused verification covers all seven outcomes, replay, late/conflicting events, foreign
incarnations, private-payload rejection, inverted times, abrupt closure, preparation failure,
HTTP/archive ordering, SQL null semantics and public inspection. Native STS opening and
the three carrier acceptance calls remain open. All five root gates passed for D6:
formatting, warnings-as-errors compilation, strict Credo, unused dependencies and 3,121
tests with zero failures (98 excluded, seed 219668). The real parser/compiler accepts
the complete outgoing example; no provider request was made for that check.


The native turn-opening checkpoint subsequently passed all root gates with **3,134
tests, zero failures, 98 excluded**, seed 269987, plus the Lean build/oracle/replay.
See the [opening decision](native-sts-opening.md) for fixed-text validation and assembly
limits. This accepts the turn-provider slice, not the remaining duplex or live E gates.
