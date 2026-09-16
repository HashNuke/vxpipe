# Neutral timeline surfaces

## Finding

The tool-call row mixed 7% violet into the panel surface. In light mode the computed result was a pink-tinted background (`oklch(0.957 0.01631 354.198)`), which visually suggested an error even for completed and pending tools. Activity events were already transparent and raw log rows already used the neutral panel token.

## Decision

Use the neutral panel surface for every tool-call row. Keep tool identity on the violet wrench and left border, and reserve red for the explicit failed status icon and HTTP error badge.

## Evidence

- Browser: inspected the human-handoff conversation in light mode at 1280×900. The tool row and panel now both compute to `oklch(0.985 0 0)`; activity events remain transparent.
- Frontend: `npm test` (22 tests), `npm run check`, and the Storybook production build pass.
- Umbrella: formatting, warning-free compilation, strict Credo, and `mix deps.unlock --check-unused` pass. Full `mix test` reported one unrelated `Vxpipe.CallEngine.LiveInspectionTest` failure after its test kills the inspection buffer and then expects the receiver participant to remain available. The exact focused rerun failed at the same assertion with `:participant_not_found`; the immediately preceding checkpoint's full suite passed before this CSS-only change.
