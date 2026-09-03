# Connect RTVI participant

## Goal

Implement the next bounded vertical slice: admit one browser participant to an
existing room, bind it to a short-lived gateway session, establish Pipecat Small
WebRTC, complete the RTVI `client-ready` / `bot-ready` handshake, and tear down
the transport connection without terminating the room.

## Scope

- One human browser participant per issued development session.
- The existing configured development principal remains the identity source.
- Audio RTP is accepted and discarded at the transport boundary for now.
- No STT, TTS, LLM, VAD, durable state, reconnection, or multi-participant media
  routing is included.

## Research

- Pipecat client 1.13.0 creates an ordered `chat` data channel, posts
  `{sdp, type, pc_id, restart_pc, requestData}`, and sends later ICE candidates
  with `PATCH` using `{pc_id, candidates}`.
- Pipecat messages on the data channel use the `rtvi-ai` label. The client sends
  protocol version 2.1.0 in `client-ready` and resolves `connect()` only after a
  `bot-ready` message.
- Pipecat's current official runner accepts both `request_data` and
  `requestData`, confirming the installed client's camel-case request envelope.
- ExWebRTC 0.17.0 is the current Hex release. Data channels require the optional
  ExSCTP dependency; Rust is installed on this host. ExWebRTC's official WHIP
  example gathers candidates after setting the local answer and then returns
  the updated local description.

## Decisions

- WebRTC and RTVI processes belong to `vxpipe_gateway`; the call engine receives
  only protocol-neutral participant admission.
- The browser will receive an opaque, expiring session credential from a
  separate room-session endpoint and pass it in Pipecat's
  `webrtcRequestParams.requestData`.
- The HTTP offer endpoint will implement both `POST` offer/answer and `PATCH`
  trickle ICE because the installed client does not wait for ICE gathering by
  default.

## Progress

- Created this labnote before implementation.
- Added a protocol-neutral `JoinParticipant` command, participant snapshot, room
  participant supervisor, and participant authority. The room authority
  serializes admission and monitors the participant; killing the room authority
  tears down the participant with the incarnation.
- Added gateway session and WebRTC supervision trees. Sessions are opaque,
  single-use, bound to a participant and room incarnation, and expire after five
  minutes by default. The first expiry-window test failed against the initial
  30-second value as expected, then passed after the default was corrected.
- Added `POST /api/rooms/:room_id/sessions`, `POST /api/rtvi/offer`, and
  `PATCH /api/rtvi/offer`. The offer endpoint consumes the session from Pipecat
  `requestData`, returns the gathered SDP answer, and accepts trickled client ICE
  candidates.
- Added the minimum RTVI codec. It answers compatible 2.x `client-ready` with a
  correlated 2.1.0 `bot-ready`, rejects incompatible versions without killing
  the connection, and ignores Small WebRTC signalling and keepalive payloads.
- Updated the samples flow to create the room, obtain the participant session,
  and pass the returned offer endpoint and request data into the Pipecat
  `ConsoleTemplate`. A failed session request can be retried without attempting
  to recreate the already-open room.

## Barriers and workarounds

- ExDTLS could not build because `pkg-config` was absent even though Rust, Cargo,
  and the OpenSSL development package were present. Installing `pkg-config`
  allowed the dependency chain to compile.
- Starting ExWebRTC before the connection authority made the supervisor its
  controlling process, so peer events arrived as unexpected supervisor
  messages. The connection incarnation now starts a per-connection dynamic peer
  supervisor first; the connection authority then starts the peer through that
  supervisor with itself as controlling process from the outset.
- The integration-test peer initially delivered events to ExUnit's supervisor.
  Explicitly transferring the test peer to the test process made event ownership
  deterministic without sleeps.

## Verification

- Focused call-engine tests: 6 passing across room creation and participant
  admission/lifecycle.
- Gateway endpoint and codec tests: 12 passing before the WebRTC integration
  test was included.
- Real ExWebRTC integration: offer/answer, trickle ICE, data-channel readiness,
  RTVI readiness, single-use session replay rejection, connection teardown, and
  surviving room all pass.
- Samples tests: 2 passing; production build succeeds with only the existing
  large-chunk advisory.
- An unmodified Pipecat React client 1.13.0 connected in headless Chrome,
  received `bot-ready` advertising RTVI 2.1.0, and disconnected cleanly. No
  browser errors were reported. Desktop and mobile layouts were rendered and
  inspected.
- Incoming audio currently stops at the WebRTC boundary. Agent attachment,
  transcription, inference, synthesis, outbound audio, reconnection, production
  authentication, TURN, durability, and recovery remain outside this slice.
- Final umbrella verification passed: formatting, warnings-as-errors
  compilation, all 19 ExUnit tests, and the unused-lock check.
