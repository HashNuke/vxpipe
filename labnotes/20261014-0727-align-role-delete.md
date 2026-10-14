# Role editor hierarchy and delete alignment

## Requests and implementation

- Move Delete role to the opposite end of its row; keep explanatory copy left.
- Distinguish Permissions from individual permission names with a 20px heading
  (resource names remain 14px). Preserve the existing typeface and palette.
- Use a wrapping flex row for deletion; actions stay right-aligned when narrow.
- This is presentation-only; no permission or deletion behavior changed.

## Verification

- Rendered Storybook role details in headless Chrome at 1440px and 390px.
  Heading hierarchy and deletion alignment verified; mobile wraps the button
  below the copy and retains right alignment.
- Permission editor tests (7), TypeScript and ESLint passed.
- Root format, warnings-as-errors compile and strict Credo passed.
- Authentication page/application tests (25) passed, for 32 focused frontend tests.
- Full root suite passed: 3,788 tests, zero failures, 134 excluded.
- Unused dependency check and diff whitespace check passed.
