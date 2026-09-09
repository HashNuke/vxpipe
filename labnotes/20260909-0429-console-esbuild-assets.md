# Console esbuild assets

## Objective

Move the existing Console-owned React sample from a separately listening Vite
development server to Phoenix's esbuild asset integration. Keep the responsive UI,
Pipecat dependencies, gateway ownership and one shared Console endpoint unchanged.

## Decisions

- Add the `esbuild` Hex package to `vxpipe_console` and configure one
  `:vxpipe_console` profile for `src/main.tsx`.
- Keep React and the existing Node dependency lockfile. Vitest remains test-only;
  it does not serve or build application assets.
- Track the small SPA index at `priv/static/index.html`. Generate stable
  `priv/static/assets/app.js` and `app.css`, ignore those generated files, and use
  revalidation rather than immutable caching for their stable names.
- Fail the root request with 503 when the index or either compiled bundle is absent.
- Supervise the esbuild watcher and Phoenix LiveReload from the Console endpoint.
  Register `Phoenix.CodeReloader` as a Mix listener for both umbrella-root and direct
  child development commands.
- Make the Console endpoint the only development web server. Phoenix/Bandit serves HTTPS,
  the React assets, and mounted gateway routes together on Tailscale port 4000. Remove
  Caddy, port 5174, the frontend proxy and the custom Vite shutdown process.
- Use the server-issued RTVI offer endpoint in the session response. Remove the
  browser build-time offer override and frontend environment file.
- Preserve `APP_HOST`: default HTTPS derives the hostname and address from Tailscale,
  provisions an ignored runtime certificate, and binds Phoenix directly. HTTP mode binds
  Phoenix to the resolved configured host or wildcard IPv4 when it is absent.

## Red-green evidence

The first `bash test/bin/dev_test.sh` red run failed because `bin/dev --http`
reported that npm was missing instead of reaching the expected Watchman boundary.
That proves the old Node server precondition was still present. After removing the
Node/npm runtime checks, the shell integration test passed.

After choosing direct Phoenix TLS, the next red run failed because the Procfile still
contained the Caddy child. The green contract proves default startup provisions the
Tailscale certificate, exports the direct-TLS listener settings, and asks Goreman to
start only the BEAM runtime and reload helper. HTTP mode does not require Tailscale.

The first focused Console endpoint run failed because the served index still pointed
at Vite's hashed `index-*.js` and `index-*.css` output rather than Phoenix-managed
`app.js` and `app.css`. After changing the tracked shell and esbuild configuration,
the six endpoint checks passed.

A subsequent release-boundary red test configured an existing index and a missing
compiled asset. It received 200, demonstrating that tracking the shell alone had
weakened the prior missing-build behavior. `PageController` now verifies all required
bundle paths before reading the shell. The focused suite passes seven tests.

## Runtime findings and workarounds

The first real `bin/dev --http` run built the assets but Phoenix warned that its code
reloader had no Mix listener. Adding the listener to the umbrella and Console project
settings removed that integration warning on the next HTTPS run.

An intermediate HTTPS run exposed Caddy at 5173 and Phoenix on loopback 4000. The final
one-port decision removed that reverse proxy. `bin/dev` now provisions the Tailscale
certificate without sudo, and the live stack exposes only Phoenix/Bandit with HTTPS on
the Tailscale address at port 4000. There is no loopback HTTP listener and nothing listens
on 5173 or 5174. `/healthz` succeeds over HTTP/2 on the HTTPS origin while the same request
to loopback HTTP fails to connect.

Headless Chromium loaded the esbuild bundle, rendered the unchanged create-room page
at 1440x900 and 390x844, created a room, and rendered the Pipecat console. One fresh
attempt reached RTVI client and agent `READY`, proving the new HTTP asset path did not
break the existing offer flow. Repeated later headless attempts failed ICE and caused
expected offer-retry 409/404 responses; those attempts are not counted as a successful
Morse media check. After moving TLS into Phoenix, a new browser pass repeated the desktop,
mobile, room-creation and initialized-console checks at the port-4000 HTTPS origin. Its
WebRTC retry hit the same ICE instability and is not represented as a one-port media success.
The required `agent-browser` command was unavailable, so rendered inspection used the
installed headless Chromium through its DevTools protocol and records that limitation.

## Verification so far

- `bash test/bin/dev_test.sh`: passed.
- `cd apps/vxpipe_console && mix test test/vxpipe/console/endpoint_test.exs`:
  seven tests, zero failures.
- `mix assets.test`: three tests, zero failures.
- `mix assets.build`: TypeScript passed; esbuild produced a 3.4 MB JavaScript bundle
  and 121.2 kB CSS bundle.
- `mix assets.deploy`: TypeScript passed; esbuild produced a minified 1.4 MB JavaScript
  bundle and 96.0 kB CSS bundle.
- Direct Phoenix HTTPS smoke check: one Tailscale listener on port 4000; health returned 200.
- Chromium render inspection: desktop, mobile, Pipecat console, and one fresh RTVI
  ready transition passed.
- `mix format --check-formatted`: passed.
- `mix compile --warnings-as-errors`: passed.
- `mix test`: call engine 137 tests, gateway 46 tests, and Console 20 tests passed;
  the configured integration exclusions remained excluded.
- `mix deps.unlock --check-unused`: passed.

`git diff --cached --check`, the staged path review, and the credential-pattern scan
passed. Commit and push remain pending for this checkpoint.
