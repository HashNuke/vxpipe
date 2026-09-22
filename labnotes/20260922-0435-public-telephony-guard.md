# Public telephony guard

## Goal

Keep the full Console private while allowing a configured telephony host to
receive carrier callbacks and media connections.

## Changes

- Moved sample pages and admission APIs under `/admin/samples` with
  installation-operator authentication.
- Moved diagnostics and LiveDashboard under `/admin/diagnostics` with the same
  authentication, including the diagnostics LiveView socket.
- Removed the root home route; `/` now returns 404.
- Added `TelephonyHostGuard`. When `TELEPHONY_HOST` is configured, its host
  allows Telnyx/Twilio webhook and media paths plus `/healthz`; other hosts are
  unchanged.
- Added the telephony host to runtime configuration and authenticated socket
  session validation.
- Validated the full Phoenix session map in the diagnostics socket instead of
  assuming the nested operator grant was passed directly.
- Removed the unused `/calls/live` socket. Diagnostics now use the dedicated
  `/admin/diagnostics/live` socket, with LiveView mount and socket host checks.
- Added the same public-host rejection to the development live-reload socket.
- Added a CSRF token to the protected sample SPA so its authenticated admission
  requests pass the existing browser API protection.

## Verification

- Focused endpoint, diagnostics, and guard tests pass.
- Console ExUnit suite: 189 tests, 0 failures (1 excluded).
- Console asset tests: 196 tests, 0 failures.
- Endpoint socket checks include authenticated diagnostics, public-host
  rejection, and local-only live reload behavior.
- `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix credo --strict`, and `mix deps.unlock --check-unused` pass.
