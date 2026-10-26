# Hosted integrations directory: API handoff

Status: v1 handoff, updated 2026-10-25 against the deployed external API. The
directory service exists in its separate project. VxPipe consumption and outbound
OAuth remain proposed; see [the consumption decision](integrations-directory-consumption.md)
and [implementation tasks](../../labnotes/milestones/integrations-directory-and-tenant-mcps.md).
The Storybooks make no remote requests. Default API origin:
`https://integrations-api-production-2803.up.railway.app`.

## Ownership and composition

Vxpipe is self-hostable. Its app-owned provider catalog defines AI model and
telephony adapters, capability tags, credential forms and model behavior. A
remote listing cannot install an adapter or introduce a new AI/telephony provider.

The hosted directory supplies tenant-only MCP categories and connection templates,
and browse/search listings containing MCP, AI and telephony entries. AI/telephony
entries reference installed provider adapters; they never download code. Browse
uses the API by default; outage fallback lists installed native providers only.
Both tenant Integrations and Platform Integrations default to Connected
integrations. The first three category URLs (`connected`, `ai`, `telephony`) are
reserved and local. Remote categories follow the second separator in tenant
navigation; they never appear in Platform Integrations. The mobile dropdown and
breadcrumbs use the same category IDs and display names.

| Data | Authority |
| --- | --- |
| AI/telephony catalog, capabilities, adapters | Installed Vxpipe version |
| Effective connected integrations and permissions | Installation database, scoped to the tenant or platform |
| MCP categories/templates and global search index | Configured hosted directory |
| Actual OAuth metadata, capabilities and tool catalog | Connected MCP server and its authorization server |
| Secrets, consent, tokens, connection health, tool allowances | Installation; never the public directory |

Do not send tenant IDs, connection IDs, credentials, enabled-state data or local
installation callback URLs to the public directory. Prefer a Console-owned
backend fetch/cache that serves validated public catalog data to the browser.
This avoids requiring each self-hosted domain to be registered with the directory.
The directory is an anonymous public read API, not an OAuth application.

Directory metadata supplies the displayed MCP name, endpoint and authentication
recipe; ordinary listed-service forms do not ask users to edit those values.
Only custom MCP setup exposes endpoint/auth configuration. The app derives required
credential fields from the recipe and validated live metadata. Automatic CIMD/DCR
registration handles callback URLs internally; manual registration shows the
callback only when the user needs to copy it into the provider setup.

## Remote HTTP contract

V1 is paginated. Do not download every integration to render, filter or search a
category. The public API owns filtering, sorting, totals and opaque cursors:

```http
GET /v1/categories?limit=100
GET /v1/integrations?category=calendar&limit=20&revision=2026-10-25.1
GET /v1/integrations?q=booking&limit=20&scope=tenant
GET /v1/integrations?q=booking&limit=20&scope=tenant&cursor=<opaque-token>
Accept: application/json
X-VxPipe-Version: 0.1.0
If-None-Match: "page-specific-etag"
```

| Parameter | Contract |
| --- | --- |
| `category` | Optional browse filter; must be absent when `q` is nonempty |
| `q` | Optional global search, maximum 200 characters; searches names and summaries across MCP, AI and telephony entries, with no category filter |
| `scope` | `tenant` (default) or `platform`; platform results exclude MCPs, maintaining the existing platform boundary |
| `limit` | Integer 1–100; default 20 for integrations, 100 for categories |
| `cursor` | Opaque continuation or previous-page token; omit for first page; maximum 2048 characters |
| `revision` | Optional first-page snapshot revision obtained from categories; a cursor binds its own revision |

Return `resource`, `items` and `pagination` using
[the JSON Schema](integrations-directory.schema.json). Pagination contains
`limit`, `total_items`, `start_index`, `end_index`, `next_cursor` and
`previous_cursor`. Indices are 1-based; an empty result has both indices zero.
First/last-page cursors are null where no corresponding page exists. A previous
cursor may return the first page; it is not inferred from arithmetic in the client.
The totals and range belong to the same normalized query, installation version
and snapshot as the rows. Incompatible entries are removed before counting and
paginating, not hidden after the client receives a page.

- `200 application/json`: one complete, validated page, never the entire directory.
- `304`: unchanged page; retain the matching validated cache entry.
- `400`: missing/malformed version header, invalid parameters, category-scoped
  search, or cursor used with different resource/query/scope/limit/version;
  distinguish `invalid_version`, `invalid_cursor` and `cursor_mismatch`.
- `422`: well-formed but unsupported/unknown installation version; code
  `unsupported_version`. Do not guess that it supports all adapters.
- `404`: unknown category; show category unavailable rather than an empty result.
- `410`: snapshot/cursor expired; code `cursor_expired`. Offer Start from first
  page, clear the cursor and old snapshot, and retain category/search.
- `429`: honor `Retry-After`; keep the current page and offer retry.
- `503`: temporarily unavailable. Error envelope:
  `{ "error": { "code": "directory_unavailable", "message": "Try again later." } }`.
- `ETag` is specific to resource, snapshot, filters, scope, cursor, limit and
  installation version. Send `Vary: X-VxPipe-Version`; a 304 from one version must
  never validate another version's page.
  `Cache-Control: public, max-age=3600`; HEAD and conditional GET are supported.
- HTTPS; no cookies or authorization. Optional browser access uses
  `Access-Control-Allow-Origin: *` without credentials. Permit the
  `X-VxPipe-Version` request header in CORS preflight responses.
- No tenant-specific responses, connection status, credential collection,
  tracking IDs, webhook registration or executable downloads.

Cursors are server-issued, integrity-protected and bound to resource, normalized
filters, scope, limit, ordering, installation version and snapshot revision. A client stores/replays them
without decoding, incrementing or constructing a URL from them. Publish category
and integration revisions atomically and retain cursor snapshots for at least
24 hours. Insertions/deletions must not cause duplicates or missing rows within a
valid paging session. Do not silently switch snapshots mid-list. Cursors contain
no secrets or tenant data and must be safe to put in a browser URL.

Both endpoints are paginated. Vxpipe follows category cursors to assemble the
small navigation taxonomy, retaining a loaded category list during retries; a
partial category response is not the complete sidebar. Integration pages are
fetched on demand. Do not follow their cursors in the background to reconstruct a
full catalog. Bound each response to 1 MiB uncompressed and 100 items. There is no
500-entry directory-wide limit. Bound metadata loading too (for example, at most
1000 categories); an overflow is an explicit compatibility error, not silent
truncation.

The [example response](integrations-directory.example.json) is a fictional
integration page; [the categories example](integrations-directory.categories.example.json)
shows navigation metadata, and [the search example](integrations-directory.search.example.json)
mixes native provider and MCP results. The Storybook dataset in `remoteDirectory.ts` models
server storage, not a proposed complete-catalog response. `directoryPageFixture.ts`
simulates the server query and returns only a page; it makes no network requests.

### Vxpipe pagination behavior

Use Previous/Next controls below the list and a range such as `21–40 of 126`.
Disable Previous on the first page and Next on the last. The UI consumes returned
cursors and totals, never infers total counts from the current page length.
Search opens a distinct Search results page and queries all integration kinds and
categories across all pages; it does not filter the selected category or downloaded
rows. Selecting a category exits search and clears the query/cursor; changing the
query also resets pagination. Debounce live
search requests in the production client and cancel/ignore superseded requests.

Browse at `/services/<category-id>` and search at `/services/search?q=...`. Include
`q` and `cursor` in the URL so reload, links and browser
Back/Forward restore the same results. Search edits replace history; explicit page
and category changes push history. Credential dialogs preserve this context when
closed. In-flight pagination keeps the current rows and marks them busy while
preventing duplicate page requests. Failure keeps those rows with Retry page;
retry the failed request, not an unrelated first page. A completed new-page request
replaces the visible rows; do not append infinite-scroll results.

Join MCP rows with local connections by permanent directory/entry IDs, and native
provider rows by local provider ID. Pagination of the public directory must never make a connected entry
appear unconnected. The independent complete local status projection described
below remains authoritative. Keep it in local state across page transitions;
refresh it on mutations. Backend authorization still applies to every edit/save.

The preview includes paginated results, a pending next page, a failed next page,
and expired-link recovery. Pending/error stories are explicit review states;
production request cancellation, debouncing, caching and race handling are planned
contracts rather than implemented network behavior.

## Catalog fields

| Field | Requirement and meaning |
| --- | --- |
| `schema_version` | Required integer `1`; unknown major versions are rejected |
| `directory_id` | Required permanent namespace; retained by mirrors, never reused by a different directory |
| `revision` | Required opaque catalog revision; no ordering assumptions |
| `resource` | `categories` or `integrations` |
| `items[]` | Current page of category records or integration records (MCP templates/native provider references) |
| `pagination` | Authoritative query total/range and next/previous cursors |
| `installation_version` | Required echo of the validated request header |
| `query` | Integration responses echo `category` (null for search), normalized `q`, and `scope` |

Category IDs and integration IDs use lowercase slug syntax, are unique within
their respective arrays, and are never derived from display names at runtime.
Remote category IDs cannot be `connected`, `ai`, `telephony` or `search`. Rename a label without
changing its ID. Category links remain `/services/<category-id>` in this preview.
An entry may belong to several categories. Each category includes a required
`integration_count` computed by the API from the full version-compatible snapshot,
independent of the current search; do not count only the loaded integration page. Sort categories by `(order, id)` and
entries by display name then ID. The connected category count comes from local
connections, including effective inherited AI/telephony connections.

| Integration field | Requirement and meaning |
| --- | --- |
| `id`, `revision` | Permanent entry ID plus monotonically increasing positive entry revision |
| `name` | Required display name; plain text |
| `summary` | Optional short plain text; omit without leaving an empty UI row |
| `logo_url` | Optional HTTPS image URL; generic MCP icon if missing or failed |
| `kind` | `mcp` or `provider` |
| `minimum_vxpipe_version` | Optional lower bound; absent means no additional minimum. Native providers still require a compatible registered adapter |
| `maximum_vxpipe_version_exclusive` | Optional exclusive upper bound for removed/changed integrations |
| `category_ids` | MCPs reference remote categories; providers reference local `ai` or `telephony` |
| `setup_url` | Optional HTTPS MCP setup link; show as Setup |
| `documentation_url` | Optional HTTPS MCP documentation link; show as Documentation. Required for native providers |
| `availability` | `available`, `preview`, or `retired`; previews get a small label, retired entries cannot be newly connected |
| `setup_notes` | Optional plain text up to 1,000 characters, shown above the Setup / Documentation link row |
| `connection.type` | `mcp` for protocol templates; `builtin` for native provider references |
| `connection.provider_id` | Required only for `builtin`; stable ID from the app provider catalog |
| `connection.transport` | MCP-only: `streamable_http` |
| `connection.endpoint` | MCP-only: complete HTTPS MCP URL, preserving its path |
| `connection.authentication` | MCP-only: setup recipe below; native providers use local credential forms |

HTTPS endpoints must have a host and no username/password, fragment or secret
query parameters. V1 publishes fixed endpoints without query strings or templates.
Account-specific/region-specific addresses can be entered through Connect other
MCP until a versioned, bounded endpoint-parameter contract is agreed. Do not ship
arbitrary interpolation, executable form definitions, scripts or custom adapters.

MCP `setup_notes`, `setup_url`, and `documentation_url` are independently optional.
Omit unavailable fields rather than returning null or empty strings. Show notes as
plain text above the supplied links; omit the entire information block if all are
absent. The hosted API reads legacy persisted `setup_note` values but emits only
`setup_notes`; new contributor definitions use the plural field.

## Global search and installation version

WordPress's Add Plugins screen offers directory search and paginated results; its
plugin API accepts search/page arguments and supplies the current WordPress version.
That is the interaction inspiration, not an API compatibility target. Vxpipe uses a
required version header and a single global search mode, without WordPress's
keyword/author/tag selector. [WordPress search](https://wordpress.org/documentation/article/plugins-add-new-screen/),
[plugin API](https://developer.wordpress.org/reference/functions/plugins_api/)

Every directory request carries `X-VxPipe-Version`, including categories, search,
next/previous pages, retries and conditional GET/HEAD. Send the full release version,
not a truncated major/minor value. Responses echo `installation_version`. Add the
version to caches and cursors; an upgrade invalidates older search/page results.

Header names are case-insensitive. `X-VxPipe-Version` is the spelling used in
examples and outbound requests; `x-vxpipe-version`, `X-VXPIPE-VERSION` and other
case variants identify the same field. Use the HTTP framework's case-insensitive
header lookup, including cache and CORS handling. This applies to the header name;
preserve and validate the version value as supplied.

The API maintains a release-to-supported-adapters manifest. Populate it from
Vxpipe release artifacts/catalog metadata, rather than assuming any remote provider
entry can run locally. Return only integrations supported by the requested release;
apply semantic-version bounds and registration/transport capabilities before sorting,
counting or paging. Include AI/telephony entries only where that release contains
their adapter. MCP entries also have a minimum supported protocol-client version.
Known removal or incompatible changes use an upper bound or explicit supported
release mapping. Keep unavailable/incompatible matches out of results, rather than
offering a Connect button that cannot work. Newer-than-tested is not automatically
incompatible; the release support manifest is authoritative. Unknown custom or
prerelease versions require an explicit manifest entry; never fail open.

A `provider` result contains a local `provider_id`, not a remote endpoint, secret
schema or executable integration. The client uses its canonical provider catalog,
capability tags, credential form and runtime implementation. Defensively reject a
provider reference absent from the installed registry even if the API returns it.
MCP connections remain declarative and tenant-only. Platform global search is
limited by `scope=platform` to AI/telephony; this is a product boundary, not a
user-selectable category search filter.

### Programmatic version source

`VERSION` at the repository root is now the shared product build version, currently
`0.1.0`. The umbrella and all child `mix.exs` files read it when building. The
umbrella itself is not an OTP application; `Application.spec(:vxpipe, :vsn)` is
therefore nil. Loaded runtime applications expose the same embedded release value:

```elixir
Application.spec(:vxpipe_console, :vsn) |> to_string()
Application.spec(:vxpipe_gateway, :vsn) |> to_string()
```

This needs no runtime filesystem read and works in a release without Mix.
`Mix.Project.config()[:version]` is appropriate at build time only. Storybook and
Vitest read the same `VERSION` file into a build constant; the preview request
builder uses that constant for its headers. Do not duplicate a version literal
in JavaScript or use the npm SDK package version as the installation version.

The future backend directory client owns the header and reads its own embedded
application version. If the production browser queries directly, provide that
version through authenticated Console bootstrap data; do not trust editable local
storage. Split Console/Gateway deployments must verify runtime adapter support
before enabling a connection if their deployed release versions differ. A catalog
match cannot override the actual runtime registry. VERSION centralization is
implemented; production bootstrap and directory networking remain future work.

## Authentication recipe

`authentication` is one of the following discriminated objects. It selects the
initial form; it is not proof of server support. Advanced manual configuration
remains available in Connect other MCP. Unsupported recipes disable new connection
with an explicit compatibility explanation; never treat them as no authentication.

| `type` | Additional fields | Credential flow |
| --- | --- | --- |
| `oauth2` | `registration`, optional `scopes: string[]` | Browser consent; client details obtained or entered as below |
| `bearer` | None | User enters a masked bearer token |
| `api_key` | Required `header_name` | User enters a masked value for that header |
| `basic` | None | User enters username and masked password |
| `none` | None | Explicit anonymous connection |

For `oauth2`, `registration` is `discover`, `cimd`, `dcr` or `preregistered`.
`discover` uses the supported registration mechanisms discovered from the server;
`cimd` and `dcr` express a preferred setup mode; `preregistered` asks the user for
the client ID and any required secret/key. CIMD and DCR are registration methods,
not alternatives to OAuth consent. The approved MCP profile describes protected
resource and authorization-server discovery, CIMD capability metadata, DCR and
preregistration. Use that discovery at connection time; directory hints cannot
override it. [MCP authorization](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization)

Scopes in the catalog are suggested capabilities for this template, displayed for
review, not a permission grant. The installation owns scope selection, state,
PKCE, redirect URI construction and token storage/refresh. Use its configured
externally reachable client-metadata and callback endpoints; do not hardcode the
directory's domain or a shared Vxpipe callback. Separate Gateway/Console deployments
must use the origin of the actual endpoint owner.

Bearer, API-key and Basic recipes describe server-specific credential mechanisms;
this proposal does not label them OAuth registration standards. Public recipes
never carry client secrets, API keys, authorization headers, tokens, private keys,
user data or a globally shared OAuth client ID. V1 omits issuer and authorization/
token endpoint overrides: discover them from the MCP server, or enter explicit
manual configuration locally. V1 also excludes client-credentials grant extensions.

Remote MCP uses a Streamable HTTP endpoint; no subprocess commands, npm packages
or stdio launch instructions are installed from this directory.
[Transport specification](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)

## Joining with installation connection records

The local service layer must return a complete connection-status projection
independent of the paginated credential inventory. Proposed local read boundary:
`GET /api/tenants/{tenant_key}/integration-status`. This route is a future proposal,
not implemented in this checkpoint. The request is authorized for that tenant.
Response records contain only public status and opaque connection IDs, for example:

```json
{
  "revision": "tenant-config-42",
  "complete": true,
  "connections": [
    { "kind": "provider", "provider_id": "deepgram", "connection_id": "cred_1", "source": "platform", "status": "connected", "can_edit": true },
    { "kind": "mcp", "directory_id": "vxpipe-public", "integration_id": "calcom", "connection_id": "mcp_1", "source": "tenant", "status": "connected", "can_edit": true }
  ]
}
```

The example IDs are fictional. Derive effective AI/telephony status after applying
tenant overrides. Third-party MCPs have tenant scope only. `can_edit` describes
access to the local management flow; it does not give a tenant permission to edit
platform secrets. Managing an inherited provider requires installation-scoped
`platform_services.write`; an authorized editor can offer a tenant override.

Match providers by local provider ID. Match MCPs by the tuple
`(directory_id, integration_id)` stored on the saved connection. Do not join by
name, description or URL. Renames and endpoint revisions retain identity; two
entries sharing an endpoint remain distinct. Manual MCP connections have no
directory identity and remain manageable under Connected integrations. Linking a
manual connection to a directory entry requires explicit user confirmation.

| Resolved state | Directory action and marker |
| --- | --- |
| No record in a **complete** local projection | Connect |
| Connected | Edit plus double checkmark, accessible label “Connected” |
| Inherited AI/telephony | Double checkmark, no source label; Edit requires platform write permission |
| Expired/revoked/invalid | Edit plus attention marker; never a connected checkmark |
| Read-only user | Status remains visible; write action disabled |
| Status loading | Checking connected integrations; no Connect/Edit action yet |
| Status unavailable or incomplete | Retry connections; no inference that an absent record is unconnected |

The checkmark means the local record is enabled/configured successfully, not a
fresh remote health probe. Do not contact every MCP before rendering. Distinguish
known expired/invalid state from temporary remote health failures.

On save, disconnect or override, refresh/invalidate the local projection and
update the row immediately. Recheck identity and authorization on mutation; a
concurrent duplicate returns a conflict that offers the existing editor instead
of saving another credential. V1 assumes one directory-backed connection per
identity per tenant; custom MCPs can still be added independently. If multi-account
connections are later allowed, Edit must open a connection chooser, not pick the
first account silently. Enforce this constraint in the future local backend.

Save the entry revision and the accepted endpoint/auth configuration with the
connection. A directory refresh must never rewrite an existing connection,
redirect its credentials to a new origin, broaden scopes, enable newly discovered
tools or revoke a working connection. Tool lists are discovered after connecting;
the agent still saves explicit tool names, not directory-provided wildcard grants.

## Offline, lifecycle and trust boundaries

- Fetch/cache public catalog data independently of connection status. Start with
  local categories; show skeletons only for pending directory content.
- A failed initial fetch leaves Connected integrations, AI/Telephony and Connect
  other MCP available. Show a targeted Retry directory message.
- After a failed refresh, use installed AI/telephony listings and retain local
  connected inventory and custom MCP setup. The cached-directory Storybook is an
  older discussion alternative, not the selected production fallback. No live
  call depends on the directory's availability.
- An empty complete category listing hides remote categories. An empty integration
  search result does not remove categories. A missing category URL shows an
  unavailable state, preserving local navigation. A retired/removed entry never
  deletes local credentials; management uses the saved connection snapshot.
- Configure the directory base URL at installation level; disable it or point to
  a compatible mirror. Bound fetch duration (5 seconds), redirects, body size and
  retries. Cache pages for an hour by directory/version/resource/revision/query/scope/cursor/limit; retain
  validated offline pages across restarts. Never reuse a page from another filter.
- Validate each full page before replacing its cache entry, including referential
  integrity, duplicate/reserved IDs, supported schema/transport/auth variants and
  URL rules. Reject invalid pages atomically; retain the previous valid page. Ignore unknown optional fields
  within v1; unsupported discriminant values are not silently accepted.
- Treat remote metadata as untrusted data. Render text as text, never HTML. Serve
  logos through a bounded validated image cache; allow PNG/WebP/JPEG, rasterize or
  reject SVG, and fall back to a local icon. No arbitrary per-logo browser tracking.
- Revalidate MCP/OAuth/image destinations, redirects and DNS at the network
  boundary. Public-directory entries cannot opt into loopback/private/link-local
  hosts or cloud metadata. Explicitly configured private custom MCPs require the
  installation's separate network policy; catalog content cannot grant an exception.

## Handoff acceptance checklist (original external-service requirements)

External-service completion is tracked in its own repository. This checklist is
not evidence of VxPipe consumption; use the new milestone for application work.

Directory project:

- [ ] Validate the required version header and maintain release adapter manifests;
  exclude unsupported integrations before computing counts/pages.
- [ ] Accept version-header names in any casing and verify identical filtering,
  totals, cache identity and pagination behavior for equivalent requests.
- [ ] Publish paginated `/v1/categories` and `/v1/integrations`, their JSON Schema,
  page-specific ETags, atomic snapshots, HEAD and conditional GET support.
- [ ] Reject missing endpoints/docs, secrets, reserved/duplicate IDs, dangling
  category references, unsupported auth/transport variants and over-limit bodies.
- [ ] Use permanent identities; support label changes, revision increments and
  retirement without ID reuse. Review provider endpoints/docs before publication.
- [ ] Add fixtures for OAuth discovery/CIMD/DCR/preregistration, bearer, API key,
  Basic, anonymous, absent/broken logos and retired entries.
- [ ] Test global search across MCP/AI/telephony, rejection of category-scoped
  search, version filtering, removed adapters, unknown versions and Vary/ETag isolation.
- [ ] Test first/middle/last/empty pages, previous cursors, cross-page search,
  stable totals, snapshot mutation during paging, and cursor/filter mismatch.
- [ ] Test 200/304/400/404/410/422/429/503, cache keys, expired snapshots, corrupt pages
  and publication rollback.

Future Vxpipe integration:

- [ ] Implement validated cached reads and the complete authorized local status
  projection; no production remote requests exist in the current Storybooks.
- [ ] Test tenant isolation, inherited overrides, matching by stable identity,
  unknown/incomplete status, duplicate-save races, and disconnect invalidation.
- [ ] Obtain request version from embedded release metadata, reset cache/cursors on
  upgrade, and reject native provider IDs missing from the actual runtime registry.
- [ ] Verify self-hosted callback/CIMD URLs against actual deployed endpoint owners.
- [ ] Exercise discovery and protocol auth with conformance fixtures separately
  from catalog rendering. Verify no directory update changes stored endpoints,
  secrets, scopes or explicit agent tool allowances.
- [ ] Verify URL/history restoration, filter reset, pending/error page retention,
  retry of the same request, canceled/out-of-order requests and expired-link recovery.
- [ ] Keep local providers and saved MCP management usable while offline; cached
  remote pages must not imply the rest of the directory has been downloaded.

## Alternatives considered

- Category-scoped search: rejected by the user. Category links browse; search
  covers all kinds/categories available to the installation version.
- Bundling every MCP in the application: rejected; requires a Vxpipe release to
  update a protocol-based catalog. AI/telephony adapters remain bundled by design.
- Returning tenant connection status from the public API: rejected; the directory
  has no tenant authority and must not receive private installation state.
- Inferring connection identity from an endpoint/name: rejected; aliases, renamed
  products, account-specific addresses and shared endpoints make it ambiguous.
- Downloading executable integration plugins: outside this design. Only
  declarative MCP templates cross this boundary.
- Downloading a full catalog and paginating/filtering in the browser: rejected;
  the user requires a paginated remote API. Query and snapshot consistency belong
  to the API, while Vxpipe renders returned pages.

## Current verification

The Storybook prototype covers connected/unconnected rows, inherited-provider
editing, disconnect updates, data-driven categories and routes, loading, stale
cache, directory outage, connection-status failure, reconnect-needed state and
cursor pagination with global MCP/AI/telephony search, version exclusion, retry
and URL recovery. All three example responses validate against the JSON Schema;
missing version echoes and category-scoped search responses are rejected. Runtime
inspection confirms umbrella, Console and Gateway version metadata is `0.1.0`.
It is a UX/API-shape review, not validation of production interoperability.
