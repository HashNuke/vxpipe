# Vxpipe samples

This Vite application is a frontend-only playground for exercising Vxpipe
gateway endpoints. It does not host a Pipecat server or duplicate call-engine
behavior in the browser.

The initial screen uses `ConsoleTemplate` from
`@pipecat-ai/voice-ui-kit`. It pulls in `@pipecat-ai/client-react` and the core
client, and uses the Small WebRTC transport. The default offer URL is
`/api/rtvi/offer`.

From the repository root:

```shell
npm install --prefix samples
bin/dev
```

To run only the frontend:

```shell
npm run dev --prefix samples
```

Copy `.env.example` to `.env.local` when an endpoint differs from the defaults.
`VITE_VXPIPE_RTVI_OFFER_URL` is exposed to the browser. `VXPIPE_GATEWAY_URL` is
used only by the Vite development proxy in HTTP mode. Never store credentials
in either variable; browser clients should obtain scoped, short-lived connection
details from the gateway.

In HTTP mode, set `APP_HOST` to a hostname or interface address to change the
Vite bind host. Without `APP_HOST`, Vite binds to `0.0.0.0`. The proxy uses
`http://127.0.0.1:4000` by default.

By default, `bin/dev` uses trusted HTTPS within the tailnet. Vite listens only on
loopback port 5174 and Goreman runs Caddy on HTTPS port 5173. Caddy routes
`/api/*` directly to the gateway and sends other paths, including Vite's hot
module replacement connection, to the frontend. The machine FQDN and Tailscale
address are discovered automatically. Run `bin/dev --http` to omit Caddy for
local troubleshooting. The HTTPS path may ask for sudo once so only Caddy can
run as root and obtain the Tailscale certificate; the application processes stay
unprivileged.
