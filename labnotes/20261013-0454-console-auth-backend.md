# Console authentication backend

The user authorized the full backend milestone and deferred UI review. Storybook
and its planning documents were committed first as `3f61e2a6`, with no backend
files in that commit. No further commit has been requested.

## Route inventory and first behavior test

- Inspected the Console router, browser/session plugs, diagnostics auth, Gateway
  mount, existing endpoint tests and Calls operator authority. Most browser JSON
  controllers still construct `InstallationOperator.authority()`, so a router-only
  guard would not enforce tenant permissions at the domain boundary.
- Recorded the action/owner map in
  [Console route inventory](../docs/console-authentication-route-inventory.md).
- Added a focused failing Console test for exact route-to-permission mapping,
  then implemented `RoutePermission`; three tests pass. Corrected a test that
  initially marked an explicit sample route unknown. The mapping is not yet
  wired into authorization and does not claim runtime security.

## First integration checks

- Added a Console facade that fails closed without configured Identity ports,
  and an opaque cookie-session helper. Focused tests were red before each
  implementation and then passed.
- Added public `/auth/api/status`, `/auth/api/setup` and `/auth/api/login`
  endpoints. The endpoint tests failed with 404 before the routes existed;
  after implementation the only failure was an overbroad test assertion that
  inspected request parameters stored in `Plug.Conn`. The response body itself
  does not include the password; corrected the assertion accordingly.
- Added `/admin/api/users`, `/admin/api/roles`, minimal role-filter options,
  account self-service, named-session details and target-aware guards. The
  protected Console and diagnostics HTTP/WebSocket paths now resolve the
  database-backed named session. Focused Console endpoint tests cover setup,
  account/role actions, logout failure, and diagnostics. The real database
  endpoint test proved upgraded setup, immediate named login, setup replay
  rejection, password-change session revocation and new-password login.
- Replaced `mix vxpipe.login`'s retired browser challenge with a one-time local
  setup proof for upgraded installations; its focused task test was red before
  the change and passed afterward. Local recovery of an already completed
  installation remains to implement.
- The first full Console suite after route cutover had 84 failures, primarily
  old endpoint fixtures signing in through `/auth/login-token`. A scoped
  teammate pass is migrating those tests to named sessions; none of the old
  browser login routes were reenabled. A real HTTP test additionally exposed
  that Admin could not create an ordinary user because `create_user` checked
  the actor's protected kind as if it were the target; this remains open in
  the Identity follow-up.
- Independent Identity review found exact-key account authorization, stale
  privileged-target writes, role-scope validation, session revocation and
  builtin-grant defects. A red-green teammate fix pass is underway; the
  subsequent review will check remaining audit/recovery behavior. Calls review
  likewise found editor lookup and scoped-service visibility gaps; a second
  follow-up pass is underway.
- Replaced the custom user-directory ARIA grid with the existing shadcn Table
  primitive. A focused test failed on the original `DIV` table and passed on a
  semantic `TABLE`. Chrome Storybook inspection at 1280× and 390× found a
  narrow phone column caused by desktop width rules; adjusted the mobile
  widths and rechecked. The final 390px view has no horizontal page overflow.
- User review asked for a modal tenant picker, consistent Users page width,
  arrowed back links, less repetitive tab headings, and removal of the
  account-management explanation. Added a focused red-green dialog test and
  moved Add tenants into the existing shadcn Dialog, retaining assigned rows
  on the user form. Chrome Storybook inspection at 1280px and 390px verified
  the dialog and the shared 1200px outer page width; the reset form remains
  590px within it. The mobile dialog footer needed an explicit row direction.
- Calls review found the carrier number lookup was accessible with
  `call_specs.read`; a focused Calls test reproduced it. Console now maps that
  route to `call_specs.write` (red-green RoutePermission test). A teammate is
  fixing the Calls boundary and a separate credential/service pagination
  regression. This authority applies to authoring lookup, while provider and
  model browsing require `call_specs.read`.
- Removed Platform Manager, Call Reviewer and Directory Reader from Storybook
  seed fixtures and actor controls. The four initial role examples are now
  Superadmin, Admin, assigned-tenant Tenant Manager and read-only Tenant
  Member. A focused fixture test failed before the change and passed after;
  the authentication component suite passed 37 tests. A Chrome Storybook
  snapshot showed only the four role filter choices and no duplicate Users
  heading. The production frontend test suite also passed its 16 auth cases
  after updating assertions for the tab-level heading change.

## Final integration and independent review

- Implemented the local recovery page/API and `mix vxpipe.recover`: a distinct
  15-minute, one-use proof resets an existing Superadmin, revokes old sessions
  and signs in the recovered account. Real-database HTTP tests cover replay,
  target restrictions and immediate replacement-password login.
- User clarified Tenant Manager includes all assigned-tenant operations. Added
  assigned service/key read/write grants and platform-reference authoring, with
  Tenant Member remaining call/spec read only. Migration 004 preserves custom
  role definitions, converts old installation tenant-operation grants to
  all-tenant scope, and refuses destructive automatic rollback.
- Independent Calls review found tenant-directory policy drift: service/key
  all-tenant roles were incorrectly denied, and a bare assignment could pass
  the HTTP guard. Red-green tests now prove a shared effective directory
  policy, empty results for unassigned roles, storage-side scope filtering,
  and denial of stale scopes without registered grants.
- Independent frontend review found a new custom role could not create mixed
  read/write scopes. The editor now keeps separate controls whenever both
  grants exist. A blank-role test failed before the fix and passed after it.
  Platform-authoring remains installation-scoped as other scopes change;
  assignment write controls depend only on assigned-scope write grants.
- Setup now passes the remote client address through to Identity throttling
  and returns 429 for throttled attempts. The endpoint test was red (422) and
  then green. Plug sets Secure for HTTPS cookies; transport policy denies
  public HTTP. The identity reviewer withdrew a cookie false-positive after
  verifying Plug's implementation and the existing secure-cookie test.
- Acceptance audit found connected diagnostics were checked only on mount.
  Lifecycle hooks now reauthenticate before info/event/parameter callbacks,
  preventing refresh or fixture mutation after revocation or storage outage.
  The focused Console suite passed 12 tests, including red-green revocation
  tests. An independent reviewer checked the implementation.
- LiveView's upstream mount logger inspected the whole session without Phoenix
  parameter filtering. Console now replaces only its mount-start telemetry
  handler with a session-redacting delegate. Capture-log tests cover both the
  diagnostics view and dependency-owned LiveDashboard while retaining useful
  mount/parameter logging. Independent frontend review found no blocker.
- A missing authentication singleton previously left existing sessions usable.
  A red test reproduced it; Persistence now requires completed setup when
  creating/resolving sessions. Acceptance tests cover normalized duplicate
  emails, lost setup-response replay and concurrent last-Superadmin demotion.
- Disposable migration tests cover empty, tenant-only and populated pre-auth
  databases, preserving tenants/specs/demo/API keys/operator keys. Historical
  challenge rows are preserved but their retired browser routes reject use.
  Separate BEAM invocations verify setup durability, login and replay after
  restart. The first migration lane run passed 3 tests; focused Persistence
  authentication coverage passed 48 tests.

## Rendered browser and final checks

- Built Console assets and Storybook, then inspected recovery and the Add tenants
  dialog in headless Chrome at 1280×900 and 390×844. The modal stays within the
  phone viewport, supports keyboard focus, and leaves assigned rows on the
  stable-width user form. The final mechanical detector returned `[]`.
- Started a separate Console on a disposable database. First-run setup created
  the initial account/session without any demo tenant. Real browser operation
  exposed a CSRF renewal issue: SPA navigation after login retained the old
  page token, so the next POST failed. A red-green frontend fix now loads a
  fresh document after setup/login/recovery; the next real protected write
  succeeded. Logout already performed a full document navigation.
- Real browser checks created a Tenant Manager, assigned the Demo tenant via
  the dialog with Read & write, saved, reset its password without email and
  confirmed success without changing the acting Superadmin's identity.
- Frontend: 664 tests across 83 files, TypeScript and ESLint pass. Console and
  Storybook builds pass. Latest auth redirect focused tests: 47 pass. Root
  format, compile-with-warnings-as-errors, strict Credo and unused-dependency
  checks pass. Full umbrella confirmation is still running at this checkpoint.
- One umbrella attempt hit an existing request-deadline test timeout and later
  terminated during application shutdown before remaining apps ran. Its focused
  recheck passed 2 tests; a fresh umbrella run passed all 108 AgentRuntime tests.
  Final full-run evidence will be appended after completion; do not infer full
  acceptance from the interrupted run.

- Final cross-BEAM acceptance passed: a long-lived VM first authenticates a
  session, a separate VM revokes it, and the original VM returns revoked on
  its next explicit request. Four disposable integration cases pass; the
  separate acceptance labnote records exact commands and cleanup.
- Real Console browser verification found a CSS build collision missed by
  Storybook: the JS import of authentication CSS caused esbuild to overwrite
  the Tailwind-owned admin.css. Moved the import into the main admin stylesheet
  and removed the component import. The standard `mix assets.deploy` now
  preserves both styles; desktop reset and phone protected-account captures
  show the expected fonts, controls and stable page width. Independent review
  confirmed both production and Storybook consume the main stylesheet.
- In separate real browser sessions, Tenant Manager logged in with the manually
  reset password and saw only its assigned tenant, with call-spec creation and
  Services available. A second reset invalidated that open browser session;
  the next request redirected to login. Admin's role filter showed Superadmin,
  and that account's phone details page had no save/reset/role mutation controls.
- The confirming umbrella run exposed an existing transfer-test race: the room
  replies to a failed handoff before completing its synchronous provider
  release. The assertion read provider state too soon. Added a test-only
  `:sys.get_state(authority)` synchronization point before inspecting that
  state. The focused file passes all 6 tests; no speech state-machine source
  changed, so the Lean lane is not applicable to this fix.
- Final standard `mix assets.deploy` and Storybook rebuild pass. Final root
  formatting, warnings-as-errors compilation, strict Credo and unused-dependency
  checks pass; documentation links and `git diff --check` pass. The temporary
  real-browser Console/database was stopped and removed after verification.

## Completion evidence

- The confirming umbrella run completed all ten apps: 3,749 tests, with only
  the already-corrected transfer synchronization assertion failing in the
  earlier-loaded test module. The final root `mix test --failed` exited 0
  with that test passing and no other failures to rerun. Console passed 285,
  Persistence 270, Calls 177 and Identity 58 cases. The 132 excluded cases
  remain the repository's explicit integration/live lanes; the new disposable
  Identity lane was separately run with all four cases passing.
- All required root static checks pass. Frontend passed 664 cases; TypeScript,
  ESLint, production assets and the final Storybook build pass. Documentation
  links and whitespace checks pass. Three independent reviewers found no
  remaining concrete blocker in their final passes.
- Engineering milestone/index marked complete. User UI review remains deferred
  as explicitly requested. Existing Storybook commit `3f61e2a6` is preserved;
  no backend/additional UI commit was made. Completion notification is sent
  separately through the user-authorized pushnotify CLI.

## Commit preparation

The user requested committing the completed milestone after acceptance. Reviewed the
working tree and exact staged paths, retaining implementation, focused tests, migrations,
lockfile, documentation and checkpoint labnotes together. Removed machine-local temporary
paths from two review notes. No runtime changes were made during commit preparation.
