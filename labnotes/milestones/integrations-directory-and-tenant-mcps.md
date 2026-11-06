# Integrations directory and tenant MCP connections

Status: **production implementation in progress; acceptance pending**. The Storybook proposal
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
- [ ] Obtain user approval of the complete workflow, including advanced authentication scope.

Acceptance: the user can follow the listed Storybooks from browse through connection
and recovery without a production backend or any credential/network submission.

### T1 — Versioned directory client and external release readiness

Depends on T0 workflow decision; external native definitions are a release gate.

- [x] Verify root VERSION-to-OTP build metadata and expose a programmatic runtime
  version accessor without a second version constant.
- [ ] Expose that installation version in the facade/browser response.
- [x] Configure the default API origin and validated runtime operator override.
- [x] Add a Console-owned public-directory client: schema validation, version header,
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

- [x] Cache validated pages with ETag, bounded memory/TTL, keyed by origin/version/
  query/scope/page; coalesce misses and handle 304 without a cached body safely.
- [ ] Add authenticated Console facade with local connection-status join and current
  permission filtering. Publish read-safe statuses, never encrypted/plain secrets.
- [ ] Derive fallback from installed Registry credential capabilities; exclude
  uninstalled/unsupported adapters. Preserve tenant-over-platform precedence.
- [x] Parse directory 429 Retry-After (seconds or HTTP date) without exposing
  upstream bodies, and suppress additional upstream queries/categories for the
  origin during the bounded cooldown. Invalid/missing headers default to 60 seconds;
  untrusted delays cap at 24 hours. Valid cached pages remain readable. Red/green
  transport/cache regressions and 14 focused cache/lifecycle tests pass; rendered recovery and
  broader release acceptance remain pending.
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

- [x] Add tenant MCP secret envelopes using the existing installation keyring,
  with separate authenticated identity and bounded JSON payloads.
- [x] Validate static authentication and initialize/discover using isolated,
  bounded transient clients without tool invocation. Caller/deadline cancellation,
  log redaction and explicit session cleanup are covered by focused fixtures; see
  [the check design](../../docs/development/mcp-connection-checks.md).
- [x] Add the trusted tenant connection repository, durable UUID/namespace,
  encrypted records, generation-checked replacement/revocation, public metadata
  and catalog refresh, and bounded atomic re-encryption. Distinct database clients
  verify deterministic duplicate and stale-generation outcomes; authorization and
  public reconnect remain separate tasks.
- [ ] Add persistence migrations for tenant connection identity/config generation,
  encrypted auth material and catalog snapshots, using the existing encryption
  keyring with explicit MCP identity binding and rotation participation.
- [x] Add authorized custom-static Calls operations and Console session/CSRF APIs,
  including discovery, masked replacement, catalog-only refresh and explicit
  retained-identity reconnect. Real HTTP/PostgreSQL/local-MCP acceptance passes;
  production modal and listed-template identity remain separate tasks. See
  [the management contract](../../docs/development/tenant-mcp-management.md).
- [ ] Complete listed-connection identity and remaining management acceptance.
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

### T4a — Credentialless discovery foundation

- [x] Add bounded protected-resource and OAuth/OIDC metadata discovery, strict
  retained-field validation, explicit issuer choice and anonymous initialization
  through the existing transient checker. Manual issuer fallback applies only
  to missing resource metadata and suggests Own-client.
- [x] Supervise preflight admission, frequency and whole-operation lifetime;
  retire nested I/O on caller death, expiry and runner restart. Composed lifecycle
  and late-result tests pass. See [discovery design](../../docs/development/mcp-discovery.md).
- [ ] Expose current-authority, session/CSRF-protected Console discovery and wire
  URL edits, revision fencing, retries and field prefills into the production UI.
  The static management checkpoint exposes this API; production modal acceptance remains open.

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

### Implementation and review fixes

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
- [ ] Wire retained-identity reconnect into the production modal and delegated
  OAuth attempts; keep full workflow acceptance open until those cases pass.

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

- [x] Extend MCP cipher boundary evidence after adversarial review: key-ID aliases
  with identical key material, provider/MCP envelope substitution, exact plaintext
  size, oversized/unsupported envelopes and encoding-error normalization. Verify
  oversized data is rejected before key lookup. Keep
  this checkpoint separate from record authorization and OAuth lifecycle claims.
  All seven focused tests pass; see the
  [cipher checkpoint](../20261106-2345-review-mcp-cipher.md).

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

## Specification review (separate from implementation)

Local design/dependency review, 2026-10-25: directory browsing can ship before OAuth;
T4 enables static MCPs without depending on remote availability; T5 requires T4 and
Console identity; T7 must replace every tenant fallback seam, not only inventory.
Native API definitions are an external dependency. Advanced JWT/client credentials
need their own interop gate. A successful empty response is not an outage. These
are reviewed contracts and proposed gates, **not implemented backend features**.

User review remains open. Rendered/prototype evidence is recorded in the
[checkpoint labnotes](../20261025-1834-integrations-directory-proposal.md).
