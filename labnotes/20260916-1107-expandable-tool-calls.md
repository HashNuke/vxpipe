# Expandable tool calls

## Decision

- `ToolCall.request` and `ToolCall.response` are independent optional JSON values.
- A tool row becomes a disclosure control only when at least one payload is present. Rows without captured details keep the same static presentation.
- Payloads start collapsed and render as formatted JSON under explicit Request and Response labels.
- The client adapter owns whether these display-safe payloads are supplied; the React package does not infer or fetch them.

## Verification

- Red: the focused React test failed because no `update_variables` disclosure existed.
- Green: 9 focused console tests pass, including expansion, collapse, and the absence of a disclosure control when no payload is available.
- `npm run check` passes.
- Browser inspection passed at 1440×1000 and 390×844 in dark mode. Request and response render side by side on desktop and stack on mobile.
