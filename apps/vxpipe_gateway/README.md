# Vxpipe Gateway

The gateway OTP application owns Vxpipe's client-facing HTTP and protocol
boundaries. Its current HTTP surface exposes `GET /healthz`; RTVI signaling is a
future checkpoint.

Configure the application from the host project's application environment:

```elixir
config :vxpipe_gateway, Vxpipe.Gateway.Application,
  http: [
    enabled: true,
    ip: :loopback,
    port: 4000,
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
