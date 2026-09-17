# Operator tenant browsing

## Scope

Checkpoint 3 of the operator-login/admin milestone: add the installation-wide tenant read boundary,
serve it only to an authenticated operator, and connect the approved Tenants Storybook composition to
real data without redesigning it.

## Red/green evidence

- Calls tests were written first and failed because the installation-operator authority, tenant page,
  admin repository port and workflow did not exist. They now cover bounds, authority separation,
  empty and unavailable repositories, pagination and out-of-range pages.
- Persistence coverage was written before `AdminStore`; it now proves deterministic creation-time/key
  order, bounds, offsets, totals and empty out-of-range reads against PostgreSQL. A review-found
  database-failure escape was reproduced with a failing adapter and fixed at the persistence boundary.
- Console endpoint tests initially reached the React HTML catch-all. They now prove the JSON response,
  literal query-string pagination, empty/unavailable distinction, invalid pages and anonymous denial.
- React tests initially remained on the static skeleton. They now cover response validation, loading,
  empty, populated, unavailable, session expiry, history restoration and obsolete-response rejection.
  Review follow-up tests also cover contradictory pagination, stale 401 responses and recovery from an
  out-of-range page URL.

## Decisions

- Calls owns `%InstallationOperator{}` as a distinct authority. The Console session pipeline establishes
  browser authority, then passes that explicit Calls authority to the bounded workflow. No tenant
  `Principal`, tenant API-key ID or wildcard tenant is fabricated.
- The approved UI uses page numbers and previous/next controls, so the JSON endpoint accepts a positive
  page and uses a fixed page size of 25. Persistence applies deterministic descending `inserted_at/key`
  order and obtains page rows plus the total in one database statement. Pages beyond the known range
  fail instead of falsely rendering the global empty state.
- Console owns response validation and HTTP/session handling. The existing `TenantsPage` still receives
  its approved `TenantsPageState`; an optional header action carries the existing sign-out form.
- Page navigation writes `?page=N` into browser history. Each load uses an abort signal plus an active
  request guard, so a late response cannot overwrite the current page.

## Browser evidence

- Completed a real `mix vxpipe.login` exchange against the local server, then loaded the persisted
  tenant directory through `/admin/api/tenants`.
- Inspected desktop 1440×900 and mobile 390×844 layouts in headless Chrome.
- Verified direct page-two load, refresh and browser back restoration. The first rendered pass exposed
  that the admin API pipeline did not parse query strings; a literal-query red test reproduced it and
  `Plug.Parsers` fixed it.
- Rendered populated data from PostgreSQL and injected empty and failed fetch outcomes into the running
  React application to verify both visible states.

## Verification

- Calls: 93 tests, zero failures.
- Persistence: 146 tests, zero failures, 11 excluded.
- Console: 172 tests, zero failures, one excluded.
- Console assets: 84 tests, TypeScript and ESLint pass.
- `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`,
  `mix deps.unlock --check-unused`, and `mix assets.build` pass.
- GPT-6 Astra xhigh approved the corrected checkpoint after verifying the one-statement page query,
  stopped-repository behavior, structured page rejection, response consistency and stale-request guards.
- The umbrella run reached one unchanged Call Engine live-inspection failure after 698 tests. The same
  test fails alone: it kills the inspection buffer, then expects a participant from the terminated
  incarnation to remain. No checkpoint code touches Call Engine.
