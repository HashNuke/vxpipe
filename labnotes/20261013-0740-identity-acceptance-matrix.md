# Identity acceptance matrix

This checkpoint adds focused acceptance coverage for the authentication store and for migration from pre-authentication installations. It does not mark the entire console authentication milestone complete.

## Behavior and decisions

- Session issuance and authentication require the singleton authentication installation row to exist, have a valid state, and be complete. An absent singleton denies both paths. The initial missing-singleton test failed before the guard was added, then passed.
- Concurrent attempts to demote the final two Superadmins are tested against the real PostgreSQL store; exactly one succeeds and one Superadmin remains. Duplicate email checks use the normalized address. Retrying first-run setup after a lost response returns `already_completed`, while the original account remains usable after a new BEAM starts.
- The migration lane creates unique disposable databases. Fresh, tenant-only, and populated pre-authentication databases are migrated independently. The populated case checks that the tenant, demo setup, tenant API key, operator key, call spec, and legacy challenge row survive migration. The tenant-only and populated cases require trusted setup proof.
- A separate long-lived BEAM authenticates a session before another BEAM revokes its user sessions in the same disposable database. The original BEAM receives an explicit `AUTH` command and denies that session after revocation. The bearer token remains inside the long-lived BEAM and is never printed or passed to another process.
- Legacy operator challenge rows remain in the database; their route is retired. This acceptance lane tests preservation rather than deleting old rows during migration.

## Verification

- `cd apps/vxpipe_persistence && mix test test/vxpipe/persistence/identity_acceptance_test.exs`: 4 tests, 0 failures.
- Focused Persistence authentication files: 48 tests, 0 failures.
- `cd apps/vxpipe_persistence && mix test --include integration test/integration/identity_migration_acceptance_test.exs`: 4 tests, 0 failures, including cross-BEAM revocation.
- `cd apps/vxpipe_persistence && mix test --include integration test/integration/identity_migration_acceptance_test.exs:93`: focused cross-BEAM test, 1 test, 0 failures after warning cleanup.
- Integration tests use `createdb`/`dropdb` on uniquely named databases and do not alter the shared test database. No disposable database was left after the complete run.

The broader umbrella completion checks and UI review are tracked by the milestone owner.
