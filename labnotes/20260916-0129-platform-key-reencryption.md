# Platform key re-encryption

## Scope and existing foundations

- Checkpoint 6 changes only the platform-owned encryption key. Tenant API-key values,
  credential identity/version/status and existing provider authentication shapes stay unchanged.
- `CredentialKeyring` already supplies one active write key and old decrypt keys;
  `CredentialCipher` authenticates the key ID and exact credential identity. Reuse both.
- Keep the operation in Persistence, alongside encrypted storage and operator Mix tasks.
  It is a platform storage operation, not a new tenant credential-management workflow.

## Bounded operation design review

- Proposed operator invocation processes at most a configured batch of old-key rows, preserving
  identity/version/status and rewriting only encrypted payload, encryption key ID and update time.
  Include revoked rows so retiring an old encryption key does not leave encrypted data behind.
- Reuse the store's private metadata/decryption path on locked rows; public resolution rejects
  revoked credentials and therefore is not suitable for this operation.
- Independent GPT 6 Astra xhigh review caught a deadlock risk in naive primary-key-order locking:
  existing active readers acquire multiple credentials in provider/name order. A rotator must not
  hold one exclusive credential lock while waiting for another held by such a reader.
- Use credential-only `FOR UPDATE ... SKIP LOCKED` selection. Do not lock joined tenant rows:
  service guards already hold tenant/service SHARE locks before credentials. Skip busy rows and
  report all remaining old-key rows, including skipped ones. Processing zero rows with nonzero
  remaining rows is not completion. Verify this with separate database connections.
- Make each bounded batch atomic. A failed payload or interruption rolls back that batch;
  successful prior batches remain committed, and retry selects the remaining old-key rows.
- Return only processed counts, the active key ID and remaining counts by old key ID. Disable
  query logging and query telemetry, as ordinary credential storage already does.
- Stage the new decrypt key on every live reader while retaining the old active key, then switch
  every writer to the new active ID before re-encryption. Runtime repository contexts capture their
  keyring; changing only the CLI environment does not update other VMs. Retire the old key only
  after all writers have switched and no old-key rows remain.
- The generic CLI argument parser echoes invalid values. Use a strict sanitized parser for the
  bounded batch-size flag so an accidentally supplied key/secret flag is not repeated in output.

## Planned verification

- Add focused red tests before implementation: mixed old/new and active/revoked rows, exact
  tenant plaintext/identity preservation, batch limits/retry, rollback on unreadable payload,
  missing/wrong keys, safe progress and no secret-bearing query events.
- Add tagged real-connection contention checks for skipped busy rows, concurrent status/writes
  and retry. Reuse the existing transaction test setup and keep default tests isolated.
- Exercise a disposable DB in fresh VMs: old-key provisioning, mixed-key transition, resumed
  batches, new-key-only restart/read, missing/wrong-key rejection and cleanup.
- Implementation has not started. This design review ran while the preceding Zenmux startup
  correction's umbrella regression was in progress; no second Mix process ran alongside it.
- Independent design review found no further blocker after the locking and rollout corrections.
  The [durable design](../docs/platform-credential-reencryption.md) records the decision and
  rejected alternatives. This review changes no checkpoint implementation count.

## Storage implementation

- Started implementation from clean `d795ec1`. The previous turn made progress with Telnyx guards,
  the Zenmux public-startup correction and verification commits. No genuine blocker prevents this
  independently runnable platform storage checkpoint.
- Added six focused tests before implementation. Corrected a test-helper name colliding with
  Ecto's `update` macro, then confirmed all six fail because the re-encryption operation is absent.
- Implemented `ProviderCredentialStore.reencrypt/2`: default batch 100, maximum 500, credential-only
  `FOR UPDATE ... SKIP LOCKED`, existing payload validation/crypto and an atomic transaction.
  Only payload/key ID and the ordinary update timestamp change. All six focused tests pass.
- Added real-connection acceptance for active-reader contention and interruption after one row
  has been rewritten. The interrupted batch also permits a concurrent new-key credential insert
  for the same tenant, proving that re-encryption does not exclusively lock its tenant row.
  Corrected a nonexistent `Process.fetch!` call in the test-only pause adapter to `Process.get`;
  this was a fixture error, not a storage defect.
- Added a third real-connection case for a concurrent status update: the batch skips the held
  row, reports it remaining, and retry preserves its revoked state and exact plaintext.
- Final focused group: 9 tests, zero failures. The broader Persistence suite passes 112 tests,
  zero failures, 8 excluded before the third tagged case was added. Format, warnings-as-errors
  compilation and strict Credo pass. Independent GPT 6 Astra xhigh code review and focused
  re-review found no blockers. The operator CLI and fresh-VM retirement checks remain pending.

## Operator command

- Storage shipped separately as `7c61680` before adding the CLI. The command runs one bounded
  batch using the configured store/keyring and prints only progress counts and key IDs.
- Added three focused operator tests first and confirmed all fail because the task is absent.
  Implemented the strict sanitized argument parser and command; all three then pass. Tests cover
  resumption, preserved payloads, invalid secret/batch arguments and unavailable keys or storage.
- Independent GPT 6 Astra xhigh review found no blockers. The command introduces no provider
  authentication support; the latest user clarification remains consistent with the closed
  existing-provider inventory and milestone exclusions.
- The full Persistence suite passes 115 tests, zero failures, 9 excluded. Formatting and
  warnings-as-errors compilation pass. The task's help lookup initially used the old development
  build and could not find the new command; after compilation, the help output is available and
  matches the documented arguments and operator rollout order.
- Operator documentation now includes the command, bounded retry, remaining-count completion
  rule and staged reader/writer transition. Fresh-VM retirement acceptance remains pending.
- Strict Credo and the unused-lock check pass. All 176 relative documentation links and anchors
  across the changed documents pass verification. The common full umbrella gate stays open
  pending a root run after this checkpoint; earlier native audio failures remain unresolved.
