# Vxpipe Project Goals

This document defines what Vxpipe is intended to become and the boundaries it
must preserve while getting there. It is a statement of direction, not a claim
that every capability described here already exists. See `AGENTS.md` and
`README.md` for the current project shape and implementation status.

## Mission

Vxpipe is a provider-neutral voice runtime that applications can use to
initiate, receive, and operate live calls.

It should be equally useful in two forms:

- as reusable Elixir/OTP libraries that an application can embed, configure,
  and extend; and
- as a voice platform in a box: one deployable service that exposes an
  authenticated API, receives provider webhooks and media connections, and
  runs calls on behalf of another application.

The standalone service should let a product team run a Vxpipe Docker image and
control calls from its main web application without moving that application's
product model, UI, or database into Vxpipe.

Vxpipe extracts and generalizes the useful call-room ideas developed in Callx.
It does not carry over Callpipe-specific product policy, persistence, tenancy,
workflows, or assumptions about a particular provider.

## The two ways to use Vxpipe

### Embed the libraries

An Elixir application should be able to add the provider-neutral core and only
the adapters it needs, supervise the runtime in its own OTP tree, and control
rooms through documented Elixir APIs. It may mount the reusable Plug/WebSock
router in its existing web application, but network services are optional.

This form is appropriate when the host wants direct process-level integration,
custom supervision, or extension points that remain inside one BEAM runtime.

### Run the standalone platform

An application written in any language should be able to deploy Vxpipe as an
independent OTP release and use its versioned network API. The application
remains the source of truth for customers, workflows, and business data;
Vxpipe owns live call execution.

A typical outbound call should work like this:

```text
Main application
  -> authenticated, idempotent call request with a validated room plan
  -> Vxpipe creates the room and asks the selected telephony adapter to dial
  -> provider events and media drive the live room
  -> Vxpipe emits normalized status and domain events
  -> main application observes, controls, or ends the call
```

A typical inbound call should work like this:

```text
Twilio, Telnyx, or another provider
  -> configured Vxpipe webhook and media endpoint
  -> adapter verifies the exact request and normalizes the provider event
  -> Vxpipe resolves an application-supplied inbound route or room plan
  -> Vxpipe creates or updates the room and answers the call
  -> main application observes and controls the call through public APIs
```

Inbound route selection must be explicit and pluggable. It may come from
runtime configuration or an embedding application callback, or be supplied by
an external control service. It must not require a Vxpipe-owned product
database.

Both forms must use the same plans, room runtime, adapter contracts, events, and
media graph. The standalone service is a composition of the libraries, not a
second call implementation.

## Product shape

The umbrella has three complementary responsibilities:

- `apps/vxpipe` is the provider-neutral call-room library, OTP runtime, and
  Membrane media plane.
- `apps/vxpipe_web` is a reusable Plug/WebSock integration that another Plug or
  Phoenix application can mount without starting a listener.
- `apps/vxpipe_server` composes the library, web layer, and selected adapters
  into the standalone Bandit release.

Telephony providers such as Telnyx and Twilio, speech providers, language-model
providers, recorders, and storage systems are adapters. They should be
replaceable and independently testable, whether maintained in this umbrella or
distributed separately.

## Core goals

### 1. Make the call room the central runtime primitive

A room represents one live call experience independently of any participant or
provider. It should:

- support inbound, outbound, and application-created sessions;
- allow participants to join, leave, fail, transfer, or be replaced in any
  order;
- represent humans, AI agents, observers, recorders, and controllers without
  tying their identity to a transport;
- keep participant, connection, and capability lifecycles explicit; and
- provide deterministic room creation, activation, teardown, and public
  snapshots.

The domain model keeps these concepts separate:

```text
Participant = who or what is in the room
Connection  = how a participant sends or receives media
Capability  = processing used by a participant, such as STT, LLM, or TTS
```

This separation should support, among other cases:

- a human caller speaking with an AI agent;
- two or more humans connected through different transports;
- an AI-to-human or human-to-AI handoff;
- a transfer to another human or AI participant;
- provider-native bridging when routing media through Vxpipe is unnecessary;
  and
- passive live listeners, recorders, debuggers, and analytics consumers.

Each live room is a supervised process island. The room controller owns the
authoritative control-plane state while participant, connection, capability,
and media processes own their narrower responsibilities. Failure in one room
must not damage unrelated calls or leave provider sessions orphaned.

### 2. Use plans as the portable call contract

A complete room plan should describe the desired participants, connections,
capabilities, routing policy, adapter choices, and safe adapter configuration.
It must be validated before any process or provider call is started.

Plans should be usable by both the Elixir API and the standalone network API.
They must be provider-neutral at the core while allowing validated,
allowlisted adapter modules to own provider-specific options. Invalid or
unsupported plans should fail before they create a partial live call.

Plans are execution inputs, not Vxpipe-owned customer records. A main
application may generate them from its own agents, workflows, phone-number
routes, or stored configuration.

### 3. Use Membrane as the real-time media plane

All continuous media processing should be expressed through Membrane
pipelines, elements, and bins rather than a custom per-frame GenServer routing
loop.

The media plane should:

- normalize provider audio formats at adapter boundaries;
- preserve timestamps and stream-format information needed for live media;
- support resampling, encoding, decoding, mixing, recording, and fan-out as
  composable graph operations;
- preserve individual participant tracks and produce a mixed track only when a
  consumer requests one;
- isolate slow or disconnected outputs with bounded buffering and explicit lag
  policies; and
- make latency, queue depth, dropped media, and stream failures observable.

The room controller remains the control plane. It owns lifecycle, membership,
authorization, routing policy, and events, but it must not become a synchronous
bottleneck for every audio frame.

### 4. Make integrations adapters, not core assumptions

Vxpipe should define small public behaviours and normalized domain values for:

- telephony and other media transports;
- speech-to-text;
- text-to-speech;
- language models and agent runtimes;
- recording and storage;
- webhook and provider-event translation; and
- future media processors or observers.

Telnyx, Twilio, Deepgram, and Rime are examples, not defaults embedded in the
domain model. A user should be able to supply a custom adapter without
replacing room internals or copying the runtime.

Provider credentials, payloads, codec names, SDK structs, retry rules, and wire
protocols should stop at the adapter boundary. Core events and errors should be
provider-neutral. External adapter names must resolve through an explicit
registry or allowlist rather than dynamic atom creation.

### 5. Provide a stable, embeddable library API

An application using Vxpipe as a dependency should be able to:

- construct and validate a room plan without starting network services;
- start and supervise the Vxpipe runtime inside its own supervision tree;
- create, inspect, modify, and end rooms through documented APIs;
- attach its own participants, connections, capabilities, media outputs, and
  adapters;
- subscribe to normalized lifecycle and domain events; and
- mount the reusable web layer only when it needs it.

Public extension points should be explicit behaviours, structs, plans, and
event contracts. Consumers should not need to know registry layouts, internal
PIDs, GenServer messages, or private Membrane topology.

### 6. Provide a stable control API for the standalone platform

The standalone network API should let an authorized application:

- submit a validated plan and initiate an outbound call;
- create a room for an application-controlled or non-telephony session;
- inspect public room and call state using stable public identifiers;
- perform supported controls such as ending a call, transferring a
  participant, or changing an approved routing decision;
- receive normalized asynchronous lifecycle and domain events; and
- attach authorized read-only or media-producing WebSocket connections.

The protocol must be versioned. Retried mutations must support explicit
idempotency, and conflicting reuse of an identifier or idempotency key must
fail clearly. Authentication and authorization happen before call control or
media access. API responses and events must not expose PIDs, registry names,
provider credentials, or adapter-private state.

HTTP request completion must not be confused with completion of a call. Call
creation returns a durable public identifier and initial status; subsequent
provider and room changes are observable asynchronously.

### 7. Accept inbound calls through verified provider ingress

Each telephony adapter should own the public webhook and media ingress required
by its provider. The reusable web layer may mount or dispatch to those adapter
handlers, while the standalone server exposes them on its listener.

Provider ingress must:

- verify signatures against the exact raw body before trusting parsed data;
- reject invalid, oversized, or unsupported requests deliberately;
- handle duplicate, delayed, and out-of-order events idempotently;
- map external numbers, accounts, or connection identifiers through explicit
  configuration to an allowed inbound plan resolver;
- normalize accepted provider events before they enter the core; and
- return a failure when required validation or dispatch fails rather than
  acknowledging unhandled work.

Inbound and outbound calls converge on the same room lifecycle after the
provider boundary. Telnyx and Twilio may require different wire protocols, but
those differences must not split the core runtime into provider-shaped models.

### 8. Offer deliberate WebSocket and event integration

Plug, Bandit, WebSock, and WebSockAdapter should be sufficient for the
standalone service and reusable web layer. Vxpipe should not require Phoenix,
though a host Phoenix application may mount the Plug router.

The web surface should:

- offer explicit participant-track and mixed-track audio subscriptions;
- use binary WebSocket frames for audio and a documented control protocol;
- distinguish read-only observers from connections allowed to inject media;
- authorize access to the exact room and track before upgrading;
- apply finite frame, timeout, queue, and process limits; and
- define backpressure, lag, disconnect, and reconnect behavior.

Normalized call events should also be deliverable to embedding subscribers and
to standalone clients through a documented asynchronous mechanism. Delivery
semantics, ordering guarantees, retries, and acknowledgement must be explicit
rather than implied by internal OTP messaging.

The reusable web application must not open a port. Only the standalone server
or the embedding host chooses and starts a listener.

### 9. Run cleanly as a standalone service and Docker image

The standalone form should:

- build as a self-contained OTP release and reproducible Docker image;
- receive listener, adapter, credential, and routing configuration at runtime;
- expose cheap liveness and bounded, dependency-aware readiness checks;
- start no product database or unrelated infrastructure by default;
- host multiple isolated calls concurrently;
- handle SIGTERM with ordered room, pipeline, and provider-session shutdown;
  and
- operate behind a normal ingress or load balancer without Phoenix-specific
  infrastructure.

A useful first deployment should require only the Vxpipe image, runtime
configuration, provider credentials, and connectivity to the selected external
providers. Optional adapters may depend on external systems, but the core
service must not quietly turn those systems into universal requirements.

### 10. Be reliable under real-time failure conditions

The runtime should deliberately handle:

- partial room startup and rollback;
- provider retries and duplicate or out-of-order webhooks;
- failed participants, adapters, pipelines, and WebSocket consumers;
- bounded mailboxes, queues, task concurrency, and network timeouts;
- idempotent start, end, connect, and disconnect operations where retries occur;
  and
- cleanup of external provider resources as well as local OTP processes.

Correctness should come from supervision, links, monitors, explicit ownership,
and tested lifecycle contracts rather than timing assumptions.

### 11. Be observable without exposing call content

Operators and embedding applications should be able to understand room health
through structured logs, metrics, telemetry, and normalized events.

Observability should use stable identifiers, durations, bounded counts, queue
depths, media rates, and normalized failure reasons. Audio, transcripts, phone
numbers, prompts, credentials, signed URLs, and raw provider payloads must not
be logged or retained by default.

### 12. Remain straightforward to extend and maintain

The codebase should use test-driven development and maintain clear ownership at
umbrella, module, process, and media-element boundaries. Each component should
have one cohesive responsibility and dependencies should flow inward toward
the provider-neutral core.

Tests should focus on Vxpipe behavior: plans, public contracts, supervision,
failure recovery, media topology, protocol handling, and adapter boundaries.
Normal tests should be deterministic and must not depend on live providers.

## Lessons retained from Callx

The Callx design provides useful evidence for the runtime model Vxpipe should
generalize:

- A room is the authoritative lifecycle and routing boundary.
- Participants, transport connections, and processing capabilities have
  different identities and lifecycles.
- Each room needs isolated supervision and explicit teardown.
- Provider webhooks, media sockets, and API responses belong at a translation
  boundary, not inside the room model.
- Human-to-human audio may use a provider-native bridge or flow through the
  application media plane; that choice should be explicit.
- Transfers and agent handoffs are changes to participants and routing, not a
  reason to replace the room.
- Control events, transcripts, hooks, and subscribers should remain outside the
  high-rate audio path.

Vxpipe should recreate these capabilities through clear public contracts and a
real Membrane media graph. It is not an extraction of Callx module names,
internal messages, persistence, or application-specific topics.

## Architectural invariants

The following constraints are part of the project goals, not incidental
implementation details:

- The core never depends on a provider adapter, web server, Phoenix, or a
  product database.
- The standalone service composes the reusable libraries rather than bypassing
  them.
- A participant is not a connection, and a connection is not a capability.
- The control plane and high-rate media plane remain separate.
- Provider-specific data is normalized at the boundary.
- Slow consumers cannot create unbounded memory growth or stall an entire room.
- Public APIs do not expose internal PIDs, process messages, or private
  topology.
- The reusable web layer does not own a listener.
- Sensitive call content is not logged or persisted by default.

## Definition of initial success

Vxpipe reaches its initial product goal when all of the following are true:

1. An Elixir application can add the core as a dependency, supervise it, create
   a room from a validated plan, and use a custom adapter without starting HTTP.
2. The supported Docker image can start from runtime configuration and expose
   health, readiness, and an authenticated, versioned control API.
3. A non-Elixir application can make one idempotent API request to initiate an
   outbound call, observe normalized state changes, control it, and end it.
4. A reference Telnyx or Twilio adapter can verify an inbound provider request,
   resolve an application-owned plan, create the room, and operate the incoming
   call through the same runtime used for outbound calls.
5. A deterministic end-to-end test proves audio can enter through an adapter,
   traverse a Membrane graph, and reach an authorized individual or mixed
   output without relying on a live provider.
6. A host application can mount `vxpipe_web`, receive a verified webhook, and
   authorize a WebSocket audio subscriber without Phoenix Channels.
7. Multiple room islands can run concurrently and failures, startup rollback,
   slow consumers, and ordered shutdown are bounded, observable, and covered by
   regression tests.
8. The public plans, behaviours, events, HTTP API, and WebSocket protocol are
   documented well enough for another project to use and extend without
   copying private code.

## Non-goals

Vxpipe is not intended to be:

- a complete contact-center, CRM, billing, workflow, tenant, or user-management
  product;
- the source of truth for agents, customers, phone-number ownership, or call
  history;
- a mandatory persistence system for customer data or call content;
- a single-vendor abstraction that merely renames one provider's API;
- a requirement to route all human-to-human audio through Vxpipe when a
  provider-native bridge is the explicitly selected mode;
- a Phoenix application or UI framework;
- a replacement for provider SDKs, codecs, or Membrane itself; or
- an exact compatibility layer for Callx internals.

Applications may build these concerns around Vxpipe. They should remain outside
the provider-neutral call-room runtime unless the project's goals are
explicitly revised.
