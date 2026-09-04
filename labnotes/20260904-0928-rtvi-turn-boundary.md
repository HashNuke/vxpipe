# RTVI turn boundary

## Reported behavior

Two successive `send-text` turns produced distinct engine outputs and distinct
RTVI `segment_id` values, but Voice UI Kit appended the second output to the
first assistant bubble.

## Investigation

- `segment_id` identifies output segments within an assistant stream; it does
  not close the assistant turn.
- The installed `@pipecat-ai/client-react` 1.8.2 protocol 2.x conversation
  reducer leaves assistant output open until it receives
  `bot-stopped-speaking` or `user-started-speaking`.
- Voice UI Kit 0.13.1 injects typed user text directly into conversation state.
  That does not synthesize a `user-started-speaking` wire event, so the gateway
  must project both input and output turn boundaries.

## Red test

Extended the real WebRTC integration to require `bot-stopped-speaking` after
the deterministic `bot-output`. The current implementation is expected to time
out because it projects only the text output.

The focused integration failed at that assertion after five seconds, confirming
the gateway never emitted a boundary. A focused engine assertion also requires
a protocol-neutral, sequenced `AgentTurnCompleted` event after `TextOutput` so
the RTVI adapter does not have to infer completion from an output chunk.

## Timing edge found during browser verification

Projecting `AgentTurnCompleted` as `bot-stopped-speaking` fixed turns separated
by the reported five-second interval. A more aggressive browser pass submitted
two text turns 100 milliseconds apart. Pipecat React deliberately delays bot
stop finalization for 2.5 seconds to tolerate speech pauses, so the fast turns
still merged.

Typed text is already a complete participant turn when `send-text` reaches the
engine. The engine will therefore emit protocol-neutral
`ParticipantTurnStarted` and `ParticipantTurnCompleted` events around accepted
text input. RTVI projects those as its standard user speaking boundaries. This
lets an unmodified client immediately close any pending assistant stream before
the response to the new user turn, without leaking RTVI terms into the engine or
making correctness depend on a client-side timer.

## Implementation

- The room authority emits participant start/completion events only after
  authorizing the process-bound `SendText` command, then dispatches the command
  to the capability.
- The deterministic capability result emits `TextOutput` followed by a distinct
  `AgentTurnCompleted` event. All four events have unique IDs and consecutive
  room-incarnation sequence numbers.
- The gateway maps participant boundaries to `user-started-speaking` and
  `user-stopped-speaking`, output to `bot-output`, and agent completion to
  `bot-stopped-speaking`. Empty RTVI lifecycle events use `data: null`.
- The current Pipecat server's `send-text` handler interrupts when requested and
  appends a complete user message; it does not itself define a client-side typed
  turn marker. The gateway mapping is therefore an RTVI compatibility
  projection from the richer internal turn lifecycle.

Primary references inspected:

- <https://docs.pipecat.ai/client/rtvi-standard>
- <https://github.com/pipecat-ai/pipecat/blob/main/src/pipecat/processors/frameworks/rtvi/processor.py>

## Focused green evidence

- Call-engine text-turn tests: 2 tests, 0 failures.
- Gateway codec plus real WebRTC integration: 8 tests, 0 failures.
- Headless Chrome with client-js 1.13.0, client-react 1.8.2, and Voice UI Kit
  0.13.1 rendered two user/assistant pairs submitted 100 milliseconds apart.
  The event console showed ordered user start/stop, bot output, and bot stop
  messages for each turn. Desktop and mobile conversation states were inspected;
  the browser reported no page errors.

## Completion verification

- `mix format --check-formatted`: passed.
- `mix compile --warnings-as-errors`: passed.
- `mix test`: 24 tests, 0 failures across both umbrella applications.
- `mix deps.unlock --check-unused`: passed.
- `npm test --prefix samples -- --run`: 2 tests, 0 failures.
- `npm run build --prefix samples`: passed; Vite retained its existing large
  chunk advisory.
- `git diff --check`: passed.
