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

The current root page is the initial shell. The observable-sample milestone
will move the existing React/Vite sample assets here; its separate bounded
diagnostics surface is available at `/diagnostics`. This application does not
own Ecto or call protocol implementations.

## Development diagnostics

The Console uses Phoenix LiveDashboard for platform VM/runtime inspection and
reserves `/diagnostics` for Vxpipe's bounded operational measurements. Diagnostics
are disabled by default and may be enabled with the namespaced Console application
setting. Repository development enables the namespace, and Caddy routes it to the
same Console endpoint as the gateway API while the voice sample remains on Vite.

`Vxpipe.Console.TelemetryReporter` subscribes to the implemented gateway and call-engine
events. It retains only bounded aggregates and the latest runtime sample. Telemetry
callbacks admit events with atomics and send them locally; once the configured pending
limit is reached, later events are counted as dropped rather than accumulating in the
mailbox. Configure the bound alongside diagnostics:

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
provider failure categories. Missing measurements have explicit empty states. The
page packages its Phoenix LiveView client locally with a content hash and does not
depend on a hosted script. Use its **System dashboard** link for deeper VM inspection
and **Voice console** to return to the separate sample.

When the engine's local model fixture is explicitly enabled, the page also shows one-shot
controls for the next model request. These controls exercise only the fixed local success,
delay, failure and no-output scenarios; they are absent when the fixture process is not
configured. They do not modify call input or expose a general provider-control endpoint.

This milestone deliberately adds no diagnostics authentication. Deployments must
control whether and where the opt-in Console endpoint is exposed. API-key authentication
belongs to call-management endpoints, while join-token validation belongs to call
admission; neither credential is an additional login mechanism for Console pages or
LiveDashboard.
