# Review MCP OAuth storage

- Begin independent source review of durable attempts, fenced grants, pruning and
  credential re-encryption commands. Keep Calls/Console authorization and runtime
  orchestration separate; include only required repository ports/private snapshots.
- Existing connection storage and secret envelopes are committed. Attempt admission
  locks the tenant row, stores a state digest and encrypted binding/payload, and caps
  live attempts at eight. Grant refresh claims lock the connection row and preserve
  configuration generation while advancing grant revision on successful rotation.
- Current tagged OAuth interoperability uses local HTTP servers, PostgreSQL and a
  single BEAM. It is not independent-node acceptance. The milestone keeps that
  gate open. No new storage fixes or tests have run for this checkpoint yet.
- Independent source review found inconsistent repository outage handling, stale
  access-token expiry after refresh, and unauthenticated attempt state/expiry
  columns. Regressions reproduced all three; a separate expiry regression confirmed
  that lifetime extension failed independently of state substitution.
- Implemented precise database/Repo outage classification with programmer errors
  preserved, authenticated state digest and canonical microsecond expiry in the
  encrypted attempt payload, and clearing prior access expiry before token merge.
  Added acceptance tasks for key transitions, cross-tenant grants, exact deadlines
  and rejected-completion rollback. Verification and re-review remain pending.
- All 26 attempt/grant tests passed after fixes. The shared dependency classifier
  was then extracted from ConnectionStore; its public error remains unchanged.
  All 57 MCP persistence tests pass after adding the requested key, tenant,
  equality-deadline and invalid-completion acceptance cases. Re-encryption retains
  a live refresh claim and completion succeeds with only the new key available.
- Protocol adapters committed independently as `d3fb8c6d`. New storage runbook
  records persistence guarantees and operator retirement order without implying
  browser orchestration or independent-node acceptance is finished.
- Final verification: 57 focused MCP persistence tests, 484 owning-application
  tests and five tagged distinct-PostgreSQL-connection race cases pass. Format,
  warnings-as-errors compilation, strict Credo and unused-dependency checks pass.
  Both operator task help pages match the documented bounds and output contracts.
  Evidence: `vxpipe-oauth-storage-focused.log`, `vxpipe-oauth-persistence-suite.log`
  and `vxpipe-oauth-storage-concurrency.log`.
- Independent adversarial review of the exact 23-file staged checkpoint is clean.
  Only storage adapters/type entries are staged from shared wiring. Later browser,
  machine, refresh orchestration and runtime providers remain outside this commit.
