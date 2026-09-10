# Typed turn interruption

## Decision

An authenticated `SendText` command with `run_immediately: true` is a
room-authoritative interruption. The room cancels every older active or queued
turn in its single logical agent-output lane before accepting replacement work.
`run_immediately: false` retains FIFO behavior.

The gateway session, not client-supplied message data, supplies the interrupting
participant and connection identities. Human and agent identities use the same
stable participant-ID namespace inside the call engine. The current room starts
one configured agent participant and can admit multiple human participants and
connections. Internal events name the agent explicitly so this contract remains
unambiguous if a later room can host more than one agent.

Each interrupted turn produces `AgentTurnInterrupted` with:

- the interrupted agent participant;
- the participant whose input produced the interrupted turn;
- the interrupted connection, command, and correlation IDs;
- the interrupting participant, connection, command, and correlation IDs; and
- locally confirmed played milliseconds.

The room authority serializes competing commands. Interruption events are
ordered newest-first so queued per-connection output is removed before active
output is ended. A later immediate command can interrupt replacement work that
was already accepted, but cannot claim an older turn that has already been
canceled.

## Protocol projection

Unmodified RTVI 2.x clients receive the standard `bot-interrupted` event. That
event remains schema-compatible and carries no private fields. The gateway also
emits an optional standard `server-message` containing this versioned envelope:

```json
{
  "t": "vxpipe.turn",
  "v": 1,
  "d": {
    "kind": "interrupted",
    "turn": {
      "agent_participant_id": "part_agent",
      "source_participant_id": "part_originator",
      "connection_id": "conn_originator",
      "command_id": "cmd_original",
      "correlation_id": "turn_original",
      "played_ms": 320
    },
    "interrupted_by": {
      "participant_id": "part_interrupter",
      "connection_id": "conn_interrupter",
      "command_id": "cmd_interrupter",
      "correlation_id": "turn_interrupter"
    }
  }
}
```

The standard surface represents one logical bot per RTVI connection. Vxpipe can
compose several internal agents behind that bot, but independently addressing
or attributing those agents requires a Vxpipe message or another future protocol
adapter.

## Cancellation path

Cancellation proceeds from the listener outward:

1. Per-connection audio egress clears unsent RTP, PCM remainder, and pending
   output operations and reports confirmed paced playout.
2. The text-to-speech capability keeps at most one sink write in a supervised
   task, so bounded RTP backpressure cannot block its control mailbox. It drops
   older queued requests and quarantines late audio for the canceled provider
   turn.
3. If speech is active and some audio played, the provider receives an interrupt
   with the cumulative session playback offset. Replacement synthesis waits for
   the old provider boundary before starting on the persistent session.
4. In-flight model work is killed, queued model work is removed, and completed
   interrupted turn pairs are removed from volatile model context. This is
   conservative when exact heard text is unavailable: later context must not
   claim the full canceled response was heard.
5. The room emits attributed interruption events, accepts the replacement turn,
   and preserves monotonic room-incarnation event sequence numbers.

This cancellation path is also used by provider-driven spoken barge-in. The
gateway now keeps microphone RTP flowing during spoken output, and a normalized
provider speech start supplies the same authenticated participant/connection
attribution through a protocol-neutral internal interrupter value. See
[`spoken-barge-in.md`](spoken-barge-in.md) for the input and turn-detection
boundary.

## Rejected alternatives

- Adding Vxpipe fields to `bot-interrupted` would create a subtly incompatible
  RTVI dialect. A parallel custom message keeps standard clients working.
- Accepting a participant ID inside `send-text` would let the browser assert an
  identity already bound by the authenticated gateway session.
- Canceling only remote synthesis would allow already-buffered audio to keep
  playing. Local egress must be the first cancellation boundary.
- Retaining a complete assistant response in model history after partial
  playback would make future turns reason from words the participant did not
  hear.
- Treating the standard bot event as independently addressable multi-agent state
  would make agent attribution implicit and ambiguous.

## Implications

- Interruption is currently room-wide because the room has one logical agent
  output lane. A future targeted multi-agent command must name its target and
  define whether other agent lanes continue.
- The interruption notification is delivered to the connection whose output was
  canceled. A future room-roster subscription can broadcast the same neutral
  event to other authorized participants without changing its fields.
- Exact partial-text history reconciliation requires provider word alignment or
  another trusted playout source. Until then the conservative history operation
  removes the completed interrupted pair.
- A provider turn interrupted before confirmed playout is drained and discarded
  until its provider boundary; it is not sent a fabricated nonzero offset.

## Verification evidence

- Audio-egress tests prove confirmed played time is returned, remaining packets
  are dropped, stale pace messages are harmless, and a replacement turn can
  start.
- Provider-adapter tests prove the playback-offset control and bounded
  interruption metadata decoding.
- Text-to-speech capability tests prove active and queued request cancellation,
  late-audio quarantine, replacement serialization, and prompt cancellation
  while a sink write is backpressured.
- Model capability tests prove task termination, queue removal, stale-result
  suppression, and conservative history removal.
- Agent Runtime coordinator tests prove active and queued caller cancellation, exact completed-turn
  history removal, replacement admission in the same Session, and survival of a separately
  supervised tool worker.
- A room vertical test proves participant B can interrupt participant A's spoken
  turn and that every identity in `AgentTurnInterrupted` is authoritative.
- Gateway codec and turn-state tests prove standard `bot-interrupted`, attributed
  `server-message`, interruption state release, and the absence of false
  completed-spoken progress.
- A model-room test proves `run_immediately: false` retains FIFO behavior.
