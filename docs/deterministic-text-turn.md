# Deterministic text turn

Status: Implemented bounded vertical slice

## Decision

Vxpipe's first bidirectional conversation path is a provider-free text turn. A
current Pipecat client sends standard RTVI `send-text`; the gateway translates
it into a protocol-neutral engine command. A supervised deterministic
capability produces an engine event, which the gateway projects as standard
RTVI `bot-output`.

The deterministic responder is a capability instance attached to an agent
participant, not a special RTVI bot inside the call engine. A future protocol
adapter can submit the same `SendText` command and consume the same `TextOutput`
event without depending on Pipecat message names.

## Runtime flow

```text
Pipecat UI              Gateway connection          Room authority       Capability
    | send-text JSON            |                         |                  |
    |-------------------------->| SendText command        |                  |
    |                           |------------------------>| authorize caller |
    |                           |                         |----------------->|
    |                           |                         |  Echo: <content> |
    |                           |     TextOutput event    |<-----------------|
    |         bot-output JSON   |<------------------------| sequence + route |
    |<--------------------------|                         |                  |
```

Development room creation requests the closed `:deterministic_text` agent
preset. The room authority admits an agent participant through the same
participant supervisor used for humans, then starts its text responder through
`RoomCapabilitySupervisor`. This makes the process a capability owned by the
room incarnation rather than work performed in the room authority mailbox.

## Attachment and authorization

The gateway claims its existing single-use session before starting WebRTC. The
connection process then submits `AttachConnection`, containing only validated
tenant, actor, room, incarnation, participant, connection, command, and deadline
identities. The room authority accepts it only when:

- the room incarnation still matches the session;
- the human participant is still admitted;
- the deterministic agent participant and capability are live;
- the connection ID is not already attached; and
- the process submitting the command is the process being attached.

The gateway monitors the room authority. The room authority monitors the
gateway connection and both participants; it also monitors the capability.
Connection exit removes the subscription. Room, human participant, agent
participant, or capability loss notifies or terminates the gateway connection.
This gives `bot-ready` a concrete meaning: the transport is bound to a live
engine path capable of accepting the supported text operation.

`SendText` repeats the stable identities and adds the client correlation ID,
content, options, and deadline. The room authority verifies the calling process
against the attached connection before dispatch. Supplying valid IDs from a
different process is insufficient.

## Engine event

The deterministic capability sends its result back to the room authority. Only
the room authority assigns the event ID and monotonically increasing sequence
within the room incarnation. `TextOutput` records:

- engine event and command IDs;
- client correlation ID;
- tenant, room, and incarnation IDs;
- source human and output agent participant IDs;
- target connection ID;
- sequence, occurrence time, and text; and
- provider-neutral aggregation and expected playout state.

The event is routed only to the originating connection. It is not yet persisted
or replayable.

## RTVI projection

The gateway accepts the installed Pipecat client's current `send-text` shape:

```json
{
  "type": "send-text",
  "data": {
    "content": "hello",
    "options": {
      "run_immediately": true,
      "audio_response": true
    }
  }
}
```

Options default to the RTVI values when omitted and must be booleans when
present. The engine additionally requires non-empty UTF-8 content of at most
4096 bytes. Invalid protocol options or rejected engine commands receive a
correlated `error-response` without closing the transport.

The output projection is one sentence-aggregated, unspoken `bot-output`:

```json
{
  "type": "bot-output",
  "data": {
    "text": "Echo: hello",
    "aggregated_by": "sentence",
    "segment_id": 1,
    "will_be_spoken": false
  }
}
```

Pipecat's text input injects the user's text into its local conversation view.
The server event adds the assistant message. Although Pipecat requests an audio
response by default, this deterministic checkpoint always reports the output as
unspoken because no speech-synthesis capability exists yet.

## Alternatives rejected

- Echoing directly in the RTVI codec would test JSON but bypass the call engine,
  participant authorization, supervision, and domain events.
- Producing the response in the room authority would put processing work on the
  authoritative state mailbox and erase the capability boundary.
- Adding a hosted model for the first text path would make credentials, network
  availability, latency, and provider behavior prerequisites for testing the
  engine contract.
- Reusing the RTVI message as the engine command would make other client
  protocols depend on Pipecat field names and defaults.
- Broadcasting the output to every room connection would disclose a private
  turn before event visibility and room subscription policies exist.

## Implications and next boundary

This slice establishes command authorization, supervised capability dispatch,
room sequencing, targeted domain-event delivery, and a real client projection.
The deterministic capability is intentionally not an LLM simulation and keeps
no conversation context.

The next audio slice can replace the text input edge with a hosted transcription
adapter and replace the unspoken output edge with hosted speech synthesis while
preserving `SendText`, `TextOutput`, participant attachment, and RTVI projection.
Turn commitment, streaming output, interruption, context, retries, provider
fallback, and actual playout remain separate checkpoints.

## Verification evidence

- A focused call-engine test creates the agent participant and capability,
  attaches a human connection, rejects the same identifiers from another
  process, and receives the sequenced `TextOutput` event.
- Another engine test proves a room without an agent path cannot report a
  successful connection attachment.
- Codec tests cover the installed client's `send-text` shape, defaults and
  validation, plus the exact unspoken `bot-output` projection.
- The real ExWebRTC integration test performs the complete SDP, ICE, RTVI
  readiness, text command, engine event, and output projection path.
- The unmodified Pipecat React client 1.13.0 was exercised in headless Chrome.
  Typing `hello` displayed local user text and `Echo: hello` as the assistant,
  recorded the `botOutput` event, and disconnected without browser errors. The
  conversation was inspected at desktop and mobile viewports.
