# Paginated integrations directory

## Scope and decisions

- Extend the existing Storybook integrations workflow with remote pagination and
  global search. Keep directory networking, credentials, OAuth and persistence
  outside this checkpoint; the hosted directory belongs to a separate project.
- User clarified that search covers MCP, AI and telephony across all categories.
  Browsing remains category-specific; entering search uses a Search results URL,
  and category navigation exits search. Platform scope continues to exclude MCPs.
- Every planned directory request includes `X-Vxpipe-Version`. The server filters
  unsupported integrations before computing totals or page boundaries. Native
  search entries reference installed provider IDs and reuse local credential UI.
- Use server-issued cursors with Previous/Next and explicit ranges. Preserve
  current rows through loading/failure, retry the failed page, and recover expired
  links from the first page. Preserve query/cursor in URLs and browser history.
- Consolidated the existing product version `0.1.0` into root `VERSION`, read by
  the umbrella and all ten child Mix projects. Loaded Console/Gateway runtime
  versions are available through `Application.spec(app, :vsn)` without Mix or a
  runtime file read. Storybook/Vitest consume the same build-time value.
- The umbrella is not itself an OTP application; `Application.spec(:vxpipe,
  :vsn)` is nil. A second runtime version module or dependency is unnecessary.

## Research and handoff

- Official WordPress Add Plugins and `plugins_api/3` documentation confirms
  directory search and pagination, with WordPress version supplied by its API
  client. Vxpipe takes the interaction inspiration and defines its own required
  version header. Sources are linked in the API handoff document.
- Updated the handoff with paginated category/integration endpoints, a mixed-kind
  search response, stable identity joins, version-aware snapshots/caches/ETags,
  release adapter manifests, unknown-version handling, and acceptance gates.
- The Storybook dataset simulates server storage. `directoryPageFixture` applies
  query/version filtering and returns a page. It is not a production browser-side
  full-catalog strategy. Real SemVer evaluation, manifest lookup, request
  cancellation/debouncing and cache implementation remain future backend work.

## Implementation and verification

- Wrote pagination behavior tests first; all five failed before implementation.
  Added global search/version-exclusion tests before that behavior change; both
  failed before implementation. Pagination tests now cover later-page connection
  status, cross-page search, history restoration, pending/error states and expiry.
- Focused integrations suite: 81 tests passed. Full Console frontend suite:
  867 tests across 112 files passed. TypeScript check and ESLint passed.
- Storybook static build passed; its existing large-chunk advisory remains.
- All three JSON example responses validate against the handoff schema. Invalid
  responses with a missing version echo or category-scoped search are rejected.
- Runtime inspection returned `0.1.0` for root Mix project, Console and Gateway.
- Headless Chrome inspection at 1440×1000 and 390×844: global Google search shows
  AI Studio plus Calendar/Docs/Sheets, tags wrap, breadcrumbs show Search results,
  and desktop/mobile navigation remains usable. Paging shows connected Cal.com
  with Edit and the double checkmark on the second page; reload and browser Back
  restore the appropriate page. Page-error retry returns the next page.
- Root quality gates passed after version centralization: `mix format
  --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`,
  `mix test`, and `mix deps.unlock --check-unused`. Umbrella test summaries total
  4470 tests with zero failures (156 excluded integration/live cases).
- Strengthened the version-exclusion test to assert the returned total as well
  as visible rows, ensuring filtering happens before counting; both search tests
  passed again. Browser search also confirmed the future AI entry is absent and
  selecting Google AI Studio opens its existing credentials form.

## Barriers and workarounds

- The running Storybook process did not reload a changed Vite define, leaving
  the version undefined in the browser. Restarted its identified process directly
  and confirmed rendering. The first restart encountered a short-lived occupied
  port while the old process exited; the subsequent start succeeded on 6006.
  No tmux was used. Leave the managed Storybook process running for review.
- Existing unrelated worktree changes were preserved. No files staged or committed.
