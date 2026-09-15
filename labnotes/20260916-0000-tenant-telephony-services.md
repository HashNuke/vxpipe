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
