# Integrations directory consumption and unlisted MCPs

Status: proposal for review, 2026-10-25. The accompanying Storybooks simulate the
workflow; production API consumption, persistence and outbound OAuth are not
implemented by this checkpoint. Delivery tasks and acceptance gates are in
[the milestone](../../labnotes/milestones/integrations-directory-and-tenant-mcps.md).
This document supersedes earlier proposals that always served AI/telephony browse
results locally. The installed adapter registry remains authoritative for what
VxPipe can actually connect.

## Directory authority and fallback

Use `https://integrations-api-production-2803.up.railway.app` by default. A runtime
operator setting, `VXPIPE_INTEGRATIONS_DIRECTORY_URL`, may replace that origin;
validate it as an HTTPS origin, never accept one from tenant/browser input. It is
independent of the Installation URL and Gateway public URL. Do not add a tenant
configuration field for the directory origin.

Both tenant Integrations and Platform Integrations open **Connected integrations**.
That inventory always comes from the installation, even when the public directory
is healthy. The directory supplies browse/search listings for AI models,
Telephony and tenant MCP categories. AI and telephony category identities and
labels remain app-owned; the other categories come from the API. Every category
keeps its own route and breadcrumb. Platform never displays/connects MCPs.

| Situation | Expected screen and action |
| --- | --- |
| First directory request | Loading state; local connected inventory remains usable |
| Valid API page | Render that page, join local connection status, show Connect or Edit with connected indicator |
| Timeout, offline, 429/5xx, invalid envelope or unknown installation release | Show the notice below sidebar categories (below the selector on mobile): “Integration directory unavailable” / “Showing built-in AI and telephony services”. Offer installed AI/telephony, local connected inventory and tenant custom MCP setup |
| Search during outage | Search installed AI/telephony only; retain the concise sidebar notice and preserve search when Retry succeeds |
| Remote category URL during outage | Retain URL/breadcrumb, show the installed-services fallback and available local navigation; do not imply the fallback belongs to that remote category |
| Successful empty result | Show empty results; do not silently replace it with local results |
| Next-page failure | Keep the last valid rows and offer retry for that page; never append local rows to remote totals |
| 410 expired cursor | Offer restart at the first page; preserve category/query, discard cursor/revision |
| 404 category | Category unavailable; offer the remaining navigation, not a fake outage |
| Local connection-status failure | Unknown status and retry; do not present a duplicate Connect action |
| Existing connection missing/retired in directory | Keep it manageable from Connected integrations using its saved identity/configuration |

Fallback uses `Vxpipe.Providers.Registry` capabilities and the existing
`installedSetupProviders` projection, intersected with executable installed
credential adapters. It is not a hardcoded list of every provider in the frontend
catalog. No MCP fallback templates, executable code downloads, or platform MCP
inheritance. AI/telephony tenant overrides retain their existing precedence,
including invalid overrides. Prototype fixtures represent the fully installed
standard build; production must use its actual capability projection.

The latest live read returned **three MCP entries and no native providers**.
Before enabling production directory browsing, add AI/telephony definitions and
the matching release registry in the external directory project. A valid empty
native page must remain distinguishable from an outage. This is a release
prerequisite, not work silently performed in this repository.

## Request, version and cache contract

Console should own a small directory client and authenticated browser facade.
The public directory remains unauthenticated; server-side reads avoid exposing
local connection state or requiring a browser CORS dependency. Each request sends
`X-VxPipe-Version`; HTTP header names are case-insensitive. Read the immutable
release version from application metadata built from root `VERSION`, never an
environment override, user agent or tenant value. Validate at build/release time
that umbrella child versions agree. Unknown versions return 422; present fallback
and record a sanitized diagnostic. The existing shared VERSION wiring is a
prerequisite to verify/finish, not evidence that a runtime accessor already exists.

Use `/v1/categories?limit=100` and
`/v1/integrations?category=<slug>&scope=tenant&limit=20`. Global search sends `q`
and **omits category**; platform requests send `scope=platform`. Send cursors
unchanged. Responses echo `query.category`; entry membership remains
`category_ids`. Consume optional minimum/maximum versions as advisory data;
the API filters compatibility before totals. Also reject native rows without a
local installed adapter. An incompatible native entry is a contract error: do not
silently show misleading pagination. Fall back and emit a redacted diagnostic.

Suggested initial bounds: 5-second request deadline, 1 MiB JSON response,
200-character query, 20 integrations/page, at most 1,000 remote categories, and
one explicit retry action after automatic request failure. Reuse existing HTTP
facilities. Follow all category cursors within that bound before declaring the
navigation complete; integration pages remain demand-loaded. Cancel obsolete
requests on query/category/tenant change and ignore out-of-order responses.

Cache only validated public data. Key by directory origin, installation version,
resource, category/query, scope, limit and cursor/revision. Bound entry count and
memory with expiry/eviction; coalesce concurrent misses. Honor ETag/304 only when
a matching cached body exists, otherwise refetch without the validator. A fresh
cache can serve a request until expiry; on an unsuccessful refresh use the local
fallback. Do not introduce an alternate stale-MCP connection path. The older
CachedDirectory Storybook is retained as an alternative for discussion, not this
milestone's acceptance behavior. Clearing a query/cursor must not clear credentials
in an open connection draft. Retry resets an expired cursor but preserves query.

No tenant IDs, saved statuses, credentials, callback URLs or tool catalogs go to
the public API. Render remote strings as text. Validate logo/documentation URLs;
restrict image loading, use a neutral icon on failure, never execute directory
HTML/SVG as markup. The directory returns `logo_url`; clients do not invent a logo
endpoint or reconstruct bucket paths. Logos may be cached separately without
credentials.

## Connecting a server not listed in the directory

**Connect other MCP** remains available on all tenant categories, including an
outage or empty search. The custom form asks for the complete HTTPS MCP URL and authentication
(default **Discover automatically**). There is no editable connection name: listed
MCPs use the directory name, and custom MCPs use initialized server metadata
(`title`, then `name`; use the endpoint host only as a temporary/fallback label).
Preserve the endpoint path. This is a hosted Streamable HTTP connection; shell commands, stdio
launchers and legacy HTTP+SSE-only endpoints are outside this release. The MCP
transport specification distinguishes subprocess stdio from Streamable HTTP;
using HTTP does not itself imply OAuth. [MCP transports](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)

Discovery checks the endpoint before prompting for secrets. When authorization is
needed, use protected-resource metadata and authorization-server metadata. Prefer
an existing registered client, then advertised CIMD, then advertised DCR; otherwise
ask for client details. CIMD and DCR are client-registration mechanisms, not two
kinds of user permission. Explicit manual choices remain in advanced setup for
providers that need them. [MCP authorization](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization)

Listed MCPs use the directory endpoint and authentication recipe, validated against
live metadata. Do not ask users to choose the authentication type or edit the
endpoint. Prepare only the required credential fields; select grant/client
authentication from the template and discovered provider capabilities. CIMD/DCR
manage callback metadata without displaying callback or client-metadata fields.

Manual registration is the exception: show the exact callback URL when the user
must register it with the provider. Retain MCP identity/endpoint and request the
client ID and any required secret/key. Custom-server setup retains the advanced
client-authentication controls because there is no directory recipe. Provider-specific setup
instructions may be linked when available, but a description/tagline is not
required. Never infer OAuth endpoints from a brand name or send credentials
before endpoint/issuer validation.

| Mode | Configuration to support |
| --- | --- |
| Automatic / CIMD | Discovery; existing Console client metadata document; optional scopes |
| DCR | Discovered registration endpoint; optional initial registration token and validated registration parameters |
| Registered OAuth client | Client ID; none/basic/post token-endpoint client authentication; secret when required; exact callback for authorization-code flow |
| Manual OAuth endpoints | Issuer, authorization/token endpoints, optional revocation URL, scopes, validated resource/audience and provider-specific parameters |
| Bearer | Masked token, sent only to the validated MCP resource |
| API key / custom headers | Named masked headers, excluding transport-managed headers; reject duplicate names/newlines and secret URL parameters |
| HTTP Basic | Username and masked password over HTTPS, only if explicitly configured |
| No authentication | No credentials; do not downgrade a rejected authenticated connection automatically |

The broader existing form also previews client-credentials grants and signed
private-key JWT authentication. Keep them an explicit additional implementation
task with advertised-support checks, key handling, algorithm constraints and
interop tests. Client credentials is a separate MCP authorization extension,
not a substitute for a user's delegated grant. Its application-level credentials
avoid a browser callback. [OAuth Client Credentials extension](https://modelcontextprotocol.io/extensions/auth/oauth-client-credentials)

Callback identity stays on **Console**: Installation URL + `/oauth/mcp/callback`.
The existing Console `/oauth/client-metadata.json` and DCR metadata helper are
foundations; the callback flow itself is not built. Gateway telephony origins may
be deployed separately and must not replace this OAuth identity. Missing/nonpublic
HTTPS Installation URL blocks browser OAuth, while static or anonymous modes stay
available. Changing that URL invalidates in-flight attempts and requires checking
existing registrations before subsequent authorization.

## Remaining backend work

Create tenant-owned connection/configuration, encrypted auth material,
single-use authorization attempts and bounded tool-catalog snapshots. A directory
connection has `(tenant, directory_id, integration_id)` identity and opens its
existing editor on a duplicate attempt. A custom connection uses a durable ID independent of its server-reported display
name; there is no user rename field. Server metadata changes must not change its
stable model-tool namespace. Do not use display names as a uniqueness or lookup
key; different servers may report the same name. Display endpoint context when
needed to distinguish them. Check for an existing custom endpoint before creating
a duplicate connection, and define its canonical endpoint identity at T4.
Use the existing double-underscore naming contract and never expose editable local
tool aliases. Multi-account directory entries are a separate product decision.

Calls owns authorized operations and repository ports; Persistence owns records
and encryption; MCP owns discovery, registration, protocol and token acquisition;
Console owns routes, sessions and forms. Verify the installed ExMCP APIs before
writing competing OAuth machinery. Reuse the existing outbound destination policy
for every resource/discovery/registration/token URL and redirect; authorization
endpoints and metadata are untrusted. Network policy and redirect validation need
to cover DNS rebinding and private destinations, not just input syntax. Private
self-hosted endpoints require operator policy, never a tenant bypass checkbox.
[MCP security guidance](https://modelcontextprotocol.io/docs/2025-11-25/tutorials/security/security_best_practices)

The app must own PKCE S256, single-use session/tenant/issuer-bound state, exact
redirect matching, resource binding, redacted errors, encrypted refresh tokens,
atomic rotation and multi-node refresh coordination. Custom parameters cannot
override these values. Recheck permissions at callback and every management
operation. Token refresh is not a new grant; revocation/disconnect invalidates
runtime use. A live call cannot wait for a sign-in window or retry an ambiguous
submitted tool operation.

Only mark connected after initialization and complete, bounded tool discovery.
OAuth consent alone is insufficient. `tools/list` is paginated; an empty tool set
is distinct from a failed discovery. A server without the tools capability can be
saved with zero usable tools, with a clear status for agent selection.
[MCP tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)

Connecting does not enable tools on agents. The existing MCP checklist expands
Select all into explicit names; later catalog additions never widen allowances.
Keep pinned schemas and safe failures for removed tools. Replace tenant reads of
application-configured MCP fallback across inventory, picker, publication,
preparation and runtime, not just this page. Preserve explicit embedded-library
configuration outside the packaged tenant service path; migration must report any
legacy tenant configuration requiring owner action.

## Alternatives and evidence

Rejected: always-local native browsing (does not follow the requested default API),
fetching the whole directory for client filtering (breaks pagination/global search),
platform-shared MCP grants (violates tenant ownership), a universal OAuth form on
first contact (unnecessary decisions), and treating every failed discovery as no
authentication (misleading and unsafe).

Evidence checked on 2026-10-25: live `/llms.txt` and versioned `/v1/integrations`
read, the external API's matching source contract, local Registry/catalog
projection, existing Installation URL metadata implementation, and the approved
MCP 2025-11-25 references above. The named Storybook states and verification
results are recorded in [the proposal guide](mcp-services-storybook.md) and
[checkpoint labnotes](../../labnotes/20261025-1834-integrations-directory-proposal.md).

## Reviewed UI states

Connected rows show a double checkmark without redundant connected/inherited text.
Inherited native connection management requires `platform_services.write` at
installation scope. Tenant integration write access alone cannot manage a platform
connection. Existing server-side platform credential routes already enforce that
permission; this proposal adds matching controls across connected inventory, hosted
listings and fallback rows. Loading skeletons belong to pending remote content and
never block local inventory.

MCP management uses Authentication and Tools tabs, direct reconnect/credential
editing, account context in the header and an auth-method tooltip. Tools search and
refresh stay outside the independently scrolling tool list. No backend MCP grant
or directory-fetch implementation is included in these Storybook refinements.
