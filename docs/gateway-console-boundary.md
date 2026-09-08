# Reusable gateway and Phoenix console

Status: implementation in progress (2026-09-08). The reusable gateway mount and Phoenix
console shell are implemented; asset/dashboard integration remains pending.

## Decision

Add `vxpipe_console` as a separate Phoenix umbrella application, with modules
under `Vxpipe.Console`. Keep the existing `vxpipe_gateway` application and
`Vxpipe.Gateway` namespace. This is an additive application boundary, not a
conversion, rename or regeneration of the gateway or call engine.

The console includes the gateway as an umbrella dependency. Endpoint and router
modules can be named `Vxpipe.Console.Endpoint` and `Vxpipe.Console.Router`;
console code must not claim the generic `Vxpipe.Web` namespace. No application
or asset files move as part of this documentation checkpoint.

| Owner | Responsibility |
| --- | --- |
| `vxpipe_gateway` | Reusable API plugs, request authentication, protocol translation, signaling, sessions and transport connection supervision |
| `vxpipe_console` | Phoenix endpoint and browser presentation: samples, operational dashboards and later authorized call inspection |
| `vxpipe_calls` | Database-neutral definition, admission and archive workflows and repository interfaces |
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
API. Keep the sample frontend in React with its existing components and Vite build
workflow; serving its built assets from the console does not require a LiveView
rewrite. The eventual asset relocation, development watcher/proxy wiring and
production static delivery must be verified together. Keep diagnostics on a
separate page from the responsive voice console.

Phoenix is the selected console framework. The operational-dashboard mechanism
and browser authentication details still need an implementation choice. Platform
VM introspection and tenant-scoped call inspection are separate access boundaries;
neither a call token nor merely running the console grants operator access.
Diagnostics remain opt-in and protected. A release may include the console, while
an embedding host can omit it and attach its own framework-independent telemetry
reporter.

## Alternatives not selected

- **Convert gateway to Phoenix:** technically still usable as an OTP dependency,
  but couples gateway consumers to Phoenix and our presentation dependencies.
- **Put dashboard and API implementations in both applications:** duplicates
  authentication/protocol behavior and allows the two paths to diverge.
- **Name the application `vxpipe_web`:** does not preserve the requested distinct
  console namespace; use `vxpipe_console` / `Vxpipe.Console` instead.
- **Move Ecto into the console:** confuses browser presentation with shared
  persistence ownership and breaks the existing database-neutral workflow boundary.

## Delivery and verification evidence

The [observable sample call](milestones/observable-sample-call.md) delivers the
first console-backed vertical slice; [call inspection](milestones/call-inspection-and-debugging.md)
adds authorized durable views. The [embedded/container slice](milestones/embedded-and-container-delivery.md)
verifies the reusable and packaged compositions. This decision adds no milestone
or implementation-completion claim.

Source inspection found an existing Plug HTTP endpoint, an optionally enabled
standalone HTTP supervisor and no Phoenix dependency in the gateway. That is a
starting point, not evidence that arbitrary host mounting is already supported.
The current sample is a separate React/Vite project. At the design checkpoint,
documentation consistency and relative links were checked while runtime mounting,
browser rendering, transport interoperability and release packaging were still
unverified.

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
enables the Console listener. Focused and live checks show the Console root and gateway health
route on the same port, one BEAM listener on port 4000, no gateway HTTP supervisor, and the
gateway session/connection runtime still active. The gateway has no Phoenix dependency. React
asset ownership, dashboard dependencies, protected diagnostics, and full call transport through
the shared endpoint remain pending.

Implementation checkpoint 3 selected Phoenix LiveDashboard for platform VM/runtime inspection
and a separate Vxpipe page for call-path measurements. These dependencies live only in Console.
Both routes fail closed through a project-owned access plug. They are disabled by default;
repository development permits only direct loopback clients and deliberately omits diagnostics
from Caddy routing. That local restriction is not production authentication or trusted-proxy
handling, so external exposure remains prohibited until operator auth covers HTTP and LiveView.
Rendered desktop/mobile checks verify the LiveDashboard surface; Vxpipe telemetry and final sample
asset integration remain pending.
