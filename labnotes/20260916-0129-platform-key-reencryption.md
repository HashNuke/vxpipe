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

## Fresh-process retirement acceptance

- The operator CLI shipped as `19cde3a` before this acceptance. Ran a temporary Python harness
  against a uniquely named, disposable PostgreSQL database; every Mix invocation starts a new VM.
  Random platform keys stayed in subprocess environment variables; synthetic provider payloads
  and expected identities used protected stdin. Child output was captured and checked for secret
  markers without printing keys, payloads or bootstrap API keys.
- Migrated the database and provisioned three old-key Google/Deepgram credentials across two
  tenants. Staged both decrypt keys while retaining the old active key; a fresh reader verified
  exact values, identity, version and active status for every row.
- Switched the active key, provisioned one new-key Zenmux credential and verified mixed-key reads.
  Separate command VMs processed batches of one and two old-key rows, reporting remaining counts
  of two then zero. A third invocation processed zero with no remaining old-key rows.
- Removed the old key entirely. Fresh-process reads returned all four exact values, identities,
  versions and statuses. Metadata listing confirmed only the new encryption key ID remained,
  with original tenant/provider/name/auth-kind/schema version and creation timestamps preserved.
- With both key settings absent, metadata listing still worked while every credential resolution
  and even an empty re-encryption batch failed with `credential_key_unavailable`. Supplying wrong
  key bytes under the new ID made every fresh-process resolution fail with
  `provider_credential_unreadable`. Wrong bytes are a negative check, not an allowed rollout step.
- The harness passed and removed only its owned disposable database. The tagged storage suite
  separately owns revoked-row preservation, contention, concurrent writes and interrupted rollback;
  no provider requests, third-party credential rotation or broader backup drill were added.
- The common full umbrella regression is running after independent storage/CLI reviews and
  static gates. Its result remains separate from the focused encryption-key transition exit.
- Independent GPT 6 Astra xhigh reviewed the harness and checkpoint coverage without running it;
  it found no missing essential contract or scope expansion. Combined with the successful local
  execution, this closes checkpoint 6. Progress is now 4 of 7 complete (1, 2, 5, 6), 2 partial
  (3, 7), and 1 not started (4). The milestone and common umbrella gate remain unchecked.

## Full umbrella result

- Full root regression after `19cde3a`, with preloaded modules, maximum requires 1, concurrency 4
  and seed 235296: 1,564 tests, one failure, 36 excluded. MCP 37, Agent Runtime 95, Engine 697,
  Calls 81, Artifacts 20, Persistence 115 and Console 106 all pass. Gateway completes 413 tests
  with one failure in the existing native repeated-AI-transfer case at
  `human_transfer_webrtc_test.exs:214`, its listener assertion at line 355.
- The failed assertion again decoded `E ` but observed only 24 trailing-silence windows
  (26 windows total), matching the already reproduced observation in earlier credential runs.
  No audio/timing/assertion change was made in this checkpoint. The preceding full run's
  five-participant cue/conversation failure does not recur; that does not establish its cause.
- Format, warnings-as-errors compile, strict Credo and unused-lock checks pass. The shared
  umbrella gate stays open. Existing isolated reproduction already covers this unchanged failure;
  another identical isolated run would add no evidence about the credential command.
- A final production-source scope scan finds no direct OpenAI/Anthropic/OpenRouter credential
  readers, cloud/OAuth additions or old speech-profile/global-config switch readers. Existing
  Telnyx/Twilio live-reader cutover and final platform cleanup remain the authorized pending work.
- Sent the requested push notification with 4/7 complete, two partial and one not started.
  The CLI and retirement evidence shipped separately as `19cde3a` and `0933098`.
