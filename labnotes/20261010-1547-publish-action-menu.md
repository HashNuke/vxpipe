# Publish actions and focus styling

## Changes and decisions

- Join Publish and a vertical ellipsis into one button group. Move Save as draft
  into the existing shadcn dropdown menu. Keep saving available when publication
  is blocked by unsaved changes, missing revision, or validation issues; retain
  read-only, busy, permission and pending-JSON guards.
- Show Saving / Publishing progress in the group's main segment. Both segments
  keep the same background when disabled; only disabled icons/text are muted.
- Place Issues before JSON so JSON stays adjacent to the Publish group. Shorten
  the revision badge to v3, with the full revision label in its title.
- Remove the extra page-wide outline that overrode primitive focus styling.
  Tabs keep one keyboard focus ring. Track pointer versus keyboard input for
  Console roots and portals because browser-restored/scripted button focus can
  still match :focus-visible following a click. Pointer interaction suppresses
  button focus decoration; keyboard navigation restores it. Text inputs retain
  their focus treatment. Listeners are shared and removed on final unmount.
- Work in the existing checkout; retain Storybook on 6006. No commits requested.

## Verification

- Red: the focused header test failed because the Publish actions group did not
  exist. Green: menu opening/selection saves an unsaved spec and closes without
  publishing. Existing integration and Storybook interactions now save via menu.
- Red: the modality test failed because pointer input was not tracked. Green:
  pointer and restored focus, keyboard navigation, modifier-only keys and cleanup.
- Full frontend suite: 536 tests in 70 files passed. Typecheck, lint and Storybook
  production build passed. Root formatting, compilation with warnings as errors,
  strict Credo and unused dependency checks passed during this checkpoint.
- The umbrella test limitation remains the previously reproduced local Ortex
  macOS NIF loader failure (mis-aligned LINKEDIT string pool); the umbrella suite
  is not green. No Elixir or speech changes were made in this checkpoint.
- Chrome inspection at 1440px and 390px covered dark/light menus, a disabled
  Publish beside an enabled menu, issue ordering, compact version badge, save
  feedback and focus restoration. The page has no horizontal overflow at 390px.
- Computed styles confirmed matching group backgrounds and opacity 1 on both
  segments. Pointer-clicked tabs have no outline or focus ring; arrow-key
  navigation restores the keyboard ring and switches the active tab.
- Initial browser interactions were reset by Storybook HMR while editing; the
  final verification used refreshed stories after source edits settled.
