# Caddy gateway configuration

## Goal

Replace the single-purpose Tailscale Serve development proxy with Caddy, add a
real gateway HTTP boundary with configurable CORS, and make OTP application
settings the canonical configuration interface. Development derives its allowed
browser origin from `APP_HOST`.

## Decisions

- Caddy is the default development HTTPS ingress on the machine's Tailscale IPv4
  address and port 5173. It routes `/api/*` and `/healthz` to the gateway on
  loopback and all remaining traffic to Vite on loopback port 5174.
- Vite retains its `/api` proxy only for `bin/dev --http`; its default upstream
  is now loopback rather than `APP_HOST`.
- Caddy terminates HTTP/WebSocket traffic only. Future WebRTC ICE-selected media
  and RTVI data-channel traffic will not traverse Caddy.
- `bin/dev` renders the Caddyfile to complete JSON before invoking Goreman,
  obtains sudo once, and runs only Caddy as root. The root process does not need
  `TS_PERMIT_CERT_UID` or application environment variables; Mix and Vite stay
  unprivileged. Caddy's admin endpoint and config persistence are disabled.
- `vxpipe_gateway` reads one namespaced application setting at startup and
  passes the HTTP options into its named HTTP supervisor. The same supervisor
  accepts options directly for embedding.
- The default listener is disabled, development enables it, and runtime
  configuration reads `APP_HOST` and `PORT`. Environment reads live in
  `config/runtime.exs`, as required by the repository guidelines; the branch is
  limited to the development configuration environment.
- The CORS contract uses exact configured origins and denies cross-origin access
  by default. Methods, headers, and credential behavior are OTP options.
- The generic OTP application and module names were changed to
  `vxpipe_gateway`/`Vxpipe.Gateway` and
  `vxpipe_call_engine`/`Vxpipe.CallEngine` while the generated applications were
  still small. Umbrella directory names were changed too because Mix requires
  them to match application names.
- The future Docker JSON file remains a deployment adapter into these same
  validated application settings. Implementing the JSON loader is outside this
  checkpoint.

## Red-green evidence

- Red: the focused gateway endpoint test failed because
  `Vxpipe.Gateway.HTTP.Endpoint` did not exist.
- Green: the endpoint tests pass for health, allowed preflight, configured
  methods and headers, disabled credentials, and a denied unconfigured origin.
- A first green run exposed incorrect test assertions that treated the empty
  header list as falsey. The assertions were corrected to compare with `[]`;
  gateway behavior was already correct.

## Barriers and workarounds

- An older development stack initially occupied port 5173, so the root-Caddy
  smoke test used port 5183. That stack had exited before the final `bin/dev`
  verification, allowing the real port 5173 path to be exercised.
- The initial host had no Caddy binary. The latest official release was v2.11.4;
  its Linux AMD64 archive was checked against both the GitHub release API SHA-256
  digest and the release checksum file's SHA-512 value, then installed root-owned
  in a system PATH directory.

## Verification evidence

- The focused gateway endpoint suite passed with three tests.
- Application runtime configuration preserved default HTTP/CORS settings,
  enabled the development listener, normalized a trailing dot from a synthetic
  `APP_HOST`, and produced the expected HTTPS origin on port 5173.
- A live gateway smoke test on an unused loopback port returned `200 ok` from
  `/healthz` and a `204` preflight response containing the configured origin,
  methods, and headers.
- `bash -n bin/dev` passed.
- Goreman reported a valid Procfile containing `caddy`, `samples`, and `vxpipe`.
- The official Caddy 2 image reported `Valid configuration` for `Caddyfile`.
- The installed v2.11.4 binary includes Caddy's standard
  `tls.get_certificate.tailscale` module. The runtime Caddy JSON validated as
  both the invoking user and root without preserving environment variables.
- A root Caddy smoke test on alternate tailnet HTTPS port 5183 obtained the
  trusted `.ts.net` certificate, proxied `/healthz` to the live unprivileged
  gateway, and proxied an allowed-origin preflight response over HTTP/2. The test
  processes and temporary alternate-port configuration were removed afterward.
- An unmodified `bin/dev` launch derived the machine's Tailscale identity,
  rendered and validated Caddy's JSON, and started the complete stack without
  Caddy or Tailscale environment setup. The tailnet HTTPS URL served the Vite
  page, returned `ok` from the gateway `/healthz`, and returned the exact-origin
  CORS headers from an `/api/rtvi/offer` preflight. Process inspection confirmed
  that only Caddy ran as root; Goreman, Mix, and Vite remained unprivileged. The
  verification stack then shut down cleanly with no listeners remaining.
- Both FQDN and IPv4 queries used by `bin/dev` succeeded against the local
  Tailscale status without printing either value.
- `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test`,
  and `mix deps.unlock --check-unused` passed from the umbrella root.
- `MIX_ENV=prod mix compile --warnings-as-errors` passed, including the empty
  production environment overlay and renamed applications.
- `npm test --prefix samples` passed through the active Mise Node installation.
- `npm run build --prefix samples` passed TypeScript and Vite production builds.
  The existing development-playground large-chunk advisory remains.
- `npm ls --prefix samples --depth=0` resolved all declared frontend
  dependencies. The non-interactive shell's stale Node path required invoking
  these checks through `mise exec`; this does not change repository behavior.
