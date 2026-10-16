# MCP OAuth implementation

## Planning and source research

- User requested replacing MCP API-key auth with OAuth, reusing ExMCP, researching
  Boruta, small experiments/checkpoints, independent review and small commits.
- Existing ExMCP handler/Plug confirmed. Product HTTP API keys are outside the
  replacement scope. No live providers, telephony or deployment needed.
- `bin/setup` succeeded with dependencies, assets and isolated database migrations.
- Independent source inspection of stable Boruta 2.3.8 identified missing resource
  binding, non-atomic default code/refresh mutation and raw token storage. Custom
  published contexts plus project-owned transactions are required; avoid copying
  the generated OIDC app. Runtime experiments remain pending.
- Identity inspection found that current principals require browser sessions and
  account writes revalidate those sessions. OAuth needs explicit grant provenance,
  current policy checks and transaction-time revalidation, not fabricated sessions.
- Selected a narrow public-client/DCR/code+refresh profile and one `mcp` scope.
  Consent delegates current authority with ceilings; existing Identity permissions
  remain the only action policy. CIMD is explicitly deferred because it adds URL
  fetching and client-ID mapping; document compatibility limits.
- Drafted design and five implementation checkpoints. Design review, experiments
  and implementation acceptance are still open; no production behavior changed.

## Protocol experiment and design review

- Real Boruta authorize/token callbacks passed with custom in-memory contexts:
  S256 exchange, wrong verifier before issuance, grant metadata propagation,
  refresh rotation and sequential replay rejection. Wrong resource succeeds inside
  Boruta, confirming the need for the boundary. No database races were tested.
- Dependency resolution with a copy of the existing lock added 12 packages without
  changing existing entries. Normal Boruta application startup passed.
- Added a standalone pinned experiment under docs/experiments. It installs only
  into Mix's normal scratch cache and uses synthetic data.
- Independent design review required explicit approve/deny authority semantics,
  disclosure of future tenants for all-tenant grants, and atomic consent-version
  checks. The design/milestone now contain those contracts and version-update sites.

## Input and account-version foundation

- Added a pure OAuth input profile before any routes are exposed. Five tests failed
  for the missing module, then passed for public-client metadata, safe redirects,
  S256, canonical resource and token/revocation bounds. All 74 Identity tests pass.
- Added a positive durable user authorization version, advanced under existing
  locks in account authority/password changes and recovery. Four focused tests
  failed before implementation and pass afterward; 59 existing Persistence
  identity regressions also pass. Grant/version comparison is still future work.
- Independent code review found no blocking issues, checked transaction rollback,
  recovery projection and exclusion of caller-supplied version fields.
- A format invocation initially used root-relative paths from a child directory
  and found no files. Reran formatting correctly from the umbrella root; this was
  a command-path error, not a test failure. The child Identity test run passed.
- User clarified no Lean proofs and no live provider tests; neither is used.
- Dev/test migrations and root format, compile warnings-as-errors, strict Credo
  and unused dependency checks passed. Full umbrella tests are still pending for
  the completed integration; focused regression evidence is recorded above.

## Delegated authority and tool policy

- Extracted common principal construction from Sessions, retaining browser behavior
  and adding explicit OAuth user/grant provenance. Consent snapshots carry version
  checks and a JSON-safe authority ceiling. Account stamping reserves grant fields.
- Kept current and approved tenant contexts separate. A merged assignment map can
  leak authority when different actions combine all-tenant and assigned scopes.
  Directory/discovery checks now apply the same per-action intersection.
- Extended existing MCP tools to real user permissions, separating reads/writes
  while preserving key paths and schemas. Transactional OAuth account writes still
  fail closed pending their persistence integration.
- Tests were red before implementation; final Identity80, Calls30 and Gateway22
  checks pass. Initial tenant test fixtures accidentally had 17-character keys;
  corrected to the required16 before green. Independent code review found no
  blockers. No live providers or Lean work.
- Boruta dependency resolution in the umbrella added12 packages and changed no
  existing locked versions. Dependency and token-store work is a separate pending
  checkpoint; no OAuth route is exposed by this authority prerequisite.

## Durable credentials and transaction review

- Added narrow real-Boruta contexts, opaque credential digests, absolute grant
  lifetime, current-authority checks and atomic code/refresh exchange. Wrong
  client/resource/verifier cannot consume or revoke another grant. Verified
  refresh reuse revokes the family and commits that result despite an OAuth error.
- Implemented explicit Identity OAuth ports/facade; no default storage fallback.
  Delegated principals are constructed only from verified user/role/grant records.
- Account writes revalidate OAuth grants under transaction locks and preserve user
  plus grant audit attribution. Four focused tests went red then green, including
  stale/reduced authority and Admin hierarchy. No grant FK on audit history, so
  deleting expired credentials cannot erase historical attribution.
- Review caught Ecto Repo.get lock options being ignored. Distinct PostgreSQL
  connection tests reproduced the failure; moved locks onto queries, including
  three existing installation mutation helpers. Cleanup review also reproduced
  stale candidate deletion of newly issued/consumed grants; SKIP LOCKED candidate
  selection plus fresh predicate checks fixed both races.
- Added bounded cleanup and quotas plus durable fixed-window address/global limits.
  Limiter races use separate connections, not a shared sandbox connection. Store
  and limiter17 tests and concurrency8 tests pass; Identity85 tests pass. No live
  provider or Lean work was run. Broader umbrella acceptance remains pending.
- Browser work exposed a later retention dependency: live pending authorization
  requests must protect their client from cleanup. This belongs with their schema
  and will land in the browser checkpoint. Expired request quota blocking was
  independently found, reproduced red and fixed by counting active requests.
- Final storage checkpoint regression:80 Persistence tests passed; compile with
  warnings-as-errors, staged-file formatting, strict Credo and unused dependency
  checks passed. Corrected one migration formatting issue before committing.

## HTTP and browser transaction prerequisites

- Added public OAuth metadata and bounded registration/token/revoke adapters,
  disabled by default. Exact configured URL prefixes survive the embedding mount.
  Duplicate JSON/form fields, over-limit bodies, timeout, bad origins/hosts/schemes
  and unavailable backends fail safely; cookies never provide token authentication.
- HTTP review found loopback reverse-proxy clients sharing a quota bucket. Reused
  Console's existing trusted-loopback address resolver; Gateway defaults to peer
  IP. Red/green tests prove trusted client isolation and spoofed-XFF rejection.
- Browser storage tests failed six times before implementation, then passed.
  A missing Ecto.Query test import was fixed before recording behavior failures.
  Request IDs/bindings are hashed, displayed snapshots bind the real session,
  approval/denial consumes the transaction once, and own-grant revoke is scoped.
- Independent review reproduced expired backlog quota blocking and cleanup deleting
  live pending consent. Count active requests, preserve live pending clients in
  both cleanup predicates, and hold a client KEY SHARE while inserting requests.
  A distinct-connection approve/deny race proves single completion. Final browser9,
  combined persistence30 and concurrency9 tests passed. An initial agent test
  command used umbrella paths; subsequent focused runs used the owning child.
- Gateway OAuth13 and Console address5 tests passed; default-disabled wiring is
  separate from the pending browser controller and OAuth-only MCP runtime cutover.

## Console consent and connected clients

- Implemented safe opaque login resume, protected consent decisions and session-only
  connected-client listing/revocation. Preserved existing Console styling and shared
  account API conventions. Backend66 and frontend51 regressions, TypeScript, scoped
  ESLint and assets build passed; independent source review found no blockers.
- Actual Chrome exposed a native HTML form Origin:null under no-referrer, despite
  the SDK's successful synthetic POST. Captured only safe request headers/status,
  reproduced403 in a focused real-CSRF test, then allowed opaque Origin only on
  consent POST through CSRF/session/binding validation. Final OAuth11 tests passed;
  SDK repeats this header and all seven acceptance groups pass.
- Rendered consent and populated/empty Account views at1280x900 and390x844. Actual
  login, approval, code exchange and seven own-grant UI revocations succeeded; no
  horizontal overflow. The disposable SQL sandbox fixture was stopped afterward.
  Chrome needed no-sandbox because the local Linux sandbox was unavailable.
- An early browser automation selector did not match; retried using rendered
  accessibility refs. Another agent accidentally printed disposable synthetic
  fixture credentials while inspecting its JSON; stopped/recreated that fixture.
  No real credentials or fixture payloads were committed.
- Independent visual reviewer returned ship at screenshot/source scope. Detector
  found no issues. No new design system or permission editor was introduced.


## OAuth-only MCP acceptance

- Replaced MCP API-key authentication with the Identity OAuth facade and explicit
  delegated-user principals. Challenges point to configured resource metadata;
  resource configuration is validated at startup. Product HTTP keys remain intact.
- Migrated fixtures to real OAuth grants while retaining separate HTTP keys for
  equivalent-authority comparisons. Focused Gateway MCP/mount 49, persisted Console
  MCP 13 and the loopback stalled-body integration test passed. Refresh retains a
  session, another grant cannot reuse it, and revocation/disabled users fail on the
  next request. Audit tests retain the real user and grant provenance.
- Updated the pinned SDK fixture to exercise actual discovery, DCR, PKCE, rotating
  refresh, resource binding and revocation across all three mounts. Console runs
  login and consent over HTTP; standalone/embedded fixtures use a private consent
  command because they do not own browser pages. All seven SDK/conformance/restart
  groups passed, including native-form Origin:null with valid CSRF.
- Independent MCP boundary, SDK and runtime reviews found no blockers. The separate
  final browser exception review confirmed POST-only scope and mandatory CSRF,
  session, binding and authority checks. Fixtures stopped before root DB tests.
- Root format, compile with warnings-as-errors, strict Credo and unused dependency
  checks passed. Full root tests are running. Updated client setup, configuration,
  limits and key-to-OAuth reconnection documentation; local links resolve.

- The full default run listed 4,437 tests (156 excluded) and exposed eight legacy
  fixture assumptions plus one local WebRTC recovery deadline failure. Three
  outgoing-call MCP fixtures still used API keys and lacked issuer/resource;
  migrated only their authentication setup, preserving HTTP-key replay and every
  timeout/idempotency assertion. All 21 tests in that file pass; independent review
  confirmed the credential paths remain distinct.
- Five Console DB/storage configuration tests supplied a production loopback HTTP
  origin. Updated fixtures to a public application host and isolated the resource
  override environment variable. Added runtime checks for matching issuer/resource,
  store ports, exact override behavior and safe rejection of invalid configuration.
  Independent review found no blockers; focused verification is pending below.
- The unrelated WebRTC failure was a real fail-closed room shutdown after its
  existing 750 ms recovery deadline, not just the polling helper timing out. No
  OAuth diff changes that code. An isolated rerun is in progress before deciding
  whether any further change is warranted; no timeout/assertion was weakened.
- Isolated WebRTC rerun passed all three generated private-media loss cases,
  with 66 unrelated cases excluded. No production code, deadline or assertion was
  changed. The earlier recovery-deadline failure remains an observed timing flake,
  not a claimed OAuth fix.

- Runtime fixture follow-up initially exposed two test assumptions: development
  resolves its host as a local listener address, and missing production APP_HOST
  fails in the preexisting Console origin guard. Kept loopback for development,
  public host for production, and asserted the actual distinct safe errors.
  Final two-file run: 16 passed. Independent review approved the final adjustment.
- Final root failed-test sweep passed all nine former failures: Gateway four and
  Console five. WebRTC therefore passed both isolated and root failed-test reruns.
  Root format, warnings-as-errors compilation, strict Credo and unused dependency
  checks also passed after all test updates. No live provider or Lean work ran.
- Milestone and index marked complete with initial failures and rerun evidence
  preserved. Documentation records configuration, limitations and MCP reconnection;
  this work does not claim deployment. Final checkpoint is ready to commit.
