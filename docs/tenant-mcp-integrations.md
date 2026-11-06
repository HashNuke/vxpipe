# Tenant MCP integrations

Current workflow contract: [directory consumption and unlisted MCPs](development/integrations-directory-consumption.md).
Its merged Integrations page, duplicate-connection policy and API-first behavior
supersede earlier workflow options below. Delivery is split into
[T0–T8, including URL-preflight checkpoint T4a](../labnotes/milestones/integrations-directory-and-tenant-mcps.md).

Status: architecture contract reconciled 2026-11-07. Tenant records, static/OAuth
management, custom forms and saved runtime wiring are implemented. Listed-template
and retained-ID reconnect UI plus authenticated browser, full runtime/transfer,
independent-node and external-release acceptance remain open in the milestone.
The earlier research remains context; it is not final delivery evidence.

## Product contract

An MCP is a tenant-owned service connection. A catalog entry is only a setup
template: endpoint, display information and provider-specific setup guidance.
It carries no connected account, token or platform-owned service instance.
Custom MCPs use the same runtime and persistence path as catalog presets.

- Show MCP connections in tenant Integrations alongside native AI and telephony
  integrations. Do not offer MCPs in Platform Integrations.
- Enforce tenant-only ownership in creation, listing, catalog discovery, call
  preparation and invocation. Removing a tenant connection must never uncover
  an application/platform fallback. Other provider inheritance stays unchanged.
- Custom connections use stable IDs independent of server-reported names. Listed
  duplicates reopen the existing connection by directory identity; multiple accounts
  for one directory entry remain a separate product decision. No editable aliases.
- Reuse credential storage infrastructure and key management, with encrypted
  MCP-specific secret records. Existing AI credentials for Google are not
  Google Calendar authorization.
- Keep endpoints, tokens and client secrets out of call specs and model input.

## Integrations workflow

Visitor mode: Operate. A tenant operator wants to connect a business system and
make its tools available to selected call agents. Preserve the current Console
shell, service inventory and compact dialog conventions.

1. **Integrations** opens Connected integrations with category navigation and global
   directory search. **Connect other MCP** remains available with no search match
   or during directory outages. Platform scope omits MCPs.
2. Selecting a preset supplies its name, endpoint and authentication recipe; none
   is editable in its connection form. Custom MCP asks for **MCP server URL** and
   uses the initialized server name, with no connection-name field. This is the full endpoint, including its path;
   never apply Installation URL normalization that discards paths.
3. Entering or changing the custom URL starts a metadata preflight and prefills
   supported settings. Authentication Type lists actual methods, without Discover
   automatically. **Connect** then validates the chosen flow, performs registration/
   authorization as needed, and returns to the same connection. CIMD has no extra
   editable fields; DCR retains only an optional initial registration token. Own
   client retains its manual configuration. No fixed three-step wizard is required.
4. Complete MCP initialization and bounded tool discovery, then show the connection
   as ready with its name, server/provider, tool count and authentication status.
   Saving configuration or receiving a token alone is not evidence of readiness.
5. Manage offers reconnect, refresh tools, credential updates and disconnect. Failed or
   canceled authorization preserves the draft. Changing the endpoint or connected
   account requires validation and new authorization; it cannot inherit old tokens.

Explain that the authorized account is available to agents in the selected tenant.
Show account identity only when reliably supplied by the provider. OAuth protocol
details belong in connection details, not the ordinary connect form.

Material states: empty/search-no-results, checking, authorization required,
waiting for provider, canceled/expired authorization, client setup required,
discovering, connected, connected with no tools, unreachable, reconnect required,
insufficient scope and disconnect-in-use. A separate incomplete connection cannot
be selected by an agent as ready. Preserve keyboard focus and dialog recovery;
use the same form on mobile with stacked fields and bounded scrolling.

## Authentication

CIMD and DCR identify/register the OAuth client; they do not replace user
authorization. Use configured pre-registration first, otherwise advertised CIMD,
then advertised DCR, then manual client setup. Anonymous access is a separate
connection mode, never an OAuth-error fallback. OAuth uses discovery, PKCE S256
and resource-bound requests. These choices follow the
[approved MCP authorization profile](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization).

Keep optional bearer/API-key header credentials as an advanced compatibility
path, distinct from the standard OAuth flow. The existing MCP adapter already
supports static bearer and validated custom headers. Do not advertise this as a
substitute for a provider's required OAuth flow.

| Preset | Verified documentation | Product consequence |
| --- | --- | --- |
| Cal.com | Official hosted endpoint `https://mcp.cal.com/mcp`; its docs describe CIMD and DCR. | Good first preset for automatic registration and browser authorization. |
| Google Calendar | Official endpoint `https://calendarmcp.googleapis.com/mcp/v1`; currently Developer Preview. Its guide requires preview access, Cloud project/API setup, and a client ID/secret. | Include manual OAuth client setup and preview labeling; do not promise universal one-click access. |
| Custom MCP | User supplies a compatible remote endpoint. | Discover capabilities rather than requiring a new Vxpipe provider implementation. |

Sources checked on 2026-10-24: [Cal.com MCP documentation](https://cal.com/docs/mcp-server)
and [Google Calendar MCP setup](https://developers.google.com/workspace/calendar/api/guides/configure-mcp-server).
These are documentation checks, not live interoperability acceptance. Test the
required scheduling operations and granted scopes before claiming receptionist
booking support; discovery of a write tool does not prove permission to use it.

## Persistence and runtime

Proposed durable records separate public configuration, private authorization and
discovery data:

- **Connection:** tenant, stable ID, display name, optional catalog preset,
  endpoint, auth mode, configuration generation and operational status.
- **OAuth registration/grant:** exact issuer/resource/client/redirect identities,
  granted scopes, expiry, encrypted secrets/tokens and authorization generation.
  Scope all grant access to the tenant and connection. Anonymous connections
  remain tenant-owned even though they have no stored grant.
- **Authorization attempt:** short-lived, single-use state bound to the initiating
  session, tenant, connection and configuration revision; protect PKCE material
  server-side and revalidate permissions when completing the attempt.
- **Catalog snapshot:** validated tool descriptions and schemas, generation and
  discovery result/time. No remote tool invocation is needed to test connection.

Keep token revision separate from grant/configuration generation. Normal access
token refresh must work during a call without changing its selected tool identity.
Coordinate refresh across processes/nodes and atomically persist rotated tokens.
Disconnect or revoked authorization invalidates further tool use; it cannot
silently keep stale grants alive or borrow another connection's credentials.
Ambiguous submitted tool calls retain the existing no-automatic-retry contract.

Reuse the existing encryption keyring and authenticated-encryption design, with
MCP-specific identity binding and participation in key rotation. The current
CredentialCipher is coupled to ProviderCredential; it is not a generic vault API.
Do not put arbitrary MCP names into the closed AI-provider registry just to reuse
its credential form. Tenant Services can aggregate different service kinds.

Custom endpoint and OAuth metadata requests need the same outbound policy:
bounded requests, approved destinations and redirect validation, no credential
forwarding to unrelated origins, and operator-controlled private-network access.
Use the existing ExMCP protections and verify every discovery/token path uses
them. This is relevant to the [MCP security guidance](https://modelcontextprotocol.io/docs/2025-11-25/tutorials/security/security_best_practices).

## Agent tool selection

Retain the approved add-tool interaction: the first screen lists platform tools
and this tenant's ready MCP connections, with MCP name and count on one line.
Selecting an MCP opens its searchable tool checklist. Select all expands into
explicit tool names saved for that agent; it never saves a wildcard.

Catalog refresh may discover more tools, but does not grant them to existing
agents. Existing calls retain their pinned tool schemas. Reuse the established
double-underscore model naming convention and source/tool UI labels; do not
introduce editable per-tool local aliases. Resolve duplicate connection names or
model-name collisions explicitly without rewriting persisted identities.

## Existing code and integration seams

- `vxpipe_mcp` already provides supervised ExMCP sessions, bounded discovery and
  invocation, credential leases and static/anonymous authentication. Its public
  client metadata builder is implemented. The installed ExMCP also has OAuth
  discovery, registration policy and an auth-provider behavior; verify and adapt
  those APIs before implementing duplicate protocol machinery.
- Call Engine already pins remote tool bindings. `RemoteMCP.IntegrationCatalog`
  currently falls back to application integrations, and `ConfiguredNames` exposes
  application names to tenants. Both paths must enforce the new tenant-only
  product contract. Document any library-host compatibility change explicitly.
- Calls should own tenant connection authorization/workflows and repository
  ports; Persistence implements durable connection, grant and catalog storage;
  MCP owns protocol/authorization adapters; Console owns the Services workflow.
  Add explicit Mix dependencies wherever a child directly uses another child.
- Replace the packaged runtime's application-configuration source with a durable
  tenant connection source. Update publication/preparation and tool-picker reads,
  rather than merely adding rows to the Services page.
- Managed startup descriptors are credential-free. A guarded private boundary
  resolves current static/OAuth headers for each request, with bounded renewal and
  scoped errors. No browser interaction may block a voice call; insufficient consent
  becomes an actionable reconnect state and a safe tool failure.

The CIMD document is served by Console. Its callback is Installation URL plus
`/oauth/mcp/callback`, now mounted for the tenant OAuth backend. Initial connection,
refresh, generation-checked reconnect and production custom OAuth forms are
implemented. Listed-template/retained-ID UI and full interoperability acceptance
remain open in the milestone.
Protocol behavior stays in the MCP adapter, with browser authority in Console,
tenant lifecycle in Calls and encrypted state in Persistence. See the
[outbound OAuth implementation contract](development/tenant-mcp-oauth.md).

## Delivery and verification

1. Review Storybooks for preset/custom connection, anonymous success, OAuth return,
   manual client setup, reconnect, errors and tenant-only inventory. No real
   credentials are needed for this workflow review.
2. Deliver durable tenant-only connections through anonymous and existing static
   auth, including real tool discovery, agent selection and invocation.
3. Add OAuth discovery, CIMD/DCR/pre-registration, callback persistence, refresh,
   reconnect/disconnect and installation-origin-change handling.
4. Verify Cal.com and eligible Google Calendar accounts in explicit integration
   lanes before labeling either supported. Keep custom-server compatibility
   bounded by the supported remote transport/protocol profile.

Acceptance must prove tenant isolation at every boundary, no application fallback,
no agent wildcard expansion, cross-node refresh coordination, callback replay and
wrong-tenant rejection, secret redaction, reconnect/revocation during calls, and
no duplicate side effects after ambiguous failures. Follow project red/green,
root gates and rendered desktop/mobile checks for each implemented slice.

Rejected alternatives: a catalog-only allowlist prevents custom services; platform
credential inheritance violates tenant ownership; separate protocol code for each
catalog item duplicates MCP; treating a saved token as ready conceals discovery
failures. The earlier suggestion to hide CIMD/DCR choices is superseded by the
user-directed single Authentication Type selector. No implementation milestone is
marked complete by this architecture document.
