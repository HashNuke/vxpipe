# Reusable gateway and Phoenix console

Status: implemented through the prepared-call admission milestone (2026-09-09). The
reusable gateway mount, Phoenix console shell, operational dashboard, release asset
integration, and trusted managed-sample handoff are complete.

## Decision

Add `vxpipe_console` as a separate Phoenix umbrella application, with modules
under `Vxpipe.Console`. Keep the existing `vxpipe_gateway` application and
`Vxpipe.Gateway` namespace. This is an additive application boundary, not a
conversion, rename or regeneration of the gateway or call engine.

The console includes the gateway as an umbrella dependency. Endpoint and router
modules can be named `Vxpipe.Console.Endpoint` and `Vxpipe.Console.Router`;
console code must not claim the generic `Vxpipe.Web` namespace. The original decision-only
checkpoint moved no application or asset files; later implementation moved the unchanged
playground source under Console ownership as approved.

| Owner | Responsibility |
| --- | --- |
| `vxpipe_gateway` | Reusable API plugs, request authentication, protocol translation, signaling, sessions and transport connection supervision |
| `vxpipe_console` | Phoenix endpoint and browser presentation: samples, operational dashboards and later authorized call inspection |
| `vxpipe_calls` | Database-neutral call spec, admission and archive workflows and repository interfaces |
| `vxpipe_persistence` | Ecto Repo, schemas, migrations, queries and transactions implementing those interfaces |
| `vxpipe_call_engine` | Protocol-neutral live room, participant, variables, tool and media behavior |

## Embedding and dependency direction

Another Elixir application must be able to use the gateway without depending on
our console, Phoenix, dashboard packages or frontend assets. The engine continues
to be usable without either gateway or console. Enforce these dependency
directions in the owning Mix projects when implementing the split.

Support these compositions without duplicating protocol handlers:

- Our console starts its Phoenix endpoint and mounts the gateway HTTP Plug in
  that endpoint's request pipeline. This is one HTTP listener/port: disable the
  gateway's standalone listener. There is no internal HTTP proxy hop between
  console and gateway.
- A host application mounts that same interface into its own compatible endpoint
  and starts the required gateway runtime processes through documented supervision
  and application options.
- A host can instead enable the gateway's standalone HTTP listener on a configured
  address and port. The console is not required to run a call gateway.

Mounting routes alone does not start gateway registries, sessions or connection
supervisors. When sharing a host endpoint, disable the gateway's separate listener
and start each required runtime subtree once. Document path-prefix handling,
origin/CORS settings, advertised signaling URLs and transport upgrades as part of
the mounting contract; do not assume forwarding HTTP routes alone proves media
interoperability. Only make focused gateway mounting/configuration changes if
implementation evidence requires them, not a gateway rewrite.

The existing `Vxpipe.Gateway.HTTP.Endpoint` is a Plug module despite its name;
it is not a Phoenix endpoint. Console owns the Phoenix endpoint that invokes it.
The standalone gateway listener above is an alternative embedding option, not
the topology of our console deployment.

The console uses the gateway and public Calls APIs, not direct Repo queries.
Calls receives configured repository adapters; persistence implements those
interfaces without introducing a reverse dependency from Calls or the engine to
Ecto. Repo ownership and migrations stay in persistence, not in a Phoenix-generated
database layer. Live archival remains asynchronous through the existing planned
storage-subscriber boundary; this split changes no admission or durability contract.

## Presentation and delivery

The console owns browser presentation, not a second implementation of the call
API. Keep the sample frontend in React with its existing components and use
Phoenix's esbuild integration for development and release bundles; this does not
require a LiveView rewrite. Phoenix serves those assets on the same endpoint as
the mounted gateway, so Console has no second frontend listener or development
proxy. Keep diagnostics on a separate page from the responsive voice console.

Phoenix is the selected console framework. LiveDashboard owns platform VM inspection,
and a separate Vxpipe page owns bounded call-path measurements. Diagnostics remain
opt-in and add no Console-specific login; the deployment decides whether to expose them.
Tenant call-inspection pages use a separate Console-owned browser session: an operator
submits an existing tenant API key over TLS, Calls authenticates its existing `:calls`
scope, and Console stores only the non-secret principal identifiers, closed scopes, and
a bounded expiry in the signed session. The secret is neither frontend configuration nor
browser-session data. This guard applies only to tenant call inspection; it does not turn
join tokens into operator credentials or add authentication to the sample, diagnostics,
or LiveDashboard routes. A release may include the console, while an embedding host can
omit it and attach its own framework-independent telemetry reporter.

### Call-inspection operator workflow

An operator opens `/operator/sign-in` over TLS and submits the tenant's public key plus an
existing API key carrying the `:calls` scope. Console authenticates it server-side and
stores only the non-secret principal in its signed, one-hour browser session. API-key
values are filtered from Phoenix request logs. Signing out removes that browser identity.

The protected `/tenants/:tenant_key/calls` route loads one cursor-bounded page of at most 25 tenant
call summaries. `/tenants/:tenant_key/calls/:call_id` adds at most 50 persisted events and, only
while the call is running, the engine's bounded live projection. The URL tenant must match the
signed operator principal. Separate opaque URL cursors retain call and history pagination; an
event key in the URL retains exact evidence selection without a backend refetch. Connected live
detail pages refresh only the bounded live projection. Persisted history remains visible when no
room process exists, and unavailable sources, archive gaps, live loss, and variable-revision
differences remain explicit.

This browser access is private operator history, not ordinary caller tool visibility.
Join tokens and public call identifiers cannot establish an operator session. The page
uses public Calls APIs through the Console inspection adapter; neither Console nor Gateway
queries Repo or reads arbitrary room state. Payloads are rendered as inert data, and the
workflow adds no audio capture, playback, variable editing, tool execution, or call control.

## Alternatives not selected

- **Convert gateway to Phoenix:** technically still usable as an OTP dependency,
  but couples gateway consumers to Phoenix and our presentation dependencies.
- **Put dashboard and API implementations in both applications:** duplicates
  authentication/protocol behavior and allows the two paths to diverge.
- **Name the application `vxpipe_web`:** does not preserve the requested distinct
  console namespace; use `vxpipe_console` / `Vxpipe.Console` instead.
- **Move Ecto into the console:** confuses browser presentation with shared
  persistence ownership and breaks the existing database-neutral workflow boundary.
- **Keep a separate Vite development server:** adds a second HTTP listener, proxy
  configuration and shutdown lifecycle even though Phoenix's esbuild watcher can
  build the existing React UI for the shared endpoint. Vitest may remain a test-only
  tool without making Vite the application asset pipeline.

## Delivery and verification evidence

The [observable sample call](milestones/observable-sample-call.md) delivers the
first console-backed vertical slice; [call inspection](milestones/call-inspection-and-debugging.md)
adds authorized durable views. The [embedded/container slice](milestones/embedded-and-container-delivery.md)
verifies the reusable and packaged compositions. This decision adds no milestone
or implementation-completion claim.

Source inspection found an existing Plug HTTP endpoint, an optionally enabled
standalone HTTP supervisor and no Phoenix dependency in the gateway. That is a
starting point, not evidence that arbitrary host mounting is already supported.
At the design checkpoint, the current sample was still a top-level React/Vite
project. Documentation consistency and relative links were checked while runtime
mounting, browser rendering, transport interoperability and release packaging
were still unverified.

Implementation checkpoint 1 added and red-tested `Vxpipe.Gateway.HTTP.Mount` as the
supported composable boundary. It claims only `/healthz` and `/api` at a root mount,
supports an explicit host path prefix, preserves configured CORS behavior, and halts
claimed responses while allowing unrelated host pages to continue. Tests run with the
standalone HTTP supervisor disabled and verify that the gateway's session and WebRTC
connection supervisors remain alive. Console/Phoenix integration and live transport
interoperability were still unverified at that checkpoint.

Implementation checkpoint 2 added the `vxpipe_console` umbrella application using Phoenix
1.8.13 and the `Vxpipe.Console` namespace. Its application prepares the gateway mount from
runtime application settings and passes it to `Vxpipe.Console.Endpoint`; the endpoint invokes
the mounted gateway before its own router. Development now disables the gateway listener and
enables the Console listener. Focused and live checks show Console browser pages and the gateway
health route on the same port, one BEAM listener on port 4000, no gateway HTTP supervisor, and the
gateway session/connection runtime still active. The gateway has no Phoenix dependency. React
asset ownership, dashboard dependencies, diagnostics, and full call transport through
the shared endpoint remain pending.

Implementation checkpoint 3 selected Phoenix LiveDashboard for platform VM/runtime inspection
and a separate Vxpipe page for call-path measurements. These dependencies live only in Console.
The subsequent access correction keeps diagnostics disabled by default and protects the Console
pages and LiveDashboard with installation-operator authentication. Repository development exposes
`/admin/diagnostics*` on the shared Console endpoint. API keys
and join tokens retain only their API/admission meanings. Rendered desktop/mobile checks verify
the LiveDashboard surface. The React/Vite playground source is now Console-owned:
the Phoenix endpoint supervises its Vite watcher in development, while release
builds place the bundle in Console `priv/static` for direct serving. Goreman does
not manage a separate frontend application.

Implementation checkpoint 5 supersedes that Vite build/runtime detail without changing
the React UI or ownership boundary. Console now uses Phoenix's `esbuild` Hex integration,
supervises its watcher with Phoenix LiveReload, and serves stable revalidated JS/CSS from
the same listener that mounts the gateway. Phoenix/Bandit terminates development TLS directly
on port 4000; Caddy, port 5174, the Vite proxy and the custom watcher lifecycle code are gone.
The release shell remains no-store, and a missing compiled JS or CSS file fails explicitly
instead of serving a broken page.

Implementation checkpoint 4 verified both reusable delivery modes at their owning
boundaries. The gateway-only mount suite now creates a room and issues a bound participant
session under a host prefix while the standalone listener is absent and the session/WebRTC
runtime remains supervised. A tagged local-network test starts the optional standalone
Bandit listener on an ephemeral loopback port, verifies configured CORS, then creates the
same room/session path. Console's endpoint suite separately proves its page and mounted
gateway health route share one endpoint while the standalone HTTP supervisor is absent.
The gateway child has no Phoenix or Console dependency.

Implementation checkpoint 6 adds the durable development sample without moving admission
or persistence into Phoenix. Console supervises a trusted process that uses the public Calls
API to bootstrap a private development tenant/key and publish the configured call spec.
Its endpoint returns only a safe call locator and join token. The React creation page then
uses the mounted gateway's standard participant-session route; the API key and initial
variables stay server-side. When persistence is not configured, the process is absent and
the existing trusted, database-free gateway sample remains runnable.
