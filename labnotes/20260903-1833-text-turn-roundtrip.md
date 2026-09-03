# Text turn round trip

## Goal

Make the existing Pipecat console complete one visible provider-free text turn
through the real Vxpipe call engine: RTVI `send-text` becomes a protocol-neutral
command, a supervised deterministic agent produces an engine event, and the
gateway projects that event as RTVI `bot-output`.

## Scope

- One deterministic text-only agent participant per development room.
- Bind each gateway WebRTC connection to its admitted engine participant and
  room incarnation before reporting `bot-ready`.
- Route one complete text response back to the originating connection.
- Tear the transport down when its room, human participant, or agent terminates.
- Do not add speech recognition, speech synthesis, model providers, audio
  response, persistence, reconnection, or tool execution.

## Research

- The installed Pipecat client 1.13.0 sends `send-text` with
  `data.content` and `data.options`; the options may contain `run_immediately`
  and `audio_response`.
- RTVI `bot-output` data contains text plus aggregation and spoken-status
  metadata. In protocol 2.x, the current React conversation state consumes
  `will_be_spoken`, `spoken_status`, `spoken_progress`, `segment_id`, and
  `aggregated_by`.
- The Voice UI Kit text input injects the local user message before calling the
  client's `sendText`, so only the engine-produced assistant output needs to be
  projected back for this slice.

## Constraints and decisions

- The gateway owns RTVI decoding/encoding; the call engine receives no JSON or
  Pipecat types.
- The room authority owns connection authorization and event sequencing, but
  deterministic response work runs in a separately supervised agent process.
- Gateway connection processes subscribe through a protocol-neutral attach
  command. Both sides monitor the boundary so failure does not leave stale
  subscriptions or transports.
- The deterministic adapter returns unspoken text even though Pipecat's default
  `send-text` option requests an audio response. Audio output is explicitly
  outside this checkpoint.

## Progress

- Created the labnote before implementation.
- Added closed, validated `AttachConnection` and `SendText` engine commands and
  a protocol-neutral, room-sequenced `TextOutput` event.
- Development room creation now admits an agent participant and starts its
  deterministic responder only through the room-owned capability supervisor.
- The room authority authorizes the connection process as well as its stable
  IDs, dispatches response work outside its mailbox, and targets output to the
  originating connection. A process presenting the same IDs without owning the
  attachment is rejected.
- Gateway connections attach before WebRTC readiness and mutually monitor the
  room boundary. Participant, room, agent, or capability loss tears down the
  transport; browser disconnect cleans the room subscription without ending the
  room.
- Extended the RTVI codec to validate current `send-text` messages, preserve
  client correlation, and encode engine output as sentence-aggregated unspoken
  `bot-output`.
- Extended the real WebRTC integration test through the text command, agent
  capability, domain event, and RTVI output path.

## Verification

- The initial call-engine test failed because the text event and command path
  did not exist, then passed after the supervised engine implementation.
- Focused call-engine tests cover the successful round trip, process-bound
  authorization, participant-loss notification, and refusal to attach when no
  agent path is ready.
- Codec tests cover valid current-client input, invalid option correlation, and
  the output projection.
- The real ExWebRTC test completes readiness and receives `Echo: hello` as a
  `bot-output` event before verifying the existing disconnect isolation.
- An unmodified Pipecat React client 1.13.0 displayed `hello` as the user and
  `Echo: hello` as the assistant in headless Chrome. The event console recorded
  the unspoken sentence output, desktop and mobile conversation views rendered
  correctly, and disconnect produced no browser errors.
- Final verification passed: formatting, warnings-as-errors compilation, all 24
  ExUnit tests, the unused-lock check, both frontend tests, and the production
  frontend build. The build retains the pre-existing large-chunk advisory.
