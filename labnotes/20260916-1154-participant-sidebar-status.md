# Participant sidebar status

## Decision

- Sidebar rows show the participant name and current state. Participant descriptions remain available in the Participants detail view.
- A caller may carry a display-safe connection projection. The sidebar prefixes the caller state with its label, such as `WebRTC · listening` or a phone number supplied by an adapter.
- Inactive and left participants retain the muted row treatment while still naming their state.

## Verification

- Added the focused assertion first and observed the expected failure while the sidebar still rendered `Browser participant` and `Delivery concierge`.
- `npm test -- packages/react/test/console.test.tsx`: 13 tests passed.
- Inspected the ready state in headless Chrome at 1440×1000 and 390×844. Names, caller connection method, states, muted styling, and horizontal mobile roster remain readable.
