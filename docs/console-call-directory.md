# Console call directory

## Decision

The tenant Calls page is a compact, paginated directory rather than a second call-inspection view.
Each row exposes only the call ID, call-spec identity and revision, a presentation state, and the
call creation time. Rows are ordered newest first with the public ID as the stable tie-breaker.

The directory API maps the internal lifecycle to two operator-facing states:

- `prepared`, `admitting`, and `running` become `ongoing`;
- `ended` and `failed` become `ended`.

Archive completeness, start/end timestamps, duration, and terminal reasons remain available from
the separate call-details inspection contract. They are intentionally absent from the directory
response and table.

The call-spec filter remains URL-backed. Its UI uses the shadcn combobox composition (Radix Popover
and cmdk) so the bounded list of call specs can be searched by name or identifier. Selecting a
filter resets pagination to the first page.

## Presentation

The table columns are `ID`, `Call spec`, `State`, and `Time`. The call-spec revision appears beneath
the name as a small badge. Time shows the browser-local date and time with a relative value beneath
it; the native hover title contains a fuller browser-local timestamp. Services timestamps use the
same local-title rule.

The populated Storybook state includes working pagination so the primary review URL exercises the
control instead of requiring a separate edge-case story.

## Rejected alternatives

- Reusing internal lifecycle labels in the directory was rejected because admission and failure
  details belong in call inspection, not in the high-level list.
- Keeping archive completeness as a list column was rejected because it added a second operational
  status without helping operators choose a call.
- A native `select` was rejected because it cannot search a long call-spec list.
- Client-side reordering of API results was rejected. Persistence owns stable newest-first paging;
  sorting after pagination could produce incorrect cross-page order.

## Verification

Focused Console endpoint tests cover the reduced response and lifecycle projection. Frontend tests
cover strict response parsing, searchable filtering, requested columns, local and relative times,
and pagination in the populated story. Browser checks cover the populated story at 1440×900 and
390×844, including filter search and page advancement.
