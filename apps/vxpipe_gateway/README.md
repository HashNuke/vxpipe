# Vxpipe Gateway

The gateway OTP application owns Vxpipe's client-facing HTTP, transport, and
protocol boundaries. Its current HTTP surface exposes `GET /healthz`,
development room/session admission, and Pipecat Small WebRTC signalling:

- `POST /api/rooms`
- `POST /api/rooms/:room_id/sessions`
- `POST /api/rtvi/offer`
- `PATCH /api/rtvi/offer`

The offer transport completes RTVI 2.x readiness over the `chat` data channel.
In development it attaches the connection to a deterministic engine agent and
maps `send-text` commands to `bot-output` events followed by RTVI agent-speaking
boundaries. Typed participant boundaries also project to RTVI user
start/stop messages so rapidly submitted turns remain separate in unmodified
clients. Incoming Opus RTP is mapped to the call engine's protocol-neutral audio
frame, sent through its bounded media ingress, and projected back as RTVI
speaking and replacement-transcription messages. The committed transcript drives
the same deterministic agent. Deepgram Flux TTS returns raw 48 kHz mono
linear16; a per-connection bounded egress reframes and encodes it to Opus, then
paces 20 ms RTP packets onto an outbound audio track negotiated before the SDP
answer. RTVI bot start/stop and whole-segment completion messages follow the
paced packets. The default 500-packet queue covers ten seconds of audio and
applies bounded backpressure to longer provider bursts. Spoken outputs generated
while another is playing remain ordered at the RTVI boundary. Typed input with
`run_immediately: true` interrupts active and queued output, while false retains
FIFO behavior. Microphone RTP continues through bounded STT ingress during
output. A hosted provider speech-start signal invokes the same cancellation path
with identity from the authenticated connection, then its committed transcript
drives the replacement response. The gateway does not run local VAD or
server-side acoustic echo cancellation and does not project synthetic mute
events merely because agent output is active.

Configure the application from the host project's application environment:

```elixir
config :vxpipe_gateway, Vxpipe.Gateway.Application,
  http: [
    enabled: true,
    ip: :loopback,
    port: 4000,
    webrtc: [
      ice_servers: [],
      candidate_gathering_timeout_ms: 1_000,
      maximum_audio_packets: 500
    ],
    room_creation: [enabled: false],
    cors: [
      allowed_origins: ["https://client.example.test"],
      allowed_methods: ["GET", "POST", "PATCH", "OPTIONS"],
      allowed_headers: ["content-type", "authorization"],
      allow_credentials: false
    ]
  ]
```

The application reads this setting once during startup and passes the HTTP
options into its supervision tree. Embedded callers can instead supervise
`Vxpipe.Gateway.HTTP.Supervisor` directly with the same HTTP options.

The repository's development configuration enables a deterministic text agent,
room creation, and participant admission with a fixed development principal so
the browser can exercise the complete path without claiming to implement
authentication. It issues an opaque, five-minute, single-use session for the
offer request.
Production and embedding configurations must leave this disabled until a real
authenticated principal is attached at the gateway boundary.

ExWebRTC and ExSCTP belong to this application because no WebRTC types cross the
call-engine API. Building their native dependency chain requires Rust,
`pkg-config`, and OpenSSL development headers.
