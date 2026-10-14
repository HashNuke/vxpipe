# Clarify user access

## Scope and decisions

Track the user's tenant, Calls, users, roles and permission review in the current
Console sidebar/dashboard milestone. Remove tenant IDs from user assignments and
chooser labels, use action phrases for assigned/all-tenant permissions, and remove
role descriptions from forms, lists, APIs and storage. Services read now includes
credential metadata and masked previews; credential writes retain their own grant.

The grant migration takes the wider existing Services/credential read scope and
increments affected role revisions. It never expands write scope. Services read
across all tenants satisfies assigned-tenant write prerequisites. Splitting merged
grants on rollback cannot reliably restore original intent, so rollback is rejected.
Removing the description column discards the old text.

## Implementation and evidence

- Initial focused tests failed for old tenant labels/summaries, the description
  column, credential read authorization and the independent API-key Read checkbox.
- Updated the catalog, route checks, Calls authorization, navigation projection,
  role editor, fixtures and persistence contract together.
- Migration acceptance failed on the old narrower read scope, then passed after the
  migration: one integration test passed, four unrelated integration cases excluded.
  Dev and test databases migrated successfully.
- Frontend suite: 730 tests passed; typecheck and lint passed. Browser reviewed the
  create-user assigned/all-tenant states, role list and create-role form at desktop
  and mobile widths. Fixed Write checkbox alignment after removing API-key Read.
- Concurrent focused backend runs encountered unrelated 100ms billing/archive test
  timeouts. Billing passed on rerun. The serial full umbrella run is the final gate.
- A root-level frontend focused invocation found no tests because the root Vitest
  config only includes packages; reran from Console assets with its own config.

## Final checks

All five required root gates passed: formatting, compilation with warnings as errors,
strict Credo, 3,788 tests with zero failures (133 excluded), and unused-dependency
check. The earlier timing failures did not recur in the full run. Final frontend
permission/access checks passed 18 tests; final Calls authorization checks passed
22 tests after duplicate fixture cleanup. Final lint and diff whitespace checks
passed. This checkpoint includes implementation, migrations, tests and documentation.
