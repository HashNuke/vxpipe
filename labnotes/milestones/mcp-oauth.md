# MCP OAuth authorization

Status: durable credentials and delegated authority implemented; browser flow and
OAuth-only MCP cutover in progress. OAuth is not yet enabled.

Prerequisites: [Platform MCP endpoint](platform-mcp-endpoint.md),
[Console authentication](console-authentication-and-user-management.md).
Design: [MCP OAuth](../../docs/mcp-oauth.md),
[existing MCP protocol/tools](../../docs/platform-mcp.md),
[Identity policy](../../docs/console-authentication-and-authorization.md).

User contract: make Vxpipe the OAuth provider for MCP, replace MCP API-key auth,
retain ExMCP, use Boruta if experiments establish fit, avoid overengineering,
implement and independently review small checkpoints, commit each usable chunk.
Notify through pushnotify after checkpoints and completion with estimated work
remaining. Percentages estimate effort, not the proportion of checked boxes.

## Approved scope

- All existing MCP tools/access levels use delegated user permissions.
- Public HTTP API keys and browser sessions keep their current behavior.
- Public clients, code + S256 PKCE, rotating refresh, DCR, discovery and revocation.
- One `mcp` scope delegates approved user authority, never grants extra permissions.
- Existing Console login plus consent and connected-client revocation.
- No OIDC/federation, confidential clients, machine OAuth grants or outbound CIMD
  fetching in this slice; document the DCR-only onboarding limitation.
- Local deterministic tests and reference-client acceptance; no live providers or
  Lean proofs/work, per the user's explicit instruction.

## Checkpoint 1: prove the protocol and review the plan (10%)

- [x] Inspect existing ExMCP/authentication and Identity/Persistence boundaries.
- [x] Inspect pinned stable Boruta 2.3.8 source and current MCP requirements.
- [x] Run checkout setup; dependencies/assets/dev and test migrations succeed.
- [x] Run a small reproducible real-Boruta experiment for code/S256 exchange,
  wrong verifier and custom storage context integration; distinguish source
  observations from runtime evidence.
- [x] Record package/dependency compatibility and concrete integration boundaries.
- [x] Independently review this milestone for missing contracts/dependency order;
  resolve findings and record review separately below.
- [x] Commit the researched design, milestone and probe evidence.

## Checkpoint 2: durable OAuth grants and token exchange (25%)

Runnable slice: local code exchange/refresh through real Boruta and PostgreSQL,
without exposing OAuth routes yet.

- [x] Red-test public client profile, exact redirects, S256-only, resource binding,
  unsupported fields/scopes/grants, and secrets absent from persisted rows/errors.
- [x] Pin Boruta and configure narrow contexts; no generated full OAuth/OIDC app.
- [x] Add bounded client/grant/code/token persistence and migrations.
- [x] Implement code consumption and refresh rotation atomically; red-test racing
  exchanges, replay-family revocation that commits on error, and rollback on failure.
- [x] Add user authorization version and compare role identity/revision; cover all
  existing invalidation paths including recovery and disable/reactivate. Increment
  in IdentityUserStore's session-invalidation path and IdentityInstallationStore's
  credential recovery; role changes retain the existing role revision mechanism.
  User version storage/invalidation is implemented and independently reviewed;
  grant comparisons are verified at issuance, exchange, refresh and access.
- [x] Implement revocation/expiry/cleanup and establish concrete durable quotas.
- [x] Verify wrong-client/resource/verifier requests cannot revoke a valid grant.
- [x] Independently review, run relevant tests, update evidence and commit.

## Checkpoint 3: delegated user authority (20%)

Runnable slice: a locally issued OAuth token authenticates as an explicitly
delegated user and exercises shared operations directly.

- [x] Red-test browser/OAuth mutually exclusive Principal provenance and stable
  grant identity; extract common trusted principal construction.
- [x] Intersect approved/current authority; apply tenant ceiling before built-in
  directory shortcuts. Check read-only, member, Admin and Superadmin behavior.
- [x] Revalidate and audit OAuth account writes inside their transaction; reserve
  grant attribution fields against injection and preserve account hierarchy.
- [x] Extend per-tool discovery/invocation to real user read/write permissions;
  preserve all 17 schemas/results and shared domain operations.
- [ ] Verify HTTP API-key and browser regressions; independently review and commit.

## Checkpoint 4: discovery, login and consent (25%)

Runnable slice: a local client discovers, registers, logs in, consents, exchanges,
refreshes and revokes using HTTP, while MCP cutover remains gated.

- [x] Red-test trusted issuer/resource and prefixed metadata construction;
  public discovery routes and bounded DCR/token/revoke routes.
- [x] Rate-limit and bound records/requests; fail closed on storage/config errors.
- [ ] Implement browser-bound expiring authorization transactions, login resume,
  CSRF-protected consent approval/denial and one-time completion. Approve/deny the
  current authority without a new permission editor; approved all-tenant grants
  include future tenants, finite assignments remain a snapshot. Reject/restart on
  user/version/role drift between rendering and approval, checked atomically.
- [ ] Render concise consent with client/callback and authority; add connected
  clients and revoke action to Account using the existing login/session design.
- [ ] Test malformed/duplicate params, unsafe redirects, forged/replayed consent,
  changed account while consent is pending, untrusted host and no secret logging.
- [ ] Inspect desktop/mobile rendered consent/account states with agent-browser.
- [ ] Independently review, update evidence and commit.

## Checkpoint 5: OAuth-only MCP cutover and acceptance (20%)

- [ ] Red-test OAuth Bearer validation/challenge and protected-resource metadata.
- [ ] Replace MCP key authentication; do not change public HTTP credential modes.
- [ ] Bind MCP sessions to the grant; refresh keeps a session, another grant cannot
  reuse it, revoked/expired/disabled principals cannot use any session operation.
- [ ] Run pinned SDK flow across real mounts and representative all-17-tool
  operations with local stores/calls, including denied and read-only cases.
- [ ] Update configuration/examples/docs and session-reconnection migration notes.
- [ ] Independent final review; resolve findings with focused red/green evidence.
- [ ] All root gates pass: format, compile warnings-as-errors, strict Credo,
  default tests, unused dependencies. Relevant frontend/browser checks pass.
- [ ] Mark this milestone/index complete only after acceptance; final commit and
  pushnotify reporting actual completion (0% pending).

## Specification review

Independent Identity reviewer checked ownership, dependency order and permission
contracts on 2026-10-16. Findings resolved: explicitly select approve/deny of current
authority, disclose future tenants for all-tenant grants, reject consent on version
drift, and name both user-version increment paths. Boruta source reviewer identified
default transaction, resource-binding and raw-token-storage gaps; checkpoints cover
those before public HTTP exposure. Research is not implementation acceptance.

## Evidence and progress

- 2026-10-16: setup succeeded; inspected actual Hex Boruta 2.3.8 archive, SHA256
  `27c703836793c852fb98d94d58ef9bb93ca7a51fce2196e16d19ee7d5cfecc62`.
  ExMCP remains pinned to `5fa760207bb09fc3b19b3049bc481b5e55106095`.
- Real Boruta probe passed through authorization/token callbacks: S256, wrong
  verifier rejection, custom context grant propagation, refresh and sequential
  reuse rejection. Wrong resource still succeeds inside Boruta, confirming the
  required Vxpipe boundary. Normal library startup passed. Dependency resolution
  against a copy of the repository lock added 12 packages and changed no existing
  entries. Reproducer: [Boruta probe](../../docs/experiments/boruta-probe.exs), run
  `elixir docs/experiments/boruta-probe.exs` outside Mix. It uses synthetic in-memory
  data and is not evidence of PostgreSQL atomicity or production authorization.
- No exposed OAuth flow or browser evidence yet.

### Foundation implementation

- Input profile: five red failures before implementation; five green checks for
  public registration, redirect syntax, S256, canonical resource, bounded exchange
  and revocation inputs. Entire Identity suite: 74 tests passed. Stored redirect
  equality and durable resource binding are still downstream work.
- User authorization version: four expected red failures, then four passing
  focused tests and 59 passing Persistence identity regressions. Covers authority,
  password/status changes, unchanged reads/email, failed audit rollback, and
  credential recovery rollback/success. Test database migration passed.
- Independent code review found no blocking issues. It verified locked atomic
  updates, preserved rollback and untrusted input exclusion. These foundations do
  not yet issue or authenticate OAuth credentials; checkpoint 2 remains open.
- Foundation checks: dev/test migrations, root format, warnings-as-errors compile,
  strict Credo and unused dependency check passed. Full umbrella tests remain a
  final acceptance gate; this subcheckpoint ran the focused Identity/Persistence
  regression suites above.

### Delegated authority prerequisite

- Principal construction now distinguishes browser sessions from OAuth grants;
  common trusted user/role projection is shared. Consent snapshots carry user
  version and role identity/revision. Pure delegation rejects drift and intersects
  current and approved grants without fabricating a browser session.
- Tenant authorization checks current and approved contexts independently per
  action. Directory scope checks delegation before built-in account shortcuts;
  approved all-tenant actions still cover future tenants. This avoids leaking
  access by merging unrelated all-tenant and assigned-tenant grants.
- MCP discovery/invocation now accepts real user read/write permissions. Account
  provenance preserves user plus grant ID. Transactional OAuth account mutations
  remain denied until checkpoint 3's persistence integration is complete.
- Red/green evidence: five missing-constructor/delegation failures, one attribution
  failure, four tenant-scope failures, and four user-discovery failures preceded
  implementation. Final Identity suite: 80 passed; focused Calls: 30 passed;
  Gateway MCP/account regression: 22 passed. Independent review found no blockers.
- This enabling work was implemented alongside token persistence because issuance
  needs the shared principal/snapshot constructor; neither checkpoint 2 nor 3 is
  marked complete before their remaining persistence and protocol acceptance.

### Durable credentials and account mutations

- Real Boruta 2.3.8 now runs through narrow PostgreSQL contexts. Codes and both
  token types persist only digests, with exact resource/client/redirect/PKCE
  checks. Refresh rotation preserves the grant and commits family revocation on
  verified replay; failed issuance rolls back all writes.
- Separate-connection tests reproduce single-winner code exchange, refresh replay,
  installation locking and cleanup races. Review caught ignored Ecto lock options;
  query-level locks now protect OAuth and three existing identity mutation paths.
  Cleanup locks candidates without waiting and rechecks predicates before deletion,
  protecting concurrently issued or consumed grants.
- Account writes revalidate fresh user/grant authority inside the mutation
  transaction, enforce the existing hierarchy and audit user plus grant. Tests
  cover revoked/reduced grants and attempted direct-store hierarchy bypass.
- Quotas: 10,000 registered clients, 100 active grants/user, 10,000 token pairs/grant.
  Bounded cleanup removes expired/revoked grants and abandoned registrations older
  than 24 hours. Per-minute address/global rates are registration10/200,
  authorization60/600, token120/2000 and revocation60/600. Fixed windows persist
  hashed address buckets; independent-connection tests verify admission ceilings.
- Independent storage/account and facade reviews completed; identified retention
  races were reproduced red and fixed green. Identity facade/port tests:5 focused
  and85 total passed. Store/limiter:17 focused passed; exchange/retention/limiter
  concurrency:8 passed using distinct database connections. Browser transaction
  persistence is tracked under checkpoint4 and remains a separate pending commit.
- Storage checkpoint regression:80 relevant Persistence tests passed. Compile
  warnings-as-errors, staged-file formatting, strict Credo and unused dependency
  checks passed; full umbrella acceptance is still pending.

### HTTP adapter and browser transaction prerequisites

- Discovery, registration, token and revoke routes are implemented behind the
  disabled-by-default OAuth option. Metadata preserves configured issuer/resource
  prefixes; parsers reject duplicates, oversized bodies and unsupported inputs.
  Host/scheme/origin checks precede backend work, errors are safe, cookies cannot
  substitute for credentials, and responses disable caching.
- Console supplies its existing trusted-proxy address resolver; standalone Gateway
  uses the peer address. Red/green review fixed shared rate buckets behind Caddy.
  Gateway OAuth13 tests and Console address5 tests passed; the earlier combined
  HTTP/MCP boundary regression passed45 tests before those proxy additions.
- Persisted browser requests have hashed IDs/bindings, ten-minute expiry, an active
  quota of10 per browser and10,000 globally, and bounded expiry cleanup. Display
  binds the authenticated session and exact authority snapshot. Completion is
  atomic and single-use; denial only returns the registered callback and state.
- Independent review found expired rows blocking quota and unused-client cleanup
  deleting live consent requests. Both were reproduced red and fixed; client locks
  and live-request predicates protect pending consent. Browser9 focused tests and
  the combined30 store/browser/account/limiter tests pass. Nine distinct-connection
  tests now include concurrent approve/deny with exactly one winner.
- Safe own-client listing/revocation persistence is ready. HTTP browser routing,
  rendered consent/Account UI, login resume and final MCP cutover remain pending;
  checkpoint4 is not complete merely because its underlying storage exists.
