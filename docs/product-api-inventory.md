# Product HTTP API inventory

Source inventory for the [platform MCP milestone](../labnotes/milestones/platform-mcp-endpoint.md),
recorded 2026-10-15. Canonical routes below are migration targets, not a claim that
they are implemented. The [platform MCP design](platform-mcp.md) owns application
boundaries, authentication and the approved MCP tool set. Moving a route does not
add an MCP tool or automatically grant a machine key permission to use it.

Implemented UI cutover (2026-10-15): tenant discovery, spec directory/detail,
spec writes/publication, provider/model catalogs, account list/detail/create/update
and paginated role options use the canonical handlers. API-key administration
also uses canonical Console handlers, with session-only authentication and the
existing delegation policy. Tenant list items are
`{tenant_key,name,created_at}`; navigation paths are derived by the UI. Account
selectors temporarily enrich canonical role options with separately authorized
legacy role-grant reads. Service/credential/role administration, password reset,
tenant creation, onboarding/samples and call inspection still require migration.
Legacy routes remain available during that work; this inventory does not claim
their removal or full controller consolidation.

## Classification and migration rules

Product operations have one canonical `/api` handler and response schema, used by
both the browser and documented external callers. Existing `/admin/api` product
routes become temporary compatibility adapters; they must invoke the same shared
Elixir operation. Browser authentication and the few read-only page helpers listed
below remain Console-owned. Carrier/media protocols keep their separate credentials.

Tables use these prefixes to keep complete routes readable:

- `A` = `/admin/api` (current Console JSON routes).
- `T` = `/tenants/:tenant_key`.
- `C` = `/calls/:call_id`.
- `P` = `/platform`.
- `API` = `/api` (canonical product prefix).

For example, `GET A/T/call-specs` means
`GET /admin/api/tenants/:tenant_key/call-specs`.
Every canonical product operation below requires a trusted actor. `S` means a
current browser user/session subject to its existing permission checks and CSRF on
unsafe methods. `Kcalls`, `Kfull` and `Kplatform` mean Settings Create & Join Calls,
Full Tenant Access and Full Platform Access keys. Scope is always checked against
the named tenant/resource. Explicit Authorization selects key authentication and
never falls back to a cookie. Standalone Gateway has no session adapter.

`S; K denied pending policy` is an explicit migration constraint, not a UI-helper
classification: publish the session credential requirement and retain the shared
product endpoint. The approved MCP matrix does not define machine grants for role
editing, access-key delegation, provider-credential administration, tenant creation
or archival reads. Resolve those grants deliberately in implementation; do not turn
an installation-status credential into an unrestricted administrative actor.
Legacy `vxop_` permissions remain unchanged. Session users also retain their actual
permissions; no route treats every signed-in user as an administrator.

`migrate` in a table means move the UI caller and documented route together,
extract shared application policy/projection, retain a thin legacy adapter where
needed, and test both allowed and denied callers. Canonical schemas must not vary
by credential type. Current Console camelCase fields can be translated only in a
legacy alias; new canonical account input uses `role_id` and membership
`tenant_key`. Existing machine `source` and response envelopes stay compatible.

## Tenants, call specs and discovery

| Existing method/path | Canonical product method/path | Shared owner and schema | Credential policy; migration |
| --- | --- | --- | --- |
| `GET A/tenants` | `GET API/tenants` | Calls tenant directory; `q`, `page`, `page_size`; safe tenant rows plus pagination | S `tenants.read`; all three K kinds see authorized tenants; migrate `App`, navigation and user membership picker |
| none | `GET API/T` | Calls tenant lookup; `{tenant_key,name,created_at}` | S visible tenant; all three K kinds within scope; add shared lookup |
| `POST A/tenants` | `POST API/tenants` | Calls `TenantCreation`; `{name}` -> `{tenant: ...}` | S `tenants.write`; K denied pending policy; migrate navigation tenant creation |
| `GET A/T/call-specs` | `GET API/T/call-specs` | Calls spec directory; page inputs -> public ID/name/revision/count rows plus pagination | S `call_specs.read`; Kfull/Kplatform; migrate directory |
| `GET A/T/call-specs/:id` | `GET API/T/call-specs/:id` | Calls authorized revision read; optional `revision`; `{call_spec: ...}` containing portable `source`, latest/published revisions | S `call_specs.read`; Kfull/Kplatform; move projection out of Console |
| `POST A/T/call-specs`; `POST API/T/call-specs`; `POST API/P/T/call-specs` | `POST API/T/call-specs` | Calls authorized authoring; exactly `{source}` -> existing `{call_spec: ...}` revision envelope, 201 | S `call_specs.write`; Kfull/Kplatform; preserve installation-service ownership checks and legacy operator alias |
| `PUT A/T/call-specs/:id`; `PUT API/T/call-specs/:id`; `PUT API/P/T/call-specs/:id` | `PUT API/T/call-specs/:id` | Calls authorized authoring; exactly `{source}`; append revision to an existing spec, 201 | Same as create; reuse shared `CallSpecAuthoring.existing_target/2`; remove redundant legacy controller lookup |
| `POST A/T/call-specs/:id/revisions/:revision/publish`; corresponding `API/T` and `API/P/T` routes | `POST API/T/call-specs/:id/revisions/:revision/publish` | Calls publish; empty object body -> revision envelope, 200 | Same as create; publication explicit; retain compatible installation alias |
| `GET A/T/providers`; `GET API/T/providers` | `GET API/T/providers` | Calls provider catalog; required `capability`; `{providers: ...}` | S `call_specs.read`; Kfull/Kplatform; same handler; opt-in page projection preserves existing unpaged machine envelope |
| `GET A/T/providers/:provider/models`; corresponding `API/T` route | `GET API/T/providers/:provider/models` | Calls model catalog; capability + provider; `{models: ...}`, voice/options metadata | Same as provider list; preserve provider/model IDs and optional paginated projection |
| `GET A/T/telephony-services/:service/numbers` | `GET API/T/telephony-services/:service/numbers` | Calls phone-number inventory through provider port; `search`, opaque `page`, optional `call_spec_id`; `{numbers,next_page}` | S `call_specs.write`; K denied pending policy; preserve provider cursor (not product page-number pagination) and assignment visibility |

The existing tenant list also returns `dashboard_path` and `can_setup`. The canonical
schema must explicitly choose whether to preserve those fields additively or derive
navigation in the UI. Neither is justification for a private tenant directory.
`tenant_id` remains an internal database identifier, never a public argument alias.

## Calls, admission and artifacts

| Existing method/path | Canonical product method/path | Shared owner and schema | Credential policy; migration |
| --- | --- | --- | --- |
| `POST API/T/call-specs/:id/calls` (outgoing only) | same, extended to web preparation | Gateway transport-neutral call workflow + Calls claim; `variables`, conditional `to`, optional Idempotency-Key header; preserve outgoing response, document prepared result | S `calls.write`; Kcalls/Kfull/Kplatform; pin revision and share idempotency namespace; no automatic retry |
| `POST API/T/participants/:participant_key/calls` | same compatibility operation | Calls admission + Gateway runtime; `variables`, `join_token_ttl_seconds`; call/participant/token response | Existing calls keys; preserve entry-specific admission while primary create-call operation uses spec ID |
| `POST API/T/C/participants/:participant_key/join-tokens` | same explicit-participant operation | Calls token issuance; TTL -> call/participant/token/expiry | S `calls.write`; Kcalls/Kfull/Kplatform; retain existing envelope |
| none | `POST API/T/C/join-tokens` | Shared token workflow; optional participant + TTL, resolve pinned entry if omitted | S `calls.write`; Kcalls/Kfull/Kplatform; reuse issuer, never guess another participant |
| none | `POST API/T/C/hangup` | Gateway whole-call workflow + Calls admission interlock; empty body -> `{call_id,status}` | S `calls.write`; Kcalls/Kfull/Kplatform; status means durable `ending` or evidenced `ended` |
| `GET A/T/calls` | `GET API/T/calls` | Calls directory; page and optional `call_spec_id`; current tenant/spec context, calls, pagination | S `calls.read`; K denied pending archival-read policy; migrate directory and filter types |
| `GET A/T/C` | `GET API/T/C` | Calls metadata + shared inspection query; `{tenant,call_spec,call_spec_revision,inspection}` | S `calls.read`; K denied pending archival-read policy; extract Console query/presenter; retain pinned revision agreement check |
| `GET T/C/inspection` | `GET API/T/C/inspection` | Same inspection query; inspection snapshot without directory envelope | Same scoped call-read policy; migrate poll URL emitted by server and `callInspection.ts` |
| `GET T/C/details/:publication_id` | `GET API/T/C/details/:publication_id` | Calls/archival read ports; exact JSON publication attachment | Same scoped call-read policy; retain content type, no-store and safe Content-Disposition; update server-generated download URLs |
| `GET T/C/recordings/:artifact_id` | `GET API/T/C/recordings/:artifact_id` | Calls/archival read ports + streaming response adapter; WAV bytes | Same scoped call-read policy; retain streaming, artifact ownership and unavailable states; update generated audio URLs |
| `POST API/T/C/participants/:participant_key/sessions` | same protocol endpoint | Gateway admission; empty object + one-time participant join token -> media session | Join-token Bearer, **not** account/API-key auth; keep token replay/expiry/binding checks |
| `POST API/rtvi/offer`; `PATCH API/rtvi/offer` | unchanged | Gateway RTVI; SDP offer/session identifier and ICE candidate messages | Existing admitted media-session/connection capability; no conversion to account API auth |
| `POST API/rooms`; `POST API/rooms/:room_id/sessions` | unchanged explicit opt-in development interface | Gateway Rooms; configured trusted preset/principal, room/session result | Existing configuration-gated development auth; not general tenant creation or MCP admission; keep disabled defaults |

The current browser sample buttons call `POST /admin/samples/calls` and
`POST /admin/samples/transfers`. These are **product mutations**, not read-only UI
helpers. Replace their hidden sample bootstrap path with canonical authorized
sample preparation (proposed `POST /api/samples/calls` and
`POST /api/samples/transfers`) over the same call creation/token workflows, or have
the UI call those primary operations directly after sample installation. Keep
the sample-enabled gate, tenant/spec-write preconditions and current token response.
Do not grant sample routes ambient installation authority solely because the
controller was historically protected by `tenants.write`. Shared operation tests
must prove direct invocation cannot bypass these checks.

## Services, provider credentials and onboarding

These are product APIs, even though none is a new MCP tool in this milestone.
Provider credential values are input-only and must never appear in directory
responses. Credential validation may contact the provider in production; its
tests in this milestone use a local fake adapter.

| Existing method/path | Canonical product method/path | Shared owner and schema | Credential policy; migration |
| --- | --- | --- | --- |
| `GET A/P/services` | `GET API/P/services` | Calls service bindings; binding directory + webhook URLs + provider capabilities | S `platform_services.read`; K denied pending service policy; migrate `ScopedServicesApp` |
| `GET A/T/services` | `GET API/T/services` | Calls services; `{tenant,credentials,telephony_services,truncated}` safe projections | S `tenant_services.read`; K denied pending service policy; migrate `App` |
| `GET A/T/service-bindings` | `GET API/T/service-bindings` | Calls bindings; inherited platform vs tenant ownership + webhook URLs/catalog | S `tenant_services.read`; K denied pending service policy; migrate scoped services/onboarding |
| `GET A/T/credentials` | `GET API/T/credentials` | Calls provider credential metadata; `{tenant,credentials,truncated}` | S `tenant_services.read`; K denied pending service policy; not access keys |
| `POST A/T/credentials/test`; `POST A/P/credentials/test` | same suffix under `API` | Calls credential validation; provider/name/values -> `{status:"valid"}` or bounded error | S `tenant_api_keys.write` or `platform_services.write`; K denied pending service policy; preserve unsupported-provider 501 |
| `POST A/T/credentials`; `POST A/P/credentials` | same suffix under `API` | Calls credential creation; provider/name/values -> `{credential: safe_metadata}`, 201 | Same respective write grants; preserve validation and duplicate-name conflict |
| `PATCH A/T/credentials/:credential_id`; platform counterpart | same suffix under `API` | Calls credential update; supported values -> safe credential metadata | Same respective write grants; no secret readback |
| `DELETE A/T/credentials/:credential_id`; platform counterpart | same suffix under `API` | Calls credential removal; no body -> 204 | Same respective write grants; preserve in-use conflict and ownership |
| `GET A/T/telephony-applications` | `GET API/T/telephony-applications` | Calls `OperatorTelephonyApplications`; tenant, application rows, published routes, truncation | S `tenant_services.read`; K denied pending service policy; migrate `TenantTelephonyApplications` |
| `POST A/T/telephony-applications` | `POST API/T/telephony-applications` | Calls telephony application create; existing validated definition -> `{application}`, 201 | S `tenant_services.write`; K denied pending service policy; preserve credential ownership |
| `PATCH A/T/telephony-applications/:service_id` | `PATCH API/T/telephony-applications/:service_id` | Calls telephony application update -> `{application}` | Same write grants; preserve published-route conflicts |
| `POST A/onboarding/demo-tenant` | `POST API/onboarding/demo-tenant` | Calls authorized ensure-demo-tenant; `{tenant}` | S `tenants.write`; K denied pending tenant-creation policy; extract controller ambient installation authority behind shared policy |
| `POST A/onboarding/demo-tenant/samples` | `POST API/onboarding/demo-tenant/samples` | Calls sample authoring workflow; installed sample IDs/names/status/revisions | S `tenants.write` **and** target `call_specs.write`; K denied pending sample-install policy; move `Console.DemoSamples` orchestration to owning boundary |

Service `truncated` results and provider cursors predate this milestone. Document
their bounds instead of silently labelling them paginated. Required MCP product
lists use the milestone's `page`/`page_size` contract. Evolve additional directory
schemas explicitly where pagination is introduced; keep legacy aliases compatible.

## Accounts, roles and access keys

| Existing method/path | Canonical product method/path | Shared owner and schema | Credential policy; migration |
| --- | --- | --- | --- |
| `GET A/users` | `GET API/users` | Identity Accounts; query, role filter, page/page_size -> safe users + pagination | S `users.read`; Kplatform; canonical snake_case DTO; move dependency wiring out of Console |
| `GET A/users/:id` | `GET API/users/:id` | Identity authorized account lookup -> `{user}` | Same read authority; keep existence protection |
| `POST A/users` | `POST API/users` | Identity account create; email/password/confirmation/role/memberships -> `{user}`, 201 | S target-category write policy; Kplatform explicit machine actor; transaction revalidation/audit |
| `PATCH A/users/:id` | `PATCH API/users/:id` | Identity partial update; email/role/memberships/enabled; omitted fields preserved | Same write authority; preserve last-enabled-Superadmin and membership guards |
| none | `POST API/users/:id/disable` | Same update operation with enabled=false -> safe result | Same write authority; revoke sessions, not independently issued keys |
| `POST A/users/:id/reset-password` | `POST API/users/:id/reset-password` | Identity password reset; password/confirmation, no password response | S existing account-category reset permission; K denied pending reset policy; separate from MCP update |
| `GET A/role-options` | `GET API/role-options` | Identity allowed role options; safe ID/name/kind + pagination | S `users.read`; Kplatform; no grants editing; migrate user editor |
| `GET A/roles`; `GET A/roles/:id` | `GET API/roles`; `GET API/roles/:id` | Identity role read; role ID/name/kind/revision/grants, single-role affected user count | S Identity role-read policy; K denied pending role policy; retain revision/count semantics |
| `POST A/roles` | `POST API/roles` | Identity role create; name/grants -> `{role}`, 201 | S role-write policy; K denied pending role policy; retain reserved role protection |
| `PATCH A/roles/:id` | `PATCH API/roles/:id` | Identity role update; expected revision/name/grants -> `{role}` | Same write authority; preserve optimistic concurrency and sessions behavior |
| `DELETE A/roles/:id` | `DELETE API/roles/:id` | Identity role delete -> 204 | Same write authority; preserve affected-user/reserved-role protection |
| `GET A/api-keys` | `GET API/api-keys` | Calls `ApiKeyManagement`; q/page -> `{keys,pagination,creatable_kinds}` | S access_keys/platform_api_keys read policy; K denied pending delegation policy; masked suffix only |
| `GET A/api-keys/tenants` | `GET API/api-keys/tenants` | Calls key issuance target search; kind/q/page -> authorized tenant options | S issuance ceilings and key-management permissions; K denied pending delegation policy; not an unfiltered tenant picker |
| `POST A/api-keys` | `POST API/api-keys` | Calls key issuance; `{name,kind,tenant_key}` -> `{key,secret}`, 201 | S existing delegation ceiling; platform issuance Superadmin-only; K denied pending delegation policy; secret returned once |
| `DELETE A/api-keys/:id` | `DELETE API/api-keys/:id` | Calls key revoke -> 204 | S existing revoke policy; K denied pending delegation policy; revocation effective at next auth |

The four access-key routes above are implemented, documented in the
[HTTP contract](product-http-api.md#api-key-management-console-session-only), and
used by the UI. Their legacy aliases invoke the same handlers and reject any
explicit Authorization header before parsing or session fallback. Machine-key
delegation remains denied.

Account and role schema consolidation must preserve public user/role IDs. Existing
Console `tenantId` membership entries actually contain the public tenant key;
canonical schema must call it `tenant_key`. Do not accept raw database IDs or use
browser-only permission plugs as the application authorization boundary.

## Browser authentication and limited UI helpers

These remain separate from the documented product mutation surface. Their inputs
and outputs are browser-specific; they cannot be used as substitutes for denied
product operations.

| Existing method/path | Classification and owner | Retained contract and reason |
| --- | --- | --- |
| `GET /auth/api/status` | Browser auth, Console + Identity | Setup/login state; no machine credential needed |
| `POST /auth/api/setup`, `/auth/api/login`, `/auth/api/recover` | Browser auth, Identity workflows | Bootstrap/login/recovery credentials and session establishment; retain CSRF/rate limits; no MCP equivalents |
| `POST /auth/logout` | Browser auth, Console + Identity | Revoke current session; CSRF protected |
| `PATCH A/account` | Browser account security, Identity | Own email/password update with current-password verification; a machine key has no personal account; retain session requirement and no second admin update path |
| `GET A/session` | UI session helper, Console + Identity | Current authenticated user/role/navigation permission context; never a machine actor impersonation |
| `GET A/navigation` | UI navigation helper, Console | Optional selected tenant -> navigation tree built from authorized reads |
| `GET A/T/dashboard` | UI page aggregate, Console | Tenant overview/recent calls/counts assembled from authorized Calls reads; no separate write behavior |
| `GET A/T/call-spec-editor-lookups` | UI aggregate, Console | Safe credential names, telephony service labels and MCP integration names; shared read policy and no credential values |
| `GET A/T/calls/spec-options` | UI search projection, Console + Calls | q/page -> `{options,has_more}` for call-history filter; preserves call-read visibility without granting full spec-source access |

Keep these helper routes explicitly documented as Console-only while product routes
move. `/account` is a personal credential workflow, whereas user administration is
the canonical public `/api/users` operation. That distinction avoids manufacturing
an end-user identity for machine keys.

HTML navigation is not an alternate API. Existing `GET /`, `/tenants`,
`/tenants/new`, `/getting-started`, `/my-tenants`, `/account`, `/users`,
`/users/new`, `/users/:id`, `/users/:id/reset-password`, `/roles`, `/roles/new`,
`/roles/:id`, `/api-keys`, `/api-keys/new`, `/platform/services`, and
`/t/:tenant_key/{dashboard,calls,call-specs,services}` remain page routes.
`GET /auth/{setup,login,recover}` remain auth pages. Legacy `/admin` and
`/admin/*path`, plus `GET T/calls`, `GET T/C` and `GET T/C/console`, remain page
redirects. `GET /operator/sign-in` and `POST /operator/{session,sign-out}` retain
their retired-operator guidance/rejection, never a second login mechanism.
`GET /admin/samples/{pipecat-console,transfer}` remain sample pages.

Diagnostics (`/admin/diagnostics`, `/admin/diagnostics/system`, their LiveView
socket and dashboard assets) remain configuration-gated Superadmin browser
operations. Static assets, Storybook fixtures and client-side navigation are not
product API calls. WebSocket diagnostics transport does not become MCP SSE.

## External protocols and machine-only compatibility

| Existing route | Classification, owner and credential contract |
| --- | --- |
| `GET /healthz` | Gateway liveness; no secret or account information; unchanged |
| `GET API/P/status` | Existing machine installation-status API; Gateway OperatorAPI; preserve operator/platform key policy and response |
| `POST /webhooks/platform/telnyx`; `POST /webhooks/tenants/:tenant_key/telnyx` | Carrier callback, Telnyx signed request verification and scoped configured credential; unchanged |
| `POST API/telephony/twilio/:ingress_key/voice`; `POST API/telephony/twilio/:ingress_key/events/:leg_id` | Carrier callback, Twilio signature/ingress binding; unchanged |
| `GET API/telephony/{telnyx,twilio}/:ingress_key/media/:token` | Provider WebSocket media upgrade, one-time scoped media capability; unchanged |
| `POST /mcp`, supported cleanup, authenticated unsupported-method handling | New API-key-only Streamable HTTP adapter; exact auth/protocol contract in platform MCP design; no Console cookie |

The shared account API authentication plug must not intercept carrier callbacks,
join-token redemption or media capability paths and reinterpret their tokens as
Settings API keys. Preserve carrier-only host restrictions and disabled embedding
defaults when changing the Gateway/Console mount order.

## Source evidence and remaining implementation checks

Inspected sources:

- [Console router](../apps/vxpipe_console/lib/vxpipe/console/router.ex) and
  [route permissions](../apps/vxpipe_console/lib/vxpipe/console/route_permission.ex).
- [Gateway router](../apps/vxpipe_gateway/lib/vxpipe/gateway/http/router.ex),
  [spec writes](../apps/vxpipe_gateway/lib/vxpipe/gateway/http/call_spec_writes.ex),
  [admission](../apps/vxpipe_gateway/lib/vxpipe/gateway/http/call_admissions.ex), and
  [call creation](../apps/vxpipe_gateway/lib/vxpipe/gateway/http/call_creation.ex).
- [Main UI requests](../apps/vxpipe_console/assets/src/App.tsx),
  [editor client](../apps/vxpipe_console/assets/src/admin/callSpecEditor/editor-api.ts),
  [account/role client](../apps/vxpipe_console/assets/src/admin/authentication/authenticationApi.ts),
  [key client](../apps/vxpipe_console/assets/src/admin/apiKeys/accessKeysApi.ts),
  [navigation client](../apps/vxpipe_console/assets/src/admin/navigation/navigationApi.ts),
  [scoped services](../apps/vxpipe_console/assets/src/ScopedServicesApp.tsx),
  [telephony applications](../apps/vxpipe_console/assets/src/admin/TenantTelephonyApplications.tsx),
  [sample admission](../apps/vxpipe_console/assets/src/sampleAdmission.ts),
  [inspection polling](../apps/vxpipe_console/assets/src/callInspection.ts), and
  [transfer signaling](../apps/vxpipe_console/assets/src/transferConnection.ts).
- Console controllers named by the router, including generated artifact download
  responses, and their response projections. Request inventory excludes test and
  Storybook-only mock fetches but includes server-generated links and media URLs.

This is a source inventory, not browser/network acceptance. Implementation must:

1. Choose canonical DTOs once and move the UI parsers/types/fixtures with each
   route. Spec-write responses currently differ: Console includes source while
   machine writes expose revision metadata. Preserve machine fields; expose any
   additive source only under the same authorized schema for both actor kinds.
2. Reuse shared spec-target existence checks and extract controller checks (sample install
   permissions, call inspection agreement) before replacing them with thin adapters.
3. Preserve key issuance ceilings and decide non-MCP machine grants explicitly;
   no route-prefix rewrite alone can authorize these operations safely.
4. Test direct application, session HTTP and key HTTP outcomes, then MCP parity for
   its finite tool set. Use local fake credential validators and call adapters.
5. Inspect rendered UI network requests to prove product requests use canonical
   routes. Search for `/admin/api`, server-generated artifact URLs and fetch wrappers
   again; remaining matches must belong to this helper list or compatibility tests.

Rejected alternatives are keeping independent browser/machine controllers, treating
all old Console routes as private helpers, and granting every platform key every
browser privilege merely to simplify routing. Each would undermine the shared
operation/authority contract rather than satisfy the migration.
