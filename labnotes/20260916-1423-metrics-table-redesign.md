# Metrics table redesign

## Problem

Separate scope sections repeated headings, consumed vertical space, and visually detached a capability such as `STT` from its measurement. The layout also could not compare sparse token, latency, duration, audio, and transport metrics across targets.

## Decisions

- Use one semantic table with one row per authoritative scope identity and one column per observed measurement.
- Preserve the four scope kinds in row metadata: room, room capability, participant, and participant capability.
- Keep the target column sticky while the measurements scroll horizontally and the tab scrolls vertically.
- Render absent target/measurement intersections as an em dash. A missing cell does not imply zero.
- Use Floating UI for every value cell, including unavailable cells. Hover or keyboard focus shows its target, description, formatted value, and source when an observation exists.
- Use compact visible headers (`DUR`, `FTL`, `Mdn TTFT`, `Mdn TTFA`, `RTT`, `Input`, `Output`, and `Cached`) with full measurement names in Floating UI header tooltips. Token cells omit the repeated unit while their tooltips retain it.
- Keep a preferred column order for known semantics and append unknown normalized metrics alphabetically, so new backend measurements remain visible.
- Expand the fixture's existing provider usage example to separate input, output, and cached tokens.

## Evidence

- Red: focused tests failed because the Metrics tab had no table and exposed explanations through separate metric-name buttons.
- Green: the focused console suite passes 17 tests. It verifies the single table, scope row identities, compact token columns, header expansion, and source/description tooltip content.
- Browser: inspected dark and light themes at 1280×900 and light mode at 390×844 in headless Chrome. The fixture renders five target rows and nine columns total; compact headers reduce the table scroll width to 1,348 px versus a 986 px desktop viewport and 390 px mobile viewport. The target column remains sticky.
- Completion: `npm test` (22 tests), `npm run check`, Storybook production build, `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`, full `mix test`, and `mix deps.unlock --check-unused` all pass.
