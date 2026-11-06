# Review MCP renewal

- Next checkpoint follows the browser-flow backend: machine grant acquisition,
  durable renewal coordination, current credential resolution and OAuth tool refresh.
  Runtime transport provider, catalog/compiler cutover and UI remain separate.
- Independent adversarial source review found that machine acquisition computes
  token expiry after MCP checking; renewal computes it after exchange. Both need
  conservative pre-request anchoring with a controlled clock. This matches the
  preceding browser callback fix.
- Review also found no aggregate renewal admission: per-connection durable claims
  do not bound concurrent requests across many saved connections. Proposed repair
  admits before durable claim through a Console-owned bounded runner port; Calls
  retains claim/completion/failure responsibility. Busy work must not consume a
  claim, and late worker results must not persist tokens.
- Caller death after token redemption deliberately leaves the durable ambiguity
  fence. Do not retry the old refresh token or return a potentially invalid old
  access token; require explicit reconnect after claim expiry. The reviewer found
  no production token-I/O owner leak and accepted this existing lifecycle policy.
- Scope review identified a transport projection assertion in the runtime resolver
  tests that must move to the later transport checkpoint. Keep the nine HTTP/database
  renewal cases separate from the eight browser cases already prepared for commit.
- Browser checkpoint committed as `9b8d859a` after clean adversarial review and all
  root gates (4,875 tests, zero failures). New controlled-clock and real-store
  admission regressions then reproduced six failures in eleven focused cases.
- Added the Console renewal runner port around Calls-owned claim/exchange work.
  Tagged admitted outcomes distinguish claim failure from accepted token results;
  only accepted results reach Calls-owned complete/fail storage operations.
  Eight slots and a fifteen-second limit apply across connections, without a tenant
  cooldown. Busy work creates no durable claim. Both expiry paths now anchor before
  their token request. All eleven focused cases pass, including two-tenant
  saturation, caller death, timeout and queued late-success persistence rejection.
- Moved the transport projection test to its later checkpoint and added registered
  renewal-supervisor restart coverage. Broader verification and final review remain
  pending.

- Source re-review of the fixes reports no new blocker. It clarified that held
  injected requests prove orchestration cleanup, not physical token-socket closure;
  production continues to use the existing synchronous SecureHTTP boundary.
- Focused Calls group passes twelve tests. The combined Console browser/renewal
  group passes thirty-one tests, including all fourteen renewal HTTP/database and
  persistence-boundary cases. Full MCP (165), Calls (314) and Console (494) suites
  pass, as do format, warnings-as-errors compile, strict Credo and unused-dependency
  checks. These suites ran against the broader worktree; the independent exact-index
  review separately confirmed that this twenty-eight-file checkpoint has complete
  dependencies and no transport/compiler/patch/UI dependency. It reported no
  actionable findings. The full umbrella result remains the preceding browser
  checkpoint's 4,875-test pass; no new full umbrella run is claimed here.
