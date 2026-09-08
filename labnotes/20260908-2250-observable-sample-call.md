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
