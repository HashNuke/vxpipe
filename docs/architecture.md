# Vxpipe protocol and runtime architecture

Status: Living architecture; room creation, one-participant RTVI connection,
text-turn, Gemini model-inference, Deepgram Flux audio-input, and Deepgram Flux
text-to-speech, typed interruption, and provider-driven spoken barge-in slices
are implemented

## Decision

Vxpipe will provide a protocol-neutral, OTP-native voice runtime. Client and
provider protocols will be adapters at the gateway boundary rather than types
embedded in the call engine.

The first client adapter will support unmodified current RTVI 2.x clients and
the RTVI 2.1 feature set. RTVI is one supported access mechanism, not Vxpipe's
internal protocol or permanent public object model. A future custom protocol or
another client standard must be able to drive the same engine commands and
consume the same domain events without changing the engine.

This document refines the initial ideas in
[`labnotes/20260903-0323-vxpipe-thoughts.md`](../labnotes/20260903-0323-vxpipe-thoughts.md)
using the Callx findings in
[`labnotes/20260902-1743-investigate-callx-architecture.md`](../labnotes/20260902-1743-investigate-callx-architecture.md)
and the current [RTVI standard](https://docs.pipecat.ai/client/rtvi-standard.md),
[RTVI server reference](https://docs.pipecat.ai/api-reference/server/rtvi/introduction.md),
and [RTVIProcessor reference](https://docs.pipecat.ai/api-reference/server/rtvi/rtvi-processor.md).

The document primarily describes the intended Vxpipe contract. The implemented
vertical slices are called out below; later sections and checkpoints remain
proposed unless stated otherwise.

## Why support RTVI

RTVI supplies a useful client-facing vocabulary and existing client SDKs. Its
standard messages cover readiness, speaking state, user transcription, bot
output, LLM and TTS activity, client-side function calls, text input, DTMF,
metrics, custom requests, and UI interaction. Pipecat clients already handle
media devices, transports, session state, and these messages across web and
mobile environments.

Supporting RTVI at the gateway provides:

- unmodified Pipecat client compatibility;
- a faster path to browser and mobile clients;
- a familiar readiness and conversation event model;
- transport-independent application messages above WebRTC or WebSocket;
- existing APIs for custom fire-and-forget messages and correlated requests;
- client-side tool handlers, DTMF, text input, and media-device controls; and
- a stable baseline against which a richer Vxpipe client can be introduced.

RTVI does not define everything Vxpipe needs. Authentication and transport
credential issuance occur outside the RTVI envelope. Its user-and-bot vocabulary
does not provide a complete multi-participant room, connection, track, telephony
leg, transfer, durable event, replay, authorization, cluster-placement, or
supervision model. Reconnection starts a new client connection rather than
defining durable room resumption.

RTVI must therefore remain a client projection over the engine rather than the
engine's source of truth.

## RTVI and Callx serve different boundaries

The existing Callx work is stronger than RTVI as a description of an internal
voice runtime. It models rooms, participants, transport connections,
capabilities, topic authorization, transfers, DTMF collection, tool invocations,
and room lifecycle. Its room process serializes authoritative state changes,
while OTP supervisors and monitors isolate runtime workers.

Callx is not a suitable public wire protocol in its current form. Its API and
events contain Elixir structs, atoms, modules, functions, PIDs, and private
adapter state. It has no wire schema or protocol version, committed events lack
durable event IDs and room sequence numbers, event history retains raw audio
without a bound, and synchronous hooks or subscribers can delay the room
mailbox. A room-authority crash can also restart that authority beside surviving
workers.

Vxpipe will retain the useful Callx domain distinctions while replacing its
in-process event surface with explicit protocol-neutral contracts.

| Concern | RTVI | Current Callx | Vxpipe choice |
| --- | --- | --- | --- |
| Existing clients | Cross-platform SDKs | No public clients | RTVI gateway adapter |
| Readiness and conversation UI | Standard client events | Internal topic events | Project engine events into RTVI |
| Rooms and participants | Primarily client/user and bot | Rich room model | Call-engine domain resources |
| Telephony legs and transfers | Not a complete model | Explicit state machines | Call-engine resources and events |
| Internal scheduling | Outside the protocol | OTP processes | Redesigned OTP runtime |
| Wire contract | JSON messages | BEAM terms | Versioned gateway codecs |
| Durability and replay | Not defined | Unbounded in-memory history | Bounded journal and snapshots |
| Authentication | Outside RTVI | Host-specific | Gateway session and operation scopes |

## Domain terminology

Vxpipe uses **capability** for behavior available to a participant. Capability
kinds include speech-to-text, model inference, text-to-speech, input and output
guardrails, recording, and other composable voice-runtime functions.

The related terms have distinct meanings:

- A **participant** has zero or more configured capability instances.
- A **capability kind** defines the provider-neutral contract and the events it
  consumes and publishes.
- A **capability instance** is one participant's resolved runtime attachment,
  including its provider selection, options, lifecycle, and routing policy.
- A **provider** supplies an underlying external function, such as hosted
  speech recognition, model inference, or speech synthesis.
- An **adapter** implements a capability contract for a provider and translates
  between provider-native data and Vxpipe commands, frames, and events.
- A **service** is an external system or an independently deployed application,
  not the generic name for a participant's runtime behavior.

For example, a human participant may have a `speech_to_text` capability instance
implemented by a provider adapter. An AI participant may have model-inference,
text-to-speech, and guardrail capability instances. Whether an adapter uses a
remote API or in-process code does not change the participant-facing capability
contract.

Vxpipe will not initially define a standalone voice-activity-detection
capability or run local speech/model inference such as Whisper. Selected hosted
STT providers are responsible for their supported speech-activity, endpointing,
and transcription behavior. When a provider emits speech-activity or endpointing
evidence, its adapter normalizes that evidence into Vxpipe turn events; the call
engine does not run a separate detector.

### Call variables, conversation history, and model context

The approved call-definition design uses **Call Variables** for typed, shared
values grouped into sections. For example, `booking` is a section and `status`
is a variable within it. Use "variable", not "field", for these named values.
Object-valued variables may contain nested data without adding a path language.

**Conversation history** contains messages and tool calls/results. A spoken
transcript is a view of what participants said. **Model context** means everything
supplied to the LLM: instructions, selected history, and permitted call variables.
Neither history nor model context is the mutable variable store.

The planned definition uses `call_variables.sections`, invocation values use
`initial_variables`, and per-agent section grants use `variable_permissions`.
The tools are `read_variables(sections)`, `update_variables(section_name, data)`,
and `update_variable(section_name, variable_name, value)`. Sections are read-only
or read+write for an agent; omitted grants give no access. RoomAuthority retains
ownership, datatype checks, revisions, and incremental updates without demanding
all variables at once.

For a remote MCP booking, the agent receives the tool result and separately calls
our variable-update tool. The remote MCP does not need Vxpipe-specific knowledge,
and no automatic result-mapping layer is required. These are approved design
contracts, not newly implemented runtime features; see the
[call-definition design](../labnotes/20260905-0405-call-definition-design.md#call-variables-are-typed-sectioned-and-permissioned).

## Architectural boundaries

```text
Pipecat clients ──> RTVI 2.x adapter ─┐
Future clients  ──> Custom adapter    ├──> Protocol-neutral commands
Telephony       ──> SIP adapter       ┘              │
                                                     ▼
                                          OTP-native Call Engine
                                                     │
                                      Domain events / media / metrics
                                                     ▼
                                  Protocol-specific event projections
```

Four contracts remain separate:

1. **Media transport:** WebRTC tracks, SIP/RTP, or WebSocket audio and video.
2. **Client protocol:** RTVI or another adapter's readiness, commands, and event
   projection.
3. **Call-engine protocol:** typed commands, signals, media frames, and domain
   events exchanged between supervised Vxpipe processes.
4. **Management and delivery:** authenticated REST/control operations, durable
   event subscriptions, webhooks, artifacts, and configuration.

The `vxpipe_gateway` application owns external protocol and transport adapters.
The `vxpipe_call_engine` application owns room state, participant and capability
lifecycle, routing, turn semantics, tools, transfers, and protocol-neutral
events. The dependency direction is from gateway to the public call-engine
contract. The call engine must not depend on RTVI message names, JSON shapes,
client SDKs, or transport credentials.

## Gateway protocol adapter contract

Every client protocol adapter must implement the same responsibilities:

- negotiate the supported protocol version and optional features;
- bind an authenticated gateway session to a tenant, actor, room, participant,
  connection, and transport;
- decode external messages into validated engine commands;
- authorize each command before it reaches the room authority;
- project only authorized engine events into the external protocol;
- correlate requests and responses with bounded deadlines;
- apply connection-level rate and queue limits;
- redact private engine and provider state; and
- detach or terminate the participant according to the room's disconnect
  policy.

The common adapter state includes:

- protocol name and negotiated version;
- advertised optional capabilities;
- tenant, actor, roles, and scopes;
- stable interaction and room IDs;
- room incarnation ID;
- participant and connection IDs;
- transport identity and credential audience;
- last acknowledged durable event cursor; and
- connection-specific limits and deadlines.

The adapter must never expose PIDs or use a distributed PID as public identity.

## RTVI 2.x compatibility

The first adapter accepts RTVI major version 2 and implements the current 2.1
feature set. Deprecated major version 1 is not part of the initial contract.
Unsupported major versions receive a protocol error and cannot activate a
session.

This needs explicit conformance testing because the standalone standard page
labels itself version 1.0 while including later 1.2 additions, and the current
RTVIProcessor advertises 2.1.0. The documentation also contains details that
should not be treated as a generated schema, such as an inconsistent
`server-response` type label and metric values without a reliable unit field.
Actual current client behavior and versioned fixtures are the compatibility
authority.

### Session startup

RTVI does not authenticate a user or create transport credentials. Before the
RTVI handshake, a Vxpipe start endpoint must:

1. authenticate the caller;
2. authorize creation of or admission to a room;
3. resolve the room, participant role, agent version, and transport;
4. create a gateway session with a bounded lifetime;
5. issue narrowly scoped transport credentials; and
6. return connection parameters understood by the chosen client transport.

After the media transport connects, `client-ready` negotiates RTVI version and
attaches the gateway session. Vxpipe sends `bot-ready` only after room admission,
the requested participant, and the required agent pipeline are ready. A
connected transport is not sufficient evidence that the bot can process input.

### Standard message mapping

| RTVI input | Engine operation |
| --- | --- |
| `client-ready` | Negotiate protocol and attach the participant connection |
| `disconnect-bot` | Detach or end according to session policy |
| `send-text` | Submit text; interrupt older room-agent work when `run_immediately` is true, otherwise retain FIFO order |
| `dtmf` | Publish ordered DTMF input to the selected connection/input collector |
| `llm-function-call-result` | Complete the matching client-owned tool invocation |
| `client-message` | Dispatch a validated optional Vxpipe request or notification |
| UI messages | Dispatch authorized UI state, event, and cancellation operations |

Engine events project to standard speaking, transcription, bot-output,
LLM/TTS, tool, error, metric, server-message, and UI messages. A client that
does not opt into any Vxpipe-specific capability must still be able to complete
a normal text or audio conversation.

### Optional Vxpipe messages

Vxpipe-specific features use RTVI's standard custom-message mechanisms rather
than incompatible top-level message types. Clients advertise or discover them
through `bot-ready.data.about.vxpipe.extensions`.

Client notifications use `client-message.data.t`. Correlated queries and
mutations use the SDK's `sendClientRequest` facility. Server notifications use
`server-message` with a versioned envelope:

```json
{
  "t": "vxpipe.event",
  "v": 1,
  "d": {
    "event_id": "evt_01...",
    "room_id": "room_01...",
    "room_sequence": 42,
    "kind": "participant.joined",
    "occurred_at": "2026-09-03T05:00:00Z",
    "correlation_id": "cmd_01...",
    "data": {}
  }
}
```

Agent interruption uses `t: "vxpipe.turn"`, `v: 1`, and
`d.kind: "interrupted"`. Its data names the interrupted agent participant,
originating participant and turn, confirmed played milliseconds, and the
authenticated participant, connection, command, and correlation that caused the
interruption. The trigger may be immediate typed input or an authenticated
provider speech-start signal. The parallel standard `bot-interrupted` event
remains unmodified.

All mutations carry a stable `command_id`. Domain-level responses have a typed
result envelope:

```json
{
  "ok": false,
  "error": {
    "code": "participant_not_authorized",
    "message": "The participant cannot perform this operation.",
    "retryable": false,
    "details": {}
  }
}
```

RTVI protocol errors remain reserved for malformed, unsupported, or
uncorrelatable wire messages.

Initial optional message families are:

- `vxpipe.capabilities`: negotiated protocol, transport, and engine features;
- `vxpipe.room`: snapshot, roster, subscriptions, lifecycle, and replay cursor;
- `vxpipe.participant`: roles, state, mute, hold, and connection state;
- `vxpipe.turn`: speech, transcript, endpointing, interruption, and commit state;
- `vxpipe.playout`: queued, first-audio, spoken ranges, truncation, and completion;
- `vxpipe.agent`: active-agent state and agent handoff;
- `vxpipe.call`: telephony legs, DTMF, voicemail, IVR, and transfer lifecycle;
- `vxpipe.tool`: invocation, progress, approval, result, and cancellation;
- `vxpipe.debug`: authorized live timeline, metrics, and bounded replay; and
- `vxpipe.session`: connection replacement and room resumption metadata.

These names describe external schemas only. Future protocol adapters may expose
the same engine capabilities with different wire messages.

## Call-engine protocol

The engine contract separates messages by lifecycle and delivery requirements.

### Commands


Commands request acknowledged state changes. Every command contains:

- command ID and schema version;
- tenant and authenticated actor identity;
- required scopes;
- room and incarnation IDs;
- optional participant, connection, capability, or tool target;
- absolute deadline;
- idempotency policy; and
- typed payload.

Examples include room admission, adding or removing a participant, changing
routing, sending text, beginning an input collection, completing a client tool,
initiating a transfer, changing an active agent, and ending a session.

Commands that alter authoritative room state receive a typed success or failure.
Calls are bounded. The engine must not make cyclic synchronous calls between
room, participant, connection, and capability processes.

### Signals

Signals cover interruption, cancellation, disconnect, nonterminal stop, process
failure, and shutdown. They are not ordinary commands because timely delivery
can invalidate queued work.

An interruption cancels speculative model work, interruptible tool work, queued
speech, and unsent audio for the affected turn while leaving the conversation
active. Graceful end drains accepted work. Immediate cancellation abandons it.
A nonterminal stop drains a pipeline stage while retaining the process for later
work. These transitions must remain distinct.

### Media frames

Media frames are ephemeral and contain:

- room, incarnation, participant, connection, and track IDs;
- format, codec, sample rate, channels, and direction;
- capture/presentation timestamp and sequence;
- turn or utterance correlation when known;
- provider-native metadata in a bounded, redacted namespace; and
- the binary payload.

Raw media is never appended to room event history. Recorders and stream sinks
subscribe through explicit bounded media paths with retention, encryption, and
failure policy.

### Domain events

Committed domain events contain:

- globally unique event ID;
- schema version;
- tenant, interaction, room, and incarnation IDs;
- monotonic sequence within the room incarnation;
- participant, connection, capability, agent-version, and transport IDs when
  applicable;
- occurrence timestamp;
- causation and correlation IDs;
- visibility and data-classification metadata;
- normalized payload; and
- optional redacted provider payload.

Events are immutable after commitment. Ephemeral processor messages and media
frames do not become durable merely because they describe lifecycle activity.
Only the room authority assigns room sequence numbers.

### Snapshots and replay

A snapshot is a public, authorized projection, never a serialization of internal
GenServer state. It includes the resolved room version, current lifecycle,
participants, connections, capabilities, active agent, current transfers/tools,
and the last durable room sequence.

Clients resume from a snapshot plus events after a cursor. Media is not replayed
through the event journal. A reconnect creates a new transport connection and
connection ID even when it rejoins the same interaction, room, and participant.

## Conversation semantics

### Human input and transcription

The initial thought that a human publishes transcription only after a completed
turn is too coarse. Vxpipe distinguishes:

1. provider speech-activity start or stop, when available;
2. semantic user-speaking start or stop;
3. partial transcript;
4. provider-final transcript segment;
5. committed conversational turn;
6. corrected or replaced transcript; and
7. cancelled or discarded turn.

Partial and segment-final transcripts remain observable to authorized clients
and monitors. The LLM consumes only the configured committed-turn event unless
the agent explicitly enables speculative generation. Provider `final` must not
be assumed to mean conversational end of turn.

RTVI `user-transcription.final` projects partial versus provider-final state for
compatibility. The optional `vxpipe.turn` messages carry the richer turn ID,
phase, evidence, timestamps, endpointing reason, and commit state.

Microphone media remains active while agent output plays. A normalized provider
`StartOfTurn` is an immediate interruption signal from the participant and
connection to which that STT capability is bound. It stops older work before the
new participant-turn event is committed. The provider's later `EndOfTurn`
commits input but does not repeat cancellation. This uses hosted provider turn
detection; the call engine does not run a local VAD.

### Agent output and actual playout

Generated LLM text, text submitted to TTS, synthesized audio, scheduled audio,
and audio actually played are different facts. Conversation history and durable
transcripts must not claim that interrupted or dropped text was heard.

Each agent utterance receives an ID. The output path reports queued text,
synthesized ranges, first audio, played word or character ranges, interruption,
truncation, and completion. The final assistant transcript is derived from
confirmed playout where the transport supplies sufficient evidence; otherwise
it carries an explicit confidence/source marker.

RTVI `bot-output` remains the compatible best-effort projection. The
`vxpipe.playout` family exposes precise Vxpipe semantics.

## OTP runtime topology

```text
Vxpipe.CallEngine.Application
├── Registry / cluster room directory
├── DynamicSupervisor RoomSupervisor
│   └── RoomIncarnationSupervisor
│       ├── RoomAuthority
│       ├── ParticipantSupervisor
│       ├── ConnectionSupervisor
│       ├── CapabilitySupervisor
│       └── PipelineSupervisor
├── Task.Supervisor for bounded external work
└── Event/metric exporter supervisors
```

Each room incarnation is an isolation boundary with its own process tree and
per-process heaps. Individual runtime workers are started through their owning
dynamic supervisor and monitored by the room authority.

The room authority must never restart alone beside surviving workers. An
authority or static room-infrastructure failure terminates the complete room
incarnation. Recovery, when configured, creates a new incarnation from the
immutable resolved plan and a durable checkpoint. Commands carrying an old
incarnation ID are rejected.

Recoverable provider or participant failures do not automatically destroy the
room. The worker is restarted only when its adapter declares restart safe;
otherwise it enters a failed state and the configured fallback or terminal
policy runs.

### Scheduling and backpressure

The room authority owns state transitions, not audio processing. Media,
provider I/O, model work, serialization, persistence, webhooks, recordings, and
metrics export execute outside its mailbox.

Every streaming edge declares:

- maximum queued frames/bytes and age;
- whether it blocks, drops newest, drops oldest, coalesces, or terminates;
- cancellation behavior;
- downstream deadline;
- overload metric and event; and
- whether loss is acceptable for that frame class.

BEAM mailboxes are not a backpressure mechanism. Queue length, process memory,
reductions, scheduler utilization, and dropped/coalesced work are monitored.

OTP 28 priority aliases may be evaluated for sparse interrupt or cancellation
signals, but not for media or normal events. Erlang's
[priority-message documentation](https://www.erlang.org/doc/system/ref_man_processes.html#priority-messages)
warns that the feature is intended for narrow cases and not large priority
queues. The baseline design uses an explicit control path and bounded stage
queues; priority aliases are adopted only if focused benchmarks show a material
benefit.

### Cluster ownership

The cluster directory maps each active room to `{node, incarnation}`. A gateway
resolves the current owner and forwards protocol-neutral commands rather than
exposing remote PIDs. Ownership registration is conditional on the incarnation
so delayed messages from a prior owner cannot reclaim or mutate the room.

Node loss, network partition, and owner migration have explicit admission and
recovery policies. Vxpipe does not assume BEAM distribution itself supplies
public authentication, durable state, or split-brain resolution.

## Security and observability

The gateway authorizes every room and participant operation. Admission to a
transport does not imply permission to observe all room events or control other
participants.

Public projections exclude:

- provider credentials and authorization headers;
- secret-bearing callback or signed URLs;
- private adapter state and authenticated request objects;
- PIDs, references, functions, module names, and stack internals;
- unapproved provider-native payloads; and
- transcript, tool, or media data outside the actor's visibility scope.

Live debugging is an authenticated monitor participant with explicit scopes,
topic grants, retention, and rate limits. It consumes projected events and
sampled media/metrics outside the room hot path. Debugging does not enable
unbounded event or raw-audio retention.

Telemetry includes:

- speech start/stop and transcription delay;
- turn-commit and interruption delay;
- LLM time to first token;
- TTS time to first audio;
- transport playback delay and end-to-end response latency;
- tool, transfer, and fallback lifecycles;
- provider availability and error categories;
- tokens, characters, audio duration, and cost attribution;
- per-room mailbox and bounded-queue pressure; and
- scheduler, reductions, memory, and process restart information.

Every metric carries a unit, aggregation, source, model/provider, and relevant
room/turn/utterance correlation. RTVI metric messages are a compatibility
projection and are not the canonical telemetry schema.

## Configuration and container boundary

OTP application settings are the canonical configuration entry point for
runnable Vxpipe applications. Each application reads its namespaced setting once
at its application boundary, validates and normalizes it, and passes explicit
options down its supervision tree. Reusable supervisors also accept those
options directly so an embedding host is not forced to mutate global
application state.

Vxpipe's own `config/<env>.exs` files configure only the Vxpipe root project.
Mix does not evaluate a dependency's configuration files in a consuming
project; the consuming release owns its application settings. Runtime modules
must not branch on `Mix.env()`. Deployment environment variables are read only
from `config/runtime.exs` and translated into application settings before the
applications start.

The Docker runner accepts one versioned JSON configuration through an explicit
`--config` path. The same schema permits pinned resource references or complete
inline definitions for a standalone process.

The JSON loader is an adapter into the same validated application options. It
must not create an independent configuration path or allow raw string-keyed JSON
to flow through runtime processes.

External strings resolve through closed registries. JSON never selects an
arbitrary BEAM module and never uses `String.to_atom/1`. Provider credentials are
runtime secret references to environment variables, mounted files, or an
external secret store. Resolved plans and validation errors are redacted.

A resolved room plan pins:

- configuration and schema version;
- agent and workflow versions;
- provider adapters and capability snapshots;
- transport, codec, and media policies;
- turn, interruption, tool, and fallback policies;
- artifact, retention, and event policies; and
- secret reference generations without storing secret values.

The container exposes readiness only after required engine and gateway services
can accept work. Termination drains admitted sessions according to policy,
rejects new admission, and exits with deterministic status. Logs are structured,
secret-safe, and exportable without a local interactive login.

### Development ingress

The repository development stack uses Caddy as its single tailnet HTTPS ingress.
Caddy binds to the discovered Tailscale address, routes `/api/*` to the gateway
over loopback, exposes the gateway health check at `/healthz`, and routes
remaining paths to the Vite samples application over loopback. This supplies one
stable secure browser origin and leaves room for additional development
applications without making Caddy part of the product protocol model.

`bin/dev` resolves the tailnet hostname and address, renders a complete Caddy
JSON configuration as the invoking user, and then asks Goreman to run only the
Caddy process through sudo. The root process does not inherit application
secrets or depend on manually preserved environment variables. This lets Caddy
retrieve `.ts.net` certificates from tailscaled without configuring
`TS_PERMIT_CERT_UID`; Mix and Vite remain unprivileged.

Caddy terminates only HTTP and WebSocket traffic. WebRTC media and RTVI data
channels still establish their own ICE-selected path and are not proxied through
Caddy. Production ingress remains deployment-specific.

## Deterministic testing facilities

Vxpipe includes deterministic Morse/tone STT and TTS adapters in the library.
They provide reproducible audio without external providers and support exact
assertions for routing, transcription phases, interruption, playout, tool calls,
and teardown.

These adapters are used for:

- protocol conformance tests;
- multi-participant routing tests;
- turn and barge-in timing tests;
- event replay and snapshot tests;
- failure and supervision tests;
- container smoke tests; and
- concurrency and scheduler regression benchmarks.

## Implementation checkpoints

Each behavior checkpoint begins with the smallest failing externally observable
test and leaves the umbrella usable.

### Implemented create-room slice

The first deliberately narrow vertical slice crosses the browser, gateway, and
call-engine boundaries without claiming completion of checkpoints 1 through 3:

1. The samples browser sends `POST /api/rooms` to its same-origin gateway.
2. The gateway injects a configured development principal with a tenant, actor,
   and `rooms:create` scope. The browser cannot assert those identities.
3. The browser supplies a non-secret, randomly generated room ID. The gateway
   validates it and constructs the protocol-neutral `CreateRoom` command with a
   generated command ID and absolute deadline.
4. The call engine starts a temporary room-incarnation supervisor through its
   named dynamic room supervisor.
5. A significant, temporary room-authority child owns the initial `open` state.
   If that authority terminates, the whole incarnation terminates and is not
   automatically recreated under stale identity.
6. The engine returns a public snapshot, which the gateway serializes. That
   confirmation replaces the creation screen with the responsive Pipecat
   console; the console receives the whole viewport without Vxpipe overlays.

The development route is disabled in base configuration and enabled only by the
repository development overlay. The configured principal is not authentication;
it is a replaceable seam where a future authenticated gateway session supplies
the same protocol-neutral identity. At this checkpoint the slice did not yet
implement generic command/event contracts, participants, media, RTVI signaling,
persistence, or room recovery.

### Implemented participant connection slice

The next slice admits one human participant and proves a real unmodified Pipecat
client can cross the browser, HTTP, WebRTC, RTVI, and OTP boundaries:

1. `POST /api/rooms/:room_id/sessions` requires the configured `rooms:join`
   scope and asks the call engine to admit a protocol-neutral human participant.
2. The room authority starts that participant only through the dynamic
   participant supervisor owned by the room incarnation. It monitors the
   participant and releases its identity if the participant terminates.
3. The gateway issues an opaque, single-use session bound to the tenant, actor,
   room incarnation, and participant. The default development lifetime is five
   minutes; expiry is enforced with monotonic time.
4. The samples app passes that session in the current Pipecat client's
   `webrtcRequestParams.requestData` and uses the same-origin
   `/api/rtvi/offer` endpoint.
5. The gateway implements Pipecat Small WebRTC's `POST` offer/answer and `PATCH`
   trickle-ICE requests with ExWebRTC. It accepts the ordered `chat` data channel
   and ignores transport signalling and keepalive messages that are not RTVI
   application messages.
6. A current RTVI 2.x `client-ready` receives a correlated `bot-ready` for
   server protocol 2.1.0. Unsupported or malformed version strings receive a
   correlated protocol error without crashing the transport process.
7. Closing the data channel tears down the complete temporary connection
   incarnation, including the peer connection, while the participant and room
   incarnation remain alive.

The gateway owns the session, WebRTC, and RTVI processes and their dependencies.
The call engine sees only participant admission and contains no ExWebRTC,
Pipecat, JSON, or RTVI types. The detailed decision, supervision topology,
failure behavior, and verification evidence are recorded in
[`rtvi-participant-connection.md`](rtvi-participant-connection.md).

At that checkpoint this was transport and protocol readiness, not a voice
conversation pipeline. Incoming RTP terminated at a diagnostic sink, and there
was not yet an agent participant or text-turn path.

### Implemented deterministic text-turn slice

The third slice adds a provider-free conversational round trip without changing
the browser UI or introducing RTVI types into the call engine:

1. Development room creation resolves a deterministic text agent. The room
   authority admits its agent participant and starts the responder through the
   room incarnation's dynamic capability supervisor.
2. A WebRTC connection must attach to its exact room incarnation and admitted
   human participant before it can complete negotiation and report
   `bot-ready`. A room without a ready agent path rejects attachment.
3. The engine and gateway monitor each other across that attachment. Browser
   disconnect removes the room subscription; loss of the room, human
   participant, or agent capability tears down the transport connection.
4. The gateway decodes RTVI `send-text` into a validated, protocol-neutral
   `SendText` command using identity from the bound session rather than the
   client message.
5. The room authority verifies that the caller owns the attached connection and
   emits consecutive `ParticipantTurnStarted` and `ParticipantTurnCompleted`
   events for the complete typed input before dispatching work outside its
   mailbox to the deterministic capability.
6. The capability produces `Echo: <input>`. The room authority assigns IDs and
   consecutive room-incarnation sequences to protocol-neutral `TextOutput` and
   `AgentTurnCompleted` events and sends them only to the originating
   connection. Completion is separate because one turn may eventually contain
   multiple output segments.
7. The gateway projects participant boundaries as RTVI user start/stop messages
   and agent output as an unspoken `bot-output` followed by
   `bot-stopped-speaking`. Pipecat's protocol 2.x client uses these lifecycle
   events to keep successive typed turns in separate messages, including turns
   submitted inside its speech-pause grace period. The unmodified Pipecat
   conversation view displays both the locally injected user message and the
   engine-produced assistant response.

This establishes the first bidirectional command/event path and the first
runtime capability instance. It does not add transcription, model inference,
speech synthesis, outbound audio, provider credentials, reconnection,
production authentication, TURN policy, persistence, or room recovery. The
detailed decision and verification evidence are in
[`deterministic-text-turn.md`](deterministic-text-turn.md).

### Implemented Deepgram Flux audio-turn slice

The fourth slice routes the browser's existing microphone track through a
provider-neutral engine boundary while preserving RTVI as a gateway projection:

1. The gateway resolves the negotiated codec for each remote audio track and
   maps an ExRTP Opus packet to a protocol-neutral `AudioFrame`. No ExWebRTC or
   ExRTP type crosses into `vxpipe_call_engine`.
2. Attaching a human connection starts one temporary speech-to-text capability
   and one bounded media ingress through the room incarnation's dynamic
   capability supervisor. The returned `ConnectionAttachment` is an internal
   runtime handle and is never a public snapshot or wire value.
3. Media ingress validates room-incarnation and connection identity, binds the
   stream to its first accepted track, and enforces maximum frame age, queue
   length, and total queued bytes. It allows only one provider send in flight,
   preserves accepted order, tolerates isolated overflow as RTP loss, and
   terminates the stream after sustained overflow.
4. The Deepgram adapter owns Flux `/v2/listen` query construction, authorization,
   bounded JSON decoding, and fixed provider-event mapping. The supervised socket
   owns WebSocket lifecycle and sends raw 48 kHz Opus payloads without exposing
   its credential or provider payloads to the room.
5. The room authority receives only normalized low-rate signals. `StartOfTurn`
   creates an audio turn, `Update` replaces the current partial transcript, and
   `EndOfTurn` emits a provider-final transcription followed by a distinct
   participant-turn completion. Eager end predictions never invoke the agent.
6. Only the complete, non-empty `EndOfTurn` transcript is dispatched once to the
   deterministic agent. All resulting events retain one engine turn correlation
   while receiving consecutive room-incarnation sequence numbers.
7. The gateway projects those events as RTVI `user-started-speaking`,
   `user-transcription` with the correct `final` flag, and
   `user-stopped-speaking`, followed by the existing deterministic bot output.
8. Closing or losing the provider before `EndOfTurn` does not fabricate a final
   transcript or committed turn. Provider and media failure tears down the
   affected WebRTC connection; automatic mid-turn reconnect is deferred.

The repository development overlay enables this capability with
`flux-general-en` and requires `DEEPGRAM_API_KEY` at runtime. Base configuration
leaves speech-to-text disabled, so an embedding application's environment is not
implicitly coupled to the repository's development provider. Default tests use
a fake transport; separately tagged live tests prove both individual 20 ms Opus
packet compatibility and the complete WebRTC-to-Flux-to-RTVI-to-agent path.
Detailed planning, provider research, implementation choices, and verification
evidence are recorded in
[`20260904-1212-stt-capability.md`](../labnotes/20260904-1212-stt-capability.md).

### Implemented Deepgram Flux text-to-speech slice

The fifth slice completes audible deterministic-agent output without placing
provider or WebRTC details in the room authority:

1. A configured agent owns one temporary text-to-speech capability under the
   room incarnation's dynamic capability supervisor. The capability keeps one
   persistent `/v2/speak` session so Flux prosody can persist across turns.
2. `TextOutput.will_be_spoken` is true only when the command requested audio,
   the room has a live TTS capability, and its originating connection supplied
   an output sink. Text-only and TTS-disabled paths still complete immediately.
3. The provider-neutral capability serializes one active synthesis request and
   a bounded pending FIFO. It sends separate Flux `Speak` and `Flush` controls,
   validates provider lifecycle messages, and synchronously hands bounded raw
   audio frames to the connection sink. The socket cannot accumulate unbounded
   audio in the capability mailbox. If the paced sink fills, the current binary
   frame and, when necessary, final-frame padding wait behind bounded calls while
   pace ticks drain capacity; provider bursts therefore apply TCP/WebSocket
   backpressure rather than terminating the room.
4. Flux streaming emits raw signed little-endian linear16 rather than Opus. The
   gateway's per-connection egress preserves provider-frame remainders, makes
   exact 20 ms 48 kHz mono frames, and encodes them through libopus. It queues a
   bounded number of packets and paces RTP at 20 ms with sequence numbers and
   timestamps advanced independently of provider chunk boundaries. The default
   500-packet queue covers ten seconds of ordinary output; longer turns remain
   supported through backpressure instead of requiring an unbounded buffer.
5. The gateway creates the outbound WebRTC audio track before answering the SDP
   offer. The output sink is an opaque process handle passed only through the
   internal attachment path; no PID enters a public command, snapshot, event,
   JSON value, or RTVI message.
6. Provider `SpeechMetadata` means no more synthesis audio. It causes egress to
   zero-pad at most one final incomplete PCM frame. Once the total packet count
   is known, egress reports elapsed scheduled playout every 100 ms for internal
   transport progress. The room does not emit agent completion until the last
   paced packet's duration has elapsed.
7. A spoken `TextOutput` is projected as an RTVI 2.x `bot-output` segment with
   `spoken_status: new`. Sending the first RTP packet produces a
   protocol-neutral `AgentSpeechStarted`; draining the final packet produces
   `AgentTurnCompleted`. The gateway projects those boundaries as
   `bot-started-speaking` plus an `in-progress` output whose entire text remains
   pending, then a `completed` output followed by `bot-stopped-speaking`. Flux
   supplies total audio duration but no per-word timing stream, so the RTVI
   adapter does not fabricate intermediate word progress from scheduled audio.
   Progressive highlighting is reserved for a future provider-alignment event;
   without one, the whole output changes from pending to completed at the paced
   gateway boundary. This gives an unmodified RTVI 2.x client one persistent
   assistant message without presenting estimated word positions as observed
   speech. The completion boundary does not claim a browser output-device
   acknowledgement.
8. This first audible slice initially gated microphone RTP and projected server
   mute boundaries during spoken output. The later spoken-barge-in checkpoint
   supersedes that input behavior: microphone RTP now continues to STT and no
   synthetic mute events are emitted. Output announcements remain serialized:
   the next segment is not exposed until the active paced turn completes, even
   though the engine may already have produced its text. At this checkpoint
   typed input during playback was queued output; the typed-interruption
   checkpoint below supersedes that behavior when `run_immediately` is true.
9. Fatal provider, transport, codec, sink, or sustained queue failures never
   fabricate successful completion. At this checkpoint local playback
   cancellation and Flux playback-offset reconciliation remained deferred; the
   typed-interruption checkpoint below implements them for immediate text.

Base configuration leaves text-to-speech disabled. The repository development
overlay enables `flux-haley-en`, requests 48 kHz linear16, and resolves the same
runtime `DEEPGRAM_API_KEY` used by Flux STT. Focused tests cover provider parsing,
bounded capability behavior, PCM framing, Opus encoding, RTP pacing, and room
sequencing. Separately tagged live tests prove both provider PCM output and a
complete RTVI text-to-Flux-to-Opus-to-WebRTC path. Research, Callx comparison,
the rejected PCMU path, and detailed evidence are in
[`20260904-1602-tts-capability.md`](../labnotes/20260904-1602-tts-capability.md).

### Implemented Gemini model-inference slice

The sixth slice replaces the repository development agent's deterministic echo
with room-scoped conversational generation while preserving the established
input and output boundaries:

1. `CreateRoom` accepts the provider-neutral `:model_inference` agent preset.
   The reusable base configuration leaves it disabled; the development overlay
   selects the ReqLLM adapter and `google:gemini-3.5-flash-lite`.
2. The room authority admits the normal agent participant and starts one
   temporary model-inference capability under the room incarnation's dynamic
   capability supervisor. Provider selection is application configuration, not
   part of the client protocol or room HTTP payload.
3. Typed RTVI input and committed Deepgram transcripts still converge on
   `SendText`. The capability accepts each turn quickly, while an explicitly
   named application `Task.Supervisor` owns blocking provider requests outside
   the room-authority mailbox.
4. Each capability runs one request at a time, bounds its pending FIFO, and
   retains a configured number of complete successful user/assistant pairs.
   The configured system prompt is placed first on every request and is not
   replaceable by client input.
5. The ReqLLM adapter translates neutral message roles, passes the runtime
   Gemini credential explicitly, and returns only normalized text chunks or an
   error. Streaming models feed a bounded sentence accumulator so each complete
   sentence can enter the existing `TextOutput`, optional TTS, and paced playout
   path before generation finishes. Models without streaming support return one
   buffered terminal segment through the same engine lifecycle.
6. A provider failure, invalid response, task exit, or timeout fails that turn,
   omits it from history, and advances queued work without ending the room. A
   protocol-neutral `AgentTurnFailed` becomes a correlated generic RTVI error
   response. A full pending queue rejects new work as retryable `agent_busy`
   before participant input events are committed.
7. Development reads `GEMINI_API_KEY` only from runtime configuration when the
   capability is enabled. The credential never enters commands, events, public
   snapshots, JSON payloads, browser configuration, or logs.

The engine does not expose provider token boundaries. It emits sentence-sized
segments and closes the logical assistant turn only after model generation and
all scheduled speech playout complete. Conversation history is volatile and
bounded by completed turn count, not tokens. Tools, token-aware compaction, durable history,
prompt-profile resolution, and provider fallback remain later checkpoints.
Provider-driven spoken barge-in is implemented by the later checkpoint below.
The detailed decision and verification evidence are in
[`model-inference-turn.md`](model-inference-turn.md).

### Implemented model tool-invocation slice

The next slice closes the first model/action/model loop without moving tool
execution into RTVI or a provider adapter:

1. Trusted call-engine configuration supplies modules implementing the neutral
   tool behavior. Each exposes a name, description, JSON parameter schema, and
   callback. The browser cannot submit executable modules or tool schemas.
2. The model capability gives neutral definitions to its provider adapter. A
   response may contain final text or normalized tool calls; both streaming and
   buffered providers use the same classification.
3. Calls execute sequentially inside the original supervised model request task.
   Results must be JSON-compatible and byte-bounded, and the complete loop has a
   configured maximum number of rounds plus the original turn timeout.
4. Tool results return to the provider as neutral assistant-call and tool-result
   messages. Provider-specific continuation metadata remains opaque adapter state
   and never enters public events.
5. Room authority publishes sequenced tool start, completion, failure, and
   cancellation events attributed to the agent, originating participant,
   connection, command, and correlation. Immediate typed or spoken interruption
   kills tool work and settles active calls before the turn interruption.
6. The RTVI gateway maps this lifecycle to
   `llm-function-call-in-progress` and `llm-function-call-stopped`. Other client
   protocols may project the same engine events differently.
7. Development enables an argument-free `get_current_time` tool returning UTC,
   allowing the unmodified samples console to demonstrate the entire loop.

The first tool runs within the model request task. Separate per-tool supervision,
parallel calls, approval gates, durable results, idempotency, and external action
providers remain later checkpoints. Detailed decisions and verification evidence
are in [`model-tool-invocation.md`](model-tool-invocation.md).

### Implemented typed turn-interruption slice

The next slice makes RTVI `send-text` urgency observable across the complete
model, synthesis, playout, and protocol path:

1. The room authority derives interrupter identity from the already attached
   connection. A client cannot override its participant ID in the message.
2. `run_immediately: true` cancels all older active and queued work in the room's
   current single logical agent-output lane before dispatching replacement work.
   `run_immediately: false` retains FIFO behavior.
3. `AgentTurnInterrupted` explicitly names the interrupted agent, originating
   participant and turn, target connection, interrupting participant and
   connection, both commands and correlations, and confirmed played time. This
   remains unambiguous with several human participants and does not assume agent
   identity from a process ID.
4. Audio egress immediately clears unsent RTP and PCM. The persistent Flux TTS
   capability keeps its one in-flight sink write in a supervised task so RTP
   backpressure cannot block cancellation. The persistent Flux TTS session
   receives an `Interrupt` with cumulative confirmed playback when audio has
   played, discards late provider audio, and starts replacement synthesis only
   after the old provider turn closes.
5. In-flight and queued model requests are canceled. A completed interrupted
   user/assistant pair is removed from volatile history when exact heard text is
   unavailable, preventing later prompts from treating the complete response as
   heard.
6. The gateway emits standard `bot-interrupted` without private fields. It also
   emits a versioned `vxpipe.turn` `server-message` carrying full attribution for
   Vxpipe-aware clients and never marks the interrupted output as completely
   spoken.
7. RTVI exposes one logical bot through each connection. The engine event names
   its agent participant so future agent composition remains protocol-neutral;
   independently addressable multi-agent clients require an optional Vxpipe
   message or another adapter.

This checkpoint covered typed interruption and initially left microphone RTP
gated during bot playout. The subsequent spoken-barge-in checkpoint supersedes
that transport behavior. The decision, rejected alternatives, implications,
and test evidence are recorded in
[`typed-turn-interruption.md`](typed-turn-interruption.md).

### Implemented provider-driven spoken-barge-in slice

The next slice uses the hosted STT provider's turn-start evidence to activate
the existing room-wide interruption path:

1. The WebRTC connection forwards valid inbound RTP through its bounded media
   ingress regardless of whether agent output is queued or playing. It no longer
   projects synthetic `user-mute-started` or `user-mute-stopped` messages around
   output.
2. A normalized provider `StartOfTurn` is accepted only from the STT capability
   bound to that tenant, room incarnation, participant, and connection. Neither
   the provider payload nor the client supplies the participant identity.
3. Before emitting the participant start, the room allocates the audio turn's
   command and correlation IDs and uses them in a protocol-neutral interruption
   context. The existing cancellation path stops model work, synthesis, and
   local playout. If no agent work exists, no interruption event is fabricated.
4. `AgentTurnInterrupted` precedes `ParticipantTurnStarted` in room sequence and
   attributes the cancellation to the authenticated STT connection. Repeated
   provider updates do not cancel twice.
5. The same audio turn continues through partial transcription. `EndOfTurn`
   commits a non-immediate internal text command because the interruption was
   already evaluated at speech start, then drives normal model inference and
   spoken output.
6. Standard clients receive `bot-interrupted`, user speaking/transcription
   events, and the replacement bot output. The optional `vxpipe.turn` projection
   carries the complete agent, source-turn, and interrupter identities.
7. The slice does not add local VAD or server-side acoustic echo cancellation.
   Capture endpoints should use their available echo control. Provider false
   starts can cancel agent work, and continuous microphone streaming continues
   to consume STT capacity during output.

The implementation and verification evidence are detailed in
[`spoken-barge-in.md`](spoken-barge-in.md).

1. **Protocol-neutral types:** implement command, signal, media-frame, event,
   snapshot, error, identity, and incarnation contracts with serialization-safe
   public projections.
2. **Room failure boundary:** implement the room incarnation supervision tree,
   authority, registries, bounded retention, and whole-incarnation failure
   behavior using deterministic adapters.
3. **Gateway adapter boundary:** define the protocol-adapter behaviour and prove
   it with an in-memory fake protocol before adding a concrete client protocol.
4. **RTVI 2.x codec:** implement handshake, standard message mappings,
   correlation, readiness, errors, and current-client conformance fixtures.
5. **Turn and playout semantics:** implement partial/segment/commit events,
   interruption, graceful end versus cancellation, and actual-playout tracking.
6. **Optional message schemas:** add capability negotiation, room/participant,
   tool, telephony, debug, replay, and session messages through RTVI custom
   messaging.
7. **Transport paths:** add WebSocket/browser media first, then SIP/PSTN while
   preserving the same participant and conversation contracts.
8. **Durability and operations:** add snapshots, replay, exporters, cluster
   ownership, admission control, health, tracing, and retention.
9. **JSON release and image:** compile mounted JSON into a redacted resolved
   plan, start the release, and verify readiness, drain, and deterministic exit.
10. **Second-adapter proof:** implement a minimal test-only second protocol
    adapter to ensure RTVI concepts have not leaked into `vxpipe_call_engine`.

## Acceptance criteria

- A current unmodified RTVI 2.x client completes text and audio conversations.
- A standard-only RTVI client works without consuming optional Vxpipe messages.
- Unsupported versions and malformed messages fail without activating or
  crashing a room.
- A second protocol adapter drives the same commands and domain events without
  modifying `vxpipe_call_engine`.
- Partial, provider-final, turn-committed, interrupted, and cancelled input are
  observably distinct.
- Generated, synthesized, scheduled, played, truncated, and interrupted agent
  output are observably distinct.
- Slow clients, exporters, recorders, or providers cannot block the room
  authority or unrelated sessions.
- Authority failure cannot leave stale room workers alive under a fresh room
  state.
- Retries and reconnects cannot duplicate acknowledged mutations.
- Snapshot plus cursor replay reconstructs the public room state without raw
  audio history.
- Authorization is enforced per operation and event projection.
- Credentials and private runtime terms never appear in public snapshots,
  events, errors, logs, or protocol messages.
- Deterministic adapters cover the same lifecycle used by network providers.

## Deferred compatibility

The first release does not promise RTVI major-version 1 compatibility, seamless
media resumption across reconnect, automatic room recovery after an
authoritative crash, or a particular production concurrency figure. These can
be added through explicit versioned policies without changing the
protocol-neutral engine contract.
