# Tenant calls workspace

## Outcome

- Replaced the definition-scoped calls route with tenant Calls plus an optional URL-backed
  `definition_id` filter.
- Added shared tenant workspace navigation for the complete Call definitions and Calls pages.
  Services remains absent until its page is complete.
- Added definition identity to tenant-wide call rows and changed visible revisions to `v<n>`.
- Added deterministic all, filtered, tenant-empty, valid-filter-empty, unknown-filter, loading,
  unavailable, partial-archive, long-content, paginated and narrow stories.

## Decisions

- `CallList` only renders the calls handed to it. The Storybook harness/fixture owns filtering so
  the later production endpoint can return the corresponding result without duplicating route logic
  inside presentation components.
- A valid definition with no calls uses an empty state. An unknown `definition_id` uses an alert so
  a stale or malformed URL cannot look like a successful empty query.
- The tenant root remains accepted by the story route as the workspace entry, while generated links
  use the explicit `/definitions` destination.

## Red-green evidence

- Added failing route tests for explicit sibling paths, optional filter round-tripping and tenant-root
  entry behavior before changing the route implementation.
- Changed definition-link and Calls-page tests before updating hrefs, state and controls; the focused
  run failed on the old paths and definition-scoped state.
- Added a failing interactive story test proving that selecting a definition must reduce visible
  rows as well as update the hash, then made the story controlled by its fixture/action boundary.
- Astra precommit review found the call-details definition breadcrumb still emitted the retired
  route. Updated its href and standalone story callback after confirming the regression test failed.
- The same review found stale pagination metadata after changing a filter in the paginated story.
  Filter and reset actions now clear that fixture's pagination; a regression test covers both paths.
- Browser review at 1024 px found the expanded table clipped Archive and row actions. The compact
  layout now remains active until the 1280 px breakpoint, where every expanded column fits.
- The long-content filter exposed native select intrinsic width at 390 px. The label and select now
  have explicit full/max width and `min-width: 0`, eliminating document overflow.

## Verification

- Console: 62 tests pass; `npm run check` and `npm run lint` pass.
- React package: 30 tests pass.
- `npm run build-storybook` passes. Vite reports its existing client-directive and bundle-size
  warnings; no build error is present.
- Browser inspection passed in dark desktop and 390 x 844 mobile layouts. Definition selection
  reduced nine rows to two; the unknown-filter story presented an explicit alert. The definitions
  page rendered the shared active navigation correctly.
- Independent GPT-6 Astra xhigh precommit review cleared the checkpoint after the breadcrumb,
  pagination and responsive-overflow fixes. Its final Chrome pass also covered Back/reload behavior.
