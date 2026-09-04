# STT capability vertical slice

Date: 2026-09-04

Status: implemented and verified with deterministic and live integration tests.

Repository baseline: Vxpipe commit `356216d` and Callpipe commit `2ea5ee0c`.
Pipecat behavior was checked against upstream commit
[`0417f251`](https://github.com/pipecat-ai/pipecat/tree/0417f251261880f08db8f6923267800cfd1934bd).

## Intended outcome

The next slice should make the existing browser playground exercise one complete
audio turn:

```text
browser microphone
  -> WebRTC audio track
  -> gateway media ingress
  -> room-scoped Deepgram Flux STT capability
  -> normalized transcription and turn signals
  -> room-authoritative events
  -> RTVI user speaking/transcription messages
  -> existing deterministic text capability
  -> "Echo: ..." bot output
```

The acceptance case is deliberately small: create a room, connect the current
Pipecat UI, speak one English turn, see partial and final user transcription,
see one start and one stop speaking boundary, and receive one deterministic
echo response derived from the committed Flux turn.

This slice is an implementation of the protocol-neutral STT and turn semantics
already described in `docs/architecture.md`. Deepgram is a provider adapter;
Flux messages do not become the engine's public or durable protocol.

## Scope

The slice includes:

- the incoming WebRTC audio track that is currently ignored by the gateway;
- a protocol-neutral, ordered audio-frame boundary between gateway and engine;
- one Flux WebSocket per active human audio source;
- normalized speech-start, transcript-update, transcript-final, and committed-turn
  signals;
- RTVI `user-started-speaking`, `user-transcription`, and
  `user-stopped-speaking` projection;
- dispatch of a committed audio turn to the existing deterministic text
  capability;
- bounded buffering, explicit teardown, and redacted provider failures; and
- fake-transport tests plus a separately tagged live Deepgram integration lane.

The slice does not include:

- a standalone VAD;
- local transcription models;
- Nova runtime support;
- speculative agent work on Flux eager end-of-turn predictions;
- TTS or bot audio;
- automatic mid-turn provider reconnection;
- transcript persistence or replay; or
- production multi-provider selection and fallback policy.

Nova is researched below because its integration demonstrates why provider-final
transcript segments and conversational turn commitment must remain separate.

## Runtime configuration evidence

The active development Goreman process was launched with the project `.env`, and
the active Vxpipe BEAM child has an environment variable named
`DEEPGRAM_API_KEY`. Only the variable name was inspected; its value was neither
read nor printed. `bin/restart-vxpipe` asks the existing Goreman process to
restart the Vxpipe entry, so watcher-driven restarts continue to use Goreman's
env-file configuration.

The implementation should read the credential in `config/runtime.exs`, place the
resolved provider options under the `:vxpipe_call_engine` application, and pass
explicit options into the supervised STT boundary. Reusable engine modules must
not call `System.get_env/1` themselves. The credential must never enter a room
snapshot, command, domain event, RTVI message, telemetry field, exception text,
or committed configuration file.

The first development configuration will select:

- provider: Deepgram;
- service: Flux `/v2/listen`;
- model: `flux-general-en`;
- eager end-of-turn: disabled; and
- API credential: a runtime-only secret reference resolved from
  `DEEPGRAM_API_KEY`.

Startup should fail with a safe configuration error when Flux is enabled without
the credential. Tests inject provider options and a fake transport directly and
do not depend on the developer's environment.

Implementation result: base configuration leaves STT disabled. The repository's
development overlay enables Flux, and `config/runtime.exs` resolves the required
credential before placing it in explicit provider options. A missing or blank
credential stops development startup with a message that names only the required
variable. The running Goreman process supplies the same environment to
watcher-driven Vxpipe restarts.

## Deepgram protocol findings

### Flux

The [Flux WebSocket reference](https://developers.deepgram.com/reference/speech-to-text/listen-flux)
uses `wss://api.deepgram.com/v2/listen`. The client sends binary audio and JSON
control messages; the server returns `Connected`, `TurnInfo`, configuration
acknowledgements, and errors. Raw audio requires explicit encoding and sample
rate parameters.

The [Flux state model](https://developers.deepgram.com/docs/flux/state) makes
the following distinctions:

- `Update` is a replaceable transcript snapshot for the current turn, normally
  emitted about every 250 ms. It is not a text delta.
- `StartOfTurn` establishes the speech boundary and may already contain the
  first transcript text.
- `EndOfTurn` carries the complete committed provider turn and increments the
  provider's turn index.
- `EagerEndOfTurn` predicts an ending before it is final. It may later be
  followed by `TurnResumed`.

Deepgram's [agent guide](https://developers.deepgram.com/docs/flux/agent)
recommends an initial implementation driven by `EndOfTurn`, with eager events
added only when speculative response generation is wanted. That matches this
slice: `EndOfTurn`, not `EagerEndOfTurn`, is the only Flux signal allowed to
dispatch the deterministic agent.

`CloseStream` is not a substitute for conversational turn completion. The
[close-stream documentation](https://developers.deepgram.com/docs/flux/close-stream)
says it drains buffered audio and can produce final updates, but it does not
produce `EndOfTurn`. Normal connection teardown must therefore discard or mark
an active uncommitted turn rather than fabricate a committed turn. A future
explicit administrative commit can use
[`ForceEndTurn`](https://developers.deepgram.com/docs/flux/force-end-turn), which
does produce the normal `EndOfTurn` flow.

### Audio compatibility gate

The browser's WebRTC audio arrives as RTP packets. The gateway can strip the RTP
header and expose payload bytes plus codec metadata without making the engine
depend on ExWebRTC or ExRTP types.

Deepgram documents raw Opus as a supported Flux input encoding and recommends
audio sends of roughly 80 ms. That does not by itself prove that an individual
browser RTP Opus payload, commonly representing a shorter interval, can be sent
unchanged as one WebSocket binary message. Pipecat does not answer this question
because its internal audio pipeline supplies linear PCM to Flux.

The first implementation checkpoint is therefore a tagged compatibility test
using actual payloads received from the existing browser/WebRTC path:

1. send extracted Opus payloads in original order with `encoding=opus` and the
   negotiated sample rate;
2. confirm Flux accepts the framing and produces `StartOfTurn`, `Update`, and
   `EndOfTurn` for a known utterance;
3. record packet duration, WebSocket send grouping, and observed event timing;
4. if unchanged payloads are rejected or transcription is unreliable, stop and
   add a deliberate codec/repacketization stage rather than concatenating Opus
   payloads or guessing at framing; and
5. keep linear PCM as the explicit fallback design, with its cost and ownership
   visible in the room plan.

This gate prevents codec work from being smuggled into the provider adapter and
keeps a live external-service assumption out of the default test suite.

Implementation result: the live compatibility lane sent individual 20 ms,
48 kHz Opus packets extracted from an Ogg fixture, paced at their original packet
duration. Flux accepted the raw packets and produced both `StartOfTurn` and
`EndOfTurn` with non-empty transcripts. No repacketization or PCM conversion is
needed for this first browser path. The test remains tagged `:integration`, is
excluded by default, and requires both a credential and an explicitly supplied
audio-fixture path.

## How Pipecat integrates Deepgram Nova

Pipecat supports both Deepgram families:

- [`DeepgramSTTService`](https://docs.pipecat.ai/api-reference/server/services/stt/deepgram)
  is the standard streaming service and defaults to `nova-3-general` on
  Deepgram `/v1/listen`.
- `DeepgramFluxSTTService` uses Flux on `/v2/listen` and recommends Pipecat's
  external user-turn strategies because Flux owns the turn boundary.

Pipecat's current
[`DeepgramSTTService` source](https://github.com/pipecat-ai/pipecat/blob/0417f251261880f08db8f6923267800cfd1934bd/src/pipecat/services/deepgram/stt.py)
maps a non-final Nova result to an interim transcription frame and an `is_final`
result to a final transcription frame. It does **not** treat every Nova
`is_final` segment as a completed conversational turn. When Pipecat receives a
pipeline `VADUserStoppedSpeakingFrame`, it asks Deepgram to `Finalize`; the
provider's `from_finalize` response confirms that requested flush.

Turn ownership remains outside the Nova adapter. Pipecat's default
[`UserTurnStrategies`](https://github.com/pipecat-ai/pipecat/blob/0417f251261880f08db8f6923267800cfd1934bd/src/pipecat/turns/user_turn_strategies.py)
uses local start evidence and a turn analyzer for stop decisions, while its
transcript aggregator accumulates provider-final segments until the pipeline
emits a user-stopped-speaking boundary. Some examples also supply a local VAD.

The [Nova streaming reference](https://developers.deepgram.com/reference/speech-to-text/listen-streaming)
explains why this is necessary: `is_final` finalizes a transcript segment,
whereas `speech_final` reflects Deepgram endpointing and `from_finalize` reflects
an explicit client flush. None should be collapsed blindly into a domain-level
turn commit.

Pipecat's Flux integration follows a different route. Its
[`stt_base.py`](https://github.com/pipecat-ai/pipecat/blob/0417f251261880f08db8f6923267800cfd1934bd/src/pipecat/services/deepgram/flux/stt_base.py)
maps `StartOfTurn` and `EndOfTurn` into proposed speaking boundaries for the
external turn controller, and produces the final transcription at
`EndOfTurn`. Its current implementation exposes Flux `Update` through an event
handler rather than emitting its ordinary interim transcription frame. Vxpipe
will preserve the same separation of provider signals from turn authority, but
will also normalize `Update` snapshots so compatible clients can display live
partial transcription.

This comparison validates the architecture rule in `docs/architecture.md`:
provider-final transcription and committed conversational turns are different
facts even when one Flux message supplies evidence for both facts.

## Callpipe reference review

The prior implementation in Callpipe was useful as transport experience, not as
code to transplant.

The following choices remain useful:

- one persistent WebSocket per active STT stream;
- validate media format before sending bytes;
- return provider events asynchronously to the owning process;
- inject a fake WebSocket boundary in focused tests;
- handle explicit stream close; and
- use a silence/watchdog policy when a provider requires continuing audio.

The following choices must not cross into Vxpipe:

- routing credentials and fixed identifiers through an unrelated intermediary;
- reading environment variables inside the adapter;
- nesting transport and adapter modules in one file;
- collapsing Flux `EndOfTurn`, Nova `is_final`, and Nova `speech_final` into one
  `turn_final?` flag;
- attaching unbounded raw provider payloads to events;
- synchronizing tests with sleeps; and
- assuming a fixed 16 kHz PCM input when this gateway currently receives
  browser WebRTC audio.

Vxpipe should preserve separate modules for the engine capability, Deepgram Flux
mapping, and WebSocket transport. The transport dependency should sit in
`vxpipe_call_engine`, the application that owns provider I/O, behind a small
project-owned behavior so deterministic tests do not open sockets.

## Proposed runtime boundaries

The slice should add the following cohesive responsibilities. Names may be
adjusted while keeping the boundaries intact.

### Gateway WebRTC connection

`Vxpipe.Gateway.WebRTC.Connection` continues to own ExWebRTC. For each incoming
audio RTP event it extracts only protocol-neutral data: connection and track
identity, codec, clock/sample rate, channel count, RTP sequence and timestamp,
arrival time, and payload bytes. It does not parse Flux responses or decide turn
semantics.

The existing catch-all ExWebRTC handler currently discards these RTP events, so
the first gateway behavior test should fail until audio is forwarded.

### Connection attachment and bounded media ingress

Attaching a connection should return an internal attachment containing the
existing room monitor plus an opaque media-ingress handle. This handle is an OTP
implementation detail shared by trusted umbrella applications and is never
placed in a public snapshot or protocol response.

The ingress owns a bounded queue; it does not forward every RTP packet through
the room authority mailbox. Its contract records maximum queued frames and age,
preserves accepted packet order, rejects frames for the wrong incarnation or
connection, coalesces no audio silently, and reports overflow. A short isolated
packet loss may be recorded and tolerated because RTP is lossy; sustained
overflow terminates the STT stream rather than allowing an unbounded BEAM
mailbox or producing a knowingly misleading transcript.

The concrete limits should be selected from measured browser packet cadence and
the Flux send path, then encoded as application settings and asserted in tests.
They should not be magic values hidden in a receive loop.

### Speech-to-text capability

One room-scoped capability instance owns one human connection/track stream. It
is started through `RoomCapabilitySupervisor`, monitors the provider transport,
validates media metadata once the track is known, and translates provider
signals into protocol-neutral messages for the room authority. It does not
assign room sequence numbers and does not send RTVI messages.

The first slice will not reconnect a failed socket mid-turn. Replaying uncertain
audio risks duplicate or corrupted transcript state. A transport failure marks
the capability unavailable, emits a safe failure signal, and causes the gateway
session to stop accepting microphone input. A later policy can start a new
capability incarnation at a clear boundary.

### Deepgram Flux adapter and socket

The adapter owns query construction, authorization headers, JSON decoding,
provider event validation, and mapping to normalized Flux signals. The socket
owns WebSocket lifecycle and binary/control frames. Both use one top-level module
per file.

Provider payloads are accepted only up to explicit size limits. Unknown fields
are ignored; unknown event variants are counted and safely ignored. Errors
retain a bounded provider code and category, not headers, URLs with sensitive
parameters, full payloads, or credential material.

### Room authority

The room authority receives only low-rate normalized speech/transcript/turn
signals. It validates the capability and connection identity, assigns room
sequence numbers to domain events, maintains correlation, and dispatches a
committed transcript to the existing deterministic text capability. It never
receives raw audio or performs provider I/O.

## Signal and event mapping

The room should retain distinct event types for transcript state and turn state.
Existing `ParticipantTurnStarted` and `ParticipantTurnCompleted` types need to
accept `:audio` as a modality; a new transcription event or events carry text,
provider phase, and provider turn identity.

| Flux input | Engine action | RTVI projection | Agent action |
| --- | --- | --- | --- |
| `StartOfTurn` | Emit `ParticipantTurnStarted` with audio modality; emit a partial transcript when text is present | `user-started-speaking`, then `user-transcription` with `final: false` when non-empty | None |
| `Update` | Replace the current partial transcript snapshot | `user-transcription` with `final: false` | None |
| `EagerEndOfTurn` | Recognize and record bounded ephemeral evidence only | No committed-turn projection in this slice | None |
| `TurnResumed` | Clear eager evidence; keep the same active turn | None | None |
| `EndOfTurn` | Emit provider-final transcription, then emit the distinct committed `ParticipantTurnCompleted` boundary | `user-transcription` with `final: true`, then `user-stopped-speaking` | Invoke once with the complete final text |
| socket closes before `EndOfTurn` | Discard or cancel the active turn; do not invent completion | End the session with a safe error; no false final transcript | None |

The final transcription event and turn-completed event may share causation and
provider evidence, but they remain separate ordered facts. Flux transcript text
is a full replacement snapshot, so neither engine nor gateway appends one
`Update` to the preceding update. The RTVI
[`user-transcription` observer mapping](https://github.com/pipecat-ai/pipecat/blob/0417f251261880f08db8f6923267800cfd1934bd/src/pipecat/processors/frameworks/rtvi/observer.py)
uses the protocol's `final` boolean for partial versus final transcription; the
gateway will project Vxpipe's normalized events into that shape.

The user-facing correlation ID for an audio turn is created when the normalized
start signal is admitted and remains stable through updates, final transcript,
turn completion, and the resulting deterministic response. Provider turn index
is evidence, not the public identifier.

## Red-green implementation checkpoints

Each checkpoint is intended to be a coherent, independently green commit.

### 1. Flux mapping with a fake transport

Write focused call-engine tests first for:

- runtime options are passed explicitly to the STT capability;
- audio metadata validation rejects unsupported input before bytes are sent;
- Flux `StartOfTurn`, full-snapshot `Update`, and `EndOfTurn` map to distinct
  normalized signals in order;
- `EagerEndOfTurn` never commits a turn;
- `TurnResumed` invalidates eager evidence;
- malformed, oversized, and unknown messages are handled safely;
- a socket failure or `CloseStream` without `EndOfTurn` does not commit; and
- provider error reporting cannot expose authorization data.

Implement the provider behavior, Flux decoder, socket boundary, and capability
only far enough to make those tests pass. Process tests use
`start_supervised!/1`, monitors, and acknowledgements rather than sleeps.

### 2. Live audio compatibility spike

Add an integration test tagged and excluded from the default suite. It requires
an explicitly enabled live lane and the runtime credential. Capture the
protocol-neutral media shape from the existing browser path and resolve the
Opus framing gate described above. Record the evidence here before selecting
unchanged Opus or an explicit codec stage.

The live lane must skip cleanly when its opt-in flag or credential is absent and
must never print the credential, authorization header, or raw `.env` contents.

### 3. Bounded engine media path

Write tests first for:

- attachment returns the correct internal media ingress for the admitted
  connection;
- frames with stale incarnation, participant, connection, or track identity are
  rejected;
- accepted audio preserves order;
- configured queue limits and maximum age are enforced;
- isolated and sustained overflow follow their documented policies; and
- capability or room termination tears down the ingress and provider socket.

Then start the STT capability and ingress through their owning dynamic
supervisor. Keep media out of `RoomAuthority`.

### 4. Domain events and committed-turn dispatch

Write call-engine tests first showing:

- audio start, transcript partial/final, and turn completion receive monotonically
  ordered room sequences where they are durable domain events;
- provider-final and turn-completed remain separate events;
- repeated or stale Flux events cannot dispatch the agent twice;
- only `EndOfTurn` dispatches the complete transcript to deterministic text;
- an empty final transcript closes the turn without invoking the agent; and
- capability death reports unavailability without crashing unrelated room
  workers.

Extend the existing turn event modality contract deliberately rather than
loosening struct types without tests.

### 5. Gateway RTP and RTVI projection

Write gateway tests first showing:

- an incoming audio RTP event becomes the expected protocol-neutral frame;
- RTP events do not traverse the room authority subscriber/event path;
- partial transcript snapshots encode as RTVI `user-transcription` with
  `final: false` and final transcripts use `final: true`;
- messages arrive in speaking-start, transcript, speaking-stop order;
- provider details and internal media handles are absent from RTVI JSON; and
- media ingress failure closes or rejects the session with a safe protocol
  error.

Then add the ExWebRTC handler and RTVI codec projections.

### 6. End-to-end acceptance

Run the playground through the existing Caddy endpoint and verify:

1. room creation and RTVI/WebRTC readiness still work;
2. microphone audio reaches Flux;
3. the UI shows a changing partial as replacement text, not appended snapshots;
4. the UI shows one final user message at `EndOfTurn`;
5. user speaking start and stop each occur once;
6. the bot responds once with `Echo: <committed transcript>`;
7. a second spoken turn creates a new user and bot message rather than appending
   to the prior turn; and
8. disconnecting mid-turn produces no false final transcript or echo.

Record timestamps from the browser log and safe provider/engine telemetry to
measure speech-start, partial, end-of-turn, and echo latencies.

## Verification requirements

During implementation, run focused tests from the application that owns each
boundary while iterating. Before each code checkpoint is complete, run from the
umbrella root:

```shell
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix deps.unlock --check-unused
```

The default suite must use fake provider transport and remain independent of the
network and local secrets. The tagged Deepgram lane supplies interoperability
evidence but is not a substitute for deterministic boundary and lifecycle tests.

## Implementation record

The slice was implemented with `websockex` 0.5.1 in the call-engine application.
The dependency is contained there because that application owns provider I/O;
the transport is still hidden behind the project-owned speech-to-text transport
behaviour used by deterministic tests.

Completed checkpoints:

- `Vxpipe.CallEngine.Provider.Deepgram.Flux` validates configuration, builds the
  connection request, bounds provider messages, and maps only fixed known event
  names. Its inspection representation omits the credential.
- `FluxSocket` owns the WebSocket lifecycle, synchronous binary sends, and
  best-effort `CloseStream` teardown without reconnecting an uncertain turn.
- `SpeechToText` validates audio identity and format, rejects duplicate or stale
  provider sequence numbers, and forwards normalized signals only.
- `Media.Ingress` binds the stream to its first accepted audio track, bounds
  frame count, total bytes, and age, and allows at most one provider send in
  flight. Frames that age while queued are dropped before delivery; sustained
  overflow fails the capability.
- Connection attachment starts and binds the capability and ingress through the
  room's owning dynamic supervisor. Partial startup or binding failure cleans up
  the new children and detaches the connection.
- The room authority assigns turn correlation and event sequence numbers, keeps
  provider-final transcription distinct from turn completion, and dispatches
  only one non-empty `EndOfTurn` transcript to the deterministic agent.
- The gateway maps negotiated Opus RTP to `AudioFrame` and projects normalized
  events to RTVI speaking and transcription messages. Partial text remains a
  replacement snapshot instead of being appended.

Focused tests were written red first at their owning boundaries. The default
call-engine and gateway suites cover provider decoding, socket delegation,
media bounds and failure, room turn semantics, RTP mapping, and RTVI encoding.
Two opt-in live tests then proved:

1. Flux accepts the unchanged Opus packet framing and emits a committed turn.
2. An ExWebRTC client can create a room and session, complete Small WebRTC and
   RTVI readiness, stream RTP through the gateway and engine to Flux, receive an
   ordered final RTVI transcription, and receive exactly the matching
   deterministic echo.

The browser remains the final interactive smoke-test surface. The automated
full-path test exercises the same HTTP, WebRTC, engine, provider, and RTVI
boundaries without depending on UI rendering.

Final verification on 2026-09-04:

- `mix format --check-formatted`: passed;
- `mix compile --warnings-as-errors`: passed;
- `mix test`: 23 call-engine tests and 19 gateway tests passed, with the two
  tagged integration tests excluded;
- `mix deps.unlock --check-unused`: passed; and
- the two explicitly included live integration tests passed together in 25.8
  seconds.

## Decisions captured

- Use Deepgram Flux for the first audio STT slice.
- Use provider-owned Flux turn detection; do not add standalone VAD now.
- Keep Nova out of runtime scope, but preserve the semantic distinctions needed
  to add it later.
- Treat Flux `Update` text as replacement snapshots and expose them as partial
  RTVI transcription.
- Treat `EndOfTurn` as evidence for both a provider-final transcript and a
  distinct engine-authorized turn commit.
- Do not let eager predictions invoke the agent in this slice.
- Do not fabricate a committed turn on `CloseStream` or socket failure.
- Keep raw audio and provider I/O outside the room authority mailbox.
- Resolve the Deepgram credential at the runtime application boundary and pass
  explicit options into supervised workers.
- Gate the browser Opus path with live evidence before choosing pass-through or
  an explicit codec stage.
