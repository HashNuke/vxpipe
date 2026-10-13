# Console sidebar and dashboard

Status: complete. Production implementation, browser acceptance, independent
review fixes and all required verification gates pass. User explicitly
authorized the entire milestone on 2026-10-13 and will review the completed UI.
No intermediate UI approval or commit is required.

## Prerequisites and design sources

Read [Console authentication and user management](console-authentication-and-user-management.md),
[Call spec editor](call-spec-editor.md), [Tenant Call Specs and API keys](tenant-call-specs-and-api-keys.md),
and [Platform and tenant services](platform-and-tenant-services.md). Authentication,
existing tenant scope enforcement and resource pages are available. Unfinished
onboarding is covered for layout compatibility, not an implementation dependency.
The [navigation decision/API contract](../../docs/console-sidebar-navigation.md)
and [authorization design](../../docs/console-authentication-and-authorization.md)
define the implemented contracts. The user deferred UI review until completion.

## Checkpoint A — Reviewable proposal

- [x] Inventory every current page/header, including specialized exemptions and auxiliary pages.
- [x] Specify routing precedence, no-access behavior, custom/mixed permissions and API ownership.
- [x] Build connected Storybook sidebar, searchable picker, landing cases and dashboard.
- [x] Present every affected page family with both themes and phone navigation.
- [x] Review design, code and API contract; record findings separately from implementation.
- [x] Run focused behavior tests, frontend checks and rendered browser inspection.
User review is a post-completion handoff, explicitly deferred by the user.

## Checkpoint B — Server navigation and scoped search

- [x] Red: test built-in/all/mixed/assigned permissions; 0/1/many extant tenants;
  deleted/stale assignments; one visible tenant on a larger paginated directory.
- [x] Add shared landing query and navigation projection with exact resource capabilities.
- [x] Extend directory query with scoped bounded search/pagination; server totals exclude
  foreign rows. Test literal wildcards, malformed input, stable ordering and no metadata leak.
- [x] Test 401, 403, concealed 404, unavailable 503, empty scope and permission revocation.
- [x] Green/refactor: focused Identity/Calls/Console suites plus root checks.

Evidence: [backend labnote](../20261013-1101-sidebar-navigation-backend.md). All five
umbrella gates pass; full suite has 3,770 tests, zero failures, 132 exclusions.
The final query-bound correction has an additional passing focused run. Frontend
adapter/parsers are ready for integration; all 688 frontend tests and both builds pass.
Browser API smoke confirms unauthenticated 401/no-store on the real local Console.

## Checkpoint C — Canonical routes and landing

- [x] Red: authenticated `/` redirects; anonymous setup/login; valid deep-link return;
  reject external redirects. Include root gateway mount precedence.
- [x] Add canonical browser routes, login landing response, old-page redirects and
  no-store headers. Keep JSON/assets/callbacks/recordings outside redirects.
- [x] Verify reload/back/forward, filters and auth expiry without loops.
- [x] Green/refactor: controller/route tests and focused frontend navigation tests.

## Checkpoint D — Sidebar and picker

- [x] Red: server projection determines groups/links; forbidden links absent; no private
  directory fetched before login; membership write caps and API-key-only Services work.
- [x] Integrate one shared shell, searchable paginated picker and account/logout controls.
- [x] Cancel stale searches/tenant loads, guard late results, reset on session/access loss.
- [x] Keyboard selection, Escape/focus restore, mobile modal/inert background, long labels,
  pending/no matches/unavailable/retry and empty directories.
- [x] Green/refactor: focused component/journey tests and rendered desktop/phone checks.

## Checkpoint E — Dashboard and complete page migration

- [x] Red: dashboard only queries authorized bounded recent calls; inaccessible sections
  omitted; partial error distinct from empty; tenant identity reauthorized.
- [x] Build dashboard with existing Calls projection and contextual permitted links.
- [x] Migrate every row of the decision's page inventory; record each verified route.
  Include users/roles forms, password reset, account, both Services titles, legacy services,
  setup/API keys/recipes, sample launchers and diagnostics shell.
- [x] Keep editor and transcript/history/publication preview sidebar-free in every state.
- [x] Preserve forms/modals, page filters, pagination and direct URLs; remove redundant
  global headers and horizontal navigation, retain local task titles/actions.
- [x] Green/refactor: page tests and bounded rendered desktop/phone light/dark review.

## Checkpoint F — Acceptance and documentation

- [x] Review implementation against API contracts and full page inventory; correct findings.
- [x] Run format, warnings-as-errors compile, strict Credo, umbrella tests, unused-lock check;
  frontend tests, typecheck, lint and Storybook/Console builds. Lean only for state-machine changes.
- [x] Manual real Console: log in as one/many/all/zero-tenant users; search/switch tenant;
  inspect custom/mixed scopes and live permission loss; account/logout; refresh deep links.
- [x] Document canonical routes and update DESIGN.md after accepted UI integration.
- [x] Synchronize acceptance evidence and index. Commit only if user asks.

## Specification review

Initial local review 2026-10-13: checked dependency order, page coverage, actual
`visible_tenant_scope/1`, role API restrictions, tenant-service/API-key split and
root mount ownership. Corrected the tempting but incorrect assumption that
installation `tenants.read` alone grants all tenant-resource access. Navigation
and backend authorization share the effective scope contract. Added zero-tenant,
partial dashboard failure, stale response, revocation, legacy routing and query
bounds to prevent an attractive shell from concealing missing contracts.
Independent finish review identified phone dashboard visibility, mutation permissions,
Services footer and credential subsection permission defects. Regression tests and
rendered corrections resolved all findings; the final verdict was `ship` for that
fix list. The generic fresh agent used the skill's degraded reviewer contract because
the named role was unavailable. Static design detection returned no findings.

Proposal verification: 18 focused navigation tests and all 682 frontend tests pass;
TypeScript, lint, Storybook and Console builds pass. All five umbrella gates pass,
including 3,749 tests with no failures (132 excluded). Chrome inspection covered
desktop/phone, both themes, searchable selection, focus restoration and logout.
See the [review guide](../../docs/development/sidebar-navigation-storybook.md) and
[checkpoint labnote](../20261013-1023-sidebar-dashboard-proposal.md).
These totals describe the proposal checkpoint; production evidence is recorded below.

## Production acceptance evidence

Canonical endpoint tests verify anonymous/root precedence, all/one/many/zero
landings, concealed foreign tenants, safe signed-session deep-link return, legacy
filters and standalone exclusions. The production App tests exercise real API
adapters for capability-driven links, no-access fetch suppression, key-only
Services, partial dashboard failure, stale searches, revocation and auth expiry.
Four additional red/green tests cover paginated picker reopen/authority changes
and explicit close notifications. The final frontend run passes 703 tests;
TypeScript, ESLint, Console assets and Storybook builds pass. All four backend
static gates pass. No speech/source state-machine changes require Lean.

Chrome desktop/phone inspection covers the complete route inventory and both
existing theme styles. Real one/many/all/zero/key-only/mixed personas received
correct landing paths and scoped lists. Read-only membership hid spec creation;
key-only Services hid provider controls. Membership changes revoked the active
session; reauthentication opened the sole remaining authorized tenant. User
disabling returned the active browser to login. Protected deep-link login and
reload passed. Keyboard search, selection, Escape/focus restoration, account and
logout passed. Editor and inspector rendered without the sidebar.

Independent production review found and corrected diagnostics host sizing and
picker lifecycle defects. Diagnostics recapture confirms visible content at the
viewport top and a connected LiveView at both widths. DESIGN.md, its sidecar,
the surface record and navigation documentation now describe production truth.
The decision's page inventory records route ownership; setup API-key/recipe
presentations that have no existing production route remain Storybook examples.
See the backend/integration labnote for barriers, fixes and full gate outcomes.

Final umbrella repeat: 3,777 tests, zero failures, 132 excluded. The independent
production reviewer returned `ship` for all three recorded fixes after the full
review; no material issues remain. User UI review remains deferred as requested.
