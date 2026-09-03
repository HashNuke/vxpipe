# Vxpipe protocol and runtime architecture

Status: Proposed architecture

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
[`labnotes/20260903-0323-vxpipe-thoughts.md`](labnotes/20260903-0323-vxpipe-thoughts.md)
using the Callx findings in
[`labnotes/20260902-1743-investigate-callx-architecture.md`](labnotes/20260902-1743-investigate-callx-architecture.md)
and the current [RTVI standard](https://docs.pipecat.ai/client/rtvi-standard.md),
[RTVI server reference](https://docs.pipecat.ai/api-reference/server/rtvi/introduction.md),
and [RTVIProcessor reference](https://docs.pipecat.ai/api-reference/server/rtvi/rtvi-processor.md).

The document describes the intended Vxpipe contract. It does not claim that the
current generated umbrella skeleton implements these components.

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

The `gateway` application owns external protocol and transport adapters. The
`call_engine` application owns room state, participant and capability lifecycle,
routing, turn semantics, tools, transfers, and protocol-neutral events. The
dependency direction is from gateway to the public call-engine contract. The
call engine must not depend on RTVI message names, JSON shapes, client SDKs, or
transport credentials.

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
| `send-text` | Append text context and optionally run the active agent |
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

1. raw VAD speech start or stop;
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

### Agent output and actual playout

Generated LLM text, text submitted to TTS, synthesized audio, scheduled audio,
and audio actually played are different facts. Conversation context and durable
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
CallEngine.Application
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

The Docker runner accepts one versioned JSON configuration through an explicit
`--config` path. The same schema permits pinned resource references or complete
inline definitions for a standalone process.

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
    adapter to ensure RTVI concepts have not leaked into `call_engine`.

## Acceptance criteria

- A current unmodified RTVI 2.x client completes text and audio conversations.
- A standard-only RTVI client works without consuming optional Vxpipe messages.
- Unsupported versions and malformed messages fail without activating or
  crashing a room.
- A second protocol adapter drives the same commands and domain events without
  modifying `call_engine`.
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
