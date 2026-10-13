# Sidebar navigation backend

## Scope and decisions

- Continued the sidebar goal after delivering the reviewed Storybook proposal.
  Backend work proceeds independently of optional layout feedback. Production UI
  cutover is a later checkpoint; no UI acceptance inferred.
- Previous goal turn completed proposal code/review and verification (progress).
  Re-inspected the worktree, routes, authorization and repository ports. Preserved
  proposal changes; no commits created.
- Calls.TenantDirectory owns visible search, extant lookup and bounded landing
  selection; Console.NavigationProjection owns browser paths/capabilities.
- AdminRepository gains optional search/candidate/recent-call operations. Older
  embedded adapters fail unavailable for new workflows; existing installation-
  operator listing remains compatible.
- Persistence intersects scope before matching/counting/pagination, uses literal
  case-insensitive strpos, and orders by lower(name), key. A single search query
  shares the count/page snapshot. Landing reads at most two rows without count.
- Dashboard authorizes tenant identity first, omits calls without calls.read and
  reads at most five rows with timestamp/ID order. Partial failure stays explicit.
  No spec-directory, provider, aggregate or secret reads are needed.

## Red/green evidence

- Persistence tests failed for absent callbacks, then passed. A wildcard test
  initially assumed an empty database; existing keys legitimately had underscores.
  Isolated fixture scope rather than deleting data.
- Domain tests failed for missing TenantDirectory, then passed. Coverage includes
  all-scope precedence, stale assignments, 0/1/many visible rows, invalid bounds,
  foreign adapter rows, empty authorized scope and no-grant denial.
- HTTP tests failed for the missing route, then passed after fresh-principal auth,
  no-store projection and scoped directory wiring. Fixed an anonymous test to use
  HTTPS, matching the existing Console origin boundary.
- Dashboard tests failed for missing domain/store/HTTP methods, then passed.
  Read-only membership caps, key-only access, session/permission revocation and
  partial failure covered. Related Console suite: 12 pass; persistence: 16 pass;
  Calls authorization/directory: 30 pass.
- Boundary review added a red regression for malformed successful adapter payloads;
  now fails unavailable. Warnings-as-errors compile and strict Credo pass. Full
  umbrella verification is running.

## Client contract and final review

- NavigationApi is ready for production-shell integration: typed projection,
  scoped search, dashboard states, AbortSignal forwarding and no-store reads.
  It rejects malformed capabilities, foreign tenant identities, external paths,
  missing/oversized recent-call sections, and keeps 401/403/404/422/503 distinct.
- Six client tests first failed for the absent module, then passed; the related
  adapter/parser run passed 22 tests. TypeScript and lint passed. Shared call-row
  parsing is exported from the existing directory parser rather than duplicated.
- Reviewed existing frontend directory parsers: added dashboard_path/has_next
  fields are compatible; existing created_at/pagination fields are preserved.
- Contract review found query length was checked before trim; a failing Unicode
  boundary test drove correction. NUL/invalid UTF-8 and offsets beyond a bounded
  page range are rejected before persistence. Focused Calls/authorization run now
  passes 31 tests. Root formatting command was briefly invoked from the child with
  root-relative paths; rerun from the umbrella root passed.

## Checkpoint verification

- Full umbrella run completed with exit 0: 3,770 tests, zero failures, 132 excluded.
  Its long gateway lane remained live and finished normally; no restart was made.
  The query-bound correction landed after its Calls lane, so a final root-level
  focused run rechecks Calls, Console and persistence against the final source.
- Final format check, warnings-as-errors compile, strict Credo and unused-lock
  check pass. No speech/source state-machine changes; Lean is not applicable.
- Full frontend suite: 86 files, 688 tests passed. TypeScript, lint, Storybook build
  and Console asset build pass. No dependencies or lockfiles changed.
- Started the local Console in its own tmux session. Chrome via agent-browser
  confirms navigation, tenant search and dashboard endpoints return JSON 401 with
  private/no-store for anonymous requests. Authenticated data/permissions are
  verified by endpoint and real persistence tests, not claimed as browser flows.
- Reviewed authorization ownership, malformed adapter success, bounded/literal
  queries, client parsing compatibility and partial dashboard failures. Findings
  were fixed with red-green tests. Final documentation links and whitespace pass.
- Checkpoint B is complete. Canonical root/login routing, production sidebar,
  live paginated picker, dashboard UI and full page migration remain required.
  Goal remains active; no commits created.

## Canonical routes and production integration

- User explicitly authorized the entire milestone and deferred UI review until
  completion; no design approval gate remains.
- Added canonical browser routes and authenticated root dispatch, legacy bookmark
  redirects, private headers, and public-HTTP exclusion. Four new endpoint tests
  failed before implementation, then passed.
- Added a server-owned deep-link return value across login/session renewal. The
  focused return test failed with the dashboard destination first, then passed.
  External return query parameters are not consumed.
- Found a credential-only mismatch in Services API admission. A focused plug test
  failed before changing the inventory GET guard to accept either services.read or
  api_keys.read; bindings remain services.read only.
- Production shell, scoped directory, dashboard, and remote picker now consume the
  server projection. Initial frontend integration run: 4 expected failures, then
  5 passing tests. Additional revocation, key-only and stale search cases pass.
- Migrating remaining pages and updating old route-specific test fixtures; full
  production browser and completion gates remain outstanding.

## Production review and corrections

- Canonical routes now cover tenant resources, directories, account, users/roles
  and forms, platform services and getting started. Samples use the same shell;
  diagnostics mounts an independent React navigation island outside LiveView DOM.
  Editor and call history stay standalone. Storybook-only API key/recipe examples
  retain layout coverage without inventing production routes.
- Chrome found an asset output collision: esbuild and Tailwind both wrote
  admin.css. Tailwind now writes admin-ui.css, linked after bundled CSS. Chrome
  then exposed missing Users/Roles titles after header removal; added local h1s.
- Fresh independent production finish review requested recapture for diagnostics:
  outer AdminShell min-height pushed server content below the viewport. Fixed
  external-host sizing; desktop main starts at y=0, phone at y=52, LiveView remains
  phx-connected, neither viewport overflows. The recapture is valid.
- Reviewer found remote picker pagination/cache lifecycle defects. Four new tests
  failed as expected: reopen after page 2, authority refresh after page 2, and both
  tenant/footer close notifications. Reset page/cache on close and authority
  change; centralize open notifications. All 15 focused picker/App tests pass.
- Additional red/green tests cover resource-specific revocation, directory refresh,
  modal inert navigation, and clearing actor identity on session expiry. Final
  frontend migration updated old exact label assertions to Call Specs; the full
  suite passed 699 tests before the four final picker regressions were added.
- Real Chrome authentication covered one/many/zero/key-only/mixed-scope users plus
  Superadmin. Landing paths and scoped lists matched contracts. Phone search,
  Escape focus restoration and keyboard tenant selection passed.
- Live membership update invalidates existing sessions by Identity contract. The
  first manual expectation incorrectly anticipated an in-session dashboard jump;
  corrected the inspection to verify login, reauthentication, then the sole
  remaining tenant dashboard. Disabling that user returned the active browser to
  login. Restored the synthetic review user's original enabled/membership values.
- Actual desktop pages inspected: directories, account, users/new/edit/reset,
  roles/new/edit, platform services, tenant calls/specs/services, getting started,
  voice and transfer samples, diagnostics. Phone captures cover account, users,
  services, specs, both samples, diagnostics and dashboard. Dashboard light-theme
  inspection explicitly sets the existing theme attribute; it does not imply a
  new theme switcher. Editor/inspector have zero sidebar rails; normal pages one.
  No horizontal overflow found. Evidence is under the local temporary review
  directory; screenshots and credentials are not committed.
- Initial final umbrella run failed one existing Twilio startup audio-wait test.
  Focused rerun failed a different generated outcome at the same waiting assertion.
  No telephony code changed. A complete repeat with the original seed is running;
  do not claim this gate passed until its final result is recorded.

## Final acceptance

- Complete umbrella repeat with the same seed passed: 3,777 tests, zero failures,
  132 excluded, including all 602 Gateway tests. The earlier audio-wait failures
  did not recur; no unrelated telephony code or timing assertions were changed.
- Final frontend: 89 files, 703 tests pass. TypeScript, ESLint, Console asset build
  and Storybook build pass. Format, warnings-as-errors compile, strict Credo and
  unused-lock check pass. No dependencies changed; Lean lane is not applicable.
- Independent finish review returned ship for the three scored production fixes
  (search lifecycle, picker close notification and persisted design truth); no
  material issues remain. This is fix-list scope after the full production review.
- Protected deep-link login returned to Call Specs, direct reload passed, and a
  read-only member had no New/Create call spec control. Key-only Services reached
  its ready state with only the Services tenant link and no provider write control.
- Milestone acceptance and index are synchronized. User UI review is deferred by
  explicit instruction; no commits created.
- Restart verification passed after allowing the previous listener to release its
  port; an immediate first restart correctly refused the occupied port. The fresh
  dev watcher writes admin-ui.css. Filtered directory URLs, browser back/forward,
  and keyboard switching from My account to a tenant dashboard passed after restart.
