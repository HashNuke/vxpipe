# Tenant provider credential storage

Trusted operators can provision Google, Deepgram, Zenmux and Telnyx API keys in PostgreSQL and list their
metadata through the [tenant provider milestone](milestones/tenant-provider-credentials-and-platform-configuration.md).
Inline Google/Deepgram/Zenmux definitions now resolve this store at save, publication, preparation
and capability creation; see [inline selections](inline-provider-selections.md). Telnyx credential
provisioning and trusted service registration are available; live carrier DB readers remain checkpoint 3 work.

## Configure and provision

The visible root file [`env.sample`](../env.sample) catalogs platform configuration. Provision
the encryption variables through the host's secret/configuration boundary before starting Mix:

- `VXPIPE_CREDENTIAL_KEY_ID`: the immutable ID of the current encryption key.
- `VXPIPE_CREDENTIAL_KEYS`: a JSON object mapping key IDs to base64-encoded, independently
  generated 32-byte random keys. Supply the current key and any older keys needed by stored rows.

There is no generated or built-in default encryption key. Omitting both variables permits
credential-free operation and metadata listing; provisioning and resolution fail without the
needed key. Partial or invalid configuration fails startup with variable names only. Never
replace key bytes under an existing ID. Losing the keys makes encrypted rows unrecoverable.
Test configuration ignores these host encryption variables and injects isolated test keys.

For this intermediate implementation, the current database variables remain
`VXPIPE_DATABASE_URL` and `VXPIPE_DATABASE_POOL_SIZE`. Development defaults to the local
`vxpipe_dev` database and pool size 10. The milestone's `VXPIPE_DB_URL` / `DATABASE_URL` and
pool aliases will replace these names in the platform cutover. Operator commands and server
startup do not require global provider keys or development profile switches.

Follow [tenant setup](tenant-control-plane.md) to create/migrate PostgreSQL and bootstrap a
tenant. Then provision using JSON supplied by a secret manager pipe or a protected file:

```shell
mix vxpipe.provider_credential.provision \
  --tenant TENANT_KEY --provider google < path/to/protected-google.json
mix vxpipe.provider_credential.provision \
  --tenant TENANT_KEY --provider deepgram < path/to/protected-deepgram.json
mix vxpipe.provider_credential.provision \
  --tenant TENANT_KEY --provider zenmux --name router < path/to/protected-zenmux.json
mix vxpipe.provider_credential.provision \
  --tenant TENANT_KEY --provider telnyx --name support-phone < path/to/protected-telnyx.json
mix vxpipe.provider_credential.list --tenant TENANT_KEY
```

The input shape is `{"api_key":"REPLACE_WITH_PROVIDER_KEY"}`. These providers currently support
only `api_key` auth; additional fields, unsupported auth kinds, empty values, whitespace and
control characters fail local validation. Telnyx keys are limited to 4,096 bytes to match the
existing carrier configuration boundary; Google/Deepgram/Zenmux keys use an 8,192-byte limit.
Zenmux uses one API key even when its model path or native routing names downstream providers.
Direct authentication with those providers is not implied by a Zenmux selection.
Telnyx connection IDs and verification public keys belong to [service metadata](tenant-telephony-services.md),
not this payload. Trusted service registration now links the public credential ID to the matching
tenant/provider; Gateway live-reader migration remains pending.
Input is limited to 16,384 bytes. The reader uses
Elixir `IO.read/2` with a bounded character count and a separate byte-size check. Only terminal
detection uses OTP `:io.getopts/1`, since Elixir has no equivalent wrapper. Its `stdin` flag
describes the input stream; `terminal` describes stdout, which can still be a terminal when
input comes from a pipe. Interactive stdin is rejected before requesting the payload. See the
[OTP I/O protocol](https://www.erlang.org/doc/apps/stdlib/io_protocol.html).

`--name` defaults to `default`; `--auth-kind` defaults to `api_key`. The binding is unique per
tenant/provider/name, and provisioning a duplicate fails without overwriting it. Commands
return credential ID, tenant, provider, name, auth kind, status, versions, encryption key ID and
timestamps. They do not print the payload. Invalid arguments are reported without echoing raw
values. Secret flags and arbitrary auth-file fields are unsupported.

These commands and `Vxpipe.Calls.ProviderCredentials` are trusted host operations. Possession of
a tenant key alone does not authorize an untrusted user to invoke them. A future tenant-facing
management endpoint must enforce its own authenticated tenant/admin boundary.

## Run the development sample

Set `VXPIPE_DEV_TENANT=TENANT_KEY` alongside the platform keyring and database settings,
then run `bin/dev` (which loads `.env`) or `mix run --no-halt` (which uses exported variables).
The Console saves and publishes its inline Google/Deepgram definition for that tenant,
then issues a server-held call-scoped API key. It does not create another tenant on restart
or copy provider keys from the environment. Without a selected tenant the managed sample
is disabled; missing or unreadable bindings prevent sample setup and call creation.

## Replace the platform encryption key

Use the existing `VXPIPE_CREDENTIAL_KEY_ID` and `VXPIPE_CREDENTIAL_KEYS` settings. Stage the
new decrypt key on every reader, then switch every writer to that new active key while retaining
both keys. Run `mix vxpipe.provider_credential.reencrypt --batch-size 100` repeatedly until
`remaining_by_key` is empty. The accepted batch size is 1–500; the default is 100.

A failed batch commits no updates; successful earlier batches remain committed. Busy rows remain
in the reported counts, so zero processed rows alone does not mean completion. Once all writers
use the new key and no old-key rows remain, remove the old key and restart. Each tenant's actual
provider credential, identity, version and status stays unchanged. See the
[operator transition](platform-credential-reencryption.md#operator-transition) for rollout details.

## Storage decision

`vxpipe_calls` owns validation, metadata, workflows and the repository port.
`vxpipe_persistence` owns encrypted storage, platform key parsing, Ecto and operator Mix tasks.
The engine and gateway do not depend on the Repo. Vxpipe API keys retain their separate one-way
SHA-256 storage and are never accepted as recoverable provider payloads implicitly.

Each credential row has a public ID, tenant foreign key, provider/name/auth kind, active/revoked
status, credential version, payload schema version, encryption key ID and encrypted JSON.
`CredentialCipher` uses OTP AES-256-GCM with a random 12-byte nonce and 16-byte authentication
tag. The version-1 envelope is one version byte, the nonce, the tag, then ciphertext.
Authenticated associated data is the ordered JSON array of:

1. `vxpipe/provider-credential/aes-256-gcm/v1` (domain/version marker).
2. Tenant key, credential public ID, provider, binding name and auth kind.
3. Credential version, payload schema version and encryption key ID.

This binds encrypted data to its exact owner and identity. Copying another row's ciphertext or
changing authenticated identity/version metadata fails decryption. OTP owns the cryptographic
primitive; project tests cover the binding and failure behavior at the repository boundary.
See [OTP authenticated encryption](https://www.erlang.org/doc/apps/crypto/crypto.html).

Resolution joins the tenant and exact provider/name, checks active status, decrypts with the
stored key ID, and revalidates the supported payload schema. Missing keys and unavailable
repositories have distinct safe errors. An unreadable or revoked record supplies no credential.
No path falls back to a provider environment variable or a credential from another tenant.
Known repository lookup/connection lifecycle failures return `provider_credentials_unavailable`;
unrelated programming exceptions retain their original stacktrace.

Public summaries contain metadata only. Resolved payloads remain in a separate private struct
whose Inspect output omits the payload; Ecto redacts the ciphertext field, and the keyring's
Inspect output omits key material. These protections are not permission to serialize private
structs into plans or archives. Credential queries disable both SQL logging and SQL query
telemetry, because Ecto's query event includes parameters and result values. Future operational
measurements must use explicitly projected, payload-free events.

## Alternatives and remaining work

- Plaintext PostgreSQL payloads and database-resident encryption keys were rejected: a database
  backup alone must not recover provider credentials.
- A one-way provider-key hash was rejected because provider requests need the original secret.
- An environment/global provider fallback was rejected because it defeats tenant ownership and
  hides missing configuration. Runtime callers use explicit tenant resolution.
- Interactive secret entry was rejected for this CLI: terminal echo and shell history are avoided
  by requiring protected redirected input.
- A custom cryptographic primitive or new encryption dependency was unnecessary; OTP supplies
  authenticated encryption. Platform encryption-key re-encryption reuses the existing keyring.
  Fresh-VM retirement acceptance passes in checkpoint 6. Third-party key rotation/revocation
  workflows and backup-restore drills are excluded. Existing admitted-client/leg lifetimes remain unchanged
  while each new construction resolves its current tenant binding.

## Verification

The persistence tests cover encrypted rows, tenant isolation, uniqueness, malformed auth,
unavailable/wrong keys, authenticated identity changes, revoked resolution, metadata-only
listing, query telemetry suppression, repository termination/recovery and CLI input safety.
Runtime tests cover explicit key injection, absent keys and sanitized startup errors.
Red/green results, independent review and disposable database/terminal acceptance are recorded
in the [provisioning labnote](../labnotes/20260915-1616-tenant-credential-provisioning.md).
Named Telnyx provisioning, encrypted tenant isolation and CLI metadata-only output are covered by
the [Telnyx provisioning checks](../labnotes/20260915-2341-telnyx-credential-provisioning.md).
