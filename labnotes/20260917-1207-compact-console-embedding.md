# Compact console embedding

## Scope

- Add a dedicated host-rendered header row without coupling breadcrumb concepts to
  `@vxpipe/react`.
- Add a borderless, cornerless fill layout for full-page hosts.
- Hide the participant rail below 600 px and preserve participant selection inside the
  Participants view.
- Let conversation participant avatars and names open the matching participant details.
- Reduce the control header and device-control footprint.

## Decisions

- Kept `headerContext` for compact call identity in the control row and added a separate
  `header` slot for host navigation or other full-row content.
- Used `layout="fill"` as an explicit opt-in. Existing package consumers retain the framed,
  bounded console by default.
- Added a mobile-only participant picker inside the Participants view. Desktop keeps the
  persistent participant rail as its picker.
- Used separate accessible avatar and name buttons in messages because both visible targets
  must work independently on touch screens.

## Red-green evidence

- Added focused tests for the header/fill contract, message-to-participant navigation, and
  participant selection without the sidebar. The initial run failed in all three cases for
  the expected missing behavior.
- `npm test` in `packages/react`: 33 tests passed.
- `npm run build` in `packages/react`: TypeScript build passed.

## Rendered inspection

- Inspected the Conversation and Participants views in Chrome at 390 × 844 through the
  running Storybook on port 6007.
- The participant rail is absent, tapping an Assistant identity opens Participants, and the
  horizontal participant picker switches the selected details without page-level overflow.

## Review follow-up

- Astra review found that the later mobile `height: 100dvh` rule could override fill mode at
  equal specificity. The fill selector now has higher specificity so a bounded host remains the
  height owner on mobile.
- Astra review also found that opening participant details unmounted the focused message control.
  Selection now transfers focus to the persistent Participants tab, covered by a regression
  assertion.
