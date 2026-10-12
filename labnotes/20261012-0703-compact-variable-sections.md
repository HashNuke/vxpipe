# Compact variable sections

## Scope and decision

- User requested condensed variable sections after the hierarchy styling pass.
- Keep the shaded section header; replace the folder with a list icon at the
  user’s request. Reduce padding and indentation,
  move constraint tags alongside the section name, and place field metadata on
  the same row as the field name when space allows.
- Use 28px icon controls and Add variable controls within dense section lists.
- Styling-only change: no new runtime behavior or implementation-mirroring tests.

- User also requested an Add variable action in the section header while
  retaining the bottom button, and removal of the section modal description.
- Added a compact plus action using the same variable modal and read-only guard.
- Expanded the existing modal behavior test to exercise both header and footer
  actions. Red run: 1 expected failure because the header action was absent.
- Removed the description; the modal retains its accessible title and field label.

- Font review: reduced section names from 16px to 14px, matching field names
  and sidebar control text. Metadata and tags remain 12px; shaded header and
  list icon establish hierarchy without increasing type size.

## Verification

- Same two-field contact fixture: height reduced from 255px to 149px (42%).
  Header reduced from 91px to 37px; rows from 53px to 37px; footer from 57px
  to 37px. Normal names and metadata fit on one line at desktop/mobile sizes.
- Inspected Chrome at 1440x960 and 390x844, in dark and light themes on port
  6006. A long renamed section wraps safely with its tags; no page-level
  horizontal overflow. Closed the inspection browser afterward.
- All 573 frontend tests, TypeScript and ESLint passed after the header action,
  list icon and modal copy updates. Formatting, compilation
  with warnings as errors, strict Credo and unused dependency checks passed.
- Full umbrella passed: 3566 tests, 0 failures, 128 existing exclusions. One focused frontend case added; no
  exclusions added.
- Final desktop/mobile pass confirmed both Add variable controls, created email
  through the header plus action, and confirmed Edit section contains only its
  title and labeled name field. List icon verified in the rendered header.

- Final font review inspected the actual call-spec-editor-page--default route on
  desktop and its mobile Call settings sheet. Computed section/field names are
  14px, metadata 12px. After this styling adjustment, 22 focused authoring tests,
  TypeScript and ESLint passed. Browser session closed after the review.
