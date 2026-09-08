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
