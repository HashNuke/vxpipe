# Metric description tooltips

## Decision

- Metrics tables keep one line per measurement. The label is a focusable explanation control with a small info icon.
- Floating UI shows the existing metric description on hover or keyboard focus and keeps it within the viewport.
- Available per-turn metric controls are blue; disabled controls remain muted. The component selector must outrank the console-wide inherited button color.

## Verification

- Red: the focused test failed because descriptions were still always visible and no explanation control existed.
- Green: 11 focused console tests and `npm run check` pass.
- Browser inspection confirmed the description tooltip in the desktop Metrics story and computed distinct blue/muted colors for available/unavailable turn metric controls.
