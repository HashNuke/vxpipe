# Remove setup services

- Decision: tenant administration has one credential surface at
  `/admin/tenants/:tenant_key/services`. The retired `setup-services` URL will
  redirect there so existing bookmarks do not fall back to the tenant directory.
- Tenant onboarding may continue to use effective service availability for
  readiness, but it must not label credentials as inherited from the platform.
  Platform credential management remains isolated at `/admin/platform/services`.
- Red evidence: `npm test -- --run src/InheritedOnboarding.test.tsx src/App.test.tsx`
  failed 3 of 31 tests before implementation. The failures showed that onboarding
  still exposed two `Inherited from platform` labels, Manage services still opened
  the setup page, and the retired URL still rendered the setup surface instead of
  the tenant inventory.
- Red evidence: the focused platform outage test failed while the platform route
  still rendered tenant-specific “saved progress” and “this tenant’s services” copy.
- A stricter onboarding regression test then failed because inherited provider cards
  were still visible. Filtering tenant onboarding to tenant-owned providers made the
  four focused frontend files pass all 38 tests.
- Browser evidence: isolated headless Chrome confirmed that the retired setup URL
  redirects to the tenant Services tab, where neither the setup link nor inherited
  platform credentials are rendered. Desktop (1440 x 1000) and mobile (390 x 844)
  checks also confirmed the platform outage now uses platform-specific copy.
- Isolated headless Chrome reproduced `GET /admin/api/platform/services` as HTTP 503
  with `service_directory_unavailable`. A direct repository diagnostic resolved the
  local cause to PostgreSQL `undefined_column`: `provider_credentials.scope` is
  absent. `mix ecto.migrations` shows the scoped-provider migration and three later
  migrations are pending. No migration was applied as part of this UI change.
- Final verification: the full frontend suite passed 182 tests; `npm run check` and
  `npm run lint` passed. From the umbrella root, `mix format --check-formatted`,
  `mix compile --warnings-as-errors`, `mix credo --strict`, `mix test`, and
  `mix deps.unlock --check-unused` all completed successfully.
