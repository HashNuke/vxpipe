# Saved tenant MCPs at call runtime

The packaged editor, publication and preparation paths now read saved tenant MCP
metadata. Gateway builds a fresh saved-connection snapshot before starting browser,
incoming and outgoing calls. Local acceptance now joins PostgreSQL publication to
Console call/session admission, real WebRTC input, model-selected ExMCP execution
and peer output. Authenticated tenant disconnect blocks a subsequent invocation
in that same room. Identity is fixture-backed; rendered browser, telephony,
transfer, broader negative cases and separate-node acceptance remain milestone gates.

## Metadata and pinning

`SavedMCPCatalog` provides stable connection IDs and cached tool choices without
decrypting credentials or contacting a server. Unsupported input schemas are omitted
from the picker; selecting one explicitly still fails compilation. Native tools
remain usable during a repository failure. There is no application-MCP fallback.
Zero-tool connections remain visible as connections, with no selectable tools.

`SavedMCPCompilationCatalog` creates an immutable tenant-only snapshot. It validates
record ownership/status and pins configuration, credential and catalog generations.
The catalog generation hashes sorted descriptors. Publication and preparation use
the shared `CallPlanCompiler`; native-only specs do not query MCP storage. Prepared
plans store selected tool descriptors and identities, never endpoints, credentials,
keyrings or runtime resolvers. New catalog tools do not add themselves to a saved
selection. A catalog change invalidates an older prepared snapshot; prepare again
to use the current catalog. Runtime startup also rejects replaced/revoked generations.

MCP descriptions are optional in the approved protocol. The model projection uses
`Call <public alias>.` when the normalized remote description is empty; it preserves
the pinned schema and does not expose the remote name or connection configuration.
This keeps a valid tool without a description from failing only at agent startup.

## Secret-free startup and current request headers

The startup builder validates current saved configuration, then discards decrypted
material. Its catalog contains only public endpoint/identity pins and a runtime
resolver descriptor, with empty bootstrap authentication. This is necessary because
OTP supervisor reports can retain raw child arguments despite opaque `Inspect`.

The standard descriptor resolves the currently configured Calls repository on each
request. An operation-level repository, grant repository, refresh port or clock
override cannot silently select a different runtime source. Such callers must supply
an explicit `:mcp_runtime_resolver` whose context contains only PIDs/references or
tuples of them. The resolver owns any private state behind those references. The
result must match the pinned tenant, connection, generation, method and endpoint.

The provider resolves one current snapshot per POST, GET/SSE connection/reconnect or
session DELETE. Its validated headers replace the entire credential header set.
Bearer and Basic require the matching Authorization scheme. OAuth renewal rereads
the final persisted token and MCP headers together; refresh tokens, registration
secrets and signing keys are not returned to transport. Failed resolution sends no
request and never falls back to cached credentials. A locally rejected POST is
classified as not submitted; ambiguous transport failures remain unknown and are
not retried. Existing in-flight requests cannot be retracted by revocation.

The pinned dependency correction now covers HTTP, SSE and Client status redaction.
The checked upgrade patch accepts the exact previous reviewed sources as well as
pristine/current sources. Unknown or mixed source edits still stop preparation.
See [transport preparation](mcp-runtime-transport.md).

## Embedding and migration

Explicit process-backed or immutable catalogs remain supported by the direct
CallEngine API. Calls also retains explicit compilation/picker injection for trusted
hosts. Packaged Gateway admission deliberately requires saved tenant records; it is
not an embedded application-catalog startup API. A host using application integrations
must use the direct CallEngine startup boundary or migrate to saved tenant records.

Gateway forwards an explicit server-owned `remote_mcp_connection_provider` to the
existing CallEngine boundary, allowing a trusted host or local HTTP acceptance
fixture to own connection establishment. Call specs and HTTP payloads cannot set
it. This does not enable injected catalogs or protocol overrides in packaged
admission; saved tenant validation and current credential resolution still apply.

Existing application configuration is neither copied nor silently shared with a
tenant. Reconnect each server in its intended tenant, obtain its stable saved ID,
update the explicit tool selections and republish. No migration deletes old secrets.

The privacy evidence here covers managed saved-runtime descriptors. Legacy embedded
static credentials can still be present in the host's supervisor arguments; Client
status redaction alone cannot sanitize those supervisor reports. Hosts should use a
nonsecret dynamic resolver rather than passing static secrets through child specs.

## Design review and evidence

Independent adversarial review found unsupported picker schemas, raw supervisor
argument exposure and the previous-patch upgrade gap. Focused regressions reproduced
each before correction. Saved-record wire acceptance also reproduced a known local
rejection being misclassified as an unknown outcome; both asynchronous and synchronous
ExMCP forms now preserve the not-submitted result.

Raw logger events are captured before the default translator can suppress SASL
reports. Activation retirement and client failure exclude synthetic token, custom
header and encryption-key markers. The saved-record test also verifies metadata-only
authoring with no decryption key, persisted-plan privacy, foreign-tenant isolation,
schema/credential changes and execution rejection after revocation.

A reusable private-config vault was rejected: it would introduce new lifetime and
ownership rules for delayed transfer activations. Complete request-header resolution
keeps the existing supervision and saved-generation contracts. Broad logger filtering
or relying on `Inspect` would leave private data in raw reports.
