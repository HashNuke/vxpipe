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
- [x] Red-test and migrate one existing spec-write flow end to end: direct Elixir,
  browser HTTP and API-key HTTP have equivalent behavior for equivalent authority.
  Direct application calls and invalid/missing CSRF or revoked credentials deny.
- [x] Acceptance: local browser/network inspection shows that UI flow using the
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
- [x] Resolve the dependency's session behavior before product handlers: bind any
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
- [x] Implement the [authentication wire contract](../../docs/platform-mcp.md#authentication-contract-and-client-compatibility):
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
Remaining domain tools and complete scope/error acceptance remain open. The
isolated reference-client runner now verifies DELETE, accelerated expiry, full
BEAM restart on the same port and fresh recovery. Request-owner death/timeout
cleanup has focused tests; immediate TCP-disconnect cancellation is not claimed.
Dependency diagnostics are now pinned to reviewed upstream commit
`5fa760207bb09fc3b19b3049bc481b5e55106095`, which removes raw timeout/error details
without changing callback or supervision semantics. Application callback fault
handling remains Vxpipe's responsibility before sensitive tools are enabled.
Handler cleanup may add approximately one second to the configured deadline.

## Checkpoint: tenant discovery and shared pagination

Depends on the authenticated foundation. Runnable slice: list tenants and inspect
one tenant through REST and MCP; a tenant key sees only its own tenant.

- [x] Red-test `list_tenants` and `get_tenant` for calls/full/platform keys.
- [x] Extend Calls directory/read authorization for machine principals; expose
  `GET /api/tenants` and `GET /api/tenants/:tenant_key` through shared workflows.
  Domain prerequisite implemented and independently reviewed: tenant calls/full
  keys use an assigned one-tenant scope; Settings platform keys use all tenants.
  Browser directory/visibility rules and scoped repository count/paging remain.
  Canonical HTTP and MCP now call those operations and share public JSON projection.
- [x] Project `{tenant_key, name, created_at}` list entries and safe tenant info. Use the existing public
  `tenant_key` consistently; never expose internal database IDs or service secrets.
- [x] Implement the shared list envelope: items plus page/page_size/total/total_pages;
  default page 1, size 25, allowed size 1–50, stable ordering with ID tie-breaker.
- [x] Scope before counting/paging. Reject invalid/out-of-range pages; empty first
  page has zero totals. Use bounded database queries, not post-fetch filtering.
- [x] Acceptance: multi-page visible/foreign fixtures, zero rows, exact page boundary,
  invalid sizes and duplicate sort values agree across REST/MCP without count leaks.

Evidence: six focused MCP tool tests cover scope, schemas/defaults, metadata,
safe callback errors and rejected tool-name telemetry. Four Console MCP tests
exercise persisted keys/revocation and HTTP/MCP parity for calls/full/platform
keys, duplicate-name ordering, page boundaries, foreign lookup and empty results.
Canonical HTTP focused selection passes 39 Gateway tests; existing browser tenant
and spec endpoints pass 18 tests. Reviews found and resolved authenticated-connection
loss on HTTP errors and library-injected metadata being mistaken for tool arguments.
The UI directory cutover and overall prerequisite/final gates remain open; this
checklist does not mark the complete platform milestone implemented.

Stable snapshot verification (2026-10-15): root format check, warnings-as-errors
compilation, strict Credo, unused dependency check and the complete default umbrella
suite all passed. All applications reported zero test failures; excluded integration
and live-provider lanes were not enabled.

## Checkpoint: call-spec discovery and authoring

Depends on tenant discovery. Runnable slice: list/get a tenant's specs, discover
models, save a draft, append a revision and explicitly publish it locally.

- [x] Red-test required list/get/create/update and supporting publish/catalog tools.
- [x] Extend principal-aware spec reads to tenant admin and Settings platform keys;
  add the missing machine GET routes. Calls-only keys cannot read portable source.
  Domain prerequisite implemented and reviewed: tenant admin source/list reads
  reject calls-only and foreign-tenant actors before storage, share source fetch
  and retain latest/historical/publication metadata. Shared read/write policy now
  also preserves Settings platform authority for canonical writes; red regressions
  and 67 Calls/15 Gateway focused tests passed, independently reviewed. Transport
  acceptance is recorded below.
- [x] Paginate spec summaries and provider/model helpers with the shared envelope;
  preserve existing catalog REST response shape when pagination is not requested.
- [x] Implement get by public ID and optional revision, returning portable source
  and latest/published revision metadata only. No compiled plans/resolved secrets.
- [x] Map `call_spec_definition` to source; updates require `call_spec_id` and append
  immutable revisions. Preserve server-generated IDs, validation, size limits,
  revision conflict and foreign-ID errors. Update cannot create a missing spec.
- [x] Keep publication explicit. Preserve transaction-time complete-source ownership
  checks, especially tenant edits of platform-service-backed definitions.
- [x] Acceptance: REST/MCP produce equivalent revisions and denials; new draft
  creation/update never publishes or starts a call. Local catalog performs no paid
  provider calls. Supporting tools have the same authorization as their operations.

Evidence (2026-10-15): seven MCP spec/catalog tools now use the shared Calls
policy and operations. Forty focused Gateway HTTP tests, four MCP tool tests,
21 Console editor/catalog tests and five persisted-key Console MCP tests pass.
The persisted parity test crosses MCP create/publish with HTTP update/read/list
for full tenant and Settings platform credentials; it verifies immutable historical
source, publication metadata, scoped foreign IDs and calls-only denials. Source
and catalog routes preserve established HTTP shapes, with opt-in catalog paging.
Independent policy, HTTP, MCP and final parity reviews found no remaining blockers.
The stable snapshot also passed all five root completion commands, including the
full umbrella suite with zero failures. No source changed during that verification.
A follow-up parity regression also aligned MCP source/list read failures with
canonical HTTP errors; 36 focused tests and independent review passed. Established
sessions reject credentials supplied only through cookies, query strings or bodies
on notifications and tool requests. The overall milestone, remaining call/user tools
and UI read/catalog cutover stay open.

## Checkpoint: create calls with variables and issue join tokens

Depends on spec authoring. Runnable slice: create a call by published spec ID with
initial variables, receive `{call_id}`, then issue/redeem its token locally.

- [x] Red-test `create_call(tenant_key, call_spec_id, ...)` for web and outgoing specs.
- [x] Share the create workflow with the existing spec-scoped REST call endpoint:
  pin one published revision, prepare web calls, or submit outgoing calls. Existing
  REST clients keep their response shape; MCP returns the minimal `{call_id}`.
- [x] Validate and persist nested `variables` under the existing declared-section,
  type and access rules before admission/dialing. Verify exact values arrive in
  the runtime; omission preserves the existing absent-section (`nil`) behavior.
  Reject invalid supplied variables before effects; do not inject new defaults.
- [x] Resolve web entry from the published spec without a caller-supplied route;
  carrier-only incoming specs return unsupported-entry, not a synthetic webhook.
  Web preparation is not live audio; outgoing acknowledgement is not an answer.
- [x] Preserve outgoing `to` validation and failed/unknown submission behavior.
  Extend optional tenant-wide `idempotency_key` claim/replay to prepared creation;
  same-key retry returns the same call, changed input conflicts, failed replay
  never admits/dials again. Requests without a key remain separate attempts.
- [x] Implement `create_join_token` with optional participant_key and existing TTL
  limits. Default only to a suitable pinned web entry; require a selector when
  there is no eligible default. Return token, expiry and resolved participant key.
- [x] Add the shared non-participant-scoped token HTTP route; preserve the existing
  participant route. Validate eligibility against this call, not the latest spec.
- [x] Acceptance: nested-variable and invalid-variable cases, concurrent publication,
  duplicate create/replay, wrong tenant/spec/call/participant, TTL/single-use and
  ended-call denial pass with local Morse/fixtures and a fake dial adapter. Token
  values never enter logs, telemetry or audit; no live providers/real calls run.

Domain/storage evidence (2026-10-15): shared actual-actor policy, pinned web and
outgoing claims, tenant-wide replay and pinned web token selection passed all
219 Calls tests plus 46 focused Persistence tests after the expected missing-API
red failures. Independent review found no domain/storage blockers. HTTP/MCP
adapter acceptance now passes as recorded below.

Transport evidence: shared Gateway creation preserves existing HTTP envelopes,
returns minimal MCP call IDs, and starts only freshly claimed outgoing calls.
Canonical/explicit token routes share the pinned issuer and safe projections.
The final focused Gateway selection passed 73 tests. Seven persisted Console tests
cross HTTP/MCP for calls/full/platform credentials
and verify browser CSRF and explicit-key precedence. Review exposed failed-web
replay incorrectly reporting an outgoing error and wrappers masking CSRF rejection;
both regressions were reproduced and fixed. Local fake-dial wire tests verify
nested variables, idempotent recovery after a lost/timeout response, and no redial.
Authorized create_call has a separate bounded 100-second handler deadline; other
operations retain ten seconds. All seven isolated reference-client groups passed.
Fast root format/compile/Credo/dependency gates passed; the next stable full-suite
run remains part of the overall milestone acceptance.

## Checkpoint: authorized whole-call hangup

Depends on call creation. Runnable slice: hang up a prepared, admitting, ringing or
running local call through REST/MCP and observe its owned resources terminate.

Implementation design: [durable whole-call hangup](../../docs/call-hangup-lifecycle.md).
The design records admission ordering, cancellation intent, exact-incarnation
completion evidence and recovery. Its review does not complete runtime tasks.

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

Runtime prerequisite: exact-incarnation supervisor monitoring is implemented.
Two focused regressions first failed for the missing API, then passed along with
19 existing lifecycle tests. A held owned worker proves authority termination
precedes whole-tree completion; monitoring remains available during cleanup and
cannot adopt another tenant or replacement incarnation. Independent review found
no blockers. The full CallEngine suite then passed 2,225 tests with zero failures.
This does not yet implement the hangup workflow or prove Gateway
carrier cleanup, and abnormal supervisor death is not successful cleanup evidence.

Durable intent prerequisite: `Calls.request_call_hangup/4` now authorizes the
actual actor/tenant and locks the call before recording cancellation. Unclaimed
prepared calls end atomically; admitting/running/failed calls retain lifecycle
evidence and first intent. Token issue/redemption reject intent under that lock.
Twenty-two Calls tests, 57 Persistence compatibility tests and two real SQL
connection race tests pass, including both lock orderings and unknown outgoing
preservation. Migration 20261015000400 was applied to the test database. Runtime
binding, shutdown/recovery and HTTP/MCP hangup remain unimplemented; this evidence
does not check off the complete hangup tasks above.

Engine admission prerequisite: resolved web/incoming/outgoing plans can now use
one owner-monitored startup gate, released or cancelled only by the exact owner,
token and incarnation. Legacy outgoing APIs and acknowledgements are preserved.
Thirty-three focused tests pass after five expected red failures, and independent
review found no blockers. All five root completion checks passed against frozen
source, including the full default umbrella suite with zero failures. Gateway
integration evidence follows below; admission-versus-hangup acceptance stays open
until all transports and cleanup reconciliation are implemented.

Exact-incarnation join prerequisite: participant admission now accepts an expected
incarnation and checks it inside the room authority before any join effects.
Three new regressions first failed for the absent API, then passed; eight focused
join/completion tests and the full CallEngine suite (2,233 tests, zero failures)
passed. Independent review found no blockers; its test-cleanup suggestion was
applied and the six join tests rerun successfully. Gateway admission integration
and whole-call shutdown acceptance remain open.

Durable binding prerequisite: web claims, incoming carrier claims and outgoing
calls now bind one incarnation under the call-row lock after checking stored
ownership and pinned plan identity. Canceled/released admissions retain ownership
for cleanup without starting. All three started projections reject cancellation
and conflicting ownership. Facts and variable snapshots share this anchor and
validate the call room; legacy history is validated once using an internal flag.
Migration 20261015000500 was applied to the test database. Focused red-green tests,
four separate-connection transaction races and a 326-test Persistence selection
passed; independent review found no remaining blockers. Root format, compile,
strict Credo and dependency checks also passed. Runtime reconciliation, incoming
gating and terminal cleanup proof remain open; binding is not completion evidence.

Gateway web/outgoing admission now connects the gate to durable binding and a
synchronous started projection before startup effects. Running web joins require
the bound incarnation. Pre-release cancellation or storage errors close only the
owned gate and do not write a generic failed state; replay still cannot redial.
Forty-eight focused Gateway tests pass after nine expected red failures, with
independent review. HTTP success shapes remain compatible, while persistence
failure cannot issue a session. Incoming gating and complete cleanup/recovery
acceptance remain outstanding.

Session cleanup prerequisite: issuance now monitors the exact room before
returning credentials. Missing/stale bindings fail; room termination closes
normal and transfer sessions, retaining retry ownership when admission release
fails. Claim/bind shutdown races return safe not-found errors. Twenty-seven
focused Session/endpoint tests passed after lifecycle/race red tests. Broader
local WebRTC tests found one test-fixture registry cleanup race, removed from
this boundary's test and verified in the focused rerun. Independent review found
no blockers. Session authority death is not whole-call cleanup evidence.

Combined admission checkpoint verification: the clean committed snapshot passed
all five root gates: formatting, warnings-as-errors compilation, strict Credo,
the full default umbrella suite and unused dependency validation. Every application
reported zero failures, including 2,233 CallEngine, 225 Calls, 688 Gateway, 320
Persistence and 335 Console tests. No source changed during the run. Local SQL
races were verified separately; live providers and real telephony stayed excluded.
The overall hangup checkpoint remains unchecked pending incoming admission,
cleanup ownership/reconciliation, terminal evidence and HTTP/MCP parity.

Incoming activation prerequisite: answer preparation now returns retained carrier
binding, pinned service, media admission and usage before submission. Rejected
answers retain finalized context; accepted/unknown results and the existing
activate wrapper preserve current behavior. Three missing-API red tests preceded
implementation; all 21 focused activation/admission-adapter/ingress tests passed,
with independent review. Incoming Leg still needs gated admission and supervised
submission integration; this does not complete incoming cancellation acceptance.

Cleanup-owner prerequisite: a temporary Gateway owner now retains canonical
incarnation membership, exact-engine/resource monitors and original-owner semantic
acknowledgements. Sealing rejects new resources; orderly exits plus every required
acknowledgement establish completion, while abnormal exits and lost owners retain
unknown evidence. Recovery lookup never creates empty membership. Six missing-API
red tests preceded implementation; review found a duplicate identity path, fixed
after a seventh regression. Ten focused tests and the four fast root gates pass;
follow-up review found no blockers. Durable fresh-owner authorization, resource
registration, usage persistence, reconciliation and retirement remain unimplemented.

Combined verification: the full umbrella run passed every application except one
Console assertion still expecting tenant list items without `created_at`. Updated
that assertion to the fixture's timestamp, then reran the entire Console suite:
335 tests passed. The full run had already passed 2,233 CallEngine, 225 Calls,
701 Gateway and 320 Persistence tests, with zero failures in the other applications.
No production source changed between those runs. Final root format, compile,
strict Credo and unused-dependency checks pass. The assertion and integration
design follow-ups were independently reviewed; all findings are resolved.

Atomic incoming-resource prerequisite: tracker startup now accepts one existing
resource and captures its original admission caller as acknowledgement owner.
Membership and monitors are installed before engine DOWN can seal the tracker.
Three missing-API regressions preceded the change; all 13 cleanup tests pass,
including immediate engine completion, owner loss and missing exact engine.
Independent review found no blockers. Incoming Leg integration remains open.

Durable cleanup reservation prerequisite: `bind_managed_call_admission/3` now
returns one-time `:new` or `:existing` ownership under the admission row lock.
Migration 20261015000600 adds private required/completed fields with binding/time
constraints. Pending managed archive closure commits without reporting ended and
preserves valid outgoing metadata; pre-start closure keeps truthful lifecycle
fields. Initial missing-API tests and six close-ordering regressions failed before
implementation. The final selection passed 104 Persistence tests, including SQL
reservation/rollback races, and four Calls tests. Independent review found no
blockers. Gateway does not select managed admission yet; completion persistence,
resource integration and recovery remain outstanding.

Usage retry prerequisite: a millisecond timestamp survives an immutable usage
retry after database microsecond normalization. The regression failed with a
conflict before the fix; all five UsageStore tests now pass, including changed
content/time rejection, with independent review. Carrier retention and explicit
persistence acknowledgement remain unimplemented.

Combined cleanup/key checkpoint verification: all production source stayed frozen
through the root run. Gateway passed 704 tests, Calls 226, Persistence 342 and
Console 341, with zero failures in the other applications except CallEngine's
replacement fixture. Full CallEngine reruns exposed two immediate-create Registry
cleanup races in scoped join/completion fixtures. Both now start replacements
through the owning supervisor's acknowledgement; the final full CallEngine suite
passed 2,233 tests. Independent review found no blockers. Root format, warnings-as-
errors compilation, strict Credo and unused-dependency checks pass. All checks used
local fixtures; live-provider lanes remained excluded. Completion persistence and
full hangup acceptance are still open.

Final carrier-usage prerequisite: `LegUsage.persist_final/2` now retries retained
original observations through the result-bearing Calls store, independently of
live room reporting. Missing/nonterminal/empty usage cannot acknowledge completion;
partial failures and mismatched acknowledgements fail closed. Managed storage
requires exact room/incarnation and only permits failed-call writes with cancellation
intent. Four missing-API regressions and two storage-policy regressions preceded
the fixes; 45 Gateway and eight Persistence tests pass, with independent review
finding no blockers. Carrier-owner wiring and
its separate semantic cleanup acknowledgement remain outstanding.

Durable completion prerequisite: `complete_call_cleanup/3` now stores the first
exact-owner acknowledgement under the call lock, preserves normal archive timing,
and projects acknowledged cancellation without inventing startup. Publication
source/store reject pending managed cleanup and managed nonterminal states;
successful completion/retries request publication after commit. Initial API/gating
reds and later ordering/conflicting-close regressions preceded the implementation.
Final focused verification passed 135 Persistence tests, including separate SQL
connection races/rollback and legacy compatibility, plus six Calls/finalizer tests.
Gateway resource wiring/reconciliation and HTTP/MCP hangup remain unimplemented;
this does not complete the hangup checkpoint.

## Checkpoint: platform-key user administration

Depends on foundation and pagination; does not require live calls. Runnable slice:
a Settings platform key lists/creates a user, disables them, then reactivates them.

- [x] Red-test required user tools plus paginated safe `list_role_options`.
- [x] Add an explicit machine actor carrying verified API key ID to the shared
  Identity policy/ports and persistence transaction checks. Keep browser actor/session
  checks intact; never fabricate a user/session or trust tool-supplied grants.
- [x] Implement the design's Full Platform Access policy for users.read and existing
  member/admin/superadmin write categories. Tenant keys and legacy operator keys
  do not inherit these new installation-wide privileges.
- [x] Add corresponding `/api/users` GET/POST, `/api/users/:id` PATCH,
  `/api/users/:id/disable` POST and `/api/role-options` GET routes. Both transports
  invoke the same Identity workflow/configuration; Gateway never calls Console.
  Declare any direct Identity use in the owning child dependency list.
- [x] Revalidate machine key inside account-write transactions and attribute audit
  to its key ID. Add the minimal schema/port changes needed for machine audit actors;
  existing user audit history remains valid and credentials stay redacted.
- [x] Preserve target/current/requested role-category checks, membership validation,
  password hashing/confirmation, duplicate-email handling and last-enabled-Superadmin
  protection, including concurrent demotion/disable and revocation races.
- [x] Implement partial updates: omitted enabled/role/memberships remain unchanged;
  `enabled: true` activates, false disables. `disable_user` uses the same workflow,
  is repeat-safe and revokes user sessions without hard deletion. Reactivation must
  not revive revoked sessions; independent API keys keep their existing lifecycle.
- [x] Paginate/filter user and role-option lists with safe projections. Passwords
  are creation inputs only and never returned, audited or logged. No implicit
  password-reset or role-administration tools.
- [x] Acceptance: platform/tenant denials, create/disable/reactivate/login outcomes,
  partial-field preservation, privileged targets, concurrency, key revocation,
  audit attribution and pagination agree between REST/MCP using synthetic accounts.

Account-domain evidence (2026-10-15): narrow machine authority, transaction-time
platform-key revalidation/audit and canonical input/paging passed 67 Identity,
53 focused Persistence, three Console and one separately selected local SQL
revocation-concurrency test. Independent review found no authority/audit blockers;
query/filter compatibility findings were corrected. Migration 20261015000300 was
applied to the test database. HTTP/MCP account adapter acceptance now passes:
eight focused Gateway tests and
four persisted Console tests cover create/update/disable/reactivate, real login
and session revocation, key audit attribution, tenant-key denial, revoked-key
sessions, safe pagination, strict partial inputs and explicit-header precedence.
Independent adapter review found no blockers. The frozen snapshot passed all five
root completion checks, including the complete default umbrella suite with zero
failures; no live-provider or telephony integration lane was enabled. UI account
route migration remains tracked in the following checkpoint.

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

UI cutover slice (2026-10-15): tenant discovery, spec directory/detail and catalogs,
account list/detail/create/update and paginated role options now use canonical
HTTP routes. Tenant list timestamps are shared across HTTP/MCP; account inputs
use canonical filters and membership tenant keys. Full role-grant reads still
enrich account selectors through the existing authorized role endpoint until role
administration migrates. Role management, password reset,
tenant creation, onboarding/samples and call inspection remain open.

Nine frontend red failures and a tenant-projection regression preceded the changes.
All 759 frontend tests, TypeScript, ESLint and the asset build passed, along with
13 focused Gateway and 11 persisted Console tests. Rendered Chrome/network checks
at desktop and mobile verified tenant/account pagination, account creation,
membership editing/disable and spec/catalog reads using canonical routes. The
independent review found an outdated SDK response assertion; it and the public
docs were corrected, and all seven reference-client groups passed. No live
providers were used; the synthetic browser fixture and sandbox were stopped.

API-key UI cutover: all four canonical `/api/api-keys` routes now reuse the
existing controller and Calls delegation policy. Canonical and legacy aliases
reject explicit Authorization before parsing or session fallback, retain CSRF and
host restrictions, and do not grant machine-key delegation. After route/client and
legacy-alias red regressions, 36 focused Console tests and all 760 frontend tests
passed, together with TypeScript, lint and the asset build. Rendered Chrome verified
listing/target selection, creation, one-time secret dismissal and revocation.
The existing table overflows horizontally at 390px; no layout changed in this slice.
Remaining UI operations and final acceptance stay open.

Services UI cutover: 16 Console-owned canonical service, credential, telephony-
application and authoring number-inventory routes now share existing controllers
with their legacy aliases. Both prefixes require sessions and reject explicit
Authorization before fallback. Direct credential validation now requires the same
write authority as HTTP, and domain denials map to 403. The UI uses canonical URLs,
including onboarding's service-binding read; onboarding mutations remain pending.

After expected policy/endpoint/client red failures, 53 Calls tests, 48 Console
tests and all 760 frontend tests passed, with types/lint/build and independent
review. Rendered desktop/mobile checks verified platform validation/create/delete,
tenant validation/create/update and onboarding's canonical binding lookup using a
fake validator. The fixture and browser stopped. Existing tenant scoped-service
and embedded telephony components have no production route; their request changes
have endpoint/component coverage, without claiming rendered coverage. Roles,
password reset, tenant creation, onboarding/samples and call inspection remain open.

## Checkpoint: parity acceptance and documentation

Depends on all required capability checkpoints and supporting workflows.

- [x] Run a local reference client against the actual Console mount, standalone
  Gateway and embedding prefix. Pin server-conformance tools and report applicable
  passes/omissions rather than using outbound acceptance as inbound proof.
  Evidence: `bin/test-platform-mcp` passed all seven groups using SDK 1.30.0 and
  conformance 0.1.16. The three selected official scenarios use a labeled loopback
  synthetic-header adapter. See [acceptance scope](../../docs/development/platform-mcp-acceptance.md);
  the SDK currently invokes tenant tools, so full capability parity stays open.
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
