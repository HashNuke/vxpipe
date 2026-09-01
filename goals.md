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
- keep participant, connection, and service lifecycles explicit; and
- provide deterministic room creation, activation, teardown, and public
  snapshots.

The domain model keeps these concepts separate:

```text
Participant         = who or what is in the room
Connection          = how a participant sends or receives media
Participant service = processing owned by one participant
Room service        = cross-cutting processing or observation for the room
Media track         = one normalized, timed stream in the Membrane graph
```

Participant services include STT, TTS, an LLM backing, and input or output
guardrails. A human backing is normally expressed through one or more
connections and routing policy rather than pretending the human is an LLM
service. Internally, participant services may be implemented as capabilities,
workers, Membrane elements, or bins according to their responsibility.

Room services include recording, transcript assembly, policy monitoring,
telemetry, evaluation, and artifact export. They attach once to the room and
observe explicit event or media outputs instead of being copied into every
participant.

This separation should support, among other cases:

- a human caller speaking with an AI agent;
- two or more humans connected through different transports;
- an AI-to-human or human-to-AI handoff;
- a transfer to another human or AI participant;
- provider-native bridging when routing media through Vxpipe is unnecessary;
- passive live listeners and debuggers;
- participant-specific input and output policy chains; and
- room-wide recorders, transcript writers, monitors, and artifact exporters.

Each live room is a supervised process island. The room controller owns the
authoritative control-plane state while participant, connection, service,
and media processes own their narrower responsibilities. Failure in one room
must not damage unrelated calls or leave provider sessions orphaned.

### 2. Use plans as the portable call contract

A complete room plan should describe the desired participants, connections,
participant and room services, routing policy, adapter choices, and safe
adapter configuration.
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
- input and output guardrails;
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
- attach its own participants, connections, services, media outputs, and
  adapters;
- attach participant services and room-wide monitoring or storage services;
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

## Working contract sketch

The following is the current starting design, not a frozen public API. It makes
the intended boundaries concrete enough to implement and test while leaving
provider callback details, media containers, and final endpoint names open.

### Participant services and room services

Every service has an id, a kind, an adapter selected through a controlled
registry, configuration owned by that adapter, declared inputs and outputs, and
a failure policy. Services differ by scope:

- A participant service belongs to one participant. STT, TTS, LLM, participant
  input policy, and participant output policy are the initial kinds.
- A room service belongs to the room. Recording, transcript assembly, artifact
  export, monitoring, evaluation, and telemetry are the initial kinds.

Each participant also declares its backing: a human reached through one or more
connections, an LLM participant service, or an application-controlled
connection. This makes human-backed and model-backed participants equally
explicit without making a telephony transport pretend to be an LLM service.

The normal AI participant signal chain is conceptually:

```text
participant audio
  -> STT
  -> input guardrail chain
  -> LLM or other agent backing
  -> output guardrail chain
  -> TTS
  -> participant audio output
```

A guardrail should have an explicit signal contract. An input guardrail may
allow, reject, redact, or transform a final transcript or structured input. An
output guardrail may allow, reject, redact, transform, retry, or request a
handoff before text reaches TTS. Audio-specific moderation, if later required,
is a different service kind and must not be hidden inside a text guardrail.

Guardrails are ordered policy chains, not ambient callbacks. Their decisions
should produce normalized events with bounded metadata, without logging the
sensitive input by default. Each service declares whether its failure fails the
participant, bypasses the service, retries within a bound, or ends the room.

Room services should receive only the data they request. A transcript writer
does not need raw audio; an individual-track recorder does not need prompts or
tool results; a telemetry exporter should receive measurements rather than call
content. A room service that consumes media attaches to a bounded Membrane
output branch. It must not receive every audio frame through the room
GenServer's ordinary mailbox.

### Initial room plan shape

One validated plan should drive both the embeddable and standalone forms. The
Elixir representation may contain approved modules when called by trusted OTP
code. The JSON representation accepts only registered adapter names and
credential references. Untrusted strings are never converted into new atoms or
arbitrary modules.

The plan should contain these top-level concepts:

```elixir
%{
  id: "room_01...",
  purpose: :customer_call,
  metadata: %{},
  participants: [],
  room_services: [],
  routing: %{},
  lifecycle: %{},
  event_outputs: []
}
```

A more complete illustrative plan is:

```elixir
%{
  id: "room_01...",
  purpose: :customer_call,
  metadata: %{external_call_id: "call_123"},
  participants: [
    %{
      id: "caller",
      kind: :human,
      role: :caller,
      backing: %{kind: :human, connection_ids: ["caller-leg"]},
      connections: [
        %{
          id: "caller-leg",
          kind: :telephony,
          adapter: :telnyx,
          direction: :inbound,
          credential_ref: "telnyx-primary",
          config: %{}
        }
      ],
      services: [
        %{
          id: "caller-stt",
          kind: :stt,
          adapter: :deepgram,
          config: %{language: "en"},
          failure_policy: :fail_participant
        },
        %{
          id: "caller-input-policy",
          kind: :input_guardrail,
          adapter: :application_policy,
          config: %{},
          failure_policy: :end_room
        }
      ]
    },
    %{
      id: "assistant",
      kind: :agent,
      role: :assistant,
      backing: %{kind: :llm, service_id: "assistant-llm"},
      connections: [],
      services: [
        %{
          id: "assistant-llm",
          kind: :llm,
          adapter: :openai,
          config: %{model: "configured-model", system_prompt_ref: "prompt-v3"},
          failure_policy: :fail_participant
        },
        %{
          id: "assistant-output-policy",
          kind: :output_guardrail,
          adapter: :application_policy,
          config: %{},
          failure_policy: :end_room
        },
        %{
          id: "assistant-tts",
          kind: :tts,
          adapter: :rime,
          config: %{voice: "configured-voice"},
          failure_policy: :fail_participant
        }
      ]
    }
  ],
  room_services: [
    %{
      id: "archive",
      kind: :artifact_export,
      adapter: :s3,
      credential_ref: "call-archive",
      config: %{
        prefix: "rooms/room_01...",
        audio: %{tracks: :individual_and_mixed},
        transcript: %{enabled: true},
        call_details: %{enabled: true}
      },
      failure_policy: :report_and_continue
    }
  ],
  routing: %{
    caller: %{sends_audio_to: ["assistant"], receives_audio_from: ["assistant"]}
  },
  lifecycle: %{idle_timeout_ms: 30_000}
}
```

This example illustrates ownership; it does not decide the final field names.
In particular, secrets and raw authorization headers do not belong in a plan,
public snapshot, event, or artifact. `credential_ref` is resolved by the
embedding application or standalone runtime at the adapter boundary.

Plan validation should happen in phases:

1. Validate ids, shapes, enums, limits, and referential integrity without
   starting any process.
2. Resolve adapter names through an explicit registry and verify that the
   adapter supports the requested service or connection contract.
3. Validate adapter-owned configuration without resolving or exposing secrets.
4. Produce an immutable normalized plan suitable for an idempotent creation
   comparison.
5. Only then start the room island and external provider operations, rolling
   back all partial work if startup fails.

### Room command API

The public Elixir API should expose semantic room commands rather than internal
GenServer messages. The first contract should cover operations equivalent to:

```text
validate plan
create room from normalized plan
activate room
get public room snapshot
end room idempotently

add, update, and remove a participant
attach and detach a participant connection
connect, answer, dial, and disconnect through that connection
attach, start, stop, and detach a participant service
attach, start, stop, and detach a room service
update routing or bridge policy

subscribe and unsubscribe from authorized room events
attach and detach authorized individual or mixed media outputs
deliver a normalized provider event or media ingress notification
```

Exact function names remain to be designed with the structs and tests. The API
should return tagged results at recoverable boundaries, accept a runtime or
supervisor reference where practical, and never require callers to address a
room process directly.

Commands that can be retried must accept a command or idempotency identifier.
Repeating the same command with the same normalized input returns the existing
result. Reusing the identifier with different input returns a conflict. Adding
or removing participants, attaching connections, bridging, and ending a room
all need explicit retry semantics because provider webhooks and HTTP clients
will repeat work.

The standalone HTTP API is a translation and authorization layer over the same
commands. It converts JSON adapter names through the registry, authenticates
the calling application, enforces room-level authorization, and maps tagged
results to a versioned wire protocol. It must not implement a second room
lifecycle in controllers or Plugs.

The network API will likely need both a general room resource and a convenient
call-creation operation. The latter can validate a telephony plan, create a
room, attach an outbound connection, and dial as one idempotent orchestration
without weakening the underlying room contract.

### Room inputs and published events

The room consumes four categories of input:

- public room commands from trusted Elixir callers or the authorized HTTP API;
- normalized provider lifecycle and control events from connection adapters;
- control-plane outputs from participant and room services, such as final
  transcripts, guarded text, tool results, and artifact completion; and
- bounded notifications from the Membrane pipeline, such as track start, end,
  format, discontinuity, lag, and failure.

Raw provider payloads stop at adapters. Continuous audio remains in the
Membrane media plane and crosses into control-plane events only when a bounded,
low-rate notification is useful.

Every public event should use a versioned envelope containing at least:

```text
event id
schema version
room id and per-room sequence
event type and occurrence time
participant, connection, service, track, and command ids when applicable
normalized payload
bounded metadata
causation or correlation id when applicable
```

The initial event families should include:

- room created, active, ending, ended, and failed;
- participant added, joined, state changed, removed, and failed;
- connection attached, connecting, connected, disconnected, and failed;
- service attached, started, stopped, bypassed, and failed;
- media track started, format changed, lagged, dropped, ended, and failed;
- transcript partial, transcript final, and speaker turn finalized;
- input or output guardrail allowed, blocked, transformed, and failed;
- bridge requested, connected, failed, and ended;
- artifact started, completed, partial, and failed; and
- normalized provider and application control events that have a documented
  public purpose.

Partial transcripts and high-rate diagnostic events are optional and normally
ephemeral. Final transcripts, lifecycle transitions, bridge results, and
artifact completion are candidates for durable delivery. The event delivery
contract must say which events are ordered, retryable, and acknowledged. A
spawned task per event, as used by Callx for some subscribers, is not a durable
delivery strategy.

Hooks that can block or transform a decision are distinct from observers.
Blocking hooks run at explicit low-rate decision points with a deadline and a
declared failure policy. Observers use bounded queues and cannot stall the room
or media pipeline.

### Telephony and bridging

Inbound and outbound telephony are connection operations. A telephony adapter
owns dialing, answering, hanging up, provider commands, webhook verification,
provider event normalization, media ingress and egress, and its provider ids.
The core owns the participant, connection lifecycle, authorization, routing,
and normalized events.

A generic human participant never defaults to Telnyx, Twilio, or another
provider. The plan or trusted application must select an adapter explicitly.
Adding a second telephony adapter must not require changes to the room domain
model.

Bridging two calls means attaching the two telephony legs as connections for
participants in one room and selecting one of two explicit modes:

- `provider_native`: one compatible telephony adapter bridges its own legs.
  Vxpipe retains authoritative participants, connection state, and normalized
  lifecycle events while the provider carries the live media.
- `media_plane`: both legs stream through the room's Membrane graph. This works
  across different providers and enables per-track recording, mixing,
  intervention, and arbitrary media outputs.

Provider-native bridging is an optional adapter capability, not part of the
minimum telephony behaviour. Cross-provider bridging necessarily uses the
media-plane mode unless an explicit external bridge adapter owns both sides.
Bridge failure and teardown must leave neither a local process nor a billable
provider leg orphaned.

### Media outputs

The media graph should expose explicit output attachments for:

- one participant's input or output track;
- one telephony connection leg or channel where available;
- a selected group of tracks; and
- a mixed room track.

An output attachment declares its desired stream format and its lag policy.
Each output branch has bounded buffering. Depending on the consumer, lag may
drop frames, mark the artifact partial, disconnect the output, or fail a room
service; it must never grow without limit or backpressure an unrelated call.

Live WebSocket listeners, recorders, and remote artifact writers consume these
outputs through different adapters but share the same track-selection model.
Mixing is requested explicitly and never destroys the original individual
tracks.

### Artifact storage model

Vxpipe should define an artifact-store behaviour rather than embed S3 calls in
the room, pipeline, or recorder. Initial implementations should include a
deterministic local filesystem store for tests and development, followed by an
S3-compatible store. Other object stores or application-owned remote endpoints
can implement the same contract.

The store contract needs operations for small JSON objects and streaming or
multipart artifacts. It must support completion, abort, idempotent retry,
checksums, content type, byte count, and bounded finalization. Storage workers
run outside the room controller. They use bounded queues or a bounded local
spool and report artifact state back through normalized events.

The default object layout should be versioned and predictable:

```text
rooms/{room_id}/manifest.json
rooms/{room_id}/call.json
rooms/{room_id}/transcript.json
rooms/{room_id}/events/000001.jsonl.gz
rooms/{room_id}/audio/participants/{participant_id}/{track_id}.{ext}
rooms/{room_id}/audio/mixed/{track_id}.{ext}
```

Object names use validated opaque ids, not phone numbers, participant display
names, or other personal data. The extension and content type reflect the
actual negotiated container and codec; the storage model does not require WAV
or any one provider format.

`manifest.json` is the entry point for consumers and should resemble:

```json
{
  "schema_version": "vxpipe.artifacts.v1",
  "room_id": "room_01...",
  "generation": 3,
  "state": "complete",
  "created_at": "2026-09-01T00:00:00Z",
  "finalized_at": "2026-09-01T00:05:00Z",
  "artifacts": [
    {
      "id": "artifact_01...",
      "kind": "participant_audio",
      "participant_id": "caller",
      "track_id": "track_01...",
      "object_key": "rooms/room_01.../audio/participants/caller/track_01xyz.ogg",
      "content_type": "audio/ogg",
      "codec": "opus",
      "started_at_ms": 0,
      "ended_at_ms": 298000,
      "bytes": 1234567,
      "sha256": "...",
      "state": "complete"
    }
  ]
}
```

The manifest may be replaced as artifacts progress, using its `generation` to
make updates explicit. It is finalized after writers have either completed or
reported a terminal partial or failed state. A room can end successfully even
if an optional exporter fails; the manifest and artifact events must make that
failure visible.

`call.json` stores provider-neutral call details:

```json
{
  "schema_version": "vxpipe.call.v1",
  "room_id": "room_01...",
  "external_call_id": "call_123",
  "direction": "inbound",
  "status": "ended",
  "started_at": "2026-09-01T00:00:00Z",
  "ended_at": "2026-09-01T00:05:00Z",
  "duration_ms": 300000,
  "end_reason": {"code": "completed"},
  "participants": [],
  "connections": [],
  "services": [],
  "metadata": {}
}
```

Participants, connections, and services contain stable public ids, kinds,
roles, direction, timing, and normalized terminal state. Provider references
are included only when the configured storage policy permits them. Credentials,
raw provider payloads, PIDs, internal registry names, and adapter state are
never included.

`transcript.json` stores canonical finalized turns rather than raw STT chunks:

```json
{
  "schema_version": "vxpipe.transcript.v1",
  "room_id": "room_01...",
  "language": "en",
  "turns": [
    {
      "id": "turn_01...",
      "sequence": 1,
      "participant_id": "caller",
      "role": "caller",
      "started_at_ms": 1200,
      "ended_at_ms": 3600,
      "text": "I need an appointment.",
      "source_service_id": "caller-stt",
      "confidence": 0.94,
      "metadata": {}
    }
  ]
}
```

Partial transcripts and replay diagnostics belong in optional event chunks, not
the canonical transcript. Transcript turns have stable ids, room sequence,
speaker ownership, timing, and source service so they can be aligned with
individual or mixed recordings.

Storage policy is explicit per artifact class. It controls whether an artifact
is disabled, retained, encrypted, redacted, or sent to one or more stores.
Vxpipe does not persist audio or transcripts merely because a storage adapter is
configured. The application must request the artifact and is responsible for
the applicable consent and retention policy.

### First implementation sequence

The implementation should proceed in contract-sized checkpoints:

1. Define and test pure plan structs, service scopes, adapter registries,
   validation, normalized plans, and public snapshots. Use only controlled fake
   adapters. This is the starting point.
2. Implement the supervised room lifecycle, participant and service attachment,
   idempotent commands, routing policy, and the versioned event envelope without
   real provider calls.
3. Implement the per-room Membrane pipeline with deterministic source and sink
   elements, individual tracks, explicit output branches, bounded buffering,
   and requested mixing.
4. Prove participant service chains with fake STT, guardrail, LLM, and TTS
   adapters, plus a room-wide observer that cannot stall media.
5. Define artifact structs and the local artifact-store adapter. Prove
   individual and mixed audio, canonical transcript, call details, manifest
   finalization, partial writes, and shutdown flushing.
6. Expose the same room commands through the versioned Plug/WebSock layer with
   authentication, authorization, idempotency, and bounded protocol limits.
7. Add one telephony adapter end to end for inbound and outbound calls, including
   exact raw-body webhook verification and bidirectional media.
8. Implement media-plane bridging, provider-native bridging where supported,
   and teardown tests for both success and failure.
9. Add a second telephony adapter to prove the core is provider-neutral, and add
   replaceable production STT and TTS adapters.
10. Add the S3-compatible artifact-store adapter and build the supported Docker
    image with runtime configuration, health, readiness, and graceful shutdown.

Each checkpoint includes its public contract, deterministic tests, relevant
notes, and failure semantics. Live-provider interoperability remains a separate
tagged test lane.

### Decisions deliberately left open

The first contract work should gather evidence before fixing:

- the final module and HTTP resource names;
- whether public plans expose generic signal ports, a constrained routing DSL,
  or both;
- the exact guardrail decision and retry vocabulary;
- which event classes receive durable at-least-once delivery in the standalone
  service;
- the initial recording container and codec combinations;
- multipart upload versus bounded local spool behavior for each artifact store;
- manifest update and conditional-write requirements across object stores;
- whether the standalone service offers an optional durable event outbox
  without introducing a mandatory product database; and
- the first production telephony, STT, TTS, and object-storage adapters.

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
- A participant is not a connection, and a service is neither of those.
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
