# Vxpipe

**TODO: Add description**

## Development

The development stack requires Elixir, Node.js and npm, a Rust toolchain,
`pkg-config`, OpenSSL development headers,
[Goreman](https://github.com/mattn/goreman),
[Watchman](https://facebook.github.io/watchman/) with its `watchman-make`
Python client, Tailscale, and `jq`.

Install the Watchman Python client as an isolated user-level tool:

```shell
uv tool install pywatchman
```

Install the Console frontend dependencies and Phoenix-managed esbuild binary once:

```shell
mix assets.setup
```

Then start the Vxpipe umbrella and Console frontend together:

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

For a credential-free typed call with audible Morse output, combine the local model
fixture with the opt-in Morse speech profile:

```shell
VXPIPE_DEV_MODEL_FIXTURE=true
VXPIPE_DEV_SPEECH_PROFILE=morse
```

With this profile, `DEEPGRAM_API_KEY` and `GEMINI_API_KEY` are not required. The
trusted sample keeps browser speech-to-text unselected, accepts typed Console input,
and emits the agent response through 48 kHz Morse TTS so the existing WebRTC output
path can play it. Browser microphone RTP is Opus and is deliberately not presented as
compatible with the linear16-only Morse STT provider. Use the call-engine direct-PCM
verification path described below when testing local Morse recognition.

Goreman loads the credentials into its child processes, including Watchman
restarts. Reusable call-engine code receives provider options through the OTP
application environment and does not read these environment variables directly.

Goreman runs the call engine, gateway, and Console applications in one BEAM
instance. The Console's Phoenix endpoint supervises its esbuild development watcher,
serves the React assets, and mounts the reusable gateway. It is the only HTTP server.
By default Phoenix listens with TLS on the machine's Tailscale address at
`https://<machine-fqdn>:4000/`. The machine FQDN and Tailscale IPv4 address are
discovered automatically; WebRTC media continues to use its negotiated ICE path.

Goreman also runs `watchman-make` in the foreground. Changes to umbrella source,
Mix manifests, or runtime configuration ask Goreman to restart only the
`vxpipe` process. A reload therefore starts a fresh BEAM instance and discards
development rooms, sessions, and WebRTC connections. Test changes do not
restart the development server. The Console asset watcher consumes its Phoenix
parent's lifecycle, so a reload does not leave a second frontend listener or
orphaned development server.

`bin/dev` asks the local Tailscale daemon for a certificate for the discovered
`.ts.net` hostname and gives its ignored runtime paths to Phoenix/Bandit. MagicDNS
and HTTPS certificates must be enabled for the tailnet. The complete stack runs as
the calling user; no root process, reverse proxy, `TS_PERMIT_CERT_UID`, or manually
exported TLS variables are required. Phoenix binds only to the discovered Tailscale
address. This does not use Tailscale Funnel or make the development stack public.

Use `--http` to omit TLS for local troubleshooting. In HTTP mode, set `APP_HOST`
to bind the Console endpoint to a specific hostname or interface:

```shell
APP_HOST=vxpipe.example.ts.net bin/dev --http
```

The repository-root `.env.example` documents the development credential and
optional Goreman process overrides. A static `APP_HOST` can be placed in `.env`
for HTTP mode; HTTPS mode derives it from Tailscale automatically. Goreman loads
`.env` into its child processes without exporting values into the parent shell.

PostgreSQL-backed tenant/API-key and call-definition storage is opt-in through
`VXPIPE_DATABASE_URL`. Without it, the development sample continues using its
trusted static definition and no Repo is started. Migration, one-time tenant/key
bootstrap, key rotation/revocation, and immutable definition publication are
documented in [Tenant control-plane operations](docs/tenant-control-plane.md).

The umbrella test alias creates and migrates the configured test database. Use
`VXPIPE_TEST_DATABASE_URL`, or standard PostgreSQL variables plus
`VXPIPE_TEST_DATABASE` (default `vxpipe_test`). Running the call-engine tests from
its child directory remains database-free.

Without `APP_HOST`, HTTP mode binds the Console endpoint to `0.0.0.0`. The React
page and mounted gateway are same-origin in both modes, so no frontend proxy or
second asset port is involved.

The gateway reads its listener and CORS options from the `vxpipe_gateway`
application environment. In development, `APP_HOST` becomes the exact allowed
origin on port 4000, using the selected HTTPS or HTTP scheme. Environment variables
are read from `config/runtime.exs`, while `config/dev.exs` only enables the listener.

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
The browser uses the session's server-issued offer endpoint; no browser build-time
endpoint setting is required.

The optional local Morse provider contract, direct-PCM test command, supported alphabet,
signal settings, and transport limits are documented in the
[call-engine README](apps/vxpipe_call_engine/README.md#local-morse-audio-providers).

For release assets, build and minify the React application through Phoenix's
esbuild integration into the Console's
`priv/static` directory before assembling the release:

```shell
mix assets.deploy
cd apps/vxpipe_console
MIX_ENV=prod mix release
```

The generated JS/CSS bundle is ignored by Git and packaged with `vxpipe_console`
by Mix; the small SPA index is tracked. At runtime, the Console serves the index
with no-store caching and revalidates the stable bundle names. Missing compiled
JS or CSS returns 503 instead of a nonfunctional shell.
