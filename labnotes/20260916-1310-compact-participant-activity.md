# Compact participant activity

## Decisions

- Sidebar text reports presence as connected, inactive or left. Speaking remains an activity state
  in Core and renders as an animated audiogram attached to the participant avatar.
- Removed the separate speaking/timing strip above the composer.
- Tool request and response details use tabs in one panel so payloads do not form narrow columns.
- `undefined` means a payload was not captured; `null` means it was captured and empty. Empty
  requests and responses have distinct copy. HTTP-backed tools may attach a response status to
  completed or failed calls.

## Red-green evidence

- Focused tests first failed because HTTP statuses, failed response details, compact presence text
  and the avatar audiogram were absent.
- `npm test -- packages/react/test/console.test.tsx`: 13 tests passed after implementation.

## Browser evidence

- Inspected Tool Call States at 1280×900 and 390×844 in headless Chrome.
- Verified Request/Response tab switching, HTTP 200 response display, a failed expandable call,
  explicit no-argument/no-body states, compact connected labels and the avatar audiogram.
- Rechecked the narrow desktop sidebar after preventing presence wrapping and dot shrinkage;
  caller `WebRTC · Connected` and agent `Connected` now share one-line dot treatment.
