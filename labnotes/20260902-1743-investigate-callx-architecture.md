# Callx architecture investigation

Date: 2026-09-02

## Goal

Inventory and understand the current `Callpipe.Callx` implementation in the
neighboring `callpipe` repository so Vxpipe can extract the runtime as a
standalone abstraction and eventually ship it as a Docker image configured by a
JSON file, including provider credentials and API keys.

This is a source investigation, not an extraction implementation. Statements
about current behavior are based on source and test contracts at callpipe commit
`2ea5ee0c503ef3690ad0d4e2139ee07bbbc985fd`. Recommendations describe work
needed in Vxpipe and are not claims that it already exists.

## Scope and method

Inspected:

- the 287-line public facade at `callpipe/lib/callpipe/callx.ex`;
- all 90 `.ex` files and 15,980 lines below
  `callpipe/lib/callpipe/callx/`;
- all 47 focused test files and 18,629 lines below
  `callpipe/test/callpipe/callx/`, containing 384 `test` declarations;
- the Callpipe application supervisor and all production callers of Callx;
- flow compilation, production/test room startup, HTTP and WebSocket ingress,
  CallRouter ownership, persistence, and test-call policy boundaries;
- relevant runtime configuration, dependencies, environment examples, design
  notes, milestone notes, and tryout harnesses; and
- the current Vxpipe umbrella skeleton.

Historical documents were treated as intent rather than authority. Current
source and tests win where a milestone document describes an earlier or proposed
slice.

## Baseline and worktree hygiene

- The `callpipe` worktree was clean before and after this read-only inspection.
- Vxpipe already had unrelated changes to `AGENTS.md`, `apps/`, and
  `labnotes/20260902-1725-add-umbrella-apps.md`. This investigation did not
  modify those paths.
- Vxpipe currently has empty generated `call_engine` and `gateway` applications,
  an umbrella `mix.exs`, and no JSON config loader, release config, Dockerfile,
  container entrypoint, or Callx implementation.
- Callx is currently an in-process OTP subsystem embedded in a Phoenix/Ecto
  monolith. It is not a separate Mix application, executable, release, or image.

## Executive conclusion

Callx is an event-driven call-room runtime. A room is the authoritative state
machine for participants, transport connections, AI capabilities, topic
subscriptions, transfers, tool invocations, media routing, and session
lifecycle. It has a real reusable kernel, but that kernel is mixed with Callpipe
database, workflow, routing, credential, provider, and web concerns.

The extraction is therefore not a directory copy. The portable core should move
into Vxpipe's `call_engine`; JSON decoding and network/container ingress belong
in `gateway`; Callpipe-owned persistence, credential lookup, flow compilation,
CallRouter coordination, and third-party API lookup must become explicit ports
or optional adapters.

The Docker/JSON goal needs a deliberately JSON-safe configuration contract. The
current runtime plan contains Elixir module atoms, structs, functions, PIDs, and
injected modules, none of which are portable JSON values. Adapter and participant
names must be resolved through closed string registries, secrets must be resolved
into private runtime state, and every public snapshot/event/log boundary must
redact them.

The most urgent findings before exposing Callx as a general-purpose image are:

1. Capability adapter state is returned by `get_room/1` and included in
   `capability_added` events. Rime and Grok adapter state retains options that
   include API keys. Literal JSON credentials would therefore be observable to
   callers and subscribers unless the public/private state boundary is changed.
2. Every published event is retained in the room forever. Audio events retain
   the complete PCM binary in memory, not only metadata. Ended rooms also remain
   supervised and registered with no delete/reaper API. Long calls or a
   long-lived container can grow memory without a bound.
3. `FlowRuntimeCompiler` emits `mcp_registry`, and both production and test
   starters pass its plan to `RoomBuilder`; `RoomBuilder` omits that key from
   `@room_attr_keys`, so the room loses the registry. The MCP acceptance tests
   invoke `Callx.create_room/1` directly and do not cover the starter/builder
   path. `tp_api_registry` is preserved.
4. `Room` directly calls Callpipe's `CallRouter` and test-call `ToolPolicy`.
   MCP, third-party APIs, persistence, and starters also depend on Ecto schemas,
   `Repo`, Tpx, workflows, and other monolith modules.
5. The per-room supervisor uses `:one_for_one`. A room-process crash will, by
   normal OTP child defaults, restart the `Room` alone while sibling dynamic
   supervisors and their workers survive. That can produce a fresh authoritative
   room state beside stale participant/connection/capability workers. This is a
   source-level failure-mode inference; the focused suite could not be executed
   in this checkout.
6. WebRTC signaling is present but transport audio is incomplete, and the
   Membrane live-mixer pipeline is explicitly a placeholder that counts frames
   without emitting mixed output.

## Runtime topology

Callpipe's application supervisor owns global names and room placement:

```text
Callpipe.Application
├── Registry Callpipe.Callx.RoomRegistry
├── Registry Callpipe.Callx.Telephony.TelnyxMediaRegistry
├── Registry Callpipe.Callx.CallRoomRegistry
├── Task.Supervisor Callpipe.Callx.SubscriberTaskSupervisor
└── DynamicSupervisor Callpipe.Callx.RoomsSupervisor
    └── Callpipe.Callx.RoomSupervisor (one per room)
        ├── DynamicSupervisor ParticipantSupervisor (per-room via tuple)
        │   └── ParticipantWorker ...
        ├── DynamicSupervisor ConnectionSupervisor (per-room via tuple)
        │   └── ConnectionWorker ...
        ├── DynamicSupervisor CapabilitySupervisor (per-room via tuple)
        │   └── CapabilityWorker ...
        ├── MCP.SessionCache
        └── Room
```

All per-room names use `RoomRegistry` via tuples such as
`{room_id, :participants}`. Dynamic children are started through their owning
supervisors and monitored by `Room`. Participant, connection, and capability
workers are temporary; the room converts a worker `:DOWN` into failed domain
state rather than crashing itself.

The room GenServer serializes authoritative mutations. Provider WebSockets and
async LLM/STT work can execute outside it, then publish outputs back. Several
routes remain synchronous, including deterministic adapters, hooks, participant
commands, direct media delivery, and opt-in synchronous subscribers such as
database persistence and local WAV recording. A slow synchronous boundary can
therefore delay the room mailbox and its default five-second public call timeout.

## Creation and lifecycle

The public creation path is:

```text
JSON flow definition in Callpipe database
  -> Workflows.FlowRuntimeCompiler
  -> Elixir runtime plan
  -> RuntimeStarter or TestCallStarter adds host/runtime data
  -> RoomBuilder expands participant-owned specs
  -> Callx.create_room starts RoomSupervisor
  -> participants/connections/capabilities are added
  -> Callx.activate_room
```

`Callx.create_room/1` normalizes only a closed set of atom/string keys, assigns a
room ID when absent, records a creation spec, and starts a child beneath
`RoomsSupervisor`. Repeating creation for the same ID is idempotent only when the
creation spec compares equal; a different spec returns `:room_id_conflict`.
Recursive MCP maps have credential-like keys removed before the creation spec is
stored. That sanitization is MCP-specific and does not sanitize capability or
connection configuration.

Room lifecycle is `created -> active -> ending -> ended`. `end_session/3` is
idempotent in `ending`/`ended`. End performs this ordered best-effort shutdown:

1. cancel the normal idle timer and mark `ending`;
2. publish `call_room_ending`;
3. disconnect every connection;
4. stop every capability;
5. stop every participant;
6. clear CallRouter ownership when configured;
7. cancel the test-call activity timer;
8. mark `ended` and publish `call_room_ended`; and
9. invoke `after_end_session` observer hooks.

The room process and its supervisor intentionally remain alive so callers can
inspect the final snapshot. There is no corresponding disposal operation or
retention policy. Normal operations reject an ended room with `:room_not_open`.

Rooms also end after `idle_timeout_ms` when no active participant has
`keeps_room_alive?`. Test rooms add maximum-turn and activity-idle limits.

## Public API and data model

`Callpipe.Callx` is a thin facade around the registered room GenServer. Its
public operations are:

- room: create, get, activate, update routing policy, and end session;
- participants: add, remove, mute/unmute, hold/resume, and commands;
- connections: add, connect, disconnect, signals, commands, provider events,
  and provider audio;
- capabilities: add, start, and stop;
- event bus: synchronous/asynchronous publish and subscribe/unsubscribe;
- orchestration: transfer a call, invoke a first-party tool, invoke MCP, invoke a
  third-party API tool, and collect provider/DTMF progress.

Synchronous facade calls default to 5,000 ms. `publish/4` accepts a custom
timeout. Missing registered processes are converted to `:room_not_found`.

The primary domain records are:

- `AudioFrame`: room, participant, connection, capability, topic, binary
  payload, audio format/sample rate/channel count, timestamp, sequence, and
  metadata;
- `Event`: room/topic/type, optional owner IDs, payload, timestamp, and metadata;
- `Participant`: identity/role/kind/module/config/PID, state, owned connection
  and capability IDs, publish/subscribe contracts, keepalive flag, and metadata;
- `Connection`: identity/participant/kind/adapter/PID, mode, media state,
  lifecycle state, and metadata;
- `Capability`: identity/participant/kind/adapter/PID, lifecycle state,
  publish/subscribe contracts, metadata, and private-looking but currently
  public `adapter_state`;
- `RoomState`: all room identity/lifecycle fields plus entity maps, handoffs,
  MCP/TpApi registries, tools, input collections, subscriptions, hooks,
  subscribers, media engine state, event history, and timers; and
- `ToolInvocation` and `InputCollection`: room-owned state machines for tools
  and DTMF collection.

`get_room/1` omits MCP/TpApi registries, hooks/subscribers, media-engine state,
and timers, but returns participant, connection, capability, handoff, tool,
input, subscription, and full event records without a serializer boundary.

## Topic bus, routing, and authority

Topics use exact strings and suffix wildcards. `*` matches everything and a
pattern such as `audio.*` matches its prefix; there is no implicit parent-topic
delivery. Participants and capabilities declare what they publish and subscribe
to. Room-owned checks reject undeclared publications and stamp authoritative
participant/capability IDs onto worker output so an adapter cannot spoof another
entity.

A committed publication runs in this order:

```text
before_publish hook (may edit/halt)
  -> generic hooks (may edit/halt)
  -> media engine / transport routing
  -> participant routing
  -> internal PID subscribers
  -> external module/function subscribers
  -> prepend to in-memory event history
  -> observer-only hooks
  -> test-call limit and activity checks
```

Internal PID subscribers receive `{:callx_event, event}`. External subscribers
default to asynchronous tasks under `SubscriberTaskSupervisor`, with a spawned
fallback; they can request synchronous delivery. Subscriber exceptions are
contained. Observer hooks exist for audio, partial/final transcripts, agent
turns, and tool-call boundaries. `before_publish` and generic hooks can mutate or
halt a publication; observer hook points cannot change committed state.

The direct media engine fans audio to connected connections owned by subscribed
participants. It excludes the source connection and normally excludes the source
participant. A participant can opt into self-events. Delivery errors mark the
target connection failed. Debug sampling can emit route-probe events.

Connection audio cannot claim another participant merely by changing an ID. A
cross-participant frame is accepted only when all bridge-fork conditions hold:

- the source connection is in `bridged_fork` / `source_both_tracks` state;
- a caller-channel route names that participant and topic;
- the room's track map approves it;
- any active handoff ID matches; and
- there is no duplicate active bidirectional audio source for the participant.

STT receives subscribed audio. LLM receives final/speaker-turn-finalized
transcripts only when the routing policy permits the source participant,
capability, input type, and expected dialogue turn. TTS receives subscribed text.
WebSocket STT and Jido LLM paths are asynchronous. A
`participant_turn_ended` event synthesizes a canonical generated transcript and
sends a private silence frame to STT to flush endpointing.

Mute and hold state suppress relevant audio. Routing policy can additionally
mute publications and constrain LLM participant/capability selection.

## Participants, connections, and capabilities

Participant modules own role-specific expansion. `RoomBuilder` asks each
participant module for runtime specs, then starts participant, connection, and
capability workers and performs requested connects/activation commands.

- `Agent` expands LLM/TTS/STT configuration, listens to selected participant
  transcripts, publishes scoped text/transcript/audio/turn topics, and does not
  keep the room alive.
- `MockHuman` builds deterministic or injected LLM/TTS/STT capability specs,
  publishes scoped topics, and normally keeps the room alive.
- `RealHumanRuntime` is shared by inbound/outbound Telnyx roles. It creates
  explicit or telecom connections, optional STT, Telnyx answer/fork activation,
  and role-specific subscriptions.
- `Visitor` is a thin browser participant with config-provided connections.
- `Debug` records transcripts and owns an optional live mixer; `RoomObserver`
  wraps it with broad topic subscriptions.
- `BusinessUser`, `CallManager`, and `Recorder` are currently thin passive role
  definitions rather than complete domain components.

`ParticipantWorker` owns role module state and synchronously dispatches events
and commands. `ConnectionWorker` owns transport adapter state and dynamically
checks optional adapter callbacks/arity; there is no connection-adapter
behaviour. `CapabilityWorker` starts provider state, routes sync/async input,
maintains LLM history, implements `__nospeak__`, validates output contracts, and
reports output back to the room. Async errors are retained in adapter state.

Defined behaviours are:

- `ParticipantBehaviour`: `init`, optional `configure`/`runtime_specs`, event,
  and command callbacks;
- `STT`: start stream, send audio, stop stream;
- `LLM`: respond to a turn and context;
- `TTS`: start stream, synthesize text, stop stream;
- `MediaEngine`: initialize and route audio;
- `Hook`: mutate/halt selected pre-events and observe committed events; and
- `Subscriber`: consume committed events.

## Providers and transports

`AdapterOptions` accepts atom/string maps or keyword lists, maps only a known set
of option names, and drops unknown string keys rather than creating atoms.

Speech-to-text:

- `Beep` detects deterministic synthetic PCM pulses for focused tests.
- `Tone` uses signal analysis for a deterministic tone-based live/test harness.
- `DeepgramFlux` is the descriptive alias for `Flux`.
- `Flux` uses Deepgram Flux through a Cloudflare Workers AI Gateway WebSocket,
  accepts an injectable synchronous transcriber, expects 16 kHz mono PCM, and
  emits partial/final transcript events. Credentials come from adapter options
  or `WORKERS_AI_GATEWAY_TOKEN`/`WORKERS_AI_TOKEN`; defaults include a fixed
  account/gateway route in source.
- `Grok` uses xAI's realtime transcription WebSocket, with key lookup from
  options, `XAI_API_KEY`, or `GROK_API_KEY`.

Text-to-speech:

- `Beep` produces deterministic PCM pulses.
- `Rime` defaults to a lazy persistent WebSocket and supports an injectable
  one-shot HTTP synthesizer. It emits 16 kHz PCM and turn-ended output and
  handles fragmented sample boundaries. Key/model/voice settings are taken from
  adapter options and `RIME_API_KEY`/`CALLPIPE_RIME_*` environment variables.
- `Grok` uses xAI's persistent speech WebSocket and emits audio plus turn-ended
  output. Key/voice/language/codec settings use options and
  `XAI_API_KEY`/`GROK_API_KEY`/`CALLPIPE_GROK_*` variables.

LLM:

- `JidoAI` converts Callx turns/history into Jido messages, calls Jido/ReqLLM,
  supports native tools, and loops through room-owned Callx/MCP/TpApi tool
  invocations. Model-visible schemas exclude private executor information.
- `JidoAI.Runner` is the injectable Jido execution boundary and currently refers
  to Callpipe's custom DeepSeek provider.
- `CurrentDatetime`, `EchoTool`, and `LookupBusinessHours` are native example or
  first-party Jido actions. Business-hours lookup is static, not a persistence
  integration.

Transports:

- Telnyx can dial outbound, optionally answer inbound calls, hang up, play media
  with marks, clear playback, bridge calls, and start a media fork. Its client is
  injectable but defaults to `Callpipe.Telnyx.Client`. Outbound audio is sent to
  an injected sink or the active Telnyx media socket. Absence of a socket is
  treated as a successful drop, which can hide media misconfiguration.
- WebRTC owns offer/answer/ICE signaling through `ExWebRTC` and supports injected
  signaling/media handlers. Without an injected media sink, `send_audio` is a
  no-op; peer lifecycle messages sent to `ConnectionWorker` are not handled as a
  complete track/media bridge. The signaling layer is ahead of media delivery.
- `TelnyxMediaCodec` supports only L16. It converts provider big-endian PCM to
  internal signed 16-bit little-endian PCM, performs the inverse on output, and
  splits dual-channel provider audio into participant-scoped frames using
  approved route metadata.
- `TelnyxMediaStream` maps Telnyx stream/call-control IDs to the Phoenix
  WebSocket process and sends provider media, clear, and mark JSON messages.
- `TelnyxMediaToken` signs time-limited media query fields using HMAC and the
  endpoint secret. The default TTL is 30 minutes; route parameters themselves
  are not part of the signed payload.

## Transfers, DTMF, and tools

`ToolInvocation` is a room-owned lifecycle with
`started -> waiting -> completed|failed`. Sources can be LLM, DTMF, system, or
workflow. A tool reference can be a Callx module or a typed MCP/TpApi reference.
Event payloads deliberately omit executor functions and private runtime terms.

First-party tools are:

- `transfer_call`: Jido action that requests transfer resolution;
- `collect_input`: Jido action that starts DTMF collection;
- `hangup_call`: stable schema/reference handled by the room; and
- `update_collected_data`: validates configured field names/types, publishes
  collection progress, annotates sensitive retention, and reports required-field
  completion.

Only DTMF input collection is implemented. It supports a maximum digit count,
terminator, overall timeout, and inter-digit timeout, with one active collection
per connection. Provider DTMF is offered to an active handoff first, then input
collection, then participant-configured DTMF triggers.

`TransferResolver` accepts a direct runtime target or resolves a configured
intent, lazily materializes its participant/connection, and selects one of:

- `participant_transfer`: room-local switch completed in process;
- `call_leg_patch`: provider-backed patch of the existing call leg; or
- `call_leg_replacement`: provider-backed replacement leg.

`HandoffSequence` is a pure transition function. A target answers, optional
whisper audio plays and acknowledges via a mark, optional DTMF accepts/rejects,
then Telnyx bridge and media fork establish a completed handoff. Rejection,
timeout, provider failure, or hangup follow terminal failure paths. The tool
invocation stays `waiting` until the handoff reaches a terminal state. Old or
requesting participants are removed according to the configured disposition.

## MCP runtime

The MCP design separates model-visible schema from private transport and
credential data:

- `ServerConfig` describes enabled Streamable HTTP servers;
- `Binding` associates a server/credential connection with a flow node and tool
  grants;
- `ToolDescriptor` keeps private binding/server/schema data and emits a safe
  model-facing tool schema;
- `Registry` validates servers, bindings, grants, disabled state, names, and
  exposed-name collisions, and builds private lookup maps plus per-agent model
  maps;
- `ToolProxy` fails closed through grant, enabled-state, descriptor, JSON-schema,
  runtime-policy, URL-safety, credential, and timeout checks;
- `Runtime` injects configured credential resolver, remote executor, policy, URL
  policy, and timeout settings;
- `SessionCache` is per room and stores MCP session IDs/Last-Event-ID state,
  attempting best-effort remote termination during process termination;
- `CredentialResolver` loads a Callpipe Tpx connection/workspace through
  Ecto/Repo and returns an authenticated `Req.Request` without putting raw
  credentials in tool results;
- `RuntimePolicy` loads the current workspace MCP-server record and requires an
  explicit allowlist for sensitive tools while allowing non-sensitive tools by
  default; and
- `RemoteExecutor` delegates protocol calls to Callpipe's MCP client, initializes
  sessions, consults the room cache, and validates output when a schema exists.

This subsystem has good fail-closed and model-boundary concepts, but the default
credential, policy, and execution implementations are Callpipe infrastructure,
not standalone engine code. Their behaviours/contracts should be made explicit
and injected by Vxpipe/Callpipe adapters.

## Third-party API tools

The TpApi subsystem parallels MCP at a smaller scale:

- `ToolDescriptor` carries connection/provider/catalog identity and safe
  model-facing schema;
- `Registry` compiles flow links, grants, and catalog snapshots into descriptor
  lookup and per-agent schemas, with exposed names normalized as
  `service__tool`;
- `Runtime` supplies injectable connection and provider resolvers; and
- `ToolProxy` checks the grant, loads the live Tpx connection from Repo, resolves
  a provider through `ProviderRegistry`, executes `execute_tool/4`, and
  normalizes provider errors.

The default proxy is tightly coupled to Callpipe Ecto/Tpx modules. Registry
validation is less defensive than MCP and includes `Map.fetch!` paths that can
raise for malformed internal input. In test calls, Callpipe's tool policy mocks
mutating or unknown-side-effect tools and permits read-only tools to run live.

## Persistence, traces, recordings, and evals

`CallPersistence` is an 841-line synchronous subscriber coupled to Callpipe
Ecto schemas and Repo. It persists transcripts, agent turns, tools,
transfer/handoff declarations, participant state, collected data, and room end.
It uses idempotency keys, row locks, and transactions to join call turns/events.
Sensitive collected values carry expiry metadata and avoid evidence retention.
Room end can enqueue a goal-fact job. This belongs in a Callpipe host adapter,
not the standalone engine.

`JsonlTraceWriter` optionally creates a local directory and appends one
sanitized JSON line per event. `Trace.Event` converts structs, PIDs, references,
functions, and binaries into serializable forms, records audio byte counts
instead of audio payloads, and recursively redacts credential-like keys and
headers. This redaction is only at the trace boundary; it does not make room
state or arbitrary subscribers safe.

`LocalWavRecorder` writes local per-room/topic WAV files for signed 16-bit
little-endian PCM or compatible WAV input and rewrites headers after each append.
It is explicitly a local debugging facility. `EvalCollector` only emits a room
end notification. `Evals.Runner` loads a local JSONL path and deterministically
checks expected event types/events/order, transcripts, and audio-frame counts.
Its field is named `trace_artifact_url`, but current code treats it as a local
filesystem path rather than fetching a URL.

## Callpipe host integration outside the Callx directory

These production pieces are part of Callx's effective system boundary even
though they are not below `lib/callpipe/callx/`:

- `Callpipe.Application`: global registries, task supervisor, room supervisor,
  and separate tryout supervisors;
- `Callpipe.CallRouter`: cluster node placement, durable/test ownership, and
  internal forwarding;
- `Callpipe.Workflows.FlowRuntimeCompiler`: converts saved flow-editor JSON into
  participant-owned Callx plans, tool schemas, MCP/TpApi registries, transfers,
  variables, knowledge, routing graph/policy, and test configuration;
- `Callpipe.Workflows.TestCalls`: test-session orchestration;
- `TestCalls.EventProjection`: projects Callx events into test-call state;
- `TestCalls.RoomLifecycleSubscriber`: synchronizes room lifecycle to a durable
  test session;
- `TestCalls.ToolPolicy`: mocks unsafe test-call tools;
- `CallpipeWeb.InternalCallxController` and router routes: signed internal setup,
  Telnyx webhook, test signaling, and test audio endpoints;
- `Callpipe.Callx.InternalIngress`: parameter validation/dispatch behind those
  endpoints, including base64 audio and whitelisted formats without dynamic atom
  creation;
- `CallpipeWeb.Telnyx.MediaStreamSocket`: validates the signed query, registers
  the socket, decodes provider frames/channel routes, passes provider audio/events
  to Callx, and emits sampled timing/errors;
- `CallpipeWeb.Workspace.FlowTestCallChannel`: browser test-call control and
  signaling;
- `CallpipeWeb.Tryouts.CallxDebug.Channel`: tryout debug control; and
- `Callpipe.Tryouts.Callx.Playground` plus `MediaLab`, `MediaLab.Tones`, and
  `MediaLab.VirtualPhone`: synthetic/custom/Telnyx/virtual development harnesses.

`RuntimeStarter` itself loads durable `Call`, `CallLeg`, and `FlowVersion` rows,
compiles the flow, injects an inbound Telnyx connection, builds/activates the
room, registers routing ownership, and forwards webhooks. `TestCallStarter`
loads test context, compiles test mode, injects lifecycle/trace/WAV subscribers
and WebRTC options, builds/activates the room, and asynchronously kicks off a
hidden initial agent turn.

## Flow compiler behavior

The compiler currently understands saved flow definitions, not a standalone
Vxpipe schema. It emits:

- production inbound Telnyx callers with Flux STT;
- browser test callers with WebRTC;
- AI test callers with `MockHuman`, Jido, and Rime;
- agent and human participant specs with role-owned connections/capabilities;
- current-datetime, hangup, update-data, MCP, and TpApi tools;
- transfer targets and DTMF triggers;
- variables, knowledge snapshots, shared context, routing graph, and initial
  routing policy; and
- test-call limits and safe/mock tool policy.

Only the `rime` configured voice service is accepted. The output is an Elixir
runtime plan containing atoms, module values, structs, and test-only injected
terms. It cannot be serialized as the proposed generic Docker contract without a
separate config compiler.

## Exhaustive Callx module catalog

Every current Callx source file is listed below. Paths are relative to
`callpipe/lib/callpipe/`.

### Public facade

| File/module | Responsibility |
| --- | --- |
| `callx.ex` — `Callpipe.Callx` | Public room/entity/event/tool facade, key normalization, idempotent creation, and MCP creation-spec sanitization. |

### Kernel, supervision, ingress, and orchestration

| File/module | Responsibility |
| --- | --- |
| `callx/adapter_options.ex` — `AdapterOptions` | Closed conversion/access/merge helpers for atom or string adapter options. |
| `callx/audio_frame.ex` — `AudioFrame` | Normalized audio envelope and ownership/format metadata. |
| `callx/capability.ex` — `Capability` | Capability runtime record. |
| `callx/capability_supervisor.ex` — `CapabilitySupervisor` | Per-room capability supervisor naming and child startup. |
| `callx/capability_worker.ex` — `CapabilityWorker` | Provider lifecycle, sync/async STT/LLM/TTS dispatch, history, validation, and output publication. |
| `callx/connection.ex` — `Connection` | Transport connection runtime record. |
| `callx/connection_supervisor.ex` — `ConnectionSupervisor` | Per-room connection supervisor naming and child startup. |
| `callx/connection_worker.ex` — `ConnectionWorker` | Dynamic transport callback dispatch, state snapshots, provider IDs, signals, commands, and audio. |
| `callx/evals.ex` — `Evals` | Public evaluation runner facade. |
| `callx/evals/runner.ex` — `Evals.Runner` | Deterministic checks over local JSONL traces. |
| `callx/event.ex` — `Event` | Normalized topic event envelope. |
| `callx/handoff_sequence.ex` — `HandoffSequence` | Pure provider-assisted transfer/handoff state machine. |
| `callx/hook.ex` — `Hook` | Hook behaviour and supported hook points. |
| `callx/input_collection.ex` — `InputCollection` | DTMF collection state and safe event payload. |
| `callx/internal_ingress.ex` — `InternalIngress` | Validates and dispatches internal setup/webhook/test signal/audio requests. |
| `callx/llm.ex` — `LLM` | LLM adapter behaviour. |
| `callx/media_engine.ex` — `MediaEngine` | Media routing behaviour. |
| `callx/media_engines/direct.ex` — `MediaEngines.Direct` | Default no-mix direct audio target selection. |
| `callx/participant.ex` — `Participant` | Participant runtime record. |
| `callx/participant_behaviour.ex` — `ParticipantBehaviour` | Participant initialization, expansion, event, and command callbacks. |
| `callx/participant_supervisor.ex` — `ParticipantSupervisor` | Per-room participant supervisor naming and child startup. |
| `callx/participant_worker.ex` — `ParticipantWorker` | Participant module state and synchronous event/command execution. |
| `callx/room.ex` — `Room` | 4,640-line authoritative GenServer for nearly all runtime state machines and routing. |
| `callx/room_builder.ex` — `RoomBuilder` | Expands participant-owned specs, builds room entities, connects, and activates commands. |
| `callx/room_state.ex` — `RoomState` | Complete internal state record and defaults. |
| `callx/room_supervisor.ex` — `RoomSupervisor` | Per-room static supervision tree. |
| `callx/runtime_starter.ex` — `RuntimeStarter` | Callpipe durable call/flow/leg to production Callx room integration. |
| `callx/stt.ex` — `STT` | Streaming speech-to-text behaviour. |
| `callx/subscriber.ex` — `Subscriber` | External event subscriber behaviour. |
| `callx/test_call_starter.ex` — `TestCallStarter` | Callpipe test session to browser/AI Callx room integration. |
| `callx/tool_invocation.ex` — `ToolInvocation` | Tool lifecycle, typed references, and safe payload projection. |
| `callx/transfer_resolver.ex` — `TransferResolver` | Direct/intent target resolution and lazy runtime materialization. |
| `callx/tts.ex` — `TTS` | Streaming text-to-speech behaviour. |

### Provider and transport adapters

| File/module | Responsibility |
| --- | --- |
| `callx/adapters/llm/jido_ai.ex` — `Adapters.LLM.JidoAI` and `JidoAI.Runner` | Jido conversation/tool loop and injectable ReqLLM runner. Two top-level modules currently share this file. |
| `callx/adapters/llm/jido_ai/tools/current_datetime.ex` — `CurrentDatetime` | Timezone-aware current date/time Jido action. |
| `callx/adapters/llm/jido_ai/tools/echo_tool.ex` — `EchoTool` | Echo/smoke-test Jido action. |
| `callx/adapters/llm/jido_ai/tools/lookup_business_hours.ex` — `LookupBusinessHours` | Static business-hours Jido action. |
| `callx/adapters/stt/beep.ex` — `Adapters.STT.Beep` | Synthetic pulse STT. |
| `callx/adapters/stt/deepgram_flux.ex` — `Adapters.STT.DeepgramFlux` | Descriptive alias delegating to Flux. |
| `callx/adapters/stt/flux.ex` — `Adapters.STT.Flux` | Deepgram Flux/Cloudflare WebSocket or injected transcriber. |
| `callx/adapters/stt/grok.ex` — `Adapters.STT.Grok` | xAI realtime transcription WebSocket. |
| `callx/adapters/stt/tone.ex` — `Adapters.STT.Tone` | Deterministic tone decoding and endpointing. |
| `callx/adapters/transport/telephony/telnyx.ex` — `Adapters.Transport.Telephony.Telnyx` | Telnyx call control, media commands, bridge/fork, and provider event normalization. |
| `callx/adapters/transport/webrtc.ex` — `Adapters.Transport.WebRTC` | WebRTC transport state, signaling, and injectable media/signal handlers. |
| `callx/adapters/transport/webrtc/peer_connection.ex` — `WebRTC.PeerConnection` | ExWebRTC peer process wrapper. |
| `callx/adapters/tts/beep.ex` — `Adapters.TTS.Beep` | Synthetic pulse TTS. |
| `callx/adapters/tts/grok.ex` — `Adapters.TTS.Grok` | xAI streaming speech WebSocket. |
| `callx/adapters/tts/rime.ex` — `Adapters.TTS.Rime` | Rime streaming WebSocket and compatibility HTTP synthesis. |

The Flux, Grok STT, Grok TTS, and Rime files also define nested
`WebSocketClient` modules in the same source file. Vxpipe's one-top-level-module-
per-file rule means these and `JidoAI.Runner` must be split during extraction.

### Participant roles

| File/module | Responsibility |
| --- | --- |
| `callx/participants/agent.ex` — `Participants.Agent` | AI-agent identity and LLM/TTS/STT runtime expansion. |
| `callx/participants/business_user.ex` — `Participants.BusinessUser` | Thin business-user role. |
| `callx/participants/call_manager.ex` — `Participants.CallManager` | Thin call-manager role. |
| `callx/participants/config.ex` — `Participants.Config` | Shared participant config key/list/map access and topic helpers. |
| `callx/participants/debug.ex` — `Participants.Debug` | Transcript observation and live-mixer commands/state. |
| `callx/participants/debug/live_mixer.ex` — `Debug.LiveMixer` | Mixer/sink lifecycle, frame filtering, and injectable pipeline boundary. |
| `callx/participants/debug/live_mixer/membrane_pipeline.ex` — `MembranePipeline` | Placeholder Membrane process that counts input and emits no mixed audio. |
| `callx/participants/mock_human.ex` — `Participants.MockHuman` | Synthetic human and optional AI capability expansion. |
| `callx/participants/real_human_runtime.ex` — `RealHumanRuntime` | Shared Telnyx human configuration/runtime expansion and activation. |
| `callx/participants/recorder.ex` — `Participants.Recorder` | Thin recorder role. |
| `callx/participants/room_observer.ex` — `Participants.RoomObserver` | Broad-topic debug observer wrapper. |
| `callx/participants/telnyx_inbound_human.ex` — `TelnyxInboundHuman` | Inbound visitor identity delegating to real-human runtime. |
| `callx/participants/telnyx_inbound_mock_human.ex` — `TelnyxInboundMockHuman` | Inbound Telnyx-shaped mock delegating to mock-human runtime. |
| `callx/participants/telnyx_outbound_human.ex` — `TelnyxOutboundHuman` | Outbound business-user identity delegating to real-human runtime. |
| `callx/participants/telnyx_outbound_mock_human.ex` — `TelnyxOutboundMockHuman` | Outbound Telnyx-shaped mock delegating to mock-human runtime. |
| `callx/participants/visitor.ex` — `Participants.Visitor` | Thin browser visitor with config-owned connections. |

### MCP

| File/module | Responsibility |
| --- | --- |
| `callx/mcp/binding.ex` — `MCP.Binding` | Flow/node/server/connection binding and grants. |
| `callx/mcp/credential_resolver.ex` — `MCP.CredentialResolver` | Callpipe Repo/Tpx credential resolution into authenticated requests. |
| `callx/mcp/registry.ex` — `MCP.Registry` | Validated private and model-visible MCP lookup maps. |
| `callx/mcp/remote_executor.ex` — `MCP.RemoteExecutor` | Callpipe MCP client/session execution boundary. |
| `callx/mcp/runtime.ex` — `MCP.Runtime` | Runtime dependency/config assembly. |
| `callx/mcp/runtime_policy.ex` — `MCP.RuntimePolicy` | Live server/sensitivity authorization through Callpipe Repo. |
| `callx/mcp/server_config.ex` — `MCP.ServerConfig` | Streamable HTTP server configuration. |
| `callx/mcp/session_cache.ex` — `MCP.SessionCache` | Per-room session and Last-Event-ID cache/cleanup. |
| `callx/mcp/tool_descriptor.ex` — `MCP.ToolDescriptor` | Private descriptor plus safe model schema. |
| `callx/mcp/tool_proxy.ex` — `MCP.ToolProxy` | Fail-closed validation, policy, SSRF, credential, timeout, and invocation pipeline. |

### Third-party APIs

| File/module | Responsibility |
| --- | --- |
| `callx/tp_apis/registry.ex` — `TpApis.Registry` | Links/grants/catalog snapshot compilation and per-agent schemas. |
| `callx/tp_apis/runtime.ex` — `TpApis.Runtime` | Resolver dependency assembly. |
| `callx/tp_apis/tool_descriptor.ex` — `TpApis.ToolDescriptor` | Provider tool identity and model-facing schema. |
| `callx/tp_apis/tool_proxy.ex` — `TpApis.ToolProxy` | Callpipe Repo/Tpx/provider execution boundary. |

### First-party tools

| File/module | Responsibility |
| --- | --- |
| `callx/tools/collect_input.ex` — `Tools.CollectInput` | Jido action/schema for DTMF collection. |
| `callx/tools/hangup.ex` — `Tools.Hangup` | Stable hangup schema/reference. |
| `callx/tools/transfer_call.ex` — `Tools.TransferCall` | Jido action/schema for transfer requests. |
| `callx/tools/update_collected_data.ex` — `Tools.UpdateCollectedData` | Stable collected-field update schema/reference. |

### Subscribers and trace

| File/module | Responsibility |
| --- | --- |
| `callx/subscribers/call_persistence.ex` — `Subscribers.CallPersistence` | Callpipe database timeline/data persistence and goal-fact enqueue. |
| `callx/subscribers/eval_collector.ex` — `Subscribers.EvalCollector` | End-of-room evaluation notification stub. |
| `callx/subscribers/jsonl_trace_writer.ex` — `Subscribers.JsonlTraceWriter` | Local sanitized JSONL event trace writer. |
| `callx/subscribers/local_wav_recorder.ex` — `Subscribers.LocalWavRecorder` | Local per-topic WAV debug recorder. |
| `callx/trace/event.ex` — `Trace.Event` | Recursive event serialization and secret/binary redaction. |

### Telnyx media helpers

| File/module | Responsibility |
| --- | --- |
| `callx/telephony/telnyx_media_codec.ex` — `TelnyxMediaCodec` | L16 endian conversion and approved dual-track splitting. |
| `callx/telephony/telnyx_media_stream.ex` — `TelnyxMediaStream` | Registered media socket lookup and outbound Telnyx JSON commands. |
| `callx/telephony/telnyx_media_token.ex` — `TelnyxMediaToken` | Expiring HMAC query token issue/verification. |

## Focused test inventory and owned contracts

All focused files were inspected. They divide into these contract groups:

- core room/entity/event behavior:
  `room_api_test.exs`, `room_builder_test.exs`,
  `room_participant_workers_test.exs`, `room_capability_routing_test.exs`,
  `room_capability_failures_test.exs`, `room_connection_failures_test.exs`,
  `room_media_routing_test.exs`, `room_hooks_test.exs`,
  `room_session_lifecycle_test.exs`, `room_debug_participant_test.exs`, and
  `call_room_registry_test.exs`;
- providers/media/transports:
  `beep_adapters_test.exs`, `tone_stt_test.exs`,
  `provider_adapters_test.exs`, `provider_adapters_jido_mcp_test.exs`,
  `transport_adapters_test.exs`, `telnyx_media_codec_test.exs`,
  `telnyx_media_stream_test.exs`, `telnyx_media_token_test.exs`,
  `debug_live_mixer_test.exs`, and `fork_split_guardrail_test.exs`;
- transfer/input/tool behavior:
  `handoff_sequence_test.exs`, `input_collection_test.exs`,
  `dtmf_router_test.exs`, `transfer_resolver_test.exs`,
  `room_transfer_test.exs`, `participant_transfer_test.exs`,
  `call_leg_replacement_test.exs`, `tool_invocation_test.exs`,
  `mcp_tool_invocation_test.exs`, and `tp_api_tool_invocation_test.exs`;
- MCP:
  `mcp/credential_resolver_test.exs`, `mcp/registry_test.exs`,
  `mcp/remote_executor_test.exs`, `mcp/room_session_lifecycle_test.exs`,
  `mcp/room_state_test.exs`, `mcp/runtime_acceptance_test.exs`,
  `mcp/runtime_policy_test.exs`, `mcp/runtime_structs_test.exs`,
  `mcp/runtime_test.exs`, `mcp/session_cache_test.exs`, and
  `mcp/tool_proxy_test.exs`;
- host integration:
  `runtime_starter_test.exs`, `test_call_starter_test.exs`, and
  `call_persistence_subscriber_test.exs`; and
- diagnostics:
  `subscribers/local_wav_recorder_test.exs` and `trace_eval_test.exs`.

Relevant cross-boundary tests also exist under CallRouter, workflows, Phoenix
controllers/channels/sockets, Chatx, tryouts, and test support. External-service
interoperability is generally injected or kept outside the default unit path;
the focused tests emphasize project-owned boundaries and failure handling.

## Dependencies and environment configuration

Directly visible Callx dependencies include:

- `jido_ai ~> 2.1` and Req/ReqLLM for LLM execution;
- `websockex ~> 0.5.1` for provider WebSockets;
- `membrane_core ~> 1.3`, `membrane_audio_mix_plugin ~> 0.16.3`,
  `membrane_webrtc_plugin ~> 0.26.4`, `membrane_opus_plugin ~> 0.20.7`, and
  `membrane_opus_format ~> 0.3.0` for media/WebRTC work;
- Phoenix/WebSock for HTTP/WebSocket ingress;
- Ecto/Postgres, Oban, Redix, and Callpipe schemas/services at host boundaries;
  and
- Jason/JSV-style validation and standard OTP facilities throughout.

Callpipe currently configures LLM model aliases and provider keys in
`config/runtime.exs`. Adapters additionally read process environment directly.
The effective variables include `CALLX_LLM_API_KEY`, `CALLX_LLM_MODEL`,
`CALLX_LLM_CAPABLE_MODEL`, `DEEPSEEK_API_KEY`, common OpenAI/Anthropic keys,
`WORKERS_AI_GATEWAY_TOKEN`, `WORKERS_AI_TOKEN`, `RIME_API_KEY`, `XAI_API_KEY`,
`GROK_API_KEY`, `CALLPIPE_RIME_*`, `CALLPIPE_GROK_*`, Telnyx settings, and
optional Callx trace/recording directories.

This scattered lookup order is unsuitable for a deterministic JSON-configured
image. Provider modules should receive resolved configuration explicitly; they
should not independently fall back to application env and process env.

## Extraction boundary for Vxpipe

Recommended ownership, following the umbrella's SRP rules:

### `call_engine`: portable runtime

Move and rename the public facade, domain records, behaviours, room supervision,
workers, topic authorization/routing, direct media engine, room builder, input
collection, tool lifecycle, transfer state machine/resolver, portable
participants, portable first-party tools, trace normalization, and deterministic
test adapters.

Split the 4,640-line `Room` by cohesive responsibility while preserving one
authoritative room process. Candidate pure/cohesive components are publication
authorization/routing, media routing, tool execution, input/DTMF, transfer
orchestration, and session shutdown. The room should coordinate them rather than
remain the implementation site for every callback family.

### `gateway`: executable and container boundary

Own JSON reading, schema/version validation, closed name registries, secret
resolution, release startup, health/readiness, HTTP/WebSocket ingress, and the
decision to start one configured room or serve multiple runtime requests. It may
depend on `call_engine`; the engine must not depend on `gateway`.

### Explicit ports/adapters

Define engine-facing contracts for:

- room placement/ownership cleanup, replacing direct `CallRouter` calls;
- persistence/event sinks, keeping Ecto schemas out of the engine;
- LLM execution/model catalog;
- transport call control and socket registration;
- MCP credential resolution, authorization policy, protocol execution, and
  session persistence;
- third-party connection/provider resolution and tool execution; and
- wall clock/ID generation where deterministic tests need them.

Callpipe can implement these ports in its own integration layer. Vxpipe can ship
standalone implementations that use only the JSON/runtime environment.

Provider adapters can begin in `call_engine` if they are genuinely part of the
runtime product, but their optional dependencies and configuration should remain
isolated. If their dependency weight or release cadence diverges, a later
adapter application is a cohesive split; a generic `Utils`/`Services` app is not.

## JSON configuration contract needed for Docker

“Any configuration” should mean every supported runtime option has a JSON
representation, not that arbitrary Elixir terms or arbitrary module names are
accepted. The loader should compile a declarative, versioned document into the
internal runtime structs.

Recommended boot pipeline:

```text
config file path or stdin
  -> bounded JSON decode
  -> versioned schema validation with path-specific errors
  -> closed string-name resolution
  -> secret reference resolution
  -> semantic/cross-reference validation
  -> private runtime plan compilation
  -> supervised gateway/engine start
  -> readiness only after required providers are initialized
```

The schema should separate:

- process/server settings: bind address, ports, logging, health endpoints, and
  shutdown/retention policy;
- provider profiles: adapter name, model/voice/codec/timeouts, endpoint, and
  secret references;
- room templates or startup rooms: participants, connections, capabilities,
  topics, routing policy, transfers, tools, hooks selected from a safe registry,
  and limits; and
- host integrations: persistence/event sinks, MCP servers/grants, third-party
  tools, and cluster/ownership mode.

A representative shape, not a committed schema, is:

```json
{
  "version": 1,
  "server": {
    "http": {"host": "0.0.0.0", "port": 4200},
    "ended_room_ttl_ms": 60000,
    "max_events_per_room": 10000,
    "retain_audio_events": false
  },
  "providers": {
    "transcriber": {
      "adapter": "deepgram_flux",
      "api_key": {"source": "env", "name": "DEEPGRAM_API_KEY"},
      "sample_rate": 16000
    },
    "voice": {
      "adapter": "rime",
      "api_key": {"source": "file", "path": "/run/secrets/rime_api_key"},
      "speaker": "astra"
    }
  },
  "rooms": [
    {
      "id": "support-line",
      "participants": [],
      "routing_policy": {},
      "idle_timeout_ms": 30000
    }
  ]
}
```

Literal secret values can be supported because the requested use case includes
API keys in the file, but they should be an explicit form such as
`{"source":"literal","value":"..."}` and documented as less safe than env or
mounted secret files. The loader should reject world-readable secret files when
the platform permits checking, never echo values in validation errors, keep them
out of creation specs and equality comparisons, and erase them from public
domain structs/events. A config file should normally be mounted read-only rather
than baked into an image layer.

Closed registries should map values such as `"agent"`, `"telnyx_inbound"`,
`"deepgram_flux"`, `"rime"`, `"jido_ai"`, and `"direct"` to compiled modules.
Unknown names must be validation errors. JSON input must never call
`String.to_atom/1`, accept BEAM module names, functions, PIDs, or raw structs.

The contract also needs a clear process model:

- one-shot mode: boot configured room(s), exit non-zero on config/start failure,
  and terminate when all rooms end; or
- daemon mode: boot the gateway, use config as defaults/templates, accept room
  creation over an authenticated API, and reap ended rooms.

The current Callpipe behavior most closely resembles a daemon. For a reusable
Docker image, daemon mode with an optional `run-once` command would cover both
operational models without overloading room config with server concerns.

## Gaps and risks to resolve before extraction is production-ready

### P0: security and correctness

- Define private adapter state and public snapshots. Never return adapter opts,
  authenticated requests, headers, credentials, provider sockets, functions, or
  PIDs from the public engine API.
- Sanitize event payloads before any subscriber receives them, not only when
  writing JSONL. `capability_added` must use a public capability projection.
- Add a red test covering a literal provider key through config -> room ->
  snapshot/events/subscriber/trace/logs before building the JSON loader.
- Preserve `mcp_registry` through `RoomBuilder` and add a starter/builder
  acceptance test; current MCP tests bypass the broken boundary.
- Bound event retention and do not retain raw audio by default. Provide a
  streaming event sink and explicit debug opt-in for payload retention.
- Add explicit room disposal/TTL and define restart semantics. Consider
  `:rest_for_one` ordering or make a room crash terminate/rebuild the entire
  per-room subtree from a durable plan; do not allow surviving workers beside a
  reset authority process.

### P1: abstraction and operability

- Remove direct Callpipe aliases from core (`CallRouter`, workflow tool policy,
  Repo/Ecto/Tpx/MCP client/custom DeepSeek/provider registry).
- Introduce one versioned JSON schema and semantic compiler with useful JSON
  pointer/path errors.
- Centralize secret/config resolution; remove direct `System.get_env/1` reads
  from provider implementations.
- Decide container daemon/run-once behavior, signals, graceful drain, readiness,
  exit codes, config reload policy, and ended-room retention.
- Make backpressure/queue/timeout behavior explicit around sync hooks,
  subscribers, media connections, and capability work.
- Define and enforce a transport behaviour instead of callback introspection.
- Make MCP/TpApi resolver/executor contracts standalone and validate both
  registries equally defensively.

### P2: incomplete or local-only features

- Complete WebRTC inbound/outbound media track integration.
- Replace the placeholder Membrane mixer with an actual pipeline or remove it
  from the supported product contract until implemented.
- Decide whether local WAV/JSONL/eval facilities are supported container
  features; if so, define volumes, quotas, rotation, and artifact sinks.
- Replace fixed/default provider routes in source with validated configuration.
- Split multi-module files to satisfy Vxpipe project rules.

## Suggested red-green extraction checkpoints

Each is intended to leave the umbrella usable and preserve externally observable
behavior:

1. Public/private state boundary: tests first for secret-free snapshots and
   events, then public projections.
2. Portable room kernel: facade, structs, supervision, deterministic adapters,
   and the focused room API/routing/lifecycle tests under `call_engine`.
3. Room lifecycle/resource bounds: tests for audio retention policy, event cap,
   disposal, and whole-subtree crash recovery.
4. Participant/capability/connection ports: move behaviours/workers and add a
   formal transport behaviour.
5. Transfers, DTMF, and first-party tools: port pure state machines and their
   focused tests.
6. MCP/TpApi abstractions: port registries/proxies against injected fake ports;
   keep Callpipe Repo/Tpx implementations outside Vxpipe.
7. Versioned JSON compiler: red tests for valid config, unknown names, invalid
   cross-references, no atom creation, secret redaction, and MCP propagation.
8. Gateway/release/image: boot from mounted JSON, readiness, graceful shutdown,
   run-once/daemon semantics, and an image smoke test with deterministic
   adapters.
9. Optional real providers/transports: Rime/Deepgram/xAI/Telnyx/WebRTC integration
   tests in an explicitly tagged network lane.

## Source documents consulted

- `docs/callx-notes.md`
- `docs/milestone-config-callx.md`
- `docs/milestone-per-callx.md`
- `docs/milestone-common-tools.md`
- `docs/milestone-flow-tools.md`
- `docs/milestone-mcp.md`
- `docs/milestone-tool-event-safety.md`
- `docs/milestone-flow-editor-test-call-audio.md`
- `docs/milestone-testchat.md`
- `docs/specs/call-room.md`
- `docs/specs/call-transfers.md`

The documents explain the intended staged architecture and are useful history.
Some explicitly describe deferred or placeholder media work, so current source
and tests remain the extraction contract.

## Verification evidence and barriers

Static evidence gathered:

- enumerated every Callx source and focused test file with `rg`;
- traced supervision, creation, publication, end-session, tool, transfer,
  provider, persistence, and ingress call paths in current source;
- cross-checked the public facade and structs against focused tests;
- traced `mcp_registry` from `FlowRuntimeCompiler` through both starters into
  `RoomBuilder` and confirmed the builder's allowlist omits it;
- traced Rime/Grok key resolution into capability adapter state, then that state
  into `Room.capabilities`, `capability_added`, and `public_state`;
- traced audio frames into `Event.payload`, then every committed event into the
  unbounded `RoomState.events` list; and
- inspected the Vxpipe skeleton and confirmed no runtime/config/image work exists
  yet.

Attempted from the Callpipe root:

```shell
mix test test/callpipe/callx
```

The command stopped before compiling or running tests because this checkout does
not have multiple dependencies available (`jido_ai`, `websockex`, Membrane
packages, Oban, Redix, bcrypt, and others), and the `decimal` lock did not match
the current dependency declaration. No dependency fetch or lockfile mutation was
performed for this documentation-only investigation.

The final Vxpipe verification for this checkpoint is Markdown inspection,
source/catalog count reconciliation, `git diff --check` on this note, and a final
worktree/diff review. The full Vxpipe build remains the appropriate completion
gate when the extraction starts changing code or dependencies.
