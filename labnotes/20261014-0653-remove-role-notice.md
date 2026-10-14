# Remove role notice

- Removed the requested protected-permission-policy subheading from built-in role
  pages. This is a copy-only change; permission behavior is unchanged.
- Recorded the request in the current Console milestone.
- Verified the protected-role Storybook page in Chrome at desktop and 390px widths.
  The subheading is absent and the remaining content aligns normally.
- TypeScript, ESLint and diff whitespace checks passed. No additional copy test
  added for this mechanical change. All five root checks passed (3,788 tests, zero failures, 133 excluded).

## Row and dropdown follow-ups

- Use 12px row padding with matching negative inline margins: hover surfaces extend
  into the page gutter while text stays aligned with headings. Applied to tenant
  lists, roles and recent calls, including the mobile recent-call override.
- Replace edge-aligned native select arrows in authentication forms with a chevron
  inset 12px, reserving text space with 36px right padding.

- Extended arrow spacing to the shared Console native-select rule after the user
  requested application-wide cleanup. Existing custom select triggers already use
  inset icons. Verified the service modal's computed inset (12px) and text reserve
  (36px), as well as the role editor.
- Removed Installation labels. Paired and single scope selectors now occupy a
  separate row, capped at 200px each; narrow screens stack paired selectors.
- Explained the existing separate platform-authoring grant from Calls enforcement:
  it permits referencing shared services on save/publish without permission to
  administer their configuration. No authorization policy changed.
- Full frontend suite: 730 passed; final permission editor tests: 7 passed.
  TypeScript and ESLint passed after the final markup change.

- Removed the Roles page subtitle on request and verified its list hover state.
