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

The first milestone checklist item remains open until the real persistence
adapter transaction is implemented and tested.
