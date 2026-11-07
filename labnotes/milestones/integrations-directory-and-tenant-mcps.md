# Integrations directory and tenant MCP connections

Status: **production implementation in progress (T1–T7); release gates pending**. The Storybook proposal
is part of this specification, not evidence that backend behavior is implemented.
Updated 2026-11-07 with the user-directed Integrations/custom-MCP changes and
implementation progress reconciliation. Those specific decisions are recorded below; full workflow/release approval
remains open. The user authorized implementation of this milestone on 2026-11-06,
including replacement of Services with Integrations for native providers and MCPs.
This milestone makes the hosted
directory the normal browse/search source, preserves installed AI/telephony during
outages, and connects tenant-owned MCP servers whether listed or entered by URL.

## Prerequisites and design sources

Read these completed prerequisites before implementation:

- [Platform and tenant services](platform-and-tenant-services.md): credential
  ownership, provider catalog, tenant override semantics and permission boundary.
- [MCP client library](mcp-client-library.md) and
  [remote MCP tools](remote-mcp-tools.md): protocol profile, destination policy,
  catalog snapshots, leases and pinned tool invocation.
- [Console authentication](console-authentication-and-user-management.md): sessions,
  role/tenant permissions and single authority for management operations.
- [Installation URL and MCP client metadata](installation-url-and-client-metadata.md):
  Console public URL, CIMD document, registration metadata and cache.

[MCP OAuth authorization](mcp-oauth.md) is related existing **inbound** server work;
it does not provide the outbound connection grant implemented here. Do not create
another inbound server or move Console callback identity to the telephony Gateway.

Authoritative new proposal:
[consumption and custom MCP decisions](../../docs/development/integrations-directory-consumption.md).
Also read the [API handoff](../../docs/development/integrations-directory-api.md),
[tenant MCP architecture](../../docs/tenant-mcp-integrations.md) and
[Storybook guide](../../docs/development/mcp-services-storybook.md). Where older
proposals differ, the consumption document and this milestone take precedence.
Existing incomplete onboarding/delivery milestones do not block this slice.

## Implementation contracts and workflow acceptance

- Editing the shared platform credential requires installation-scoped
  `platform_services.write`. Tenant credential writers can override and restore
  their tenant binding through the existing Services operations. Omit source labels
  from listings. MCP manage dialogs
  use Authentication/Tools tabs with reconnect/save controls inside Authentication
  and a stable Disconnect/Close footer. Refresh tools disables its button and
  animates the icon while pending; it adds no success message after completion.
- Directory `setup_notes`, `setup_url`, and `documentation_url` are independently
  optional for MCPs. Show plain-text notes above the supplied Setup / Documentation
  links in connection/authentication content. Generated callback URLs stay muted,
  read-only and copyable.
- Both integration areas default to local Connected integrations. Browsing and
  global search use the hosted API by default, including native providers.
- API failure shows only executable, registered AI/telephony integrations as the
  directory fallback. Connected MCP management and Connect other MCP keep working.
- The API filters versions before pagination; send the actual installation version
  in case-insensitive `X-VxPipe-Version`. Global search never sends a category.
- Native adapters and credential forms stay in VxPipe; remote templates cannot add
  executable integrations. Platform has no MCP catalog or grant inheritance.
- Tenant MCP auth supports discovery with CIMD/DCR and registered OAuth clients,
  plus anonymous/static/custom authentication. Store secrets encrypted; never send
  them or tenant connection state to the public directory.
- Listed MCPs use directory names/endpoints/auth recipes without editable name,
  URL or authentication selectors. Custom MCPs ask for URL and needed auth settings
  and use server-reported names. Hide CIMD/DCR callback metadata; show a callback
  only when manual OAuth registration requires the user to configure it.
- Tools become available only after protocol initialization/discovery. Agents still
  choose an explicit allowlist, independently of connection setup.

## Current custom-MCP contract (2026-11-06)

These user-directed decisions supersede the older automatic-authentication dropdown
and generic advanced controls for CIMD/DCR. They describe production requirements;
the present Storybook implements only a local simulation.

- Entering/changing a complete HTTPS MCP URL starts debounced discovery before
  Connect. The browser makes one installation-backend discovery operation; that
  backend may perform several MCP/resource/OAuth metadata requests. Preserve paths.
- Show pending, checking MCP server, discovering OAuth settings, success, partial
  discovery and failure/retry states inline. A failed check is never proof of
  anonymous access. Do not guess endpoints from a host/brand or reuse the
  prototype's synthetic `/oauth/*` values in production.
- Authentication Type contains actual methods only, with an unresolved placeholder.
  Remove Discover automatically and the Endpoint configuration selector. Managed
  settings are internal; Own client exposes editable discovered values.
- Changing URL invalidates pending responses, old server settings and credentials.
  Closing cancels pending UI work. Editing a field for the same URL takes precedence
  over a later prefill; responses must match the current draft revision.
- Changing authentication type clears old header names/values. Custom headers
  initializes one empty X-API-Key row; other methods initialize no extra headers.
  Reselecting the same method preserves input. Inactive credentials/parameters
  cannot be transmitted or block validation under another method.
- Discovery alone neither creates a connected record nor starts registration,
  consent or token exchange. Connect validates the selected flow and completes
  initialization/tools before reporting readiness. Server identity comes from
  `initialize` (when authorized), not from OAuth protected-resource metadata.

| Authentication Type | Editable configuration in the custom modal |
| --- | --- |
| OAuth - CIMD | None beyond MCP URL and the method; metadata, endpoints, scopes/resource, callback and request parameters are managed |
| OAuth - DCR | Optional masked initial registration token for protected registration; no registration URL/parameter editor or other managed OAuth fields |
| OAuth - Own client | Client ID, applicable secret/key/client-auth/grant fields, copyable callback for manual registration, editable OAuth endpoints/scopes and supported advanced parameters |
| Bearer token | Masked bearer token; explicitly added MCP headers only |
| Custom headers | Editable header names and masked values with Add/Remove; no empty Additional parameters disclosure |
| HTTP Basic | Username and masked password; explicitly added MCP headers only |
| No authentication | No credential or additional-parameter controls |

CIMD/DCR are registration mechanisms, not consent substitutes. The retained DCR
token is an initial access token for registration, not the eventual resource
access token. Its acquisition is out of band; do not claim discovery can supply it.
See [MCP authorization](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization)
and [RFC 7591 §3](https://www.rfc-editor.org/rfc/rfc7591.html#section-3).

## Delivery map and ownership

| Checkpoint | Runnable outcome / owner |
| --- | --- |
| T0 | Reviewed fixture workflows in Console Storybook; no production support claim |
| T1–T2 | Console directory adapter/cache/facade with installed-provider fallback |
| T3 | Production Integrations browse/search and native-service management |
| T4 | Calls-authorized tenant MCP records backed by Persistence; static connection checks through MCP |
| T4a | Non-mutating URL preflight through Console/Calls/MCP plus draft-safe modal integration |
| T5 | Delegated OAuth/CIMD/DCR connection, callback, encrypted grant lifecycle |
| T6 | Own-client advanced methods with explicit interoperability evidence |
| T6a | Trusted listed-template identity and locked connection forms |
| T6b | Explicit retained-ID reconnect and connected-duplicate recovery |
| T7 | Tenant connection source used by picker, publication, preparation and invocation |
| T8 | Cross-slice acceptance, operations and release readiness |

T2/T3 depend on the implemented T1 client; external native-directory publication
blocks release, not local UI development. T1–T3 and T4/T4a can progress independently
after the relevant T0 decisions.
T5 depends on T4/T4a and the completed installation-identity foundation; T6 extends
T5. T7 can validate static connections after T4, but its OAuth acceptance waits
for T5/T6. T6a/T6b precede complete browser workflow acceptance. Runtime admission
and separate-node verification can proceed independently. T8 waits for all applicable
gates. No new milestone/index entry is needed.

## Smaller implementation tasks

Each task is a coherent checkpoint with its own red/green tests and runnable
acceptance. Commit only on request. Keep the umbrella usable between tasks;
production routes remain on the existing flow until their dependencies are ready.

### T0 — Proposal and workflow review

- [x] Research the deployed API, installed provider registry, existing MCP seams and
  the approved protocol profile; record defaults, exclusions and alternatives.
- [x] Add Storybook interactions for API-first listings, installed-provider fallback,
  limited outage search, registration recovery, discovery failure and URL prerequisite.
- [x] Complete focused tests, rendered desktop/mobile review and record evidence (879 frontend tests; TypeScript and Storybook build pass; finish-review fix resolved).
- [x] Update the prototype for URL-triggered discovery, one authentication selector,
  CIMD/DCR field visibility, empty-section removal and header reset on method changes.
  Evidence: [discovery](../20261106-0941-url-triggered-discovery.md),
  [managed OAuth](../20261106-1319-simplify-managed-oauth.md), and
  [header isolation](../20261106-1530-isolate-auth-headers.md).
- [x] Review partial discovery and multi-issuer recovery against the real backend.
  Authenticated browser checks now cover explicit retry with manual-method
  preservation, unavailable-issuer selection and recovery to the working issuer,
  then real consent, saved testing and disconnect. Unsupported OAuth stays blocked.
  See [recovery evidence](../20261107-1304-verify-discovery-recovery.md).
- [ ] Obtain user approval of the complete workflow, including advanced authentication scope.

Acceptance: the user can follow the listed Storybooks from browse through connection
and recovery without a production backend or any credential/network submission.

### T1 — Versioned directory client and external release readiness

Depends on T0 workflow decision; external native definitions are a release gate.

Progress 2026-11-06: added the versioned public request boundary, validated runtime
origin override, bounded HTTP transport and composed schema-validating client with
focused red/green tests. The authenticated inventory endpoint exposes the actual installation version.
Error recovery is implemented; the external catalog release gate remains pending.
The live API still returns only three MCP entries for version 0.1.0. All 13 native
definitions now match the release registry and are committed in the external
definitions repository (`9eef75c`), following independent adversarial review.
The complete local catalog imports and serves all 16 entries, and Console validates
that actual response. Public deployment and native release verification remain open.
See [client implementation evidence](../20261106-1603-implement-integrations-directory.md)
and [native release evidence](../20261107-0859-native-directory-release.md).

- [x] Finish/verify root VERSION-to-OTP build metadata; expose a programmatic runtime
  version accessor and browser response field without a second version constant.
- [x] Configure the default API origin and validated runtime operator override.
- [x] Add a Console-owned public-directory client: schema validation, version header,
  `category`, global `q`, scope, pagination and typed/redacted error mapping.
  Request/Page/Client/Transport tests cover the boundary; the focused directory
  suite passes 34 tests. HTTP 400 distinguishes invalid version/cursor/mismatched
  cursor through a fixed code whitelist, never upstream diagnostic text.
- [ ] Verify/add native entries and this release's adapter IDs **in the separate
  directory repository**, coordinated as an external prerequisite; do not mark
  this task complete against an MCP-only catalog.

Acceptance: local HTTP fixtures assert outgoing version/header/query shape, valid
empty pages, optional compatibility bounds, unsupported schema/version, unknown
native adapters, malformed cursors and bounded response/timeouts. A tagged read-only
live check confirms categories/native/MCP entries for the release, with no secrets.

- [x] Resolve the native-directory missing-icon contract for MorseCode API. Its
  homepage has no declared favicon. Native definitions may omit `icon_url`; the
  publisher skips asset work and the API omits `logo_url`, preserving Console's
  neutral icon. MCP icons remain required and supplied-icon failures still abort
  sync. Definitions commit `0d5fff6` and publisher commit `a5ed7a5` pass Python and
  Go race/vet/build checks plus independent adversarial staged review. Deploy the
  publisher/API before iconless definitions; public release readiness remains open.

### T2 — Bounded public cache and directory outage fallback

Depends on T1. Native connection management remains the existing implementation.

Progress 2026-11-06: supervised public cache and authenticated tenant/platform
inventory endpoints added. Connected inventory is local; browsing joins effective
native/MCP status and provides installed-native fallback on directory outage.
Category navigation and recovery are implemented. Authenticated browser acceptance
remains open; these task checkboxes are not release claims.

- [x] Cache validated pages with ETag, bounded memory/TTL, keyed by origin/version/
  query/scope/page; coalesce misses and handle 304 without a cached body safely.
- [x] Join tenant MCP records into local Connected inventory and directory identity/
  endpoint matches. Keep saved MCP metadata available during directory outage and
  fail closed on MCP status lookup failure. Nine backend tests and five frontend
  parser tests pass. Management controls and rendered fixtures are now implemented;
  authenticated browser acceptance remains open.
- [x] Add authenticated Console facade with local connection-status join and current
  permission filtering. Publish read-safe statuses, never encrypted/plain secrets.
- [x] Derive fallback from installed Registry credential capabilities; exclude
  uninstalled/unsupported adapters. Preserve tenant-over-platform precedence.
- [x] Parse directory 429 Retry-After (seconds or HTTP date) without exposing
  upstream bodies, and suppress additional upstream queries/categories for the
  origin during the bounded cooldown. Invalid/missing headers default to 60 seconds;
  untrusted delays cap at 24 hours. Valid cached pages remain readable. Red/green
  transport/cache tests and 32 focused directory tests pass; rendered recovery and
  broader release acceptance remain pending.
- [x] Implement timeout/429/5xx/schema/unsupported-version fallback, sanitized
  diagnostics, explicit retry and request cancellation/out-of-order protection.
- [x] Add invalid/mismatched cursor recovery to the production directory. Offer
  Start from first page while retaining search/category; invalid version errors
  use installed-provider fallback. Two frontend red/green cases pass, as do all
  eight directory component tests and TypeScript. Chrome desktop/mobile inspection
  verifies the error state and successful restart with the search preserved.

Acceptance: cached/fresh/missing/expired responses and concurrent requests cannot
cross query/version or tenant status boundaries. Outage leaves Connected, AI and
Telephony usable; no remote MCP is falsely offered from a stale listing. A failed
local status lookup never yields an enabled duplicate Connect action.

### T3 — Production browse/search navigation and pagination

Depends on T2; use the approved Storybook layout and existing credential modals.

Progress 2026-11-06: production Services routes now mount Integrations, including
category URLs, search, cursor navigation and existing native credential dialogs.
Native credential lifecycle and production route tests now use the new inventory
API while retaining existing management operations. Desktop/mobile Storybook
inspection exercises production components with local fixture responses. Real
authenticated Console acceptance remains pending.

- [x] Connect tenant/platform routes, category breadcrumbs/mobile selector, default
  connected inventory, app-owned native categories and paginated remote categories.
- [x] Implement global search, cursor history, previous/next, expired-page restart,
  next-page retry, valid empty results and unavailable-category recovery.
- [x] Preserve modal drafts and selected query/category while opening/closing native
  credentials. Match local connection state before deciding Connect versus Edit.
- [x] Mount the tenant custom MCP CTA and saved-MCP Manage controls after the static
  API/preflight foundations; platform/read-only connection creation remains hidden.
  OAuth forms are now implemented under T5/T6. Lifecycle UI tests and desktop/mobile
  production-component fixtures pass; authenticated backend acceptance remains open.

Acceptance: real Console browser checks at desktop/mobile cover healthy directory,
API outage and recovery, direct URL/back/forward, unknown status, permissions and
platform exclusion. Existing native connection/update/override tests remain green.

#### Production inventory and static modal checkpoint (2026-11-07)

- [x] Reuse Services native credential validation, save, override/restore and exact
  named removal behind the Integrations presentation and stable Services routes.
- [x] Join authorized local native/MCP status to hosted browse/search pages, with
  installed fallback, category navigation and cursor recovery.
- [x] Preserve inventory state across production-wrapper navigation; retain the
  previous page after a failed next-cursor request.
- [x] Separate native credential write from MCP service write, including inherited
  platform bindings and read-only management.
- [x] Wire debounced, revision-bound URL discovery to static custom MCP creation and
  management, with credential isolation and catalog-only tools refresh.
- [ ] Finish authenticated Console browser acceptance, listed templates, retained-ID
  reconnect proposals and the external release prerequisite before
  considering the whole Integrations workflow complete.

See [UI contracts](../../docs/development/integrations-ui.md) and
[checkpoint evidence](../20261107-0309-review-integrations-ui.md).

### T4 — Tenant MCP records and static/anonymous connection lifecycle

Depends on T0 approved form and completed prerequisite milestones; may proceed
independently of T1–T3 behind unexposed operations.

- [x] Add an MCP secret envelope bound to tenant/connection/generation/authentication
  method/purpose using the shared keyring. Focused replay/rotation/bounds tests pass.
- [x] Add tenant-only durable connection records and the Calls repository port;
  implement encrypted create/read/replace, duplicate identity checks, generation
  conflict checks, revocation and bounded storage re-encryption. Nine focused
  persistence/cipher tests pass. Authorized Calls operations and session/CSRF-protected
  Console endpoints are now wired; end-to-end persistence acceptance remains open.
  See [storage boundary](../../docs/development/tenant-mcp-storage.md).
- [x] Validate static authentication inputs and implement isolated transient MCP
  checks with bounded lifetime and caller-death cleanup. A real local HTTP fixture
  proves initialization/tools discovery without tool invocation (seed 806205).
- [x] Add authorized static management endpoints with session/CSRF checks and
  public-only responses. Filter whole credential/endpoint fields from request logs.
- [x] Support omitted saved credentials on edits only for the same endpoint/method;
  reject stale generations before probing and retain transactional generation checks.
  Seven Calls boundary tests pass (seed 790565); browser masked-edit acceptance remains open.
- [x] Add `mix vxpipe.mcp_credential.reencrypt` for bounded resumable rotation of
  static MCP credentials and saved OAuth grants using the configured installation
  keyring. Preserve identity/configuration/grant revisions and redact CLI output.
  Three new database-backed command tests pass; focused MCP persistence suite 26
  passes. Document both stores and pending OAuth attempts before key retirement;
  cross-node rotation and retention acceptance remain pending.
- [x] Add persistence migrations for tenant connection identity/config generation,
  encrypted auth material and catalog snapshots, using the existing encryption
  keyring with explicit MCP identity binding and rotation participation.
- [x] Add authorized Calls operations/repository ports and Console management API.
  Unique directory identity prevents concurrent duplicate creates. Custom identity
  is a durable ID/canonical endpoint, never a display name. Define endpoint duplicate
  handling and disambiguate same-name servers without editable connection aliases;
  keep the internal namespace stable if server metadata changes.
- [x] Add tenant-authorized public connection details and cached tool catalog GET.
  Persistence reads require no decryption key; cross-tenant reads fail and public
  projections exclude credentials. Store/Calls/API focused suites pass (7/9/5 tests).
- [x] Add production Authentication/Tools management tabs with saved-secret
  preservation, replacement, retest, cached catalog/search, refresh and disconnect.
  Seven create/manage tests pass; desktop/mobile fixtures render correctly. Live
  inventory-row wiring is now implemented; authenticated end-to-end acceptance remains open.
- [x] Implement no-auth, bearer, API-key/custom-header and Basic connection checks,
  bounded discovery, edit/retest/disconnect and zero-tools state. Reuse ExMCP.
- [x] Expose these operations through the T4a custom modal only after the authorized
  API/preflight foundations. T4 operation/API fixtures remain separate from
  authenticated browser acceptance. Platform never accepts these records.

Acceptance: restart persistence, encryption/redaction/key rotation, cross-tenant
isolation, permission changes, concurrent duplicate saves, masked edits, invalid
headers/URLs and catalog failure tests. A local fixture MCP proves initialization
and paginated tools without executing a tool; unavailable and zero tools differ.

### T4a — URL-triggered discovery and custom-modal integration

Depends on T4's authorization/identity ports; does not require a stored connection
or a completed OAuth grant. Implement as a separate runnable checkpoint before T5.

- [x] Add a read-only OAuth/OIDC metadata adapter using the installed ExMCP pinned
  fetcher and endpoint validation, with the approved path order, exact issuer
  matching, bounded documents and redacted errors. Three focused tests pass
  (seed 9885); subsequent resource discovery and complete preflight are implemented below.
- [x] Add protected-resource metadata reads with Bearer challenge precedence,
  path/root fallback, exact resource validation and bounded issuer lists. Preserve
  all advertised issuers for explicit selection; missing metadata never means no auth.
  Three focused tests pass (seed 61435); complete traversal/UI acceptance stays open.
- [x] Compose resource/issuer discovery with endpoint/revision-bound outcomes,
  explicit multi-issuer choice and anonymous initialization checks. Four focused
  tests pass (seed 725389); registration/token exchange remains outside preflight.
- [x] Add Calls preflight authorization before/after discovery, reject credentials
  and mismatched result revisions. Eight management-boundary tests pass (seed 108438).
  Console exposes the port through the session/CSRF endpoint recorded below.
- [x] Add a supervised preflight runner (eight active operations, 15-second overall
  deadline, bounded tenant-frequency map) and owner-bound DNS/HTTP work. Focused
  tests prove worker timeout, capacity rejection, caller death and I/O cancellation.
- [x] Expose POST tenant `mcp-discovery` through session/CSRF/current write authority;
  API fixtures verify revision echo, no save and no platform route. Four tests pass.
- [x] Define and test an authenticated, tenant-services-write preflight operation
  taking the endpoint plus a draft request/revision identifier, with session/CSRF
  protection and current tenant permission checks. Accept no credentials
  for this operation; keep it separate from save/connect. Rate-limit and bound
  concurrent probes, request time, redirects, decoded bytes and metadata traversal.
- [x] Reuse the installed ExMCP resource/issuer metadata primitives behind the MCP
  policy boundary. Close any transient initialization/session resources on completion,
  timeout or cancellation; do not cache them across tenants. Audit the actual call path: `DiscoveryFlow.execute/1` also obtains
  tokens via client credentials, so it is not a read-only prefill operation.
- [x] Probe the MCP endpoint, prefer the `WWW-Authenticate` resource_metadata URL,
  otherwise try path-specific then root `/.well-known/oauth-protected-resource`.
  Follow advertised issuers using RFC 8414/OIDC well-known paths in the approved
  profile's order, including issuer paths. Validate exact issuer/resource identities.
- [x] Return bounded, redacted results tied to the requested endpoint/revision:
  stage/outcome, validated resource and issuer metadata, supported methods and a
  suggested method, usable endpoint/scope values, and actionable missing settings.
  Define partial/unknown versus anonymous outcomes; never infer anonymous access
  from a 404, network error or absence of metadata. Multiple issuers require a
  documented deterministic policy or explicit choice, not an accidental first item.
- [x] Add the production discovery hook: debounced same-origin CSRF requests,
  cancellation on close/URL changes, endpoint/revision response checks and retry.
  Three focused hook tests pass; dialog wiring and rendered fixtures are now implemented.
- [x] Add a production static custom-MCP dialog using the discovery/create APIs,
  active-method credentials only, URL secret clearing, manual-choice preservation,
  retry and failure recovery. Three component tests and desktop/mobile fixture checks
  pass. Inventory CTA and OAuth fields are now wired; authenticated acceptance remains open.
- [x] Wire debounced URL edits to the facade, inline progress/retry and prefills;
  cancel/ignore superseded requests and preserve manual edits for the same revision.
  Clear the old URL's credential material and settings before accepting new results.
- [x] Apply the field matrix above in connect and manage dialogs. Clear headers on
  authentication changes; validate/send only active method fields. Preserve masked
  saved-secret semantics and keep working saved connections intact on canceled edits.
- [x] Wire the live tenant static-MCP CTA and refresh inventory after create/manage/
  disconnect. Verified full fixture browse → connect → tools refresh → disconnect.
- [ ] Complete authenticated browser acceptance for the tenant custom CTA,
  including supported OAuth methods and explicit unsupported-capability recovery.
  Custom static, CIMD, unprotected/protected DCR, all four own-client authentication
  methods and three confidential machine methods now pass authenticated acceptance.
  Partial/multiple-issuer and unsupported-capability recovery now pass; remaining
  browser URL/revision races and close/reopen checks stay open.
  An explicit manual choice can recover from failed discovery where the selected
  supported method has enough validated information; CIMD/DCR cannot fabricate
  missing metadata or silently fall back to another method.

Acceptance: controlled resource/OAuth servers cover challenge URLs, well-known
fallbacks, issuer paths, missing/partial/invalid metadata, multiple issuers,
unsupported CIMD/DCR, anonymous initialization and unreachable servers. Assert no
registration, token request, durable create or tool invocation happens on URL entry.
Browser checks cover URL A→B races, edits during prefill, close/reopen, retry,
field visibility for every method and Custom headers→Bearer→Basic transitions.
Malicious URLs/redirects and tenant/permission changes fail at the backend boundary.

### T5 — Automatic discovery and delegated OAuth

Depends on T4/T4a and existing Console Installation URL/CIMD foundation.

- [x] Wire production CIMD, DCR and Own-client forms to existing discovery and
  OAuth/connection operations. Managed CIMD has no generic fields; DCR has only
  its optional initial token. Own-client shows advertised grants, authentication
  and signing choices, exact Console callback, active credential fields and
  grant-specific request parameters. Saved OAuth labels and catalog-only testing
  preserve existing credentials. See [UI contract](../../docs/development/mcp-oauth-ui.md).
- [x] Preserve tenant directory location through browser consent and add optional
  five-minute tab-local nonsecret draft recovery bound to actor/tenant/attempt.
  Require current authorized inventory before success feedback; consume once,
  reenter secrets and reject stale saved generations or lost write authority.
  Storage failure never blocks authorization. Query-bearing endpoint/issuer
  values are not stored. Browser/provider round-trip acceptance stays open.
- [x] Fix adversarial UI review findings: reject unsupported saved browser-OAuth
  endpoint changes before submitting; preserve callback context across expired
  directory cursor recovery; accept valid percent-encoded return paths within
  bounded storage. Each finding has a red-then-green regression. Hidden multiline
  keys require reveal-to-edit and retain newlines across hide/show.
  Rendered retry notices stay inside the modal; cursor recovery also preserves
  attempt context while authenticated identity is still loading.
- [ ] Complete authenticated Console/provider browser acceptance and retained-ID
  reconnect proposals; fixture UI and protocol acceptance do not close these gates.

- [x] Review installed ExMCP callback/transaction ownership and add a private S256
  authorization-request builder with fixed Console callback/resource and protected
  OAuth query fields. Three focused tests pass; see
  [outbound OAuth decision](../../docs/development/tenant-mcp-oauth.md).
- [x] Inspect installed ExMCP support and adapt its discovery/authorization interfaces;
  record gaps before adding protocol code. Support protected-resource metadata,
  OAuth/OIDC issuer discovery, existing registration, CIMD, then DCR negotiation.
- [x] Add explicit CIMD/DCR registration adapter using installation-owned metadata
  and ExMCP request validation/pinned HTTP. CIMD performs no registration request;
  DCR supports optional initial access tokens, exact callback/auth-method validation
  and redacted non-retried failures. MCP suite: 76 tests, zero failures (4 excluded).
  Connect orchestration and saved-registration reuse are wired below;
  full interoperability acceptance remains pending.
- [x] Compose fresh resource/issuer discovery, capability validation, managed
  registration and authorization request into a private Connect preparation result.
  Reject browser endpoint overrides and unadvertised issuers;
  unsupported PKCE fails before DCR. Four focused tests and the 80-test MCP suite
  pass (4 excluded). Calls/Console start and persistence wiring are now implemented.
- [x] Implement actual registration only at Connect: app-owned CIMD metadata or
  discovered DCR endpoint/metadata, including optional initial access token for
  protected registration. Keep generated credentials private and scoped to the
  connection; do not expose generic registration editors for these two methods.
- [x] Preserve DCR client-secret expiry from registration through encrypted attempt
  and grant storage. Reject missing/malformed/elapsed issued-secret expiry, and
  recheck before code redemption, refresh and client-credentials token requests.
  Keep expiry out of token HTTP parameters and prevent refresh results from
  overriding it. Red tests cover the previous gaps; 14 protocol, nine Console and
  29 persistence tests pass, with static gates green. Saved-registration reuse
  and reconnect backend replacement are implemented in the following checkpoint;
  full workflow acceptance remains open.
- [x] Add generation-bound OAuth reconnect through the existing connection
  replacement transaction. Preserve the working grant during consent/failure;
  bind replacement intent in encrypted attempts, recheck the target before token
  redemption, preserve directory identity and reject concurrent edits/revocation.
  Reuse matching saved DCR registration after fresh discovery and expiry/auth
  validation; otherwise perform fresh explicit registration. The session/CSRF
  route accepts the expected generation and returns only private handoff data.
  Calls 296, MCP 99, Console 451 and persistence MCP 32 tests pass; static gates
  pass. Real-browser/HTTP/database and independent-node acceptance remain open.
- [x] Add backend OAuth return context for initial connection and reconnect. Accept
  only this tenant's Integrations root/category with bounded search/cursor fields;
  exclude it from protocol input and authenticate it inside the durable attempt.
  Restore it on success with a fixed status, ignoring callback-supplied destinations;
  legacy attempts fall back to the tenant root. Filter the field from diagnostics.
  Calls 296, Console 454 and persistence MCP 33 tests pass; static gates pass.
  Production UI location submission is implemented; the real browser round trip remains open.
- [x] Exercise managed CIMD and confidential DCR through Console session/CSRF
  routes, real local OAuth/MCP HTTP and encrypted PostgreSQL stores. Cover
  credentialless preflight, Connect-time registration, PKCE/resource binding,
  initialization/tools discovery, single-use callback, refresh rotation, saved
  registration reuse, successful reconnect and disconnect. Denial and failed MCP
  initialization preserve the working grant; revocation during consent prevents
  redemption. Three tagged integration cases pass. The identity backend is a
  fixture, transport adapters route to loopback, and one BEAM hosts the test;
  real-browser, external TLS/CIMD retrieval and independent-node gates stay open.
- [x] Add encrypted durable attempt storage with tenant admission locking, expiring
  hashed state, session/installation/callback binding, atomic single claim and
  ciphertext erasure on consumption. Focused persistence lane: 15 tests pass
  (seed 229875), including expiry, tenant isolation and missing-key rollback.
  Callback authorization and retention are implemented; cross-node acceptance remains open.
- [x] Add the Calls attempt repository port and browser authorization boundary;
  derive user/session identity from the principal and recheck current tenant write
  authority before issue/claim. Focused Calls lane: 12 tests pass (seed 271194).
  Callback route and token exchange are separate implemented checkpoints below.
- [x] Preserve and validate the authorization-response issuer capability during
  discovery; add bounded, opaque callback parsing with duplicate/code-error rejection,
  exact issuer checks and redacted denial handling. MCP suite: 68 tests, zero
  failures (4 excluded). Route/state-claim/token-exchange integration is implemented below.
- [x] Add authorized Calls start orchestration: check tenant and current session,
  resolve installation identity before/after protocol preparation, bind new connection
  identity and persist attempt before returning a browser authorization URL. Reject
  changed installation revision and redact preparation failures. Calls suite: 263
  tests pass (seed 67439). Console adapter/start route are implemented below.
- [x] Wire tenant POST `mcp-oauth` through session/CSRF/current write authority to
  bounded Console protocol preparation and the encrypted attempt repository. Read
  fresh installation URL/revision from identity storage; public response contains
  only handoff URL and opaque IDs. Six endpoint tests and seven Calls start tests
  pass; full Console suite passes 436 tests (22 excluded), including real preparation
  projection. UI enablement and callback/grant integration are now implemented.
- [x] Add durable callback tenant lookup keyed by state digest and bound user/session;
  expired or consumed attempts reveal no scope. Calls resolves scope, checks current
  tenant authority and exact installation callback, then atomically claims. Persistence
  MCP lane: 17 tests pass; Calls suite: 265 tests pass. Callback route is implemented below.
- [x] Wire session-only OAuth callback through one-time claim, protocol completion,
  post-network installation/permission rechecks and encrypted initial connection
  creation. Reject duplicate query fields before claim; redirect to tenant Integrations
  without code/tokens and set no-referrer/no-store. Eight endpoint tests and the full
  267-test Calls suite pass. Cross-node and full provider/browser interoperability
  acceptance stay open; refresh implementation is recorded below.
- [x] Implement session/tenant/connection/issuer/revision-bound, expiring single-use
  attempts, PKCE S256, callback route, exact redirect/resource/scope handling.
- [x] Add single-attempt code redemption through ExMCP pinned HTTP with fixed
  PKCE/callback/resource fields, explicit supported client authentication, bounded
  response validation and opaque tokens. Reject private destinations; never follow
  redirects or retry ambiguous code redemption. MCP suite: 72 tests, zero failures
  (4 excluded). Grant persistence and callback orchestration are implemented below.
- [x] Add private callback completion adapter: validate issuer, redeem code once,
  initialize MCP with the returned token and discover tools before producing a
  connection. Three tests pass, covering issuer rejection and failed initialization.
- [x] Persist initial OAuth credentials encrypted while preserving the connection UUID
  bound in the attempt. Persistence MCP suite: 18 tests pass. Callback orchestration,
  distinct grant revisions, refresh coordination and replacement are implemented below.
- [x] Add encrypted durable refresh claims with row locking and a grant revision
  independent of configuration generation. Atomic rotation verifies the claim and
  current connection generation; revocation fences stale workers. Expired claims
  require reconnect and cannot be reclaimed. Persistence lane: 21 tests pass;
  network orchestration and independent-BEAM database races are now covered;
  cross-node token/transport lifecycle acceptance remains open.
- [x] Wire internal refresh coordinator and Console token adapter: claim before one
  network exchange, atomically rotate on success, fence failures for reconnect.
  Refresh HTTP uses fixed saved resource/client fields. MCP suite 81 tests and
  persistence MCP lane 23 tests pass; focused coordinator/adapter tests pass.
  Runtime resolver integration and local HTTP/database concurrency are implemented;
  separate-node/provider interoperability acceptance remains open.
- [x] Add bounded, key-independent deletion of expired/claimed OAuth attempts and
  `mix vxpipe.mcp_oauth.prune`, retaining live pending attempts and reporting safe
  pending-by-key counts. Database tests cover cutoff equality, resumable batches,
  live claim preservation, unavailable replay and CLI redaction/configuration errors.
  Document operator scheduling and key-retirement dependencies. Independent-node
  claim/cleanup race acceptance now passes in the seven-case persistence lane below.
- [x] Add encrypted grant storage, durable refresh coordination, atomic rotated
  token persistence, permission recheck, redacted error and reconnect transitions.
- [ ] Verify the complete grant/refresh workflow across independent BEAM nodes.
  Seven separate-process persistence cases and eleven delegated/machine runtime
  cases now pass, including caller cancellation and runner restart. Callback
  acceptance remains open.
- [x] Verify delegated token exchange and transport on independent nodes sharing
  PostgreSQL: rotation reaches POST/resumed GET/DELETE, remote revocation blocks
  subsequent submissions, held responses respect revocation and exclusive claims,
  unrelated tenants progress, and a crashed claimant cannot redeem again.
- [x] Verify machine-grant renewal across independent nodes, retaining the saved
  client-credentials grant without introducing refresh-token behavior. Two rotations
  reach POST/resumed GET/DELETE and omit returned refresh tokens from saved state;
  remote revocation prevents subsequent submissions.
- [x] Verify caller cancellation and renewal-runner restart across independent nodes;
  late token responses cannot persist or permit ambiguous redemption to repeat.
  Four real-HTTP cases cover both grants, worker retirement, durable deadline
  fencing and fresh unrelated renewal on the original node.
- [x] Implement custom Own-client handoff when managed registration is unavailable;
  preserve only the nonsecret draft, display the exact manual callback and reject
  unsupported capabilities. Listed-template recipe handling is still required below.
- [x] Make every discovery/authorization/token destination follow outbound policy;
  cover DNS/redirect handling and never leak tokens to another issuer/resource.

Acceptance: fixture authorization servers exercise CIMD, DCR, preregistration and
no registration, denied consent, expired/replayed/cross-tenant state, callback URL
changes, missing installation URL, malformed metadata, issuer substitution,
PKCE/resource validation, refresh races and invalid grants. Real browser flow
returns to the same tenant/category, then discovers tools before marking connected.

#### Browser-flow backend checkpoint (2026-11-07)

- [x] Wire session/CSRF-protected tenant OAuth start and explicit reconnect through
  current installation/authority checks, fresh protocol preparation and encrypted
  attempt persistence before returning the authorization handoff.
- [x] Claim session/tenant/installation-bound callback state once, validate issuer,
  redeem the code, initialize MCP/tools and recheck authority before encrypted save.
- [x] Return claimed failures to the authenticated tenant location with fixed status
  and bound attempt ID; malformed/unclaimed state and authority loss remain errors.
- [x] Admit completion before code redemption, bound the whole operation, cancel
  owned work on caller death/restart and reject a late success before persistence.
- [x] Anchor token expiry before exchange so MCP checking cannot extend validity.
- [x] Reconnect retained static/revoked identities without old credentials, preserve
  namespace/directory/generation fencing and recover unreadable DCR registration
  through fresh registration. Retain working grants until replacement succeeds.
- [x] Verify browser code flows through local OAuth/MCP HTTP and encrypted
  PostgreSQL, including replay, denial, failed initialization and restoration.
- [ ] Complete listed-template identity handling and real browser/separate-node
  acceptance. Production forms, nonsecret return recovery and runtime renewal are implemented.

See [browser-flow contracts](../../docs/development/mcp-oauth-browser-flow.md) and
[review evidence](../20261107-0143-review-mcp-oauth-flow.md). Backend fixtures do not
establish rendered browser or external provider interoperability acceptance.

### T6 — Manual authentication interoperability

Depends on T4/T5. Registered-client forms and local interoperability are implemented;
provider/browser and independent-node acceptance remain distinct open gates.

- [x] Add a bounded registered-client assertion adapter using ExMCP signing
  primitives. Preserve/validate advertised algorithms, constrain PEM/key type and
  strength, fix client/token-endpoint claims and short lifetime, and sign each code,
  refresh or machine-token request independently. Reject mixed authentication or
  mismatched identities before HTTP. This protocol checkpoint does not complete
  encrypted key persistence/rotation, HTTP interoperability or UI enablement;
  see the Own-client assertion decision in the outbound OAuth document. Twenty
  focused tests, the 107-test MCP suite and 13 Console adapter/HTTP-database cases
  pass; format, compile, strict Credo and unused-dependency checks pass.
- [x] Add validated Own-client issuer/endpoints/scopes/resource/audience and
  provider parameters without overriding managed OAuth/transport fields. These
  editors do not appear for CIMD/DCR; DCR's initial token belongs to T5.
- [x] Compose validated Own-client configuration with fresh discovery and the
  existing durable authorization-code lifecycle. Keep public/secret/JWT methods
  exclusive, support advertised issuer selection and same-origin endpoint overrides,
  and persist private configuration inside the encrypted attempt/grant. Rebuild
  client authentication for callback and refresh; preserve additional MCP headers
  during validation/runtime startup. Seven local HTTP/database cases now cover
  managed methods plus all four Own-client methods, refreshed tokens, key/secret
  replacement and failed replacement preserving the saved grant. Frontend forms
  and machine renewal are now implemented; real-browser acceptance remains open.
- [x] Add bounded literal provider parameters and a separate optional audience
  input to authorization/code/refresh/machine-token adapters. Reject managed field
  overrides, request-object/response-mode indirection, duplicates, control bytes
  and size overflow. Reject conflicts with endpoint query fields before token
  HTTP. Twenty-one focused tests, all 114 MCP tests and 13 Console protocol/local
  HTTP-database cases pass; static gates pass. Own-client input composition,
  encrypted configuration and UI are now implemented.
- [x] Add a bounded single-request client-credentials token adapter for advertised
  confidential client_secret_basic/client_secret_post methods and matching token
  endpoints. Validate scope syntax, preserve the resource binding, reject callback/
  grant overrides and public clients before HTTP, and omit returned refresh tokens
  from this grant's result. MCP suite 86 tests passes (4 excluded). This is the
  protocol adapter checkpoint; preparation, renewal, saved configuration, private-key
  JWT and production forms are implemented in subsequent checkpoints.
- [x] Implement explicit machine-to-machine client credentials only with compatible
  server support, and private-key JWT with registered public-key requirements,
  bounded signing algorithms, protected keys and rotation.
- [x] Reuse authorized MCP create/update and the probe port for explicit Own-client
  machine grants. Fresh discovery, one token acquisition and MCP initialization
  precede encrypted persistence. Reuse durable grant claims for renewal with a new
  client-credentials request, rejecting refresh tokens and fencing ambiguous
  failures. Advertise supported grants during preflight. Ten local HTTP/database
  cases pass, including Basic/POST/JWT machine connect, runtime renewal, replacement
  and disconnect without consent attempts or DCR. Production forms are implemented;
  independent-node acceptance remains open. The 2025-11-25 wire profile is unchanged.
- [x] Verify public versus confidential client methods and selected grant compatibility;
  preserve previous working credentials until replacement validation succeeds.

Acceptance: each exposed method has a local interop case, negative override tests,
secret redaction and safe edit/reconnect behavior. Unsupported methods return a
specific recovery state; hiding an unimplemented choice requires updating the
proposal and obtaining scope agreement, not quietly claiming this milestone passed.

#### Machine-grant and renewal backend checkpoint (2026-11-07)

- [x] Extend existing tenant MCP create/replace operations with validated registered
  client-credentials acquisition, initialization/tools and encrypted persistence;
  require supported confidential authentication and create no browser attempts.
- [x] Coordinate renewal through durable claim/complete/fail ports, using refresh
  tokens for delegated grants and saved client configuration for machine grants.
  Preserve generation/revision fencing and never retry ambiguous redemption.
- [x] Resolve current pinned OAuth credentials privately, renew once near expiry,
  reread persisted state and prevent fallback under active/expired ambiguity claims.
- [x] Refresh OAuth tool catalogs with current tokens and saved MCP headers without
  overwriting rotated grant state or changing the configuration generation.
- [x] Verify nine local HTTP/database renewal cases and five durable boundary cases,
  including cross-tenant saturation, cancellation and late-result rejection.
- [ ] Complete independent-node and authenticated browser acceptance before treating
  this backend checkpoint as full workflow delivery. Runtime transport/catalog
  cutover and production UI are implemented; independent-node renewal/lifecycle
  checks now pass. Authenticated browser and cross-node callback acceptance remain.

See [renewal contracts](../../docs/development/mcp-oauth-renewal.md) and
[review evidence](../20261107-0208-review-mcp-renewal.md). Admission is per application
instance; per-connection durable claims provide the cross-instance fence.

### T6a — Listed-template connection identity and forms

Depends on T1/T2 directory resolution and T4/T5/T6 connection/authentication contracts.
Listing resolution/discovery, snapshot storage, static connection management and
locked static/OAuth forms are implemented. OAuth flows bind accepted configuration;
saved-registration discovery advice has passed checkpoint verification. Authenticated browser and retained-ID recovery acceptance remain open.
See [lookup and snapshot contracts](../../docs/development/listed-mcp-connections.md).

- [x] Reuse the existing directory page cache for bounded directory/entry/revision
  references and add those references to remote MCP inventory rows. Reject
  malformed, retired, incompatible or changed entries without accepting browser
  connection configuration. Project only supported public recipe/setup fields.
- [x] Extend the existing authorized, bounded discovery operation with listed
  references and validate returned draft/entry/endpoint identity. Keep discovery
  credentialless and filter the whole reference from request logs, including
  rejected extra private fields. Focused red/green contracts cover these boundaries.
- [x] Address checkpoint review: distinguish outer-proposal/reference error codes
  in the contract, and verify canceled/expired discovery cannot continue to MCP
  requests after an independent shared directory fetch finishes.
- [x] Add repository storage for the accepted public listing snapshot separately
  from encrypted credentials. Bind its directory/entry identity, endpoint and
  recipe; reject private/unknown fields and mutation of an accepted snapshot.
  Preserve the snapshot through revocation/reconnection and its name through
  catalog refresh. Calls/Console mutation wiring remains in the tasks below.
- [x] Address storage checkpoint review: document outer-method binding versus
  protocol/credential checks and public metadata's trust boundary; verify the
  maximum compound ID, omitted-snapshot preservation and unchanged credentials/
  generation after rejected replacement.
- [x] Wire listed static creation through the existing directory adapter and tenant
  connection routes. Ignore endpoint/authentication/header-name overrides; collect
  only recipe-required credentials and persist the accepted public snapshot.
  Reject a probe result for a different directory, entry or revision.
- [x] Use accepted saved configuration for static replacement and retained-ID
  reconnect, with generation/state checks before credential use and no directory
  lookup. Preserve canonical credentials, snapshot/name and ID/namespace through
  replacement, tool refresh, disconnect and reconnect. Real-store HTTP lifecycle
  coverage verifies directory outage, stale generation and cross-tenant isolation.
- [x] Join inventory by compound directory/entry identity as well as canonical
  endpoint; retain matches across upstream endpoint/revision changes without
  confusing identical entry IDs from different directories.
- [x] Enable listed static Connect with known local status, current tenant MCP
  write authority and an available supported recipe. Reuse the production dialog
  with fixed URL/authentication and only recipe-required credentials; preserve
  accepted saved configuration during management and directory outages.
- [x] Validate listed references and saved bindings in the UI projection, render
  optional plain-text setup notes and safe independent links, and provide explicit
  recovery for changed/missing listings. Listed OAuth remains visibly disabled.
- [x] Address rendered checkpoint finding: supply the existing MCP style scope
  inside the production dialog, correcting unstyled inputs and desktop overflow;
  keep long headings/notes contained. Desktop/mobile Chrome fixture confirmation
  covers API-key creation/replacement, bearer/Basic/anonymous fields, tools during
  outage and read-only controls. Authenticated backend browser acceptance stays open.
- [x] Address listed OAuth checkpoint review: preserve the existing explicit-issuer
  Own-client fallback when protected-resource metadata is absent, even when issuer
  metadata advertises managed registration. Reject conflicting or invalid metadata;
  verify new and accepted-snapshot preparation without a registration request.
- [x] Address listed OAuth checkpoint review: reject malformed issuer input with
  HTTP 422 before directory/protocol reads; verify capability loss between selection
  and revalidation cannot proceed to registration or consent handoff.
- [x] Prepare listed OAuth through existing bounded discovery/registration and
  encrypted attempts. Bind proposed entry/revision, draft and resource; permit only
  required managed or preregistered client fields. Preserve accepted snapshot/name
  through callback and reject mismatched protocol results before persistence.
- [x] Reuse accepted saved configuration for generation-bound OAuth replacement and
  retained-ID reconnect without directory access. Real-store session/CSRF lifecycle
  coverage verifies callback outage, single-use state, compatible DCR reuse, refresh,
  revocation/fresh registration, namespace preservation and stale/cross-tenant rejection.
- [x] Add listed OAuth forms with fixed URL/recipe, live capability selection,
  explicit preregistered-client authentication and only applicable credential
  fields. Preserve a validated public listing through consent retry; reenter secrets.
- [x] Address independent UI review: keep manual issuer recovery mounted and focused
  across first-character input and discovery restarts. Red/green typing regression
  and rendered Chrome desktop/mobile confirmation pass.
- [x] Extend the existing discovery operation with a bounded saved ID/generation
  proposal and shared Connect-time registration choice. Preserve compatible DCR
  without new registration endpoints; return only public advice and checked
  callback identity. Cover revocation, unavailable/expired credentials, scope and
  issuer changes, plus held authority/generation/installation changes.
- [x] Complete final saved-discovery/locked-OAuth checkpoint review and root gates.
  All five root gates pass: 4,944 umbrella tests, zero failures, 201 excluded
  (seed 426342). Independent adversarial source and exact-index reviews are clean.
  Focused Calls 43 and Console 37 tests pass; all 1,031 frontend tests, TypeScript
  and ESLint pass (only the existing SetupDialog hook warning).
  Production-component Storybook desktop/mobile inspection and independent UI
  review pass; authenticated browser acceptance remains open. See
  [form/discovery evidence](../20261107-0617-connect-listed-oauth-forms.md).
- [x] Address saved-discovery adversarial review: older preflight adapters without
  the optional saved operation return a bounded unavailable result before reading
  registration secrets. Red/green regression preserves custom discovery behavior.
- [x] Reconcile stale durable-document statements with implemented listed OAuth
  forms while leaving retained-ID recovery and authenticated browser gates open.

Discovery checkpoint evidence: [labnotes](../20261107-0431-connect-listed-mcps.md),
4,901 umbrella tests with zero failures (201 excluded, seed 177411), all five root
gates, and clean independent adversarial/exact-index review. No listed connection
persistence, rendered form or real-provider acceptance is claimed by this checkpoint.

Snapshot storage evidence: [labnotes](../20261107-0454-persist-listed-mcps.md),
4,905 umbrella tests with zero failures (201 excluded, seed 371945), all five root
gates and clean independent adversarial/exact-index review. The additive migration
preserves existing records; public snapshots survive repository lifecycle changes.

Static management evidence: [labnotes](../20261107-0512-connect-listed-static.md),
4,914 umbrella tests with zero failures (201 excluded, seed 780141), all five root
gates and clean independent adversarial/exact-index review. Listed OAuth, locked
forms and browser acceptance remain open; this checkpoint enables only the API.

Static form evidence: [labnotes](../20261107-0537-connect-listed-forms.md), 1,018
frontend tests and 4,915 umbrella tests with zero failures (201 excluded, seed
342196), all five root gates, TypeScript and clean independent adversarial/exact-index
review. ESLint retains only the existing SetupDialog hook warning. Production
components were inspected with in-memory Storybook responses on desktop/mobile;
this does not close authenticated production-browser acceptance.

Listed OAuth backend evidence: [labnotes](../20261107-0553-connect-listed-oauth.md),
4,931 umbrella tests with zero failures (201 excluded, seed 181095), all five root
gates and clean independent adversarial/exact-index review. Two preexisting test
synchronization races were corrected separately while preserving exact outcomes.
Listed OAuth UI and authenticated browser acceptance remain separate open work.

- [x] Resolve new listed-connection proposals through the existing trusted backend
  directory adapter. Reject retired/incompatible proposals before side effects;
  bind the validated directory ID, endpoint and recipe into connection/attempt
  configuration. Ignore browser endpoint/authentication overrides for listed entries.
  Preserve an in-flight OAuth attempt's validated identity/recipe through completion.
  Manage existing connections from saved validated configuration when the directory
  is unavailable or the entry disappears/retires; do not add an upstream dependency
  to refresh, replacement, disconnect or retained-ID reconnect.
- [x] Enable listed MCP Connect only with known local connection status, tenant
  write authority and a supported recipe. Use the directory name/endpoint with no
  editable URL, name or authentication selectors. Preserve custom-MCP behavior.
- [x] Render independently optional plain-text setup notes and validated Setup /
  Documentation links. Collect only recipe-required user credentials; use live
  OAuth capability checks for managed registration hints and exact installation
  callback identity for preregistered clients. No remote definition can introduce
  executable code or shared client secrets.
- [ ] Preserve directory identity through catalog refresh, secret replacement,
  browser callback, machine acquisition, disconnect and retained-ID reconnect.
  Do not create a second record when directory and endpoint identify existing
  connections; preserve the backend's deterministic conflict behavior.
- [ ] Add red/green facade/storage/UI contracts for recipe tampering, changed
  versions, outage, duplicates and optional setup content. Verify desktop/mobile
  rendered listed static and OAuth forms, then the authenticated browser workflow.

### T6b — Retained-ID reconnect and duplicate recovery

Depends on T4/T5/T6; listed identity cases additionally require T6a.

- [x] Consume the backend's existing bounded static reconnect proposal for a disconnected endpoint
  and show an explicit Reconnect action. Keep its retained ID/generation bound to
  the current endpoint/draft; an ordinary Connect must not silently resurrect it.
- [x] Extend the existing detail GET with strict `retained_generation` input, fresh
  write authorization and exact tenant/ID/generation/revoked checks. Return public
  accepted configuration without credential decryption or connection side effects;
  ordinary details include the current edit capability.
- [x] Render retained static/browser/machine setup with fresh credentials, fixed
  endpoint and accepted directory recipe. Submit explicitly through the existing
  reconnect operations; hide connected-only tools/test/disconnect actions.
- [x] Recover denied/failed retained OAuth from its matching actor/tenant/attempt
  draft and a fresh generation-bound metadata read. Keep temporary-failure retry
  context only in bounded, expiring memory and ignore late scope/navigation results.
- [x] Address independent recovery review: leaving an unfinished callback recovery
  removes its stale Retry recovery action and notice. Red/green navigation regression
  preserves completed callback feedback. Connected duplicates may open read-only
  management after write authority changes.
- [x] Resolve trusted custom/listed targets and check duplicate identity before static
  authentication or OAuth preparation. Extend required internal ports, reuse the
  repository's deterministic endpoint-or-directory query and retain atomic create
  as the final race guard. Cover changed listing recipes, authority loss and races.
- [x] Use the existing static reconnect or generation-bound OAuth reconnect
  operation as appropriate. Complete browser-start duplicate/proposal handling
  where needed without adding another connection/grant store. Preserve identity,
  namespace and directory binding; reject changed generations and authority.
- [x] Distinguish an already connected duplicate from a retained disconnected
  record. Offer current management instead of misleading retry advice; do not
  trust conflict response text or restore secret values from saved records.
- [ ] Verify explicit consent, cancel, URL/method changes, stale proposals,
  cross-tenant IDs, storage failure and preservation of existing call-spec
  references. Cover custom/listed, static/browser OAuth/machine flows and rendered
  desktop/mobile recovery before closing authenticated workflow acceptance.

Recovery checkpoint progress: [labnotes](../20261107-0648-wire-retained-mcp.md).
Calls 24 and Console 11 focused tests pass, plus real-store session/CSRF lifecycle
coverage that reads retained configuration without encryption keys during directory
outage. Chrome desktop/mobile inspection covers explicit review, cleared credentials,
accepted listed configuration, connected management and cancelled OAuth setup.
Independent backend and UI source reviews are clean after the retry cleanup fix.
All 1,056 frontend tests, TypeScript and ESLint pass (the preexisting SetupDialog
hook warning remains). All five root gates pass: 4,955 umbrella tests with zero
failures (201 excluded, seed 362537). The separately reviewed output-arbiter
correction also passes Lean build/oracle/replay. Full authenticated workflow
acceptance remains open.

Early duplicate lookup is implemented and passes its checkpoint gates.
Custom/listed static, machine and browser OAuth starts resolve a credentialless
target, refresh authority around keyless identity lookup and bind continuation
results to the accepted configuration. The same deterministic query remains the
atomic create guard. Calls 356, Console MCP 83 and storage 22 tests pass, including
changed recipes, callback races and real-cache caller cancellation. Independent
adversarial source and exact-index reviews found no remaining checkpoint findings.
All five root gates pass: 4,984 tests with zero failures (201 excluded, seed 472487).
Authenticated browser and full runtime/release acceptance remain open. See
[duplicate lookup evidence](../20261107-0714-check-mcp-duplicates.md).

### T7 — Tenant-only runtime/tool picker cutover and migration

Depends on T4; OAuth methods additionally depend on T5/T6.

- [x] Switch the default editor tool catalog to cached saved tenant connections,
  using stable connection IDs and rejecting foreign/revoked/malformed records.
  Preserve native tools on repository failure without application-MCP fallback;
  explicit embedded catalog injection remains separate. Calls suite: 275 tests pass.
  ConfiguredNames, publication and startup wiring are now implemented; full
  per-admission execution acceptance remains open.
- [x] Remove ConfiguredNames from packaged editor lookups. Both member and operator
  lookups list stable saved tenant connection IDs, including zero-tool servers;
  unavailable MCP storage leaves native choices usable and signals MCP unavailability
  through the tool catalog. Calls suite: 276 tests pass. Compilation and startup
  now use the tenant-specific saved catalog snapshots recorded below.
- [x] Accept immutable IntegrationCatalog snapshots at both CallEngine compilation
  and startup boundaries, preserving explicit process-backed catalogs. Compiler
  tests verify identical tool bindings; the live-call fixture executes against the
  supplied snapshot. Focused remote MCP suite: 37 tests pass. Saved-record snapshot
  construction and Gateway wiring are now implemented.
- [x] Replace packaged tenant application-config fallback in ConfiguredNames,
  IntegrationCatalog, picker, publication, preparation and invocation. Keep explicit
  embedded-host configuration a separate boundary; report required migration work.
- [x] Add trusted runtime credential resolver pinned to tenant/connection/generation;
  refresh near-expiry OAuth once, reread persisted tokens and remove refresh/client
  secrets from returned runtime data. Reject stale/revoked identities and pending or
  ambiguous refresh state. Calls suite: 273 tests pass. Actual transport/catalog
  wiring is now implemented; ExMCP provider error fallback is explicitly unsuitable.
- [x] Add guarded runtime provider with token/method validation, fixed process exit
  on resolution failure and challenge rejection without retry. Actual ExMCP POST
  entry test verifies no DNS/old-token fallback; MCP suite 84 tests passes (4 excluded).
  Provider is now wired through the fixed client profile and saved startup bindings;
  full invocation/cross-node acceptance remains pending.
- [x] Resolve runtime credentials before deferred GET/SSE reconnects and session
  DELETE using a checksum-verified patch of the pinned ExMCP transport. Preserve
  local cleanup when revoked credentials prevent remote deletion. Setup and CI
  apply the patch; clean-checkout/idempotence/tamper checks pass (3 tests), setup
  checks pass (33 tests), and the MCP suite passes (89 tests, 4 excluded).
  Loopback HTTP observes initial, renewed reconnect and latest DELETE tokens;
  revoked POST/GET/DELETE tests verify no DNS. Full runtime acceptance and cross-node
  revocation acceptance remain open. See the transport decision in
  [outbound OAuth](../../docs/development/tenant-mcp-oauth.md).
- [x] Add saved-record compilation snapshots and wire CallPlanCompiler, shared by
  publication and preparation, to use them for MCP selections. No credential reads
  or refresh occur; native-only specs do not query MCP storage. Validate tenant,
  duplicate identity and cached descriptors; pin configuration/schema generations.
  Red publication test now passes; Calls suite 281 tests passes. Runtime startup
  is a separate implemented boundary below.
- [x] Build a secret-free tenant compilation snapshot from saved connection records:
  stable connection/configuration identity, validated cached schemas and explicit tool
  selections. Do not decrypt credentials or refresh tokens during publication.
  Verified SavedMCPCompilationCatalog uses only list metadata and empty client
  configuration; its four tests cover tenant isolation, stale schema/configuration,
  duplicate/revoked records and zero tools. Publication test covers saved selections
  and revoked selections; included in the passing 286-test Calls suite above.
- [x] Add a private static-auth startup catalog builder for selected saved MCPs.
  Reject foreign scopes before lookup; resolve repeated selections once; validate
  current tenant/ID/generation/status and exact cached schema pinning. Keep secrets
  out of inspection and reject unsupported OAuth without refreshing tokens.
  Five focused tests and Calls suite (286 tests) pass. Subsequent Gateway wiring
  and guarded OAuth bindings are recorded below.
- [x] Wire guarded runtime authentication through ClientOptions and saved startup
  bindings. The current boundary resolves complete current request headers for
  each pinned static/OAuth submission; startup descriptors contain no credentials.
  Registration/refresh secrets remain private to the resolver. Red/green
  binding/projection tests pass; MCP suite 90 tests and Calls suite 288 tests pass.
- [x] Route packaged Gateway startup through fresh saved-tenant snapshots, including
  browser, managed incoming/outgoing and legacy incoming admission. Require call
  tenant and plan tenant to match; attach an empty snapshot for native-only calls
  rather than inheriting application MCPs. A focused startup test verifies saved
  binding construction and rejection of revoked/foreign records. Full per-route
  saved-record execution acceptance remains below.
  Full Gateway suite after wiring: 869 tests pass, 13 excluded.
- [x] Resolve a fresh saved-connection snapshot at packaged call startup through
  Gateway CallAdmission.CallEngineOptions. Cover browser, incoming and outgoing
  telephony admission, including the legacy incoming entry migrated to build/2.
  Reject revoked/replaced generations between preparation and startup; keep the
  explicitly configured trusted/embedded host path separate.
- [x] Test the complete saved-record path from publication through preparation and
  execution, including foreign tenant IDs, storage outage, zero-tool connections,
  changed schemas and deleted tools. Ensure private connection configuration never
  enters persisted PreparedCall plans or browser projections. Local WebRTC plus
  managed incoming/outgoing and legacy incoming carrier-fixture cases execute the
  saved selection. Web boundary cases cover the listed negative conditions;
  separate-node acceptance remains below.
- [x] Bind credentials/token provider and schemas privately by tenant connection ID
  and generation. Refresh tokens without changing stable tool identity.
- [x] Reuse MCP-name/tool selection and double-underscore runtime naming. Select all
  saves explicit names; new tools do not grant themselves and removed tools fail safely.
- [x] Implement guarded transport invalidation on disconnect/revocation without
  re-enabling stale grants or retrying ambiguously submitted tool operations.
- [x] Verify revocation during full admitted calls and delayed transfer activation;
  fail within the existing scoped call boundary without a browser prompt. Local
  web/phone calls preserve their room after disconnect; web transfer cases cover
  cold/reused-client rejection and source preservation. Separate-node races remain open.

Acceptance: tenant A cannot list/execute tenant B or platform MCP tools; directory
outage does not stop an already authorized call. Catalog refresh, server-name changes, revoke,
refresh race and reconnect preserve pinning and scoped failure contracts. Migration
is repeatable and does not silently share or delete existing credentials.

#### Saved runtime wiring checkpoint (2026-11-07)

- [x] Read tenant saved metadata for editor names/tools and compilation, preserving
  native choices during storage failure without application-MCP fallback. Filter
  unsupported schemas and keep zero-tool connection identities available.
- [x] Share immutable metadata snapshots between publication and preparation, with
  explicit configuration/catalog pins and no credential reads or persisted secrets.
- [x] Build fresh saved startup bindings in Gateway browser, incoming and outgoing
  admission, including the legacy incoming entry. Reject mismatched tenant/pins.
- [x] Keep startup descriptors free of credentials and keyrings; resolve complete
  current headers at each request and fence endpoint/method/runtime-source changes.
- [x] Verify saved PostgreSQL records through publication/preparation, Gateway's
  startup-options boundary and actual loopback MCP execution. Check revocation,
  schema/replacement pins, unchanged explicit allowlists and persisted-plan privacy.
- [x] Document direct CallEngine embedding and manual tenant migration; packaged
  Gateway never silently starts application-scoped MCP selections.
- [x] Complete local per-admission room/transfer execution and independent-node
  credential/transport lifecycle acceptance. The 20 saved-runtime cases cover web,
  managed incoming/outgoing and legacy phone paths, cold/reused delayed transfers
  and submitted-request semantics. Eleven node cases cover both grants, revocation,
  caller/runner retirement and crash fencing. The revocation, claimant-crash and
  caller/runner cases observe explicit release and completion of the response-handling
  attempt. These separate lanes do not claim distributed
  admitted-room execution; cross-node browser callbacks and T8 release remain open.
  See [audit and correction](../20261107-1200-verify-held-mcp-responses.md).

See [saved runtime contracts](../../docs/development/saved-mcp-runtime.md) and
[checkpoint evidence](../20261107-0242-review-mcp-cutover.md).

#### Runtime transport credential checkpoint (2026-11-07)

- [x] Project current pinned credentials into a guarded MCP provider, validating
  method and bearer syntax without exposing registration/refresh secrets.
- [x] Resolve credentials for POST, initial GET, SSE reconnect and session DELETE;
  reject unavailable credentials before submission and preserve local cleanup.
- [x] Ship the pinned three-file ExMCP transport patch with revision/source/patch
  checksums, idempotent preparation, setup/CI compilation and preparation tests.
- [x] Verify actual HTTP token rotation, resume cursor progression and request
  rejection privacy. Keep network interoperability in the tagged integration lane.
- [x] Complete per-admission room/transfer and independent-node revocation acceptance.
  Committed web/phone/transfer cases verify admitted execution and scoped failure;
  the independent-node runtime/lifecycle cases below verify actual-client submission
  fences and both grant types. Cross-node browser callback and final release gates
  remain open.

See [transport contracts](../../docs/development/mcp-runtime-transport.md) and
[review evidence](../20261107-0224-review-mcp-transport.md). This checkpoint extends
the committed resolver/renewal boundary. Per-admission and independent-node
transport acceptance pass in the follow-up checkpoints below; this does not close
the complete cross-node grant workflow or final release gates.

#### Saved web-admission acceptance checkpoint (2026-11-07)

Saved web-admission acceptance checkpoint passes:
[labnotes](../20261107-0758-saved-mcp-acceptance.md). A tagged local Console test
now follows saved PostgreSQL publication through call/session admission, WebRTC
input, model-selected ExMCP execution and result delivery. An authenticated,
CSRF-protected tenant disconnect blocks the next invocation in the same running
room. Six saved-runtime/managed-web tests pass. Identity is fixture-backed; this
is protocol/endpoint acceptance, not rendered browser or real identity-provider
acceptance. Telephony, transfer, independent-node and broader negative cases stay
open. All five checkpoint root gates pass: 4,986 tests, zero failures (202 excluded,
seed 666644). Independent adversarial source and exact-index reviews are clean.

Saved boundary and transfer follow-up: the local web path now covers foreign tenant
selections with a separate authorized server, zero-tool records, changed/deleted
descriptors, and repository outages at preparation, startup and invocation. Fresh
preparation uses the original publication and never grants newly discovered tools.
Five delayed-transfer cases prove successful destination execution and source
preservation after cold/reused-client revocation or replacement. Sixteen tagged
Console cases, 170 MCP tests and five existing wire cases pass. All five root gates
pass: 4,987 tests, zero failures (214 excluded, seed 181171). Independent adversarial
source and staged implementation review found no remaining code issues.
Telephony, separate-node and authenticated rendered acceptance
remain open. See [boundary evidence](../20261107-0822-saved-mcp-boundaries.md).

Submitted-request follow-up: a controlled authenticated MCP POST may complete
after tenant disconnect, while a subsequent invocation fails in the same admitted
room without another POST or SSE request. Timeout/cancellation cannot synthesize
fixture success. All 17 saved-runtime cases and five existing wire cases pass;
all five root gates pass (4,987 tests, zero failures, 215 excluded, seed 957720).
Independent adversarial source re-review is clean. This is local web-call acceptance;
separate-node renewal/revocation races stay open. See
[in-flight evidence](../20261107-0855-saved-mcp-inflight.md).

#### Saved phone-admission acceptance checkpoint (2026-11-07)

Three local carrier-fixture cases now execute a saved MCP from published specs
through managed incoming, managed outgoing and legacy incoming startup. Managed
cases assert durable cleanup ownership; the compatibility fixture explicitly uses
the legacy three-argument startup and delegates the remaining carrier lifecycle.
Actual carrier audio reaches STT, model-selected ExMCP results reach the model and
speech output reaches the original phone socket. Authenticated tenant disconnect
blocks the next invocation without another tools/call, while the same stored
room/incarnation remains running. Native and MCP private markers are excluded from
plans, model/public projections and archived facts. Signed carrier hangup closes
the observed room/socket/leg/tracker and all three cases await durable ended state.
All 20 combined saved-runtime cases and all five root gates pass: the full umbrella
run has 4,987 tests, zero failures and 218 excluded with seed 397067. Independent
adversarial source review is clean. The composite T7/T8 independent-node and release
gates remain open.
See [phone evidence](../20261107-0922-saved-mcp-telephony.md).

#### Independent-node runtime checkpoint (2026-11-07)

Five tagged Console cases now use the production renewal coordinator and real
ExMCP clients in separate BEAM processes with distinct OS and PostgreSQL backend
IDs. Token rotation on one node reaches POST, resumed GET and explicit session
DELETE on the other. A second tool succeeds after clean EOF without initializing
again. Remote revocation prevents subsequent POST/GET/DELETE. Held real token
responses cover revocation, duplicate exclusion, unrelated-tenant progress and
claimant crash fencing. The five cases and 14 focused transport tests pass, as do
seven pinned-patch preparation tests. The full MCP lane passes 184 tests; all five
root gates pass with 4,987 tests, zero failures and 229 excluded (seed 108915).
Independent source and exact-index adversarial reviews are clean. Machine renewal,
caller cancellation, renewal-runner restart and browser/callback acceptance remain
open; these tests do not close the composite
cross-node workflow gate. See [evidence](../20261107-1017-mcp-runtime-nodes.md).

The renewal-lifecycle follow-up extends the combined lane to eleven passing cases.
Machine rotation/revocation now runs against the real client and never saves a
refresh token. Four held-response cases verify caller cancellation and registered
runner restart for both grants, followed by cross-node duplicate rejection,
deadline fencing and fresh unrelated renewal. The existing backend passes these
cases without production changes. All 25 combined node/OAuth boundary cases pass
after the review corrections below, and both independent source re-reviews are
clean. All five root gates pass: 4,987 tests, zero failures and 235 excluded
(seed 94648), after an unchanged same-seed retry of an unrelated Twilio harness
startup failure. Browser/callback acceptance remains open. See
[lifecycle evidence](../20261107-1056-mcp-renewal-lifecycle.md).

### T8 — Release and operational verification

Depends on T1–T7, including T4a, T6a and T6b. Update installation/operations docs
and all related Storybooks.

- [ ] Run all five root gates plus focused frontend checks and rendered acceptance.
  Run `bin/verify-lean` for any changes to the source-cutover or speech state
  machines, as required by AGENTS; record applicability and the result.
- [x] Add tagged database concurrency coverage using independent BEAM processes
  sharing PostgreSQL (assert distinct OS/backend PIDs): one-time attempt claim,
  cleanup versus live claim, tenant pending cap, refresh exclusivity and refresh
  completion versus revocation. Seven integration tests pass, including a held claim
  revoked from another node and abrupt claimant death with deadline fencing. These
  verify durable cross-node storage contracts; token/transport lifecycle stays open.
  The combined persistence lane passes 72 tests; all five root gates pass with
  4,987 tests, zero failures and 220 excluded (seed 141375). Independent source and
  staged adversarial reviews are clean. See [evidence](../20261107-0959-mcp-cross-node.md).
- [ ] Run tagged MCP/OAuth conformance and local cross-node persistence/refresh tests;
  live third-party checks only with explicitly provisioned test accounts.
- [ ] Verify remote API unavailable, no usable cached catalog, and connected-status
  unavailable independently. Check rate limiting, cache bounds, revocation and logs.
- [ ] Record independent implementation review, user workflow approval and release
  evidence; only then check the milestone in the index.
- [ ] After implementation, run an independent review agent using GPT-6 Astra with
  xhigh reasoning effort (explicit user requirement, 2026-11-06).
- [ ] Add every review finding requiring a change to the fix checklist below;
  implement and verify fixes before declaring the review complete.
- [ ] Send the user a `pushnotify` completion message only after implementation,
  independent review and fixes are complete.

### Implementation and review fixes

- [x] Add controlled partial, multiple-issuer and unsupported-OAuth discovery
  scenarios. Three failing protocol cases now pass; the combined lane passes
  39 tests and requires discovery to avoid registration/token/tool side effects.
  Authenticated desktop/mobile retry and issuer recovery lead to real consent,
  saved testing and disconnect; unsupported OAuth remains blocked.
- [x] Correct unsupported-OAuth submission feedback: after metadata is known to be
  unsupported, report that limitation instead of asking the user to discover again.
  The reproduced browser message has a failing-then-passing component regression;
  eight focused cases, all 1,064 frontend tests, TypeScript and the asset build pass.
  Corrected desktop/mobile rendering is verified. All five root gates pass
  (4,991 tests, zero failures, 253 excluded, seed 390973), and independent adversarial
  source/documentation/rendered review is clean. See [recovery evidence](../20261107-1304-verify-discovery-recovery.md).

- [x] Observe explicit response release and completion in the older cross-node
  revocation and claimant-crash cases. A generic renewal error could otherwise be
  satisfied by hold timeout. All eleven strengthened node/lifecycle cases pass.
  Independent audit establishes the broad T7 runtime scope from the separate local
  admission and cross-node transport lanes; do not claim distributed admitted-room
  execution or complete cross-node browser callbacks. All five checkpoint root gates
  pass (4,991 tests, zero failures, 237 excluded, seed 535581).
- [x] Correct the T7 audit wording to name the explicit acknowledgement cases and
  describe completion of the response-handling attempt, including closed-client
  failure, rather than implying physical delivery of a response to a dead client.

- [ ] Extend the controlled peer's startup scenarios for independent outage states.
  Partial/multiple-issuer metadata, configured own clients, machine grants and
  protected registration are now covered
  below. The user suggested configurable real-server testing;
  an independently hosted test server can additionally exercise unmodified outbound
  DNS/TLS routing when available, without replacing the existing local gates.
- [x] Provision own-client browser peers for public, Basic, POST and private-key JWT
  token authentication, and machine peers for the three confidential methods.
  Add protected DCR with a fresh initial registration token; missing/wrong tokens
  cannot register a client. Nine failing scenario cases now pass; the combined
  protocol/renewal lane passes 36 tests. All five root gates pass (4,991 tests,
  zero failures, 250 excluded, seed 343039), with clean independent adversarial
  source/documentation/browser-evidence reviews. See [scenario evidence](../20261107-1247-configure-oauth-test-modes.md).
- [x] Verify all four own-client methods and three confidential machine methods in
  the authenticated Console: create, actual consent for delegated grants, saved
  testing, mobile Tools and disconnect. Machine discovery selects client credentials
  and connects without browser consent. Protected DCR rejects a missing registration
  token; explicit Basic-to-DCR retained reconnect succeeds after token entry and
  consent while preserving ID/namespace. Separate-node callbacks and broader
  recovery cases remain open.
- [x] Add startup-selected anonymous, bearer, custom-header and Basic peers with
  fresh private credentials and real ExMCP preflight/connection checking. All 18
  focused static/OAuth/consent cases pass; authenticated browser and final checkpoint
  gates are recorded separately in [scenario evidence](../20261107-1208-configure-mcp-test-modes.md).
- [x] Preserve received RPC counting before authentication in the shared fixture.
  Independent review found that moving counting after authentication weakened
  existing no-tool-request assertions. Three failing rejected-request cases now
  pass without executing unauthenticated RPCs.
- [x] Use incorrect credentials in each static method's own format in negative
  protocol acceptance: wrong bearer, wrong x-api-key, and Basic with the correct
  username and wrong password. Keep the absent-credential cases as well.
- [x] Exercise anonymous, bearer, custom-header and Basic startup modes through the
  authenticated Console. Verify create, incorrect-credential rejection where
  applicable and saved-secret testing; failed Basic replacement keeps the existing
  identity/generation. All four disconnect checks pass; Basic was completed after
  the pointer fix below. Eighteen focused cases and all five root gates pass
  (4,991 tests, zero failures, 241 excluded, seed 579799). Mobile tool lists render.
- [x] Prevent pointer activation of Tools from dismissing the recentering management
  dialog. Five failing assertions reproduce the gesture boundary; thirteen focused
  dialog/management tests now pass. Restore anchored management height and Authentication scrolling.
  Headless Chrome pointer/keyboard checks pass at 390×844 and 1280×900, including
  inside-to-backdrop release, genuine outside dismissal, Escape and long forms with
  reachable actions. The 1,062-test frontend suite, TypeScript and asset build pass;
  all five root gates pass (4,991 tests, zero failures, 241 excluded, seed 721027).
  Independent adversarial source/test/browser review is clean; see the
  [evidence](../20261107-1229-stabilize-mcp-dialog.md).
- [x] Add the independent review's complementary gesture cases: release over content
  and a different pointer's release must not complete a backdrop dismissal.
- [x] Verify custom unprotected DCR URL discovery, initial denied consent, draft
  recovery and successful retry through the actual Console browser. The automatic
  method selection exposes only the optional initial registration token; denial
  creates no connected record, and approval initializes/tools-discovers one record.
  Saved-credential testing returns HTTP 200, and management/tools render on desktop
  and mobile without exposing saved values. Protected registration and retained
  Basic-to-DCR recovery now pass above; broader listed/replacement recovery remains open.

- [x] Repair the controlled browser launcher's prerequisites and lifetime. Create
  its output directory before startup; attach its named fixture supervisor to
  Console so peers survive script evaluation; use an explicit test CA for actual
  CIMD retrieval with peer/hostname verification. The first browser attempts exposed
  peer shutdown and invalid test trust, without changing production policy.
- [x] Verify custom CIMD in an authenticated desktop/mobile browser: URL discovery,
  unavailable-server retry, real TLS CIMD fetch, explicit consent, callback,
  initialization/tools, refresh and undisplayed saved credentials. Denied replacement
  preserves the connected generation. Mobile retained review, denied reconnect and
  later approval preserve ID/namespace; a connected duplicate opens existing
  management. The combined fixture/OAuth/renewal lane passes 39 tests. All five root
  gates pass: 4,991 tests, zero failures and 237 excluded (seed 594684). Other methods,
  listed identity, partial/multiple-issuer discovery and cross-node callback gates
  remain open. See
  [browser evidence](../20261107-1108-integrations-browser-acceptance.md) and
  [runner guide](../../docs/development/mcp-browser-acceptance.md).
- [x] Complete fresh-checkout MCP dependency preparation in setup and CI. The
  isolated browser checkout reproduced ExMCP compilation before Plug was built;
  include dependency children when compiling the patched ExMCP. The focused fix
  passes 33 setup tests, source review and a complete fresh-checkout setup. All five
  root gates pass: 4,987 tests, zero failures and 235 excluded (seed 999227). This
  prerequisite does not close browser acceptance. See
  [bootstrap evidence](../20261107-1110-fix-mcp-bootstrap.md).
- [x] Require an explicit release acknowledgement in cross-node renewal lifecycle
  tests. The unconditional response-finished signal could also mean hold timeout;
  four strengthened cases failed before the fixture emitted the correlated release
  signal. Keep completion observation separate from proof of the intended release.
- [x] Update stale machine-grant interoperability assertions to the implemented
  private runtime projection: current token plus submitted MCP headers. Exact-map
  equality still rejects client/refresh/private-key secrets; three broader-lane
  failures exposed the old expectation. Independent source review confirms the
  header projection is required by the transport contract. Record the completed
  combined rerun accurately: 25 tests pass, including both review corrections.
- [x] Reconcile transport acceptance wording after documentation review: complete
  the narrow per-admission/remote-revocation gate, retain broader workflow gates,
  record the passing MCP lane and name caller cancellation and renewal-runner
  restart as outstanding. The subtask split preserves the existing scope/order.
- [x] Preserve the existing MCP session across clean SSE EOF while the stream
  process resumes; monitor actual stream termination so credential rejection still
  unblocks the receiver. The focused red test returned connection_closed before
  resumed events; it now receives them. Never replay a tool POST to repair a stream.
- [x] Consume successful SSE reconnect notices and handle resumed GET rejection.
  Two review regressions reproduced mailbox accumulation and a missing 405 result;
  all 14 focused transport tests now pass. Keep the usable POST session on 405;
  explicit disconnect retains ownership of stream cleanup.
- [x] Sample the cross-node fixture's token-response hold flag before notifying the
  test. Changing the flag for an unrelated tenant cannot release the already-held
  response. All five cross-node cases pass after the correction; source re-review
  is clean.

- [x] Match cross-node evidence to the assertions: the two peers have distinct OS
  and PostgreSQL backend IDs, and their OS IDs differ from the parent. The test
  does not compare the parent's database backend ID. Keep token/transport lifecycle
  acceptance open; repository concurrency checks alone do not establish it.

- [x] Finish the phone-acceptance review fixes: send signed carrier hangup and
  observe exact room/socket/leg/tracker cleanup plus persisted managed completion;
  add explicit failure-path tracker cleanup, recheck no tool requests after final
  speech/shutdown, and validate privacy markers in every decoded carrier frame.
  All three strengthened cases pass with real archive persistence and independent
  source re-review. Observe durable archive closure before sandbox release; carrier
  cleanup completion follows the archived end time and need not equal it.

- [x] Preserve historical icon metadata when publishing an iconless native entry,
  and document safe deployment/rollback order. Independent review required reading
  the old revision after removal and clarified that republishing the current
  catalog does not remove incompatible retained snapshots. The regression and
  full Go race/vet/build checks pass; native icon prerequisites are committed in
  their external repositories. Public release remains pending.
- [x] Replace the stale Cal.com icon with its currently declared 512-pixel PNG.
  A real local catalog sync first rejected the old unadvertised URL; inspecting
  the three MCP landing pages and correcting only Cal.com makes all 16 entries
  import successfully without weakening declared-icon validation.

- [x] Strengthen in-flight revocation acceptance to consume the initial protocol
  handshake and stream observations, then reject every later POST/GET/stream-open
  observation, including unexpected initialization or reconnects. The controlled
  held response succeeds only on explicit release; subsequent tool selection fails
  without sending another request. All 17 saved-runtime acceptance cases pass.

- [x] Revalidate current runtime credentials before reusing an open MCP session for
  another activation. A saved, admitted sibling-call regression first completed a
  delayed transfer after disconnect; a focused Connections regression also failed.
  Reuse now resolves and discards current headers, rejects the activation on failure,
  and preserves other rooms' shared session. Per-request authorization remains in
  place. Cold/reused failure leaves the source responsible on the original peer.
- [x] Address saved-boundary review gaps: re-prepare the original publication after
  catalog changes, give simultaneous peers distinct supervised identities, and
  correlate model inputs/transfer outcomes rather than accepting arbitrary mailbox
  traffic. Foreign-tenant positive control uses a separate server and credentials.
  Replace the warm-case mailbox drain with a controlled held SSE stream, so a
  legitimate request submitted before revocation cannot cause a timing-dependent
  false failure. Observe and release the exact stream; timeouts cannot pass.

- [x] Forward the trusted MCP connection provider through Gateway admission while
  preserving saved-tenant catalog construction and rejecting protocol/request
  overrides. The focused red test first reported the missing option; all six
  Gateway option tests pass. An invalid HTTP provider field leaves its join token
  available for the subsequent valid request.
- [x] Give MCP tools without an optional description a model description based
  only on their public alias. The full saved-call test exposed agent startup
  failure; a focused red/green descriptor test now covers the fix. Preserve
  schema validation and existing host-tool requirements; all six descriptor tests pass.
- [x] Address saved-call review gaps: inspect every consumed RTVI frame for private
  values, match the exact invocation completion ID/status and check for extra
  tools/call submissions again after final peer output and observed cleanup.
  The six-test saved-runtime/managed-web integration lane, independent adversarial
  re-review and all five checkpoint root gates pass (4,986 tests, zero failures).

- [x] Reject non-map OAuth proposals before credentialless target resolution.
  The red case raised BadMapError; it now returns the fixed validation error.
- [x] Preserve the intent of MCP boundary tests after adding earlier authority
  refresh: revoke machine-grant authority during the acknowledged probe. Give the
  completion deadline fixture a 1,000 ms test-only budget to reach its held stage,
  then assert timeout and monitored worker termination; retain the production
  15-second limit. Independent review approved the correction, and the focused
  Calls/Console lanes pass. Remove the exercised endpoint's unused import.

- [x] Reconcile durable documentation with implemented security boundaries: raw
  SecureHTTP token validation, initialization-before-grant persistence, DCR saved-
  scope coverage, explicit retained-revoked reconnect, startup source compatibility
  and per-request identity checks. Correct split browser/renewal test commands and
  remove obsolete form/runtime-pending claims. Keep real acceptance gates open;
  see [documentation review](../20261107-0413-reconcile-integrations-progress.md).

- [x] Stabilize fixture delivery through an acknowledged Google STS message send,
  avoiding a query against a legitimately retired wire. Isolate ingress cancellation
  and binding-error cases with fresh per-test setup while retaining all assertions.
  Test-only checkpoint; full umbrella seed 825059 passes 4,887 tests. See
  [delivery evidence](../20261107-0424-stabilize-test-delivery.md).

- [x] Split native credential and MCP mutation permissions in the inventory and
  production route. Test service-only, credential-only and platform-only writers;
  prevent enabled inherited actions that the tenant wrapper cannot execute.
- [x] Keep the production inventory mounted across cursor navigation and verify
  failed-next-page recovery through the actual Integrations wrapper.
- [x] Persist the effective authentication selection after saving a discovered
  anonymous endpoint; keep subsequent Test connection enabled.
- [x] Send generation/refresh_tools for catalog-only refresh, preserving saved
  configuration and unsaved form credentials; align in-memory Storybook responses.
- [x] Complete installed native capability projection and first-render verification
  without eagerly loading model/credential settings.

- [x] Remove unsupported cached schemas from picker choices while preserving valid
  siblings/native tools; explicit unsupported selections still fail compilation.
- [x] Reproduce raw supervisor exposure and remove saved credentials/keyrings from
  ancestor child arguments. Validate token/header/keyring privacy on activation
  retirement and client failure, before default Logger translation suppresses SASL.
- [x] Resolve and replace complete credential headers per request, including saved
  OAuth MCP headers after renewal; validate endpoint/source and Basic/Bearer schemes.
- [x] Classify fixed pre-submission credential rejection as not submitted in both
  ExMCP request modes; keep other transport outcomes ambiguous and never retry them.
- [x] Upgrade the previous reviewed dependency patch through an exact checksum-pinned
  transition, preserving unknown edits and supporting shallow-checkout CI tests.

- [x] Isolate official MCP fixture npm commands in their pinned checkout working
  directories after reproducing lock resolution failures from Vxpipe. Preserve
  fixture revisions and scenarios; the full MCP integration lane passes 176 tests.
- [x] Give fresh SSE event IDs precedence over captured initial HTTP cursor headers;
  reproduce the stale reconnect cursor and verify resumed HTTP uses the latest ID.
- [x] Redact live SSE OTP termination reports when runtime credentials are rejected;
  verify both formatted and structured reports exclude cached header sentinels.
- [x] Return a fixed HTTP submission error on the exact runtime credential-rejection
  signal, preventing a live stateless client's crash report from exposing custom
  headers. Keep zero-network rejection and terminal SSE behavior.

- [x] Anchor machine-acquisition and renewal token expiry before token HTTP;
  verify request and MCP-check time cannot extend the returned lifetime.
- [x] Admit renewals before durable claim with an aggregate concurrency/lifetime
  bound. Busy work must not consume claims; held I/O, caller death and late success
  must not bypass durable ambiguity fencing or persist late tokens.

- [x] Return failed/denied OAuth callbacks to the bound tenant view using only
  authenticated claimed-attempt context. Recheck current authority/installation
  even after protocol failure; leave invalid or unclaimed state as bare errors.
- [x] Restore only a matching, bounded-lived nonsecret UI draft after the callback.
- [x] Admit and bound the entire callback completion before code redemption;
  verify zero-capacity rejection, held-I/O timeout, caller death, worker cleanup
  and rejection of late success before persistence.
- [x] Anchor access-token expiry when the exchange starts or the response arrives;
  MCP initialization/tool-discovery delay must not extend the token lifetime.

- [x] Map known repository/connection outages to stable errors in OAuth attempt
  and grant stores, preserving programmer exceptions and successful recovery.
- [x] Clear a prior access-token expiry when a refresh result omits its own expiry;
  retain the saved refresh token and scope only under their deliberate contracts.
- [x] Authenticate attempt expiry and state digest inside the encrypted envelope;
  reject database metadata tampering that changes either lookup state or lifetime.
  This extends storage tamper resistance, not browser authority.
- [x] Verify old/new-key attempt claims, missing-key non-consumption, re-encryption
  during refresh, wrong-tenant grant operations, exact deadline equality, and
  invalid/oversized refresh completion rollback at the persistence boundary.
  All 57 focused MCP persistence tests pass; see the
  [storage runbook](../../docs/development/mcp-oauth-storage.md) and
  [checkpoint evidence](../20261107-0132-review-mcp-oauth-storage.md).

- [x] Do not suggest browser OAuth when all advertised token authentication
  methods or signing algorithms are unsupported by Own client or managed flows.
- [x] Reuse DCR registration only with scope evidence covering the newly selected
  challenge/resource scopes; request fresh registration when coverage is unknown
  or insufficient. Keep same/subset-scope reuse working. Two red regressions now
  pass; the full MCP suite passes 163 tests.

- [x] Validate raw OAuth token responses before dependency defaults: require
  token_type and match the supported Bearer token character/size contract. Cover
  omitted type, invalid token characters and oversized access tokens.
- [x] Reject CIMD handoff when explicitly advertised token authentication methods
  exclude the public client method; keep discovery suggestions consistent.
- [x] Validate managed token-endpoint query parameters before dynamic registration
  so protected-field conflicts cannot create an unusable external registration.
- [x] Bind DCR request metadata to selected resource/challenge scopes and supported
  grants, and validate explicit returned grant/response-type/scope changes before
  browser handoff. Distinguish optional RFC scope metadata from the chosen
  interoperability policy; do not silently assume every registration is usable.
  Eight red regressions reproduced these issues; 40 focused tests now pass. See
  [protocol boundary](../../docs/development/mcp-oauth-protocol.md) and
  [review evidence](../20261107-0113-review-mcp-oauth.md).

- [x] Reject recognized credential query parameters before discovery or connection
  I/O so tokens cannot enter public endpoint columns or read responses. Preserve
  nonsecret query parameters, cover encoded/case variants and verify the real
  Console probe adapter's public projection. Log filtering alone is insufficient.
- [x] Permit fresh credential replacement without decrypting unreadable old
  ciphertext. Validate tenant/identity/generation from metadata first and resolve
  old secrets only when credentials were deliberately omitted.
- [x] Keep the static management checkpoint independently runnable: exclude later
  OAuth structs/helpers/routes from its fixture and wiring, and add static catalog
  refresh plus real Console probe adapter coverage.

- [x] Isolate pure OAuth metadata capability validation from later authorization
  and client-assertion/signing modules so the discovery foundation is independently
  runnable. Validate types and bounds for scopes, grant/response/challenge/auth
  arrays and the CIMD flag before returning an OAuth discovery outcome.
- [x] Normalize exceptions/throws inside DiscoveryIO's spawned callback worker
  before OTP reporting. Synthetic log-capture regression passes; the reproduced
  gap is an injected callback boundary, not a confirmed remote-server secret leak.
- [x] Accept permitted whitespace around Bearer challenge parameter separators
  while preserving duplicate rejection, and validate challenge scopes before
  returning discovery metadata. Preserve quoted and escaped content. The pinned
  HTTP parser is stricter than the protocol at this whitespace boundary.
- [x] Verify composed preflight-runner cancellation through held DNS/HTTP work
  and cleanup on actual application runner restart in the isolated test BEAM.
  Five lifecycle tests pass in addition to the isolated component checks.
- [x] Allow explicit issuer discovery for Own-client only when resource metadata
  is missing. Never bypass malformed/conflicting/unavailable metadata. Reject
  oversized, invalid UTF-8 and forbidden issuer URL forms before I/O instead of
  reflecting them in partial results. Both behavior regressions failed first.
- [x] Accept bare Bearer challenges, including mixed casing and permitted empty
  list entries, without inventing parameters or accepting multiple Bearer
  challenges. The well-known fallback regression failed before the parser fix.
- [x] Enforce the preflight deadline when accepting a queued result, not only when
  handling the timer message. A suspended-runner regression reproduced late
  success and now returns the fixed timeout. See the
  [discovery decision](../../docs/development/mcp-discovery.md) and
  [checkpoint evidence](../20261107-0031-review-mcp-discovery.md).

- [x] Correct the MCP connection-row SQL constraint to reject connected rows with
  NULL ciphertext and a present key ID. Add a database constraint regression;
  repository writes already encrypt payloads, so this is an integrity gap rather
  than a demonstrated authorization bypass.
- [x] Make connection-storage foundation tests independent of the later OAuth
  grant store; retain grant-renewal/catalog integration evidence in its own lane.
- [x] Normalize stopped/missing MCP repositories and checkout failures to the
  fixed unavailable result using the existing provider-store boundary pattern;
  preserve programmer errors and prove recovery with an isolated fixture Repo.
- [x] Verify repository restoration of a revoked MCP identity with fresh secrets
  at the observed revoked generation, preserving ID/namespace and advancing the
  generation. Add wrong-tenant replacement and failed-batch rollback coverage.
  Fifteen store tests, two distinct PostgreSQL-client race tests and the full
  473-test Persistence suite pass; static gates pass. See
  [storage review](../20261107-0013-review-mcp-storage.md).
- [x] Add authorized static HTTP reconnect for retained MCP identities with fresh
  credentials and the observed revoked generation. Normal create returns an
  explicit proposal; reconnect preserves ID/namespace and never resolves old
  credentials. Two tagged HTTP/PostgreSQL/local-MCP tests verify the actual
  disconnect/reconnect path and fresh replacement after losing an old key. See
  [management evidence](../20261107-0052-review-mcp-management.md).
- [x] Wire retained-identity reconnect into delegated OAuth attempts, including
  fresh registration after secret erasure or unavailable old keys.
- [x] Wire retained-identity reconnect into the production modal. Focused endpoint/UI
  tests and rendered desktop/mobile recovery pass; full authenticated workflow
  acceptance remains open in T6b/T8.

- [x] Extend MCP cipher boundary evidence after adversarial review: key-ID aliases
  with identical key material, provider/MCP envelope substitution, exact plaintext
  size, oversized/unsupported envelopes and encoding-error normalization. Verify
  oversized data is rejected before key lookup. Keep
  this checkpoint separate from record authorization and OAuth lifecycle claims.
  All seven focused tests pass; see the
  [cipher checkpoint](../20261106-2345-review-mcp-cipher.md).

- [x] Reject production localhost and IPv4/IPv6 loopback origins before client
  startup, including private-host allowlist attempts. Preserve per-request DNS
  validation/address pinning and the separate trusted loopback fixture profile.
  The focused loopback test failed before the guard and passes afterward.
- [x] Fix cancellation during MCP initialization: acknowledge supervised startup
  before network I/O, register the client with an independent lifetime controller,
  and enforce the absolute deadline before accepting completion. Eight held starts
  reject a ninth promptly; concurrent success, owner death, timeout, expired
  admission and late completion tests pass. The original cancellation test failed.
- [x] Keep raw MCP options out of supervisor start metadata and redact callback
  status/error reports. Synthetic bearer/Basic/header/query markers are absent from
  formatted and structured crash logs. The original startup-report exposure was a
  source hypothesis, not reproduced by the initial fixture; do not overstate it.
- [x] Attempt bounded disconnect/session DELETE and pin check-only POST mode to
  avoid unowned asynchronous POST workers. Local HTTP fixtures prove DELETE and
  actual socket closure during cancelled initialization/tools-list and stalled
  DELETE. Only completions accepted before the deadline can succeed; final local
  cleanup has a separate bounded budget. All 26 scoped tests and the 137-test MCP
  suite pass; static gates pass. See the
  [check checkpoint](../20261106-2354-review-mcp-checks.md) and
  [lifecycle decision](../../docs/development/mcp-connection-checks.md).

- [x] Strengthen directory cache evidence after adversarial review: acknowledge
  the second pending caller before releasing the first fetch, fail a refresh of
  an actually cached/expired page, and cover byte eviction, worker/waiter limits,
  crash/timeout slot recovery and worker termination on a cache restart. Use
  process/message acknowledgements and controlled clocks rather than sleeps.
  Fourteen focused tests and the full 476-test Console suite pass. See the
  [cache checkpoint](../20261106-2339-review-directory-cache.md) for the test-clock
  synchronization correction and review evidence.

- [x] Validate MCP endpoint host and port in addition to generic URI syntax;
  reject hostless HTTPS authorities and ports outside 1–65535. Strengthen the
  streaming-size regression to require `response_too_large` for valid oversized
  JSON, so invalid-JSON rejection cannot conceal a missing byte cap.
- [x] Keep checkpoint milestone claims tied to committed behavior: split the
  completed version accessor from the later facade/browser response field, and
  distinguish checkpoint tests from the broader worktree verification lane.

- [x] Enforce URI formats in directory schema validation and align category query
  identifiers with the shipped schema. Review found malformed HTTPS-prefixed URLs
  accepted as valid and valid returned categories that could not be requested.
  Regression tests failed before enabling formats and matching the category grammar.
- [x] Document directory HTTP timeouts as per-phase budgets, with caller-owned
  total-lifetime cancellation, rather than promising a five-second wall-clock cap.

- [x] Tighten public directory response identity before committing the client:
  reject a response whose revision differs from the explicitly requested snapshot,
  and reject a later page when the request omitted its cursor. Add failing
  regressions and preserve valid continuations/empty pages. The 23 scoped tests
  and full Console suite (470 tests) pass. Final adversarial staged review is
  tracked in the [client checkpoint](../20261106-2325-review-directory-transport.md);
  final milestone-wide root acceptance remains in T8.

- [x] Complete adversarial pre-commit review of the Storybook discovery checkpoint.
  Fix URL edits in Manage that reset the method without running discovery, expose
  the same progress/retry states and disable Save until a method is selected.
  Ignore an inactive authorization URL after switching to client credentials.
  Add transition regressions and preserve manual OAuth edits during pending
  discovery. Both transition regressions failed before the fixes; 108 prototype
  and 967 frontend tests pass, as do TypeScript, focused lint and root gates.
  Chrome desktop/mobile verifies Manage rediscovery through simulated consent.
  Independent GPT-6 Astra xhigh re-review reports no remaining scoped code issues;
  the labnote absolute-path hygiene issue was also fixed. See the
  [review checkpoint](../20261106-2316-review-mcp-prototype.md).

- [x] Support OAuth management through the existing detail/update APIs. Return
  only fixed OAuth method labels; unavailable decryption keys still permit public
  details. Add explicit catalog-only refresh using saved current credentials and
  a final generation/permission check. Preserve encrypted grants and configuration
  generation so token rotation cannot be overwritten by a tools refresh. Preflight
  exposes validated public callback metadata for manual registration. Focused
  Calls 20, persistence 10 and Console endpoint 14 tests pass; frontend use remains
  part of the open production-dialog tasks.

- [x] Preserve Own-client MCP headers at runtime startup without copying token
  parameters, access tokens or signing keys into client options. Reject saved
  headers that could replace runtime Authorization; eight runtime catalog tests pass.
- [x] Preserve Own-client configuration and browser-grant error codes through
  Calls/Console as 422 responses, without creating consent attempts. Twenty-four
  focused Console endpoint/protocol tests pass.
- [x] Prefer the resource challenge's scope over `scopes_supported` in managed
  CIMD/DCR preparation, sharing the default-selection rule with Own-client. A red
  test exposed the ignored challenge; the fix also covers non-subset scope sets.

- [x] Prevent endpoint query fields from bypassing the managed OAuth parameter
  boundary. Regression tests first accepted authorization request objects and
  token grant overrides in endpoint queries. Both paths now validate query fields
  and reject duplicates/conflicts with supplied parameters. Negative transport
  tests use observed messages rather than exceptions that adapters can redact.

- [x] Preserve the preparation limiter's busy result through OAuth start/reconnect
  and return HTTP 429 before issuing an attempt. The endpoint regression first
  returned generic 503; it now passes for both operations. Allow trusted Console
  composition to supply an isolated bounded runner, keeping the default production
  limiter unchanged. The focused endpoint/preparation/HTTP-database lane passes
  all 17 tests.

- [x] Isolate cancellation/error cases in CallIngressTest. Umbrella run 50822
  failed when the loop reused a retiring call identity. Each generated test now
  gets its own setup identity and cleanup; all 27 tests in the file pass with
  the failing umbrella seed. No telephony runtime behavior changed. Full umbrella
  rerun 56503 passes every application, including Gateway 870 and Console 456.

- [x] Return a stale-connection conflict when authentication changes during OAuth
  consent. The regression first returned invalid reconnect; generation checks now
  precede authentication-type checks, stopping before token redemption. Calls suite
  passes, including cross-tenant and concurrent-replacement cases.

- [x] Replace failed remote directory logos with a neutral icon, retaining row
  actions and allowing a changed logo URL to load. The regression test first failed
  on the broken image; nine directory tests, TypeScript and the full frontend
  suite pass. Chrome desktop/mobile inspection confirms the neutral icon and
  intact row layout; a changed logo URL retries normally in the regression test.

- [x] Fix the full-suite GoogleSTSControllerTest delivery synchronization race:
  root run 54822 queried the old transport after goAway had legitimately retired
  it. The focused IDLE/BUSY cases pass with the same seed. Acknowledge fixture
  delivery synchronously instead of querying the retired transport; preserve the
  resumption assertions. Explicit synchronous delivery now replaces unsafe barriers
  in both controller and provider helpers; deliberate late-message tests retain
  asynchronous delivery. All 193 fixture-consumer tests and static gates pass.
  Full umbrella rerun 20722 passes all applications with zero failures.

- [x] Consolidate native inventory loading for Integrations. Reuse the existing
  Services credential/binding operations and hosted directory API; avoid the
  eager ScopedServicesApp plus IntegrationsDirectory duplicate inventory reads.
  Keep native modals, validation, overrides and removal on their existing handlers;
  extend the local inventory contract only for directory/MCP data it does not own.
  Native editor settings now load only on an explicit native action; mutation
  success refreshes the joined inventory instead of both inventories. Telephony
  still loads settings needed by its existing application-management controls.
  Initial-load and existing editor/override/restore tests pass; rendered desktop
  and mobile override flow verified. No new native-management backend was added.

- [x] Enforce shared-callback mix-up defense: require advertised RFC 9207 issuer
  response support before registration/consent, and an exact response `iss` before
  code redemption even for attempts stored with the old optional flag. Add missing,
  false and mismatched issuer tests and expose unsupported capability in preflight.
  Applies to authorization-code flows, not client credentials. Decision and rejected
  dynamic-redirect fallback are recorded in docs/development/tenant-mcp-oauth.md.
  Red tests reproduced registration, missing-issuer acceptance and false OAuth
  suggestions. MCP 93 / Console 446 / focused frontend 7 tests now pass; TypeScript
  and static checks pass. Full OAuth/browser interoperability remains a release gate.

- [x] Stabilize the transient-check cancellation test's startup acknowledgement
  deadline under umbrella load. Root run seed 588816 missed `checked_client` at
  the default 100 ms. Increased the bounded startup wait to 1 second and retained
  monitor-based cleanup. The rerun's MCP lane passes all 90 tests; the remainder
  of the umbrella suite is still running, so the full-root gate stays open.

- [x] Preserve the longer origin cooldown when concurrent directory requests return
  different Retry-After delays. Red test reproduced a premature upstream request;
  monotonic maximum deadline fixes it. All 33 directory tests pass.

- [x] Preserve the operational `credential_key_unavailable` error when attempt
  encryption cannot run; roll back without inserting an attempt. Regression test
  failed before the fix and passes afterward.

Keep this list current as fixes are identified; add review-agent findings here.

- [x] Reject deleted tenants before outbound connection checks and redact custom
  header values plus endpoint query strings from Phoenix parameter logs.
- [x] Exercise real CSRF enforcement in endpoint tests by removing the test bypass
  and obtaining a token through the session page.
- [x] Make Refresh tools use saved endpoint/credentials even when the authentication
  draft contains an invalid URL; preserve that draft during refresh. Regression passes.
- [x] Restore the inherited native integration Edit action to the tenant management
  modal instead of redirecting directly to Platform. Regression test reaches
  Override for this tenant; 14 focused UI tests and TypeScript pass. Rendered
  desktop/mobile Storybook inspection confirms the inherited and override states.
- [x] Allow tenant-write users to reach inherited native override controls without
  platform-write permission; retain the prohibition on tenant-page removal of
  platform credentials. Red/green regression and rendered mobile check pass.
- [x] Verify named override restoration deletes exactly the tenant credential,
  refreshes inherited state and allows overriding again. Production-component
  fixture test passes; real backend/browser save-and-restore acceptance is pending.
- [ ] Verify native override/restore against an authenticated backend browser session.
  The existing tenant controls and role separation are implemented and fixture-tested;
  editing the shared platform credential still requires platform write permission.

- [x] Persist replacement generation through the Ecto changeset instead of only
  mutating its source struct. Stale-write regression now rejects old generations.
- [x] Hide resolved MCP secrets from generic inspection using a private snapshot
  struct; the redaction regression passes.
- [x] Force initial connection generation to one and return a deterministic duplicate
  when endpoint and directory identity match different records. Focused tests pass.

- [x] Restore native credential removal in the replacement inventory, targeting the
  exact named binding. Preserve connection state on failure and suppress removal
  for read-only/inherited connections. Focused red/green and rendered fixtures pass.
- [x] Derive native row capability badges from installed provider capabilities,
  rather than the broader prototype catalog. Focused red/green regression passes.
- [x] Migrate all remaining Services route tests to the Integrations API and UI,
  retaining credential, stale-response, permissions and onboarding coverage.
  Full frontend suite: 945 tests pass across 124 files.

- [x] Remove the shared runtime configuration's dependency on Console-only code so
  individual umbrella children start independently. Gateway child rerun: 26 tests pass.
- [x] Correct Req/Finch timeout configuration so real HTTP works, not only Plug mocks.
  Tagged local HTTP regression and read-only hosted-directory fetch pass.
- [x] Handle negative monotonic timestamps when checking cache freshness.
  Focused cache hit/revalidation tests pass.
- [x] Return a recoverable busy result when fetch-worker capacity is exhausted,
  rather than crashing the shared cache. Focused capacity regression passes.

Checkpoint evidence 2026-11-06: frozen backend full umbrella run passed (seed
369158), including 423 Console tests; format, warnings-as-errors compilation,
strict Credo and unused-dependency checks passed. This verifies the T1/T2 backend
checkpoint, not the remaining UI/MCP milestone or final release acceptance.

## Specification review (separate from implementation)

Saved-admission design review, 2026-11-07: independent review approved forwarding
only the trusted connection provider while preserving saved catalog construction,
real admission and protocol handling. It required authenticated tenant disconnect,
same-room terminal failure, bidirectional wire/model/peer observations, input
override rejection and teardown before global configuration restoration. These
are checkpoint contracts; the remaining T7/T8 gates keep their original scope.

Local design/dependency review, 2026-10-25: directory browsing can ship before OAuth;
T4 enables static MCPs without depending on remote availability; T5 requires T4 and
Console identity; T7 must replace every tenant fallback seam, not only inventory.
Native API definitions are an external dependency. Advanced JWT/client credentials
need their own interop gate. A successful empty response is not an outage. These
were design-only contracts at that review. Current implementation progress is
tracked in the task lists above; that historical review does not establish delivery.

Local design/dependency review, 2026-11-06: inspected current Storybook components,
Console routes, MCP metadata helpers and installed ExMCP authorization interfaces.
The existing milestone is the correct owner; no duplicate plan was created.
T4a now separates non-mutating preflight from OAuth side effects; T5 owns DCR's
initial token; T6 owns manual-only overrides. The field/reset matrix incorporates
specific user decisions without marking full workflow approval or production gates
complete. Storage/routes and outbound grants were pending at that review and are
now implemented; the historical review is not their verification evidence.
The external API release-content prerequisite remains unverified by this review;
the attempted documentation fetch was unavailable, not evidence of API health.
See [review evidence](../20261106-1535-integrations-milestone-review.md).

Full workflow review remains open. Earlier rendered/prototype evidence is recorded in the
[checkpoint labnotes](../20261025-1834-integrations-directory-proposal.md).

Implementation-status review, 2026-11-07: independent read-only review reconciled
committed facade/static/discovery/OAuth/runtime wiring with duplicate unchecked
specification tasks. Historical test counts remain checkpoint evidence, not final
release results. Listed-template and retained-ID UI are explicit missing vertical
slices. Authenticated browser, full room/admission/transfer, separate-node and
external-directory publication remain open. The index stays unchecked. See
[reconciliation labnotes](../20261107-0413-reconcile-integrations-progress.md).

Acceptance follow-up, 2026-11-07:

- [x] Preserve intentional room-push interruption during output preemption. A late
  successful/interrupted reply for a retired turn no longer kills room output;
  native clear remains the sole post-drain frame acknowledgement. Preserve genuine
  RTP failures and reject interruption while the token is current. Five red-first
  regressions, 39 focused tests, independent adversarial re-review, all five root
  gates (4,955 tests, seed 362537) and Lean build/oracle/replay pass. The test gate
  uses an explicit release and cleanup, without a timing fallback. See
  [output correction](../20261107-0720-inspect-transfer-policy.md).
- [x] Stabilize the umbrella gate's pending-admission shutdown test by acknowledging
  the owner after creating its asynchronous monitor and before terminating the
  separate controller. Exact shutdown-reason/no-dial assertions are preserved;
  50 focused repetitions, the full 29-test file and all 4,931 umbrella tests pass
  (seed 181095). See [correction evidence](../20261107-0613-fix-admission-monitor.md).
- [x] Stabilize the terminal speech-overflow fixture by observing completion through
  the capability instead of awaiting a reply from its deliberately retired provider.
  Exact overflow and termination assertions remain; fifty focused repetitions and
  the full 63-test file and all 4,931 umbrella tests pass (seed 181095). See
  [correction evidence](../20261107-0625-fix-overflow-fixture.md).
