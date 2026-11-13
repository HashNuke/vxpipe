# Fix Telnyx review findings

- User requested fixes for both validated Astra review findings, using the existing reproductions as regression tests.
- Baseline `505e9ca1`; two reproductions failed for the expected reasons before edits (`telnyx-fixes-red.log`). Existing PostgreSQL controls establish the permitted operations.
- Scope: preserve null application inheritance while editing outbound callers; expose application-only modal editing under tenant service permission without exposing credential controls.
- Keep credential and application write permissions separate, including credential-only reset of an existing dedicated application. Preserve existing required-ID validation for dedicated/new application forms.
- Use agent-browser/Chrome for a bounded desktop/mobile inspection. No live provider credentials or calls are needed.


## Implementation and focused evidence

- Inherited application forms preserve null when the ID is blank; dedicated/new forms retain their required application ID. The first reproduction changed from one GET/no PATCH to a successful number update (`telnyx-caller-number-green.log`).
- Derived application-edit permission separately in the production route and carried it through the inventory, host and modal. Only the primary Telnyx connection gains application editing from service permission; other credential providers and named credential bindings retain their previous gates.
- Credential replacement remains coupled to application editing because that action clears/requires the tenant application. Credential-only writers may reset credentials while keeping an existing dedicated application. Application-only writers see masked credential summaries without credential actions.
- Extended the production-route reproduction through an actual application-only PATCH, and added a failing permission test for credential-only reset before implementing the split (`telnyx-permission-red-2.log`: two failures/six passes). The focused group now passes 37 tests (`telnyx-review-fixes-green.log`).
- Astra xhigh independently reviewed the fixes and ran the same six focused suites: 37 tests passed, no additional confirmed defects. It made no further changes.
- Full Console frontend suite: 145 files, 1,109 tests passed in 59.45 seconds (`telnyx-fixes-frontend-all.log`). TypeScript and all changed-file ESLint checks pass. The new Storybook fixture initially needed an inline useMemo callback for the hook lint rule; corrected and rechecked.

## Browser verification

- Added reusable production-component stories under Telnyx permissions: application writer, inherited caller number and read-only.
- Used agent-browser with headless Chrome at 1440×1000 and 390×844. Saved an outbound number while retaining Platform default; saved/reopened an application override and reset it to the platform default. Credential controls remained hidden for the application-only writer. Read-only Edit Telnyx stayed disabled.
- Both rendered forms fit their viewport, with accessible labels and usable Save controls; the mobile document width equals 390 pixels. Inspected the four captures under the ignored `.impeccable/review/telnyx-fixes/` directory.
- Stories use in-memory responses. Actual App permission derivation is covered by the production-route regression; the PostgreSQL controls exercise the matching real backend operations. No live provider calls were made.

## Repository acceptance

All five root gates pass: format, warnings-as-errors compilation, strict Credo,
full umbrella tests and unused dependency checks. The final umbrella run reports
5,264 tests, zero failures, 381 excluded (seed 732924); the two new PostgreSQL
control tests are included. Output is captured in `telnyx-fixes-root-tests.log`.
No source-cutover or speech state-machine implementation changed, so the Lean
lane was not required. Documentation links and diff whitespace are verified.

The user subsequently requested a Git push. The fixes, reproductions, backend
controls, stories, usage documentation and milestone evidence are included
together in the follow-up checkpoint. The original implementation was committed
before review as requested.
