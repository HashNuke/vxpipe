# Prepared calls and single-use joining

Status: in progress. Specification review: approved (2026-09-08).
Prerequisites: [Tenant definitions/API keys](tenant-definitions-and-api-keys.md); [Call Variables](call-variables-and-tool-visibility.md).
Sources: [Web routes](../../labnotes/20260905-0405-call-definition-design.md#web-participant-admission-routes--approved-g2-routing); [single-use tokens](../../labnotes/20260905-0405-call-definition-design.md#single-use-join-tokens-and-existing-call-recovery--approved-g2-decisions); [timing](../../labnotes/20260905-0405-call-definition-design.md#record-creation-and-actual-call-start--approved-timing-contract).

## Runnable outcome

A backend prepares a tenant call with private initial variables and gets a token. The browser receives only that token, joins using the existing WebRTC/RTVI path, and starts the stored call exactly once.

## Specification

- Implement the approved tenant-scoped POST routes: participants/{participant_key}/calls, calls/{call_id}/participants/{participant_key}/sessions, and calls/{call_id}/participants/{participant_key}/join-tokens under /api/tenants/{tenant_key}. Calls resolves routes/revisions through ports; gateway owns credential/token verification and transport translation.
- Preparation and existing-record token issuance require a backend API key and grant no CORS access. Authorize tenant and calls scope; validate declared initial variables without defaults/completeness rules. Caller-start route must match entry_caller. Store call/initial values/pinned plan before returning an opaque participant-bound token, never a full private snapshot.
- Preparation creates no room/provider/dial; started_at remains unset. Claim token in a short atomic transaction before startup; do not hold a transaction across engine/provider work. Distinguish created_at, actual started_at, and logical ended_at; opening playback does not reset start time.
- Tokens default to five minutes; authenticated issuance may request longer. Independent unused tokens do not invalidate each other; revoking the issuing API key neither invalidates them nor ends sessions. Expiry consumes no call lifetime and does not delete an unstarted record.
- Recheck shared call/participant admission eligibility so racing distinct tokens cannot create duplicate participants/rooms or take over a connection. Tokens remain consumed after accepted admission even if confirmation is lost. Recover only bookkeeping for existing room/leg work; never repeat a crashed call or speculative dial.
- Browser join/signaling has configured CORS and token authentication; WebRTC remains first transport. Do not introduce WebSockets as a requirement or credentials in query strings. A future WebSocket adapter needs its own Origin checks, not an API-key direct-start shortcut.
- Existing-record issuance preserves initial values/plan. Eligible first admission of a new participant into a live call is supported by the same boundary; transferring destinations become runnable later. No caller reconnection or arbitrary participant-disconnect hangup policy.

Joining an existing call resolves its stored participant mapping, not the latest deployment.
API keys and join tokens stop at the gateway/Calls boundary and never enter engine inputs.
Emit authoritative live-start occurrence data once and hand off lifecycle projection without
waiting on a post-start database write: the later history slice fills out EctoStorage, but
failure to mark an already-running call must not tear it down or start another room now.

## Implementation checklist

- [x] Red-test preparation/token/claim workflows through ports and real adapter transaction integration.
- [x] Add prepared call, token and admission claim persistence with safe public IDs and independent lifetimes.
- [ ] Implement authenticated routes, safe response envelopes, CORS separation, and WebRTC session translation.
- [ ] Coordinate room startup and bookkeeping without spanning network work with SQL transactions.
- [ ] Update trusted samples backend setup to prepare then join; never ship its API key or initial variables to the browser.

## Acceptance and failure checks

- [ ] Prepare, wait, expire token: no process tree/start timestamp; fresh authorized issuance preserves the same record and values.
- [ ] Race same and distinct tokens: one accepted caller/startup, consumed token never becomes reusable after lost response.
- [ ] Reject cross-tenant/call/participant tokens, ended-call joining, entry override, active takeover, and browser mutations of initial values/visibility.
- [ ] Confirm five-minute/default and explicitly longer expiry with a fake clock; key revocation leaves already-issued tokens independent.
- [ ] Crash before/after claim and startup: finish known bookkeeping, preserve uncertain outcomes, clean known resources, never redial/recreate a crashed call.
- [ ] Repeat creation requests may produce separate call records; no creation-idempotency cache. Temporary transport loss is not automatically logical end.
- [ ] Change the published deployment after preparation: join uses this call's pinned mapping.
- [ ] Pre-live startup failure leaves started_at null; delayed/duplicate projection preserves
  the original live occurrence timestamp, not token claim or SQL receipt time.
- [ ] An unused/unaccepted token can retry; expiry after accepted joining does not end the call.
- [ ] Allowed/disallowed browser origins and missing/invalid credentials are independent tests;
  no CORS grant is not authorization, and no API key/token appears in engine state/events.

## Manual verification

1. Prepare through a backend with a synthetic read-only order ID; inspect that no room exists yet.
2. Pass only the returned token to the browser and join through the existing console.
3. Verify the agent reads the order while browser responses contain no preparation snapshot.
4. Repeat with expired and competing tokens, a revoked issuer key, and a newly published definition; the prepared call retains its original plan.
5. Observe started_at only at actual live start and ended_at only at logical end.

## Scope boundaries

No direct API-key media socket, HMAC payload signature, same-call caller reconnection, automatic prepared-record expiry, or general crash recovery. Exact transport end detection must be documented during implementation without assuming every participant departure ends a multiparty call.

## Completion and evidence

- [ ] Demonstrate the runnable outcome and every acceptance/failure check above.
- [ ] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [ ] Update this milestone, the index checkbox, relevant architecture/user docs, and
  implementation labnote with actual test/browser/integration evidence in the implementation commit.

Implementation evidence: database-neutral preparation, issue, and atomic-claim workflows
landed in `69019a9`. The PostgreSQL adapter adds transactional prepared-call/first-token
insertion, immutable resolved-plan reconstruction, independently expiring digest-only tokens,
and one admission per call/participant. Focused real-adapter coverage includes transaction
rollback, expired-token non-consumption, API-key revocation independence, and concurrent same-
and distinct-token claims. Gateway routes, live startup/bookkeeping, browser verification, and
the remaining failure matrix are still open; this slice is not complete.

## Specification review

Reviewed independently by milestone_review_b on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Added pinned join mapping, occurrence timestamps, pre/post-admission token semantics, credential/Origin separation and nonblocking lifecycle handoff; re-review approved.
This is specification evidence only; implementation and runtime verification remain unchecked.
