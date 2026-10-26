# Integrations directory and tenant MCP connections

Status: **proposed; production implementation not started**. The Storybook proposal
is part of this specification, not evidence that backend behavior is implemented.
User review/approval of the workflow remains open. This milestone makes the hosted
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

## Contract to approve

- Inherited native connection management requires installation-scoped
  `platform_services.write`; omit source labels from listings. MCP manage dialogs
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
- [ ] Obtain user approval of the workflow, including advanced authentication scope.

Acceptance: the user can follow the listed Storybooks from browse through connection
and recovery without a production backend or any credential/network submission.

### T1 — Versioned directory client and external release readiness

Depends on T0 workflow decision; external native definitions are a release gate.

- [ ] Finish/verify root VERSION-to-OTP build metadata; expose a programmatic runtime
  version accessor and browser response field without a second version constant.
- [ ] Configure the default API origin and validated runtime operator override.
- [ ] Add a Console-owned public-directory client: schema validation, version header,
  `category`, global `q`, scope, pagination and typed/redacted error mapping.
- [ ] Verify/add native entries and this release's adapter IDs **in the separate
  directory repository**, coordinated as an external prerequisite; do not mark
  this task complete against an MCP-only catalog.

Acceptance: local HTTP fixtures assert outgoing version/header/query shape, valid
empty pages, optional compatibility bounds, unsupported schema/version, unknown
native adapters, malformed cursors and bounded response/timeouts. A tagged read-only
live check confirms categories/native/MCP entries for the release, with no secrets.

### T2 — Bounded public cache and directory outage fallback

Depends on T1. Native connection management remains the existing implementation.

- [ ] Cache validated pages with ETag, bounded memory/TTL, keyed by origin/version/
  query/scope/page; coalesce misses and handle 304 without a cached body safely.
- [ ] Add authenticated Console facade with local connection-status join and current
  permission filtering. Publish read-safe statuses, never encrypted/plain secrets.
- [ ] Derive fallback from installed Registry credential capabilities; exclude
  uninstalled/unsupported adapters. Preserve tenant-over-platform precedence.
- [ ] Implement timeout/429/5xx/schema/unsupported-version fallback, sanitized
  diagnostics, explicit retry and request cancellation/out-of-order protection.

Acceptance: cached/fresh/missing/expired responses and concurrent requests cannot
cross query/version or tenant status boundaries. Outage leaves Connected, AI and
Telephony usable; no remote MCP is falsely offered from a stale listing. A failed
local status lookup never yields an enabled duplicate Connect action.

### T3 — Production browse/search navigation and pagination

Depends on T2; use the approved Storybook layout and existing credential modals.

- [ ] Connect tenant/platform routes, category breadcrumbs/mobile selector, default
  connected inventory, app-owned native categories and paginated remote categories.
- [ ] Implement global search, cursor history, previous/next, expired-page restart,
  next-page retry, valid empty results and unavailable-category recovery.
- [ ] Preserve modal drafts and selected query/category while opening/closing native
  credentials. Match local connection state before deciding Connect versus Edit.
- [ ] Keep custom MCP CTA gated until T4 is available; no dead production control.

Acceptance: real Console browser checks at desktop/mobile cover healthy directory,
API outage and recovery, direct URL/back/forward, unknown status, permissions and
platform exclusion. Existing native connection/update/override tests remain green.

### T4 — Tenant MCP records and static/anonymous connection lifecycle

Depends on T0 approved form and completed prerequisite milestones; may proceed
independently of T1–T3 behind unexposed operations.

- [ ] Add persistence migrations for tenant connection identity/config generation,
  encrypted auth material and catalog snapshots, using the existing encryption
  keyring with explicit MCP identity binding and rotation participation.
- [ ] Add authorized Calls operations/repository ports and Console management API.
  Unique directory identity prevents concurrent duplicate creates. Custom identity
  is a durable ID/canonical endpoint, never a display name. Define endpoint duplicate
  handling and disambiguate same-name servers without editable connection aliases;
  keep the internal namespace stable if server metadata changes.
- [ ] Implement no-auth, bearer, API-key/custom-header and Basic connection checks,
  bounded discovery, edit/retest/disconnect and zero-tools state. Reuse ExMCP.
- [ ] Enable the tenant custom CTA once this slice works; expose only implemented
  authentication modes until T5/T6 pass. Platform never accepts these records.

Acceptance: restart persistence, encryption/redaction/key rotation, cross-tenant
isolation, permission changes, concurrent duplicate saves, masked edits, invalid
headers/URLs and catalog failure tests. A local fixture MCP proves initialization
and paginated tools without executing a tool; unavailable and zero tools differ.

### T5 — Automatic discovery and delegated OAuth

Depends on T4 and existing Console Installation URL/CIMD foundation.

- [ ] Inspect installed ExMCP support and adapt its discovery/authorization interfaces;
  record gaps before adding protocol code. Support protected-resource metadata,
  OAuth/OIDC issuer discovery, existing registration, CIMD, then DCR negotiation.
- [ ] Implement session/tenant/connection/issuer/revision-bound, expiring single-use
  attempts, PKCE S256, callback route, exact redirect/resource/scope handling.
- [ ] Add encrypted grant storage, refresh coordination across nodes, atomic rotated
  token persistence, permission recheck, redacted error and reconnect transitions.
- [ ] Implement manual-client handoff when registration is unavailable; preserve
  nonsecret draft, display exact callback only for manual registration, reject
  unsupported provider capabilities. Directory flows derive credential requirements
  from the template/live metadata; never expose managed endpoint/auth selectors.
- [ ] Make every discovery/authorization/token destination follow outbound policy;
  cover DNS/redirect handling and never leak tokens to another issuer/resource.

Acceptance: fixture authorization servers exercise CIMD, DCR, preregistration and
no registration, denied consent, expired/replayed/cross-tenant state, callback URL
changes, missing installation URL, malformed metadata, issuer substitution,
PKCE/resource validation, refresh races and invalid grants. Real browser flow
returns to the same tenant/category, then discovers tools before marking connected.

### T6 — Manual authentication interoperability

Depends on T4/T5; the existing broad form is a proposal, not a support claim.

- [ ] Add validated manual issuer/endpoints/scopes/resource/audience, DCR initial token
  and provider parameters without overriding managed OAuth/transport fields.
- [ ] Implement explicit machine-to-machine client credentials only with compatible
  server support, and private-key JWT with registered public-key requirements,
  bounded signing algorithms, protected keys and rotation.
- [ ] Verify public versus confidential client methods and selected grant compatibility;
  preserve previous working credentials until replacement validation succeeds.

Acceptance: each exposed method has a local interop case, negative override tests,
secret redaction and safe edit/reconnect behavior. Unsupported methods return a
specific recovery state; hiding an unimplemented choice requires updating the
proposal and obtaining scope agreement, not quietly claiming this milestone passed.

### T7 — Tenant-only runtime/tool picker cutover and migration

Depends on T4; OAuth methods additionally depend on T5/T6.

- [ ] Replace packaged tenant application-config fallback in ConfiguredNames,
  IntegrationCatalog, picker, publication, preparation and invocation. Keep explicit
  embedded-host configuration a separate boundary; report required migration work.
- [ ] Bind credentials/token provider and schemas privately by tenant connection ID
  and generation. Refresh tokens without changing stable tool identity.
- [ ] Reuse MCP-name/tool selection and double-underscore runtime naming. Select all
  saves explicit names; new tools do not grant themselves and removed tools fail safely.
- [ ] Invalidate on disconnect/revocation without re-enabling stale grants; no browser
  prompt on an active call and no retry of ambiguously submitted tool operations.

Acceptance: tenant A cannot list/execute tenant B or platform MCP tools; directory
outage does not stop an already authorized call. Catalog refresh, server-name changes, revoke,
refresh race and reconnect preserve pinning and scoped failure contracts. Migration
is repeatable and does not silently share or delete existing credentials.

### T8 — Release and operational verification

Depends on T1–T7. Update installation/operations docs and all related Storybooks.

- [ ] Run all five root gates plus focused frontend checks and rendered acceptance.
- [ ] Run tagged MCP/OAuth conformance and local cross-node persistence/refresh tests;
  live third-party checks only with explicitly provisioned test accounts.
- [ ] Verify remote API unavailable, no usable cached catalog, and connected-status
  unavailable independently. Check rate limiting, cache bounds, revocation and logs.
- [ ] Record independent implementation review, user workflow approval and release
  evidence; only then check the milestone in the index.

## Specification review (separate from implementation)

Local design/dependency review, 2026-10-25: directory browsing can ship before OAuth;
T4 enables static MCPs without depending on remote availability; T5 requires T4 and
Console identity; T7 must replace every tenant fallback seam, not only inventory.
Native API definitions are an external dependency. Advanced JWT/client credentials
need their own interop gate. A successful empty response is not an outage. These
are reviewed contracts and proposed gates, **not implemented backend features**.

User review remains open. Rendered/prototype evidence is recorded in the
[checkpoint labnotes](../20261025-1834-integrations-directory-proposal.md).
