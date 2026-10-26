# Sidebar issue card

- Request: visually contain the integrations-directory outage notice beneath the
  category navigation so it reads as an issue.
- Added a thin Fault Coral border, existing soft issue background, shallow corners
  and 12px padding. Retained the requested copy and accessible retry control.
- Mobile uses the same card below its category selector. Text tint derives from
  existing foreground and issue tokens for both themes.
- Presentation-only CSS change: no behavior changed and no new tests needed.
  Existing directory tests and rendered desktop/mobile verification cover it.
- Verification pending below.

## Verification

- Existing DirectoryProposal suite: 10 tests passed.
- Headless Chrome: inspected 1440×1000 and 390×844, both light/dark themes.
  Notice remains below categories/selector, fits without horizontal overflow, and
  uses the existing semantic colors. Centered the heading against its retry icon.
- Rendered Retry directory clears the notice and restores directory listings.
- Initial capture raced Storybook hot reload; direct story navigation restored the
  render. Final screenshots are in the ignored Impeccable review directory.
- DESIGN.md records the card treatment; no new design tokens or suppressions.
- Formatting, warnings-as-errors compilation and strict Credo have passed.

## Connected status follow-up

- User requested uniform connected indicators across AI, telephony and MCP rows.
- MCPs now show the same 18px double checkmark without a visible Connected label.
  Retained the accessible screen-reader label and hover title; actionable
  reconnect warnings remain visible. This is a presentation-only change.
- Completed umbrella run: 4,470 tests, zero failures, 156 excluded. All five root
  gates passed. Follow-up permissions/loading/modal work is recorded in
  20261025-2101-integrations-review-fixes.md.
