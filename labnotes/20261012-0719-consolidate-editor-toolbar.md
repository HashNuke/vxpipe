# Consolidate editor toolbar

## Scope and implementation

- User requested moving Call settings into the bottom Add/Arrange toolbar and
  removing visible text from Arrange and Call settings.
- Added the settings callback and issue count to the toolbar; removed the
  separate canvas settings button. Settings still selects the call-level
  inspector and opens its phone sheet.
- Both icon actions use existing ghost button styling, accessible names,
  and tooltips. Settings retains its visible issue badge and aria-description.
- Add participants remains disabled for read-only/busy specs; Arrange and
  Call settings remain available for inspection.
- Updated the isolated toolbar story and authoring guide.

- Follow-up requested removing nested toolbar layers. Removed the Add group
  background/container and standalone Add label. The toolbar is now one outer
  frame with borderless + AI Agent, + Human, Arrange and Call settings controls;
  outer padding reduced from 8px to 4px.

- User requested a lighter toolbar against the dark chart. Use foreground as
  its surface and background for text/icons, with subtle background-tinted
  hover states. Theme tokens invert the treatment for light mode.

- Follow-up tightened the top header to 4px padding and gaps. JSON and issues
  now use borderless controls; Publish retains primary emphasis with less padding
  and a narrower ellipsis action, without the internal border. Back navigation
  retains its existing divider.

## Tests and verification

- Red: existing layout test expanded to require Call settings inside the
  toolbar and exercise settings/participant navigation on a phone. Failed
  because the old settings button was outside the toolbar.
- Green: 16 focused toolbar/layout tests passed. All 573 frontend tests passed
  after the flattened controls; TypeScript and ESLint passed.
- Chrome inspected desktop 1440x960 and mobile 390x844. One flat toolbar fits
  both sizes, settings opens the phone sheet, and its tooltip is exposed on hover.
  CanvasIssues story confirms the red issue badge remains visible.
- A text-based browser wait was unsuitable for the mobile icon-only CanvasIssues
  state. Verified through a fresh DOM snapshot and direct screenshot instead.
- Formatting, warnings-as-errors compilation, strict Credo and unused dependency
  checks passed. Initial umbrella hit a pre-existing clock-sensitive onset test;
  see the stabilize-onset-test labnotes for its reproduction and fixture fix.
- Final header and toolbar inspected in Chrome at 1440x960 and 390x844,
  including the publish dropdown and light theme. Compact controls fit; the
  mobile header wraps actions into a second row without overflow.
- Final frontend run: all 573 tests passed; TypeScript and ESLint passed.
- Full umbrella rerun passed: 3,566 tests, zero failures, seed 541905.
  No commit requested for this checkpoint.

## Flatten publish follow-up

- User clarified Publish and ellipsis should also be flat toolbar controls.
  Switched both to ghost buttons and removed split-button corner/disabled
  foreground overrides. They share the header surface, with standard hover and
  disabled states. Publish/menu behavior and save gates remain unchanged.
- Verified flat actions in Chrome at desktop and phone widths, including the
  Save as draft dropdown. All 13 header tests, TypeScript and ESLint passed.
  Earlier full checkpoint gates remain recorded above; no runtime logic changed.

## Adjoining header cells

- User clarified flat means dividers between JSON, Publish and ellipsis, with
  hover filling the entire toolbar cell rather than an inset rounded button.
- Removed action-area gaps and wrapper padding; moved title padding to the title
  block. Actions stretch vertically and use square adjoining edges with one-pixel
  dividers. Only the outer right corner remains rounded to match the header.
- Retained publish gates, menu behavior, accessible names and keyboard focus.
- Chrome checked desktop and phone layouts, Publish hover and ellipsis menu.
  Computed styles confirm 40px adjoining cells, square interior corners, and
  a full-cell Publish hover background. All 13 header tests, TypeScript and
  ESLint passed; git diff --check passed.

## JSON editor menu action

- User requested moving the header JSON control into the ellipsis menu and
  naming it JSON editor. Removed the standalone header control and added the
  menu item above Save as draft. Updated the DrawTransfer story interaction.
- The menu stays available for JSON inspection when mutation gates block saving;
  Save as draft remains disabled in those states. Loading still blocks JSON.
- Red: four focused cases failed before implementation (normal, read-only,
  saving forbidden and authoring forbidden). Tests require opening JSON from
  the menu and keeping Save as draft disabled where appropriate.

## Consolidated top toolbar

- User requested moving canvas actions to a second row of the top toolbar, with
  Add AI Agent, Add Human and Arrange on the left and Call settings on the right.
- Header now accepts a toolbar row; layout supplies the existing callbacks.
  Removed floating positioning, nested padding and individual rounded controls.
  The second row retains the contrasting surface, with full-cell hover areas.
- Red: phone layout test failed because toolbar was outside the header.
  Implementation places it inside the header and retains phone-sheet navigation.
- Browser review of JSON menu exposed focus restoration closing the non-modal
  source sheet. Prevent menu close autofocus when selecting JSON editor, allowing
  source-sheet focus to remain in the editor.
- Final consolidated header verified in Chrome at 1440x960 and 390x844.
  Source editor stays open after selecting JSON editor; settings opens the phone
  inspector sheet. No floating toolbar remains.
- Green: 576 frontend tests passed across 71 files; TypeScript and ESLint passed.
  Full umbrella/static verification for the accumulated checkpoint is recorded
  above. User requested committing this checkpoint after completion.
