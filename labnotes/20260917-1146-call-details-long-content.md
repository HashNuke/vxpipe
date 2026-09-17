# Call details long content

## Purpose

Close the final Storybook coverage gap for long tenant, definition, prompt and transcript content on
the Call details page.

## Red-green-refactor

- Added a focused fixture test first. It failed because `long-content` fell through to the malformed
  response state.
- Added the typed `long-content` fixture scenario and its Storybook export.
- Kept the variation in fixture construction; the page and reusable CallConsole gained no
  scenario-specific behavior.
- The focused fixture test now passes and verifies long tenant/definition context, system prompt and
  assistant transcript content.

## Rendered review

- Desktop at 1440 × 1000: breadcrumbs, toolbar, participant rail, transcript and sticky composer
  remained bounded and readable.
- Mobile at 390 × 844: long context truncates within the breadcrumb, transcript text wraps inside the
  scrollable pane, the composer remains sticky and `scrollWidth` equals `clientWidth` at 390 px.

## Verification

- Console TypeScript check passed.
- Console ESLint check passed.
- Console suite passed: 17 files, 76 tests.
- React suite passed: 3 files, 30 tests.
- Storybook 10.6.0 production build completed successfully.
