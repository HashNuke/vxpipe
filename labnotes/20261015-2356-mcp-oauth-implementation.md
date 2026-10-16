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
