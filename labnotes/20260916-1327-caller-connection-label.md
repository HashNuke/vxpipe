# Caller connection label

## Decision

- Caller rows show a presence dot and connection identity without repeating a written state.
- WebRTC displays as `WebRTC`.
- Phone admission displays the adapter-supplied normalized E.164 number.
- The current state remains in the connection label's accessible name and hover title.
- Non-caller participants retain a dot plus the written connected, inactive or left state.

## Verification

- Added the WebRTC/phone assertions first and observed the phone scenario fail while it still used
  the WebRTC fixture.
- `npm test -- packages/react/test/console.test.tsx`: 14 tests passed.
- `npm run check`: package builds and workspace TypeScript check passed.
- Inspected the phone-caller scenario in headless Chrome at 1280×900; the sidebar renders
  `+14155550123` with the same status dot alignment as the assistant row.
