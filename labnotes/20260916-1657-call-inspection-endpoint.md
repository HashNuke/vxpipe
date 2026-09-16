# Call inspection endpoint

## 2026-09-16 design inspection

- The existing `/calls/:call_id` LiveView combines persisted Calls history with optional live room
  inspection, usage, publication listings and recordings. It is not a reusable JSON contract.
- `/calls/:call_id/details/:publication_id` downloads one immutable publication through the
  call-details backend and can use S3. It cannot supply ongoing or cursor-paginated database state.
- Chosen resource: `GET /calls/:call_id/inspection`, backed only by Calls database workflows.
- Chosen module split: `CallInspectionQuery` for authorized orchestration,
  `CallInspectionPresenter` for pure wire conversion, controller for HTTP.
- Ongoing calls deliberately show the latest database archive state. RTVI remains an optional live
  edge applied by the browser after the database baseline.
- Added four implementation checkpoints to the call-debug-console milestone and recorded the
  durable decision in `docs/call-inspection-json-endpoint.md`.

## Database query boundary

- Red: three focused query tests failed because `CallInspectionQuery` did not exist.
- Green: the query now loads the authorized persisted inspection before the exact definition
  revision and usage report. It uses the existing injected Calls backend and never invokes
  `inspect_live_call`.
- Supporting definition or usage failures are explicit unavailable values; they do not hide an
  otherwise inspectable call. A missing/cross-tenant call stops before either supporting read.
- Focused verification: 5 tests, 0 failures across the new query and existing inspection facade.

## 2026-09-16 scope correction

- The user rejected the inherited older-history cursor and `as_of` fields. The endpoint is one
  complete latest database snapshot, not a page feed.
- Replaced the broad milestone items with four explicit vertical checkpoints: complete database
  query, pure presenter/Core contract, authenticated HTTP resource, and Console host integration.
- The query checkpoint must now use the existing complete `Calls.fetch_call_history/3` workflow;
  this also lets the presenter combine tool starts with their terminal request/response state and
  select the actual latest variable snapshot without page-boundary guesses.
- GPT 6 Astra xhigh found no blocker in the revised 1A implementation. It noted that the focused
  backend tests prove no live-inspection call; reviewed dependency direction proves the query only
  reaches Calls database workflows. Those are separate pieces of evidence and will be reported as
  such rather than claiming that the test intercepts arbitrary S3 access.
- Revised 1A red tests failed against the old paged result because `call`/`history` did not exist
  and the complete history read was never attempted. The green implementation now fetches the
  authorized summary with `inspect_call(limit: 1)`, then requires `fetch_call_history`; 6 focused
  query/facade tests pass.

## Runtime participant identity correction

- Presenter work exposed that definition keys (`assistant`) differ from generated runtime
  participant IDs stored in call facts. Recompiling a definition cannot reproduce those IDs.
- The database `PreparedCall` already stores the immutable resolved plan with the exact ID mapping,
  effective capabilities, prompts, tools, connections and transfers. The query now requires that
  record and no longer fetches the separate definition revision.
- Red tests failed while the query skipped the prepared call. The corrected query stops before
  history/usage if the prepared record is unavailable and passes 5 focused query tests.

## Public response projection

- Red tests established the versioned snake-case response, runtime participant IDs, semantic
  timeline, tool request/response capture, variables, usage metrics, completeness and redaction.
- GPT 6 Astra xhigh found three contract defects before commit: metric IDs omitted settlement
  provenance, participant state changes reused a definition revision, and Core discarded metric
  availability. It also found that tool lifecycle reduction incorrectly prioritized timestamps.
- Metric IDs now hash the complete effective-amount identity used by persistence and settlement.
  Metric and participant revisions use supporting archive fact sequences; zero explicitly means
  that the selected persisted record has no matching source fact in the supplied history.
- Tool lifecycle state reduces by source sequence. Timestamps remain display-order data only.
- Core retains metric availability separately from the collection, so unavailable usage remains
  distinct from a successfully loaded empty report. The redundant participant-configuration
  availability marker was removed because the prepared plan is required.
- Focused Console verification: 13 tests, 0 failures. TypeScript verification: build/typecheck,
  5 Core tests and 27 React tests all pass.
- Root verification also passes: format check, warnings-as-errors compile, strict Credo, full
  umbrella tests and unused dependency check. The temporary React display condition was removed;
  this checkpoint changes data contracts and fixtures but no rendered UI behavior.

## Authenticated HTTP resource

- Red: six endpoint tests failed with `Phoenix.Router.NoRouteError` before the route existed.
- Green: `GET /calls/:call_id/inspection` now uses a JSON/session/operator pipeline and a thin
  controller that delegates to the query and presenter. It returns private, non-cacheable JSON.
- The focused endpoint coverage exercises authentication, ongoing and ended lifecycle data,
  content type, secret/tenant redaction, indistinguishable missing/cross-tenant results, invalid
  requests and database unavailability.
- Focused verification: 17 query, presenter and endpoint tests pass. The injected backend proves
  that the endpoint never asks for live inspection; source review confirms the query has no
  publication, recording, artifact or object-storage dependency.
- GPT 6 Astra xhigh found no 1C blocker after explicit `Accept: application/json` coverage. An
  incompatible Accept header was not claimed as verified: the endpoint's pre-existing global
  render-error configuration has no JSON error renderer, which is outside this resource slice.
- Root format, warnings-as-errors compile, strict Credo, full umbrella tests and unused dependency
  checks pass with the HTTP resource included.

## Console response adapter

- Red: the focused Vitest suite failed because the Console-owned inspection adapter did not exist.
- Green: the adapter fetches the same-origin inspection resource with JSON negotiation and no
  browser cache, validates schema version 1 at runtime and maps snake-case fields into the
  `@vxpipe/core` snapshot contract.
- Validation covers lifecycle, configured participants, every timeline variant, variables,
  metrics, availability and completeness. Optional captured tool payloads remain distinct from
  missing payloads.
- Focused coverage exercises ongoing and ended snapshots, a `503` response, malformed data and an
  encoded call ID. The loader also rejects a valid snapshot carrying a different call identity.
- Astra's pre-commit review found that a clean asset typecheck depended on ignored Core build
  output. The Console asset TypeScript configuration now resolves the monorepo Core dependency to
  its source, while the package dependency still records the intended package boundary.
- Pre-commit verification passed the clean Console asset typecheck, all 19 Console asset tests,
  root JavaScript checks/tests, formatting, warnings-as-errors compilation, strict Credo, Console
  tests and unused-dependency checks. The umbrella run reached one unrelated existing Gateway
  WebRTC failure at `human_transfer_webrtc_test.exs:376`; the same test also timed out in isolation
  while waiting for its native adoption gate.

## Console production host

- Red: the React host test failed because `CallInspectionApp` did not exist; the authenticated
  Phoenix endpoint tests failed because `/calls/:call_id/console` was not routed.
- Green: the HTML host safely embeds the requested call ID and loads the dedicated production
  bundle. `CallInspectionApp` fetches once, creates the Core store/controller and injects that
  controller into the same `@vxpipe/react` `CallConsole` exported to Storybook. Historical views do
  not attach live call or device controls.
- A clean `mix assets.build` exposed two React runtimes when esbuild followed source package paths.
  The esbuild profile now aliases React and ReactDOM to the Console asset installation; the built
  page then rendered normally.
- Focused verification: 3 React host tests and 3 Phoenix host-route tests pass.
- Chrome inspection used the built production JS/CSS and endpoint-shaped fixture responses.
  Ongoing and ended calls rendered at 1440x900; the ongoing state also rendered at 390x844. Body
  scroll width matched the viewport at both sizes, the console remained height-bounded, and no live
  controls appeared. Screenshots were written to `/tmp` and are not repository artifacts.
- Astra's final review exposed three integration defects before commit. The Console-only install
  depended on undeclared root workspace output, repeated per-attempt metrics overwrote one another,
  and unavailable duration/metrics were rendered as zero or empty data.
- `mix assets.setup` now installs and builds the root workspaces once before the Console install;
  the Console consumes the packages' declared distribution entry points. The exact setup/build/test
  workflow passes from the umbrella root.
- React now keeps every repeated metric observation in its table cell with separate source
  tooltips. It also distinguishes unavailable metrics from an available empty report and renders an
  unknown duration as unavailable. Three focused regressions failed first and now pass.
- Re-inspected the metrics Storybook in Chrome at 1440x900 after the correction; the bounded table,
  sticky target column and dark presentation remain intact. The capture is
  `/tmp/vxpipe-metrics-rereview.png` and is not a repository artifact.
- GPT 6 Astra xhigh cleared the corrected 1D-b checkpoint with no remaining commit blockers.
- Final verification passes: workspace build and tests (Core 5, React 29), Console asset clean
  setup/typecheck/build/tests (22), focused Console inspection/host tests (14), root formatting,
  warnings-as-errors compilation, strict Credo, unused dependency check and the full umbrella test
  suite. The final Console lane reports 133 tests, zero failures and one excluded test.
