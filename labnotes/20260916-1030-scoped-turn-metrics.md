# Scoped and turn metrics

## Goal

Represent the requested room, room-capability, participant and participant-capability metric
scopes, and expose metrics correlated to one message from an icon immediately after its time.

## Red / green

- Red: added one test for the four scope headings and one for a focused turn-metrics trigger. Both
  failed because metrics were flat and message headers had no trigger.
- Green: added the discriminated `MetricScope` Core contract, grouped Metrics rendering and
  optional per-message metrics. The focused suite passes 8 tests.

## Decisions

- Missing scopes are omitted. Participant names are resolved from the authoritative snapshot;
  unknown IDs remain visible instead of being guessed.
- Turn metrics exist only when the adapter correlates them to that message. The aggregate Metrics
  tab still contains the same observation under its authoritative scope.
- `@floating-ui/react` owns hover/focus positioning, viewport shifting, flipping and dismissal.
  The tooltip is portalled and receives the active light/dark theme explicitly.
- The Metrics tab starts directly with scope sections. The redundant “Metrics” introduction and
  the clock/audibility footnote were removed from the component.

## Verification

- `npm test -- --run packages/react/test/console.test.tsx`: 8 tests, 0 failures.
- `npm run check`: both workspaces build and the root TypeScript check passes.
- Rendered Chromium inspection passed for the dark turn tooltip at 1440 × 1000 and the scoped
  Metrics tab at 1440 × 1000 and 360 × 800. Hover placement stayed within the viewport; the
  mobile table retained the measurement/value hierarchy.
