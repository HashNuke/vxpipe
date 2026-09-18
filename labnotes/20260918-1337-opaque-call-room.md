# Opaque call-room surface

## Progress

- Added a focused CSS contract first and confirmed it failed because the
  call-room surface used a translucent white fill in both themes.
- Replaced that fill with theme-specific opaque surfaces: `#18191c` in dark
  mode and `#f8f9fb` in light mode. The component's own low-opacity radial
  accents remain layered above the solid base.
- The focused call-room visual test passes.
- Browser verification checked the computed surface values in both themes and
  confirmed that page artwork no longer shows through the panel.
- Previewed three nonpersistent page-background directions in Chromium at
  1440x1000 in both themes: Soft Focus, Open Wave, and Dual Signal. No backdrop
  alternative was initially written to the source pending selection.
- The user selected Open Wave. Added a failing CSS contract for its left-offset
  wave origin, then replaced the centered ripple treatment and made the focused
  contract pass.
- Rechecked the selected backdrop and opaque call-room at 1440x1000 and 390x844
  in dark and light themes. All four renders had viewport-width scroll bounds;
  computed call-room surfaces were `#18191c` and `#f8f9fb` respectively.
- Replaced a pre-existing literal landing-page heading size with the equivalent
  Starlight typography token, clearing the design-hook finding without changing
  the rendered scale.

## Notes

- The Impeccable live picker is not configured for this Starlight project, so
  the alternatives were injected as temporary browser-only CSS and captured to
  `/tmp/vxpipe-background-options/`.
- The design audit reports existing custom values throughout the call-room
  component. They predate this focused surface change and were left unchanged
  without adding broad suppressions.
