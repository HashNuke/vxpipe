# Vxpipe

**TODO: Add description**

## Development

The development stack requires Elixir, Node.js and npm, a Rust toolchain,
`pkg-config`, OpenSSL development headers,
[Goreman](https://github.com/mattn/goreman),
[Watchman](https://facebook.github.io/watchman/) with its `watchman-make`
Python client, [Caddy](https://caddyserver.com/), Tailscale, and `jq`. Vite 8
requires Node.js 20.19.x or Node.js 22.12 or newer.

Install the sample frontend dependencies once:

```shell
npm install --prefix samples
```

Then start the Vxpipe umbrella and sample frontend together:

```shell
bin/dev
```

Goreman runs the `vxpipe_call_engine` and `vxpipe_gateway` applications in one
BEAM instance, serves the Vite playground on loopback port 5174, and runs Caddy
as the tailnet-only HTTPS ingress at `https://<machine-fqdn>:5173/`. The machine
FQDN and Tailscale IPv4 address are discovered automatically. Caddy sends
`/api/*` and `/healthz` to the gateway on loopback port 4000 and all other
requests to Vite.

Goreman also runs `watchman-make` in the foreground. Changes to umbrella source,
Mix manifests, or runtime configuration ask Goreman to restart only the
`vxpipe` process. A reload therefore starts a fresh BEAM instance and discards
development rooms, sessions, and WebRTC connections. Test changes do not
restart the development server.

Caddy automatically obtains a certificate for the `.ts.net` hostname from the
local Tailscale daemon. MagicDNS and HTTPS certificates must be enabled for the
tailnet. `bin/dev` renders a complete JSON configuration, obtains sudo once, and
Goreman runs only the Caddy process as root. Mix and Vite continue to run as the
calling user. No `TS_PERMIT_CERT_UID` or manually exported Caddy variables are
required. Caddy binds only to the discovered Tailscale address; it does not use
Tailscale Funnel or make the development stack public.

Use `--http` to omit Caddy and run Vite directly on port 5173 for local
troubleshooting. In HTTP mode, set `APP_HOST` to bind the playground to a
specific hostname or interface:

```shell
APP_HOST=vxpipe.example.ts.net bin/dev --http
```

The repository-root `.env.example` documents optional Goreman process
overrides. A static `APP_HOST` can be placed in `.env` for HTTP mode; HTTPS mode
derives it from Tailscale automatically. Goreman loads `.env` into its child
processes without exporting values into the parent shell.

Without `APP_HOST`, HTTP mode binds Vite to `0.0.0.0`. Vite proxies `/api`
requests to the gateway over loopback in HTTP mode; Caddy owns that routing in
the default HTTPS mode. `VXPIPE_GATEWAY_URL` remains available to override the
Vite proxy target.

The gateway reads its listener and CORS options from the `vxpipe_gateway`
application environment. In development, `APP_HOST` becomes the exact allowed
HTTPS origin on port 5173. Environment variables are read from
`config/runtime.exs`, while `config/dev.exs` only enables the listener.

The playground's **Create room** action creates a supervised room, admits one
human participant, and obtains a five-minute, single-use gateway session. The
gateway supplies its configured development tenant and actor; the browser never
asserts either identity. This development principal is not an authentication
mechanism, and the admission endpoints are disabled by default outside the
repository's development configuration.

The first playground uses the Pipecat Voice UI Kit console and Small WebRTC. It
targets `/api/rtvi/offer`, completes SDP and trickle-ICE signalling, and performs
the RTVI 2.x `client-ready` / `bot-ready` exchange. Incoming audio is not yet
routed through an agent or speech pipeline, so this checkpoint proves admission,
transport, and protocol readiness rather than a voice conversation. The
implemented `/healthz` route verifies the gateway listener.
Set `VITE_VXPIPE_RTVI_OFFER_URL` in `samples/.env.local` to test a different
offer endpoint.
