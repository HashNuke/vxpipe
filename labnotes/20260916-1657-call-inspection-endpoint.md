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
