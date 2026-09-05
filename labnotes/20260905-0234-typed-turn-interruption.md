# Typed turn interruption

## Objective

Implement the next vertical slice: an accepted RTVI `send-text` command with
`options.run_immediately: true` interrupts an in-progress agent turn, stops
locally buffered audio, cancels superseded queued work, attributes the
interruption to the authenticated participant and connection, and then starts
the new turn. `run_immediately: false` retains the existing queued behavior.

## Current observations

- A room can contain multiple participant identities and multiple attached
  connections. Each connection is bound to one participant by the room
  authority.
- A room currently starts one configured agent participant. The internal event
  model must nevertheless name that agent explicitly so a future room with
  several agents does not inherit an ambiguous interruption contract.
- `SendText` already carries `participant_id`, `connection_id`, and
  `run_immediately`. The gateway derives those IDs from its attached session;
  client message data is not an authority for participant identity.
- Text generation and speech synthesis each serialize work independently.
  Audio egress paces already-produced audio, so canceling only generation or
  synthesis would still allow buffered audio to play.
- The public RTVI interruption event cannot carry Vxpipe's full attribution.
  Vxpipe can preserve that standard event and additionally project a versioned
  custom server message for clients that understand richer room semantics.

## Identity and ordering decisions

- The room authority is the serialization point for interruption. It validates
  the new command's connection before any work is canceled.
- The interrupted turn records the agent participant, the participant whose
  input produced that turn, its target connection and correlation ID, plus the
  interrupting participant, connection, command, and correlation IDs.
- The first accepted immediate command that observes active work owns the
  interruption attribution. Later commands operate on the state that remains;
  they cannot be credited with interrupting an already-canceled turn.
- Standard clients receive `bot-interrupted`. Vxpipe-aware clients also receive
  a `server-message` whose versioned payload identifies the interrupted turn,
  agent, and interrupter. Standard event schemas will not be modified with
  private fields.
- The current room exposes one logical bot through an RTVI connection. Multiple
  internal agents remain possible, but independent addressing is a Vxpipe
  extension rather than an assumption embedded in the standard projection.

## Planned checkpoint

1. Add focused failing tests for the owned contracts:
   - audio egress atomically drops remaining packets and reports played time;
   - speech synthesis cancels the current request and queued requests, discards
     stale provider audio, and lets later synthesis continue;
   - immediate text cancels superseded generation/speech and emits an attributed
     interruption, while non-immediate text continues to queue;
   - gateway turn state emits the standard interruption and the versioned
     attributed server message, then permits the replacement turn;
   - interruption from a second participant is attributed to that participant,
     not to the participant whose earlier turn is being interrupted.
2. Implement the smallest APIs at the owning boundaries: audio output,
   text-to-speech, model inference, room authority, internal event, gateway turn
   state, codec, and WebRTC event routing.
3. Keep local playback authoritative. Stop queued RTP before waiting for any
   remote synthesis acknowledgement. When the speech provider still has an
   active turn, send it the session playback offset and discard late audio until
   that turn is closed.
4. Conservatively remove a canceled completed response from model history when
   exact heard text is unavailable, so subsequent prompts do not treat an
   unplayed full response as heard. Cancel in-flight model tasks before accepting
   replacement work.
5. Update durable architecture and sample-facing documentation for the new
   behavior and attribution contract.
6. Run focused tests throughout, then the umbrella completion checks:
   `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test`,
   and `mix deps.unlock --check-unused`.

## Progress log

- 2026-09-05: Inspected the command, room, generation, synthesis, audio egress,
  event projection, and gateway turn-state boundaries. Confirmed that room and
  connection identity already provide an authoritative interrupter ID, while a
  new internal event and custom server message are required to expose complete
  attribution.
- 2026-09-05: Added a failing audio-egress test. It demonstrated that the sink
  had no interruption call and crashed on the new control. Added an authenticated
  turn/callback cancellation boundary which drops queued packets, invalidates
  stale pace messages, and returns locally elapsed playout. The focused egress
  suite then passed.
- 2026-09-05: Added provider-adapter tests before implementation. Added the
  session-wide playback-offset interrupt control and normalized interruption
  feedback fields. Verification against the provider reference caught an
  incorrect initial assumption about field nesting; the normalized decoder now
  reads speech identity from metadata and played/text feedback from the top-level
  message.
- 2026-09-05: Added synthesis capability tests for active and pending
  cancellation, late-audio discard, and replacement ordering. A second red test
  reproduced control-mailbox starvation while a bounded sink write was
  backpressured. The final design keeps exactly one sink write in a dedicated
  supervised task, preserving provider backpressure without delaying control
  messages or accumulating audio tasks.
- 2026-09-05: Added model-capability tests for killing an in-flight provider
  task, clearing queued work, ignoring its stale result, and removing an
  interrupted completed pair from later context. History identity uses
  connection, correlation, and command IDs together so separate participants
  cannot collide by reusing a client correlation ID.
- 2026-09-05: Added `AgentTurnInterrupted` and made the room authority track
  accepted agent turns. Immediate commands cancel older model, synthesis, and
  egress work and emit newest-first interruption events; non-immediate commands
  retain FIFO behavior. A two-participant room test proves that the event names
  the earlier source participant and the distinct authenticated interrupter.
- 2026-09-05: Added the gateway projection. Standard clients receive
  `bot-interrupted`; an optional `vxpipe.turn` server message carries the agent,
  source, target, interrupter, commands, correlations, and played time. The turn
  state releases mute without emitting a false completed-spoken update.
- 2026-09-05: Updated the architecture, component READMEs, and the focused
  decision record in `docs/typed-turn-interruption.md`. Focused call-engine and
  gateway suites are green.
- 2026-09-05: All umbrella completion checks passed:
  `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test`
  (47 call-engine tests and 35 gateway tests passing; tagged integration tests
  excluded by the default lane), and `mix deps.unlock --check-unused`.
