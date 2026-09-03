# Vxpipe Gateway

The gateway OTP application owns Vxpipe's client-facing HTTP, transport, and
protocol boundaries. Its current HTTP surface exposes `GET /healthz`,
development room/session admission, and Pipecat Small WebRTC signalling:

- `POST /api/rooms`
- `POST /api/rooms/:room_id/sessions`
- `POST /api/rtvi/offer`
- `PATCH /api/rtvi/offer`

The offer transport completes the minimum RTVI 2.x readiness exchange over the
`chat` data channel. Incoming RTP is accepted but not yet routed to a speech or
agent pipeline.

Configure the application from the host project's application environment:

```elixir
config :vxpipe_gateway, Vxpipe.Gateway.Application,
  http: [
    enabled: true,
    ip: :loopback,
    port: 4000,
    webrtc: [ice_servers: [], candidate_gathering_timeout_ms: 1_000],
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

The repository's development configuration enables room creation and
participant admission with a fixed development principal so the browser can
exercise the complete path without claiming to implement authentication. It
issues an opaque, five-minute, single-use session for the offer request.
Production and embedding configurations must leave this disabled until a real
authenticated principal is attached at the gateway boundary.

ExWebRTC and ExSCTP belong to this application because no WebRTC types cross the
call-engine API. Building their native dependency chain requires Rust,
`pkg-config`, and OpenSSL development headers.
