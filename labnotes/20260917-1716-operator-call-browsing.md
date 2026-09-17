# Operator call browsing

## Scope

Checkpoint 5 of `operator-login-and-admin-dashboard.md`: let an installation operator browse one
tenant's calls, optionally filtered by the stable public identity of a call definition. Call-detail
navigation remains disabled until checkpoint 7 supplies the operator-session inspection page.

## Decisions

- Calls owns the authorized workflow and repository-neutral directory structs. Console supplies the
  installation-operator authority; it does not manufacture tenant API-key authority.
- A definition filter matches `call_definitions.public_id` after joining each call through its pinned
  immutable revision. This includes calls made from every revision of the selected definition while
  retaining the pinned revision name and version in each row.
- The filter selector is bounded to 100 definitions, ordered by current name and stable public ID.
  A directly selected definition outside that window is appended after an exact tenant-scoped lookup
  so a deep link remains representable.
- Archive state reflects the latest call-details publication completeness. Calls without a latest
  publication report `unconfirmed`; no archive payload is read for this directory.
- Production call rows are noninteractive in this checkpoint. The approved Storybook component keeps
  its default detail link for the checkpoint 7 composition.
- Browser state lives in the tenant-scoped URL. Changing or clearing the definition filter returns to
  page one, and out-of-range recovery retains the filter.

## Red/green evidence

- Focused Calls, Persistence, Console endpoint, typed-client, and AdminApp tests failed before the
  call directory port, query, endpoint, parser, and route existed.
- The frontend recovery test initially observed only the first request because it asserted against a
  heading already present during loading. It now waits for the recovered response's call row before
  checking the second request.
- A review of test fixtures found the definition-directory and call-filter summary structs swapped in
  two fake-repository fixtures. Correcting the fixtures preserved passing behavior and made each test
  assert its actual port contract.

## Verification

- Calls: 97 tests pass.
- Persistence: 149 tests pass with 11 integration exclusions.
- Console: 176 tests pass with one integration exclusion.
- Console assets: 97 tests pass; TypeScript and ESLint pass.
- The Impeccable mechanical detector reports no findings in the changed frontend files.
- Headless Chrome verified the real operator login, all-calls and definition-filtered URLs, filter
  reset, browser back, refresh restoration, and the approved call table at 1440×900 and 390×844.
- A Storybook edge state verifies the compact disclosure for more than 100 filter options at desktop
  and mobile sizes.
- The full umbrella suite passes, including 438 Gateway tests and its WebRTC lane. Formatting,
  warnings-as-errors compilation, strict Credo and unused-dependency checks also pass.
- GPT-6 Astra xhigh found the missing truncation disclosure and filtered-row consistency check. Both
  were added with focused red/green coverage; the corrected implementation received final approval.
