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

The React voice playground source lives under `assets/`. Phoenix's `esbuild` Hex
integration owns JavaScript development watching and release bundling; Tailwind's CLI compiles the
approved admin components, and Phoenix LiveReload
refreshes the browser after watched changes. There is no separate frontend HTTP
server or Goreman application. `mix assets.build` writes the React `app.js`, `admin.js`,
`admin.css`, and `app.css`, shared
LiveView `live.js`, Console directory `home.css`, and separate `call_inspection.css` and
`diagnostics.css` and operator-login CSS outputs into the application's ignored
`priv/static/assets` directory. Call
inspection and diagnostics select their own socket paths through their HTML roots while sharing
the same LiveView client module.

## Operator login

With PostgreSQL migrated, run `mix vxpipe.login` on the Vxpipe host. Loopback development uses the
existing Phoenix development secret. Production and development exposed through a non-loopback host
or listener require an explicit `SECRET_KEY_BASE`. Open the printed URL and enter the separately
printed eight-digit code. Phoenix filters the path token from its logs, renders it into the
server-owned form, and redacts both token and code before application telemetry processes the POST.
Keep raw URL access logging disabled for the private login route. The resulting installation-operator
session lasts at most 12 hours and opens `/admin`.

Public deployments terminate HTTPS either in the Console endpoint or at a same-host reverse proxy.
The Console accepts `X-Forwarded-Proto: https` only from a loopback peer. Plain HTTP operator access
is limited to a loopback peer requesting a loopback host.

The Console root has no public page. The tracked React SPA index is served at
`/admin/samples/pipecat-console` for the caller sample and `/admin/samples/transfer` for its transfer
destination; both require an installation-operator session.
`Plug.Static` serves all revalidated `/assets/*` files. If either compiled sample bundle is absent,
those SPA routes return 503 rather than a nonfunctional shell. The separate bounded diagnostics
surface remains available at `/admin/diagnostics` and requires the same session. This application does not own Ecto or call
protocol implementations; as the repository executable host, it may compose and
start their owning umbrella applications.

## Development recording composition

Recording is disabled by default. To select the implemented multipart S3-compatible
writer for repository development, configure PostgreSQL and enable recording:

```shell
VXPIPE_DB_URL=postgres://user:password@database/vxpipe
VXPIPE_RECORDING_ENABLED=true
STORAGE_BUCKET=vxpipe-call-artifacts
AWS_REGION=us-east-1
# AWS_ENDPOINT=http://127.0.0.1:9000
```

The endpoint is optional and must be a root HTTP(S) origin; it enables path-style
requests for a compatible local object store. ExAws obtains credentials from its
standard provider chain, including `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`.
For supplied temporary credentials, also set `AWS_SESSION_TOKEN`; ordinary long-lived keys
leave it unset. See the visible root [`env.sample`](../../env.sample) for all platform settings.
Do not put credentials, bucket settings, or endpoint settings in call specs or
client requests.

## Call-details publication composition

When PostgreSQL is configured, the repository host can publish immutable post-call JSON revisions
to the same S3-compatible bucket used for recordings:

```shell
VXPIPE_DB_URL=postgres://user:password@database/vxpipe
STORAGE_BUCKET=vxpipe-call-artifacts
AWS_REGION=us-east-1
# AWS_ENDPOINT=http://127.0.0.1:9000
```

Both writers and recording playback use `STORAGE_BUCKET`, `AWS_REGION` and `AWS_ENDPOINT`.
The former per-artifact S3 variables are removed and ignored. A configured database and bucket enable post-commit
finalization plus pending-revision recovery; without either one, automatic publication remains
disabled. The endpoint accepts only a root HTTP(S) origin and uses path-style access. ExAws obtains
credentials from its standard provider chain. These settings do not enable recording, and none of
the bucket, endpoint, or credentials belong in a call spec or browser request.

Renaming variables does not move stored objects. Set the new bucket and endpoint to the existing
artifact location to preserve recording playback: stored recording references contain object keys,
not their original bucket/endpoint. Deployments that used separate recording and call-details
stores must explicitly consolidate their existing objects into the shared destination before
switching configuration. Preserve object keys and referenced ETags, or reconcile stored ETag
references after copying; playback sends `If-Match` and a changed ETag can prevent retrieval.
Verify playback before switching. There is no automatic object migration or old-location fallback.

The development recorder captures the live full mix and all individual tracks only
for intervals permitted by the effective room media policy. Raw PCM objects and
terminal metadata are internal at this checkpoint; authenticated operator playback
is still pending in the streaming-recordings milestone.

The sample root, diagnostics, and LiveDashboard have no Console-specific authentication.
Call inspection is separate and requires its operator session as described below. Join
tokens remain scoped to call admission and do not grant inspection access.

## Call inspection

Open `/operator/sign-in` and submit a tenant key plus an existing API key with the `calls`
scope. Console verifies that credential server-side, then stores only tenant/API-key
identifiers, closed scopes, and expiry in its signed browser session; the API-key secret is
not serialized into the session.

After sign-in, `/tenants/:tenant_key/calls` shows a tenant-scoped list of at most 25 calls per page
and `/tenants/:tenant_key/calls/:call_id` shows at most 50 persisted timeline records per history
page alongside the bounded live projection when the room is active. The URL tenant must match the
signed operator principal. Persisted and live reads remain independent, so an archive outage can
still show permitted live evidence. The page labels source, revision, gaps, loss, unavailable data,
and unknown outcomes rather than inventing continuity. Closing or reconnecting the page only stops
or repeats these bounded reads; it does not start, resume, or end a call.

The call detail page also reads the tenant-safe usage projection independently. It shows
non-overlapping provider totals and exact known currency values first, with individual effective
operations and genuine external request/operation/session references in a disclosure. Unknown or
unavailable measurements are never rendered as zero. An unavailable usage projection does not hide
the remaining call evidence, and this operator-only view does not change ordinary client tool or
usage visibility.

## Development diagnostics

The Console uses Phoenix LiveDashboard for platform VM/runtime inspection and
reserves `/diagnostics` for Vxpipe's bounded operational measurements. Diagnostics
are disabled by default and may be enabled with the namespaced Console application
setting. Repository development enables the namespace on the same Console endpoint
as the gateway API and React sample.

`Vxpipe.Console.TelemetryReporter` subscribes to the implemented gateway and call-engine
events. It retains only bounded aggregates and the latest runtime sample. Telemetry
callbacks admit events with atomics, reduce them to validated numeric measurements and
closed dimensions, and only then send them locally. Raw metadata and correlation values
never enter the reporter mailbox. Once the configured pending limit is reached, later
events are counted as dropped rather than accumulating in the mailbox. Configure the bound
alongside diagnostics:

```elixir
config :vxpipe_console, :diagnostics,
  enabled: false,
  max_pending_events: 1_000
```

The reporter starts even when browser diagnostics are disabled so it can be enabled at
the routing boundary without changing event ownership. An embedding host may omit the
Console entirely and attach its own handler to the framework-independent events.

The diagnostics page reads the reporter with a short timeout and refreshes only the
latest snapshot. It shows collection freshness and drops, runtime gauges, gateway
request timing, model completion/first-output state, TTS first-audio timing and safe
provider failure categories. Its compact background-tools instrument also shows admission
outcomes, local worker timing, reservation pressure, and completion-mailbox handoff without
tool names, arguments, results, or correlation identities. Missing measurements have explicit
empty states. The page packages its Phoenix LiveView client locally with a content hash and does not
depend on a hosted script. Use its **System dashboard** link for deeper VM inspection
and **Voice console** to return to the separate sample.
The LiveView does not own the Telemetry handler or a second event buffer: disconnecting
it has no effect on collection or call traffic. A replacement reporter detaches a stale
handler with the same stable ID before attaching, starts with an honestly empty snapshot,
and cannot double-count later events.

When the engine's local model fixture is explicitly enabled, the page also shows one-shot
controls for the next model request. These controls exercise only the fixed local success,
delay, failure and no-output scenarios; they are absent when the fixture process is not
configured. They do not modify call input or expose a general provider-control endpoint.

This milestone deliberately adds no authentication to diagnostics, the sample, or
LiveDashboard. Deployments must control whether and where those opt-in Console surfaces are
exposed. Call inspection is the exception: it exchanges a `calls`-scoped API key server-side
for the non-secret signed operator session described above. Join-token validation remains
limited to call admission. The same diagnostics setting gates both HTTP routes and new
LiveView socket connections, so a disabled deployment cannot bypass its 404 by connecting
to the socket path directly.
