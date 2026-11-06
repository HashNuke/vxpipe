# Persist listed MCPs

## Scope and dependencies

- Builds on `5b42dfca`, which resolves public listing references through the
  existing page cache and adds credentialless listed discovery. Its full root
  suite and independent adversarial review passed before this checkpoint began.
- Before this checkpoint, connection records had a nullable directory identity but
  no accepted template snapshot. Revocation clears encrypted credentials while retaining
  identity; therefore setup configuration needed for explicit reconnection must
  be stored separately from secrets and must not depend on the public directory.
- Preserve accepted listing name, endpoint, recipe and public setup metadata
  through refresh/replacement/revocation. The future listed mutation must resolve
  references again on the backend before accepting a new snapshot.
- Added the first persistence behavior test before implementation: round-trip the
  snapshot through creation, catalog refresh, secret replacement, revocation,
  retained metadata lookup without a keyring and same-ID reconnection.

## Red/green evidence and decisions

- Initial round-trip test failed because the public record lacked `directory_entry`.
  Added private-field/inconsistent-binding and immutable-replacement tests; all
  three failed before implementation (19 tests total, three failures).
- Added a nullable public snapshot column and a closed, bounded storage validator.
  Unknown fields and inconsistent binding fail before encryption/persistence;
  accepted snapshots cannot be detached or revised during credential replacement.
- Listed identity uses `<directory-id>/<entry-id>`: two valid 64-character IDs
  require 129 characters. Existing preview identity strings and custom records
  remain valid; no data is rewritten by the additive migration.
- The accepted directory name wins over protocol-reported display names during
  creation/replacement/catalog refresh; custom behavior is unchanged.
- Read `mix help ecto.migrate`; test and development databases accepted the additive
  migration. All 19 connection-store tests pass (seed 281208).
- Broader verification and independent adversarial review results are recorded
  below. Actual listed connection creation, OAuth attempts and locked forms remain open.

## Review corrections

- Independent source review found no correctness/tenant/migration blocker. Clarified
  that storage binds the public snapshot to the outer auth method, not encrypted
  credentials to header names or OAuth registration/scopes. Resolver/protocol
  checks remain mandatory before side effects. Public metadata has repository
  immutability, not a cryptographic protection against privileged DB edits.
- Added requested regressions for the 129-character compound identity, retaining
  the snapshot/name when replacement omits it, and verifying rejected replacements
  retain the decrypted secret and observed generation.
- All 20 connection-store tests pass (seed 193771); independent correction review
  is clean. The prior full Persistence suite passed 487 tests (43 excluded), before
  the final extra boundary test. Root format/compile/Credo/unused checks pass.
- Changed documentation links and heading anchors pass validation.

## Final checkpoint verification

- Full root umbrella: **4,905 tests, zero failures, 201 excluded**, seed 371945,
  exit 0. This includes all 488 Persistence tests after the review addition.
- All five root gates pass; format/Credo were repeated after the final test edit.
- Independent adversarial review, correction review and exact nine-file staged
  review are clean. No unintended staged work or remaining scoped findings.
- No frontend or source-cutover/speech state-machine code changed; no browser or
  Lean acceptance claim is added. Overall milestone/index remain incomplete.
