# Sidebar dashboard proposal

## Scope and decisions

- User requests planning and a Storybook proposal before production integration;
  additionally requests review and careful backend API planning.
- Clean starting worktree. Ran bin/setup successfully; isolated Console 4002,
  Storybook 6009. Did not read live provider configuration or run live services.
- Reviewed router, existing headers and permissions. Calls.UserAuthorization owns
  effective tenant visibility; assignment count and role-name shortcuts are wrong.
- Created milestone and durable API/UI decision, including header inventory,
  zero/one/many/all scope, bounded queries, stale results, revocation, migration
  and specialized editor/inspector exemptions.
- Reusing existing page content/components in an isolated Navigation Storybook
  family. Production route cutover remains an unchecked milestone checkpoint.

## Red/green evidence

- navigationPolicy tests first failed on missing implementation; four pass after
  adding landing, visibility and mixed-scope presentation model.
- Journey tests first failed on missing component; subsequent run exposed cmdk
  overriding the input role/accessible label and the fixture's existing Sign in
  label. Added Command label and used its combobox semantics.
- Initial test file was accidentally written beneath the assets cwd with a root
  relative path; moved it to the proper source path before red verification.
- agent-browser initially could not start Chrome in this container; --no-sandbox
  resolves the environment restriction. Existing Users page inspected in Chrome
  before building. Wait for actual content before screenshots: the first capture
  preceded React rendering and was discarded.

## Review and corrections

- Independent finish review returned `fix`: phone dashboard hid call state in the
  wide ledger; auxiliary read-only routes retained writes; steady-state Services
  had a disabled setup Continue action; API-key-only Services was not distinct.
- Added five failing focused tests for the permission/footer findings. They failed
  for the expected absent title/gate/destination behavior. Fixed with dedicated
  permission fixtures, no-write auxiliary views, platform read-only propagation,
  API-key-only Services and an explicit API keys action independent of readiness.
- Recent calls now use compact records with name, ID, state and time reflowing on
  phones. Existing full Calls/Call Specs ledgers retain their bounded local scroll.
- Settled mobile drawer recapture confirmed its solid background; an earlier image
  was taken during the entrance animation and is not final evidence.
- 17 focused tests pass after fixes; TypeScript and lint pass. Before correction,
  the full frontend lane passed 676 tests. Final rerun is underway.
- All five umbrella gates pass: format, warnings-as-errors compile, strict Credo,
  3,749 tests / 0 failures / 132 exclusions, and unused-lock check. No state-machine
  change; Lean lane is not applicable. Storybook and Console builds passed before
  the bounded corrections; final builds follow the final frontend suite.
- API review clarified that GatewayMount does not claim `/`: add the root route in
  Console.Router without changing gateway ownership. No-directory-grant principals
  receive an authoritative empty navigation projection; existing directory 403 is
  retained, while authorized zero-tenant scope returns an empty directory.
- Chrome initial batch covered 49 captures across full page families and both themes;
  all showed no page-level overflow. Capture wait was corrected to target the actual
  Storybook root, because its hidden No Preview template also contains h1 elements.
- The first unrestricted frontend run was terminated (143) during concurrent root
  work. A bounded two-worker run completed successfully; no test failure is inferred
  from the terminated run. Started the preview in its own tmux session for continuity.

## Final proposal evidence

- Follow-up review found service-only readers could still see masked credential
  metadata in legacy Services. Added a failing regression, then propagated the
  API-key read capability to hide the credential column. Existing component defaults
  preserve production behavior. The related four-file run passed 31 tests.
- Final frontend suite: 85 files, 682 tests passed with two workers. Navigation
  accounts for 18 focused tests. TypeScript and lint pass; final Storybook and
  Console asset builds pass. No dependencies or lockfiles changed.
- Independent reviewer scored every finding resolved, including final loaded-logo
  captures, with `ship` at fix-list scope. Used a fresh generic agent with the
  skill's degraded finish-review contract because no named agent role was available.
- One static design detector run over changed UI targets returned an empty list.
- Browser confirmed tenant name/key search and keyboard selection, switching from
  Services always to the selected dashboard, unmatched search, Escape restoring
  picker focus, mobile selection closing the drawer and returning focus to Menu,
  and logout showing the sidebar-free login. Phone dashboard identity/state/time
  remain visible in both themes. Final asset captures waited for fonts and images.
- Production backend/routes remain unimplemented, and UI acceptance remains open.
  Recorded the proposal's visual delta in its surface brief; existing DESIGN.md
  remains the accepted production baseline. No commits created.
