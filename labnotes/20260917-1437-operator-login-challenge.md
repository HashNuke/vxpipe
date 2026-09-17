# Operator login challenge

## Scope

Checkpoint 1 of `operator-login-and-admin-dashboard.md`: persist and issue a short-lived operator
login challenge through `mix vxpipe.login`. This checkpoint does not add browser exchange or
operator sessions.

## Decisions

- Console owns the Mix task and external-origin validation. Calls owns challenge generation and a
  repository-neutral port. Persistence owns the Ecto schema and atomic database decision.
- The emitted token contains 32 random bytes encoded as unpadded base64url. The eight-digit code is
  sampled uniformly with rejection sampling, preserving leading zeroes.
- The database stores SHA-256(token) and a domain-separated HMAC verifier over the token digest and
  exact submitted code. Console first derives a dedicated challenge secret from an explicit
  deployment secret.
- The explicit deployment secret is separate from the checked-in development endpoint secret.
  `SECRET_KEY_BASE` must contain at least 64 bytes to satisfy both challenge and signed-cookie
  requirements. Production always uses it; development requires it before login issuance.
- Persistence samples its clock after acquiring `FOR UPDATE`. Incorrect submissions commit their
  increment rather than rolling it back. The fifth failure exhausts the challenge.
- HTTP is permitted only for the literal loopback hosts `localhost`, `127.0.0.1`, and `::1`.
  HTTPS hostnames must be syntactically valid DNS names or IP addresses. URL userinfo, query,
  fragments, non-root paths and duplicate options are rejected.

## Red-green evidence

- Calls tests first failed with the workflow modules absent, then with the old direct HMAC and
  malformed-code rejection behavior. Four focused tests now pass.
- Persistence tests first failed with the schema/store absent. Eight focused storage/durability
  tests now pass, including two concurrent correct submissions, restart persistence, expiry,
  five-attempt exhaustion, consumed state, unavailable Repo and a transactionally hidden table.
- Console tests first failed with configuration/task modules absent, then exposed unsupported URL
  options, malformed hosts, short endpoint secrets and missing application startup. Fourteen focused
  configuration/runtime/task tests now pass.

## Review corrections

The first GPT-6 Astra xhigh review blocked the commit. It found that the task did not start
Persistence, malformed hosts and URL components were accepted, 32-byte endpoint secrets could fail
Plug cookie sessions, the public development secret could authorize challenges, and restart evidence
did not prove the remaining attempt budget. Each finding was reproduced or captured by a focused
test and corrected before the follow-up review.

## Verification

- `apps/vxpipe_calls`: 89 tests, zero failures.
- `apps/vxpipe_persistence`: 144 tests, zero failures, 11 excluded integration tests.
- `apps/vxpipe_console`: 151 tests, zero failures, 1 excluded integration test.
- `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`, and
  `mix deps.unlock --check-unused` pass from the umbrella root.
- The full umbrella run completed with one unrelated Gateway timing failure: the Telnyx custom-URL
  destination-loss handoff missed its source-recovery speech deadline. The same line-selected set of
  five generated scenarios passed immediately in isolation (5 tests, zero failures, 8 excluded).
- The follow-up GPT-6 Astra xhigh review found no remaining implementation blocker after the listed
  corrections.
