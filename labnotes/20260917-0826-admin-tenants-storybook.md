# Admin tenants Storybook

## Scope

Implement checkpoint 1 of the operator-admin Storybook milestone: establish the Console-owned
Storybook and render the tenant directory from deterministic view models. This checkpoint does not
add Phoenix routes, endpoint clients, persistence, authentication, or production application code.

## Decisions

- Kept admin concepts in `apps/vxpipe_console/assets/src/admin`; reusable call state and call UI
  remain owned by `@vxpipe/core` and `@vxpipe/react`.
- Used source-owned React components with Tailwind utilities, Radix Slot, CVA, and the existing
  Vxpipe visual language. Presentation components receive serializable state and injected actions.
- Used real `/admin/tenants/:tenant_key` links. The Storybook harness intercepts ordinary primary
  clicks so later checkpoints can compose the same pages into a linked in-memory journey.
- Kept empty, unavailable, loading, and populated states distinct. Tenant identity uses the stable
  tenant key and the user-facing tenant name.
- Added ESLint for the Console TypeScript package. Enabling it exposed unused historical type
  imports in `CreateRoomPage.tsx`; those imports and the unused local alias were removed without
  changing runtime behavior.

## Red-green-refactor evidence

- The focused `TenantsPage` test was written first. Its initial run failed because
  `./TenantsPage` did not exist.
- The first green implementation exposed a semantic issue: an anchor with `role="row"` was no
  longer discoverable as a link. The list was refactored to native `ul`/`li`/`a` semantics and the
  focused tests remained green.
- Independent review found that modified link clicks were intercepted and the deterministic
  pagination fixture advertised a third page it could not reach. Two focused regressions failed
  for those exact reasons; the link now preserves browser modifier behavior and the fixture reaches
  a final third page whose Next action is disabled.
- The same review reproduced a broken preview reload after story selection because the harness had
  replaced the iframe pathname. A focused regression now keeps the preview document URL intact and
  records the intended `/admin` destination in a story-local hash until the linked journey exists.
  It also identified Storybook 10's removed `defaultViewport` option and reduced-motion behavior;
  the narrow story now uses the supported viewport global and skeleton animation honors reduced
  motion.
- The focused contracts cover real-link tenant selection, valid pagination actions, distinct
  empty/unavailable states, and loading state action removal.

## Verification

- `npm test`: 8 files, 29 tests passed.
- `npm run check`: passed.
- `npm run lint`: passed.
- `npm run build-storybook`: passed. Vite reported only third-party Lucide `"use client"` notices
  and its ordinary large-chunk advisory.
- Rendered Storybook inspection passed for populated, loading, empty, unavailable, long-content,
  paginated, narrow-screen, dark, and light states.
- Desktop and 390 × 844 mobile inspection found no page overflow. The long-content mobile fixture
  reported equal document scroll and client widths (390 px).
- Storybook 10 applied the Narrow story at exactly 390 px. Under browser-emulated reduced motion,
  the loading skeleton's computed `animation-name` was `none`.
- Browser console inspection found only Vite connection and React development-tool notices; no
  application errors were present.
- Light mode retained neutral row and surface backgrounds; unavailable state alone used the
  semantic error color.

## Next checkpoint

Build the tenant definitions page from separate definition models, fixtures, rows, status
presentation, and page composition. Add breadcrumbs and generalize pagination while preserving the
tenant directory behavior.
