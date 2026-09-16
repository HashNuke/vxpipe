# Participant connection labels

## Scope

- Label the caller as `Caller` in the participant rail without changing message attribution.
- Show a known live connection method for any participant, including a human joining through WebRTC.
- Keep presence available to assistive technology when connection identity replaces the visible state.

## Evidence

- Red: the focused React test failed because the rail exposed `You` and the joined support participant exposed only `connected`.
- Green: `npm test -- --run packages/react/test/console.test.tsx` passes 15 tests after generalizing the connection projection and adding the human-handoff fixture connection.
- Browser: inspected the human-handoff story at 1280×900 and 390×844 in headless Chrome. The rail shows `Caller · WebRTC`, keeps transcript attribution as `You`, and shows the joined support participant as `WebRTC` with its speaking audiogram.

## Decisions

- Connection identity belongs to a participant rather than to the caller role. The framework contract therefore permits `connection` on every participant.
- The participant rail uses `Caller` as its role-oriented display label. The underlying participant name remains unchanged for transcript attribution and data identity.
