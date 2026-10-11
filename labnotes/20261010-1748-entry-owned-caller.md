# Entry-owned caller

## Change

- Remove Caller from Call settings. Apply the same rule to outgoing Callee;
  both already correspond to the Entry card. Retain Handled by and its existing
  direction-specific choices. Opening settings does not rewrite the source.
- Remove the obsolete reference-changing branch and update missing-entry guidance
  to point to the call spec JSON instead of the removed Call settings selector.
- Document the Entry card's responsibility. Keep the existing checkout, prior
  edits and Storybook server on 6006; no commits requested.

## Evidence

- Red: incoming/outgoing settings checks failed because Caller/Callee selectors
  were still present. Green: 22 focused settings and human-inspector tests passed.
- Typecheck, lint, root formatting, compilation with warnings as errors, strict
  Credo and unused dependency checks passed.
- Full frontend suite: 537 tests in 70 files passed. The required umbrella test
  run again encountered the existing Ortex native-loader failure (mis-aligned
  LINKEDIT string pool); stopped after confirming it. The umbrella is not green.
- Chrome inspection: incoming settings at 1440px and outgoing settings in the
  390px mobile sheet show only Handled by, direction information and Entry guidance.
  The entry participant and its connection remain on the canvas/Entry inspector.
