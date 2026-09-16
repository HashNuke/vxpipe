# Participant descriptions

## Finding

The call-definition participant already accepts an optional `description` of up to 1,024 characters. Compilation preserves it and the call-details projection includes it when configured. No backend schema change is needed.

## Decision

The client snapshot normalizes an absent participant description to `null`. The Participants tab renders a description only when the definition supplies one. Prototype fixtures no longer invent labels such as `Browser participant`, `Delivery concierge`, or `Rescheduling agent`.

## Evidence

- Red: the focused console test found the invented `Delivery concierge` label in participant details.
- Green: the focused console suite passes 15 tests and `npm run check` passes after making the normalized description nullable and rendering it conditionally.
- Browser: inspected the Participants story at 1280×900 in headless Chrome. The Assistant heading now leads directly into its configured capabilities without an invented subtitle.
