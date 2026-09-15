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
- Implementation has not started. The current umbrella regression belongs to the preceding
  Zenmux startup correction and must finish before another Mix process runs.
- Independent design review found no further blocker after the locking and rollout corrections.
  The [durable design](../docs/platform-credential-reencryption.md) records the decision and
  rejected alternatives. This review changes no checkpoint implementation count.
