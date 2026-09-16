# Metrics table polish

## Goal

Keep participant naming consistent and make the compact metrics matrix use its space efficiently.

## Decisions

- Centralize the non-transcript caller label as `Caller`; direct transcript attribution remains `You`.
- Reduce metric columns from 144 px to 112 px now that their visible labels are compact.
- Remove cell padding around the Floating UI trigger. The trigger fills the complete 112×64 px value cell, so hover and focus work anywhere in the cell.

## Evidence

- Red: the focused metrics test found the raw `Participant: You` identity instead of `Participant: Caller`.
- Green: the focused console suite passes 17 tests and `npm run check` passes.
- Browser: inspected the Metrics story at 1280×900. The target rows include `Caller`; table width fell from 1,348 px to 1,092 px. A measured data cell is 112×65 px and its Floating UI trigger fills 111×64 px, leaving no inset dead hover area.
