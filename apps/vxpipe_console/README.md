# Vxpipe Console

`vxpipe_console` owns Vxpipe's Phoenix endpoint and browser presentation. It
depends on the reusable `vxpipe_gateway` Plug and mounts its health/API routes
in-process; protocol, session, and WebRTC ownership remain in the gateway.

The console application starts `Vxpipe.Console.Endpoint`. At startup it reads
the gateway's configured HTTP route options once and passes a prepared
`Vxpipe.Gateway.HTTP.Mount` into the endpoint. In a console deployment,
configure `Vxpipe.Gateway.Application` with `http: [enabled: false, ...]` so the
gateway runtime starts without its standalone Bandit listener. The Console
endpoint is then the only listener.

The React voice playground source lives under `assets/`. Phoenix's `esbuild` Hex
integration owns development watching and release bundling; Phoenix LiveReload
refreshes the browser after watched changes. There is no separate frontend HTTP
server or Goreman application. `mix assets.build` writes `app.js` and `app.css`
into the application's ignored `priv/static/assets` directory.
The Console root serves the tracked SPA index and `Plug.Static` serves its
revalidated `/assets/*` files. If either compiled bundle is absent, the root returns
503 rather than a nonfunctional shell. The separate bounded diagnostics surface
remains available at `/diagnostics`. This application does not own Ecto or call
protocol implementations.

No route in this asset path adds authentication. API keys remain scoped to
call-management endpoints and join tokens to call admission; Console and
LiveDashboard pages receive no additional login layer in this milestone.

## Development diagnostics

The Console uses Phoenix LiveDashboard for platform VM/runtime inspection and
reserves `/diagnostics` for Vxpipe's bounded operational measurements. Diagnostics
are disabled by default and may be enabled with the namespaced Console application
setting. Repository development enables the namespace on the same Console endpoint
as the gateway API and React sample.

`Vxpipe.Console.TelemetryReporter` subscribes to the implemented gateway and call-engine
events. It retains only bounded aggregates and the latest runtime sample. Telemetry
callbacks admit events with atomics, reduce them to validated numeric measurements and
closed dimensions, and only then send them locally. Raw metadata and correlation values
never enter the reporter mailbox. Once the configured pending limit is reached, later
events are counted as dropped rather than accumulating in the mailbox. Configure the bound
alongside diagnostics:

```elixir
config :vxpipe_console, :diagnostics,
  enabled: false,
  max_pending_events: 1_000
```

The reporter starts even when browser diagnostics are disabled so it can be enabled at
the routing boundary without changing event ownership. An embedding host may omit the
Console entirely and attach its own handler to the framework-independent events.

The diagnostics page reads the reporter with a short timeout and refreshes only the
latest snapshot. It shows collection freshness and drops, runtime gauges, gateway
request timing, model completion/first-output state, TTS first-audio timing and safe
provider failure categories. Its compact background-tools instrument also shows admission
outcomes, local worker timing, reservation pressure, and completion-mailbox handoff without
tool names, arguments, results, or correlation identities. Missing measurements have explicit
empty states. The page packages its Phoenix LiveView client locally with a content hash and does not
depend on a hosted script. Use its **System dashboard** link for deeper VM inspection
and **Voice console** to return to the separate sample.
The LiveView does not own the Telemetry handler or a second event buffer: disconnecting
it has no effect on collection or call traffic. A replacement reporter detaches a stale
handler with the same stable ID before attaching, starts with an honestly empty snapshot,
and cannot double-count later events.

When the engine's local model fixture is explicitly enabled, the page also shows one-shot
controls for the next model request. These controls exercise only the fixed local success,
delay, failure and no-output scenarios; they are absent when the fixture process is not
configured. They do not modify call input or expose a general provider-control endpoint.

This milestone deliberately adds no diagnostics authentication. Deployments must
control whether and where the opt-in Console endpoint is exposed. API-key authentication
belongs to call-management endpoints, while join-token validation belongs to call
admission; neither credential is an additional login mechanism for Console pages or
LiveDashboard. The same diagnostics setting gates both HTTP routes and new LiveView
socket connections, so a disabled deployment cannot bypass its 404 by connecting to
the socket path directly.
