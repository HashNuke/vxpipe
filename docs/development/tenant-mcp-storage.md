# Tenant MCP storage boundary

Status: storage, static/OAuth management, grants and saved runtime wiring are
implemented, 2026-11-07. [Authenticated MCP browser flows](mcp-browser-acceptance.md),
[local admitted-call execution](saved-mcp-runtime.md) and independent-node
callback/renewal/rotation lanes pass their recorded scopes. Final verification,
external release and user approval remain in
[T4–T8](../../labnotes/milestones/integrations-directory-and-tenant-mcps.md).
The repository is a trusted internal port; it is not a public authorization API.

Verification counts and pending-acceptance statements in the earlier checkpoint
sections below record their original scope. Use the current evidence linked above
and the milestone for subsequent completion and remaining release gates.

## Ownership and records

Calls owns `MCPConnectionRepository`; Persistence implements `MCP.ConnectionStore`.
Only tenant keys are accepted. A non-null tenant foreign key prevents platform
records. Reads select the connection ID and tenant together; there is no inherited
or application-config fallback.

`tenant_mcp_connections` stores a stable UUID, endpoint and canonical endpoint
identity, optional directory ID and accepted entry snapshot, server name, authentication method, configuration
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
generation again. The Calls reconnect flow uses an authorized retained-record
lookup; it cannot resolve or reuse erased credentials. Production UI handling of
retained-ID proposals remains an explicit milestone task.
Network validation must complete before the transaction; no network call belongs
under these locks.

Connected rows require non-null ciphertext and a key ID. A forward corrective
migration also tightens checkouts that already applied the preview schema; it
does not delete or rewrite rows. Rolling back that compatibility step retains the
invariant now present in the initial migration. Inconsistent existing rows fail constraint
validation and require explicit repair. Missing/stopped repositories and checkout
failures return the fixed unavailable error; unrelated programmer errors propagate.

## Accepted directory configuration

The nullable `directory_entry` JSON column stores accepted public configuration
separately from encrypted credentials. Existing custom and preview records remain
valid without it. New listed records use `directory_id` as the unambiguous
`<directory-id>/<entry-id>` binding; two 64-character IDs plus the separator fit
the 129-character validation bound. Existing preview IDs are not rewritten.

Persistence accepts only the closed public snapshot from
[listed discovery](listed-mcp-connections.md): directory/entry IDs, entry revision,
name, endpoint, authentication recipe and optional plain-text setup notes/HTTPS
links. The encoded snapshot is bounded to 64 KiB; unknown fields, including nested
secret fields, are rejected. Its identity, endpoint and recipe must agree with
the connection attributes. Protocol support, destination policy and actual
credential validation still belong to the authorized connection boundary.
This storage check binds the outer authentication method; it does not compare
encrypted credentials with an API-key header name, OAuth registration mode or
requested scopes. Its API-key name check enforces grammar, while the directory
resolver/protocol layer rejects reserved transport headers. Future listed
mutations must retain those checks before network side effects. The public
snapshot is immutable through repository operations; it is not cryptographically
authenticated metadata and does not protect against privileged database changes.

Replacement cannot detach or modify an existing accepted snapshot. Revocation
clears credentials and the catalog but retains this public configuration for
explicit same-ID reconnection, even without a decryption key. Catalog refresh
keeps the accepted directory display name while replacing tool descriptors.
Custom connections continue to use their server-reported names. Directory
refreshes never rewrite saved configuration; accepting a changed recipe would
require a separately designed explicit migration workflow.

The additive migration and repository contracts are implemented. Creating listed
connections through Calls/Console, binding OAuth attempts and rendering locked
forms remain T6a tasks; the storage capability alone does not enable Connect.

## Secrets and rotation

The MCP envelope reuses `CredentialKeyring` and AES-256-GCM. Authenticated data binds
its own versioned MCP namespace, key ID, tenant, connection, configuration generation,
authentication method and purpose. Provider credentials cannot be substituted for
MCP secrets. Inputs and ciphertext are bounded to a 64 KiB plaintext payload.
Returned metadata contains no secrets; private resolution uses a struct whose
inspection omits all fields. SQL queries suppress bound-data logging and telemetry.

The storage re-encryption operation processes a bounded batch using `FOR UPDATE
SKIP LOCKED`, keeps the generation unchanged, and reports remaining rows by old
key ID. Failed batches roll back. Operators must retain old decrypt keys until all
writers use the new key and all secret stores have no old-key rows. The operator command `mix vxpipe.mcp_credential.reencrypt --batch-size 100`
now runs this operation using the configured MCP repository/keyring. It accepts
batches of 1–500 and prints only processed/current-key/remaining-key counts. Run it
alongside provider re-encryption; pending OAuth attempts are a separate short-lived
store, so retain old keys until those attempts have been claimed or expired.
[Cross-node rotation acceptance](../../labnotes/20261107-0832-verify-mcp-key-rotation.md)
now covers both grant types, draining old-primary writers, a final re-encryption
batch and subsequent renewal on both nodes with only the new key.

OAuth grant revisions and durable refresh claims are implemented separately from
configuration generation. Routine token refresh does not advance configuration
generation or alter pinned tool identity. Independent-node acceptance passes;
see [renewal contracts](mcp-oauth-renewal.md).

## Alternatives and verification

Reusing `provider_credentials` rows was rejected: their adapter-specific validation,
platform inheritance and lifecycle do not describe tenant-only MCP connections.
Reusing the installation keyring avoids a second operator secret-management system.
Plaintext credentials and display names as durable identities were rejected.

Connection-store tests cover encrypted storage, secret inspection,
cross-tenant reads/writes, duplicate identities, stale updates, invalid-edit
rollback, revocation/restoration, repository outage/recovery, constraint enforcement
and re-encryption batch rollback. Two tagged tests use distinct PostgreSQL
connections to verify duplicate identity and generation races. These clients run
inside one BEAM; separate-node acceptance remains open. Operational rotation and
complete authenticated persistence interoperability remain release gates. See
[storage review evidence](../../labnotes/20261107-0013-review-mcp-storage.md).

## Authorized static management

Calls checks browser-session tenant permissions and tenant existence before a probe,
then refreshes session authority before writing. Console exposes tenant-only management
routes with session and CSRF protection. Secret values never enter public projections.
For an edit, omitting `credentials` retains the saved credential map only when the
endpoint and authentication method match exactly. Supplying credentials replaces
that map completely; no inactive fields are merged. A stale generation is rejected
before probing, with a second compare-and-swap inside the write transaction.

MCP owns static input validation and the transient initialization/tools check. Each
probe gets a unique supervised client subtree, a ten-second lifetime and a monitor
of its requesting process. Caller cancellation terminates the subtree; cleanup does
not rely solely on an `after` clause in a process that could be killed. The checker
never invokes tools. Fake-runtime tests cover success, failure and caller death;
a tagged local HTTP fixture additionally proves actual initialization/tools traffic.
These checks do not yet establish every authentication mode's HTTP interoperability.

## Read-only discovery adapter

`Vxpipe.MCP.OAuthMetadata` supplies the issuer-metadata leg of URL preflight.
It reuses ExMCP's hardened `MetadataFetcher` and metadata endpoint validator,
while owning the discovery order required by the
[MCP 2025-11-25 profile](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization).
The installed OIDC discovery helper tries a different order, so using it directly
was rejected. Exact issuer mismatch and malformed successful responses fail closed;
404/405 responses advance to the next well-known candidate. Each document is
limited to 64 KiB, redirects to two, and requests to fixed timeouts. Credentials,
registration and token exchange are absent from this adapter. The complete preflight
must additionally bound the entire traversal, own cancellation/concurrency and
validate the protected-resource identity before selecting an issuer.

`ResourceMetadata` supplies the protected-resource leg: it reads the endpoint without
credentials, honors a parsed Bearer `resource_metadata` challenge, and otherwise tries
path-specific then root well-known metadata. Cowlib owns HTTP challenge grammar;
ambiguous Bearer challenges and repeated parameters are rejected. Resource identity
must match the requested endpoint exactly. Up to eight distinct HTTPS issuers are
returned without selecting one. Missing metadata is a distinct failure, never an
anonymous-access assertion. Endpoint initialization is still required to establish
anonymous MCP access and server identity. The two metadata adapters are foundations;
the authorized preflight API and static/OAuth production forms are wired.
Authenticated browser acceptance remains open.

Preflight runs through `POST /api/tenants/:tenant_key/mcp-discovery`, with session,
CSRF and current tenant write permission checks. Input contains endpoint, revision
and optional advertised issuer selection; credential fields are rejected. Calls
rechecks authority after discovery. Multiple issuers return `issuer_required`;
metadata failure returns partial/unknown, and only successful anonymous initialization
can suggest no authentication. Registration, grant acquisition and saving are separate.

A one-for-all supervisor owns the runner and its task supervisor. The runner limits
concurrent operations to eight and lifetime to 15 seconds, with a 500 ms per-tenant
admission interval and a bounded recent-tenant map. Each DNS/HTTP operation is linked
to a worker monitoring the preflight owner, closing the dependency's otherwise
independent I/O workers on cancellation. Caller-process termination is covered;
browser abort behavior still needs rendered/end-to-end verification.

Connection details use the repository `get` operation and
`GET /api/tenants/:tenant_key/mcp-connections/:id`. This reads the encrypted row's
public configuration and cached tool catalog; these remain available even when no
decryption key is supplied. For OAuth records, a successful optional decryption adds
only three fixed labels: registration method, grant type and client authentication
method. Unknown labels or unavailable keys yield no OAuth summary. Client IDs,
keys, tokens, parameters and header values are never returned. Calls enforces tenant read
permission and projects public fields plus `tools`. Revoked and foreign-tenant IDs
are unavailable. Reading this endpoint does not contact the remote MCP server.

`PATCH /api/tenants/:tenant_key/mcp-connections/:id` accepts a catalog-only request
`{generation, refresh_tools: true}` with no credentials or configuration fields.
Calls rechecks tenant write authority, resolves current saved credentials (renewing
OAuth through the runtime coordinator when needed), then initializes and lists tools.
Only server display name and cached descriptors are written, with a final generation
check and permission recheck. Preserve the encrypted envelope byte-for-byte, including
any concurrently rotated tokens or pending renewal claim. Configuration generation
stays unchanged; the existing catalog hash changes with descriptor changes and fences
stale compilation snapshots. No new connection route or secret replacement is needed.

The authenticated preflight result also includes the installation's validated public
callback/client-metadata URLs for manual registration. Missing installation identity
returns a null `oauth_client`; it does not prevent static or machine discovery.
Managed CIMD/DCR forms keep these settings internal.

## Editor catalog cutover

The default Calls editor tool catalog now reads cached descriptors from saved tenant
connections. Stable connection IDs identify integrations; server display names do
not become credential or tool identity. Foreign, revoked or malformed repository
rows make MCP choices unavailable. Native tools remain available on read failure,
without falling back to application MCP records. An explicitly injected embedded
catalog remains a separate supported host boundary. Packaged editor lookups now use those same saved IDs, including zero-tool
connections, instead of ConfiguredNames. Publication and saved runtime transport
are wired; full per-admission/transfer invocation acceptance remains open.

The Calls compiler now builds an immutable tenant-only snapshot from those saved
records when a call spec selects MCP tools. Publication and call preparation share
this path. No credential resolution or OAuth refresh occurs during compilation;
configuration and credential generations use the saved record generation, while
catalog identity hashes the sorted cached descriptors. A changed configuration or
schema fails checkout against an older resolved selection. Empty connections are
valid inventory entries but contribute no selectable tools. Native-only specs do
not query MCP storage, and explicit embedded catalog injection remains supported.
These compilation snapshots intentionally contain no transport configuration:
Gateway obtains fresh private runtime bindings before startup, and the guarded
transport resolves current headers for each submission. Full room/transfer and
independent-node acceptance remain open.
