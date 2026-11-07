# Saved tenant MCPs at call runtime

The packaged editor, publication and preparation paths now read saved tenant MCP
metadata. Gateway builds a fresh saved-connection snapshot before starting browser,
incoming and outgoing calls. Local acceptance now joins PostgreSQL publication to
Console call/session admission, real WebRTC input, model-selected ExMCP execution
and peer output. Authenticated tenant disconnect blocks a subsequent invocation
in that same room. Local web acceptance also covers tenant isolation, empty catalogs,
schema/deletion pins, repository outages and delayed agent transfers with cold and
reused clients after revocation/replacement. It verifies one already-submitted
request completing after disconnect while later submissions fail. Identity is
fixture-backed. Local carrier-fixture acceptance also covers managed incoming and
outgoing admission plus the legacy incoming startup entry. Independent-node
credential/transport lifecycle acceptance now covers both OAuth grant types,
revocation and caller/runner retirement in a separate lane. Those node tests call
ExMCP directly; they do not claim distributed admitted-room execution.
[Management-browser flows](mcp-browser-acceptance.md) and
[cross-node callbacks with subsequent renewal](../../labnotes/20261107-0819-verify-oauth-node-callbacks.md)
also pass separate acceptance lanes. An unchanged published call spec survives
disconnect/reconnect with fresh preparation while the old prepared generation stays
fenced; see [composition evidence](../../labnotes/20261107-1109-verify-reconnected-call-spec.md).
Final verification, external release and user approval remain open in the milestone.
See [runtime transport](mcp-runtime-transport.md) and the
[acceptance audit](../../labnotes/20261107-1200-verify-held-mcp-responses.md).

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

Opening a reused session also validates its supplied client profile and resolves
current runtime headers before authorizing the new activation. The headers are
discarded after that check; each later transport submission resolves them again.
This closes the gap where a delayed transfer could take control using another
room's cached connection after its saved grant was disconnected. Reuse failure
rejects the new activation without retiring the shared session: an unavailable
repository must not terminate other rooms, and their own requests remain guarded.
Explicit node-local revocation still retires the scoped connection and its leases.

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

The saved boundary suite now follows the original published selection through fresh
preparation after a catalog change. It rejects stale prepared calls and invalid new
arguments, then executes permitted arguments without granting newly discovered
tools. An observed repository wrapper distinguishes preparation, startup and active
request outages; native-only calls make no MCP repository reads. A foreign-tenant
selection fails publication while that tenant's own server and distinct credentials
execute successfully. Delayed transfer acceptance uses public participant snapshots,
exact tool outcomes and subsequent input over the original peer to prove ownership
and unchanged call incarnation. A sibling admitted call keeps the reused MCP client
open in the revocation regression.

In-flight acceptance holds an authenticated tool POST at the local server, disconnects
the saved connection through Console, then releases that exact response. The result
reaches the model and original WebRTC peer; a later model-selected invocation
fails in the same running room without another protocol request. Explicit handler
references and a held SSE stream avoid timing assumptions. Cancellation, owner death
and timeout cannot satisfy the successful-response acknowledgement. This verifies
local submitted-request semantics, not separate-node renewal or revocation races.

Local phone acceptance publishes the saved selection with persisted native speech
credentials and a telephony service. Managed incoming/outgoing calls use normal
carrier verification, admission and media attachment; a compatibility fixture also
exercises the legacy three-argument incoming startup. Actual Opus input reaches the
speech wire, the model executes the saved MCP over loopback HTTP, and controlled
speech output reaches the original phone socket. After authenticated disconnect,
the next invocation fails without another tool request while the same call remains
running. A signed carrier hangup then closes the room, media socket, leg and managed
cleanup tracker; all three routes wait for durable ended state and a private-safe
archive close record. Carrier commands and speech responses are synthetic: this
does not claim live-carrier or separate-node interoperability. See
[phone acceptance evidence](../../labnotes/20261107-0922-saved-mcp-telephony.md).

A reusable private-config vault was rejected: it would introduce new lifetime and
ownership rules for delayed transfer activations. Complete request-header resolution
keeps the existing supervision and saved-generation contracts. Broad logger filtering
or relying on `Inspect` would leave private data in raw reports.
