# Transfer edge navigation

## Scope and direction

- Clicking a transfer edge selects its source participant and opens the
  Transfers tab in the sidebar, including the narrow-screen sheet.
- Removed the redundant source/target/delete edge inspector and its separate
  selection state. Transfers remain editable through the existing destination
  controls. Read-only revisions keep those controls disabled. Also removed the
  display row helper whose only active consumer was the deleted inspector.
- The locked Entry connection opens Entry's Connection tab.
- Inspected the incumbent Storybook interaction before editing. The existing
  edge panel showed only Source, Target, and Delete transfer.

## Verification

- Added focused behavior coverage first for desktop/mobile selection, read-only
  controls, returning to Transfers after switching tabs, Entry routing, and
  removing one destination while preserving the others. The initial run failed
  six tests because the previous edge view did not provide those controls.
- Focused editor/inspector tests: 30 passed. Complete Console frontend suite:
  565 tests passed across 71 files. TypeScript and ESLint passed.
- Rendered Chrome inspection at 1440x960 and 390x844 confirmed that clicking the
  transfer edge selects intake and opens Transfers in the sidebar or mobile
  sheet. Switching to Prompt and clicking the edge again returned to Transfers.
  Removing specialist through the mobile destination control removed its edge
  and kept the source inspector open. No duplicate edge view remains.
- Root format, warnings-as-errors compilation, strict Credo, unused dependency
  checks, and whitespace validation passed. Full umbrella suite passed:
  3,564 tests, zero failures, 128 existing integration/live exclusions.
- The referenced `docs/milestones/index.md` is absent in this checkout. Updated
  the existing call spec editor source documentation for the new navigation.
