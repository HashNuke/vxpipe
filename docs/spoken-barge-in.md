# Provider-driven spoken barge-in

Status: Implemented bounded vertical slice

## Decision

Vxpipe keeps an authenticated participant's microphone ingress active while
agent audio is playing. The hosted speech-to-text provider remains responsible
for speech activity and endpointing. When its adapter emits `StartOfTurn`, the
room authority treats that signal as an immediate, room-wide interruption of
the current single logical agent-output lane.

The call engine does not run a local VAD and the gateway does not infer an
interruption from RTP energy. Provider turn evidence is the semantic trigger.

## End-to-end flow

1. The WebRTC connection forwards every valid inbound audio packet through the
   connection's bounded, protocol-neutral media ingress, including while agent
   output is queued or playing.
2. The participant's speech-to-text capability streams that audio to its
   configured provider. Output state does not pause this provider stream.
3. A normalized `StartOfTurn` reaches the room authority with the internal
   identity of the speech-to-text capability that produced it.
4. The room verifies that capability is still bound to the same tenant, room
   incarnation, participant, and connection. It generates the new audio turn's
   command and correlation IDs before cancellation begins.
5. The existing interruption path stops locally queued RTP, cancels active and
   queued synthesis and model work, and emits one attributed
   `AgentTurnInterrupted`. If no agent turn is active, no interruption event is
   fabricated.
6. The room emits `ParticipantTurnStarted` and subsequent replacement
   transcription events using the same generated identity. Repeated provider
   updates for that turn do not interrupt again.
7. `EndOfTurn` commits the final non-empty transcript. Its internal `SendText`
   command is non-immediate because interruption was already evaluated at
   speech start. The committed turn proceeds through model inference, TTS, and
   paced WebRTC output normally.

The cancellation event precedes the new participant-start event in the room's
monotonic sequence whenever an older turn was active. This makes the state
transition explicit: old output ends, then the replacement input turn begins.

## Identity and protocol projection

No participant identifier is accepted from the STT payload or an RTVI message.
Each STT capability is attached to one server-authenticated connection and one
participant. The room uses that binding for `interrupted_by_participant_id` and
`interrupted_by_connection_id`; the generated audio-turn IDs become the
interruption command and correlation IDs.

Unmodified RTVI 2.x clients receive the standard empty `bot-interrupted` event,
then the normal user-speaking and transcription events. Vxpipe-aware clients
also receive the existing versioned `vxpipe.turn` server message with complete
interruption attribution. No private fields are added to standard event shapes.

The standard event is sent to the connection whose agent output was canceled.
Room-wide roster broadcasting remains a later authorization and subscription
feature.

## Full-duplex and echo boundary

The gateway no longer sends synthetic `user-mute-started` or
`user-mute-stopped` events around agent output and no longer discards microphone
RTP based on output state. Its bounded ingress policy is unchanged: stale,
unsupported, malformed, or overflowing media can still be dropped according to
the existing media contract.

Full-duplex transport makes acoustic echo control important. Browser or device
capture should enable its available echo cancellation and use appropriate
output/input routing. Vxpipe does not attempt server-side acoustic echo
cancellation in this slice. If echoed agent audio causes the provider to emit a
false `StartOfTurn`, the room will treat it as participant speech and interrupt;
that is an explicit limitation rather than a hidden local energy heuristic.

Observed stop latency contains microphone capture and RTP transit, provider
turn-start detection, provider-to-engine transit, and room cancellation. Once
the room receives the signal, local audio egress is still the first playout
boundary stopped. No fixed end-to-end latency is promised by this checkpoint.

## Rejected alternatives

- Waiting for `EndOfTurn` would provide final text but would make the agent keep
  speaking throughout the user's interruption.
- Triggering from raw RTP arrival would make background audio and silence look
  like intentional participant speech.
- Adding a local energy detector would duplicate provider turn detection and
  introduce a VAD capability that is outside the current product scope.
- Fabricating a partial `SendText` command at speech start would conflate an
  interruption signal with conversational input that has not yet committed.
- Trusting a participant ID in a provider or client payload would bypass the
  authenticated connection binding already owned by the room.
- Keeping the server mute messages while continuing to process audio would make
  the protocol claim the opposite of actual transport behavior.

## Implications

- Every connected participant has a separate transport connection, so a
  provider speech start has an unambiguous authenticated source.
- Barge-in is room-wide while a room exposes one logical agent-output lane.
  Targeted interruption requires an explicit future multi-agent contract.
- Microphone audio continues to consume STT bandwidth and provider capacity
  during agent output.
- Provider false starts can cancel useful work. Future confidence policies may
  delay or qualify interruption, but they must remain explicit room policy and
  must not alter the authenticated source identity.
- The engine's interruption primitive is protocol-neutral. Typed input,
  provider speech, and future client protocols can share cancellation without
  importing RTVI or WebRTC types into the call engine.

## Verification evidence

- A call-engine vertical test starts real room STT and TTS capability processes
  with fake transports, begins paced agent playout, injects `StartOfTurn`, and
  proves local playout and synthesis are interrupted before `EndOfTurn`.
- The same test proves interruption attribution and the new participant turn
  share one generated command/correlation identity, the committed transcript
  produces replacement output, and replacement synthesis waits for the old
  provider boundary.
- A second engine test proves speech start while idle emits no false
  interruption.
- Gateway turn-state tests prove spoken output remains serialized without any
  synthetic server mute actions or false completed-spoken progress.
- A deterministic local WebRTC test proves RTP received during active agent
  output reaches the STT transport, provider start projects standard and
  attributed interruption messages, and provider end produces replacement
  spoken output.
- The default call-engine and gateway suites cover these paths without external
  network access. Live provider interoperability remains in the explicitly
  tagged integration lane.
