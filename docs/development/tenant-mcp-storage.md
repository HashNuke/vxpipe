# Tenant MCP storage boundary

Status: secret-envelope foundation implemented, 2026-11-06. Persistent records,
authorized management, OAuth lifecycle and runtime consumers remain separate
checkpoints in [T4–T7](../../labnotes/milestones/integrations-directory-and-tenant-mcps.md).
The cipher is a trusted internal boundary, not a public authorization API.

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
re-encrypted or expired. Record batching, retirement checks and atomic grant
replacement are later storage/lifecycle work; this adapter does not provide them.

## Decisions and verification

Reusing the installation keyring avoids another operator key-management system.
A separate MCP AAD namespace prevents confusion with the existing provider cipher.
Reusing provider credential rows was rejected because their validation, platform
inheritance and lifecycle differ from tenant MCP connections. Plaintext credentials
and display names as durable credential identities are not accepted alternatives.

Seven focused tests cover all five identity fields, key-ID aliases, provider/MCP
namespace separation, key rotation and retirement, exact payload limits,
unsupported/oversized/truncated envelopes and redacted JSON-encoding failures.
These test project-owned envelope policies rather than the cryptographic
implementation. Authorization, database, cross-node and end-to-end acceptance
remain milestone gates. See the [review checkpoint](../../labnotes/20261106-2345-review-mcp-cipher.md).
