# Metric participant label

## Goal

Make participant-capability targets easier to scan in the metrics table.

## Decision

- Use the capability name as the primary row label.
- Identify its owner with a compact participant badge below it.
- Remove the redundant visible `Participant capability` scope label while retaining an explicit accessible row name such as `LLM, Assistant`.

## Evidence

- Red: the focused table test could only find `Participant capability: Assistant · LLM` and not the proposed `LLM, Assistant` row.
- Green: all 24 frontend tests, `npm run check`, and the static Storybook build pass.
- Browser: inspected the Metrics story at 1280×900. The LLM and TTS rows show the capability name first and an `Assistant` badge below it, without the redundant scope label.
