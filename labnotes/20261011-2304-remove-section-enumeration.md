# Remove section enumeration

## Scope and decision

- User requested removal of section-level enumeration from the backend and UI.
- Reject `enum` at the section schema root; preserve variable, nested-field and
  array-item enumeration. Sections continue to hold one object.
- Preserve unrelated in-progress agent prompt and section modal changes.
- Existing section enums must be removed through JSON. Do not silently discard
  authored constraints or keep an advanced JSON bypass for a removed feature.

## Red tests

- Added shared editor/Engine validation scenarios: reject a `student_info`
  section enum of complete name/age objects; accept field enums for grade,
  object-valued placement and array items.
- Backend contract suite: 81 tests, 1 expected failure because the section enum
  was accepted. Frontend focused suite: 103 tests, 4 expected failures (schema
  accepted plus Add/Edit/View section dialogs still exposing Allowed values).
- An initial fixture-generation script had a syntax error before writing;
  corrected it and reran the red phase with the actual shared scenarios.

## Implementation

- Backend and client validation reject root `enum` with a field-specific path.
- Section forms hide the enum controls and omit an empty Constraints heading.
- Individual variable controls remain intact; existing required-field tags and
  validation issue focus are preserved.
- Updated the editor guide and source contract, including existing-spec repair.

## Verification

- Focused green: 98 Engine tests and 103 frontend tests passed.
- Full frontend: 572 tests across 71 files passed; TypeScript and ESLint passed.
- Chrome on Storybook port 6006: inspected the section modal at 1440x960 and
  390x844. Renamed contact to student_info on desktop and added student_info
  through the mobile Call settings sheet. No section Allowed values or empty
  Constraints heading remains. Confirmed a field still exposes Enumeration and
  saved its allowed value. Closed the inspection browser session afterward.
- Formatting, compilation with warnings as errors, strict Credo and unused
  dependency checks passed. Full umbrella: 3566 tests, 0 failures,
  128 existing integration/live exclusions. No new skips or exclusions.
- Final diff whitespace check passed. No source-cutover or speech state-machine
  changes, so the Lean lane was not required.
