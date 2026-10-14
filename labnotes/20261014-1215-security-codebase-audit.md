# Security codebase audit

## Scope and constraints

Reviewed source at `a02f0114236a47ecb37e9b81517488e46b98c99b` across the umbrella, the
frontend, configuration and CI. Every check was offline. No live provider or carrier
calls ran, no provider credentials were used, and no deployed endpoints were probed.
`~/.config/vxpipe/live_providers.env` was not read. The deliverables are a milestone
of open issues plus failing reproduction tests in the suite. No fixes were requested.

## Progress

- **First attempt (stalled):** a Bubblewrap-sandboxed audit run in an external
  directory mapped the architecture and the coverage units. It stopped before
  hunting and produced no findings.
- **Restart, wave 1:** six read-only review agents ran at once. The user reported
  the machine was slow, so four were stopped. From then on, at most two review
  agents ran at a time:
  - wave 1 kept browser auth and identity, plus the Gateway machine API;
  - wave 2 covered the call engine and rooms, plus frontend, config and CI.
- **Parent review:** carrier webhooks (Twilio HMAC, Telnyx Ed25519), media tokens,
  the opening-audio address policy and the MCP target policy were reviewed
  directly.
- **Verification:** every agent candidate was checked against source before a
  test was written.

## Findings and evidence

The full detail is in
[the security audit remediation milestone](milestones/security-audit-remediation.md).

| ID | Severity | Reproduced on `a02f0114` |
| --- | --- | --- |
| SEC-1 | medium | After 30 failed logins with random emails from one forwarded client, the correct Superadmin password from another client returns 429. |
| SEC-2 | low | `password: [..]` raises `FunctionClauseError` in `Argon2Hasher.verify/2` for an existing account; an unknown account gets 401. |
| SEC-3 | low | Gateway prepare accepts a 100-year join-token TTL. |
| SEC-4 | low | The dev runtime config with `APP_HOST=192.0.2.10` and no `SECRET_KEY_BASE` loads without raising. |

Owner decisions, with no failing test:

- D-1: a fresh install trusts the first visitor as Superadmin.
- D-2: `tenants.write` installs demo specs with installation authority.

## Decisions

- **Tests:** each test asserts the secure behaviour and is tagged `:security_open`.
  The Console and Gateway `test_helper.exs` files exclude the tag, so the default
  suite stays green while the open issues stay one command away
  (`mix test --only security_open`).
- **Owner decisions:** the documented first-visitor bootstrap is not encoded as a
  failing test, because that would assert a design the user has not rejected.
- **Rejected candidates:**
  - Missing `Secure` cookie flag: Plug sets Secure on HTTPS, and
    `TrustedProxyScheme` runs before the session. An untagged regression test now
    guards this.
  - MCP loopback targets: only operator configuration can set them, and TLS
    `verify_peer` protects them.
- **First SEC-4 test attempt:** it failed for the wrong reason (`KeyError` on the
  gateway `trusted_call`). Merging the dev Gateway config, as
  `endpoint_origin_runtime_configuration_test.exs` does, fixed it.

## Verification

Focused runs:

- `mix test <file> --only security_open` in Console and Gateway shows the 4 expected
  failures, each for the intended reason.
- The default lane shows the Secure-cookie guard passing and the tagged tests
  excluded.

## Fixes (2026-10-14, after rebasing onto `5d815c85`)

- **D-2:** demo sample installation now requires `call_specs.write` on the demo
  tenant. This was committed separately, red then green.
- **SEC-1:** added `Vxpipe.Console.ClientAddress`. It trusts the last
  `X-Forwarded-For` entry only from a loopback peer, matching
  `TrustedProxyScheme`, and is used for setup, login and recovery throttling.
- **SEC-2:** `Sessions.login/4` treats a non-binary password as a counted failure,
  and `Argon2Hasher.verify/2` returns `false` for non-binaries.
- **SEC-3:** join-token TTL is capped at 86,400 s in Calls and in the Gateway. A new
  Calls test fails without the cap, which was checked by temporarily reverting it.
- **SEC-4:** the dev runtime raises when the listener is not loopback and there is
  no `SECRET_KEY_BASE`. Two runtime tests with network listeners now set a test
  secret.
- The `:security_open` exclusions were removed from the test helpers, since no
  open finding remains.
- **Verification approach:** focused tests ran per fix, and the root gates ran once
  at the end, at the user's request.
- **Left open:** the per-account lockout policy, and the unknown-user Argon2
  timing difference.
