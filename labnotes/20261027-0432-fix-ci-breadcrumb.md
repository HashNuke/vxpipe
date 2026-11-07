# Fix CI breadcrumb timing

## Diagnosis and scope

- Main CI run `40441788645` failed in `Test Console assets`: the API-key creation
  story test queried the `API Keys` button while the breadcrumb still represented
  the inventory loading state. Compilation, linting, and asset builds passed;
  the umbrella test step was skipped.
- Branch run `40439875023` had three outdated ElevenLabs assertions. The merge
  already corrected those assertions; the related tests passed locally.
- `ApiKeysPage` loads its available key kinds asynchronously and only then renders
  the creation form and clickable breadcrumb. Waiting for the navigation element
  does not wait for that state transition.
- `bin/setup` completed successfully in this checkout during the investigation.
  The worktree was clean before this fix. No application behavior needs changing.

## Verification

- Changed the existing test to inspect the immediately rendered breadcrumb
  synchronously, reproducing the CI loading state before the fixture response
  arrives.
- Red: the focused test failed at line 71 with the same missing `API Keys` button
  and inventory breadcrumb DOM as CI. Synchronous inspection makes this race
  reproducible without artificial delays or dependency mocks.
- Fix: use `await within(breadcrumb).findByRole(...)` for the button. Keep the
  initial navigation query synchronous so the test exercises the loading state.
- Green: all 31 tests in `ConsoleStories`, `PageBreadcrumbs`, `ServiceSetupModal`,
  and `defaults-panel` passed.
- `npm run check` passed. The full Console asset suite passed: 119 files,
  916 tests. The existing jsdom `scrollTo` notice was non-fatal.
- `mix format --check-formatted`, `mix compile --warnings-as-errors`, and
  `mix credo --strict` passed.
- `mix test` completed across all ten umbrella applications: 4,529 tests
  reported, zero failures, 159 excluded. The call-engine suite took about
  225 seconds and the gateway suite about 506 seconds; continued test output
  confirmed progress during the longer run.
- `mix deps.unlock --check-unused` and `git diff --check` passed.
- Browser inspection is not applicable: only test synchronization changed;
  application and story rendering code are unchanged.
- No source-cutover or speech state-machine changes were made, so the Lean lane
  is not applicable.
