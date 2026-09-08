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
will move the existing React/Vite sample assets here and add the separate,
protected diagnostics surface. This application does not own Ecto or call
protocol implementations.

## Development diagnostics

The Console uses Phoenix LiveDashboard for platform VM/runtime inspection and
reserves `/diagnostics` for Vxpipe's bounded operational measurements. Both
routes pass through `Vxpipe.Console.OperatorAccess`. Diagnostics are disabled by
default. Repository development enables them only for a client whose direct
socket address is IPv4 or IPv6 loopback, while Caddy deliberately does not route
the diagnostics namespace.

Loopback access is a local-development restriction, not production operator
authentication and not a trusted-proxy policy. Do not expose these routes through
a reverse proxy or non-loopback listener. A call token, tenant identity, public
call ID, or tailnet reachability grants no diagnostics access. External
deployment remains disabled until a production operator-auth mechanism is
configured and enforced at both HTTP and LiveView subscription boundaries.
