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
