# Prototype Variables tab

## Goal

Add the read-only Variables tab to the isolated Core/React prototype using the approved normalized
snapshot contract.

## Red / green

- Red: added a component test that opens `initialTab="variables"` and expects the authorized
  `intake.requested_date` value plus global revision. It failed because the view did not exist.
- Green: added protocol-neutral JSON/section/snapshot types to `@vxpipe/core`, fixture data and the
  `Variables` React component. The focused suite passes 6 tests.

## Decisions

- `CallSnapshot.variables` is the newest full authorized projection or `null` when unavailable.
- React groups values by section and displays global and section revisions. It does not decode
  RTVI or expose editing.
- The composer appears only in Conversation. Variables and the other inspector views are read-only.
- Structured values use formatted JSON; missing projection and empty sections have distinct states.

## Verification

- `npm test -- --run packages/react/test/console.test.tsx`: 6 tests, 0 failures.
- `npm run check`: both workspaces build and the root TypeScript check passes.
- Rendered Chromium inspection passed at 1440 × 1000 and 360 × 800 in the default dark theme.
  Section grouping, revisions, long-form layout and mobile stacking remained legible without
  horizontal page overflow.
