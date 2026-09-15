# Platform credential re-encryption

Status: the bounded storage operation, operator CLI and fresh-VM transition are implemented and verified in
[checkpoint 6](milestones/tenant-provider-credentials-and-platform-configuration.md#checkpoint-6--rotate-the-platform-owned-encryption-key).

## Operation and ownership

The platform operator replaces the encryption key protecting stored provider credentials.
The operation preserves each tenant's actual credential value, identity, version and status.
It uses the existing Persistence `CredentialKeyring`, `CredentialCipher` and credential store.
No tenant credential-management API, scheduler or upstream key-rotation protocol is required.

Trusted host code can invoke `Vxpipe.Persistence.ProviderCredentialStore.reencrypt(context, size)`
using the configured `[repo: Repo, keyring: keyring]` context. The default batch size is 100;
accepted sizes are 1–500. Success returns `{:ok, %{processed: count, current_key_id: id,
remaining_by_key: counts}}`. An unreadable batch returns a safe error and commits no updates.
The operator command uses this same operation and the configured platform keyring:

```shell
mix vxpipe.provider_credential.reencrypt --batch-size 100
```

It prints JSON containing only `processed`, `current_key_id` and `remaining_by_key`.
Repeat until `remaining_by_key` is empty; a busy batch may process zero rows while work remains.
Invalid arguments fail without echoing their values. Supply no provider credentials to this command.

Each operator invocation processes a bounded batch of rows encrypted with an older key.
Validate the current key even when no rows need work. Include revoked rows so removing an old
encryption key leaves no stored payload behind; re-encryption does not make revoked credentials
available to runtime readers. Decrypt using the locked row's original authenticated identity,
then encrypt the same payload under the current key. Update only the encrypted payload,
encryption key ID and update timestamp.

## Transactions and progress

Lock only candidate credential rows with `FOR UPDATE ... SKIP LOCKED`. Existing active-reader
guards acquire multiple credentials in provider/name order, so waiting while holding an arbitrary
batch in primary-key order can deadlock. Do not lock joined tenant rows; service guards already
hold tenant/service locks before reading credentials.

Make each batch atomic. An unreadable row or interruption rolls back that batch; previous
successful batches remain committed. Retry selects the remaining old-key rows without a separate
cursor or job subsystem. Report processed counts, the active key ID and remaining counts by old
key ID. Remaining counts include busy rows skipped by the lock: zero processed rows is not
completion while any old-key row remains.

Disable SQL logging and query telemetry as existing credential storage does. Command output
contains no payload or ciphertext. The argument parser accepts only the bounded batch-size
option and never echoes supplied invalid values, including accidental secret flags.

## Operator transition

1. Add the new decrypt key to every live reader while keeping the old active write key.
2. Switch every writer to the new active key ID, retaining both decrypt keys.
3. Run bounded batches and retry incomplete work until no old-key rows remain.
4. Remove the old key and restart with the new key only; verify credential reads.

Runtime repository contexts capture their keyring. Updating only the CLI environment does not
update other running VMs. A zero-remaining report cannot prevent a separately running writer
with the old configuration from creating another old-key row; complete the writer transition
before treating that report as permission to retire the key.

## Verification and rejected alternatives

Focused tests must cover mixed keys and tenants, revoked records, exact plaintext preservation,
bounded retry, rollback on a later unreadable row, unavailable/wrong keys and private output.
Tagged tests with separate database connections must cover contention, skipped-row progress and
concurrent writes. A disposable database across fresh VMs must prove mixed-key reads during the
transition and new-key-only reads afterward. Six focused database tests and three tagged
transaction tests pass. The latter hold active-reader locks on separate connections, interrupt
a batch after its first write, and provision a new-key credential for the same tenant while
re-encryption is paused. They also verify a concurrent status update survives skipped-row retry.
Three operator tests verify bounded retry, safe output, rejected arguments and unavailable keys or
storage. Disposable database acceptance across fresh Mix VMs verifies staged decrypt keys,
mixed-key reads, new-key writes, resumed batches and new-key-only reads after old-key removal.
Exact tenant payloads and public identities/versions/status remain unchanged. Missing/wrong-key
reads fail safely; metadata remains available without keys. The full Persistence suite passes
115 tests (9 excluded), and independent storage, CLI and exit reviews found no blockers.

Replacing key bytes under an existing ID, changing tenant credential versions, migrating only
active rows, relying on a batch cursor, or adding another key-provider framework would violate or
unnecessarily expand this operation. Reuse the existing storage boundary and immutable key IDs.
The [design review labnote](../labnotes/20260916-0129-platform-key-reencryption.md) records the
locking finding, rollout requirements and planned verification.
