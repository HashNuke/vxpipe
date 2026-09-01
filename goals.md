# Vxpipe Project Goals

This document defines what Vxpipe is intended to become and the boundaries it
must preserve while getting there. It is a statement of direction, not a claim
that every capability described here already exists. See `AGENTS.md` and
`README.md` for the current project shape and implementation status.

## Mission

Vxpipe is a provider-neutral voice runtime that applications can use to
initiate, receive, and operate live calls.

The first product version is intentionally voice-first, but voice is not the
permanent boundary of the platform. Plans, participants, connections, media
tracks, services, and public events should remain extensible to future video,
image, avatar, and other multimodal inputs and outputs. Those media types are
not part of the v1 delivery criteria and must not delay a reliable voice
runtime.

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

## Version 1: the voice foundation

V1 is the smallest release that is genuinely useful both as an embedded
library and as a standalone voice platform. It proves one complete,
production-capable human-to-AI voice session over WebSockets and the extension
contracts needed to grow the platform. It is not a promise to implement every
goal in this document before shipping.

V1 includes:

- validated provider-neutral room plans, authoritative room lifecycle,
  supervised room islands, idempotent commands, and versioned events;
- the embeddable core and reusable web layer, plus the standalone release and
  Docker image using the same runtime contracts;
- a versioned WebSocket media-ingress connection through which a human
  participant sends audio, and a separate authorized, read-only WebSocket
  output subscription through which a client receives an agent, participant,
  or requested mixed track;
- one production adapter each for STT, LLM, and TTS, and a Silero VAD-backed
  turn detector;
- a real per-room Membrane audio graph with normalized timed tracks, bounded
  output branches, individual and requested mixed output, and deterministic
  media tests;
- room-scoped conversation context, participant-scoped context projections,
  room-level and participant-level tools, and cold and warm agent transfers;
- VAD-backed turn boundaries and coordinated barge-in that cancels generation,
  flushes undelivered audio, and suppresses late results;
- the ordered provider-candidate and failover contract, proven with
  deterministic adapters even though v1 does not require two production
  providers for every service kind;
- lifecycle and performance metrics, optional local recording/transcript
  artifacts, and authorized event subscriptions;
- a dogfooding and reference web application with a Vite/React TypeScript
  frontend, a Fastify TypeScript backend, and project-owned UI states developed
  in Storybook; and
- explicit startup rollback, bounded queues and timeouts, dependency-aware
  readiness, content-safe observability, and ordered shutdown.

WebSockets are the deliberate v1 transport because they allow local,
deterministic, and browser-capable development without a carrier account,
public webhook, phone number, or billable telephony call. This choice does not
replace the Membrane media plane or make WebSocket protocol details part of the
room domain. Later telephony or other real-time transports attach as connection
adapters to the same participants, tracks, services, and routing contracts.

The v1 `samples` web application is a reference client and development harness,
not a product UI or a runtime dependency. Its backend owns sample orchestration
and server-side credentials; the browser sends and receives live media directly
through Vxpipe's authorized WebSockets. Microphone capture, playback, and
browser echo-cancellation behavior remain client concerns. Reusable UI states
are prototyped and reviewed in Storybook before being wired into sample pages.

The following remain goals, but are delivered incrementally after v1:

- telephony adapters for inbound and outbound carrier calls, verified webhooks,
  DTMF, IVR navigation, voicemail detection, and provider-native call control;
- second and subsequent production STT, LLM, TTS, VAD, storage, and other
  service adapters, including production primary/backup combinations;
- media-plane and provider-native telephony bridging;
- advanced audio cleanup and optional turn-scoped audio artifacts;
- S3-compatible artifact export, richer retention and storage policies, and an
  optional durable event outbox;
- broader evaluation and operational tooling; and
- video, image, avatar, and other multimodal tracks and services.

Post-v1 work should extend the public participant, connection, service, track,
plan, and event contracts rather than introduce a parallel runtime.

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

A typical v1 WebSocket call should work like this:

```text
Main application
  -> creates a room from an authenticated, idempotent request
  -> authorizes a human participant's media-ingress connection
Web client
  -> opens the participant WebSocket and sends binary microphone audio
  -> opens a read-only output subscription for the agent's audio track
Vxpipe
  -> runs turn detection, STT, context, tools, LLM, and TTS
  -> publishes normalized events and binary agent audio
  -> main application or web client controls or ends the room
```

The ingress connection and output subscription are separate protocol roles.
The ingress socket is a participant connection allowed to produce media. The
output socket is a bounded, read-only attachment to an authorized individual or
mixed track and may be joined by more than one observer. A simple web-call
client normally opens one of each.

After v1, a typical outbound telephony call should work like this:

```text
Main application
  -> authenticated, idempotent call request with a validated room plan
  -> Vxpipe creates the room and asks the selected telephony adapter to dial
  -> provider events and media drive the live room
  -> Vxpipe emits normalized status and domain events
  -> main application observes, controls, or ends the call
```

An inbound telephony call should work like this:

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

The `samples` package sits outside the umbrella applications. It is a
TypeScript dogfooding client and end-user reference implementation; neither the
core libraries nor the standalone release depend on it.

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

Agent-to-agent handoff is a first-class room operation, not an application
convention built from unrelated participant mutations. The public API must
define preparation, context handoff, routing cutover, completion, cancellation,
failure, rollback, and idempotency. The room id remains stable across a
handoff, and the operation must make it unambiguous which participant owns the
active agent role at every point.

### 2. Use plans as the portable call contract

A complete room plan should describe the desired participants, connections,
participant and room services, routing policy, ordered provider choices,
turn-taking and interruption policy, transfer policy, and safe adapter
configuration.
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
- voice activity and turn detection;
- conversation context and scoped tool execution;
- DTMF, IVR navigation, and voicemail detection;
- recording and storage;
- webhook and provider-event translation; and
- future media processors or observers.

Telnyx, Twilio, Deepgram, Rime, and Silero VAD are examples, not defaults
embedded in the domain model. Silero VAD is the initial voice-activity detector
to evaluate, behind the same provider-neutral contract as alternative or
future turn detectors. A user should be able to supply a custom adapter without
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

- submit a validated plan and create an application-controlled room;
- inspect public room and call state using stable public identifiers;
- perform supported controls such as ending a call, transferring a
  participant through the defined transfer API, or changing an approved
  routing decision;
- receive normalized asynchronous lifecycle and domain events; and
- attach authorized read-only or media-producing WebSocket connections.

The protocol must be versioned. Retried mutations must support explicit
idempotency, and conflicting reuse of an identifier or idempotency key must
fail clearly. Authentication and authorization happen before call control or
media access. API responses and events must not expose PIDs, registry names,
provider credentials, or adapter-private state.

HTTP request completion must not be confused with completion of a room or call.
Creation returns a durable public identifier and initial status; subsequent
provider and room changes are observable asynchronously.

### 7. Add verified provider ingress after the WebSocket foundation

Each post-v1 telephony adapter should own the public webhook and media ingress
required by its provider. The reusable web layer may mount or dispatch to those
adapter handlers, while the standalone server exposes them on its listener.

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

- provide a versioned participant media-ingress WebSocket that authenticates a
  media-producing connection before it joins the room;
- offer explicit participant-track and mixed-track audio subscriptions;
- use binary WebSocket frames for audio and a documented control protocol;
- make the read-only media output subscription a separate protocol role from a
  connection allowed to inject media;
- authorize access to the exact room and track before upgrading;
- negotiate or require a documented v1 audio format and normalize it at the
  Membrane boundary while preserving sequence and timing information;
- apply finite frame, timeout, queue, and process limits; and
- define backpressure, lag, disconnect, and reconnect behavior.

The v1 web-call client model uses two sockets: a participant media-ingress
connection for microphone audio and a read-only media output subscription for
the desired agent or mixed track. The output subscription is independently
authorized and buffered, so a slow listener cannot stall the participant input,
agent processing, or another subscriber.

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
- ordered primary and backup providers for every provider-backed service,
  including bounded failover without changing the logical service identity;
- provider failure during partially emitted text or media, without duplicating
  output or leaving the failed provider active;
- user barge-in that cancels in-flight LLM and TTS work, flushes queued output,
  and records what was generated separately from what was actually delivered;
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

The public metric vocabulary should distinguish vendor/service metrics from
end-to-end runtime performance. It should cover provider request counts,
failures, retries, failovers, usage units, and cost inputs where available, as
well as VAD timing, STT finalization latency, LLM time to first response, TTS
time to first audio, end-to-end turn latency, interruption drain time, queue
depth, dropped media, and playback timing. Metrics carry stable room,
participant, service, provider-candidate, and turn identifiers but no call
content.

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

Every service has a stable logical id, a kind, declared inputs and outputs, an
implementation selected through a controlled registry, and a failure policy.
A provider-backed service additionally declares one or more ordered provider
candidates and provider-owned configuration. It may have only a primary
candidate, but the contract supports backups without changing the service's
public identity. Services differ by scope:

- A participant service belongs to one participant. STT, TTS, LLM, participant
  input policy, participant output policy, and participant tools are v1 kinds.
  IVR navigation and voicemail detection are planned post-v1 kinds.
- A room service belongs to the room. Recording, transcript assembly, artifact
  export, conversation context, room tools, monitoring, evaluation, and
  telemetry are initial kinds.

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

### Service provider selection and failover

A provider-backed logical service declares an ordered list containing a primary
candidate and zero or more backups. Each candidate names an allowlisted adapter,
credential reference, adapter-owned configuration, and the capabilities it is
expected to provide. Plans fail validation when candidates are incompatible
with the service contract.

Failover policy declares which startup failures, timeouts, rate limits,
provider errors, or health states advance to the next candidate; retry and
cooldown bounds; and what happens after the candidate list is exhausted. A
provider switch emits a normalized event and vendor/service metrics while the
logical service id remains unchanged. Authentication or configuration errors
must not be treated as indefinitely retryable failures.

Streaming services require an explicit safe failover boundary. If an LLM or TTS
provider fails after emitting partial output, Vxpipe must cancel or isolate the
failed attempt, identify which text or media was delivered, and avoid replaying
content blindly through the backup. Live provider settings may be updated only
through validated service commands with observable success or failure.

### Conversation context and scoped tools

Conversation context is a room service because it must survive participant and
agent transfers. It owns the canonical ordered conversation state for the room,
including finalized user and agent turns and bounded tool-call results. It may
summarize, truncate, or export that state according to an explicit policy; it is
not automatically a permanent product record.

Participant LLM services consume authorized projections of the room context.
The projection may omit private participant data, room-only control events, raw
tool results, or history outside the participant's role. Multiple named context
services may be used when a room needs deliberately isolated conversations.

Tools have explicit room or participant scope:

- a room-level tool is available to every participant authorized by its policy
  and operates on room-owned capabilities;
- a participant-level tool is visible only to its owning participant unless a
  transfer policy explicitly grants it to the target; and
- every invocation has a stable id, validated input, authorization decision,
  deadline, cancellation policy, normalized result or error, and bounded
  observability metadata.

Tool execution runs outside the room controller and high-rate media path.
Invocations must be cancellable where the integration permits it, and late
results from cancelled or superseded turns must not mutate context or trigger
speech accidentally.

### Turn taking, interruption, and telephony interaction

Turn detection is a participant-level media capability. The first voice
implementation should evaluate Silero VAD for speech activity while keeping the
public contract independent of that implementation. VAD detects speech versus
non-speech; it does not by itself prove that a speaker has semantically
completed a turn. Turn policy therefore combines VAD events with configurable
start, silence, end-of-turn, and idle rules.

Accepted user speech produces stable turn-start and turn-end events with media
timestamps. When policy permits barge-in, a new user turn interrupts the active
agent response as one coordinated operation: cancel or supersede in-flight LLM
and TTS work, stop synthesis and playback, flush bounded queued agent audio,
mark undelivered output, and prevent late results from restarting the response.
The context and artifact models must distinguish generated text/audio from the
portion actually delivered to the participant.

DTMF is a normalized connection command and event, regardless of whether a
telephony provider sends native digit events or a media element detects or
generates tones. DTMF, IVR navigation, and voicemail detection enter with the
post-v1 telephony work. IVR navigation may be a participant service or an
application-controlled state machine that consumes DTMF, speech, and connection
events. Voicemail detection is a participant service that can combine
provider-native signals with media analysis and reports a normalized decision,
confidence when available, evidence category, timing, and failure reason.

### Agent transfers and handoffs

The public transfer API targets an existing participant or a validated new
participant specification. A transfer command contains a stable command id,
source and target, handoff mode, context policy, routing policy, timeout, and
failure policy. At minimum, the contract should support:

- a cold transfer that atomically replaces the active agent;
- a warm transfer that prepares the target and its services before cutover;
- an overlap period in which both agents may participate under explicit
  routing; and
- cancellation or rollback when preparation or cutover fails.

Transfer phases are observable as requested, preparing, ready, committed,
cancelled, and failed. Preparing the target may resolve its provider candidates,
start required services, and provide an authorized full, summarized, or empty
context projection without routing its output to the caller. Commit changes
active-agent ownership and routing exactly once. Completion stops or demotes the
source according to policy and leaves neither provider work nor media output
orphaned.

Agent handoff is distinct from a provider-native transfer of a telephony leg.
Both are room commands, but they have different adapter capabilities, media
effects, and failure semantics. Replaying an idempotent transfer command returns
the existing operation; reusing its command id for a different target or policy
returns a conflict.

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
  turn_policy: %{},
  transfer_policy: %{},
  lifecycle: %{},
  event_outputs: []
}
```

A more complete illustrative plan is:

```elixir
%{
  id: "room_01...",
  purpose: :web_voice_session,
  metadata: %{external_session_id: "session_123"},
  participants: [
    %{
      id: "caller",
      kind: :human,
      role: :caller,
      backing: %{kind: :human, connection_ids: ["caller-media-in"]},
      connections: [
        %{
          id: "caller-media-in",
          kind: :websocket_media,
          adapter: :vxpipe_websocket,
          direction: :ingress,
          config: %{
            format: %{encoding: :pcm_s16le, sample_rate: 16_000, channels: 1}
          }
        }
      ],
      services: [
        %{
          id: "caller-stt",
          kind: :stt,
          provider_candidates: [
            %{
              id: "primary",
              adapter: :deepgram,
              credential_ref: "stt-primary",
              config: %{language: "en"}
            },
            %{
              id: "backup",
              adapter: :configured_stt_backup,
              credential_ref: "stt-backup",
              config: %{language: "en"}
            }
          ],
          failover: %{max_attempts_per_candidate: 1},
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
          provider_candidates: [
            %{
              id: "primary",
              adapter: :openai,
              credential_ref: "llm-primary",
              config: %{model: "configured-model", system_prompt_ref: "prompt-v3"}
            },
            %{
              id: "backup",
              adapter: :configured_llm_backup,
              credential_ref: "llm-backup",
              config: %{model: "configured-backup-model", system_prompt_ref: "prompt-v3"}
            }
          ],
          failover: %{max_attempts_per_candidate: 1},
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
          provider_candidates: [
            %{
              id: "primary",
              adapter: :rime,
              credential_ref: "tts-primary",
              config: %{voice: "configured-voice"}
            },
            %{
              id: "backup",
              adapter: :configured_tts_backup,
              credential_ref: "tts-backup",
              config: %{voice: "configured-backup-voice"}
            }
          ],
          failover: %{max_attempts_per_candidate: 1},
          failure_policy: :fail_participant
        }
      ]
    }
  ],
  room_services: [
    %{
      id: "conversation",
      kind: :conversation_context,
      adapter: :local_context,
      config: %{summarization: :configured},
      failure_policy: :end_room
    },
    %{
      id: "archive",
      kind: :artifact_export,
      provider_candidates: [
        %{
          id: "primary",
          adapter: :s3,
          credential_ref: "call-archive",
          config: %{}
        }
      ],
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
  turn_policy: %{
    detector: %{adapter: :silero_vad, config: %{}},
    barge_in: :interrupt_agent_output
  },
  transfer_policy: %{default_mode: :warm, context: :summary},
  lifecycle: %{idle_timeout_ms: 30_000}
}
```

This example illustrates ownership; it does not decide the final field names or
the required v1 audio format.
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
GenServer messages. The complete contract should cover operations equivalent
to:

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
update a service's validated settings or provider candidates
update routing or bridge policy
request, inspect, commit, and cancel an agent transfer
interrupt or supersede an active agent response
send DTMF through an authorized connection
invoke or cancel an authorized room-level or participant-level tool

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
or removing participants, attaching connections, transferring agents, invoking
tools, sending DTMF, bridging, and ending a room all need explicit retry
semantics because provider webhooks and HTTP clients will repeat work.

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
participant, connection, service, provider-candidate, track, turn, tool-call,
transfer, and command ids when applicable
normalized payload
bounded metadata
causation or correlation id when applicable
```

The initial event families should include:

- room created, active, ending, ended, and failed;
- participant added, joined, state changed, removed, and failed;
- connection attached, connecting, connected, disconnected, and failed;
- service attached, started, stopped, bypassed, failed, provider selected,
  provider switched, and providers exhausted;
- media track started, format changed, lagged, dropped, ended, and failed;
- speech activity started and stopped, turn started and finalized, transcript
  partial and final, response interrupted, and output flushed;
- input or output guardrail allowed, blocked, transformed, and failed;
- tool requested, authorized, started, completed, cancelled, timed out, and
  failed;
- agent transfer requested, preparing, ready, committed, cancelled, and failed;
- DTMF sent and received, IVR state changed, and voicemail detected or
  undetermined;
- bridge requested, connected, failed, and ended;
- artifact started, completed, partial, and failed; and
- normalized provider and application control events that have a documented
  public purpose.

Partial transcripts and high-rate diagnostic events are optional and normally
ephemeral. Final transcripts, lifecycle and transfer transitions, tool results,
bridge results, and artifact completion are candidates for durable delivery.
The event delivery contract must say which events are ordered, retryable, and
acknowledged. A spawned task per event, as used by Callx for some subscribers,
is not a durable delivery strategy.

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

`call.json` stores provider-neutral room and call details:

```json
{
  "schema_version": "vxpipe.call.v1",
  "room_id": "room_01...",
  "external_session_id": "session_123",
  "direction": "application_created",
  "transport": "websocket",
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

### V1 delivery sequence

The implementation should proceed in contract-sized checkpoints:

1. Define and test pure plan structs, service and tool scopes, ordered provider
   candidates, adapter registries, turn and transfer policies, validation,
   normalized plans, and public snapshots. Use only controlled fake adapters.
   This is the starting point.
2. Implement the supervised room lifecycle, participant and service attachment,
   idempotent commands, routing policy, agent transfer state machine, and the
   versioned event envelope without real provider calls.
3. Implement the per-room Membrane pipeline with deterministic source and sink
   elements, individual tracks, explicit output branches, bounded buffering,
   and requested mixing.
4. Prove participant service chains with fake STT, guardrail, LLM, and TTS
   adapters, primary-to-backup failover, a room conversation-context service,
   scoped tools, and a room-wide observer that cannot stall media.
5. Implement deterministic VAD-backed turn detection and barge-in. Prove turn
   timestamps, cancellation of in-flight LLM and TTS work, bounded audio flush,
   suppression of late results, and generated-versus-delivered output state.
6. Define artifact structs and the local artifact-store adapter. Prove
   individual and mixed audio, canonical transcript, call details, manifest
   finalization, partial writes, and shutdown flushing.
7. Expose the same room commands through the versioned Plug/WebSock layer with
   authentication, authorization, idempotency, and bounded protocol limits.
8. Implement the v1 WebSocket participant media-ingress connection and
   read-only media output subscription. Prove format validation, timestamps,
   authorization, independent buffering, lag policy, reconnect behavior, and
   teardown with deterministic clients and the `samples` web application.
9. Add one replaceable production adapter each for STT, LLM, and TTS and verify
   the complete browser-to-Vxpipe-to-agent-to-browser voice path through the
   sample application in the tagged interoperability lane.
10. Build the supported Docker image and prove the embedded and standalone
    acceptance paths with runtime configuration, health, readiness, metrics,
    startup rollback, concurrent rooms, and graceful shutdown.

Each checkpoint includes its public contract, deterministic tests, relevant
notes, failure semantics, and applicable vendor/service and end-to-end
performance metrics. Live-provider interoperability remains a separate tagged
test lane.

### Post-v1 delivery increments

After the v1 acceptance criteria are green, capabilities should be added as
small end-to-end increments rather than as a second broad foundation phase. The
expected early increments are:

1. Add the first telephony adapter end to end for inbound and outbound calls,
   including exact raw-body webhook verification, bidirectional media, and
   normalized DTMF.
2. Add a second telephony adapter and production backup STT, LLM, and TTS
   candidates to exercise provider-neutral behaviour and failover with live
   integrations.
3. Add media-plane call bridging and provider-native bridging where supported,
   including failure and teardown tests for both modes.
4. Add packaged IVR navigation and voicemail detection on top of normalized
   DTMF, connection events, and participant services.
5. Add the S3-compatible artifact-store adapter and the selected production
   recording formats, upload strategy, and retention controls.
6. Add richer evaluation, audio preprocessing, diagnostics, and optional
   turn-scoped artifacts without making sensitive retention the default.
7. Introduce additional media track kinds and adapters when multimodal work is
   scheduled, beginning with contracts that preserve the v1 voice behavior.

### Decisions deliberately left open

The first contract work should gather evidence before fixing:

- the final module and HTTP resource names;
- the exact v1 WebSocket audio format, binary frame envelope, timestamp and
  sequencing rules, and whether reconnect can resume an existing attachment;
- whether public plans expose generic signal ports, a constrained routing DSL,
  or both;
- the exact Silero VAD package and runtime boundary, VAD thresholds, and the
  initial strategy used to distinguish silence from semantic turn completion;
- the precise safe failover boundaries for partially emitted model and speech
  output;
- the exact guardrail decision and retry vocabulary;
- which event classes receive durable at-least-once delivery in the standalone
  service;
- the initial recording container and codec combinations;
- multipart upload versus bounded local spool behavior for each artifact store;
- manifest update and conditional-write requirements across object stores;
- whether the standalone service offers an optional durable event outbox
  without introducing a mandatory product database; and
- the first production STT, LLM, TTS, and VAD implementations, and the first
  post-v1 telephony and object-storage adapters.

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

## V1 acceptance criteria

V1 is complete only when all of the following are true:

1. An Elixir application can add the core as a dependency, supervise it, create
   a room from a validated plan, run a voice call with custom adapters, and end
   it without starting HTTP.
2. The supported Docker image starts from runtime configuration and exposes
   health, readiness, and an authenticated, versioned control API.
3. A non-Elixir application can make one idempotent request to create a
   human-to-AI voice room, authorize the needed media attachments, observe
   normalized state changes, use the supported controls, and end it.
4. A client can open an authenticated participant media-ingress WebSocket, send
   binary microphone audio, open a separately authorized read-only output
   subscription, and receive the selected agent or mixed audio track.
5. One production STT, LLM, and TTS adapter can form a complete agent service
   chain, while deterministic adapters prove primary-to-backup failover and
   failure exhaustion without changing the logical service identity.
6. A Silero VAD-backed turn detector and deterministic media tests prove turn
   boundaries, user barge-in, cancellation of in-flight LLM and TTS work,
   bounded output flushing, and suppression of late output.
7. A room conversation-context service survives agent handoff, exposes only
   authorized participant projections, and records accepted tool results
   without retaining sensitive content by default.
8. Room-level and participant-level tools enforce scope, input validation,
   authorization, deadlines, cancellation, idempotency, and late-result
   handling.
9. The versioned transfer API performs and observes cold and warm
   agent-to-agent handoffs while preserving room identity, applying the chosen
   context policy, and rolling back a failed cutover.
10. Deterministic end-to-end tests prove timed WebSocket audio can enter through
    a participant connection, traverse a Membrane graph and agent service
    chain, and reach authorized individual and requested mixed outputs without
    live providers.
11. Media ingress and every output subscription have independent authorization,
    bounded buffering, format validation, lag and disconnect policies, and
    teardown; a slow subscriber cannot stall a room or another subscriber.
12. Optional local artifacts can produce aligned individual and mixed audio, a
    canonical transcript, call details, and an explicit complete, partial, or
    failed manifest without enabling retention by default.
13. A host application can mount `vxpipe_web` and use the same room-control,
    media-ingress, and output-subscription protocols without starting the
    standalone listener or using Phoenix Channels.
14. Multiple room islands run concurrently and startup rollback, provider and
    pipeline failure, slow consumers, bounded queues, metrics, and ordered
    shutdown are observable and covered by regression tests.
15. The public plans, behaviours, events, transfer API, HTTP API, and WebSocket
    protocol are documented well enough for another project to use and extend
    without copying private code.
16. The TypeScript sample backend can orchestrate a room without exposing
    server credentials, and the Storybook-developed web client can complete the
    v1 media-ingress and output-subscription flow against that room.

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
