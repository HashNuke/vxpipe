# Microphone permission state

## Goal

Make the pre-call permission-denied state explicit and decide whether it blocks starting a call.

## Decision

- Keep Call enabled when the microphone is muted, not yet authorized, or denied because the console supports text-only input.
- In the denied state, show the slashed disabled microphone control, disable its device selector, and display `Microphone access is blocked. You can still type.`
- Preserve denial when the fixture starts the text-only call so the UI does not imply permission was recovered.
- A future route-level `audio input required` contract may disable Call with a visible reason; do not infer that requirement from microphone state.
- Present the microphone/input selector and speaker/output selector as two semantic button groups with a shared border seam and complementary corner radii.

## Evidence

- Red: the new pre-call fixture initially fell through to a connected microphone-off state, so neither the denial explanation nor Start call appeared.
- Green: all 25 frontend tests, `npm run check`, and the static Storybook build pass.
- Browser: inspected `Microphone Denied Before Call` at 1280×900. Input and output controls render as joined groups. The denied input group is disabled and slashed, Start call remains enabled, and after starting the call the microphone stays denied while the composer becomes available.
