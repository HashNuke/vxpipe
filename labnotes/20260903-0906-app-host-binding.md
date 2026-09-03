# APP_HOST binding

## Goal

Allow the development applications to use a caller-supplied `APP_HOST`, with a
resolvable machine FQDN as the motivating case.

## Current boundary

- The Vite samples application is currently the only application in the
  umbrella development stack that opens a network listener.
- The `gateway` application is an empty OTP supervision skeleton. It receives
  `APP_HOST` in its environment through Goreman, but there is no gateway HTTP,
  WebSocket, or WebRTC listener to bind yet.
- The implementation therefore applies the bind behavior to Vite and uses the
  same hostname for its gateway proxy. The gateway listener must consume this
  contract when that listener is added.

## Decision

- In HTTP mode, `APP_HOST`, when non-empty, is Vite's exact bind hostname and
  the host portion of the default gateway proxy target on port 4000.
- `VXPIPE_GATEWAY_URL` remains the explicit proxy override.
- With no `APP_HOST`, preserve the existing wildcard Vite bind and loopback
  gateway proxy.
- Remove the hard-coded `--host 0.0.0.0` Procfile argument so it cannot override
  Vite's environment-based configuration.
- Add only the configured hostname to Vite's host allowlist. Do not enable the
  unsafe allow-all setting.
- A focused configuration test was tried during implementation and removed as
  unnecessary. This configuration-only change uses direct process verification
  under the repository's configuration exception.
- HTTPS mode uses foreground Tailscale Serve rather than publishing Vite
  directly. `bin/dev` derives the local machine FQDN, binds Vite to
  loopback, and asks Goreman to manage the TLS terminator on port 5173.
- HTTPS is the default development mode. `bin/dev --http` provides an explicit
  local troubleshooting escape hatch, while `--https` remains an accepted alias.
- Tailscale Serve is scoped to the tailnet. Tailscale Funnel is deliberately not
  used because it exposes services publicly.
- The Tailscale certificate hostname is recorded publicly through Certificate
  Transparency, while network access to the service remains private to the
  tailnet and its access policy.

## Verification

- `npm run build --prefix samples` passed TypeScript checking and the Vite
  production build. The existing development-only large-chunk advisory remains.
- `bash -n bin/dev` passed.
- Goreman reported a valid Procfile containing the `https`, `samples`, and
  `vxpipe` processes.
- FQDN discovery passed against the local `tailscale status --json` response,
  with the terminal DNS dot removed and without logging the hostname.
- A live `APP_HOST=localhost bin/dev` smoke test bound Vite to the
  hostname-resolved loopback address, started exactly the `vxpipe` and `samples`
  Goreman processes, and returned HTTP 200. A separate existing listener already
  occupied the same IPv4 port; both listeners coexisted, and only the smoke-test
  process was stopped.
- The HTTPS process was not activated during verification because doing so
  changes the machine's Tailscale Serve state. Activation remains an explicit
  `bin/dev` operation.
- `mix format --check-formatted` passed.
- `mix compile --warnings-as-errors` passed.
- `mix test` passed with four umbrella tests.
- `mix deps.unlock --check-unused` passed.

## References

- Current Vite `server.host` and `server.allowedHosts` documentation.
- Current Tailscale Serve CLI, HTTPS setup, and local development-server
  documentation.
