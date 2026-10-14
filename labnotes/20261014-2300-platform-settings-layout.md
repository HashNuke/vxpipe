# Platform Settings layout

## Request and design

- Move platform pages to a separate layout without tenant context. Its sidebar contains only permitted platform links and a back action at the top. The regular sidebar exposes one Settings entry.
- Preserve the existing palette, type, row density and mobile Radix drawer. Settings replaces the brand/picker area with Back to tenants and a Settings title. Account access stays in the workspace; logout stays available in both layouts.
- Existing platform URLs remain valid. Settings opens the first permitted platform destination. Tenant links and picker are absent from Settings, including the mobile header.
- User correction: always return to /my-tenants, labeled Back to tenants. Removed all remembered workspace state. Keep /my-tenants in the regular layout even for all-tenant operators so the back action cannot loop into Settings.

## Verification and corrections

- Red: two new shell tests failed on the old combined navigation. Green: 23 initial shell/journey tests passed after the split.
- Initially added return-history regression coverage. After the user correction, the exit always targets /my-tenants, including direct entry and login redirects.
- Added production router coverage for an all-tenant operator returning from a direct Settings visit to the regular directory.
- Browser checked the workspace, Settings, and mobile drawer at 1440x1000 / 390x844. Platform links are grouped under Settings, without tenant context; The first browser pass verified the original return behavior; the fixed directory destination is verified in the correction pass. Layout detector reported no findings before implementation.
- Full frontend run exposed one expected legacy-sidebar assertion and five pre-existing credential-test assertions (native disabled/inline unsupported copy). Updated tests to assert the existing aria-disabled tooltip contract; no credential UI behavior changed.
- Full frontend checks: all 750 tests passed, TypeScript and ESLint passed, production CSS build passed. Light-mode Roles also verified with the Settings sidebar; final layout detector returned no findings. All five root gates passed, including 3,801 backend tests with no failures.

- Final correction verified in Chrome: Back to tenants opens My tenants with the regular sidebar and no tenant selected. Updated focused navigation/authentication tests passed (43 tests), with TypeScript/ESLint green again.
- Follow-up audit found the canonical Phoenix controller also redirected all-tenant users from /my-tenants to /tenants. Added a server regression: expected 200, observed 302 (red). Removed that redirect; kept post-login landing rules unchanged. All 312 Console tests passed after the correction; formatting, compilation, strict Credo and unused-dependency checks passed.

## Shared directory refinement
User moved Tenants outside Settings. Canonical /tenants now serves all scopes;
legacy /my-tenants redirects with supported query parameters preserved. Normal
navigation places Tenants above tenant resource links. Settings retains only
Roles, Users and Services and returns directly to /tenants.
Red evidence: four UI regressions and six endpoint regressions failed before
implementation. Existing server-side tenant authorization/search remains intact.
Updated synthetic test navigation projections to use the canonical directory.

Final verification: 750 frontend tests passed, plus 14 focused navigation tests
after adding legacy query-preservation coverage. TypeScript, ESLint, CSS build,
format, warnings-as-errors compilation, Credo and unused dependency checks passed.
Desktop, mobile drawer and assigned-tenant directory inspected in Chrome.
Full umbrella: 3,802 tests, one unrelated DeadlineTest close timing failure;
all 14 tests in that file passed on focused rerun. All 312 Console tests passed.
