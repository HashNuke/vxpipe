# Tenant MCP storage boundary

Status: encrypted tenant connection-record foundation implemented, 2026-11-07.
Authorized management, OAuth lifecycle, runtime consumers and production UI remain
separate checkpoints in [T4–T7](../../labnotes/milestones/integrations-directory-and-tenant-mcps.md).
The repository is a trusted internal port, not a public authorization API.

## Ownership and records

Calls owns `MCPConnectionRepository`; Persistence implements `MCP.ConnectionStore`.
Only tenant keys are accepted. A non-null tenant foreign key prevents platform
records. Reads select the connection ID and tenant together; there is no inherited
or application-config fallback.

`tenant_mcp_connections` stores a stable UUID, endpoint and canonical endpoint
identity, optional directory ID, server name, authentication method, configuration
generation, state, tool catalog and encrypted secret envelope. The namespace is
`mcp_` followed by the UUID without hyphens. Changing server metadata does not
rename that namespace. The repository receives already validated endpoints and
catalogs; canonicalization and protocol validation belong to the Calls/MCP boundary.

One tenant cannot create two records for one endpoint identity or directory ID.
Writes lock the tenant row before checking identity, and database unique indexes
provide a second constraint. Conflicts return an existing connection ID. If a
request conflicts with different records by endpoint and directory, the oldest
record wins deterministically; the caller must resolve the conflict rather than
merging credentials. Different tenants may use the same endpoint.

Replacement and revocation require the observed generation. A stale edit fails
without changing the working record. Replacement increments generation atomically
with its ciphertext and catalog. Revocation increments generation and erases both
secret ciphertext and catalog; private resolution returns a revoked error. The
retained identity supports explicit repository replacement with entirely fresh
secrets at the revoked generation. This preserves ID/namespace and advances the
generation again. The public Calls reconnect flow still needs an authorized
tombstone lookup; it cannot resolve or reuse the erased credentials.
Network validation must complete before the transaction; no network call belongs
under these locks.

Connected rows require non-null ciphertext and a key ID. A forward corrective
migration also tightens checkouts that already applied the preview schema; it
does not delete or rewrite rows. Rolling back that compatibility step retains the
invariant now present in the initial migration. Inconsistent existing rows fail constraint
validation and require explicit repair. Missing/stopped repositories and checkout
failures return the fixed unavailable error; unrelated programmer errors propagate.

## Secret identity and payload policy

`MCP.SecretCipher` reuses the existing `CredentialKeyring` and AES-256-GCM.
Authenticated data binds a versioned MCP namespace, key ID, tenant key, connection
ID, configuration generation, authentication method and secret purpose. Key-ID
aliases cannot substitute for one another even with identical key material.
Provider credential envelopes and MCP envelopes cannot be interchanged.

Payloads must be JSON-encodable maps. Encoded plaintext is limited to 64 KiB;
decryption rejects oversized ciphertext, unsupported versions and malformed
envelopes. Invalid input, encoding and authentication failures return fixed errors
without payload data. Missing decryption keys retain their distinct unavailable
error. The adapter does not establish tenant existence, permissions, endpoint
validity or auth-method-specific credential shape; later callers own those checks.

Rotation uses the stored key ID for decryption and the keyring's current key for
new encryption. Operators must retain old keys until dependent stores have been
re-encrypted or expired. The connection store supports bounded transactional re-encryption batches.
Operator commands, retirement checks and atomic OAuth grant replacement remain
separate checkpoints; the cipher itself does not provide them.

## Read projections and batch rotation

List/detail projections contain connection metadata and catalog snapshots, not the
secret payload. Static details require no decryption key. OAuth details optionally
include three fixed method/grant/client-authentication labels; missing keys leave
those labels unavailable. Private resolution returns a struct with opaque inspection.
SQL operations suppress bound-data logging and query telemetry.

Re-encryption uses bounded batches of 1–500 rows with `FOR UPDATE SKIP LOCKED`.
Identity/configuration generation stay unchanged; a failed row rolls back its
whole batch. Progress reports current-key and remaining-key counts. Operational
commands and cross-node rotation remain later acceptance work. Network operations
never run under database locks.

## Decisions and verification

Provider credential rows were rejected because their platform inheritance and
provider-specific validation do not describe tenant-only MCP connections. Reusing
the installation keyring avoids a second key-management system. Plaintext payloads,
display-name identity and silently creating a new identity after revocation were
rejected. Fresh, explicitly authorized restoration preserves the stable namespace.

Seven cipher tests cover authenticated identity, namespace/key-ID separation,
rotation, bounds and fixed failures. Fifteen connection-store tests cover tenant
isolation, encrypted payloads, duplicate identity, generation conflicts,
revocation/restoration, SQL constraints, outage/recovery and batch rollback.
Two tagged tests use distinct PostgreSQL connections for duplicate-create and
replacement races. These run in one BEAM; separate-node acceptance is still open.
See [cipher evidence](../../labnotes/20261106-2345-review-mcp-cipher.md) and
[storage review evidence](../../labnotes/20261107-0013-review-mcp-storage.md).
