# Scoped provider inheritance

- User authorized the complete platform/tenant services plan, with vertical checkpoints
  and pushnotify progress reports. Initial push notification succeeded.
- Preserved the uncommitted setup-navigation cleanup from the preceding task.
- Reviewed the plan, milestone order, credential storage/readers, operator authority
  and existing encryption context. Split delivery into four runnable checkpoints in
  the plan and synchronized the bootstrap milestone/index without marking work complete.
- Checkpoint A starts with persisted platform ownership and explicit tenant policies.
  Existing tenant IDs and version-1 ciphertext must remain valid; platform ownership
  must use a distinct authenticated context. Call tenant identity remains the consumer.

## Evidence

- Red: the first inherited-provider test failed with `invalid_tenant_key` for a
  platform owner. Implemented tagged owner metadata, nullable platform ownership
  with SQL check/unique constraints, migration backfill of explicit tenant override
  policies, and the shared resolver used by ordinary reads and final write guards.
- Platform ciphertext uses a distinct version-2 authenticated context; tenant
  ciphertext retains the existing version-1 context. Re-encryption includes both.
- Red: disabled/restore policy test failed because the policy operation did not
  exist. Added serialized policy writes with a tenant-row lock shared by protected
  readers. Missing/revoked overrides never consult platform credentials.
- Green: scoped-provider, original credential-store, re-encryption and inline voice
  files pass together: 39 tests, zero failures, 2 excluded (seed 342087).
- Implementation barriers: Ecto requires literal lock clauses; used a closed mapping.
  The tamper test needed an explicit forced changeset update to restore ciphertext,
  since restoring a stale struct's original value otherwise emits no SQL change.
- Push notification sent with these results. Checkpoint A remains incomplete:
  preparation pinning, operator API flow and broader migration/concurrency evidence
  are still being implemented.

## Preparation and review

- Added safe credential owner/ID pins to newly prepared plans and final transaction
  guards. Fresh model/STT/TTS destination readers reject scope rebinding; speech
  cache identity includes the selected credential and version. The old-plan codec
  accepts stored plans without the new field. Already initialized clients retain
  their private snapshots.
- Red: the persisted inherited voice test lacked preparation pins; the legacy
  codec test lacked the new default; equal-payload platform/tenant speech assets
  shared a cache identity. The corresponding focused tests are green.
- Added the protected, named platform credential creation endpoint. Its initial
  test failed with 404. The final endpoint suite passes 7 tests, including real
  CSRF enforcement and safe responses. ConnTest normally skips CSRF; the regression
  explicitly removes that bypass and retains the page response's session cookie.
- The user requested review before committing and then requested checkpoint
  commits. Reviewed and committed the preceding navigation cleanup separately.
  Backend review reproduced two issues before fixing them: platform replacement
  metadata incorrectly matched a tenant key, and the engine accepted a foreign
  tagged owner whose consumer matched. Both now fail safely where appropriate.
- Green: Calls operator tests pass 18 tests (seed 918758); engine credential and
  destination tests pass 7 tests (seed 851868), including model/STT/TTS rebindings.
- The explicit database integration lane passes both transaction tests (seed
  546811). Separate connections cannot change tenant policy or revoke the selected
  platform credential while the authorized write is held; both become writable
  after completion. No timing sleeps or live provider requests were used.
- Root format, warnings-as-errors compile and strict Credo pass. Full umbrella
  tests and disposable-database migration/restart acceptance are running before
  the checkpoint is marked complete or committed.
- Disposable database acceptance passed: create through the previous migration,
  insert a version-1 tenant credential, upgrade, compare ID and ciphertext digest,
  decrypt and verify explicit override; roll back and upgrade again with identical
  results. Provision platform credentials, resolve in a fresh VM, disable and verify
  in another VM. Rollback with scoped configuration is rejected atomically and
  leaves the disabled policy intact. The owned database was removed. Script/output
  remain under ignored `tmp/scoped-provider-migration.py` and
  `tmp/scoped-services-migration.log`.
- The first umbrella run exposed a Twilio decoder preparation failure outside the
  changed credential path. Investigating this gate before committing the checkpoint;
  the result is not being reported as a passing suite.
- Following the user's request for small reviewed commits, split Console delivery
  into B1 (platform save/edit and tenant inheritance) and B2 (tenant exceptions and
  restore). Each is an end-to-end flow. Updated the linked checkpoint counts;
  no subsequent implementation starts before A is committed.
- The first full run finished with 1,733 tests, one failure and 40 exclusions
  (seed 772211, concurrency 16). All credential-owning application suites passed.
  Gateway's real Twilio decoder startup took seconds before its one-second
  preparation call failed. The entire affected file then passed independently:
  13 tests with the same seed. Re-running all umbrella tests at concurrency four
  without simultaneous migration VMs to verify the suspected scheduling pressure.
- The bounded run exposed two native output-pipeline readiness timeouts. A
  separate fixture checkpoint increases only initialization deadlines; all 17
  focused pipeline/ingress tests pass. The subsequent umbrella run passes those
  tests but fails Twilio phone-transfer source recovery: 1,733 tests, one failure,
  40 exclusions, seed 772211. Every credential-owning application's suite passes.
- The original failing Twilio recovery scenario passes in isolation (one selected
  test, 12 excluded, same seed). An experiment waiting for the earlier connecting
  acknowledgement did not confirm the unfinished-speech hypothesis and was removed.
  There is no production recovery fix or confirmed root cause yet.
- Final checkpoint review: corrected platform replacement owner matching and
  rejected malformed/foreign engine owners, each with a regression test. Reviewed
  migration ownership, encrypted contexts, transactional policy locks and prepared
  binding checks. Format, warnings-as-errors compilation, strict Credo and unused
  dependency checks pass. The complete umbrella test gate remains open.
- Per the user's request to avoid an accumulating review diff, commit the runnable
  backend checkpoint with this verification limitation explicit. A remains
  unchecked in the plan until the umbrella gate passes; the next feature slice
  has not started. Notification reports the same distinction.
