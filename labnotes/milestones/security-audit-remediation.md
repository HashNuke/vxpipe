# Security audit remediation

Status: SEC-1 to SEC-4 and D-2 are fixed, with regression tests; D-1 is accepted. Final root gate evidence is below.
Audited source: `a02f0114` (clean worktree), 2026-10-14.
Labnotes: [security codebase audit](../20261014-1215-security-codebase-audit.md).

## Scope and method

Source-first review of the umbrella, the React Console, configuration, scripts and CI.
Every check ran offline: there were no live provider or carrier calls and no
deployed endpoints were probed. Each reproduction uses dummy principals with the
local test database sandbox, or plain function and config evaluation.

The review covered these surfaces:

- browser identity: login, sessions, roles, account and tenant administration;
- the Gateway machine API: API keys, call admission, join tokens, WebRTC sessions;
- carrier webhooks: Twilio HMAC and Telnyx Ed25519 checks, media tokens;
- outbound fetch policy: opening audio and MCP;
- real-time rooms and transfer authority;
- browser rendering;
- HTTP and runtime configuration;
- CI.

A candidate counts as a finding only when a lower-trust principal crosses a real
boundary and produces a concrete result.

## Reproductions

Each finding has a test that asserts the secure behaviour. These tests failed on the
audited tree and pass after the fixes. While findings were open, the tests carried
`@tag :security_open` and were excluded by default. The fixes removed the tag and the
exclusions, so they now run in the default suite.

| ID | Severity | File | Test |
| --- | --- | --- | --- |
| SEC-1 | medium | `apps/vxpipe_console/test/vxpipe/console/security_audit_login_test.exs` | failed logins from one client behind the proxy do not lock out other clients |
| SEC-2 | low | `apps/vxpipe_console/test/vxpipe/console/security_audit_login_test.exs` | a non-string password is rejected identically for existing and unknown accounts |
| SEC-3 | low | `apps/vxpipe_gateway/test/vxpipe/gateway/http/security_audit_join_token_test.exs` | rejects a join-token lifetime beyond one day |
| SEC-4 | low | `apps/vxpipe_console/test/vxpipe/console/security_audit_runtime_configuration_test.exs` | development refuses a non-loopback listener without SECRET_KEY_BASE |

Observed failures on `a02f0114`:

- SEC-1: 429 `rate_limited` for the correct Superadmin password.
- SEC-2: `FunctionClauseError` in `Argon2Hasher.verify/2`, which surfaces as HTTP 500 for the existing account, versus 401 for the unknown account.
- SEC-3: the prepare route accepts a 100-year TTL.
- SEC-4: `Config.Reader.read!/2` returns a config without raising.

## SEC-1: one anonymous client can lock every user out of login and recovery (medium)

- **Principal:** any anonymous visitor who can reach the public Console host.
- **Path:**
  - Production binds plain HTTP and serves `/auth/*` only when `conn.scheme == :https` (`operator_traffic.ex`).
  - `TrustedProxyScheme` grants HTTPS only to `remote_ip` 127.0.0.1 or ::1. Every working login therefore arrives from the same-host proxy's loopback address.
  - `UserAuthController.login/2`, `setup/2` and `recover/2` use `conn.remote_ip` as the throttling address.
  - `Sessions.login/4` calls `check_rate/5` before checking the credential.
  - `RateLimit` allows 30 attempts per address per 600 s, counted over all accounts by `IdentityAttemptStore`.
- **Result:**
  - About 30 failed logins with random emails every 10 minutes give one global bucket. Every user then gets 429, including a Superadmin with the correct password.
  - Browser recovery shares the bucket.
  - Separately, 10 failures lock any chosen account (`max_per_account`).
- **Invariant:** one source's failures must not deny other sources, and a correct credential must not be blocked by unrelated failures.
- **Fix:**
  1. Derive the client address from the last `X-Forwarded-For` hop only when the immediate peer is the trusted loopback proxy (the same rule as `TrustedProxyScheme`), and use it for setup, login and recovery.
  2. Consider letting a correct password bypass the address bucket, or replacing the hard block with per-account backoff.
- **Tasks:**
  - [x] Added `Vxpipe.Console.ClientAddress.for_throttling/1`. For a loopback peer it uses the last `X-Forwarded-For` entry; otherwise it uses `remote_ip`. `UserAuthController` uses it for setup, login and recovery. `client_address_test.exs` covers the forwarded, spoofed and malformed cases.
  - [ ] The account-lockout policy is unchanged: 10 failures per account in 10 minutes is still a hard block. Changing it to backoff needs an owner decision.
  - [x] Removed `:security_open` from the SEC-1 test. The focused Console auth tests (28) and the Identity suite (59) pass.

## SEC-2: a non-string password distinguishes existing accounts without throttling (low)

- **Principal:** an anonymous visitor.
- **Path:**
  - `UserAuthController.login/2` passes `params["password"]` through unchanged; JSON can send a number and a form can send `password[]=x`.
  - `Sessions.login/4` calls `hasher.verify/2` only after it has found an enabled user.
  - `Argon2Hasher.verify/2` matches only binaries, and its `rescue` does not cover a `FunctionClauseError` raised in the function head.
- **Result:**
  - An existing enabled email returns 500. An unknown or disabled email returns the intended 401 `invalid_credentials`.
  - The 500 path never reaches `record_attempt/4`, so probing costs no rate-limit budget.
  - Unknown and disabled users also skip Argon2 entirely, which leaves a weaker timing difference.
- **Invariant:** every failed login returns the same 401, is counted, and takes comparable time.
- **Fix:**
  1. Treat a non-binary email or password as `:invalid_credentials` in `Sessions.login/4` and record the attempt.
  2. Add a fallback `verify/2` clause that returns `false`.
  3. Call `Argon2.no_user_verify/0` for unknown and disabled users.
- **Tasks:**
  - [x] `Sessions.login/4` now rejects a non-binary password as a counted `:invalid_credentials` failure, and `Argon2Hasher.verify/2` has a fallback clause that returns `false`. Setup and recovery already reject such passwords in `Password.confirm/2`.
  - [x] Removed `:security_open` from the SEC-2 test.
  - [ ] Not done: the dummy Argon2 verify for unknown and disabled users, which would close the timing difference. It would need a new `PasswordHasher` callback.

## SEC-3: join-token lifetime has no upper bound (low)

- **Principal:** a holder of a tenant `:calls` API key, or a backend that forwards caller-chosen values.
- **Path:** `CallAdmissions.ttl_seconds/1` in the Gateway and `Admissions.token_ttl/1` in Calls both check only `>= 300`. `expires_at` is set to `issued_at` plus that TTL.
- **Result:**
  - A join token is a single-use bearer credential for a live call, but it can be minted to last for centuries, so a leaked unused token never expires.
  - Very large values push `expires_at` past PostgreSQL's range and return 500 instead of 400; only the requesting tenant is affected.
- **Fix:** set one maximum, for example 86_400 s, and enforce it in both validators; the domain check is authoritative.
- **Tasks:**
  - [x] Added an 86,400-second maximum in `Vxpipe.Calls.Admissions` and in the Gateway `CallAdmissions` validation. No API reference documents this field, so there was nothing to update.
  - [x] Removed `:security_open` from the SEC-3 test, and added the Calls test "rejects a join-token lifetime beyond one day". Without the cap it fails with `:join_token_conflict`.

## SEC-4: a development Console on a network address keeps the public development secret (low, dev profile)

- **Principal:** a network peer, on the LAN or tailnet, of a development Console started with a non-loopback `APP_HOST` and no `SECRET_KEY_BASE`.
- **Path:**
  - `config/dev.exs` sets `secret_key_base` to the public `"development-only-"` value, with `debug_errors: true`.
  - The `config/runtime.exs` dev block keeps it when `SECRET_KEY_BASE` is unset and binds the resolved `APP_HOST` address.
  - `env.sample` says the variable is required in this case, but nothing enforces that.
  - The operator-login secret is correctly withheld off loopback; the endpoint secret is not.
- **Result:**
  - Peers can forge anything signed with the endpoint secret (Phoenix tokens, LiveView signing) and can see debug error pages.
  - Browser sessions themselves are still validated against the database.
- **Fix:** in the dev block, raise when the listener is not loopback and `SECRET_KEY_BASE` is missing. Consider disabling `debug_errors` off loopback.
- **Tasks:**
  - [x] The `config/runtime.exs` dev block now raises "SECRET_KEY_BASE is required for a non-loopback development listener". `bin/setup` already writes a `SECRET_KEY_BASE`. Two runtime tests that configure network dev listeners now supply a test secret, and the provider runtime test also restores the variable.
  - [x] Removed `:security_open` from the SEC-4 test.

## Owner decisions

- [x] **D-1: a fresh production install trusts the first visitor as Superadmin. Accepted by the owner on 2026-10-14.**
  - **Path:**
    - `Bootstrap` documents "Fresh installs trust the first visitor".
    - `IdentityInstallationStore.require_pending/2` accepts `first_run` without a proof.
    - Production binds `0.0.0.0` on a public `APP_HOST`.
    - The README's `docker run -p 4000:4000` publishes the port on every interface.
  - **Residual risk:** until setup completes, whoever posts to `/auth/api/setup` first becomes Superadmin. The operator must finish setup immediately after first boot, or keep the port unreachable until then.
  - If this is revisited, the options are:
    - require the local setup proof whenever the listener is not loopback;
    - log a one-time setup token at boot;
    - change the README snippet to `-p 127.0.0.1:4000:4000`.
- [x] **D-2: `tenants.write` installed demo call specs with installation authority. Fixed on 2026-10-14.**
  - **Problem:** `AdminOnboardingController.install_samples/2` called `DemoSamples.install(InstallationOperator.authority(), tenant.key)` after checking only `tenants.write`. A custom-role holder could therefore publish call specs without `call_specs.write` for the demo tenant.
  - **Fix:** the controller now calls `UserAuthorization.authorize_tenant(principal, "call_specs.write", demo_tenant_key)` before installing and returns 403 `forbidden` when the check fails.
  - **Test:** "sample installation requires call-spec write access to the demo tenant" in `apps/vxpipe_console/test/vxpipe/console/admin_onboarding_endpoint_test.exs` failed first (422 instead of 403) and now passes.
  - **Follow-up:** the onboarding page shows its generic "Sample installation unavailable" message for a 403.

## Informational and non-security observations

- **Dev-profile room creation needs no credential.**
  - `config/dev.exs` gives the Console-mounted `/api/rooms` routes a fixed `rooms:create`/`rooms:join` principal.
  - Any peer of a tailnet-bound dev Console can start calls that spend the developer's provider credentials.
  - Production keeps `room_creation` disabled.
- **Admissions are released only for pending-transfer sessions** (`CallAdmissions`, failure branches). A participant whose session failed cannot be re-admitted. This affects reliability for the tenant's own call, not security.

## Rejected candidates

- **The session cookie lacks `Secure`.** False. `TrustedProxyScheme` runs before `BrowserSession`, and Plug marks cookies Secure on HTTPS connections. This is now guarded by the untagged test "the session cookie is marked Secure behind the trusted HTTPS proxy".
- **The MCP target policy admits `https://localhost` and `127.x`.** True in the ExMCP fork, but MCP endpoints come only from operator application config, never from tenants, and TLS `verify_peer` against public CAs blocks loopback services. No boundary is crossed.

## Areas reviewed and found sound

- **Tenant scoping:** Gateway routes are scoped by tenant down to SQL.
- **Machine keys:** `vxp_` and `vxop_` keys are SHA-256 digests, and tenant and installation keys are separated.
- **Join tokens:** claimed under `FOR UPDATE`, single-use, and bound to tenant, call and participant.
- **Capability identifiers:** generated with a CSPRNG.
- **WebRTC:** session claims are single-use, ICE requests are scoped to the connection, and RTVI and sideband messages are size-capped and bound to their room.
- **Twilio signatures:** the signed URL comes from server configuration, not the Host header, and comparison is constant-time.
- **Telnyx signatures:** Ed25519 with a 300 s timestamp window.
- **Media tokens:** 32 random bytes, single-use, with a TTL, bound to the leg and the tenant service.
- **Opening-audio fetch policy:** rejects non-public addresses, including IPv4-mapped IPv6, CGNAT, link-local and 6to4. The MCP fork resolves all DNS answers and pins one address.
- **Browser accounts:** role ceilings, last-Superadmin protection, session revocation on role, membership, password or disabled changes, and no session fixation.
- **CSRF and redirects:** CSRF covers every cookie-authenticated mutation. The return path is validated against a server-side allowlist.
- **Rendering:** React and HEEx output is escaped, with no `raw`, `innerHTML` or markdown HTML. `frame-ancestors 'self'` is set.
- **Call engine:** a model can only name a transfer target from its binding, and the authorizer pins tenant, room, incarnation and source capability. Dial numbers come only from the spec or baseline API variables, in E.164 form. Human hand-off attach and control are bound to the attempt, the connection and the deadline. Private briefings never reach transcripts. Tool results go only to the triggering source. Room lookups are keyed by tenant. Shared caches are bounded and keyed by tenant.
- **CI and secrets:** CI uses `contents: read` and no `pull_request_target`. Production requires a `SECRET_KEY_BASE` of at least 64 bytes, and the credential keyring rejects placeholder keys.

## Acceptance

- [x] SEC-1 to SEC-4 fixed, with their tests untagged and green.
- [x] D-1 accepted as designed; D-2 fixed, with a regression test.
- [ ] Root completion checks pass (`mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`, `mix test`, `mix deps.unlock --check-unused`).
