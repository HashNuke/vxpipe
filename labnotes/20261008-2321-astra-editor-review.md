# Astra call-spec editor review

Reviewed the completed call-spec-editor milestone, starting with Console authoring
commit `57cc346f` and production integration commit `7e04a716`, then tracing the
source editor, validation, request reducer, provider catalog and speech adapter
contracts needed to assess the integration. The review was requested with failing
regression tests for each testable finding. No implementation was changed.

Initial `git status --short` contained only the unrelated untracked
`labnotes/20261002-0241-wrangler-cache-repair.md`; it was preserved. This checkout
had already run setup. Available memory was approximately 5 GiB, and focused jobs
were serialized. No live provider tests, calls or secrets-file reads were used.

## Confirmed: no-op source save rounds valid large integer enums

`createEditorApi` parses the read response through `Response.json()` and then
serializes `saved.source` for the editor. An API-authored Call Variables schema
with `external_id: {type: "integer", enum: [9007199254740993]}` reaches the editor
as `9007199254740992`; the unchanged source passes client validation and is sent
back with the rounded enum on save. The saved schema's accepted value changes,
violating source preservation. The source can instead be protected from silent
rewrites if exact number support is unavailable; narrowing the server contract
would require an explicit compatibility decision.

Evidence:

- Added the no-op read/save regression to
  `apps/vxpipe_console/assets/src/admin/callSpecEditor/editor-api.test.ts`.
- From Console assets:
  `npm test -- --maxWorkers=1 src/admin/callSpecEditor/editor-api.test.ts`.
  Result: 1 failed, 3 passed. The outbound body assertion expected
  `"enum":[9007199254740993]` and received `"enum":[9007199254740992]`.
- Added a Console endpoint control proving the exact integer source is accepted,
  has no compiler errors, and reads back unchanged from persistence.
  `mix test test/vxpipe/console/admin_call_specs_endpoint_test.exs:209` from
  `apps/vxpipe_console`: 1 test, 0 failures (9 excluded), seed 644960.

## Confirmed: an existing spec ID new opens the creation seed

Caller-supplied call-spec IDs permit `new` (tenant API PUT and the CLI save task
both support explicit IDs). The Console list links every stored ID to
`/admin/tenants/:tenant/call-specs/:id`, but `CallSpecEditorRoute` treats the value
`new` exclusively as creation. Clicking that existing spec's row displays an
empty new source, and cannot open its stored revision through this route.
Creation intent needs a route/representation that does not shadow a valid ID.

Evidence:

- Added a list-to-editor regression to
  `apps/vxpipe_console/assets/src/CallSpecEditorRoute.test.tsx`.
- From Console assets:
  `npm test -- --maxWorkers=1 src/CallSpecEditorRoute.test.tsx`.
  Result: 1 failed, 7 passed. The stored-name assertion expected `Original` and
  received an empty value after clicking the existing spec row.
- Added a Console endpoint control showing a valid `new` ID saves with no
  compiler errors and can be read through the source API.
- From `apps/vxpipe_console`:
  `mix test test/vxpipe/console/admin_call_specs_endpoint_test.exs`.
  Result: 11 tests, 0 failures, seed 196616. This includes both backend control
  tests plus the existing tenant-isolation, immutable-revision, CSRF, privacy and
  error-projection cases.

## Review limits and handoff

No additional issue was proven in the reviewed authorization, publication,
stale-request, session-expiry or unsaved-navigation boundaries. The review did not
rerun the full umbrella suite, live provider lanes or rendered browser acceptance;
only regression tests and this labnote changed, and the two new frontend tests
are intentionally red for follow-up implementation. The parent reported the
pre-review baseline as 503 frontend tests and 3,458 umbrella tests passing.

Root `mix format --check-formatted`, Console assets `npm run check`, focused
ESLint over the two changed frontend test files, and `git diff --check` pass.
Test-only diff and final status were inspected. No commits were created, and the
unrelated labnote was preserved.

## Follow-up disposition (2026-10-09)

Finding 1 is fixed with exact integer source parsing/serialization and numeric
controls; its original API regression now passes. See
[integer preservation evidence](20261009-0345-preserve-source-integers.md).

For finding 2, the user clarified that API/UI clients must never choose a new
public ID. The former PUT upsert contract was corrected to update-only at the
shared authoring boundary; creation internally allocates a UUID. The review's
API-authored `new` scenario is replaced with regressions proving allocation is
forbidden and a UUID returned by creation opens correctly from the list. Legacy
stored IDs are not migrated, so this does not claim support for a pre-existing
legacy row named `new`. See
[server-owned identity evidence](20261009-0416-server-owned-spec-ids.md).
