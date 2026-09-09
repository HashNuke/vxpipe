# Prepared-call admission

## Objective

Implement the prepared-call admission milestone: authenticated backend preparation
persists a pinned call plan and private initial variables, then an opaque,
participant-bound, single-use token admits the browser through the existing WebRTC
transport and starts the call exactly once.

## Initial inspection

- `Vxpipe.Calls` already owns database-neutral tenant authentication and immutable
  definition/route workflows through repository ports.
- `Vxpipe.Persistence` implements those ports with Ecto transactions and keeps the
  call engine database-free.
- The gateway currently creates a trusted call before issuing an in-memory
  `Vxpipe.Gateway.Session`; Small WebRTC atomically claims that session before
  starting a connection.
- The durable design requires a prepared-call/token repository port and Calls
  workflow, followed by a gateway adapter that turns an accepted admission into
  the existing transport binding. API keys and token secrets stop at that
  boundary.

## Checkpoint plan

1. Red-test and implement database-neutral prepare, issue, and atomic-claim
   workflows with a controllable clock and repository double.
2. Add Ecto records and the short transactional claim implementation, including
   concurrency and restart coverage.
3. Add authenticated tenant routes, CORS separation, and WebRTC startup handoff.
4. Exercise the browser sample and failure cases, then update durable docs and
   milestone evidence.

## Checkpoint 1: database-neutral preparation and claim

The first focused test run failed with six expected `UndefinedFunctionError`
failures because the call repository and admission facade did not exist. The
implemented Calls boundary now:

- resolves only a published tenant route and immutable revision;
- requires the preparation route to identify `entry_caller`;
- validates supplied initial values while allowing declared sections to remain
  empty;
- compiles one plan with stable call, room, actor, participant, and activation
  identities, then stores that exact plan and a SHA-256 plan digest;
- stores the prepared call and first token through one repository operation;
- stores only a SHA-256 token digest while returning the opaque token once;
- uses a five-minute default and accepts an explicitly longer lifetime;
- atomically consumes a token only when its expected tenant/call/participant
  scope and shared admission eligibility still match.

Private initial values and token plaintext are excluded from struct inspection.
The in-memory repository double serializes competing claims and records one
accepted admission per call/participant.

The broader Calls test found an intermittent existing contract mismatch: a
96-bit base64url tenant key may begin with `-` or `_`, while the call-engine
identifier validator previously required an alphanumeric first character. A
focused compiler regression test failed for both legal leading characters; the
validator now accepts all URL-safe identifier characters in every position.

Verification so far:

- Red: `cd apps/vxpipe_calls && mix test test/vxpipe/calls/admissions_test.exs`
  — 6 tests, 6 expected failures at the missing repository/API boundary.
- Red: `cd apps/vxpipe_call_engine && mix test
  test/vxpipe/call_engine/call_definition/compiler_test.exs` — 10 tests, 1
  expected failure for a URL-safe leading tenant-key character.
- Green: the focused compiler suite — 10 tests, 0 failures.
- Green: the complete `vxpipe_calls` suite — 13 tests, 0 failures.
- `mix compile --warnings-as-errors` passed after the admission modules were
  added.

At that checkpoint the first milestone checklist item remained open pending the
real persistence adapter transaction below.

## Checkpoint 2: PostgreSQL preparation and atomic claim

The Ecto adapter introduces three normalized records:

- `calls` holds the durable identity, exact definition revision, private initial
  variables, serialized resolved plan and digest, room identity, lifecycle state,
  and distinct creation/start/end timestamps;
- `join_tokens` holds only a SHA-256 digest plus participant scope and an
  independent issue/expiry/consumption lifetime;
- `call_admissions` records the accepted token and enforces one admission for a
  participant definition within a call.

Preparation uses one `Ecto.Multi`, so a first-token uniqueness failure rolls the
new call back. Issuance and claiming lock the call row in short transactions.
Claiming additionally locks the token row, rechecks URL scope, expiry, call state,
route-to-participant mapping, and existing admission before consuming the token.
The transaction ends before any engine/provider work exists.

The plan is encoded as a deterministic Erlang external term and decoded with
`:safe`; this preserves the exact resolved profiles, runtime identities, tool
bindings, validators, and initialized variables selected at preparation. The
call row separately pins the immutable definition revision and SHA-256 plan
digest. Both the domain and Ecto structs exclude variables/plan bytes from
ordinary inspection.

An initial green attempt exposed misuse of string-length validation for arbitrary
32-byte digests: whether a random digest passed depended on UTF-8 validity. The
changesets now validate byte size, matching the PostgreSQL octet-length
constraints. A second green attempt exposed a selection tuple mismatch while
rehydrating the definition relation; the adapter now consistently carries tenant,
definition, and revision records.

Verification:

- Red: `cd apps/vxpipe_persistence && mix test
  test/vxpipe/persistence/call_store_test.exs` failed at the missing Ecto schemas
  and adapter boundary.
- Green: the focused call-store suite — 5 tests, 0 failures.
- Green: the complete `vxpipe_calls` suite — 13 tests, 0 failures.
- Green: the complete `vxpipe_persistence` suite — 13 tests, 0 failures.
- `mix format --check-formatted` and `mix compile --warnings-as-errors` passed.
- A disposable empty PostgreSQL database migrated from the full migration chain
  and ran the 5 focused call-store tests with 0 failures; it was then removed.

The managed runtime now configures `Vxpipe.Persistence.CallStore` as the Calls
repository whenever `VXPIPE_DATABASE_URL` enables persistence. The first two
milestone implementation checklist items are complete. Gateway authentication,
session translation, live-start bookkeeping, and browser verification remain.

## Checkpoint 3: authenticated routes and live startup handoff

The reusable gateway now mounts the three approved routes:

- backend-only API-key preparation;
- backend-only existing-call token issuance;
- CORS-enabled browser session admission with the single-use token.

Preparation accepts only `initial_variables` and an optional token lifetime of at
least the five-minute default. Token issuance accepts only that lifetime. Session
admission accepts no body fields, so a browser cannot replace variables or tool
visibility. Both credential types use the `Authorization: Bearer` header; query
credentials are rejected. Safe responses omit initial variables, plan data, token
digests, API keys, and the consumed token from the live session response.

The CORS Plug recognizes backend-only route shapes before applying CORS. Their
preflights fall through to a normal 404 with no access-control grant, while the
participant session and RTVI signaling routes retain configured-origin handling.
CORS remains independent of authentication.

After the short database claim returns, `Vxpipe.Gateway.CallAdmission` starts the
already-pinned plan through the call engine and obtains the existing entry-caller
participant. The handler then issues the established in-memory Small WebRTC
session. It hands the authoritative post-start occurrence timestamp to a named
supervised task for lifecycle projection. Projection failure does not change the
successful session response or tear down the room. A known pre-live startup
failure is projected as a bounded internal reason and returns a generic error;
the consumed token is not restored.

Starting the room and obtaining participant/session metadata are separate
boundaries. A focused regression exposed that collapsing both failures would
incorrectly mark an already-live room as a failed call start. The production
adapter now returns an explicit post-start outcome when participant lookup
fails. The handler projects the authoritative room incarnation and start
occurrence, returns a generic session-start error, and never projects a terminal
failure for that live call.

Lifecycle projection added after the storage checkpoint is deliberately separate:
an additional migration stores room incarnation and bounded terminal reason.
`mark_call_started` preserves the first occurrence timestamp and incarnation on
duplicate delivery, while `mark_call_failed` retains a null start time and records
the logical failure end. Both verify the accepted admission and use their own
short row-locking transactions.

Red/green evidence:

- Red: the Calls lifecycle test had 2 expected failures at the missing
  `mark_call_started` / `mark_call_failed` facade.
- Green: the Calls admission suite — 8 tests, 0 failures.
- Red: the gateway route suite first failed at the absent Calls dependency and
  route implementation.
- Red: the post-start participant/session regression failed with an unhandled
  `{:started, room}` outcome after the fake backend made the live boundary
  observable.
- Green: the focused gateway admission suite — 10 tests, 0 failures.
- Green: full suites: Calls 15, Persistence 15, Gateway 62 (4 integration tests
  excluded), Console 20; all had 0 failures.
- `mix format --check-formatted` and `mix compile --warnings-as-errors` passed.
- A new disposable PostgreSQL database migrated through all three migrations
  and ran the 7 focused call-store tests with 0 failures; it was then removed.

Managed development configuration enables these routes when
`VXPIPE_DATABASE_URL` is present; otherwise the existing database-free trusted
sample remains available. The sample itself still uses the older trusted route
and is the final implementation checkpoint for this milestone.

## Checkpoint 4: managed sample and acceptance audit

The Console now supervises a development-only `SampleCall` process when
PostgreSQL is configured. On BEAM startup it uses public Calls workflows to
bootstrap a fresh tenant and calls-scoped API key, save and publish the configured
sample definition, and retain the entry-caller route. PostgreSQL stores only the
key digest. The issued plaintext key and configured initial variables remain in
the process's inspect-redacted state and are never returned by its controller.
Backend exceptions become a bounded unavailable result without crashing the
process.

Each `POST /sample/calls` authenticates with that private key and prepares a new
durable call. Its safe response contains only the public tenant/call/participant
locator plus opaque join token and expiry. The React creation page then presents
the token to the normal tenant participant-session route with an empty body. A
404 from the managed sample endpoint selects the existing database-free trusted
room fallback, so persistence remains opt-in and embedding development stays
runnable.

The first live development check caught an invalid sample-definition shape:
tool visibility had initially been nested under a proposed client object. Moving
the already-approved `tool_visibility` field to the definition root made the
trusted configuration publishable. A disposable database then demonstrated the
complete real adapter path: the call remained prepared with a null `started_at`
after `/sample/calls`, became running only after token admission, and returned a
joined Small WebRTC participant without returning the consumed token.

The acceptance audit also found that the gateway always called full plan startup,
even when storage accepted the first admission of another participant into an
already-running call. A route test failed on the previously unhandled joined
outcome. The production admission adapter now constructs the pinned participant's
protocol-neutral join command and admits it beneath the persisted room incarnation.
It preserves the call's original `started_at`, never reruns room startup, and does
not project the existing call as failed if that participant cannot start. Direct
adapter/engine and PostgreSQL tests prove both halves of that boundary.

Additional acceptance coverage now verifies all three URL scope components,
ended-call rejection without token consumption, changed published revisions after
preparation, allowed and disallowed browser origins, missing and invalid credentials,
and credential/CORS independence. The prepared record continues to carry its exact
revision-one plan after revision two is published.

Red/green and runtime evidence for this checkpoint:

- Red: the focused Console contract suite had 3 expected failures before the
  managed sample process/controller existed.
- Red: the React suite had 3 expected failures before the two-request managed
  admission flow replaced its direct call.
- Red: the existing-live-call gateway test failed on the unhandled `{:joined,
  participant}` outcome before the engine join path was added.
- Red: forcing the sample backend to raise terminated the process before exception
  containment was added; the regression now keeps it alive and reports unavailable.
- Green: focused Calls admission — 10 tests; persistence call-store — 9 tests;
  gateway admission/adapter — 14 tests; Console sample/endpoint — 12 tests; and
  React assets — 4 tests, all with 0 failures.
- A real disposable PostgreSQL database migrated through the full chain and a live
  HTTP flow produced `prepared -> running`, one joined participant, and no exposed
  token in the live response; the database was then removed.
- Chromium inspection at 1440×1000 and 390×844 exercised **Create room** through
  the real managed flow. The existing creation screen and responsive Voice UI Kit
  console rendered without overflow or added chrome, so no visual redesign was
  needed. Browser artifacts were kept outside the worktree.

Final gates:

- `mix format --check-formatted`, `mix compile --warnings-as-errors`, and
  `mix deps.unlock --check-unused` passed.
- The complete umbrella passed: call engine 165, Calls 17, persistence 17,
  gateway 66, and Console 25 tests, all with 0 failures; 2 call-engine and 4
  gateway network/provider integration tests remained excluded by default.
- One prior umbrella run exposed the existing 100 ms model-timeout observer test
  as scheduling-sensitive: it received the expected capability timeout but missed
  the observer assertion under suite load. The exact test passed immediately in
  isolation with the same seed, and the subsequent complete umbrella run passed.
  No production behavior or unrelated test timing was changed in this milestone.
- `mix assets.test` passed 4 tests; TypeScript checking and the esbuild asset build
  passed.
- A fresh disposable PostgreSQL database ran the complete three-migration chain
  and all 9 call-store tests, then was explicitly removed.

Milestone 7 is complete. The managed sample preserves the established frontend
design, and the `impeccable` hardening pass influenced only error/fallback and
responsive verification rather than adding new interface chrome.
