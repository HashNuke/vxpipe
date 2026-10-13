# Console Storybook organization

## First checkpoint: remove the sidebar hint

- Removed the unrequested tenant-selection hint and its unused CSS from the shared
  sidebar. Updated the sidebar contract to omit empty navigation groups silently.
- The focused regression was red before the removal and passes afterward.
- Reviewed the diff and rendered the tenant directory in desktop and phone Chrome.
  The hint is absent; the tenant picker remains available.
- Root formatting, compilation with warnings as errors, strict Credo and unused
  dependency checks pass. The complete frontend suite passes (711 tests).
- The first umbrella test process received SIGTERM before completion; rerunning
  the full suite. Section-based Storybook organization remains the next checkpoint.

## Second checkpoint: group editor components

- Kept Call spec editor as its own Console section and placed its eight component
  groups under `components`. The standalone editor Page stories retain their IDs.
- Reviewed the mechanical title-only diff. TypeScript, ESLint and Storybook build
  pass; the live index contains the new groups and editor page renders at desktop
  and phone sizes without a sidebar.

## Third checkpoint: consolidate Console stories

## Request and decisions

- Remove the unrequested tenant-selection hint from the actual shared sidebar.
  Keep fixture explanations in Storybook documentation, not rendered review UI.
- Organize Console by site section, with reusable controls under `shared` and
  section-specific controls under `components`. Keep the call spec editor separate.
- The prior Navigation gallery duplicated older page stories without migrating
  their hosts. Consolidate the gallery into section-owned page stories and frame
  the existing detailed fixtures with the production sidebar. Preserve unique
  loading/error/pagination/form/permission scenarios; retire duplicate presentations.
- Authentication, Users, Roles and My account have separate page groups. Setup
  examples belong to Tenants, Services or Call Specs. Call history and the editor
  remain standalone. Shared controls have no application header.

## Implementation and evidence

- Initial four focused tests failed for the unwanted hint and missing sidebar on
  existing Calls, Call Specs and service inventory stories, then passed.
- Added story-only composition helpers. Existing leaf components retain their
  state fixtures; callback navigation can enter the linked dashboard/journey.
  The helper carries actual fixture tenant identity and authority across selection.
- Two regression tests first exposed lost directory tenant identity and a member
  being promoted to the default fixture role on navigation. Both now pass.
- Inspector links now address the standalone Calls/History story. Return links
  resolve to the owning page group, with existing call context retained.
- A shared-control regression failed while the old AccessFrame brand header was
  present, then passed after making the component showcase header-free.
- The running Storybook server returned 404 for existing editor/dialog modules
  before editing. Restarted the same port after confirming the stale process
  stopped. Did not create any tmux session or second preview server.
- The initial rendered sweep used a bad readiness predicate: Storybook keeps a
  hidden error element in its document. Stopped that sweep, corrected the predicate
  to require mounted story content, and started the bounded desktop/phone pass.
- Updated Storybook sorting, cross-story links and current review guides. Historical
  milestone labnotes remain historical evidence; current guides own the new IDs.

## Verification

- Final frontend suite: 90 files, 712 tests passed. A review regression exposed
  a lost call-spec filter on inspector return; the test failed with "All call
  specs", then passed after restoring the hash filter on mount.
- TypeScript, ESLint, production assets and Storybook builds pass. The final live
  and built Storybook indexes agree on all 289 entries; no Navigation group remains.
- Rendered 51 desktop/phone views in headless Chrome with agent-browser. Normal
  pages have one sidebar, component/authentication/history/editor presentations
  have their intended framing, and none has horizontal overflow or the removed hint.
- Verified searchable tenant selection, mobile Menu/Escape, history/filtered-call
  round trip, user tenant-selection dialog/Escape/cancel, and read-only inventory.
- Root formatting, warnings-as-errors compilation, strict Credo and unused-lock
  checks passed. All umbrella applications passed: 3,777 tests, zero failures
  (132 excluded integration/live tests), across the completed runs.
- Two root `mix test` executions received SIGTERM near five minutes, after the
  Identity, MCP, Providers, Agent Runtime, Call Engine and Calls suites passed
  (2,582 tests). Ran the remaining Gateway, Artifacts, Persistence and Console
  test directories from the umbrella root in one detached runner to avoid that
  command lifetime. It exited successfully: 602 + 20 + 275 + 298 tests passed.
  Gateway took 472.5 seconds. No test processes remain running.
- Final staged diff and working tree checks are clean. No dependency or speech
  state-machine changes were made; Lean verification was not required.
- Review was performed directly; no teammate processes, agents or tmux sessions
  were created for this task. Existing preview port 6006 serves the reorganized tree.
