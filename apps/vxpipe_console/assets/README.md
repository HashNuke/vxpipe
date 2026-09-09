# Vxpipe Console assets

This Console-owned React application is a frontend-only playground for exercising
Vxpipe gateway endpoints. It does not host a Pipecat server or duplicate call-engine
behavior in the browser. The Console's Phoenix endpoint supervises Phoenix's esbuild
wrapper as its development watcher and uses LiveReload for browser refreshes;
`mix assets.deploy` writes the minified release bundle to the Console application's
ignored `priv/static/assets` directory. Phoenix serves the UI and mounted gateway
from one listener.

The initial screen uses `ConsoleTemplate` from
`@pipecat-ai/voice-ui-kit`. It pulls in `@pipecat-ai/client-react` and the core
client, and uses the Small WebRTC transport. The default offer URL is
`/api/rtvi/offer`.

The **Create room** control calls `POST /api/rooms` on the same Phoenix origin
with a browser-generated room ID. The development gateway compiles its trusted
sample definition into a fresh pinned plan, starts only the web caller and receiving
agent, and returns the caller's five-minute, single-use Small WebRTC session in the
same response. Only then does the creation screen give the whole viewport to the
responsive Pipecat console. The definition, capability profiles, development tenant,
and actor are injected by server configuration; they are not supplied or authenticated
by the browser.

The Pipecat **Connect** control sends its offer to the returned endpoint along
with the request data from the session response. The current gateway completes
WebRTC and RTVI readiness. Typed input and committed microphone speech run
through the room's Gemini model capability; final model text is displayed and
spoken through the configured Deepgram path.

## Manual tool-call test

1. Put valid `GEMINI_API_KEY` and `DEEPGRAM_API_KEY` values in the repository-root
   `.env` file.
2. From the repository root, run `bin/dev`.
3. Open `https://<this-machine's-tailscale-fqdn>:4000/`, choose **Create room**,
   and then choose **Connect** in the Pipecat console.
4. Type or say: `Use the get_current_time tool and tell me the current UTC time.`
5. In the console event log, verify an `llm-function-call-in-progress` event for
   `get_current_time`, followed by an `llm-function-call-stopped` event whose
   `cancelled` value is `false`.
6. Verify that the assistant then displays and speaks a UTC time as one normal
   assistant turn.

The development system prompt requires the model to call this tool for current
date or time questions, so a guessed answer without the two function-call events
is a failed test.

## Manual provider-fixture test

1. Put a valid `DEEPGRAM_API_KEY` in the repository-root `.env`, set
   `VXPIPE_DEV_MODEL_FIXTURE=true`, and omit `GEMINI_API_KEY` if it is not otherwise
   needed.
2. Run `bin/dev`, then open `/diagnostics` on the HTTPS development origin.
3. Choose **Delay**, return through **Voice console**, create and connect a room, and
   send a typed message. Verify the local response arrives after roughly 1.5 seconds
   and the dashboard attributes first-output timing to **Local fixture**. With TTS
   enabled, it also shows the independently measured Deepgram first-audio timing.
4. Repeat with **Failure**. Verify no assistant text is fabricated and the dashboard
   records a Local fixture unavailable outcome with missing first output.
5. Repeat with **No output**. Verify the invalid empty result fails without assistant
   content or a first-output timing. The next request returns to the configured default
   scenario.

These controls are development application state, not fields accepted from the browser's
room creation or RTVI payloads.

## Manual local Morse output test

1. In the repository-root `.env`, set `VXPIPE_DEV_MODEL_FIXTURE=true` and
   `VXPIPE_DEV_SPEECH_PROFILE=morse`. Remove the hosted provider keys if the point of the
   check is to prove credential-free startup.
2. Run `bin/dev`, create a room, connect, and send a typed message containing only the
   supported Morse alphabet documented in the call-engine README.
3. Verify one normal assistant text row appears and its audio track plays audible Morse tones.
   The default local fixture response is valid Morse input.
4. Do not use microphone speech as a Morse STT assertion. This browser transport supplies Opus,
   while the deterministic decoder accepts mono little-endian linear16. Run the call-engine
   direct-PCM room test for the local recognition and complete audio round trip.

This profile changes only trusted development application configuration; it adds no browser
control and no field that a client can use to select a provider.

From the repository root:

```shell
mix assets.setup
bin/dev
```

To check, test, or build the frontend without starting the endpoint:

```shell
mix assets.test
mix assets.build
```

The browser uses only the scoped, short-lived connection details returned by the
gateway. There is no build-time gateway URL or frontend environment file, and
credentials must never be added to browser assets.

In HTTP mode, set `APP_HOST` to a hostname or interface address to change the
Phoenix bind address. Without `APP_HOST`, Phoenix binds to `0.0.0.0` on port 4000.

By default, `bin/dev` uses trusted HTTPS within the tailnet. Phoenix supervises
its esbuild watcher and is the only web server, listening with a Tailscale certificate
on HTTPS port 4000. It serves the assets and invokes the mounted gateway on that same
origin. The machine FQDN and Tailscale address are discovered automatically.
Run `bin/dev --http` to omit TLS for local troubleshooting.
