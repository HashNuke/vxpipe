# Shade editor toolbar

- User requested replacing the white second header row with a shade related to
  the dark top row. The initial muted surface matched the canvas; user clarified
  the toolbar must also differ from the diagram background.
- Blend background and muted tokens equally in OKLCH for the second row, retaining
  theme hues and placing its shade between the top row and canvas. Text and icons
  use the foreground token.
- Hover uses the existing control-hover token over the whole cell. Preserve the
  consolidated layout, callbacks, dividers and disabled states.
- Styling-only change; no new behavior tests required. All 19 focused header and
  layout tests passed; TypeScript, ESLint and git diff --check passed.
- Chrome inspected 1440x960 and 390x844 layouts plus the Add agent hover state.
  Second row is visibly lighter than the top row and text remains readable.
- Initial npm verification used the umbrella root, which has no matching asset
  test script. Reran from the Console assets directory successfully.
- Final Chrome desktop and phone inspection confirmed distinct computed shades:
  top row lightness 0.141, second row 0.2075, canvas 0.274 in dark mode.
- Final 19 focused tests, TypeScript, ESLint and diff whitespace checks passed.
  User requested committing the color refinement.
