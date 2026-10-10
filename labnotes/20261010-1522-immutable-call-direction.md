# Immutable call direction

## Scope and decisions

- Replace human handshake icons with UserRound consistently on graph nodes,
  inspector headings, add-human actions and transfer destinations.
- Group revision/publication/unsaved indicators with the editable name at the
  header's left. Give the back link its own compact section and divider, with no
  separately bordered button.
- Ask for incoming/outgoing before constructing a new editable spec. No direction
  is preselected. Outgoing requires an explicit configured phone service; missing
  services link to setup. Cancel returns to the list without persisting a spec.
- Keep the existing first-save lifecycle: creation opens an unsaved draft, and
  Save draft allocates the server identity. The editor and JSON preserve the
  direction selected at creation; changing direction requires another spec.
- Enforce direction across revisions in the owning Calls save workflow, comparing
  against revision one before writes. This covers Console/API/trusted host saves
  and retry after insert conflicts. Existing revisions are not modified.
- Preserve legacy incoming revisions. No speech state machine or source schema
  cutover is changed, so Lean verification does not apply.
- Work in the same checkout and keep Storybook on 6006. Preserve earlier task and
  unrelated changes; no commits requested.

## Evidence so far

- Backend red: the new immutability case failed because a changed direction was
  saved. Green: 12 CallSpecs tests passed, covering both directions, legacy input,
  no revision on rejection, and subsequent same-direction edits.
- Frontend red: five failures for creation gate, missing-service/cancel state,
  JSON direction changes and the remaining direction switch. Outgoing seed test
  also failed before implementation.
- Frontend focused green: 43 tests across five files. Typecheck passed.

## Final verification

- Full frontend suite: 534 tests in 69 files passed. Removed unused call-settings
  lookup props after the direction switch was deleted; typecheck and lint pass.
- Full Calls application suite: 142 tests passed. Console authoring endpoint suite:
  11 tests passed. Root format, compile with warnings as errors, strict Credo and
  unused dependency lock checks passed. Storybook production build passed.
- Root test run again reached the existing Ortex macOS NIF error (`mis-aligned
  LINKEDIT string pool`) in speech tests. Stopped the run after confirming that
  environmental failure; do not interpret focused green suites as a green umbrella.
- Chrome inspection covered dark/light at 1440px and 390px: human node/toolbar/
  inspector icons, compact divided back section, nearby revision and unsaved text,
  initial unselected creation state, outgoing service selection and creation,
  incoming creation and responsive header. The chosen direction has no switch.
- Initial rendered inspection exposed an old negative margin clipping short header
  names by 4px; removed it and reduced mobile action padding. Confirmation showed
  the corrected name sizing and no page-level horizontal overflow.
