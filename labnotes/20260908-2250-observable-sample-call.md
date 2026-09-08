# Observable sample call

Milestone: [Observable sample call](../docs/milestones/observable-sample-call.md), sequence 2.
Started: 2026-09-08.

## Checkpoint 1: reusable gateway mounting boundary

The repository begins this milestone with an optionally supervised standalone Bandit listener
inside `vxpipe_gateway`. Its HTTP endpoint is already a Plug, but it always owns every path it
receives and its mounting behavior is not a public, tested host-composition contract. The test
environment disables the standalone listener while retaining the named session and WebRTC
connection supervisors.

The first slice will red-test a composable gateway mount that:

- claims `/healthz` and the `/api` namespace while leaving host/console pages untouched;
- supports a host path prefix without changing the gateway router's own paths;
- halts after a claimed response so a downstream host router cannot send twice;
- preserves configured CORS behavior; and
- works while the standalone listener is disabled and the gateway runtime remains active.

This boundary is intentionally implemented before adding Phoenix. It gives the future console
one in-process HTTP listener while leaving standalone gateway embedding available and keeping
Phoenix dependencies out of `vxpipe_gateway`.

### Red, green, and verification evidence

- Red command: `mix test test/vxpipe/gateway/http/mount_test.exs` from the gateway child.
- Red result: compilation failed because `Vxpipe.Gateway.HTTP.Mount.init/1` did not exist.
- Green result: `4 tests, 0 failures`.
- Root mounting claims `/healthz` but not `/diagnostics`; prefixed mounting rewrites
  `/voice/healthz` to the existing gateway route and records `voice` in `script_name`.
- A mounted preflight request retained its configured origin and method response headers.
- An unknown path under the mounted `/api` namespace returned the gateway's 404 and halted.
- The same test process observed no `Vxpipe.Gateway.HTTP.Supervisor`, while the named session
  and WebRTC connection supervisors were running. The host can therefore own the listener
  without disabling gateway protocol runtime.
- The complete gateway suite passed `43 tests, 0 failures (3 excluded)`.
- Umbrella gates passed `mix format --check-formatted`,
  `mix compile --warnings-as-errors`, `mix deps.unlock --check-unused`, call engine
  `102 tests, 0 failures (1 excluded)`, and gateway `43 tests, 0 failures (3 excluded)`.

## Checkpoint 2: Phoenix Console shell and shared listener

Current Phoenix documentation and Hex metadata identified Phoenix 1.8.13 as the current release.
The new `vxpipe_console` application uses that compatible release with Bandit and a direct
umbrella dependency on `vxpipe_gateway`. It deliberately has no Ecto, separate domain layer,
LiveView, dashboard, or frontend build stack yet.

The Console application prepares `Vxpipe.Gateway.HTTP.Mount` once from the gateway's runtime
HTTP route settings and passes it as endpoint startup configuration. This replaced an initial
working `Endpoint.init/2` implementation after Phoenix 1.8 warned that callback is deprecated.
`Vxpipe.Console.GatewayMount` reads the prepared endpoint configuration and delegates claimed
requests before the Console router. Development configuration disables the gateway's standalone
listener and enables the Console endpoint on the existing port.

### Red, green, and verification evidence

- Red command: `mix test test/vxpipe/console/endpoint_test.exs` from the Console child.
- Red result: `2 tests, 2 failures`; `Vxpipe.Console.Endpoint.init/1` did not exist.
- Green result after the lifecycle refactor: `2 tests, 0 failures` with no warnings.
- The tests serve the Console root and gateway `/healthz` through the same endpoint, retain the
  gateway session/WebRTC supervisors, observe no standalone gateway HTTP supervisor, and prove
  an unknown `/api` route remains a halted gateway 404 rather than falling into Console routing.
- A fresh `bin/dev` run logged only `Vxpipe.Console.Endpoint` at `127.0.0.1:4000`. Socket
  inspection found one BEAM listener on that port. Direct requests to `/` and `/healthz` both
  returned 200 from it.
- Chromium rendered the initial routing shell at 1440x900 and 390x844 with empty browser error
  output. The first launch required the documented `--no-sandbox` flag on this host because
  unprivileged Chromium namespaces are unavailable. This shell is not the milestone's final
  presentation; the existing React sample and separate diagnostics surface remain pending.
- Runtime URL configuration reports the Caddy HTTPS origin when that development mode is active,
  while the sole application listener stays on loopback. The temporary shell uses an empty data
  favicon so browser inspection does not generate an irrelevant Console route miss.
- Final checkpoint gates passed `mix format --check-formatted`,
  `mix compile --warnings-as-errors`, `mix deps.unlock --check-unused`, call engine
  `102 tests, 0 failures (1 excluded)`, gateway `43 tests, 0 failures (3 excluded)`, and Console
  `2 tests, 0 failures`.
