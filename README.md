# Vxpipe

**TODO: Add description**

## Development

The development stack requires Elixir, Node.js and npm, a Rust toolchain,
`pkg-config`, OpenSSL development headers,
[Goreman](https://github.com/mattn/goreman),
[Watchman](https://facebook.github.io/watchman/) with its `watchman-make`
Python client, [Caddy](https://caddyserver.com/), Tailscale, and `jq`. Vite 8
requires Node.js 20.19.x or Node.js 22.12 or newer.

Install the Watchman Python client as an isolated user-level tool:

```shell
uv tool install pywatchman
```

Install the sample frontend dependencies once:

```shell
npm install --prefix apps/vxpipe_console/assets
```

Then start the Vxpipe umbrella and sample frontend together:

```shell
bin/dev
```

Development enables Gemini model inference plus the Deepgram Flux
speech-to-text and text-to-speech capabilities. Put development credentials in
the ignored repository-root `.env` file before starting the stack:

```shell
DEEPGRAM_API_KEY=replace-with-a-development-key
GEMINI_API_KEY=replace-with-a-development-key
```

For a deterministic local model boundary, set `VXPIPE_DEV_MODEL_FIXTURE=true`
instead of supplying `GEMINI_API_KEY`. The fixture keeps Deepgram speech enabled,
so spoken sample output still requires `DEEPGRAM_API_KEY`. With the fixture enabled,
the diagnostics board exposes one-shot **Success**, **Delay**, **Failure**, and
**No output** controls for the next model request. Values `delay`, `failure`, and
`missing` may also select the initial/default outcome. The fixture is disabled in
base configuration and never reads a switch from call input.

Goreman loads the credentials into its child processes, including Watchman
restarts. Reusable call-engine code receives provider options through the OTP
application environment and does not read these environment variables directly.

Goreman runs the call engine, gateway, and Console applications in one BEAM
instance, serves the Vite playground on loopback port 5174, and runs Caddy
as the tailnet-only HTTPS ingress at `https://<machine-fqdn>:5173/`. The machine
FQDN and Tailscale IPv4 address are discovered automatically. Caddy sends
`/api/*`, `/healthz`, and `/diagnostics*` to the Console endpoint on loopback
port 4000 and all other requests to Vite.

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

The repository-root `.env.example` documents the development credential and
optional Goreman process overrides. A static `APP_HOST` can be placed in `.env`
for HTTP mode; HTTPS mode derives it from Tailscale automatically. Goreman loads
`.env` into its child processes without exporting values into the parent shell.

Without `APP_HOST`, HTTP mode binds Vite to `0.0.0.0`. Vite proxies `/api`
requests to the gateway over loopback in HTTP mode; Caddy owns that routing in
the default HTTPS mode. `VXPIPE_GATEWAY_URL` remains available to override the
Vite proxy target.

The gateway reads its listener and CORS options from the `vxpipe_gateway`
application environment. In development, `APP_HOST` becomes the exact allowed
HTTPS origin on port 5173. Environment variables are read from
`config/runtime.exs`, while `config/dev.exs` only enables the listener.

The playground's **Create room** action asks the gateway to compile its configured
trusted sample definition into a fresh pinned plan. The engine starts only the web
caller and receiving agent, while the same response supplies a five-minute,
single-use gateway session bound to that existing caller. The gateway supplies its
configured development definition, profiles, tenant, and actor; the browser never
asserts those values. This development principal is not an authentication mechanism,
and the admission endpoints are disabled by default outside the repository's
development configuration.

The first playground uses the Pipecat Voice UI Kit console and Small WebRTC. It
targets `/api/rtvi/offer`, completes SDP and trickle-ICE signalling, and performs
the RTVI 2.x `client-ready` / `bot-ready` exchange. Incoming Opus audio is routed
through a bounded, protocol-neutral media ingress to Deepgram Flux. Flux turn
signals become RTVI speaking and replacement-transcription messages; a committed
turn is sent through the room's participant-owned Jido agent using the pinned Gemini
model profile. Its
complete text response is streamed through Flux TTS as 48 kHz linear16, encoded
to 20 ms Opus packets, and paced onto the negotiated browser audio track. RTVI
bot speaking boundaries and 2.x bot-output progress follow the gateway's paced
output queue rather than provider generation completion. Microphone RTP
continues through the bounded STT ingress while bot output is playing. A
provider `StartOfTurn` interrupts current and queued agent work immediately,
stops unsent RTP, and attributes the
interruption to the authenticated participant connection; its later committed
transcript begins the replacement model and spoken response. This uses hosted
provider turn detection, not local VAD. Typed RTVI input with
`run_immediately: true` uses the same cancellation path, while
`run_immediately: false` remains queued. Provider bursts are absorbed by a
bounded ten-second packet queue and then backpressured while RTP drains; later
spoken outputs are announced and played in order. Without provider word
timestamps, spoken text stays pending until paced playout completes rather than
using a character estimate. The implemented
`/healthz` route verifies the gateway listener.

The development agent also exposes the engine-owned `get_current_time` tool.
Asking for the current UTC time exercises a model/tool/model loop inside the
original supervised turn and produces standard RTVI function-call lifecycle
events before the streamed spoken answer. Exact browser verification steps are
in the [Console asset README](apps/vxpipe_console/assets/README.md#manual-tool-call-test).
Set `VITE_VXPIPE_RTVI_OFFER_URL` in `apps/vxpipe_console/assets/.env.local` to
test a different offer endpoint.

For release assets, build the unchanged Vite application into the Console's
`priv/static` directory before assembling the release:

```shell
mix assets.build
cd apps/vxpipe_console
MIX_ENV=prod mix release
```

The generated bundle is ignored by Git and packaged with `vxpipe_console` by Mix.
At runtime, the Console serves the SPA index with no-store caching and its hashed
assets with immutable caching. A missing bundle returns 503 instead of a placeholder.
