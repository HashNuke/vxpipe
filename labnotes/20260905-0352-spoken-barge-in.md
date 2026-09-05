# Spoken barge-in

## Objective

Implement provider-driven spoken barge-in as the next vertical slice. While an
agent response is playing, microphone audio continues through the authenticated
connection's speech-to-text capability. A provider `StartOfTurn` signal stops
the active and queued agent work immediately. The same user turn continues to
collect transcription and, when committed by the provider, becomes the
replacement model and spoken response.

This slice does not add local voice-activity detection. Provider turn detection
remains the semantic source for speech start and end.

## Current observations

- The gateway currently implements half-duplex behavior. Once spoken output is
  announced, `TurnState.input_enabled?/1` becomes false, incoming RTP is
  discarded, and `user-mute-started` is sent to the client until playout ends.
- Deepgram Flux already normalizes `StartOfTurn`, transcript updates, and
  `EndOfTurn` into speech-to-text signals. The room begins a participant audio
  turn on `StartOfTurn`, but interruption currently waits for the committed
  transcript at `EndOfTurn`.
- The existing typed interruption path already cancels model inference, queued
  synthesis, remote synthesis, and locally queued RTP. It also emits an
  attributed `AgentTurnInterrupted` event.
- Each speech-to-text capability is bound by the room authority to one
  authenticated connection and participant. A provider signal therefore has a
  trusted interrupter identity without accepting an identity from the client or
  provider payload.
- Spoken barge-in must occur at provider turn start. Waiting for a final
  transcript would make the user finish speaking over audio that should already
  have stopped.

## Design decisions

- Introduce a protocol-neutral internal interruption context rather than
  fabricating a `SendText` command before text exists. Both typed and spoken
  interruption use the same room-owned cancellation function.
- A newly accepted provider turn owns a generated command ID and turn
  correlation ID. Those IDs, together with the bound connection and participant
  identity, attribute the interruption and later committed input consistently.
- Interrupt at most once for a provider turn, when its `StartOfTurn` is accepted.
  Transcript updates, `TurnResumed`, and `EndOfTurn` do not repeat the
  cancellation.
- If no agent work is active, speech start only opens the participant turn; no
  false interruption event is emitted.
- The gateway remains full duplex during agent output. It no longer uses
  server-side user-mute messages or drops microphone RTP based on output state.
  Acoustic echo control remains a capture/transport responsibility; it is not a
  reason to invent local VAD in this slice.
- Standard interruption and speaking/transcription projections remain
  compatible. Rich attribution continues through the existing optional
  `vxpipe.turn` server message.

## Planned checkpoints

1. Room-authoritative spoken interruption:
   - add a focused failing call-engine test in which provider `StartOfTurn`
     interrupts an active spoken agent response before `EndOfTurn`;
   - refactor the room cancellation path around a neutral interrupter identity;
   - prove the event attributes the STT-bound participant and that the committed
     audio turn subsequently produces the replacement response;
   - prove an idle speech start emits no interruption.
2. Full-duplex gateway ingress:
   - add focused failing gateway tests proving microphone input stays enabled
     throughout agent playout and no server mute actions are projected;
   - remove the output-dependent RTP gate and obsolete mute projection while
     preserving output sequencing and interruption handling;
   - add or extend the WebRTC boundary test so RTP received during spoken output
     reaches the engine ingress.
3. Documentation and verification:
   - update durable architecture and development documentation with the
     provider-driven barge-in semantics and explicit non-goals;
   - record red/green evidence and any implementation corrections here;
   - run format, warnings-as-errors compilation, the complete default test
     suite, and unused-dependency verification from the umbrella root.

## Progress log

- 2026-09-05: Inspected the gateway RTP gate, RTVI turn projection, normalized
  Flux signals, room audio-turn lifecycle, and the previously implemented
  cancellation path. Confirmed the slice can reuse existing media, STT, model,
  TTS, and egress components; its new engine boundary is early interruption on
  authenticated provider turn start.
- 2026-09-05: Added a room-level spoken barge-in test before implementation. It
  failed at the expected boundary: `StartOfTurn` emitted participant start and
  transcription events but produced no audio-egress or synthesis interruption.
- 2026-09-05: Added an internal `TurnInterrupter` value so typed commands and
  provider speech starts share cancellation without treating an incomplete
  spoken turn as text input. The room now allocates the audio turn identity,
  cancels older work, emits the attributed interruption, and only then emits the
  participant turn start. The generated command submitted at `EndOfTurn` is
  non-immediate because interruption was already evaluated at speech start.
- 2026-09-05: The new tests prove active speech is canceled before turn commit,
  the interruption and later transcript share the generated command and
  correlation IDs, replacement speech waits for the old provider boundary, and
  idle speech start emits no false interruption. The focused file passes two
  tests; the call-engine suite passes 49 tests with one tagged integration test
  excluded.
- 2026-09-05: Changed the gateway turn-state expectations before implementation.
  Three tests failed because spoken output still produced `user-mute-started`
  and completion or interruption still produced `user-mute-stopped`. Added a
  real local WebRTC test with fake provider transports; it timed out waiting for
  STT audio and captured the mute message, confirming RTP was discarded while
  the output turn was active.
- 2026-09-05: Removed the output-dependent RTP gate and synthetic server mute
  actions. `TurnState` continues to serialize spoken output projection, while
  the WebRTC connection now forwards every valid inbound audio packet through
  its bounded media ingress regardless of output state. Removed the unused mute
  encoder rather than retaining a misleading control path.
- 2026-09-05: Updated the externally tagged audio tests to reject server mute
  messages. The queued-TTS test now correctly uses non-immediate text and waits
  for both output completions instead of using the removed mute-stop message as
  a completion sentinel. The focused turn-state and WebRTC tests pass six tests;
  the gateway default suite passes 35 tests with three externally tagged tests
  excluded.
- 2026-09-05: Extended the local WebRTC test through the complete control path.
  After proving RTP reaches the fake STT transport during active output, the test
  injects provider start and end signals and observes standard interruption,
  attributed custom context, user speech/transcription boundaries, and the
  replacement spoken `bot-output` on the data channel. This keeps the default
  suite deterministic while covering the adapter-to-engine-to-adapter slice.
