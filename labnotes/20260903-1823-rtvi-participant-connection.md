# RTVI participant connection

> Relocated from `docs/rtvi-participant-connection.md` on 2026-10-09. First recorded source commit: `e45fc002a039` (2026-09-03T18:23:58+00:00).
> Historical research/implementation archive. Original status, failures, proposals and acceptance claims below describe their recorded checkpoints; relocation does not update or reapprove them.
> Related task records: [20260903-1740-connect-rtvi-participant](20260903-1740-connect-rtvi-participant.md).
> Maintained contracts/progress: [architecture](../docs/architecture.md), [native-webrtc-testing](../docs/development/native-webrtc-testing.md). Detailed contract refinements are deferred to the separately reviewed documentation work.

Status: Implemented bounded vertical slice

## Decision

Vxpipe admits a browser participant through the protocol-neutral call engine,
then creates its Pipecat Small WebRTC connection entirely inside
`vxpipe_gateway`. The connection supports the minimum current RTVI 2.x readiness
exchange without introducing Pipecat, WebRTC, JSON, or RTVI types into
`vxpipe_call_engine`.

This is one gateway mechanism. Other client protocols and transports can issue
the same participant-admission command and supervise their own connections
without changing the call-engine participant model.

## External flow

```text
Browser                 Gateway                         Call engine
   | POST /api/rooms       |                                 |
   |---------------------->| CreateRoom                      |
   |                       |-------------------------------->|
   |<----------------------| public room snapshot            |
   | POST /api/rooms/:id/sessions                            |
   |---------------------->| JoinParticipant                 |
   |                       |-------------------------------->|
   |                       |<--------------------------------|
   |<----------------------| participant + one-use session   |
   | POST /api/rtvi/offer  |                                 |
   |---------------------->| claim session; start WebRTC     |
   |<----------------------| SDP answer + connection ID      |
   | PATCH /api/rtvi/offer |                                 |
   |---------------------->| trickle ICE candidates          |
   | client-ready -------- data channel                      |
   |<------- bot-ready ---- data channel                      |
   | close channel -------->| stop connection incarnation     |
   |                       | room and participant remain     |

   |<------- peerLeft ----- data channel (if room ends)       |
   | disconnects --------->| bounded connection shutdown     |
   |                       | room is already ended           |
```

`POST /api/rooms/:room_id/sessions` is a development admission endpoint. It
requires the configured `rooms:join` scope, admits a human participant to the
live room incarnation, and returns an opaque session ID plus transport
parameters. The browser does not choose or assert its tenant, actor,
incarnation, or participant identity.

The session is held by a temporary gateway process, expires after five minutes
by default, and can be claimed atomically only once. It is a registry-backed
development credential, not a signed token. Production admission still needs
real authentication, authorization, rate limits, and a deployment-specific
credential policy.

## Ownership and supervision

The call engine adds this room-owned subtree:

```text
RoomIncarnationSupervisor
├── RoomParticipantSupervisor (DynamicSupervisor)
│   └── ParticipantAuthority (temporary)
└── RoomAuthority (temporary, significant)
```

Only `RoomParticipantSupervisor` starts participant authorities. The room
authority serializes admission, monitors participants, and prevents duplicate
live participant IDs. Terminating the significant room authority tears down the
room incarnation and its participants.

The gateway adds independent session and transport trees:

```text
Vxpipe.Gateway.Supervisor
├── SessionRegistry
├── SessionSupervisor (DynamicSupervisor)
│   └── Session (temporary, expiring, single-use)
├── WebRTC.Registry
└── ConnectionSupervisor (DynamicSupervisor)
    └── ConnectionIncarnationSupervisor (temporary)
        ├── ConnectionPeerSupervisor (DynamicSupervisor)
        │   └── ExWebRTC.PeerConnection (temporary)
        └── Connection (temporary, significant)
```

The connection authority is the ExWebRTC controlling process from peer startup,
so media, data-channel, ICE, and lifecycle events reach the process that owns
the protocol state. A closed chat data channel, failed/closed peer connection,
or peer-process exit stops the connection authority. Because it is significant,
the entire connection incarnation shuts down instead of leaving transport
workers behind. The later deterministic text-turn slice also attaches this
process to the room authority with mutual monitoring. A browser disconnect does
not terminate the room or participant, while room or participant loss now
terminates the stale transport. When an established RTVI channel still exists,
room loss first sends the Small WebRTC `peerLeft` signalling message and gives
the client a bounded 250-millisecond grace period to disconnect; connection loss
or expiry of that grace period then stops the transport subtree. Failure to send
the best-effort signal never keeps a stale connection alive.

## Compatibility contract

The offer endpoint accepts the current Pipecat Small WebRTC request shapes:

- `POST /api/rtvi/offer` with `sdp`, `type: "offer"`, and a session ID under
  either `requestData` or `request_data`;
- a response containing `pc_id`, `sdp`, and `type: "answer"`; and
- `PATCH /api/rtvi/offer` with `pc_id` and the client's trickled ICE candidates.

The ordered data channel is named `chat`. Small WebRTC signalling messages and
string keepalives are transport concerns and are ignored by the RTVI codec. A
valid `rtvi-ai` `client-ready` for major version 2 receives a same-ID
`bot-ready` advertising RTVI 2.1.0. Other major versions and invalid semantic
versions receive `error-response`; they do not crash the connection.

The gateway uses ExWebRTC 0.17 and ExSCTP 0.1.3. ExSCTP enables the data channel;
its native dependency chain requires a Rust toolchain, `pkg-config`, and OpenSSL
development headers when dependencies are compiled.

## Alternatives rejected for this slice

- Putting WebRTC in the call engine would couple the protocol-neutral domain to
  one client transport and reverse the intended dependency direction.
- Treating a public room ID as connection authority would allow possession of a
  non-secret identifier to bypass admission and would not bind the connection
  to a participant or incarnation.
- Sending the session in a query string would make it more likely to appear in
  browser history and access logs. Pipecat already provides `requestData` for
  offer metadata.
- Starting peer processes directly from request handlers would bypass an owning
  dynamic supervisor and leave failure cleanup ambiguous.
- Adding a Python Pipecat server would duplicate runtime ownership instead of
  proving that the Elixir gateway can implement the client-facing protocol.
- Adding speech providers in the same checkpoint would obscure whether failures
  belong to admission, signalling, WebRTC, RTVI, or the provider pipeline.

## Implications and next boundary

This slice proved connection compatibility rather than conversational
usefulness. The next planned text slice has since been implemented in
[`deterministic-text-turn.md`](20260903-1851-deterministic-text-turn.md). Incoming audio is
still accepted without being routed to a capability, and the server emits no
speech, transcription, model, or audio output.

Reconnection is also deliberately absent. A claimed or expired session cannot
be reused; a later reconnection policy must issue a new connection credential
and decide whether it reuses the participant or admits a replacement.
An ended room is not a temporary transport failure: `peerLeft` lets an
unmodified client complete its normal disconnect transition instead of retrying
the consumed session. The development Console discards that terminal
connection view and returns to its create-room page, so its only offered recovery
starts a new call.

## Verification evidence

- Focused call-engine tests cover public participant snapshots, duplicate
  admission, admission to a missing room, and participant teardown with the room
  incarnation.
- Gateway endpoint tests cover the bound session response and its practical
  expiry window.
- Codec tests cover current RTVI readiness, unsupported versions, signalling,
  and keepalive handling.
- A real ExWebRTC integration test performs offer/answer, trickle ICE, opens the
  data channel, completes readiness, rejects session replay, closes the
  connection, and confirms the room remains registered.
- A second real ExWebRTC boundary test ends the monitored room, receives the
  exact `signalling/peerLeft` message on the established channel, and observes
  the gateway connection terminate after delivery.
- The unmodified Pipecat React client 1.13.0 was exercised in headless Chrome.
  It reached connected and agent-ready states, reported server RTVI 2.1.0, and
  returned to disconnected without browser errors. The creation and console
  views were inspected at desktop and mobile viewports.
- A rendered durable Gemini/Morse call invoked platform hangup, received
  `peerLeft`, returned directly to the create-room view without a retry or HTTP
  409, and passed desktop/mobile overflow, browser-error, and WCAG A/AA checks.
