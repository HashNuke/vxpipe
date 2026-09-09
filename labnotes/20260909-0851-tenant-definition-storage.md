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
