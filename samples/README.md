# Vxpipe samples

This Vite application is a frontend-only playground for exercising Vxpipe
gateway endpoints. It does not host a Pipecat server or duplicate call-engine
behavior in the browser.

The initial screen uses `ConsoleTemplate` from
`@pipecat-ai/voice-ui-kit`. It pulls in `@pipecat-ai/client-react` and the core
client, and uses the Small WebRTC transport. The default offer URL is
`/api/rtvi/offer`.

The **Create room** control calls `POST /api/rooms` through the same-origin proxy
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
3. Open `https://<this-machine's-tailscale-fqdn>:5173/`, choose **Create room**,
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
