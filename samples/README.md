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
used only by the Vite development proxy. Never store credentials in either
variable; browser clients should obtain scoped, short-lived connection details
from the gateway.

In HTTP mode, set `APP_HOST` to a hostname or interface address to change the
Vite bind host. When `VXPIPE_GATEWAY_URL` is absent, the proxy also connects to
port 4000 on `APP_HOST`. Without `APP_HOST`, Vite binds to `0.0.0.0` and the
proxy uses `http://127.0.0.1:4000`.

By default, `bin/dev` uses trusted HTTPS within the tailnet. Vite listens only on
loopback and Goreman also runs Tailscale Serve on HTTPS port 5173. The machine
FQDN is discovered automatically. This keeps the development server private to
the tailnet while providing the secure browser context required for microphone
access. Run `bin/dev --http` to disable TLS for local troubleshooting.
