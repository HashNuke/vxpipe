# Console sidebar and landing

Status: production routing, shared sidebar and scoped navigation/search/dashboard
APIs are implemented. Final verification is tracked in the milestone; user UI
review is deferred until completion and has not been recorded as acceptance.
The [milestone](../labnotes/milestones/console-sidebar-and-dashboard.md) owns tasks
and acceptance. The existing [authorization contract](console-authentication-and-authorization.md)
remains authoritative. This extends the Operator's Bench visual system.

## Experience

A sticky, 232px-wide left rail holds Vxpipe, immediately followed by a searchable tenant
picker. Tenant links are Calls, Call Specs, Services; Platform links are Tenants,
Roles, Users, Services. My account and Logout stay at the bottom. Omit destinations
without effective permission and omit empty groups. The selected tenant label
links to its dashboard; the picker always switches to `/t/:tenant/dashboard`.
The picker footer links to the appropriate directory, including My tenants for
assigned users, without adding an extra top-level item to the requested menu.

Content has one clear page title and its local actions. Remove global headers,
account bars and sibling navigation from ordinary pages. Tenant resource pages
retain a compact linked tenant name/key context above their page title.
Keep local form back links, filters, setup steps and modal headings. Tenant
services is titled **Services**; platform services is **Platform Services**.
A phone uses a compact Menu trigger and a modal navigation drawer with the same
order; Escape, selection and dismissal close it and restore focus.

The tenant dashboard shows tenant identity, permitted destinations and recent
calls if calls.read is allowed. It does not invent aggregate counts, billing,
provider health or cross-tenant statistics. Hide inaccessible sections rather
than rendering unauthorized data. Empty, loading, unavailable and no-access
states are distinct. Call spec editor and call transcript/history inspector
remain standalone, including their loading/error views and working return links.

## Landing and authority

For authenticated `/`, decide on the server using a freshly resolved principal:

1. `visible_tenant_scope == :all` → `/tenants`, even with zero or one tenant.
2. Exactly one extant authorized tenant → `/t/:tenant/dashboard`.
3. Zero or multiple extant authorized tenants → `/my-tenants`.

Use `Vxpipe.Calls.UserAuthorization.visible_tenant_scope/1`, not role names,
assignment counts, a page of results, or installation-wide counts. All-tenant
means effective tenant grants, including custom/mixed roles; `tenants.read` alone
currently does not confer tenant-resource access. Preserve this distinction.
Memberships alone confer no access. Only stored, extant, authorized tenant rows
count. A zero-tenant user can still use account and permitted platform resources. When
there is no tenant-directory grant at all, navigation returns directory_access=false
and the My tenants page renders the authoritative empty state without a directory
request. Preserve the existing directory authorization boundary.
A directory database failure is unavailable with Retry, never zero access.

Roles is visible only to built-in Admin/Superadmin under the current role API.
Users requires users.read. Platform Services requires platform_services.read.
Tenant Calls and Call Specs require their own read grants. Services admits either
tenant_services.read or tenant_api_keys.read, rendering only allowed subsections;
credential metadata and mutations retain their independent API-key permissions.
Read/write membership caps and built-in privileged-user restrictions are unchanged.
The UI hides writes without write authority; every request is reauthorized server-side.

## Backend API contracts

Keep `/admin/api` as the authenticated JSON boundary. Page URL cleanup does not
require renaming API routes. Console owns HTTP/presentation; Calls owns tenant
lookup and scope filtering; Identity owns principal/grants and revocation. Add
small projection/query modules rather than expanding App.tsx or controllers.

| Endpoint | Implemented contract |
| --- | --- |
| `GET /` | Browser pipeline: setup/login gate when anonymous; 302 to computed landing when authenticated. `Cache-Control: private, no-store`; never cache user-specific redirects. |
| `GET /admin/api/navigation?tenant=:key` | Authenticated shell bootstrap. Returns `landing_path`, `directory_path`, `tenant_scope` (`all`/`assigned`), actor public fields, `directory_access` boolean, platform destinations, optional selected tenant `{key,name,dashboard_path}` and per-resource read/write capabilities. No credentials, session tokens or unauthorized tenant metadata. Optional tenant independently checked; unknown/foreign uses identical 404. No bulk tenant list. |
| `GET /admin/api/tenants?q=&page=1&page_size=25` | Existing directory extended for the picker and full directory. Trim q, max 120 Unicode characters; literal case-insensitive name/key search; validate positive page and page_size 1–50. Stable name/key ordering; filter permission scope before search, count and pagination in the persistence query. Return `tenants:[{key,name,dashboard_path}]`, `pagination:{page,page_size,total,total_pages,has_next}`. Empty authorized scope returns 200 empty; a principal with no directory grant retains 403; backend failure 503, invalid query 422. Page beyond last returns 422, UI resets to first after query/access change. |
| `GET /admin/api/tenants/:key/dashboard` | Authorize tenant identity before response. Return `{tenant:{key,name,dashboard_path,capabilities},recent_calls}`. `recent_calls` is omitted without calls.read; otherwise `{status:"ready",calls:[...]}`, bounded to 5, newest first with stable ID tie-break. Reuse Calls directory projection, not a new global aggregate. A failed section is `{status:"unavailable"}`, never fabricated zero. No spec-directory/service reads are performed. |

The navigation projection and browser redirect share one Calls query contract:
resolve visible scope plus at most two authorized extant tenants to distinguish
zero/one/many. All-scope needs no count query. Do not load the whole directory or
perform one authorization query per row. Paginated queries must intersect scope
before data leaves persistence. Escape SQL wildcard characters or use a literal
substring implementation; parameterize all queries. Keep totals scoped and page
size bounded. Avoid nesting synchronous process calls for this projection.
Search rejects invalid UTF-8 and NUL characters with 422. Page numbers are bounded
to 1–2,147,483,647 so a parsed integer cannot overflow the persistence offset type.
The 120-character limit applies after trimming and counts Unicode characters.

401 means expired session: clear user/tenant caches and return to login. 403 is an
explicit action denial; 404 conceals unavailable/foreign tenant identity. On
permission/tenant loss, cancel pending queries, discard old tenant data and
reload navigation; land via the new server decision. Requests carry AbortSignal
and a tenant/query generation guard so late responses cannot replace a newer
selection. Search uses a short debounce; its loading, no matches, unavailable
and retry states retain the search term. Keyboard selection and mouse selection
have the same destination. Do not persist a last-tenant choice that overrides `/`.

Protected page entry records its path and supported query parameters in the signed
session before redirecting to login. Login preserves that return path; authenticated
root consumes it after checking same-origin syntax and page permission, otherwise
using the fresh navigation landing. The destination route/API independently checks
tenant existence and resource access. Scheme-relative URLs, external schemes,
backslashes and line breaks are rejected. Explicit authorized deep links survive
refresh; root landing rules do not replace them. Logout is
an existing CSRF-protected POST; no GET logout route. Clear caches after success.
Dashboard and shell do not change gateway tokens, recordings or provider APIs.

### Implemented JSON shape

The navigation projection carries `actor:{id,kind}`, with account display data
remaining available from the existing session endpoint. `platform_destinations`
contains permitted `{id,label,path}` entries in menu order. `tenant` is null
without a selection, otherwise `{key,name,dashboard_path,capabilities}`. Capabilities
are `calls`, `call_specs`, `services`, and `api_keys`, each with independent boolean
`read` and `write` fields. Services navigation admits either services or API-key
read access; a false subsection capability must omit that subsection entirely.
No full role assignment or tenant directory is embedded in this response.

Directory results retain `created_at` for existing consumers and add
`dashboard_path`; pagination adds `has_next` while retaining existing fields.
Installation-operator domain listing keeps its older contract and ordering;
browser directory and picker use the scoped alphabetical search query. New optional
repository callbacks are `search_tenants/5`, `tenant_candidates/3` and `recent_calls/3`.
Adapters without these callbacks return unavailable for the new workflows, without
falling back to unscoped reads. The PostgreSQL adapter implements all three.

## Browser routes and compatibility

Canonical pages: `/tenants`, `/my-tenants`, `/t/:tenant/dashboard`,
`/t/:tenant/calls`, `/t/:tenant/call-specs`, `/t/:tenant/services`, `/roles`,
`/roles/new`, `/roles/:id`, `/users`, `/users/new`, `/users/:id`,
`/users/:id/reset-password`, `/account`, `/platform/services`, `/getting-started`.
Auth routes remain at `/auth/*`. Console.Router registers explicit canonical
browser routes ahead of page fallbacks.
GatewayMount runs first but claims only health/API/webhook paths, passing `/` and
the new browser paths through. Keep that ownership unchanged and test it.
Old `/admin`, tenant, user, role and service page URLs redirect to canonical
counterparts after authentication. Preserve supported pagination/filter query
parameters. `/admin/tenants/:key` maps to dashboard. Never redirect API, asset,
websocket, recording/publication or provider callback URLs. Keep existing editor
and call inspector deep links during the first cutover; update return links to
canonical destinations. Validate tenant keys once, URL-encode segments, reject
malformed/foreign keys without reflecting secret resource metadata.

## Page/header inventory

Reviewed router, Endpoint, App, ScopedServicesApp, AdminShell, AccessFrame,
TenantWorkspaceNavigation and all TSX header uses (including Storybook-only pages).

| Surface / source | Implemented treatment |
| --- | --- |
| `/admin`; TenantsPage, TenantSetupOverview | Shared sidebar; Tenants or My tenants; rows open dashboard. Authorized operators reach tenant creation through Getting started. |
| TenantCallSpecsPage | Sidebar + Call Specs title; retain New, row editing and call filters. |
| CallSpecCallsPage (all calls and spec-filtered) | Sidebar + Calls title; keep spec filter, reset, pagination and standalone inspector links. |
| ScopedServicesApp + TenantSetupPage, tenant | Sidebar + Services; remove repeated Tenant created banner on steady-state service view. Keep inherited/overridden bindings and dialogs. |
| ScopedServicesApp + TenantSetupPage, platform | Sidebar + Platform Services; remove platform breadcrumb/header buttons. |
| Legacy TenantServicesPage | Sidebar + Services; preserve service inventory, telephony applications and credential form. No duplicate tabs/header. |
| AccountPage | Sidebar + My account; password/current-password and session behavior preserved. |
| UsersPage, UserEditorPage (new/detail), ResetPasswordPage | Sidebar with Users active; keep local back links, role/tenant dialogs, restrictions and form notices. |
| RolesPage, RoleEditorPage (new/detail/built-in) | Sidebar with Roles active; keep read-only built-ins, permission editing and deletion constraints. |
| AuthenticationJourney/AccessFrame | Authenticated pages use shared shell; setup/login/recovery remain public standalone with brand, no private picker/menu. |
| OnboardingPage `/admin/onboarding` | Redirect to `/getting-started`, with shared shell and permission-gated setup content; the directory exposes its contextual link. |
| OnboardingStory: services, platform, tenants | Apply same shell/title treatment; preserve modal and pending/error states. |
| ApiKeysSetupPage, SampleRecipesPage | Storybook-only setup presentations retain the shell and local titles. No new production API-key-setup or recipe route is introduced; production Services retains its existing credential workflow. |
| CreateTenantModal, ServiceSetupModal, SetupDialog | Modal titles retained; background sidebar inert while modal is open. |
| Call spec new/editor, editor-header, toolbar | **No sidebar**; retain specialized authoring controls and return link. |
| CallDetailsPage/CallDetailsConsoleHeader, publication/history preview | **No sidebar**; retain inspector context, call identity and return links. |
| Pipecat sample App, TransferPage sample header | Voice and transfer samples use the shared sidebar with full-document navigation; in-call media controls remain local. Existing sample permissions remain; no new main menu item. |
| DiagnosticsLive / DiagnosticsLayout | Shared React navigation island with diagnostics.read gate; LiveView retains ownership of its panels and DOM. Full-document navigation leaves the island correctly. LiveDashboard retains its dependency-owned UI. No diagnostics menu item added. |
| HomePage (legacy module; no current `/` router entry) | Authenticated root landing is handled by ConsoleLandingController; setup and samples retain contextual entry points. |
| OperatorLoginPage / legacy sign-in guidance | Public legacy guidance stays standalone; do not expose authenticated navigation. |
| ThemeCheck, component stories, ledger/modal headers | Development/component content, not page navigation; retain local headings. |

## Decisions and alternatives

Use one sidebar and capability projection instead of independent headers and
frontend role-name checks. Keep selected tenant visible while browsing platform
pages, but make platform scope obvious in the page title; direct platform entry
starts without a selected tenant. Do not preserve the old leaf on tenant switch:
the dashboard avoids landing on an action the new tenant does not permit.
Keep specialized workspaces full width. Reuse existing components and fixture
content in Storybook; this prototype makes no backend or live provider requests.
Do not implement speculative analytics just to fill the dashboard.

## Direction contract

THESIS: One persistent navigation rail anchors tenant work and platform administration.
OWN-WORLD: Existing neutral Operator's Bench, Inter controls, shallow corners, restrained dividers.
STORY: Identify scope, choose tenant, enter permitted work, return to account.
FIRST VIEWPORT: 232px rail; searchable picker below logo; page title and actions above a wide working surface. Recent calls lead the dashboard.
FORM: User-specified sidebar order; local extension, no concept seed required. Production extends the reviewed Storybook surface.
FINISH: Record production implementation in DESIGN.md, its sidecar and the surface
brief; keep automated and rendered verification evidence in the milestone and
labnotes. User review follows completion. No new raster assets are introduced.

## Integration decisions and verification boundary

`ConsoleNavigation` owns shell loading, navigation projection, session expiry and
logout. It refreshes authority on window focus; selected-tenant loss clears the
selection and reloads the server-selected landing. Directory and picker use
separate query hooks over the same scoped API, with request cancellation and
late-result guards. Dashboard data is checked against the current tenant before
rendering. A failed call section is retryable without presenting a fabricated zero.

Diagnostics uses an independent `navigationMain.tsx` React island instead of
reparenting LiveView nodes or duplicating permission logic in a server-rendered
rail. The external island host has zero minimum height, its desktop rail is fixed,
and the server content receives a 232px offset that disappears at 760px. This
preserves LiveView patch ownership and keeps the mobile panels directly below
Menu. Voice and transfer samples also use full-document destination changes.

Tailwind's compiled administration stylesheet is `admin-ui.css`; esbuild's CSS
bundle remains `admin.css`. Separate outputs prevent one build from overwriting
the other. Admin and diagnostics HTML load the Tailwind asset explicitly.

Storybook remains the synthetic visual-state lane, while production screenshots
and endpoint/frontend/persistence tests exercise the integrated path. The task
labnotes and milestone record actual results and unresolved gates. This decision
describes implemented behavior; it does not claim pending tests passed, user UI
acceptance, or provider-live acceptance.
