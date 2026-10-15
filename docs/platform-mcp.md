# Platform MCP endpoint

Status: approved for implementation, 2026-10-15. Implementation is in progress.
The [implementation milestone](../labnotes/milestones/platform-mcp-endpoint.md)
owns checkpoints and acceptance. This decision records the initial scope and its
authorization boundaries.

## Intended use

Expose the platform's API-key operations as named MCP tools at `/mcp` on the
existing application origin. A user configures their MCP client with that URL and
`Authorization: Bearer <Vxpipe API key>` using a key created in Settings. No second
key system, browser login, or separate deployment is needed.

The user-selected scope includes tenant discovery, call-spec CRUD-style authoring,
call creation/join/hangup, user administration and paginated lists. This supersedes
the earlier nine-tool machine-endpoint-only proposal. Several required operations
need shared machine API/application changes; they remain part of this milestone,
not deferred Console-only features.

## What exists today

- Gateway owns machine HTTP routes and Calls owns their authorization/workflows.
- Tenant keys become `Vxpipe.Calls.Principal` values with `admin` and/or `calls`
  scopes. These scopes are independent.
- Settings issues Create & Join Calls keys (`calls`), Full Tenant Access keys
  (`admin` + `calls`), and Full Platform Access keys (`platform`). Creation is
  restricted by the issuing user's permissions. Authentication uses the issued
  key's current stored scope/revocation state; it does not impersonate the issuer's
  browser session or dynamically inherit their role.
- Settings platform keys (`vxpk_`) authenticate as installation operators and can
  also establish an explicitly tenant-bound `admin` + `calls` principal through
  `Calls.authenticate/4`. For authoring with platform services, preserve the
  installation-authority path used by platform HTTP routes.
- Trusted legacy operator keys (`vxop_`) have platform status/authoring access;
  they are not interchangeable with Settings platform keys on tenant call routes.
- `vxpipe_mcp` is an outbound MCP client library. Its existing conformance results
  do not establish inbound server support.

Evidence: [key contract](api-key-access.md),
[machine API behavior](operator-api-key-authoring.md),
[Gateway router](../apps/vxpipe_gateway/lib/vxpipe/gateway/http/router.ex),
[tenant authentication](../apps/vxpipe_calls/lib/vxpipe/calls/administration.ex),
[Settings key issuance](../apps/vxpipe_calls/lib/vxpipe/calls/api_key_management.ex),
[Console router](../apps/vxpipe_console/lib/vxpipe/console/router.ex).

## Shared application and HTTP API

User decision: the UI and external HTTP clients use one documented product API.
MCP invokes the same underlying Elixir application operations directly. Sharing
database tables or placing similar business logic in separate controllers does
not satisfy this contract.

```mermaid
flowchart TD
  UI[Console UI] --> HTTP[Documented HTTP API]
  External[External HTTP clients] --> HTTP
  Client[MCP clients] --> MCP[MCP tools]
  HTTP --> App[Shared Elixir application operations]
  MCP --> App
  App --> Domain[Calls / Identity / runtime workflows]
  Domain --> Stores[Persistence ports and runtime owners]
```

The application API is a set of focused public context functions, not a new generic
dispatcher or a service deployment. Reuse the existing umbrella owners:

| Responsibility | Owner |
| --- | --- |
| Tenant/spec reads and writes, key authority, durable admission/claims | `vxpipe_calls` |
| Account policy and user lifecycle | `vxpipe_identity` |
| Preparing/starting/stopping transport-backed calls | Transport-neutral application workflows in `vxpipe_gateway`, composing Calls and engine/runtime owners |
| Repositories, transactions, actor revalidation and durable audit | `vxpipe_persistence` through domain-owned ports |
| HTTP parsing/authentication and MCP protocol envelopes | Thin adapters in Gateway, with Console supplying its browser-session integration |

No new umbrella application is required solely to provide a shared facade. Keep
functions grouped by domain rather than a large `API.execute(action, params)`
module. Each operation accepts a trusted actor and validated operation input,
returns `{:ok, result}` or `{:error, error}`, and owns its policy, validation,
pagination, transaction/idempotency and side effects independent of transport.
Use small typed request/result structures only where they clarify a real contract.

For example, both the HTTP handler and MCP handler invoke the same public
create-call workflow with actor, tenant_key, call_spec_id and call options. Neither
handler reimplements initial-variable validation, performs Repo queries, or chooses
an unscoped engine process. Direct Elixir callers receive the same authorization
checks; a controller's route-permission plug is not the sole guard.

Move reusable Identity dependency composition out of Console-only code into its
owning application's configured boundary. Keep Calls independent of Gateway and
Identity independent of Calls/Console; use ports and application-owned configuration
where machine-key validation requires persistence. Declare actual dependencies in
the owning child rather than relying on transitive access.

### One HTTP contract for UI and external clients

- Canonical product routes live under `/api`. The UI calls these same routes and
  receives the same schemas, pagination, validation errors and response shapes
  as documented external callers. Public does not mean anonymous.
- The current split between `/admin/api` Console handlers and machine-only `/api`
  handlers is migration work. Migrate each overlapping workflow to one canonical
  handler/schema, update UI callers/types/fixtures, and retain necessary legacy
  aliases only as thin compatibility adapters. Do not document one route while
  leaving the UI on an independently implemented private equivalent.
- Preserve existing published `/api` contracts where possible; document and use
  them from the UI. If evolution is needed, specify the additive/versioned migration
  before changing consumers. Existing fields such as `source` are not renamed
  merely to match an Elixir function argument or tool label.
- Inventory all UI requests, not just the MCP subset. Tenant/spec/call/user
  operations, services, roles and key management are product operations, not
  automatically UI-only because they currently live under `/admin/api`. Classify
  and document their canonical routes and machine/session authorization. This
  HTTP consolidation does not add extra MCP tools beyond the reviewed catalog.
- UI-specific helpers may include session/navigation information and page-oriented
  lookups/aggregates. Keep them few, explicitly classified, and composed from the
  same authorized application reads. Login/setup/recovery/CSRF are separate browser
  authentication mechanics. A UI helper must not become a second write path or
  evade public operation permissions.
- One HTTP documentation/schema source covers canonical operations and their
  allowed credential types. Reuse existing schema tooling if available; avoid a
  parallel handwritten API schema for the UI and another for external users.
  MCP schemas adapt these inputs/results and add protocol metadata; they do not
  independently define business validation.

### Authentication and authority

Browser UI requests use the existing session cookie and CSRF protection for unsafe
methods. External callers and MCP use API keys; never put a platform key in the
browser bundle or mint a machine key merely to make the UI use the public API.

The shared HTTP boundary obtains an actor from configured authentication adapters.
Console supplies session authentication/CSRF integration without making Gateway
depend on Console; standalone Gateway can expose the same routes with Bearer-only
authentication. The same HTTP operation implementation serves both deployments.
Explicit Authorization selects key authentication; an invalid/unsupported header
does not fall back to a more privileged cookie. Without Authorization, the browser
session path applies its CSRF/origin protections. Never union key and session grants.
MCP remains API-key-only even on the Console host.

Authenticated actors retain their real provenance: browser user/session or machine
key. Shared policy checks each actor's existing grants/key type, tenant membership
and ownership. Equivalent authority gives equivalent behavior, not every browser
user and every API key the same access. Account writes revalidate the appropriate
actor in the transaction and audit that actor, without fabricated browser sessions.

Acceptance must cover the same operation via direct Elixir, browser-session HTTP,
API-key HTTP and MCP, including denied/foreign resources, initial variables,
pagination and mutation effects. Browser inspection and network verification must
show the UI actually using the documented endpoints. Testing only HTTP and MCP
while retaining the old UI path is incomplete.

## Required tool catalog

Use the names below. `tenant_key` is the public identifier already stored in `tenants.key` and used by
our HTTP routes/authentication. Reserve `tenant_id` for the internal database
primary/foreign key; do not accept it as a public alias. The key is an identifier,
not an authentication secret. Spec, call and user IDs mean their existing public
identifiers. Reject unexpected fields and client-supplied authority.

Use `tenant_key` in MCP arguments, new machine API arguments and new tenant response
objects, including user membership entries. Existing REST responses that expose
`key` remain compatible; old Console payloads can be supported during the UI's
cutover by thin legacy aliases. The final UI uses the documented canonical shapes,
without a browser-specific variant of the same endpoint. This introduces no new
tenant identifier and requires no tenant data migration. Use `get_tenant` for the
proposed tenant-info tool to match `get_call_spec` naming.

Require `tenant_key` for every tenant-specific operation, even when the credential
already identifies one tenant. This keeps one client/tool schema for tenant and
platform keys, makes the intended target visible, and prevents an implicit selected
tenant from changing the meaning of a call. A tenant key must match that ID; a
platform key selects it explicitly. Validate every supplied spec/call/participant
against the selected tenant as well. Wrong-tenant and unknown resource IDs share
the not-found response. The argument selects a resource context, never authority.
`list_tenants` and installation-wide user/role operations do not take `tenant_key`.

| Tool | Arguments | Result and behavior |
| --- | --- | --- |
| `list_tenants` | `page`, `page_size` | Paginated `{tenant_key, name}` records visible to the key |
| `get_tenant` | `tenant_key` | `{tenant_key, name, created_at}` for one visible tenant; no service secrets |
| `list_call_specs` | `tenant_key`, `page`, `page_size` | Paginated spec summaries with ID, latest revision and published revision |
| `get_call_spec` | `tenant_key`, `call_spec_id`, optional `revision` | Portable definition, selected/latest/published revision metadata; latest saved revision by default |
| `create_call_spec` | `tenant_key`, `call_spec_definition` | New server-generated `call_spec_id` and draft revision |
| `update_call_spec` | `tenant_key`, `call_spec_id`, `call_spec_definition` | Append an immutable draft revision to that existing spec |
| `create_call` | `tenant_key`, `call_spec_id`, optional `variables`, `to`, `idempotency_key` | `{call_id}`; pin the published spec and validate initial variables before admission |
| `create_join_token` | `tenant_key`, `call_id`, optional `participant_key`, `join_token_ttl_seconds` | Token, expiry and resolved participant key for that call |
| `hangup_call` | `tenant_key`, `call_id` | `{call_id, status}` with `ending` or `ended`; terminate the whole call |
| `list_users` | `page`, `page_size`, optional `query`, `role_id` | Paginated safe user records, including ID, email, role, enabled state and memberships |
| `create_user` | `email`, `password`, `password_confirmation`, `role_id`, optional `memberships` | Created enabled user, without passwords or hashes |
| `update_user` | `user_id`, supplied fields among `email`, `role_id`, `memberships`, `enabled` | Updated user; `enabled: true` activates/reactivates the account |
| `disable_user` | `user_id` | Disabled user; repeat-safe, no hard deletion |

These are JSON object arguments, not positional function calls. Optional fields
and defaults are defined below; unspecified fields are required. The target
`call_spec_id` belongs outside the portable definition on updates.

Supporting tools retained/proposed for a complete authoring workflow:

- `publish_call_spec_revision(tenant_key, call_spec_id, revision)`: publication stays
  explicit. Create/update must not silently activate a draft or place calls.
- `list_providers(tenant_key, capability, page, page_size)` and
  `list_provider_models(tenant_key, provider, capability, page, page_size)`: existing
  local provider/model discovery, now with paginated MCP/API projections.
- `list_role_options(page, page_size)`: safe role IDs/names/kinds so a client can
  create/update users without guessing IDs; no role editing tools.

These four helpers are distinguished from the 13 user-requested operations.
Platform status is no longer a proposed product tool; protocol ping remains.
No MCP tools for services/credential management, API-key issuance, role editing,
call-history listing, recording downloads or carrier callbacks are added here.
Existing UI product HTTP operations are still covered by the shared-API inventory
and consolidation requirement above.

## Argument and result details

These contracts are proposals for implementation; they do not imply these tools
already exist. Each tool takes a JSON object with `additionalProperties: false`.
The portable spec and variables have their own existing schema/validation rules,
not a blanket restriction on their nested property names.

| Argument | Type and behavior |
| --- | --- |
| `tenant_key` | Required on tenant-specific tools; existing 16-character URL-safe key |
| `call_spec_id` | Required on spec get/update/publish and call creation; existing public spec identifier |
| `call_id` | Required on token/hangup; existing public call identifier |
| `user_id`, `role_id` | Public user/role UUIDs, never database IDs; role_id required on user creation, optional on update/filter |
| `page`, `page_size` | Optional integers; defaults 1 and 25, page_size maximum 50; no numeric-string coercion in MCP |
| `revision` | Optional positive integer on get, default latest saved revision; required on explicit publish |
| `call_spec_definition` | Required complete portable source object on create/update; update is replacement of source in a new immutable revision, not a JSON patch |
| `variables` | Optional object on create_call, default `{}` before existing declared defaults/validation; missing required variables still fail validation |
| `to` | Optional E.164 string on outgoing create_call; required for a dynamic destination, rejected for a fixed destination or a web-prepared call |
| `idempotency_key` | Optional nonblank UTF-8 string, 1–256 bytes, on create_call; client-generated and reused for the same intended creation |
| `participant_key` | Optional published route key on create_join_token; resolve the pinned eligible web entry if omitted; not a participant's display label |
| `join_token_ttl_seconds` | Optional integer, default 300, range 1–86,400, using current admission limits |
| `email` | Required on create_user, optional on update_user; existing normalization/uniqueness rules |
| `password`, `password_confirmation` | Required input-only strings on create_user; existing password policy and matching confirmation; unsupported on update_user |
| `memberships` | Optional array of `{tenant_key, access}`; default `[]` on create, unchanged if omitted on update; supplied array replaces assignments, `[]` clears them; access is `read` or `read_write`; duplicate tenants rejected |
| `enabled` | Optional boolean on update_user; true activates, false disables, omission leaves status unchanged; null/string values rejected |
| `query` | Optional string on list_users, using the existing bounded account-search rules; absent means no search filter |
| `capability`, `provider` | Required on the appropriate supporting catalog tools; existing capability enum and provider identifier, no arbitrary upstream endpoint |

`update_user` requires at least one change field; every supplied field is validated.
Changing roles must validate the resulting memberships and both old/new account
categories. No implicit role change, assignment deletion or activation is permitted.
Creation returns an enabled user; creating initially disabled accounts is not an
additional flag in this proposal. `disable_user` only changes enabled state and
performs existing session revocation.

| Tool/result group | Structured result |
| --- | --- |
| All list tools | `{items, pagination}` using the envelope below |
| Tenant list item / get_tenant | `{tenant_key, name}` / `{tenant_key, name, created_at}` |
| Spec list item | `{call_spec_id, latest_revision, published_revision}`; published_revision may be null |
| get_call_spec | `{call_spec_id, revision, latest_revision, published_revision, call_spec_definition}` |
| Spec create/update | `{call_spec_id, revision, validation_errors}`; retain current draft-save/compiler-error semantics; neither implicitly publishes |
| Spec publish | `{call_spec_id, published_revision}` after successful publication |
| create_call | `{call_id}`; failures preserve bounded admission/submission error codes |
| create_join_token | `{call_id, participant_key, token, expires_at}`; expiry is an ISO 8601 UTC timestamp |
| hangup_call | `{call_id, status}` where status is ending or ended |
| User list item / create/update/disable | `{user_id, email, role_id, enabled, memberships}`; memberships use public tenant keys |
| Role option item | `{role_id, name, kind}`; kind is admin, superadmin, or null for an ordinary role, matching existing role options |
| Provider/model item | Existing safe catalog fields, preserving provider/model IDs, capability availability and voice options |

The response shapes above are for MCP and corresponding new public projections.
Existing REST response bodies keep their compatible field names/envelopes; the UI
adopts those documented contracts. Compatibility aliases may preserve old Console
payloads during migration. Do not maintain different canonical response schemas
based on whether the caller is the UI or an external client.
No password, password hash or stored API-key material is returned by any tool.

## Pagination

Every product `list_*` operation, including supporting discovery/role lists, accepts
`page` (1-based, default 1) and `page_size` (default 25, range 1–50). Return:

```json
{
  "items": [{"tenant_key": "PUBLIC_TENANT_KEY", "name": "Example"}],
  "pagination": {"page": 1, "page_size": 25, "total": 1, "total_pages": 1}
}
```

Apply authorization and filters before counts and pagination. Use a stable sort
with a unique public-ID tie-breaker; page 1 of an empty directory returns an empty
list with zero totals/pages. Invalid pagination returns a validation error; a page
above `max(total_pages, 1)` returns `page_out_of_range`. Query the database with
bounded limit/offset rather than materializing all users/tenants/specs. Small static
provider catalogs may be paginated after their permission-filtered projection.
Page-based lists are not snapshots across concurrent writes; document this limit.
MCP `tools/list` has its own protocol cursor rules, separate from product pagination.

## Access levels and shared API extensions

| Operation group | Create & Join Calls key | Full Tenant Access key | Full Platform Access key |
| --- | --- | --- | --- |
| Tenant list/info | Own tenant only | Own tenant only | All tenants |
| Spec list/get/create/update/publish; provider/model discovery | No | Own tenant | Selected tenant |
| Create call/join token/hangup | Own tenant | Own tenant | Selected tenant |
| Users and role options | No | No | Installation-wide |

This is the proposed explicit extension of the existing key types for the requested
operations. It must be implemented once in application policy and used by both REST
and MCP. It does not grant a calls-only key access to spec source or a tenant key
access to the user directory. Installation operations require a Settings Full
Platform Access key, not just a tenant key issued by an administrator.

Tenant writes retain complete-source/transaction-time platform-service ownership
checks; platform authoring uses installation authority. A calls key can execute an
already-authorized published spec without gaining authority to edit it. Keep
legacy admin-only and operator-key behavior intact; the new user-administration
rights belong to Settings platform keys and must not implicitly elevate legacy keys.

For Identity, introduce an explicit authenticated machine actor with API key ID.
Do not fabricate a browser user/session or accept permission claims in arguments.
Full Platform Access is issued only by Superadmins today; propose granting its
machine actor `users.read` and the existing member/admin/superadmin account-write
permissions. Reuse current/requested role-category checks, membership validation,
transactional target guards, and the last-enabled-Superadmin invariant. This is a
new machine policy, not a claim that Identity already accepts API keys.

Persist audit attribution to the API key, revalidate key validity inside account
write transactions, and preserve browser actor/session validation unchanged.
Disable revokes that user's sessions; reactivation does not resurrect old sessions.
Current keys are independently revocable credentials without issuer binding:
user disable must not claim to revoke their previously issued API keys automatically.
Partial `update_user` input preserves omitted fields, especially `enabled`, role
and memberships; do not reuse the Console controller's default-valued request map.
Membership inputs use `{tenant_key, access}` entries with existing `read` or
`read_write` access levels. Password reset is not implicitly added to `update_user`. Creation passwords are
input-only, never echoed or logged.

## Call creation, variables and publication

`create_call` uses `call_spec_id`, not a participant route as its primary identifier.
Resolve the tenant-owned published revision and pin it once, including when a
concurrent publication occurs. `variables` is the initial Call Variables object:
validate declared sections, types and access rules before storing/admitting/dialing;
preserve values without coercion or logging. Omission uses the existing empty/default
behavior. It is not metadata and must reach the runtime's initial variables unchanged.

```json
{
  "tenant_key": "PUBLIC_TENANT_KEY",
  "call_spec_id": "PUBLIC_CALL_SPEC_ID",
  "variables": {"customer": {"name": "Dana"}},
  "idempotency_key": "client-generated-request-id"
}
```

For a published web-joinable incoming spec, create a durable prepared call and
return `{call_id}`. The call starts when a participant redeems a join token through
the existing session API. Resolve the entry caller from the published spec; do not
select the first route or trigger a carrier callback. A carrier-only incoming spec
cannot be synthetically received: return an explicit unsupported-entry error.

For an outgoing spec, reuse outgoing admission/dial submission and its `to` rules,
then return `{call_id}` after submission acknowledgement. This is not proof that the
callee answered. `to` is conditional on the spec's fixed destination; it never
comes from initial variables. Preserve bounded validation/submission errors.

Retain outgoing optional `idempotency_key` semantics and extend the shared claim
contract to prepared calls so the same public tool has consistent lost-response
recovery. The same tenant, idempotency key, spec, destination and variables replay the same call without
an extra dial; changed input conflicts. The existing tenant-wide idempotency
namespace must cover both paths without collisions. Failed/unknown submissions
retain their recorded outcome; replay never silently starts another attempt.
Without a key, separate invocations create separate calls. JSON-RPC IDs are not
idempotency keys. No automatic mutation retries.

The spec create/update tools map `call_spec_definition` to the existing portable
`source` contract. Updates require an existing tenant-owned ID and append a revision;
publication stays separate. `get_call_spec` returns portable source as `call_spec_definition`, never
compiled plans or resolved credentials. Definitions are checked for private material
under the same rules as REST.

## Join-token and hangup behavior

Join tokens remain participant-bound. With no `participant_key`, resolve the call's
pinned web-joinable entry caller. If it has no suitable default, require an explicit
participant selector; do not guess another participant. An explicit key must belong
to this call's pinned routes and be eligible for admission. Subsequent publication
must not change token eligibility for this call. Return the resolved participant
key so the client can use the existing session endpoint.

Reuse single-use token storage, TTL bounds and ended-call denial. Tokens are
intentional sensitive results; keep them out of logs, telemetry and audit summaries.
MCP authenticates with the API key, while token redemption/media negotiation stay
on the existing transports. It does not open audio streams itself.

`hangup_call` is a new authorized application workflow. Resolve tenant ownership
and the exact live incarnation server-side, then request whole-call shutdown through
its owner. Do not simply mark a database row ended or call an unscoped process kill.
Prepared calls must become terminal and their tokens unusable; admitting calls need
an atomic cancellation/admission interlock so shutdown cannot race a new live room.
Running/ringing calls must release all participant sessions and carrier legs through
existing cleanup owners. Never terminate a replacement incarnation using stale data.

A durable shutdown acceptance can return `ending`; return `ended` only with terminal
evidence. Already-ended calls return `ended` without new effects. Foreign/missing
calls return the same not-found shape. If the room is missing with no durable
terminal evidence, return a bounded unavailable/unknown outcome, not false success.
Test cleanup and archival/usage completion with local fake adapters. Do not label an
API-requested hangup as a remote-party hangup if the existing engine entry point
would produce that misleading reason.

## REST parity and ownership inventory

Add routes in the existing `/api` namespace using the shared application operations:

| Machine route | MCP operation(s) | Existing behavior to reuse/extend |
| --- | --- | --- |
| `GET /api/tenants`, `GET /api/tenants/:tenant_key` | Tenant list/info | Scoped tenant directory and safe tenant projection |
| `GET /api/tenants/:tenant_key/call-specs[/:id]` | Spec list/get | Existing Console/domain reads, now machine-authorized |
| Existing spec POST/PUT/publish routes | Create/update/publish spec | Immutable authoring and installation-service ownership |
| `POST /api/tenants/:tenant_key/call-specs/:id/calls` | Create call | Existing outgoing endpoint extended to web preparation |
| `POST /api/tenants/:tenant_key/calls/:id/join-tokens` | Create join token | Existing participant-specific issuer with pinned default resolution |
| `POST /api/tenants/:tenant_key/calls/:id/hangup` | Hang up call | New authorized workflow over durable admission and runtime owners |
| `GET/POST /api/users`, `PATCH /api/users/:id` | User list/create/update | Identity policy, password hashing, transactional guards and audit |
| `POST /api/users/:id/disable` | Disable user | Same partial-update workflow with enabled=false |
| `GET /api/role-options` | Role options | Safe role discovery, no role administration |
| Existing provider/model GET routes | Provider/model lists | Local catalog; add optional paginated projection compatibly |

Keep existing participant admission routes and outgoing responses compatible:
MCP projects the minimal `{call_id}` result from the shared domain result; existing
REST callers keep their response shapes. Do not create a separate outgoing path or
require existing clients to rename body `source`/`variables` fields. Existing catalog
clients without pagination retain their current response shape; pagination is a
shared opt-in REST projection and the standard MCP list shape. New machine routes
and MCP must have identical authorization and side effects.

## Protocol and ownership

Use the existing pinned ExMCP public server/Plug interface in Gateway, with a
direct dependency in that owning child and the shared lockfile. Calls continues
to own key authorization and call workflows; Identity owns account policy;
Persistence owns lookup/storage and transactional actor revalidation.
Console composes the mount and browser authentication adapter. Do not add a Calls/Gateway dependency to the
outbound `vxpipe_mcp` child, introduce an HTTP loopback proxy, or build a new MCP
protocol implementation.

Use the repository's existing MCP `2025-11-25` profile. The product boundary
rejects other revisions even though the dependency supports more versions.
Local Plug tests demonstrate initialization, notifications, ping, key-bound
sessions, deletion and request-worker cleanup. The isolated
[server acceptance runner](development/platform-mcp-acceptance.md) also verifies
the official SDK against all three mounts and selected official conformance
scenarios; this is not full protocol or OAuth certification.

Use Streamable HTTP with JSON tool responses, initialization, initialized
notification, ping, tool discovery and invocation. No unsolicited event stream:
GET returns 405. If ExMCP issues sessions, bind them to authenticated key identity,
bound their count/lifetime, and reauthenticate every request. No durable session
storage or event replay is needed. The implementation probe must settle supported
session/DELETE behavior and version negotiation before enabling tool handlers.
See the [transport specification](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)
and [lifecycle specification](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle).

Current defaults are 64 concurrent HTTP requests, a 128 KiB request body, a
five-second body-read timeout and a ten-second handler deadline. Handler cleanup
can add approximately one second. JSON-RPC IDs are strings of at most 256 bytes
or integers in the inclusive range -9007199254740991 through 9007199254740991.
Rejected oversized IDs are not echoed. Unknown valid notifications receive no
JSON-RPC response body.

The selected ExMCP session manager is node-local and shared: its current defaults
are 10,000 sessions, 10,000 distinct request IDs per session, a one-hour idle TTL
and cleanup every 60 seconds. These are dependency defaults, not per-key quotas;
the isolated runner verifies accelerated idle expiry and full BEAM restart on the
same port, followed by fresh-session recovery. Request owner death releases
Gateway admission and terminates the request handler. These checks do not claim
immediate cancellation on every TCP disconnect. Clients must still supply
their API key on subsequent requests, and use fresh request IDs within a session.

Advertise tools only: no resources, prompts, subscriptions, sampling, elicitation,
task extensions, audio streams, or outbound MCP proxy. Provide strict schemas,
bounded results, structured content plus a text representation, and accurate
read-only/destructive/idempotency annotations. Protocol-envelope failures are
JSON-RPC errors; resource visibility and ordinary domain failures are tool results
with `isError: true`. Credential failures and operation-level key-scope denials
remain HTTP failures. Pre-dispatch scope checks must use the shared application
policy, not a second MCP-specific permission matrix. Follow the
[tool specification](https://modelcontextprotocol.io/specification/2025-11-25/server/tools).

## Authentication contract and client compatibility

Recommendation for this API-key milestone: configure the credential in the MCP
client's HTTP headers. There is no `api_key` tool argument, initialization field,
login tool or URL parameter. The client supplies the header before initialization
and on every subsequent request:

```http
Authorization: Bearer <Vxpipe API key>
```

This is a deliberate compatibility choice, not an implementation of MCP OAuth.
The pinned [MCP authorization profile](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization)
makes authorization optional, but recommends that HTTP implementations follow its
OAuth-based profile. Its interoperable path uses OAuth 2.1, protected-resource and
authorization-server discovery, PKCE, and resource-bound access tokens. Static
Vxpipe keys do not implement that flow; an OAuth client ID/client secret is also
not a substitute for a Vxpipe key.

Our proposed static-key wire contract is:

- Accept exactly one Authorization credential with the Bearer scheme. Reject
  duplicate/combined or malformed credentials with HTTP 400. Never merge credentials
  or fall back to a browser cookie, query string, body, or MCP session ID.
- Missing credentials return HTTP 401 and `WWW-Authenticate: Bearer realm="vxpipe"`.
  Invalid/revoked credentials return 401 with the same challenge and
  `error="invalid_token"`. Responses do not reveal key existence or tenant matches.
- Valid credentials lacking an operation's required authority return HTTP 403;
  shared authorization failures are mapped before producing successful tool results.
  Resource visibility/not-found and other domain failures retain their existing
  safe tool-result mapping. Unavailable authentication storage fails closed with
  HTTP 503, not a misleading invalid-key response.
- Authenticate initialization, notifications, ping, discovery, invocation and any
  supported session cleanup requests. Only after authentication may an unsupported
  method return 405. A session ID alone grants no access; revocation affects the
  next request even when the MCP session already exists.
- Use HTTPS outside loopback development, configure the final endpoint URL, and
  never forward keys to another origin or upstream provider. Do not add login
  redirects, fake OAuth discovery metadata, or a `resource_metadata` challenge
  pointing to an unimplemented authorization server.

### Client setup

[Claude Code documents HTTP Bearer headers and environment substitution](https://code.claude.com/docs/en/mcp#environment-variable-expansion-in-mcpjson).
For example, configure `.mcp.json` with a secret reference:

```json
{
  "mcpServers": {
    "vxpipe": {
      "type": "http",
      "url": "https://YOUR-VXPIPE-HOST/mcp",
      "headers": {
        "Authorization": "Bearer ${VXPIPE_API_KEY}"
      }
    }
  }
}
```

Replace the host with the actual installation and supply `VXPIPE_API_KEY` through
the client's local environment. Never commit its value or put it in a model prompt.
Use a dedicated Settings key with the narrowest access level needed.
[VS Code also documents configurable remote headers](https://code.visualstudio.com/docs/agent-customization/mcp-servers)
and recommends secret inputs or environment files instead of embedded keys.
These are documented client capabilities, not evidence that the product endpoint
has passed interoperability tests. Implementation acceptance must exercise
a real reference client with a locally issued synthetic key.

Clients that require OAuth discovery and cannot configure Authorization headers
are outside this milestone's compatibility promise. If those clients become a
requirement, add an explicit OAuth authorization-server integration: browser
consent, bounded grants, token issuance/expiry/revocation, resource/audience checks,
discovery and PKCE, with client registration chosen for the target clients. Keep
the same shared application authorization boundary. Do not build an ad hoc API-key
exchange or treat the Console cookie as an MCP token to simulate OAuth support.

## Authorization and operational implications

Initialization has no tenant URL. Add a narrow Calls authentication entry point
that resolves a key's stored identity/scope by digest, using a Persistence port.
Do not scan tenants or trust a client-provided scope. Existing tenant storage only
guarantees digest uniqueness within a tenant: use an indexed bounded lookup and
fail closed on ambiguity. Keep old tenant-specific API authentication working;
do not force key rotation or expose which tenant matched.

Each request authenticates afresh. Each invocation checks its named operation,
tenant/resource ownership, installation user-administration grants, and enabled backend. Tool discovery is filtered by key
authority and enabled capabilities, but hiding a tool is not authorization.
Never retain a raw key in session/process state, use a global current principal,
accept authority from tool arguments, or reuse another request's principal.
Revocation denies subsequent requests, including existing MCP sessions. Already
admitted calls/tokens retain the API's existing lifecycle; revocation does not
retroactively cancel them.

Mount exactly `/mcp` through Gateway before generic JSON/browser parsing, both
standalone and Console-hosted. Preserve embedding defaults and carrier-only host
restrictions. Require HTTPS in hosted use and allow HTTP only in loopback development.
Configure explicit trusted host/origin handling, no broad credentialed CORS,
no query-string keys, bounded bodies/deadlines/concurrency, and `no-store` responses.
Use sanitized operation/outcome/duration telemetry; never record arguments,
authorization headers, join tokens, transcript data or credential digests.

## Alternatives and verification

- A generic HTTP tool hides schemas and side effects; use the finite named catalog.
- New MCP scopes would drift from existing API access; reuse application authority.
- Browser session impersonation would misattribute machine operations; the approved
  capability expansion instead needs explicit shared API policy and machine actors.
- A new service or server framework is unnecessary while ExMCP's public server API
  can meet the contract. Investigate concrete gaps before changing dependencies.
- OAuth, prompt/resource catalogs, realtime events and durable replay are separate
  features, not prerequisites for the requested API-key tool endpoint.

Planning evidence is source inspection and primary protocol documentation only.
Implementation acceptance must compare HTTP and MCP outcomes for the same key,
tenant, resource and input, including denials, revocation, platform service ownership,
concurrent principals, initial variables, call lifecycle races, user activation and
consistent pagination. The requested API additions need new parity tests, not just
wrappers over the smaller pre-existing HTTP surface. Use local synthetic keys, PostgreSQL,
Morse/fixture providers and fake outgoing adapters. No live provider or telephony
tests are needed. Pin a local reference client/server-conformance runner and report
its applicable scenario matrix rather than claiming blanket certification.
