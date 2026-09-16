# Tenant call routes

## Decision

Console call resources follow the Gateway's tenant hierarchy:
`/tenants/:tenant_key/calls/...`. This applies to the call list, server-rendered detail, immutable
details downloads, recordings, the React console host, and its inspection JSON resource.

The tenant in the URL is routing context, not authority. `RequireTenant` compares it with the
tenant in the signed operator principal and returns 404 before a controller or LiveView performs a
call lookup. Calls workflows continue to receive the authenticated principal rather than trusting
the path parameter.

The shared LiveView WebSocket remains at `/calls/live`; it is transport infrastructure rather than
a call resource and its signed session still carries the tenant principal.

## Red-green evidence

- Updated host and JSON endpoint tests first; all 11 failed because the tenant-scoped routes did
  not exist.
- Added tenant-scoped routing, URL/session validation, host data, and the tenant-aware frontend
  loader. The 11 focused host/JSON tests then passed.
- Updated the remaining call routes and generated links. The 47 focused Console route,
  presentation, details, recording, host, and JSON tests passed.
- The 11 focused Console asset loader/host tests and TypeScript check passed.
- Astra review found that connected LiveView patches bypassed the mount-only tenant check. Added
  tenant validation to both LiveViews' `handle_params/3` callbacks and regressions for list and
  detail patches; the focused file now passes 23 tests and performs no mismatched-tenant reads.
- The complete Console suite passed with 137 tests, and the full umbrella suite passed.
- Root format, warnings-as-errors compile, Credo strict, and unused dependency checks passed.
- Chrome followed an unauthenticated tenant-scoped Console URL to the operator sign-in page as
  expected.
