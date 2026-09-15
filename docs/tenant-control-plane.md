# Tenant control-plane operations

Vxpipe keeps tenant credentials and reusable call definitions in an optional
PostgreSQL control plane. `vxpipe_calls` owns the database-neutral workflows and
repository contracts; `vxpipe_persistence` owns Ecto, PostgreSQL schemas,
migrations, constraints, and transactions. The gateway and call engine never
query the Repo directly.

## Configure and migrate PostgreSQL

Set `VXPIPE_DATABASE_URL` through the deployment's secret/configuration boundary.
Repository development defaults to `postgres://localhost/vxpipe_dev`; the variable
is an optional override there. Outside development, when it is absent, the
persistence application starts without a Repo and the
existing embedded/static call-engine mode remains database-free. An optional
`VXPIPE_DATABASE_POOL_SIZE` sets the connection-pool size and defaults to 10.

Create and migrate the configured database before using the operator commands:

```shell
mix ecto.create
mix ecto.migrate
```

The repository disables ordinary Ecto query logging because bound query values
will include API-key digests and may later include other sensitive control-plane
data. Operational query measurements should use bounded, payload-free telemetry.

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
definitions resolve these records at save, publication, preparation and capability creation.
Trusted [Telnyx service registration](tenant-telephony-services.md) links connection/verification
metadata to the matching tenant credential. Live carrier DB readers remain in progress.
API-key issuance and authentication above remain independent.

## Save and publish call definitions

Select supported providers and provider-local models inline, provision their tenant
credentials, and configure any referenced host tools before saving. Invalid selections
or missing credentials prevent saving. Other unsupported host references remain draft
`validation_errors`; a revision with errors cannot be published.

Save the first immutable revision from a JSON file:

```shell
mix vxpipe.definition.save \
  --tenant TENANT_KEY \
  --file examples/call-definitions/development.json
```

That tracked example selects Google Gemini inline and requires the tenant’s `google/default`
credential. Deployments should provide their own definition and configured host tools.

The output contains a generated `definition_id`, revision number, source digest,
validation results, and draft participant route UUIDs. Draft routes are not
callable. To edit a definition, save the changed JSON under its existing public
ID; Vxpipe inserts the next revision rather than updating the old source:

```shell
mix vxpipe.definition.save \
  --tenant TENANT_KEY \
  --definition-id DEFINITION_ID \
  --file path/to/call-definition.json
```

Publish an error-free revision explicitly:

```shell
mix vxpipe.definition.publish \
  --tenant TENANT_KEY \
  --definition-id DEFINITION_ID \
  --revision 1
```

Only the selected revision's deployment routes resolve. Read any immutable
revision, including its portable source and credential-free compiled metadata:

```shell
mix vxpipe.definition.show \
  --tenant TENANT_KEY \
  --definition-id DEFINITION_ID \
  --revision 1
```

Provider/MCP credentials and private credential leases are rejected from portable
definition JSON. Recoverable upstream credentials belong to their separate
application or tenant secret boundary.

## Design implications and rejected alternatives

- Public tenant and route keys are distinct from SQL primary keys. Tenant lookup,
  route resolution, and uniqueness are enforced in PostgreSQL without exposing
  internal IDs.
- API keys are high-entropy bearer credentials with one-way storage. Reversible
  API-key encryption and plaintext database storage were rejected because Vxpipe
  never needs to recover these values.
- Definition revisions are append-only source records. Updating published JSON or
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
