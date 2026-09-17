# Operator definition browsing

## Scope

Checkpoint 4 of the operator login/admin milestone: add a bounded operator read for one tenant's
call-definition summaries and connect the approved React tenant-definitions composition to canonical
tenant URLs.

## Red/green evidence

- Calls tests failed first because definition summary/page contracts and the authorized workflow did
  not exist. They now cover operator authority, bounded pagination, missing tenants and unavailable
  storage.
- Persistence tests failed first because `AdminStore.list_definitions/4` did not exist. The adapter
  now obtains tenant identity, page membership, total, latest/published revisions, current name and
  call totals in one PostgreSQL statement. Empty out-of-range rows preserve the total.
- Console tests initially reached the React HTML catch-all. The tenant-scoped JSON route now covers
  populated, missing, unavailable, malformed-page and anonymous outcomes.
- React tests failed while `AdminApp` only loaded tenants. They now cover tenant selection, direct
  workspace canonicalization, stale tenant responses, response validation and distinct empty,
  missing and unavailable states.

## Decisions

- The latest revision supplies the displayed name and updated time. The definition's current
  publication pointer supplies the published version. Call count spans calls pinned to every immutable
  revision of that definition.
- `/admin/tenants/:tenant_key` canonicalizes to `/definitions`; the page number stays in the query
  string. Calls and Services workspace links stay hidden until their vertical slices work.
- Production renders definition call counts as plain values until the Calls route exists. The
  approved Storybook composition retains its linked counts so checkpoint 5 can activate the same
  contract without redesigning the table.
- The React response validator requires exact page length and rejects a published version newer than
  the latest saved version. A tenant key returned by the endpoint must match the selected URL.

## Browser and UI audit evidence

- Completed a real operator login against the local server and opened a persisted tenant's definition
  page from the tenant directory.
- Inspected 1440×900 and 390×844 Chrome renders. The wide table scrolls inside its container and the
  document width remains equal to the mobile viewport.
- Verified direct tenant-root canonicalization, refresh and browser back/forward restoration.
- Rechecked the corrected production composition at 1440×900 and 390×844. Definition call counts
  render as plain table cells with zero unfinished Calls links, and document width remains equal to
  the viewport at both sizes.
- The existing approved Storybook compositions cover empty, unavailable, paginated and long-content
  states. Integration component tests cover the corresponding loader outcomes.
- The Impeccable deterministic detector returned no findings for `AdminApp`,
  `TenantDefinitionsPage`, or `TenantWorkspaceNavigation`. Manual audit found the design coherent with
  the existing dark operator shell; the existing 1.2 MB unminified development bundle remains a later
  performance concern rather than a checkpoint regression.

## Verification

- Calls: 95 tests, zero failures.
- Persistence: 147 tests, zero failures, 11 excluded.
- Console: 174 tests, zero failures, one excluded.
- Console assets: 90 tests, TypeScript and ESLint pass.
- GPT-6 Astra xhigh found that definition counts still linked to the unfinished Calls route. A
  focused integration test reproduced it first; the production composition now disables only those
  links, and Astra approved the corrected checkpoint with no remaining blocker.
- Root `mix test` completed every umbrella application but reported one unrelated Gateway WebRTC
  timing failure in the five-participant handoff test (`missing ordered cue/conversation audio`). The
  exact failed test passed alone afterward: one test, zero failures, 67 excluded. All applications
  changed by this checkpoint remained green in the root run.
