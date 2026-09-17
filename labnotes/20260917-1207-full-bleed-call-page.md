# Full-bleed call page

## Scope

- Make the reusable console the only visible working surface for a ready call-details page.
- Inject tenant/definition breadcrumbs into the console's dedicated host header while retaining
  call identity in the control row.
- Preserve loading, unavailable, and malformed states in the standard admin page frame.
- Keep partial-archive disclosure inside the compact console header.

## Decisions

- The admin host owns breadcrumb URLs, definition context, archive completeness, and call
  identity. It passes breadcrumbs through `header` and call identity through `headerContext`, so
  the React package remains tenant-neutral and the two regions stay distinct.
- Ready states use `layout="fill"` inside a `100dvh` main element. The prior max-width, page
  padding, console border, corner radius, and calculated height are removed.
- At mobile width, the dedicated breadcrumb bar is hidden. A `Back to calls` link targeting the
  definition-filtered Calls page appears immediately before call identity in the console control
  row.
- The mobile call action keeps its accessible name while visually reducing to its Lucide icon,
  allowing status, both device groups, duration, and call action to remain on one row.

## Red-green evidence

- Changed the call-details host test first to require the injected header, fill layout, and the
  absence of the old `headerContext`/`maxHeight` contract. The focused test failed on the missing
  fill layout before implementation.
- `npm test` in Console assets: 76 tests passed.
- `npm run check` and `npm run lint` in Console assets passed.
- `npm test` in `packages/react`: 33 tests passed.
- `npm run build` in `packages/react` passed.

## Rendered inspection

- Restarted Storybook after rebuilding the linked React package to avoid Vite's stale dependency
  cache.
- Desktop Chrome inspection at 1440 × 900 confirmed one edge-to-edge console surface, a dedicated
  28 px breadcrumb bar, separate call identity/control row, and no page gutters or outer frame.
- Isolated mobile Chrome inspection at 390 × 844 confirmed the breadcrumb bar is absent, `Back to
  calls` precedes call identity, the control cluster remains compact, the participant rail is
  hidden, the composer is sticky, and there is no page-level horizontal overflow.
- Tapping an Assistant message identity opened the Participants tab with the compact participant
  picker and selected details visible.
- Light-theme partial-archive inspection at 1280 × 800 kept neutral conversation/tool surfaces and
  showed the compact amber `Partial history` status in the injected header.
- The production Storybook build completed successfully; Vite emitted only the existing dependency
  directive and bundle-size advisories.
