# Refine call directory

## Requests and decisions

- Search call specs within the tenant from the Calls dropdown; include specs
  beyond the initial 100 loaded options.
- Merge call ID, spec name and vN into Call info. Put finalized duration below
  local absolute time, with a dash for ongoing or missing recorded duration.
- Preserve calls.read authorization; do not require call_specs.read. New lookup
  uses latest spec names, literal case-insensitive name/ID search, 25 results
  plus a has-more flag. Storage filters before limit/offset.
- Duration is ended_at minus started_at, clamped nonnegative. Calls without a
  start/end pair remain unknown. UI supports legacy payloads without duration.

## Implementation and verification

- Red: persistence search failed because the callback did not exist; endpoint
  test failed on absent duration; new search route hit the old inspector route.
  UI tests failed on old column/relative-time rendering and no remote search.
- Green: storage 13 tests; API 3; initial UI integration 45; search/race/error
  and row grouping 18. TypeScript and ESLint passed.
- Full frontend initially found three older tests assuming synchronous choices;
  updated their mock endpoint and awaited asynchronous options.
- Desktop/mobile browser pass found the existing popup portal lost theme variables
  outside .vx-admin. Portal now stays within that theme container. Table remains
  locally horizontally scrollable on small screens, with the page width intact.
- The previously unused duration helper now formats milliseconds as h/m/s.
  Storybook derives fixture durations from recorded start/end timestamps and
  mocks the same paginated search contract as production.
- Required umbrella checks running; final results recorded below when complete.

## Final evidence

- All required umbrella gates passed: formatting (including explicit changed
  Elixir paths), warnings-as-errors compilation, strict Credo, 3,785 tests
  (132 excluded), and unused dependencies.
- Frontend: full suite 728 tests passed; final API/picker/row tests 35 passed,
  including the additional duration parser case. Final picker tests 2 passed
  after moving portal-container lookup into the ref callback to satisfy React
  lint. Final TypeScript and ESLint passed.
- Desktop and mobile Chrome verified rows and readable popup. Selecting a spec
  updates the URL and list. Browser sessions closed; Storybook remains on 6006.
