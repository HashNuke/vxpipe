# Tenant telephony service registration

## Checkpoint scope

- Prior goal turn made progress: committed the source-backed provider inventory and completed
  all five provisioning gates (1,534 tests, 0 failures). Worktree was clean at `08354c8`.
- Add a neutral Calls service record/repository and trusted registration/metadata lookup, backed
  by Persistence. Telnyx only in this slice; retain its existing API-key authentication.
- A service uses a stable public ID, tenant-local alias, globally unique ingress key, Telnyx
  connection/public verification metadata and the existing carrier options. Its stable credential
  reference must match tenant/provider through a database foreign key. Public origins stay platform-owned.
- Registration checks active readable credentials in the same transaction as the write. Metadata
  reads contain no secrets and do not decrypt; live leg construction must resolve fresh auth in the
  following reader slice. No update/rebind API, carrier policy subsystem or new protocol is included.

## Verification

- Added focused tests first for registration/lookup, tenant and ingress isolation, credential
  ownership/readability, database ownership enforcement, invalid metadata, outages and runtime wiring.
- Expected red: 8 tests, 7 failures at the missing registration APIs and runtime wiring.
- Added the Calls record/port/workflow, Persistence schema/store/migration and runtime composition.
  The composite foreign key covers credential public ID, tenant ID and provider; credentials are
  locked and decrypted through the existing adapter before insertion in the same transaction.
- Migrated the test database and obtained green: 8 tests, 0 failures, seed 235296. Direct database
  update attempts confirm tenant/provider mismatches are rejected by the ownership constraint.
  No Gateway/Engine reader changes or live carrier acceptance are claimed.
- Independent GPT 6 Astra xhigh review found no transaction, ownership, scope or field-validation
  blocker. It confirmed metadata lookup does not decrypt and trusted OTP registration is a usable
  checkpoint before the separate CLI/live-reader work. `git diff --check` passes.
- Root formatting, warnings-as-errors compile and strict Credo pass. Owning-app suites pass:
  Calls 81 tests, 0 failures; Persistence 95 tests, 0 failures, 6 excluded, seed 235296.
  Full root suite remains pending for the ongoing implementation turn.
- The focused documentation records trusted registration and metadata lookup as implemented and
  CLI/live-reader acceptance as pending. No checkpoint count changes.
- All 181 local documentation links/anchors resolve; `git diff --check` passes.

## Operator CLI checkpoint

- Committed trusted storage/workflow as `947734b` before extending the operator surface.
- Added CLI tests first; all 3 failed at the expected missing task module.
- Implemented `mix vxpipe.telephony_service.register --tenant ... --file ...` over the existing
  Calls registration. Input is a single metadata JSON object, bounded to 16 KiB. Output contains
  public binding IDs/locators; invalid arguments and input do not echo supplied values.
- CLI + service storage + runtime group passes: 11 tests, 0 failures, seed 235296. Invalid JSON,
  secret-bearing/oversized input and secret flags leave no service registration behind.
- Updated operator docs to show the one-time registration input and distinguish it from a live
  configuration file. Live readers remain pending.
- Independent GPT 6 Astra xhigh review found no blockers. Root formatting, warnings-as-errors
  compile and strict Credo pass; Persistence passes 98 tests, 0 failures, 6 excluded.
- Added cleanup for the CLI test temporary files after review identified the generated child
  `tmp/` output. The files are test artifacts, not tracked service configuration.
- Full root tests and unused-dependency verification remain pending for the ongoing turn.
- The CLI cleanup rerun passes 3 tests; generated files are gone from status. All 156 local
  links/anchors in the changed docs resolve and both JSON examples parse. `git diff --check` passes.

## Next reader boundaries — source review only

- Local review found live `LegSupervisor`/`Leg`/`OutgoingLeg` correlation keys and durable
  `TelephonyCallStore` duplicate queries/indexes using provider + service alias + event/leg ID.
  The reader cutover must carry tenant and canonical service identity through both; returning a
  tenant-scoped service from the new repository alone does not repair these downstream lookups.
- Independent GPT 6 Astra xhigh review confirmed the next definition boundary: enumerate every
  non-web participant, including later destinations, and fail credential checks before
  `Definitions.validate_support`, which otherwise converts compiler failures into writable drafts.
- Extend the final database write guard for service + referenced credential under deterministic
  locks on the same Repo transaction. `PreparedCallFactory` preflight is followed by compilation
  and opening preparation; it cannot protect a later write on its own. Web `Admissions.prepare`
  already has a final guard, while fresh `TelephonyAdmissions.claim_incoming` currently lacks one.
  Preserve existing duplicate/admitted-leg behavior separately from fresh admissions.
- `CallPlanCompiler` is the neutral host boundary for pinning an Engine-owned non-secret service
  reference before plan hashing. Keep the authored alias and pass the expected canonical/account
  identity through `OutboundLegRequestResolver` to the actual reader. Validate it again under the
  final preparation write guard, and reject unpinned hosted phone plans safely.
- These are existing checkpoint 3 requirements and source findings, not implemented progress.
  No additional policy, lease or generic legacy-conversion subsystem is required.

## Full root verification and unresolved native case

- Committed the CLI as `2612973`, then ran all static root gates again: format,
  warnings-as-errors compile and strict Credo pass. The full suite completed 1,543 tests,
  1 failure, 33 excluded, seed 235296, module preloading and concurrency four.
- MCP 37, Agent Runtime 93, Engine 695, Calls 81, Artifacts 20, Persistence 98 and Console 106
  tests passed. Gateway completed 413 tests with one failure.
- The existing Gateway `native repeated AI transfers retain callers and recordings across
  listener re-entry` case failed at `human_transfer_webrtc_test.exs:355`: listener Morse
  assertion awaited `E`; state held text `E `, silence with 23 current windows, 25 total windows
  and no pending marks. Its final decoder flush rejects that silence timing.
- Re-ran exactly `human_transfer_webrtc_test.exs:214` without changing source, using the same
  preload/seed/concurrency settings. Result: 1 test, 1 failure, 67 excluded, 103.8 seconds;
  the same state and failure reproduced. This is not a passing umbrella gate.
- The earlier provisioning labnote `20260915-1616-tenant-credential-provisioning.md` already
  records an intermittent final-flush timing failure in this case. No Gateway/Engine runtime or
  test source changed in the service-registration chunks. The precise native media cause remains
  unresolved; do not infer a fix, change decoder tolerance, or remove exact audio assertions.
- Logs: `tmp/telephony-service-final-root-{format,compile,credo,test}.log` and
  `tmp/telephony-service-native-isolated.log`. The sequential root driver stopped at the failed
  suite; the separate `mix deps.unlock --check-unused` run passes, recorded in
  `tmp/telephony-service-final-root-unused.log`. Live-reader implementation and final milestone
  acceptance remain open.
