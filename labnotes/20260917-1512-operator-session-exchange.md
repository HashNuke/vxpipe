# Operator session exchange

## Scope

Checkpoint 2 of the operator-login/admin milestone: exchange a durable login challenge for one
installation-wide browser session, protect the empty React admin mount, and verify the flow in a
real browser.

## Red/green evidence

- Added focused flow tests before the session/login implementation. They initially failed because
  the routes and grant did not exist.
- Added follow-up regression tests after GPT-6 Astra xhigh review for code filtering, router stop
  metadata, session-key independence, real loopback checks, trusted reverse-proxy handling,
  session rotation and referrer policy. The hardened tests failed against the first implementation
  and now pass.
- Focused Console authentication suite: 20 tests, zero failures.

## Decisions

- The user chose a backend-owned form: `GET /auth/login-token/:token` receives a Phoenix-filtered path
  parameter and renders it into the hidden field. No login JavaScript is required. Raw URL logging must
  stay disabled on this private route because the HTTP server and proxy necessarily receive its path.
- A pre-CSRF plug encrypts valid token/code values into a private envelope, then unconditionally
  redacts the parsed POST fields. The controller decrypts only after CSRF succeeds. Router completion,
  exception and error-rendered telemetry therefore contain no raw form credentials.
- Token and code form parameters are filtered in Phoenix logs and replaced with filtered values
  before router completion telemetry runs. Auth responses also set `no-referrer` and `no-store`.
- The operator grant includes an HMAC made with an independently derived operator-session secret.
  An explicit 64-byte operator secret is required to issue or accept a grant, so the checked-in
  development endpoint signing key cannot mint operator authority.
- Public HTTPS behind the documented same-host reverse proxy trusts `X-Forwarded-Proto` only when
  the actual peer address is loopback. Plain HTTP requires both a loopback peer and loopback Host.

## Browser evidence

- Inspected guidance, code-entry, generic unavailable, authenticated admin and sign-out states in
  headless Chrome at desktop and mobile sizes.
- Confirmed keyboard focus, native eight-digit validation, dark styling, responsive layout, React
  mount, secure session exchange and return to the token-free guidance page.

## Review

The first Astra review blocked commit on code logging, use of the public development cookie key,
forwarded HTTPS handling, Host spoofing, referrer leakage and POST error telemetry. Parameter
filtering, encrypted pre-CSRF handoff and the authenticated grant resolve the application boundaries.
The user explicitly selected the server-rendered path-token flow over a browser-fragment handoff.
