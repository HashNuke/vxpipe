# Anchor service modal

- User reported the service modal shifting vertically whenever provider fields change.
  Source confirmed vertical centering (`place-items: center`) recalculated its top edge.
- Before changing CSS, Chrome measured top positions of 379.5, 278.5 and 131.22 px for
  the empty picker, Deepgram and Telnyx at 1440x1000. The stable-position assertion failed.
- Added an opt-in top anchor to SetupDialog, enabled only for ServiceSetupModal. Other
  dialog positioning is preserved. Desktop offset is capped at 64 px and mobile is 12 px;
  available height accounts for both margins and long forms scroll inside the modal.
- Chrome then measured [64, 64, 64, 64, 64] through all picker providers on desktop,
  and [12, 12, 12] for empty/Deepgram/Telnyx on mobile. Both assertions passed. At 390x600,
  the dialog remains between y=12 and y=588 and can scroll to its bottom actions.
- User additionally requested the exact tenant note: “Credentials belong to the tenant.
  Saved secrets are never shown.” Updated that copy and removed the unused tenantName
  prop. Platform/inherited credential notes retain their existing scope-specific copy.
- No new unit tests for this small layout/copy edit. Used browser geometry before/after
  plus the existing 36 modal/onboarding/form tests, TypeScript and lint; both initial and
  final copy runs pass. Layout detector has no findings. Screenshot evidence is under
  ignored tmp/onboarding-storybook/modal-anchor-*.png.
- No commits, staging or bin/dev management. Existing scoped-service changes in the
  worktree were preserved.

## Follow-up during review

- User requested a single-line webhook input instead of the wrapping textarea, removed
  the API-key helper, and specified the public-key note exactly: “Optional; Only required
  for Telephony services”. Implemented those changes while preserving URL selection and Copy.
- Browser inspection confirms an INPUT, exact tenant/public-key notes and absent API-key
  helper at desktop and mobile widths. The anchored mobile top stays 12 px. Screenshots:
  tmp/onboarding-storybook/modal-copy-desktop.png and modal-copy-mobile.png.
- The 36 focused tests, TypeScript and lint pass after this final refinement; diff checks pass.

- Subsequent review removed the platform credential footer, briefly tried a scope badge,
  then removed that badge at the user's request. The service picker now lives in the
  header after Connect/Manage/Override; the independent Service field is removed.
  SetupDialog retains a text heading for its accessible name, while accepting custom
  visible header content. The dropdown retains its Service accessible label.
- Chrome checked the final Telnyx desktop/mobile and Google mobile states; no scope badge,
  no horizontal overflow, dropdown is in the header, and provider switching still keeps
  the mobile modal at y=12. Screenshots: modal-header-*.png in the ignored evidence folder.
- Updated the existing option-label assertion for “a service”. All 36 focused tests,
  TypeScript and ESLint pass. An initial test invocation from the workspace root selected
  the SDK test config and found no frontend tests; rerunning from the assets directory
  used the intended config.
- Format, compile-with-warnings-as-errors and strict Credo passed. The subsequent umbrella
  test run failed; truncated tool output did not retain its failure details, so reran to
  a log. That retry exposed existing room participant shutdown and audio-egress timing
  failures outside the changed UI code. The participant file passes alone (3 tests).
  The audio-egress file also passes alone (8 tests). Final umbrella retry completed with the same two failures;
  no backend files were changed for these UI-only requests.

- Final user preference keeps only the dropdown in the header: no visible Connect prefix,
  no scope badge, and “Select a service” as the unselected option. The original option
  assertion is restored. Checked desktop empty state and mobile Google selection in Chrome
  (modal-header-final-*.png). Focused frontend checks pass again.
- Unused dependency check passes. Umbrella retry has two unrelated failures described above;
  both affected files pass independently. No backend fixes were made as part of UI review.
