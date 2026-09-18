# Tenant control-plane operations

Vxpipe keeps tenant credentials and reusable call specs in an optional
PostgreSQL control plane. `vxpipe_calls` owns the database-neutral workflows and
repository contracts; `vxpipe_persistence` owns Ecto, PostgreSQL schemas,
migrations, constraints, and transactions. The gateway and call engine never
query the Repo directly.

## Configure and migrate PostgreSQL

Set `VXPIPE_DB_URL` or its lower-priority alias `DATABASE_URL` through the deployment's
secret/configuration boundary. Development defaults to `postgres://localhost/vxpipe_dev`.
Outside development, absence of both leaves persistence disabled for explicit embedded use;
hosted tenant admission requires PostgreSQL.

`VXPIPE_DB_POOL_SIZE` takes precedence over `DB_POOL_SIZE`, with default 10. Both settings
are independent: URL `pool_size` query values cannot override the selected pool. Unset/empty/
whitespace-only values are absent; an invalid selected value fails safely instead of falling
through to another alias. Test mode preserves its dedicated database and Sandbox configuration.
The retired `VXPIPE_DATABASE_URL` and `VXPIPE_DATABASE_POOL_SIZE` are ignored.

Create and migrate the configured database before using the operator commands:

```shell
mix ecto.create
mix ecto.migrate
```

The repository disables ordinary Ecto query logging because bound query values
will include API-key digests and may later include other sensitive control-plane
data. Operational query measurements should use bounded, payload-free telemetry.

### Upgrade notes for the Call Specs rename

The rename is delivered by a new reversible migration for the two Call Spec tables
and their related columns and constraints. Existing migrations retain their historical
filenames and contents. This requires a coordinated application-and-migration deployment;
old binaries cannot use the renamed tables. Callers must update the changed `/call-specs`
routes and `call_spec*` JSON, API, and CLI names. Existing published JSON remains
byte-for-byte exact, and a safe legacy resolved-plan reader keeps pre-rename stored plans
usable after migration. Take the usual database backup before upgrading, and use the new
migration's down operation only for a deliberate rollback.

## Bootstrap a tenant

The first key does not require another API key because this is a trusted local
operator action:

```shell
mix vxpipe.tenant.bootstrap --name "Example tenant" --scopes admin,calls
```

The command emits one JSON object containing the 16-character tenant key, public
API-key ID, explicit scopes, and plaintext API key. The plaintext value is shown
only once. Move it directly into the integrating backend's secret store; do not
put it in source control, screenshots, tickets, shell tracing, or application
logs. Vxpipe stores only its SHA-256 digest and cannot recover a lost key.

Tenant keys use the complete URL-safe Base64 alphabet, including a possible leading `_` or `-`.
Pass the exact key through preparation and Engine commands; do not rewrite or add a prefix.

`admin` and `calls` are independent grants. Neither implies the other.

## Rotate or revoke a key

Issue a separately revocable replacement while the old key is still active:

```shell
mix vxpipe.api_key.issue \
  --tenant TENANT_KEY \
  --name "replacement" \
  --scopes calls
```

After the integrating backend has adopted the replacement, revoke the old public
key ID:

```shell
mix vxpipe.api_key.revoke \
  --tenant TENANT_KEY \
  --key-id API_KEY_ID
```

Revocation prevents new authentication with that API key. It does not terminate
an established session or couple future join-token validity to the issuing key.
Join tokens are introduced by the prepared-call milestone.

## Provision upstream provider credentials

Google, Deepgram and Telnyx credentials have separate encrypted tenant storage and trusted
provision/list commands. See [provider credential storage](provider-credential-storage.md)
for platform encryption settings, protected stdin input and metadata output. Inline Google/Deepgram
call specs resolve these records at save, publication, preparation and capability creation.
Trusted [Telnyx service registration](tenant-telephony-services.md) links connection/verification
metadata to the matching tenant credential. Live carrier DB readers remain in progress.
API-key issuance and authentication above remain independent.

## Save and publish call specs

Select supported providers and provider-local models inline, provision their tenant
credentials, and configure any referenced host tools before saving. Invalid selections
or missing credentials prevent saving. Other unsupported host references remain draft
`validation_errors`; a revision with errors cannot be published.

Save the first immutable revision from a JSON file:

```shell
mix vxpipe.call_spec.save \
  --tenant TENANT_KEY \
  --file examples/call-specs/development.json
```

That tracked example selects Google Gemini inline and requires the tenant’s `google/default`
credential. Deployments should provide their own call spec and configured host tools.

The output contains a generated `call_spec_id`, revision number, source digest,
validation results, and draft participant route UUIDs. Draft routes are not
callable. To edit a call spec, save the changed JSON under its existing public
ID; Vxpipe inserts the next revision rather than updating the old source:

```shell
mix vxpipe.call_spec.save \
  --tenant TENANT_KEY \
  --call-spec-id CALL_SPEC_ID \
  --file path/to/call-spec.json
```

Publish an error-free revision explicitly:

```shell
mix vxpipe.call_spec.publish \
  --tenant TENANT_KEY \
  --call-spec-id CALL_SPEC_ID \
  --revision 1
```

Only the selected revision's deployment routes resolve. Read any immutable
revision, including its portable source and credential-free compiled metadata:

```shell
mix vxpipe.call_spec.show \
  --tenant TENANT_KEY \
  --call-spec-id CALL_SPEC_ID \
  --revision 1
```

Provider/MCP credentials and private credential leases are rejected from portable
call spec JSON. Recoverable upstream credentials belong to their separate
application or tenant secret boundary.

## Design implications and rejected alternatives

- Public tenant and route keys are distinct from SQL primary keys. Tenant lookup,
  route resolution, and uniqueness are enforced in PostgreSQL without exposing
  internal IDs.
- API keys are high-entropy bearer credentials with one-way storage. Reversible
  API-key encryption and plaintext database storage were rejected because Vxpipe
  never needs to recover these values.
- Call Spec revisions are append-only source records. Updating published JSON or
  making draft routes callable implicitly was rejected because active/prepared
  calls must be able to pin an exact revision.
- Putting Repo queries in the gateway or realtime engine was rejected to preserve
  embedded use and keep database work outside live room authority/media paths.

## Verification

The Calls workflow suite covers issuance, explicit scopes, independent revocation,
immutable revisions, unsupported-feature recording, and tenant-isolated routing.
The persistence suite runs against PostgreSQL and covers constraints,
draft/publication behavior, public/SQL identity separation, and authentication
across a supervised Repo restart. The operator suite exercises every command
above while capturing one-time key output rather than logging it.
