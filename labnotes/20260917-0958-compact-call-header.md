# Compact call header

## Behavior

`CallConsole` now exposes a presentation-only `headerContext` slot. On regular-width layouts, the
host context, connection state, device controls, duration, and call action share one toolbar row.
The toolbar wraps at narrow widths rather than shrinking or clipping interactive controls.

The Admin call-details page uses the slot for `v<n> · <call-id>` and removes its separate page title
and metadata row. The definition name remains in the breadcrumb. It also hides the global Admin
header on this workspace route while retaining the themed shell. Loading and unavailable states
show the same compact identity outside the console so resource context is not lost.

The composer is one row: the flexible textarea sits left of the Send button, and the redundant
keyboard hint is removed. Transcript message bodies use 14px text with a tighter line height. These
changes recover space inside the reusable console for every host.

Device controls now render as two compact button groups. Each microphone or speaker action is paired
with an ellipsis button; a Floating UI menu shows the current device, marks the selected option, and
allows switching. The accessible button label retains the current selection while the visible header
stays icon-only. The menus support arrow-key navigation and typeahead. The space between the input
and output groups is half the earlier value while the paired buttons inside each group remain joined.

Conversation filters now share the tab row. Regular-width layouts show icon-only toggles with color
for enabled categories and muted icons for disabled categories. At narrow widths they collapse into
a vertical-ellipsis Floating UI menu with icon-and-text checkbox items and a reset action. The active
filter state remains owned by `CallConsole`, so restarting an ended call restores the defaults. The
overflow menu begins at the tablet breakpoint because the participant rail reduces the main pane's
available width before the viewport itself reaches mobile dimensions.

## Verification

- The focused `@vxpipe/react` console tests cover injected context, DOM order, filter behavior, and
  keyboard device selection.
- The focused Admin call-details tests cover the compact context, hidden site header, unavailable
  identity, and expanded console height.
- Package builds passed.
- Headless Chrome rendered the ongoing-call story at 1440×900, 768×1024, and 390×844. The desktop
  toolbar is a single row, and the filter toggles share the tab row. Tablet and narrow viewports avoid
  tab overlap by replacing the filter icons with the inspected icon-and-text overflow menu; the narrow
  toolbar wraps without horizontal overflow.
- Root package build, 35 package tests, and the shared production Storybook build passed. Console
  asset type checking and linting passed.
