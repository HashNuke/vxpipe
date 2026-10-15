# Platform MCP endpoint

Status: implementation authorized and started on 2026-10-15. The user approved
the milestone, incremental commits, subagent reviews and pushnotify updates.

## Runnable outcome

A user connects to `/mcp` using a Settings-created Vxpipe API key, lists authorized
tenants, reads/authors/publishes call specs, creates a call with initial variables,
obtains a participant join token, and hangs up the call. Full Platform Access keys
also list/create/update/activate/disable users. All list operations paginate.
The UI and external clients use one documented HTTP API, backed by shared Elixir
application operations also called directly by MCP. Session/key authentication
establishes actor identity; shared policy owns authorization and behavior.

This expands the earlier nine-tool proposal. Tenant/spec reads, hangup and user
management are required work, even where machine endpoints do not exist yet.
Implementation tasks remain unchecked until their acceptance evidence is recorded.

## Prerequisites and sources

- [Tenant Call Specs and API-key administration](tenant-call-specs-and-api-keys.md):
  completed scoped keys, immutable revisions and repository boundaries.
- [Settings API-key management](console-sidebar-and-dashboard.md#settings-api-key-management):
  completed key issuance, scopes, delegation ceilings and revocation.
- [Platform and tenant services](platform-and-tenant-services.md): completed service
  ownership/authoring rules; unfinished bootstrap/onboarding is not a prerequisite.
- [Console authentication and user management](console-authentication-and-user-management.md):
  completed identity policy, protected accounts and transaction/session safeguards.
- [MCP client integration](mcp-client-library.md): pinned ExMCP dependency/profile;
  outbound acceptance does not establish server acceptance.
- [Platform MCP design](../../docs/platform-mcp.md): authoritative tool/argument,
  pagination, key matrix, proposed REST routes and call/user behavior contracts.
- [API-key access](../../docs/api-key-access.md),
  [HTTP authoring/admission](../../docs/operator-api-key-authoring.md), and
  [identity policy](../../docs/console-authentication-and-authorization.md).
- Primary MCP transport/lifecycle/tools/authorization specifications linked in the
  design document; propose the existing `2025-11-25` profile pending the local probe.

## Required capabilities

| Group | Required tools |
| --- | --- |
| Tenants | `list_tenants`, `get_tenant` |
| Call specs | `list_call_specs`, `get_call_spec`, `create_call_spec`, `update_call_spec` |
| Calls | `create_call`, `create_join_token`, `hangup_call` |
| Users | `list_users`, `create_user`, `update_user`, `disable_user` |

These are 13 required tools. Supporting workflow tools are
`publish_call_spec_revision`, `list_providers`, `list_provider_models`, and
`list_role_options`. Publication remains explicit; role options expose identifiers
without role editing. Product list tools use page/page_size, including these helpers.
Every tenant-specific tool requires the public `tenant_key`; authentication checks
key/tenant/resource agreement. Tenant discovery and installation-wide user/role
operations do not take a tenant argument. No session-selected tenant is implied.

- [x] Incorporate the user's tenant/spec/call/user workflow list and pagination.
- [x] Make initial variables part of `create_call`, not optional implementation scope.
- [x] Include activation through `update_user(enabled: true)` and explicit disable.
- [x] Incorporate one shared Elixir application API and one documented product HTTP
  API used by both the UI and external clients, with bounded UI-specific helpers.
- [x] Preserve browser login-session authentication; API keys are for external HTTP
  and MCP callers. The UI does not need to create, store or send a machine key.
- [x] User authorized implementation of the concrete signatures, publication/default-
  participant behavior and Full Platform Access account authority (2026-10-15).

## Checkpoint: shared Elixir application API and canonical HTTP contract

Runnable slice: one existing spec-authoring operation is served through a canonical
documented HTTP handler used by the UI and an API-key client; both invoke the same
public Elixir operation with their actual authenticated actor.

- [x] Inventory current UI HTTP requests and machine routes. Classify every route
  as canonical product API, browser authentication/UI helper, or temporary legacy
  alias. Include services, roles and key management even though they are not MCP
  tools. Record canonical route, owner, schema, credential policy and migration.
  Evidence: [complete route inventory](../../docs/product-api-inventory.md), reviewed
  against Console/Gateway routes and frontend fetch modules. Non-MCP machine grants
  remain default-deny until explicitly defined; inventory is not route migration.
- [ ] Select existing Calls/Identity/application functions as the shared operation
  boundaries; extract controller-owned business checks/projections where necessary.
  Keep functions domain-focused, not a generic dispatcher or unnecessary new app.
- [ ] Define trusted actor/input/result/error contracts. Shared functions enforce
  authorization, tenant scope, validation, pagination, transactions, idempotency
  and lifecycle behavior even when called without an HTTP/MCP adapter.
- [x] Move reusable Identity dependency composition out of Console-only wiring;
  preserve umbrella direction through ports and owning-child dependencies. Keep
  runtime orchestration in transport-neutral Gateway application modules.
  Evidence: `Vxpipe.Identity.dependencies/0`, runtime config under `:vxpipe_identity`,
  Console delegation; red then 61 Identity and eight Console tests passing, reviewed.
- [ ] Define one HTTP handler/schema per product operation under `/api`, retaining
  compatible published contracts. UI and external clients receive the same wire
  contract. Legacy `/admin/api` aliases may translate formats but cannot own policy.
- [ ] Add configured authentication adapters: browser sessions with CSRF/origin
  protection, API-key Bearer for external requests, Bearer-only standalone hosting.
  Explicit Authorization never falls back to session authority; grants never union.
- [ ] Red-test and migrate one existing spec-write flow end to end: direct Elixir,
  browser HTTP and API-key HTTP have equivalent behavior for equivalent authority.
  Direct application calls and invalid/missing CSRF or revoked credentials deny.
- [ ] Acceptance: local browser/network inspection shows that UI flow using the
  documented canonical route and response; a synthetic API-key request uses the
  same handler. No platform key is embedded in or issued just for the browser UI.

First slice evidence (2026-10-15): canonical spec writes now share one Gateway
handler for browser sessions and keys. The editor uses `/api` for create/update/
publish; existing metadata responses are preserved. Fourteen Console endpoint
tests pass, including session/key writes, CSRF, invalid-header precedence and
restricted-user 403. Five frontend adapter tests and TypeScript/build pass.
Rendered Chrome inspection at desktop and 390px mobile verified a draft save to
`PUT /api/tenants/:tenant_key/call-specs/:id` returning 201/revision 2, using a
local sandbox database and fake login identity. This does not complete the shared
checkpoint: legacy adapters, full platform-service parity, all shared operation
contracts and final gates remain outstanding.

## Checkpoint: authenticated MCP foundation

Runnable slice: a local client initializes `/mcp` using a real locally issued
Settings key, calls ping and obtains an authorized tool catalog. Domain tools are
advertised only as their checkpoints become usable.
Depends on the shared application/HTTP contract. MCP invokes its public operations
directly, without an HTTP loopback request or controller invocation.

- [x] Red-test the pinned public ExMCP Plug/handler boundary in Gateway; add the
  direct owning-child dependency using the shared lock. Keep outbound `vxpipe_mcp`
  independent of Calls/Gateway and preserve its existing tests.
  Evidence: three public-boundary probe tests failed without the handler, then
  passed. Direct Gateway dependency uses the existing shared lock unchanged.
- [x] Prove `2025-11-25` negotiation, initialized notification, ping, JSON results,
  request IDs and unsupported versions/methods. GET returns 405 without an
  unsolicited SSE stream; do not implement unrelated protocol extensions.
- [ ] Resolve the dependency's session behavior before product handlers: bind any
  issued sessions to authenticated key identity, bound their count/lifetime, and
  verify DELETE/expiry/restart and timeout/disconnect cleanup truthfully.
- [x] Add Calls-owned tenant-independent key authentication through a Persistence
  port: bounded indexed digest lookup, ambiguity rejection, stored scopes and
  revocation. No tenant scan, forced key rotation or client-asserted authority.
  Evidence: `Calls.authenticate_api_key/2`, bounded indexed digest lookup including
  revoked duplicates, Settings-platform/legacy provenance, 26 focused Calls and
  11 Persistence tests passing after red tests and the additive index migration.
- [x] Authenticate every HTTP request from one Bearer header. Reject absent,
  invalid/revoked keys and fail closed on unavailable storage. No query/body keys
  or browser-cookie substitute; never retain raw keys in session/process state.
- [ ] Implement the [authentication wire contract](../../docs/platform-mcp.md#authentication-contract-and-client-compatibility):
  400 for malformed/duplicate credentials, 401 with Bearer challenge for missing
  or invalid keys, 403 for insufficient authority, and 503 for unavailable key
  storage. No OAuth metadata/login redirects or fabricated token exchange.
- [x] Mount exact `/mcp` through Gateway and Console before generic parsers; keep
  embedded enablement explicit, app/carrier host separation, HTTPS/loopback rules,
  host/origin checks, no-store responses and bounded work/body/deadline limits.
- [ ] Implement the shared operation/key policy from the design matrix. Filter
  discovery and independently check invocation; isolate concurrent principals.
- [ ] Define schemas, structured/text results, public error mapping, annotations,
  sanitized telemetry and no automatic mutation retries. Document concrete limits.
- [ ] Implement the [argument/result contracts](../../docs/platform-mcp.md#argument-and-result-details)
  as per-tool schemas: required fields, typed defaults, null handling and safe
  projections. Public tenant arguments/memberships use `tenant_key`, not the
  internal `tenant_id`; preserve existing REST/Console wire shapes at adapters.
- [ ] Acceptance: local wire tests cover initialization, invalid headers, revoked
  sessions, wrong-key session reuse, disabled configuration and zero secret leakage.
  Include notifications/discovery/invocation without a repeated credential, a
  session ID without a key, cookie/query/body-only credentials and scope denials.

Probe evidence (2026-10-15): the pinned Plug creates in-memory sessions for
`2025-11-25`. Tests prove selected-version initialization, notifications, ping,
empty tool discovery, trusted per-request actor injection, wrong-key session 404,
DELETE 204/subsequent 404 and monitored handler-timeout cleanup. Independent review
found no blockers in the probe. The product boundary now passes 21 Gateway probe,
endpoint and mount tests plus two Console tests with real locally issued keys.
It enforces version/method rules, per-request authentication, exact/prefixed mounts,
host/origin/transport restrictions and bounded concurrent requests. Review found
oversized retained request IDs and incorrect unknown-notification responses; both
failed focused tests before fixes. IDs are limited to 256-byte strings or safe
integers and rejected IDs are not echoed; notifications have no JSON-RPC body.
Domain tools, complete scope/error acceptance and session expiry/restart evidence
remain open. A dependency timeout/crash logging issue must be fixed before tools
accept sensitive inputs or produce sensitive results.
Handler cleanup may add approximately one second to the configured deadline.

## Checkpoint: tenant discovery and shared pagination

Depends on the authenticated foundation. Runnable slice: list tenants and inspect
one tenant through REST and MCP; a tenant key sees only its own tenant.

- [ ] Red-test `list_tenants` and `get_tenant` for calls/full/platform keys.
- [ ] Extend Calls directory/read authorization for machine principals; expose
  `GET /api/tenants` and `GET /api/tenants/:tenant_key` through shared workflows.
- [ ] Project `{tenant_key, name}` list entries and safe tenant info. Use the existing public
  `tenant_key` consistently; never expose internal database IDs or service secrets.
- [ ] Implement the shared list envelope: items plus page/page_size/total/total_pages;
  default page 1, size 25, allowed size 1–50, stable ordering with ID tie-breaker.
- [ ] Scope before counting/paging. Reject invalid/out-of-range pages; empty first
  page has zero totals. Use bounded database queries, not post-fetch filtering.
- [ ] Acceptance: multi-page visible/foreign fixtures, zero rows, exact page boundary,
  invalid sizes and duplicate sort values agree across REST/MCP without count leaks.

## Checkpoint: call-spec discovery and authoring

Depends on tenant discovery. Runnable slice: list/get a tenant's specs, discover
models, save a draft, append a revision and explicitly publish it locally.

- [ ] Red-test required list/get/create/update and supporting publish/catalog tools.
- [ ] Extend principal-aware spec reads to tenant admin and Settings platform keys;
  add the missing machine GET routes. Calls-only keys cannot read portable source.
- [ ] Paginate spec summaries and provider/model helpers with the shared envelope;
  preserve existing catalog REST response shape when pagination is not requested.
- [ ] Implement get by public ID and optional revision, returning portable source
  and latest/published revision metadata only. No compiled plans/resolved secrets.
- [ ] Map `call_spec_definition` to source; updates require `call_spec_id` and append
  immutable revisions. Preserve server-generated IDs, validation, size limits,
  revision conflict and foreign-ID errors. Update cannot create a missing spec.
- [ ] Keep publication explicit. Preserve transaction-time complete-source ownership
  checks, especially tenant edits of platform-service-backed definitions.
- [ ] Acceptance: REST/MCP produce equivalent revisions and denials; new draft
  creation/update never publishes or starts a call. Local catalog performs no paid
  provider calls. Supporting tools have the same authorization as their operations.

## Checkpoint: create calls with variables and issue join tokens

Depends on spec authoring. Runnable slice: create a call by published spec ID with
initial variables, receive `{call_id}`, then issue/redeem its token locally.

- [ ] Red-test `create_call(tenant_key, call_spec_id, ...)` for web and outgoing specs.
- [ ] Share the create workflow with the existing spec-scoped REST call endpoint:
  pin one published revision, prepare web calls, or submit outgoing calls. Existing
  REST clients keep their response shape; MCP returns the minimal `{call_id}`.
- [ ] Validate and persist nested `variables` under the existing declared-section,
  type and access rules before admission/dialing. Verify exact values arrive in
  the runtime; omission preserves defaults. Reject invalid variables before effects.
- [ ] Resolve web entry from the published spec without a caller-supplied route;
  carrier-only incoming specs return unsupported-entry, not a synthetic webhook.
  Web preparation is not live audio; outgoing acknowledgement is not an answer.
- [ ] Preserve outgoing `to` validation and failed/unknown submission behavior.
  Extend optional tenant-wide `idempotency_key` claim/replay to prepared creation;
  same-key retry returns the same call, changed input conflicts, failed replay
  never admits/dials again. Requests without a key remain separate attempts.
- [ ] Implement `create_join_token` with optional participant_key and existing TTL
  limits. Default only to a suitable pinned web entry; require a selector when
  there is no eligible default. Return token, expiry and resolved participant key.
- [ ] Add the shared non-participant-scoped token HTTP route; preserve the existing
  participant route. Validate eligibility against this call, not the latest spec.
- [ ] Acceptance: nested-variable and invalid-variable cases, concurrent publication,
  duplicate create/replay, wrong tenant/spec/call/participant, TTL/single-use and
  ended-call denial pass with local Morse/fixtures and a fake dial adapter. Token
  values never enter logs, telemetry or audit; no live providers/real calls run.

## Checkpoint: authorized whole-call hangup

Depends on call creation. Runnable slice: hang up a prepared, admitting, ringing or
running local call through REST/MCP and observe its owned resources terminate.

- [ ] Red-test `hangup_call` with tenant ownership and calls-scope requirements,
  including denial before runtime lookup and repeated termination.
- [ ] Add a shared application workflow and `POST /api/tenants/:tenant_key/calls/:id/hangup`.
  Resolve room/incarnation server-side; do not expose unscoped engine termination.
- [ ] Handle prepared calls durably and prevent token issue/redemption afterwards.
  Interlock cancellation with admission so a concurrent join/start cannot resurrect
  a cancelled call. Preserve truthful terminal/unknown states through restart.
- [ ] Request live shutdown from the exact owner/incarnation, with an API-requested
  reason. Release participant sessions, all carrier legs and owned workers through
  the normal lifecycle; keep usage/archive completion intact.
- [ ] Return `ending` on durable acceptance and `ended` only with evidence. Already
  terminal calls are repeat-safe; missing runtime without terminal evidence is a
  bounded unavailable/unknown outcome. Never terminate a replacement incarnation.
- [ ] Acceptance: local barriers/monitors prove hangup-versus-admission/dial races,
  retry, stale incarnation, crash/restart, foreign IDs and resource cleanup without
  arbitrary sleeps or real telephony. Add/run relevant Lean verification if the
  implementation changes modeled source/speech transitions.

## Checkpoint: platform-key user administration

Depends on foundation and pagination; does not require live calls. Runnable slice:
a Settings platform key lists/creates a user, disables them, then reactivates them.

- [ ] Red-test required user tools plus paginated safe `list_role_options`.
- [ ] Add an explicit machine actor carrying verified API key ID to the shared
  Identity policy/ports and persistence transaction checks. Keep browser actor/session
  checks intact; never fabricate a user/session or trust tool-supplied grants.
- [ ] Implement the design's Full Platform Access policy for users.read and existing
  member/admin/superadmin write categories. Tenant keys and legacy operator keys
  do not inherit these new installation-wide privileges.
- [ ] Add corresponding `/api/users` GET/POST, `/api/users/:id` PATCH,
  `/api/users/:id/disable` POST and `/api/role-options` GET routes. Both transports
  invoke the same Identity workflow/configuration; Gateway never calls Console.
  Declare any direct Identity use in the owning child dependency list.
- [ ] Revalidate machine key inside account-write transactions and attribute audit
  to its key ID. Add the minimal schema/port changes needed for machine audit actors;
  existing user audit history remains valid and credentials stay redacted.
- [ ] Preserve target/current/requested role-category checks, membership validation,
  password hashing/confirmation, duplicate-email handling and last-enabled-Superadmin
  protection, including concurrent demotion/disable and revocation races.
- [ ] Implement partial updates: omitted enabled/role/memberships remain unchanged;
  `enabled: true` activates, false disables. `disable_user` uses the same workflow,
  is repeat-safe and revokes user sessions without hard deletion. Reactivation must
  not revive revoked sessions; independent API keys keep their existing lifecycle.
- [ ] Paginate/filter user and role-option lists with safe projections. Passwords
  are creation inputs only and never returned, audited or logged. No implicit
  password-reset or role-administration tools.
- [ ] Acceptance: platform/tenant denials, create/disable/reactivate/login outcomes,
  partial-field preservation, privileged targets, concurrency, key revocation,
  audit attribution and pagination agree between REST/MCP using synthetic accounts.

## Checkpoint: UI cutover to the documented product API

Depends on the implemented shared operations. Runnable slice: the Console uses the
documented product endpoints for its business operations; only the explicitly
inventoried session/navigation/authentication helpers remain UI-specific.

- [ ] Migrate UI callers, TypeScript response parsing, fixtures and focused tests
  to canonical routes and shared schemas. Do not leave UI/public controllers with
  parallel implementations of tenant/spec/call/user actions.
- [ ] Complete the inventory for remaining existing UI product operations, including
  services, roles and key management: one canonical handler per operation, explicit
  key/session policy preserving current delegation/privileged-account safeguards,
  and user-facing HTTP documentation. Do not quietly classify writes as UI helpers
  to avoid consolidation or assume all actor types share all permissions.
- [ ] Keep UI helpers few and compositional; helpers reuse authorized application
  reads. Record their purpose/credential contract and do not add a second write API.
- [ ] Retain needed legacy routes as thin compatibility aliases with a documented
  migration/deprecation policy; retire duplicate controllers and unused policy maps
  once no consumer needs them. Preserve already published external contracts.
- [ ] Maintain one canonical HTTP schema/documentation source, using existing
  tooling where available; verify UI client and documented examples agree with it.
  MCP schemas/results adapt the same operation contracts without new business rules.
- [ ] Acceptance: rendered desktop/mobile flows plus network inspection show the UI
  using documented endpoints; synthetic session/key requests exercise the same
  handlers. Verify changed frontend types/tests/build and no credential exposure.

## Checkpoint: parity acceptance and documentation

Depends on all required capability checkpoints and supporting workflows.

- [ ] Run a local reference client against the actual Console mount, standalone
  Gateway and embedding prefix. Pin server-conformance tools and report applicable
  passes/omissions rather than using outbound acceptance as inbound proof.
- [ ] Verify all 13 required tools and four helpers against the authority matrix,
  including direct calls to undiscovered tools, revoked keys, unavailable storage,
  foreign resources, variable initialization, pagination, hangup and user activation.
- [ ] Verify direct Elixir, UI session HTTP, external key HTTP and MCP parity for
  each shared capability, comparing equivalent authority and expected differences
  for restricted roles/key scopes. Confirm documented HTTP endpoints are the ones
  exercised by UI network traffic, not merely similarly named domain functions.
- [ ] Exercise bounded concurrency/session cleanup, malformed/oversized requests,
  slow clients and log redaction, including passwords and join tokens.
- [ ] Document client connection via static Bearer headers, signatures, public IDs,
  all pagination shapes, prepare-versus-dial behavior, explicit publication,
  variable examples, default participant rules, activation and retry semantics.
  Explain OAuth-only client limitations without adding OAuth to this milestone.
  Include secret-reference client configuration and verify it with a local client;
  never describe static API keys as full MCP OAuth authorization conformance.
- [ ] Run the five common root gates, changed frontend tests/types/build, rendered
  browser verification and relevant model verification for lifecycle changes.
- [ ] Use only local PostgreSQL, synthetic accounts/keys, Morse/fixture providers and
  fake carrier adapters. No live-provider tests, external telephony or deployments.
- [ ] Update evidence/index only when every requested capability passes; do not mark
  completion for just the original nine tools. Commit only when authorized.

## Specification review

- [x] Original local review inspected key authentication, tenantless MCP initialization,
  ExMCP ownership, revocation, scoped authoring and mount order (2026-10-15).
- [x] Follow-up review incorporated the user's broader workflow scope: 13 required
  tools plus four supporting helpers, page-based lists, public ID mapping, update
  target identity, pinned participant defaults and preserved initial variables.
- [x] Identified substantive shared API work: machine-authorized reads, create-by-spec
  web preparation, whole-call hangup and explicit machine Identity/audit actors.
- [x] Expanded the user's pseudocode into typed arguments/defaults/results, using
  `tenant_key` consistently and `get_tenant` alongside `get_call_spec`. Checked
  identifiers against the current tenant schema/routes and retained compatibility
  for existing REST/Console response fields.
- [x] Checked missing lifecycle contracts: publication race, repeated create/dial,
  token eligibility, admitting-call cancellation, stale incarnation, partial account
  updates, transaction-time key revocation and last-Superadmin protection.
- [x] Checked dependency order and local-only acceptance. User management depends on
  foundation/pagination and Identity, not call runtime. Delivery/onboarding stays
  independent. Revised index/decision and preserved unchecked implementation tasks.
- [x] Incorporated the explicit shared-layer decision: canonical application/HTTP
  slice first, MCP adapter next, domain workflows and UI cutover before final parity.
  Reviewed actor provenance, session CSRF, Bearer precedence, direct-call policy,
  Identity dependency direction, legacy aliases and one HTTP schema source.
- [x] Reviewed official MCP authorization and client configuration documentation.
  Selected configured Bearer headers for the requested Settings-key scope, with
  explicit OAuth-only client limitations, per-request authentication and error
  contracts. OAuth is the interoperable standard path and remains separate work.
- [x] User authorized implementation of the refined signatures/policy (2026-10-15).
- [ ] Implementation and all acceptance gates completed.

Independent subagent planning review (2026-10-15) confirmed dependency direction
and scope. Clarified HTTP key-scope denials versus resource/domain tool errors and
recorded implementation authorization. Runtime acceptance remains outstanding.
