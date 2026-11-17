# Validate platform MCP sessions

## Scope and method

- User authorized live lifecycle validation on `https://vitrum.vxpipe.com`, a
  temporary database-created admin with a random password, browser OAuth consent,
  and archival of the account afterward. The user separately approved a brief
  container restart and shortening expiry to accelerate the test.
- `bin/setup` completed in the main checkout. Existing unrelated documentation
  edits were preserved. No implementation, dependency, or global token-policy
  change was requested or made.
- Used Python `requests` as a small MCP wire client: DCR, S256 PKCE, browser
  consent via an isolated agent-browser Chrome session, loopback callback, code
  exchange, initialize, initialized notification, and tools/list. Each request
  used a fresh connection with `Connection: close`; no persistent stream was used.
- Generated the account password with `secrets.token_urlsafe(36)`. Credentials
  stayed in private temporary files. No secrets or user identifiers are recorded
  here. The forbidden live-provider environment file was not accessed.
- The production container has distributed RPC disabled. Separate release `eval`
  processes started only the repository through `Ecto.Migrator.with_repo` for
  bounded account/credential inspection and changes. No existing user was edited.

## Evidence

- Normal token responses reported `expires_in: 599` (integer time rounding).
  Persisted token timestamps differ by about 600 seconds, and grant timestamps
  differ by about 2,592,000 seconds (30 days).
- Sequential refresh: 200; new token tools/list: 200; old refresh replay:
  400 `invalid_grant`; new access token: 401; new refresh: 400 `invalid_grant`.
- Concurrent refresh on a separate grant: one 200, one 400; the winning response's
  access token then returned 401. This reproduces the collision mechanism, not
  proof that the user's Codex installation actually races refresh requests.
- Existing session created at 12:19:41 UTC: after the approved restart, tools/list
  returned 404 at 12:22:46. A new initialize using the exact same access token
  returned 200, initialized returned 202, tools/list returned 200, and refreshing
  the original refresh token returned 200. No additional login was needed.
- Deployed ExMCP module in an isolated release-eval process: default ETS storage,
  idle TTL 3,600 seconds, cleanup interval 60,000 ms. Backdating only this isolated
  test session's last activity by 3,601 seconds and invoking cleanup rejected the
  session. Restarting only this isolated session-manager instance also lost its
  session. This was accelerated module verification, not an hour-long public test.

## Barriers and corrections

- Browser click completion does not guarantee completion of the loopback callback.
  Early consumers twice read token files before the session field was written.
  A newly requested restart-test session hit 502 during shutdown; the already
  established expiry-test session supplied the valid before/after restart evidence.
- Browser favicon requests initially entered the callback handler and produced
  harmless state-assertion failures. Successful OAuth callback records and saved
  credentials were unaffected; these are harness issues, not application failures.
- Docker restart was followed by a service-supervisor restart (NRestarts became 1,
  final container start 12:23:29 UTC). The first accelerated expiry check therefore
  observed 401 for expired access, successful refresh, then 404 for its old MCP
  session. Repeating after service stabilization separates token expiry from
  session loss. Public health recovered to HTTP 200.
- The original ten-minute wait was stopped at the user's suggestion. Only the
  selected temporary token's persisted `access_expires_at` was changed to now plus
  60 seconds; production issuance defaults and grant expiry stayed unchanged.
  Initial scratch probe labels containing “natural_expiry” refer to these
  accelerated checks and must not be interpreted as a full ten-minute wait.

## Completion

- Clean accelerated expiry at 12:25:20 UTC: expired access 401, refresh 200
  with normal `expires_in: 599`, same MCP session tools/list 200. No browser login.
- Temporary admin archived at 12:25:44 UTC; unrevoked browser sessions and OAuth
  grants both zero. Access rejected with 401; refresh rejected with 400
  `invalid_grant`; browser account navigation redirected to login.
- Final public health returned 200. Browser and callback listener closed;
  temporary credentials removed from host and container.
- User subsequently requested a configurable 60-minute lifetime and validation
  with the actual Codex client, also reporting similar Railway MCP reconnects.
  That follow-up is implementation work, not evidence that Codex caused the
  reproduced Python-client refresh collisions.
