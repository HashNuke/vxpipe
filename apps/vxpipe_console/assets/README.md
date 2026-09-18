# Vxpipe Console assets

This Console-owned React application is a frontend-only playground for exercising
Vxpipe gateway endpoints. It does not host a Pipecat server or duplicate call-engine
behavior in the browser. The Console's Phoenix endpoint supervises Phoenix's esbuild
wrapper as its development watcher and uses LiveReload for browser refreshes;
`mix assets.deploy` writes the minified release bundle to the Console application's
ignored `priv/static/assets` directory. Phoenix serves the UI and mounted gateway
from one listener. The caller playground is mounted at `/samples/pipecat-console`; the root is a directory
of the available Console interfaces.

The esbuild profile has independent named entries for the React sample, the shared LiveView client,
call-inspection styles, and diagnostics styles. Operator assets are served by the same Phoenix
`Plug.Static` boundary as the sample; they are not embedded into Elixir modules. The shared client
reads the page's `phx-socket` attribute, so call inspection and diagnostics retain their distinct
socket endpoints without duplicating Phoenix or LiveView in the browser bundle.

The initial screen uses `ConsoleTemplate` from
`@pipecat-ai/voice-ui-kit`. It pulls in `@pipecat-ai/client-react` and the core
client, and uses the Small WebRTC transport. The default offer URL is
`/api/rtvi/offer`.

Development uses the local `vxpipe_dev` PostgreSQL database by default;
`VXPIPE_DATABASE_URL` optionally overrides that connection. The **Create room** control calls
`POST /sample/calls` on the same Phoenix origin. The Console's supervised sample
backend uses its private development API key and configured initial variables to
prepare a call, then returns only its public tenant/call/participant locator and
five-minute join token. The browser presents that token to the matching gateway
participant-session route. Its atomic claim starts the stored pinned plan and returns
the Small WebRTC session. The API key and initial variables never enter the browser.

For hosts that disable the managed sample, `POST /sample/calls` returns 404 and
the control keeps the database-free fallback: it calls `POST /api/rooms` with a random room ID,
and the trusted gateway adapter starts the configured plan and returns its session.
Only after either path succeeds does the creation screen give the whole viewport to
the responsive Pipecat console.

The Pipecat **Connect** control sends its offer to the returned endpoint along
with the request data from the session response. The current gateway completes
WebRTC and RTVI readiness. Typed input and committed microphone speech run
through the room's Gemini model capability; final model text is displayed and
spoken through the configured Deepgram path.

## Manual prepared-call admission test

1. Create and migrate the local `vxpipe_dev` PostgreSQL database before starting
   `bin/dev`. Set `VXPIPE_DATABASE_URL` only to use a different database.
2. Open the Console and choose **Create room**. Verify a new call row is initially
   prepared with no `started_at` and that no room process exists before admission.
3. Verify the browser receives a join token and public locator, but no API key or
   initial-variable snapshot, then uses the token on the participant-session route.
4. Verify that call becomes running only after the session response, retains one
   room incarnation and original pinned call spec revision, and has one admission
   for the caller.
5. Choose **Connect** and complete one typed or spoken turn through the ordinary
   Small WebRTC/RTVI path.

## Manual tool-call test

1. Follow [provider credential setup](../../../docs/provider-credential-storage.md) to provision
   Google and Deepgram for one tenant. Set `VXPIPE_DEV_TENANT` to its public key alongside the
   platform encryption settings in the ignored repository-root `.env`.
2. From the repository root, run `bin/dev`.
3. Open `https://<this-machine's-tailscale-fqdn>:4000/samples/pipecat-console`, choose **Create room**,
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

## Manual human-transfer test

1. Create/migrate `vxpipe_dev`, provision the tenant’s Google and Deepgram credentials,
   select that tenant with `VXPIPE_DEV_TENANT`, and start `bin/dev`.
2. Open `/samples/pipecat-console` as the caller, choose **Create room**, then connect the Pipecat console.
3. Open `/samples/transfer` in a second browser or device. Use headphones when both clients are on one
   machine so the two live microphones do not feed each other.
4. In the caller console, type or say: `Please transfer me to human support. I need help with my
   sample order.` The development agent must invoke its catalog-bound transfer tool; a model reply
   that merely promises a transfer is not sufficient.
5. Within the transfer's 30-second deadline, choose **Connect transfer desk** on the destination
   page. Verify its status becomes **Private briefing line open**, the destination alone hears the
   agent's bounded reason and configured development notice, and the caller hears neither. Before
   acceptance, caller speech must not reach the destination and destination speech must not reach
   the caller.
6. Choose **Accept transfer**. Verify the destination status becomes **Main room active**, the
   source agent exits, and caller and destination can hear one another in both directions. Speak
   from the destination and verify its partial and completed transcriptions appear in the caller
   console's conversation. The configured destination STT starts only after promotion; private
   preparation speech must not appear there. The Pipecat template labels human speech `user`;
   the underlying RTVI transcription retains the speaking participant's `user_id`.
7. Disconnect the destination and verify the control ledger records the bounded state changes
   without displaying the private briefing, API key, Call Variables, or unrestricted history.

The transfer page is a Vxpipe development client, not an RTVI extension or a second Pipecat
console. It uses the authenticated `vxpipe` WebRTC sideband for exact-attempt acceptance and the
ordinary negotiated audio tracks for private briefing and active room media.

## Local provider fixtures

The default browser sample uses its provisioned Google/Deepgram tenant. Local model and Morse
selections are explicit inline call spec fields with host-configured adapters; environment
profile switches are removed. See [local fixtures](../../../docs/development.md#local-fixtures)
for the deterministic direct-PCM voice test. It verifies local STT and audible Morse output
without provider credentials. Browser microphone RTP is Opus, while Morse STT takes linear16.

From the repository root:

```shell
mix assets.setup
bin/dev
```

`mix assets.setup` installs and builds the root `@vxpipe/core` and `@vxpipe/react`
workspaces before installing the Console assets. This keeps a clean Console build on the
packages' declared distribution entry points.

To check, test, or build the frontend without starting the endpoint:

```shell
mix assets.test
mix assets.build
```

The operator administration prototype is included in the existing `@vxpipe/react` Storybook. It
uses deterministic view models and does not require Phoenix, PostgreSQL, media access, or a live
call. Run it from the repository root:

```shell
npm ci
npm ci --prefix apps/vxpipe_console/assets
npm run build
npm run storybook
```

Open `http://127.0.0.1:6006/`. Individual page stories expose their important states through
Storybook Controls. Use **Admin / Full journey** for the linked review flow; each page checkpoint
extends that same story until it reaches call details.

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
