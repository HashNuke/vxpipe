# Style device selects

## Problem and decision

The device fields styled only the closed native `<select>` element. Once opened, the browser or
operating system owned the popup, so it could not match the Vxpipe surface or the quality of a
shadcn Select. Replace both device fields with one exported, compositional Select primitive using
the Radix UI variant supported by shadcn. Keep package-owned CSS instead of adding Tailwind.

The trigger retains the combobox name and disabled semantics. The portalled popup receives the
active light/dark theme explicitly, because it renders outside the console's theme container.
Options include keyboard focus and a checkmark for the current device. Opening motion is brief;
reduced-motion disables it. No other console controls changed.

## Red, green, and verification

- Added a focused test requiring the input-device combobox to open a single option list and apply
  `USB headset` through the public client. It failed against the native controls because both
  always-present native option sets matched, then passed after the Select implementation.
- jsdom lacks `scrollIntoView`, which Radix uses when positioning the current option. Added the
  conventional test-environment stub; browser behavior is untouched.
- `npm test`: 10 tests passed. `npm run check` passed both package builds and strict TypeScript.
  `npm run build-storybook` completed with the existing bundle-size advisory.
- Rendered Chrome inspection covered the opened input menu in dark desktop, dark 360 px mobile,
  and light desktop. The popup matches trigger width, stays within the viewport, shows the selected
  checkmark, and uses the correct theme. Keyboard ArrowDown + Enter changed the selected input to
  `USB headset`. Focus returned visibly to the trigger.
- The design hook initially rejected a new literal shadow color. Replaced it with a translucent
  mix of the existing popup border token. No detector suppression was added.

The Storybook server was restarted after the new dependency so Vite would optimize Radix cleanly.
Public shadcn registry hosting remains a separate distribution checkpoint.
