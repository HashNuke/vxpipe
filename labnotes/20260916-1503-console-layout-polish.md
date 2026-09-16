# Console layout polish

## Goal

Keep device controls and the call action on one row, then make participant rows use the full sidebar width without clipped selection surfaces.

## Decisions

- Put connection state and elapsed duration directly below the call button as a compact metadata line.
- Make each desktop participant button a full-width, square-edged row. Keep only the sidebar heading inset.
- Preserve compact rounded participant buttons in the horizontal mobile rail.

## Evidence

- `npm test`: 22 tests passed.
- `npm run check`: package builds and TypeScript checks passed.
- `npm run build-storybook`: static Storybook build passed; Vite reported only dependency directive and bundle-size warnings.
- Browser: inspected the human-handoff story at 1280×900 and 600×900. The desktop devices and call action share one row, call metadata sits below the button, participant rows fill the 227 px rail with zero border radius, and the narrow viewport has no page overflow.
