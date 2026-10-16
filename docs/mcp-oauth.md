# MCP OAuth authorization

Status: implemented and locally verified, 2026-10-16. The
[milestone](../labnotes/milestones/mcp-oauth.md) records experiments, reviews and
acceptance evidence. This document does not claim that OAuth is deployed.

## Decision

Vxpipe issues OAuth credentials for its own MCP endpoint. Keep ExMCP for
Streamable HTTP, protocol lifecycle and tools. Use Boruta core (Hex package
`boruta`, pinned stable version 2.3.8) for OAuth protocol processing, with narrow
Vxpipe persistence adapters. Reuse Console login and Identity permissions.

OAuth replaces API-key authentication **only at `/mcp`**. The documented product
HTTP API keeps its browser-session and API-key contracts. OAuth access tokens are
not product HTTP API keys, join tokens or browser sessions.

The initial profile serves public MCP clients using authorization code with PKCE
S256 and rotating refresh tokens. It does not introduce OIDC login, an identity
provider deployment, password/client-credentials/implicit grants, JWT client
assertions, JAR, PAR, federation or a general OAuth administration product.

## User and client flow

1. An unauthenticated MCP request receives a Bearer challenge pointing to protected
   resource metadata. Metadata identifies Vxpipe's authorization server.
2. The client obtains authorization-server metadata and registers its name and
   exact redirect URI through bounded dynamic client registration (DCR).
3. The client opens `/oauth/authorize` with its client ID, redirect URI, state,
   canonical MCP `resource`, `scope=mcp` and S256 code challenge.
4. Vxpipe validates the request, records an expiring authorization transaction,
   and uses the existing browser login. The browser resumes by an opaque local
   transaction ID; raw OAuth parameters do not become an arbitrary return URL.
5. A consent page identifies the client, callback origin and requested MCP access.
   It explains the user's permitted operations and tenant scope, including whether
   all-tenant access covers future tenants. Approval and denial require CSRF.
6. Approval creates an independent delegated grant and a single-use code. The
   client exchanges the code and verifier at `/oauth/token` for a short-lived
   opaque access token and refresh token. Denial returns `access_denied` with the
   original state only to an already validated redirect URI.
7. Every MCP request sends its access token as a Bearer credential. Refresh rotates
   tokens but retains the grant identity, so the MCP session remains usable.
8. The user can view and revoke their connected clients from Account. Client token
   revocation is also supported. A revoked grant cannot be revived by refreshing.

The single `mcp` scope means access to the existing tool catalog within the user's
approved authority. It grants no permission itself. Avoid a second permission
language: Identity remains authoritative for read/write and account hierarchy.
Consent captures permission and tenant ceilings. Current authority can reduce
access; it cannot expand an existing grant beyond approval. User authorization
version and role revision changes require fresh authorization.

This slice offers approve/deny of the user's current authority, without a separate
permission or tenant picker. Approved all-tenant permissions include future tenants;
finite assignments remain a snapshot. Consent must state this distinction plainly.
Approval atomically checks that user identity, authorization version and role
identity/revision still match the rendered request. A change requires restarting
consent, even if it would increase permissions. Never approve unseen authority.

## Wire profile

| Route | Contract |
| --- | --- |
| `/.well-known/oauth-protected-resource/mcp` | RFC 9728 metadata for the canonical MCP resource. |
| `/.well-known/oauth-authorization-server` | RFC 8414 issuer/endpoints, `code`, authorization-code/refresh grants, `S256`, `none`, and `mcp`. |
| `POST /oauth/register` | RFC 7591 public-client registration; server generates UUID client IDs, no client secret. |
| `GET /oauth/authorize` | Validate request and initiate browser login/consent; never approve on GET. |
| `GET /oauth/authorize/:id` | Resume an opaque browser-bound request after login and display consent. |
| `POST /oauth/authorize/:id` | CSRF-protected approval/denial of that transaction. |
| `POST /oauth/token` | Form-encoded code exchange or refresh; no cookies or browser redirect. |
| `POST /oauth/revoke` | Revoke the caller's token/grant; unknown tokens succeed without disclosure. |
| `/mcp` | Existing ExMCP protocol with OAuth-only Bearer authentication. |

Connected-client list/revoke operations use the existing browser-session product
HTTP boundary with CSRF for revocation. They never accept an OAuth grant as a
browser session or expose other users' grants.

Issuer and resource URLs come from validated runtime configuration, not Host or
forwarded headers. The resource includes the exact mount prefix and `/mcp` path.
Standalone Gateway and embedded mounts can point to the Console authorization
server, but must share a deliberately configured resource and persistence boundary.
No silent fallback to a different issuer or API-key mode when configuration fails.

Require the exact resource at authorization and initial exchange; on refresh an
omitted resource retains its binding and a supplied different resource fails.
Validate tokens against that binding on every request. Duplicate parameters,
unknown scopes, unsupported grants/auth methods and request/JWKS URI fields fail
before library processing. Errors never redirect until client and redirect are
validated. Token responses use `Cache-Control: no-store` and `Pragma: no-cache`.

Registered redirects must be HTTPS or explicit HTTP loopback addresses for native
clients. Reject fragments, userinfo, wildcards, invalid hosts and ambiguous URLs.
Match the complete registered URI exactly; clients register their selected
loopback port. Do not fetch registration URLs, logos or client documents.

DCR is the initial interoperability mechanism. Client ID Metadata Documents are
recommended by MCP but deliberately deferred: Boruta's request schemas require
UUID client IDs, and URL documents introduce an outbound fetch/SSRF boundary.
Advertise DCR truthfully and do not advertise CIMD support. Clients requiring CIMD
without a DCR fallback will not connect in this slice. Revisit with demonstrated
client need rather than adding URL fetching merely for a second onboarding path.

Initial bounds: 60-second codes, 10-minute access tokens, 30-day absolute grants
and refresh expiry (rotation does not extend the grant). Authorization transactions
expire after 10 minutes. Registration accepts a 120-byte name and at most five
2,048-byte redirects; forms are bounded to 16 KiB. Rate limits return 429 with a
60-second Retry-After. Fixed one-minute address/global limits are registration
10/200, authorization 60/600, token 120/2000 and revocation 60/600. The Console resolves client addresses through its existing
trusted loopback proxy boundary; standalone Gateway defaults to the peer address.
Address buckets contain hashes and retain at most three windows per operation.

Storage quotas are 10,000 clients, 100 active grants/user, 10,000 token pairs/grant,
10 active pending requests/browser and 10,000 active pending requests globally.
Registration and issuance perform bounded cleanup. Clients unused for 24 hours can
be removed, but live grants or pending consent protect them. Rotation does not
extend absolute expiry. Quotas fail closed; deployments expecting larger traffic
must deliberately adjust these bounds and verify admission under contention.

## Authority and persistence

`Identity.Principal` carries explicit OAuth provenance and grant ID. Its
browser session field remains nil for OAuth; never invent a browser session or
convert a delegated user into a platform API-key operator. Use the stable grant ID
for MCP session ownership, separate from a particular access token.

Identity owns principal construction, permission intersection and port contracts.
Persistence owns OAuth client, authorization transaction, grant, code and token
records, locking and cleanup. Console owns browser login/consent/account pages.
Gateway owns thin OAuth HTTP and MCP resource adapters. Boruta context modules
belong with their persistence implementation; the protocol caller declares its
own Boruta dependency. No Gateway-to-Persistence dependency or new deployment.

Hash opaque codes and access/refresh tokens at rest. Keep raw values only during
issuance and request verification. Suppress query parameters and credentials from
logs, telemetry, exception messages and process diagnostics. Store only safe grant
metadata for the Account page. A database failure fails closed.

Code consumption and successor issuance run in one database transaction with row
locking. Refresh does likewise. A verified replay of a consumed refresh token
revokes its whole grant; this revocation must commit despite returning
`invalid_grant`. Wrong client/verifier/resource requests must not consume valid
credentials or revoke somebody else's grant. Revocation and code/refresh exchange
use a consistent lock order and bounded database timeouts.

A user authorization version increments on the existing password, recovery,
role, membership and status invalidation paths. Grants also capture role identity
and revision. Every token use and refresh checks the enabled user, current versions,
grant expiry/revocation and resource; disable/reactivate cannot revive old grants.
Browser logout ends its own session, not separately consented connections.

MCP tool discovery must follow delegated read/write permissions rather than
machine-key buckets. Invocation independently enforces shared domain
policy. Tenant listing must apply the delegated ceiling before admin/all-tenant
shortcuts. Account writes revalidate the grant and current user inside their
existing transaction and audit user plus grant provenance, without accepting
client-supplied actor fields. Admin cannot manage Admin/Superadmin accounts; ordinary
users cannot acquire account-write access through OAuth.

## Why these boundaries

The inspected Boruta 2.3.8 release supports custom contexts for clients, resource
owners, scopes, codes and tokens. Its defaults allow plain PKCE/wildcard redirects,
do not retain `resource`, store raw tokens, and issue successors before separately
revoking predecessors. These are source findings, not runtime test results. Custom
contexts and a transaction boundary are required before exposing the endpoint.

Rejected alternatives: hand-writing the entire OAuth protocol, a separate identity
service, replacing ExMCP, copying Boruta's full generated OIDC schema/controllers,
and treating a browser cookie or API key as an OAuth token. A JWT access token is
unnecessary when each request already needs current revocation/permission checks.

Sources: [MCP authorization profile](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization),
[Boruta integration](https://boruta.hexdocs.pm/provider_integration.html),
[Boruta PKCE](https://boruta.hexdocs.pm/pkce.html),
[pinned release archive](https://repo.hex.pm/tarballs/boruta-2.3.8.tar),
[security advisories](https://hex.pm/packages/boruta/advisories),
[OAuth security BCP](https://www.rfc-editor.org/rfc/rfc9700.html).

## Migration and verification

The cutover follows local acceptance of the complete OAuth flow. Existing MCP
sessions cannot be reused after the change: clients must reconnect and authorize
through OAuth. API keys are rejected at `/mcp`; public HTTP API keys remain valid
on their existing routes.

Verification covers real Boruta plus local PostgreSQL, concurrent exchange/replay,
discovery/registration/browser consent, disabled and reduced-permission users, all
17 tools across existing mounts, refreshed-session continuity and cross-grant
isolation. Use the pinned MCP reference client, synthetic accounts and local calls.
No live provider, external telephony or deployment is necessary. Check the consent
and connected-client pages in rendered desktop/mobile browsers. Record actual
experiment and review outcomes in the milestone before marking it complete.

## Runtime configuration

With database-backed Console enabled, the authorization server uses the configured
application origin (`APP_HOST`, `PORT`, and the existing development TLS setting).
The canonical resource defaults to that origin plus `/mcp`.
`VXPIPE_MCP_RESOURCE_URL` overrides the exact resource for an embedding mount;
it does not create the mount or change the configured allowed hosts. Use the same
canonical resource on Gateway and Console, including any path prefix. Changing
it requires client reconnection and new consent; old tokens remain bound to the
old resource and cannot authenticate against the new one.

Application hosts composing Gateway directly configure both `mcp:` and `oauth:`
with `enabled`, `issuer`, `resource`, `allowed_hosts`, `allowed_origins` and
`allow_loopback_http`. Defaults are disabled. Enabled configurations reject
missing or invalid URLs at startup. The standard Console browser issuer has no
path prefix; lower-level metadata supports issuer prefixes for hosts supplying
matching browser routes. The normal deployment needs no separate OAuth issuer
setting or secret: clients are public and use PKCE.

Identity uses its configured `oauth_store` and `oauth_browser_store` ports; the
standard runtime selects Persistence implementations when PostgreSQL is enabled.
Missing or failing storage never falls back to API-key authentication.

Migrate the database before enabling the routes. Reconnect existing MCP clients
and remove static API-key Authorization overrides. Old MCP sessions use different
principal identities and cannot continue; product HTTP API keys remain unchanged.
Account lists connected clients with creation/expiry and a revoke action. Browser
logout does not revoke these independent grants.

Database-enabled production requires a configured public HTTPS application origin
(`APP_HOST`); the loopback HTTP exception is for development/test only.
