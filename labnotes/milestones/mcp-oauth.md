# MCP OAuth authorization

Status: planning and Boruta experiments in progress; runtime OAuth not implemented.

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
- Local deterministic tests and reference-client acceptance; no live providers.

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

- [ ] Red-test public client profile, exact redirects, S256-only, resource binding,
  unsupported fields/scopes/grants, and secrets absent from persisted rows/errors.
- [ ] Pin Boruta and configure narrow contexts; no generated full OAuth/OIDC app.
- [ ] Add bounded client/transaction/grant/code/token persistence and migrations.
- [ ] Implement code consumption and refresh rotation atomically; red-test racing
  exchanges, replay-family revocation that commits on error, and rollback on failure.
- [ ] Add user authorization version and compare role identity/revision; cover all
  existing invalidation paths including recovery and disable/reactivate. Increment
  in IdentityUserStore's session-invalidation path and IdentityInstallationStore's
  credential recovery; role changes retain the existing role revision mechanism.
- [ ] Implement revocation/expiry/cleanup and establish concrete durable quotas.
- [ ] Verify wrong-client/resource/verifier requests cannot revoke a valid grant.
- [ ] Independently review, run relevant tests, update evidence and commit.

## Checkpoint 3: delegated user authority (20%)

Runnable slice: a locally issued OAuth token authenticates as an explicitly
delegated user and exercises shared operations directly.

- [ ] Red-test browser/OAuth mutually exclusive Principal provenance and stable
  grant identity; extract common trusted principal construction.
- [ ] Intersect approved/current authority; apply tenant ceiling before built-in
  directory shortcuts. Check read-only, member, Admin and Superadmin behavior.
- [ ] Revalidate and audit OAuth account writes inside their transaction; reserve
  grant attribution fields against injection and preserve account hierarchy.
- [ ] Extend per-tool discovery/invocation to real user read/write permissions;
  preserve all 17 schemas/results and shared domain operations.
- [ ] Verify HTTP API-key and browser regressions; independently review and commit.

## Checkpoint 4: discovery, login and consent (25%)

Runnable slice: a local client discovers, registers, logs in, consents, exchanges,
refreshes and revokes using HTTP, while MCP cutover remains gated.

- [ ] Red-test trusted issuer/resource and prefixed metadata construction;
  public discovery routes and bounded DCR/token/revoke routes.
- [ ] Rate-limit and bound records/requests; fail closed on storage/config errors.
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
- No OAuth runtime implementation or browser evidence yet.
