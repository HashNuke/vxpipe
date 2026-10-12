# Compact wait sounds

- Removed the border, corner radius and padding from each wait-sound group.
  All four selectors now form a single compact stack with consistent spacing;
  an Audio URL field stays grouped with its selector when chosen.
- Styling-only change: existing wait-sound behavior and source mapping are
  unchanged, so no new behavior test was added.
- Existing settings panel suite: 15 tests passed. TypeScript and lint passed.
- Rendered Chrome review passed for the default editor at 1440px and the wait
  sounds panel at 390px, including Audio URL and Silence selections.
- Root gates passed: formatting, warning-free compilation, strict Credo, 3,572
  umbrella tests with zero failures, and unused-dependency checks. No speech
  state-machine or source-cutover change; Lean verification is not applicable.
