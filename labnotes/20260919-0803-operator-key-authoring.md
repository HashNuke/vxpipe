# Operator key authoring

- Started after reviewed Console checkpoint `ba941a3`. A3 will use two runnable
  commits: trusted key lifecycle plus authenticated status, then HTTP spec writes.
  The overall A3 acceptance stays open until both are verified.
- Recorded the key lifecycle and HTTP contracts in `docs/operator-api-key-authoring.md`.
  Keep operator keys separate from tenant keys and browser login grants; begin with
  one active installation key and explicit replacement instead of a broad IAM system.
- Added the first persisted red tests for one-time bootstrap, hash-only storage,
  authority separation, atomic failed replacement and revocation.
- Initial persisted tests failed on the missing operator-key principal field; both
  pass after storage/workflow implementation. The CLI test failed on missing tasks;
  the HTTP tests failed with 404 and an unrecognized mount option before wiring.
- Added a fault-injection regression for a crashed output writer. It failed with
  an escaping exception and an issued key still active; the file boundary now catches
  output failures, attempts revocation and removes the incomplete file. Four persisted
  lifecycle/CLI tests and both Gateway status/mount tests pass.
- A disposable PostgreSQL exercise proved concurrent bootstrap converges on one
  secret, mode-0600 output, real HTTP operator/tenant authority separation, fresh-VM
  restart, atomic replacement and revoked-key rejection. The first fixture attempt
  exited its temporary supervisor parent before readiness; kept that script's owner
  alive and reran successfully. Removed the owned server, database and key files.
- Review found endpoint enablement limited to development. A new configuration test
  failed in production; moved enablement beside shared runtime Gateway configuration
  so it follows configured persistence in either environment. No API-key value is
  read from runtime environment variables.
- Owning validation passes: Calls 114 tests, Persistence 167 tests (12 excluded),
  Console 176 tests (one excluded), and the 36-test Gateway status/mount/endpoint/
  admission group. No UI changed in this step; API behavior was exercised through
  actual HTTP requests. The combined A3 umbrella gate follows the authoring step;
  the preceding B1 serial umbrella run is not claimed as validation of new key code.
- Review covered the closed operator grant, separate digest store, no promotion of
  tenant keys, output-file lifecycle, default-disabled embedded Gateway and runtime
  production enablement. No dependency or lockfile change. Root static checks pass.
