# Astra Telnyx review

- Requested review of the shared Telnyx application and tenant override work using Astra at xhigh. The user requires a reproducing test for each valid bug report.
- Committed the completed implementation first as `505e9ca1` (`Support shared Telnyx applications and tenant overrides`), per the user’s instruction. The worktree was clean immediately afterward.
- Review scope: the committed implementation, migrations, routing, configuration permissions/atomicity, and modal state. No production fixes or follow-up commits are part of this review.
- Reviewer: `astra_telnyx_review`, model `gpt-6-astra`, reasoning `xhigh`.
- Only failures from tests asserting the approved intended behavior count as confirmed findings. Parent will independently rerun reported reproductions and check fixture validity.
- Existing acceptance evidence is in `20261113-1114-implement-shared-telnyx.md`. No live-provider calls or credential-file reads are needed.

## Follow-up

The user subsequently requested fixes for all valid findings. Both reported UI defects are now corrected and their reproductions pass; see [fix evidence](20261113-1431-fix-telnyx-review.md). The original review history below records the pre-fix failures.

## Results

Review complete: two P2 findings, both independently reproduced. No additional test-proven backend defect was found.

### Confirmed: inherited application blocks outbound caller edits (P2)

- A tenant using the shared platform application has a null stored application ID. Phone routing correctly displays Platform default, but its edit form converts null to an empty required field and rejects saving without a dedicated ID.
- Editing only the outbound caller number therefore sends no PATCH. The connection modal does not provide another caller-number editor.
- Reproduction: `apps/vxpipe_console/assets/src/SharedTelnyxReview.test.tsx`.
- Run from `apps/vxpipe_console/assets`: `npm test -- src/SharedTelnyxReview.test.tsx`.
- Astra and parent independently observed the expected PATCH assertion fail; only the initial GET occurred (one fetch call). Parent run: one test, one failure, 1.80 seconds; captured in `astra-telnyx-review-parent-ui.log`.
- Source: `TelephonyApplicationForm.tsx` initializes the inherited ID as empty, marks it required, and rejects an empty value. The nullable application contract introduced by this commit makes this previously unreachable state valid.

### Rejected candidate

- A possible missing settings directory during Test credentials was disproven by tracing the production inventory action: `withNativeSettings` loads it before opening the modal. This is not a bug report.


### Confirmed: service-only writer cannot open the application editor (P2)

- A member with `tenant_services.read` and `tenant_services.write` can override or reset the tenant application through the new operation while keeping platform credentials. The production route still requires `tenant_api_keys.write` to enable Edit Telnyx, preventing that application-only edit.
- The second test in `SharedTelnyxReview.test.tsx` renders the production App route with these grants. It fails because Edit Telnyx is disabled. Waiting for Connect other MCP establishes that the service-writer session has loaded.
- Parent reran both frontend reproductions: two tests, two expected failures (2.93 seconds), captured in `astra-telnyx-review-parent-ui-2.log`.
- Relevant source: `App.tsx` calls `canWriteTenantCredentials` for the entire modal, and `ScopedServicesApp.tsx` gates opening through that value. The new backend authorizes application-only changes separately in `OperatorTelnyxConnection`.

### Independent backend controls

- New `apps/vxpipe_persistence/test/vxpipe/persistence/shared_telnyx_review_test.exs` runs the corresponding operations against PostgreSQL using service-only writer grants.
- It proves application override/reset succeeds without credential authority, and outbound caller changes retain the null stored application ID and effective platform application owner.
- Run from `apps/vxpipe_persistence`: `mix test test/vxpipe/persistence/shared_telnyx_review_test.exs`.
- Astra: two tests, zero failures, seed 901151. Parent: two tests, zero failures, seed 107021 (3.1 seconds), captured in `astra-telnyx-review-parent-backend.log`.


## Completion and limits

- Astra reviewed configuration transactions, inheritance/reset rules, routing, retained ownership, durable deduplication, publication locking, migrations and modal integration.
- Parent reran the final UI file after fixture corrections: two tests, two expected failures, 3.06 seconds (`astra-telnyx-review-parent-ui-final.log`). Both failures match the report above; they are not compilation, setup or fixture failures.
- The reviewer ran the frontend TypeScript check successfully. Parent verified ESLint on the new UI test, formatting on the new ExUnit file, and diff whitespace.
- No production code was changed after commit `505e9ca1`. The two test files and this labnote remain uncommitted. The UI regression tests intentionally remain red pending fixes; the backend control tests pass.
- This review did not run live Telnyx calls or perform a new rendered-browser inspection. The implementation’s earlier acceptance/browser evidence remains separately recorded in its original labnote.
- A possible scope-switch defect was discarded: the production App keys the integration component by tenant, remounting the modal on scope changes.
