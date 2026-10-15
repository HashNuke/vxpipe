# Platform MCP plan

Task: plan one `/mcp` endpoint, authenticated by Settings-created platform API
keys, with the same authority as existing APIs. Produce checkpoints and a
capability inventory for user review before implementation.

## Findings and decisions

- Started from a clean `main` at `8e52d5b4`. This task only adds/updates planning
  documentation; earlier commit/push requests concerned the completed Morse work.
- Inspected Gateway routes/handlers, Console routes/mount/host guards, Calls
  authentication/authoring/admission and Settings key issuance, Persistence key
  lookup/schema, and the pinned ExMCP public server Plug.
- Existing `vxpipe_mcp` is outbound. Propose ExMCP server integration in Gateway,
  preserving Calls/Persistence dependency direction and reusing the locked package.
- Settings platform keys already establish tenant-bound admin/calls authority;
  installation authority must still be retained for platform-service authoring.
  Legacy operator keys are not equivalent on tenant admission endpoints.
- The current machine surface maps to nine named tools. Console call/spec reads,
  services, tenants, key management and identity administration use browser-user
  policy and need an explicit shared API extension if included. Asked the user
  whether to include those operations; the draft keeps the boundary visible and
  does not silently treat the limited catalog as full Console coverage.
- Initialization needs a tenant-independent digest lookup. Existing uniqueness is
  tenant-scoped, so the plan requires bounded indexed lookup and ambiguity rejection
  rather than guessing a tenant or rotating existing keys.
- Reauthenticate each request; filter discovery and also authorize invocation.
  Preserve outgoing idempotency, no automatic mutation retries, and deliberate
  join-token output without credential logging.
- Read official MCP 2025-11-25 transport/lifecycle/tools/authorization documents.
  Static API keys remain the requested contract; OAuth-only client compatibility
  is not promised. The pinned ExMCP client evidence is not inbound-server proof.

## Artifacts and review

- `docs/platform-mcp.md`: decisions, HTTP/tool inventory, key matrix, explicit
  Console-only candidates, ownership, protocol profile and rejected alternatives.
- `labnotes/milestones/platform-mcp-endpoint.md`: six dependent checkpoints with
  Markdown tasks and local acceptance criteria. Implementation remains unchecked.
- Updated milestone index counts/order and linked the plan from API-key docs.
- Local design review checked tenantless auth, revocation, request/session
  isolation, platform-service authoring, secrets, replay/outcome semantics and
  prerequisite order. No independent-agent or implementation review is claimed.

## Verification

Documentation-only verification passed: all relative links/anchors in the new
decision/milestone and updated key guide resolve; the inventory contains nine
tools; the index has 51 ordered entries (39 complete, 12 incomplete); all 43
implementation tasks across six checkpoints remain unchecked. `git diff --check`
passes, and the changed paths contain only the requested planning artifacts.
No application changes, build, live-provider tests, real calls or deployments ran.

At the original plan handoff, the optional scope question remained open. The
initial proposal used existing API-key endpoints and presented Console-only
additions explicitly for review. The user's subsequent workflow list resolves
that scope question as recorded below.

## User-selected workflow expansion

The user requested 13 operations: tenant list/info; spec list/get/create/update;
call create/join-token/hangup; user list/create/update/disable. All lists paginate,
call creation must accept initial variables, and user updates must support activation.

- Rewrote the decision and milestone around this scope, replacing the nine-tool
  release boundary. Added seven implementation checkpoints and matching REST
  extensions; new read/user/hangup workflows are required, not deferred.
- Spec updates take an explicit public spec ID; call creation resolves and pins a
  published spec by ID. Initial `variables` remain typed call state and must arrive
  unchanged at runtime. Incoming web creation prepares; outgoing creation submits
  a dial. Optional idempotency has explicit retry/failure contracts.
- Join tokens default to the pinned web entry participant, with an optional explicit
  selector and a clear error when no eligible default exists. Hangup requires
  ownership/incarnation validation, admission cancellation interlocks and normal
  whole-call cleanup, not a database-only state update.
- Inspected Identity.Accounts, Authorization, IdentityRecord and IdentityUserStore.
  Current writes require an actual browser actor/session and audit attribution.
  Plan an explicit platform-key actor, transactional key revalidation and key audit
  attribution, preserving privileged-account/last-Superadmin and browser guards.
- User update omission preserves enabled/role/membership fields; enabled=true
  reactivates, disable revokes sessions, and reactivation cannot revive old sessions.
- Pagination follows existing page-based directory conventions: default 25, maximum
  50, stable ordering, bounded queries and authorization before counts/pages.
- Retain four supporting tools for explicit publication, provider/model discovery
  and role-ID discovery. No role editing, key issuance or services expansion is implied.
- Recommended requiring public tenant_id on every tenant-specific operation for a
  consistent agent interface and explicit target selection. It must match a tenant
  key and every resource's ownership; installation users/roles remain unscoped.
- Refined signatures and the explicit machine user-management policy remain design
  proposals for review. No implementation or runtime verification is claimed.
- Follow-up documentation checks pass: exactly 13 required tools, seven checkpoints,
  52 unchecked implementation tasks, valid relative links/anchors, unchanged correct
  index totals (51/39/12), and `git diff --check`. No live-provider tests ran.

## Identifier recommendation and expanded arguments

The user asked whether to use tenant_key or tenant_id and clarified that earlier
function signatures were examples to expand. Verified the current Ecto tenant
schema, original migration, PublicId generator and Console tenant projection:
tenants has an internal primary key plus a unique generated 16-character key.

- Recommend `tenant_key` consistently for MCP/new public API arguments, responses
  and membership entries, reserving tenant_id for internal database relations.
  This supersedes the earlier proposed public tenant_id alias. No new tenant
  identifier or tenant data migration is needed; old REST/Console field names
  remain compatible through boundary projections.
- Recommend `get_tenant` for the tenant-info operation to match get_call_spec.
- Added concrete required/optional types, defaults, accepted ranges, update
  semantics and output shapes for all required tools and supporting helpers.
- Spec update is full source replacement in a new revision, with the target ID
  separate. User update is partial, preserving omitted fields; memberships replace
  only when supplied. Passwords are creation-only inputs, never output.
- Initial variables use the existing `variables` field and validation; destination
  and idempotency are separate typed arguments. Join-token selector/TTL/expiry are
  explicit. All product lists share one pagination contract.
- No implementation, credential access, live testing or deployment was performed.
- Documentation verification passes: 13 required tool signatures, seven checkpoints,
  53 unchecked implementation tasks, valid links/anchors and index counts, and
  `git diff --check`.

## Shared application layer and one HTTP API

The user requires an underlying Elixir API shared by HTTP and MCP, and clarified
that the documented public HTTP API must be the API used by the UI. The browser
authenticates with its login session, not an API key. External HTTP clients and
MCP authenticate with API keys. A few explicitly UI-specific helpers are allowed.

- Inspected Console's spec controller, RequireUserAPI/RoutePermission and
  UserIdentity composition alongside Gateway's spec-write handler and Calls facade.
  Some domain operations are already shared, but routes/controllers and Identity
  dependency wiring are not yet one canonical product API.
- Added a shared application/HTTP architecture section and diagram. Focused public
  functions remain in their existing Calls/Identity/Gateway workflow owners; there
  is no new generic dispatch framework or automatic new umbrella application.
- Added a first vertical checkpoint for a canonical HTTP operation used by both UI
  and key clients, and a UI cutover checkpoint before final acceptance (nine total).
  Inventory all UI business requests, including services/roles/key management;
  these HTTP consolidation requirements do not expand the reviewed MCP catalog.
- Browser sessions retain CSRF/origin protections. Configured authentication adapters
  prevent Gateway depending on Console. Explicit Authorization selects key auth
  without cookie fallback or grant union; MCP stays key-only. Direct Elixir calls
  must also pass shared operation authorization.
- Public schemas/handlers serve UI and external HTTP callers alike. Existing
  published fields remain compatible; legacy admin aliases only translate during
  migration and cannot retain separate business rules. UI-only helpers are few,
  classified and composed from the same authorized operations.
- Account composition moves out of Console-only ownership; machine/user actors
  preserve actual provenance and transaction-time policy/audit checks.
- Acceptance now compares direct Elixir, session HTTP, key HTTP and MCP, plus
  rendered browser/network evidence that the UI uses documented routes. Frontend
  type/build/tests and browser checks are part of implementation acceptance.
- Documentation checks pass: valid relative links/anchors, 13 required tools,
  nine checkpoints with 68 unchecked implementation tasks, consistent milestone
  counts and `git diff --check`. No runtime/UI changes or live tests were made.

## MCP authentication recommendation

- Reviewed the official MCP 2025-11-25 authorization profile and current Claude
  Code/VS Code remote-client documentation linked in the design. Used the
  security-audit skill in focused guidance mode; no broad audit or runtime probes.
- MCP recommends an OAuth-based authorization profile for HTTP interoperability.
  A static Settings key in a configured Bearer header is practical for clients
  supporting headers, but does not provide OAuth discovery, consent or token flows.
- Kept the requested API-key scope and existing application authority. Added an
  explicit wire contract, per-request credentials, session/key separation, error
  statuses and secret-reference client setup. No API-key argument, login tool,
  cookie fallback, fabricated metadata or custom token-exchange feature is planned.
- Documented OAuth-only clients as a compatibility limitation. Broader support
  would need an explicit OAuth integration with the same authorization boundary;
  current client documentation is not runtime interoperability evidence.
- Added one unchecked foundation task and expanded local acceptance for missing
  credentials after initialization, malformed credentials, revocation and scope
  denials. All implementation tasks remain unchecked; no live tests were run.
- Documentation verification passed: local links/anchors, JSON example syntax,
  nine checkpoints with 69 unchecked tasks, milestone index order/counts and
  `git diff --check`. No application implementation or runtime testing occurred.
