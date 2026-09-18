# Allow loopback origins

## Scope and diagnosis

- User requested equivalent `localhost` and `127.0.0.1` socket access during local
  development after Phoenix rejected the numeric loopback origin.
- An earlier automation session named `router-app` remained on the numeric
  loopback admin page with its Phoenix live-reload frame. Closed that session at
  the user's request; no new matching warnings appeared during a 12-second check.
- Runtime development configuration selects one endpoint URL host and inherits
  Phoenix's default host origin check. The application has no explicit local
  loopback alias policy.
- Add an explicit two-origin allowlist for local development, using the configured
  scheme and port. Preserve the default configured-host check for remote
  development and production. The user retains control of `bin/dev`.

## Verification

- Added focused runtime configuration coverage for the default host, explicit
  loopback hosts/custom port, Tailscale development, and production isolation.
- Red: focused child test run produced 4 tests, 2 failures (seed 152403). Both
  alias-policy assertions failed because `:check_origin` was absent; the remote
  development and production assertions passed.
- Implemented the local development origin allowlist; remote development explicitly
  retains `check_origin: true`. Production configuration is unchanged.
- Green: origin configuration and existing operator-login runtime tests passed
  together: 8 tests, 0 failures (seed 954934).
- Headless Chrome loaded the operator login page via both addresses and opened a
  real Phoenix live-reload WebSocket successfully from each origin. Screenshots
  were inspected under ignored `tmp/loopback-origin-check/`. The temporary browser
  session was closed after verification.
- Watchman automatically reloaded the existing development server after the
  runtime configuration change. No manual server lifecycle commands were used.
- An initial root compile hit missing protocol-consolidation output files while
  browser/server reload and compilation overlapped. Re-running the gates
  sequentially passed format, warnings-as-errors compilation, and strict Credo
  (958 source files, no issues). No build/dependency cleanup was necessary.
- `mix deps.unlock --check-unused` and `git diff --check` pass.
- Full umbrella `mix test` passes: 1,724 tests, 0 failures, 39 excluded
  (seed 366405). All five root completion gates pass.
