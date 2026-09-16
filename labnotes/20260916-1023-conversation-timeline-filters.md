# Conversation timeline filters

## Goal

Combine messages, semantic activity, tool calls and optional raw RTVI traffic into one ordered
Conversation timeline. Remove the separate Logs tab and handoff notice bar.

## Red / green

- Red: replaced the separate Logs-view test with the user-facing filter contract. It expected
  messages/events/tool calls by default, raw logs off, independent toggles and Reset restoring the
  defaults. The test failed because activity and tool-call rows did not exist.
- Green: added typed `ActivityEvent` and `ToolCall` Core state, a merged time-ordered timeline,
  four filters and Reset. The focused suite passes 6 tests.

## Decisions

- Defaults follow the explicit filter list: Messages, Events and Tool calls on; Logs off.
- Logs are only Core-provided RTVI protocol events and retain repeated observed traffic. Each raw
  entry expands in place to show its safe payload.
- Join, leave and transfer facts are semantic activity rows. The human and agent handoff fixtures
  now say “Support joined” or “Delivery specialist joined” in the timeline and do not set a notice.
- Filters use icon-plus-label controls for clarity and remain horizontally scrollable on narrow
  viewports. Their accessible names describe the resulting Show/Hide action.

## Verification

- `npm test -- --run packages/react/test/console.test.tsx`: 6 tests, 0 failures.
- `npm run check`: both package builds and the root TypeScript check pass.
- Rendered Chromium inspection passed for the human-handoff fixture at 1440 × 1000 and 360 × 800
  in dark mode. The desktop timeline preserved hierarchy; the mobile filters and raw log rows
  remained usable through horizontal/vertical scrolling.
