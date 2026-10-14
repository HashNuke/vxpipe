# Console sidebar and dashboard

Status: implementation and tenant UI review continuation complete. Production
implementation, rendered browser checks and required verification gates pass. User explicitly
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


## Tenant UI review continuation — 2026-10-13

### Original change requests (verbatim)

> I got change requests for you to complete.
>
> "Create a tenant through the trusted administration workflow, then return here"
>
> In http://localhost:6006/?path=/story/vxpipe-console-tenants-directory--empty
> * Lol if the user has permissions to create tenants, then just let them create tenants. Add a button here to do just that if there are no tenants.
> * And please make the message proper normal english instead of making it sound like a govt process.
>
> I dont think we have a page to create tenants. So we'll have to add that. Please respect the permissions of the user when allowing/disallowing the user to create tenants. If the user cannot create tenants do not even show them a link to the page to create tenants. After tenant creation redirect users to the tenant dashboard.
>
> For http://localhost:6006/?path=/story/vxpipe-console-tenants-my-tenants--my-tenants
> * Why do we have buttons here for Calls, Call Specs and Services. The sidebar already has that right. Are they are better off being stats cards?
> * Why is the mytenants list different from the design for the tenants page. They can be the same design. I like the design for my tenants page. I think the same design can go on the tenants list page. But one thing. The my tenants page tenants list view needs the tenant created date. So I would add a relative date (time ago) like "Created 5y ago" on something like that next to the tenant key.
> * B/w my tenants has a search box. The tenants page has no search box so I would add that one there. I hope the search is a backend search.
> * Also hope the tenants dropdown search in the sidebar is a backend search and not a local search.
>
> We have few pages that have different variables of no-tenants scenario. Which one do we use? Consolidate?
> * http://localhost:6006/?path=/story/vxpipe-console-tenants-directory--empty
> * http://localhost:6006/?path=/story/vxpipe-console-tenants-my-tenants--no-tenant-access
> * This is error scenario - required to mention that retry after storage s available? seems useless.  http://localhost:6006/?path=/story/vxpipe-console-tenants-directory--unavailable
>
> For http://localhost:6006/?path=/story/vxpipe-console-tenants-dashboard--unavailable-dashboard
> * Why do we have a "try again button"? The user can refresh the page. Our app doesnt have to take on browser responsibilies.
>
> Having tenants pages is confusing because some of them have the setup or setup services links (I dont know why we have both) in the table rows. And then we also have some setup card being shown (which now I dont think it's required since we send the user to the services setup page after tenant creation AND also display a "Setup" link in the tenants page row for that tenant - if we consolidate the views).
>
> For http://localhost:6006/?path=/story/vxpipe-console-tenants-directory--empty
> * Why is the dropdown arrow alligned weirdly on the right edge of the dropdown? while the left side of the dropdown and the top and bottom have sufficient padding for the content.
> For http://localhost:6006/?path=/story/vxpipe-console-tenants-dashboard--loading-dashboard
> * Loading calls again... use a skeleton loader please
>
> For http://localhost:6006/?path=/story/vxpipe-console-tenants-setup-overview--demo-nudge
> * I'm confused about this page. Because we have the tenants directory - http://localhost:6006/?path=/story/vxpipe-console-tenants-directory--populated which lists tenants. I dont know how the other view http://localhost:6006/?path=/story/vxpipe-console-tenants-setup-overview--demo-nudge will be used and when.
>
> And these two views conflict too:
> http://localhost:6006/?path=/story/vxpipe-console-tenants-directory--all-tenant-login
> http://localhost:6006/?path=/story/vxpipe-console-tenants-directory--populated
>
> For "The tenant could not be created. Your name is kept here; try again." tenant creation error. WTF is that error. "Your name is kept here; try again" is such a bad error message. "your name is kept here" ROFL.
>
> The stuff here is going to be a lot of change requests. So please add these tasks to a recent milestone doc as is and then turn these into a checklist of tasks to complete. Then implement the changes. Git commit changes frequently as you make progress.
>
>
> For http://localhost:6006/?path=/story/vxpipe-console-tenants-my-tenants--loading-tenants
> * The loading tenants loader can be a skeleton loader please? It's too plain now.

### Design review and execution order

The original milestone used both a legacy table/overview and the new navigation
workspace list in Storybook. Consolidate on the workspace list and reuse its
presentation in production and stories. Preserve distinct no-access, empty,
search-empty and unavailable states inside that one surface. Existing backend
scoped tenant search serves the directory and sidebar picker; verify its request
and storage contracts rather than replacing it with local filtering.

Creation adds an authorized tenant-create API and a dedicated
`/tenants/new` form. Hide links without `tenants.write`, guard direct route access,
and retain backend enforcement. The explicit post-create request takes precedence
over the later reference to service setup: redirect to the tenant dashboard.
Use one permission-aware Setup link to Services; remove redundant setup cards and
legacy overview stories. Dashboard shortcut buttons are removed; do not invent
statistics from incomplete or unauthorized data.

- [x] Checkpoint G: authorized creation page, direct-route/API permission tests,
  dashboard redirect, normal creation/error/empty copy.
- [x] Checkpoint H: one tenant list design for Tenants/My tenants/legacy entry
  points; relative created date beside key; permission-aware Setup link; backend
  search and pagination in both lists and the picker verified.
- [x] Checkpoint I: consolidate empty/error states and Storybook variants; remove
  obsolete setup overview/card and duplicate shortcuts; skeletons for tenants
  and dashboard/calls; correct picker chevron spacing; remove retry buttons from
  requested page errors.
- [x] Checkpoint J: rendered desktop/mobile/theme/permission checks; focused
  and full frontend/backend gates; docs/index synchronized; final clean commit.

Review: dependencies exist for authentication and scoped search; tenant creation adds a new API,
and canonical dashboard routing. Creation-only custom roles require explicit
consideration so a successful create does not redirect to an inaccessible tenant.
Approved clarification: creation-only roles see tenant identity, with no resource
links or data. Installation tenant-write grants directory/dashboard metadata
visibility without granting Calls, Call Specs, Services or API Keys access.
List Setup links must use effective service-write capability, not directory
visibility. Relative dates use real created timestamps; full dates remain
available. Stories simulate APIs, while production must issue server queries.

Implementation evidence for G–I: the dedicated creation route and API are committed
in `61b463ec`. Shared tenant rows now power the canonical directory, My tenants,
and sample setup's compatibility presentation. Legacy browser entry points
redirect to the canonical directory. Backend directory results project effective
Setup capability; the directory and picker retain scoped server search. Retired
Setup overview and duplicate All Tenant Login stories; creation lives under
Tenants / Create. Skeletons replace plain list/dashboard loaders. The shared
picker has symmetric 12px horizontal padding in the rendered directory.

Focused endpoint tests pass (14), including creation-only identity and Setup
membership caps. Frontend suite passes (719), TypeScript and ESLint pass, and
Storybook builds. Final gate resolution is recorded below.

### Continuation acceptance evidence

- 719 frontend tests; TypeScript and ESLint pass. Storybook static build passes.
- Required root format, compile-with-warnings-as-errors, strict Credo and unused
  dependency checks pass. Full umbrella test run exercised 3,782 tests (132
  excluded); its only remaining failure was an older exact-response assertion
  missing `can_setup`. Updated that assertion; root `mix test --failed` passes,
  followed by all 300 Console tests passing (16 excluded). No runtime change
  followed the full run. Other umbrella applications passed in that run.
- Headless Chrome checked desktop/mobile creation and directories, light/dark
  themes, long content without horizontal overflow, empty/loading/error states,
  and denied/creation-only roles. Creation-only dashboard shows identity without
  resource links or data. Storybook stays on port 6006.
- No live provider requests or provider credentials were used. Storybook data
  remains synthetic; production search and permission boundaries are covered by
  frontend request and backend endpoint/persistence tests.
- Checkpoints committed as `61b463ec` and `35d16368`; the final acceptance commit
  carries the corrected API assertion and documentation. User review remains
  distinct from these engineering checks.


### Tenant presentation follow-up — 2026-10-14

Approved UI simplification supersedes the row identity/Setup presentation above:

- [x] Remove tenant keys and Setup actions from Tenants and My tenants rows;
  show name and created age, with consistent alignment.
- [x] Show only tenant name in the context heading above Dashboard/resource pages.
- [x] Remove horizontal padding from recent-call rows to align with the heading.
- [x] Use “Give your tenant a name” as the creation field label; remove subheading.
- [x] Complete required checks and record the follow-up checkpoint. All five
  umbrella gates passed; frontend 719 tests, focused follow-up 33 tests,
  TypeScript, ESLint, and desktop/mobile browser inspection passed.

The backend permission/search contracts remain unchanged. The current UI reaches
Services through the sidebar. Evidence: [follow-up labnotes](../20261014-0516-simplify-tenant-rows.md).

## Calls list follow-up — 2026-10-14

Approved review requests: searchable call-spec dropdown within the tenant;
combine call ID and call-spec name/revision under “Call info”; replace relative
creation age with finalized duration below the absolute local timestamp.

Design review: keep the existing Calls permission for this lookup rather than
requiring Call Specs access. Search storage before pagination to include specs
outside the initial 100. Use recorded start/end times rather than elapsed age;
missing or unfinished durations remain unknown. Keep filtering and call-list
pagination independent. No prerequisite milestone change is needed.

- [x] Add tenant-authorized, paginated backend call-spec choice search.
- [x] Connect the searchable picker with loading, empty, error, and Load more states.
- [x] Merge call identity and spec name/revision; display compact finalized duration.
- [x] Inspect desktop/mobile Storybook, including themed popup and selection.
- [x] Finish required gates and commit the coherent Calls checkpoint. Five umbrella
  gates passed (3,785 tests); frontend 728 full-suite tests, final focused tests,
  typecheck, lint and desktop/mobile browser verification passed.

Evidence: [Calls follow-up labnotes](../20261014-0528-refine-call-directory.md).
