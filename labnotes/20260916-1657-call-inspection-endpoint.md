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
