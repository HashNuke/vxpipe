# Vxpipe Project Goals

This document defines the intended outcomes and enduring boundaries of Vxpipe.
It is a statement of direction, not a claim that every capability described here
already exists. See `AGENTS.md` and the root `README.md` for the current project
shape and implementation status.

## Mission

Vxpipe is a provider-neutral Elixir/OTP runtime for building and operating live
voice call rooms.

It should be equally useful in two forms:

- as a reusable library that an existing Elixir application can embed, configure,
  and extend; and
- as a standalone OTP release that can run in a Docker container and expose a
  versioned HTTP and WebSocket interface.

Vxpipe extracts and generalizes the useful call-room concepts proven in Callx
without carrying over Callpipe-specific product policy, persistence, or provider
assumptions.

## Product shape

The umbrella has three complementary responsibilities:

- `apps/vxpipe` is the provider-neutral call-room library, OTP runtime, and
  Membrane media plane.
- `apps/vxpipe_web` is a reusable Plug/WebSock integration that another Plug or
  Phoenix application can mount without starting a listener.
- `apps/vxpipe_server` composes the library and web layer into a standalone
  Bandit-based release suitable for a container.

Provider integrations such as Telnyx, Deepgram, Rime, LLMs, recorders, and
storage systems are adapters. They should be replaceable and independently
testable, whether maintained in this umbrella or distributed separately.

## Core goals

### 1. Make the call room the central runtime primitive

A room represents one live call experience independently of any participant or
provider. It should:

- support inbound, outbound, and application-created sessions;
- allow participants to join, leave, fail, transfer, or be replaced in any order;
- represent humans, AI agents, observers, recorders, and controllers without
  tying their identity to a transport;
- keep participant, connection, and capability lifecycles explicit; and
- provide deterministic room creation, activation, teardown, and snapshots.

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
- a transfer to another human or AI participant; and
- passive live listeners, recorders, debuggers, and analytics consumers.

### 2. Use Membrane as the real-time media plane

All continuous media processing should be expressed through Membrane pipelines,
elements, and bins rather than a custom per-frame GenServer routing loop.

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

### 3. Make integrations adapters, not core assumptions

Vxpipe should define small public behaviours and normalized domain values for:

- telephony and other media transports;
- speech-to-text;
- text-to-speech;
- language models and agent runtimes;
- recording and storage;
- webhooks and provider event translation; and
- future media processors or observers.

Telnyx, Deepgram, and Rime are initial examples, not defaults embedded in the
domain model. A user should be able to supply a custom adapter without replacing
room internals or copying the runtime.

Provider credentials, payloads, codec names, SDK structs, retry rules, and wire
protocols should stop at the adapter boundary. Core events and errors should be
provider-neutral.

### 4. Provide a stable, embeddable library API

An application using Vxpipe as a dependency should be able to:

- construct and validate a room plan without starting network services;
- start and supervise the Vxpipe runtime inside its own supervision tree;
- create, inspect, modify, and end rooms through documented APIs;
- attach its own participants, connections, capabilities, media outputs, and
  adapters;
- subscribe to normalized lifecycle and domain events; and
- mount the reusable web layer only when it needs it.

Public extension points should be explicit behaviours, structs, plans, and event
contracts. Consumers should not need to know registry layouts, internal PIDs,
GenServer messages, or private Membrane topology.

### 5. Offer simple HTTP, WebSocket, and webhook integration

Vxpipe should not require Phoenix for its transport needs. Plug, Bandit, WebSock,
and WebSockAdapter should be sufficient for the standalone service and reusable
web layer. A host Phoenix application may still mount the Plug router.

The web surface should:

- receive provider webhooks, verify them against the exact raw request body, and
  normalize them before they reach the core;
- expose bounded, versioned endpoints for room lifecycle and provider callbacks;
- let authorized applications stream live room audio over WebSockets;
- offer explicit participant-track and mixed-track subscriptions;
- send audio in binary frames, with a documented control and metadata protocol;
- distinguish read-only listeners from clients authorized to inject media; and
- define authentication, authorization, backpressure, disconnect, and
  slow-consumer behavior as part of the protocol.

The reusable web application must not open a port. Only the standalone server or
the embedding host chooses and starts a listener.

### 6. Run cleanly as a standalone OTP service

The standalone form should:

- build as a self-contained OTP release and Docker image;
- receive deployment configuration and secrets at runtime;
- expose cheap liveness and bounded readiness checks;
- start no product database or unrelated infrastructure by default;
- handle SIGTERM with ordered room, pipeline, and provider-session shutdown; and
- operate behind a normal ingress or load balancer without Phoenix-specific
  infrastructure.

### 7. Be reliable under real-time failure conditions

Each room should be a supervised process island so that one failed call does not
damage unrelated rooms. The runtime should deliberately handle:

- partial room startup and rollback;
- provider retries and duplicate or out-of-order webhooks;
- failed participants, adapters, pipelines, and WebSocket consumers;
- bounded mailboxes, queues, task concurrency, and network timeouts;
- idempotent start, end, connect, and disconnect operations where retries occur;
  and
- cleanup of external provider resources as well as local OTP processes.

Correctness should come from supervision, links, monitors, explicit ownership,
and tested lifecycle contracts rather than timing assumptions.

### 8. Be observable without exposing call content

Operators and embedding applications should be able to understand room health
through structured logs, metrics, telemetry, and normalized events.

Observability should use stable identifiers, durations, bounded counts, queue
depths, media rates, and normalized failure reasons. Audio, transcripts, phone
numbers, prompts, credentials, signed URLs, and raw provider payloads must not be
logged or retained by default.

### 9. Remain straightforward to extend and maintain

The codebase should use test-driven development and maintain clear ownership at
umbrella, module, process, and media-element boundaries. Each component should
have one cohesive responsibility and dependencies should flow inward toward the
provider-neutral core.

Tests should focus on Vxpipe behavior: plans, public contracts, supervision,
failure recovery, media topology, protocol handling, and adapter boundaries.
Normal tests should be deterministic and must not depend on live providers.

## Architectural invariants

The following constraints are part of the project goals, not incidental
implementation details:

- The core never depends on a provider adapter, web server, Phoenix, or a product
  database.
- A participant is not a connection, and a connection is not a capability.
- The control plane and high-rate media plane remain separate.
- Provider-specific data is normalized at the boundary.
- Slow consumers cannot create unbounded memory growth or stall an entire room.
- Public APIs do not expose internal PIDs, process messages, or private topology.
- The reusable web layer does not own a listener.
- Sensitive call content is not logged or persisted by default.

## Definition of success

Vxpipe has reached its initial product goal when all of the following are true:

1. An Elixir application can add the core as a dependency, supervise it, create a
   room from a validated plan, and use a custom adapter without starting HTTP.
2. A host application can mount `vxpipe_web`, receive a verified webhook, and
   authorize a WebSocket audio subscriber without Phoenix Channels.
3. The standalone release can run in a container, accept runtime configuration,
   report health, host multiple isolated rooms, and shut down cleanly.
4. A deterministic end-to-end test proves audio can enter through an adapter,
   traverse a Membrane graph, and reach an authorized individual or mixed output
   without relying on a live provider.
5. Reference adapters demonstrate telephony, STT, and TTS integration while the
   core test suite remains provider-independent.
6. Room and output failures are bounded, observable, and covered by regression
   tests, including startup rollback and slow-consumer behavior.
7. The public plans, behaviours, events, and WebSocket protocol are documented
   well enough for another project to extend them without copying private code.

## Non-goals

Vxpipe is not intended to be:

- a complete contact-center, CRM, billing, workflow, or user-management product;
- a persistence system or source of truth for customer and call-history data;
- a single-vendor abstraction that merely renames one provider's API;
- a requirement to route all human-to-human audio through one topology when a
  provider-native bridge is the explicitly selected mode;
- a Phoenix application or UI framework;
- a replacement for provider SDKs, codecs, or Membrane itself; or
- an exact compatibility layer for Callx internals.

Applications may build these concerns around Vxpipe. They should remain outside
the provider-neutral call-room runtime unless the project's goals are explicitly
revised.
