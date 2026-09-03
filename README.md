# Vxpipe

**TODO: Add description**

## Development

The development stack requires Elixir, Node.js and npm,
[Goreman](https://github.com/mattn/goreman), Tailscale, and `jq`. Vite 8 requires
Node.js 20.19.x or Node.js 22.12 or newer.

Install the sample frontend dependencies once:

```shell
npm install --prefix samples
```

Then start the Vxpipe umbrella and sample frontend together:

```shell
bin/dev
```

Goreman runs the `call_engine` and `gateway` applications in one BEAM instance,
serves the Vite playground on loopback, and exposes it privately through
Tailscale Serve at `https://<machine-fqdn>:5173/`. The machine FQDN is discovered
automatically. The playground sends `/api` requests to port 4000 on that host by
default. Set `VXPIPE_GATEWAY_URL` to change the proxy target.

Tailscale Serve is tailnet-only; do not substitute Tailscale Funnel, which is
public. MagicDNS and HTTPS certificates must be enabled for the tailnet. The
trusted HTTPS origin provides the secure browser context required for microphone
access.

Use `--http` to disable TLS for local troubleshooting. In HTTP mode, set
`APP_HOST` to bind the playground to a specific hostname or interface. The same
host becomes the default gateway proxy target unless `VXPIPE_GATEWAY_URL`
overrides it:

```shell
APP_HOST=vxpipe.example.ts.net bin/dev --http
```

Alternatively, put a static `APP_HOST` value in the repository-root `.env`.
`bin/dev` asks Goreman to load that file into its child processes. It does not
export the value into the parent shell, so `env | grep APP_HOST` remains empty
unless the value was separately exported there.

Without `APP_HOST`, HTTP mode binds to `0.0.0.0` and proxies to the gateway over
loopback. The current gateway skeleton has no network listener yet; `APP_HOST`
is passed through to its process but has no gateway socket to configure until
that listener is implemented.

The first playground uses the Pipecat Voice UI Kit console and Small WebRTC. It
targets `/api/rtvi/offer`; the gateway must implement that endpoint before a
voice connection can succeed. Set `VITE_VXPIPE_RTVI_OFFER_URL` in
`samples/.env.local` to test a different offer endpoint.
