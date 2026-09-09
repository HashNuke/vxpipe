# Tenant definition storage

## Goal

Implement milestone 6 as a database-neutral Calls workflow backed by a separate
Ecto/PostgreSQL adapter: tenant bootstrap, independently revocable scoped API
keys, immutable call-definition revisions, and draft-to-published participant
routes.

## Checkpoints

- Confirmed the local PostgreSQL server is reachable. The current operating-system
  user does not yet have a matching PostgreSQL role; database setup remains for
  the persistence checkpoint.
- Added the Calls child-app/test skeleton and wrote the first externally observable
  workflow tests before production modules. These tests intentionally reference
  the not-yet-implemented administration and definition APIs.

## Decisions carried into implementation

- `vxpipe_calls` owns workflows and repository behaviours without Ecto.
- `vxpipe_persistence` will own Repo, schemas, migrations, constraints, and adapter
  transactions.
- API keys use explicit `admin` and `calls` grants, are returned only at issuance,
  and persist only a SHA-256 digest of a high-entropy random value.
- Issued-key structs implement redacted inspection so routine diagnostics cannot
  print the one-time secret accidentally. Authentication looks up the digest in
  the tenant scope and maps both missing and revoked keys to the same public
  failure.
- Saved revisions retain JSON-safe portable source plus reusable compilation
  metadata. Participant route UUIDs are deployment records, not portable JSON;
  publication makes only that selected revision's routes callable.
- A structurally valid draft may record unsupported configured features, but it
  cannot publish until those errors are cleared in a later immutable revision.

## Verification

- Red: `mix test apps/vxpipe_calls/test` failed while compiling
  `AdministrationTest` because `Vxpipe.Calls.IssuedApiKey` did not exist. This is
  the expected missing production contract, before implementation.
- An intermediate green attempt exposed two implementation defects: UUID output
  used uppercase hexadecimal and the available standard JSON module exposes
  `encode!/1`, not `encode/1`. Correcting those contracts also allowed the
  revocation assertion to exercise its intended path.
- Green: `mix test apps/vxpipe_calls/test` — 7 tests, 0 failures.

## PostgreSQL adapter checkpoint

- Added red adapter tests around the Calls ports before adding Repo, schemas,
  migrations, or adapter implementations. The tests cover hash-only storage,
  tenant-scoped lookup, independent revocation, uniqueness error mapping,
  immutable source revisions, publication, and indexed route isolation.
- Initial dependency resolution failed because the existing Membrane `ratio`
  dependency supports Decimal 1/2 while `numbers` 5.2.5 and Ecto 3.14 require
  Decimal 3. A forced Decimal override still failed Mix's dependency check. The
  compatible set is Ecto SQL 3.13.5/Postgrex 0.21.1 with Decimal 2, plus a narrow
  gateway override that holds its Membrane stack's `numbers` dependency at
  5.2.4. The full umbrella suite must prove that compatibility before this
  checkpoint is accepted.
- The first adapter run failed because a string-length validator was inappropriate
  for arbitrary 32-byte digests; it also would have mislabeled validation errors
  as uniqueness conflicts. Replaced it with an exact byte-size change validator
  and now classify only Ecto errors carrying unique-constraint metadata.
- Green adapter baseline: `mix test apps/vxpipe_persistence/test` — 5 tests,
  0 failures. SQL query logging is disabled for this Repo so credential digests
  and future sensitive parameters do not appear in ordinary query logs.
- Hardened the adapter suite with an actual supervised Repo stop/restart, route
  replacement on publishing a later revision, and explicit separation between
  public UUIDs/tenant keys and SQL primary keys.
- Green: Calls 7 tests; Persistence 6 tests; unused-dependency check passed.
- Embedded verification: from `apps/vxpipe_call_engine`, `mix test` passed 164
  tests with 2 integration tests excluded. That child has no dependency on
  Calls, Ecto, Postgrex, or Persistence and did not start the Repo.
- Local test setup created the disposable `vxpipe_test` PostgreSQL database and
  a peer-authenticated role matching the operating-system user. No database
  credential was written to source or output.
