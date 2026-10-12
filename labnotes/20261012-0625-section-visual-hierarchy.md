# Section visual hierarchy

## Request and scope

- User found section and field names visually too similar in Call settings.
- Keep existing section/variable authoring behavior and all in-progress changes.
- Use the existing Console theme tokens, shallow panel corners and Lucide icons.

## Implementation

- Shaded section header, folder icon and 16px section title establish the group.
- Indented variable rows, empty state and Add variable action sit beneath it.
- Constraint tags align with the section name; field names retain their 14px
  monospace styling. No new labels, controls or interaction behavior.
- Styling-only change: no new implementation-mirroring tests; verify existing
  authoring tests and inspect rendered desktop/mobile and dark/light states.

## Verification

- Inspected Chrome at 1440x960 and 390x844 in Storybook on port 6006.
  Dark and light themes preserve the header/row contrast; section titles measure
  16px versus 14px field names. Fields are 12px farther inset than section names.
- Renamed a section to student_contact_and_enrolment_information on mobile;
  it wraps without pushing edit/delete actions outside the panel. No page-level
  horizontal overflow at either viewport. Browser session closed after review.
- All 572 frontend tests (71 files), TypeScript and ESLint passed.
- Formatting, warnings-as-errors compilation, strict Credo and unused dependency
  checks passed. Full umbrella: 3566 tests, 0 failures and 128 existing
  integration/live exclusions; no new skips. Final diff whitespace check passed.
- An initial edit command used the assets working directory with root-relative
  paths and failed before writing. Reran from the repository root, then ran the
  frontend suite against the completed styling changes.
