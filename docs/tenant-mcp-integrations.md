# Tenant MCP integrations

Latest review proposal: [directory consumption and unlisted MCPs](development/integrations-directory-consumption.md).
Its merged Integrations page, duplicate-connection policy and API-first behavior
supersede earlier workflow options below. Delivery is split into
[T0–T8](../labnotes/milestones/integrations-directory-and-tenant-mcps.md).

Status: researched proposal, 2026-10-24. The user specified tenant-only MCP
services, catalog presets plus custom servers, and CIMD/DCR/anonymous support.
This document proposes the remaining workflow and implementation contracts;
it does not claim new UI, persistence or OAuth integration is implemented.

## Product contract

An MCP is a tenant-owned service connection. A catalog entry is only a setup
template: endpoint, display information and provider-specific setup guidance.
It carries no connected account, token or platform-owned service instance.
Custom MCPs use the same runtime and persistence path as catalog presets.

- Show MCP connections in tenant Services, grouped separately from AI and
  telephony services. Do not offer them in Platform services.
- Enforce tenant-only ownership in creation, listing, catalog discovery, call
  preparation and invocation. Removing a tenant connection must never uncover
  an application/platform fallback. Other provider inheritance stays unchanged.
- Support several connections to the same provider, with meaningful names such
  as Reception calendar and Sales calendar. Stable connection identity is
  independent of the display name and catalog provider ID.
- Reuse credential storage infrastructure and key management, with encrypted
  MCP-specific secret records. Existing AI credentials for Google are not
  Google Calendar authorization.
- Keep endpoints, tokens and client secrets out of call specs and model input.

## Services workflow

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
3. **Connect** checks the server. An anonymous endpoint goes directly to discovery;
   OAuth opens the provider authorization flow and returns to the same connection.
   Additional client registration fields appear only when needed. Avoid a fixed
   three-step wizard or asking users to choose between CIMD and DCR.
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
- The current client options turn auth into static headers. OAuth needs a private
  token-provider boundary for refresh and scoped errors. No browser interaction
  may block an ongoing voice call; insufficient consent becomes an actionable
  reconnect state and a safe tool failure.

The existing CIMD document is served by Console. Its advertised future callback
is Installation URL plus `/oauth/mcp/callback`. Keep that identity stable for this
proposal and ensure the callback is actually mounted there. OAuth logic belongs
behind an application-independent adapter; this plan does not assume an
unimplemented general Gateway URL or claim the callback already exists.

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
failures; an always-visible CIMD/DCR selector exposes machinery rather than a user
decision. No implementation milestone is marked complete by this proposal.
