# Destination credential boundaries

## Scope and findings

- Continue checkpoint 2 after the global-reader removal. Independent GPT 6 Astra xhigh source
  review identified missing evidence at the existing destination credential boundaries.
- Existing save validation already traverses effective selections for every participant. These
  contract tests passed against that implementation; no runtime behavior or credential lifecycle
  operation was added and no red failure was manufactured.

## Save validation checkpoint

- Nine PostgreSQL cases cover missing, other-tenant-only and inactive destination model/TTS/STT
  bindings. Entry credentials remain healthy; each failure identifies the destination selection
  and leaves definition/revision/route row counts unchanged. Public errors exclude secret markers.
- A whole-selection fixture override does not require the unused hosted default binding.
  Saved draft data excludes credential payloads.
- Focused Persistence group: 18 tests, 0 failures, 2 excluded, seed 235296. Independent GPT 6
  Astra xhigh review found no blocking issues in these save checks.
- Save validation alone did not complete checkpoint 2; final acceptance is recorded below.

Run from `apps/vxpipe_persistence`:

```shell
mix test test/vxpipe/persistence/inline_tenant_voice_test.exs --seed 235296
```

## Constructor checkpoint

- Named model, voice and listener selections with identical aliases in two tenants resolve only
  the matching tenant payload. Actual ReqLLM/Flux configurations retain complete selection
  overrides instead of merging unused default options.
- New agent and human destination construction rechecks the injected credential source. Updated
  synthetic payloads distinguish fresh construction from copying a previous configuration.
- Missing model/TTS/STT bindings reach the existing preparation failure before client startup;
  retired global speech options cannot rescue them. Plans, inspected destinations and voice-cache
  identity exclude secret markers. No runtime change was needed.
- Focused constructor group: 5 tests, 0 failures. Combined destination/inline-activation/compiler
  group: 15 tests, 0 failures. Final 5-test rerun after replacing keyword-list bracket access also
  passes. All use seed 235296. Independent GPT 6 Astra xhigh review found no blocking issues.

Run from `apps/vxpipe_call_engine`:

```shell
mix test test/vxpipe/call_engine/plan_startup/destination_credentials_test.exs test/vxpipe/call_engine/plan_startup/inline_activation_test.exs test/vxpipe/call_engine/call_definition/inline_capabilities_test.exs --seed 235296
mix test test/vxpipe/call_engine/plan_startup/destination_credentials_test.exs --seed 235296
```

## Database activation checkpoint

- Three tagged integration cases use a persisted plan and the existing transfer boundary.
  Replacing only synthetic encrypted payloads after entry preparation changes the actual
  destination TTS authentication and intercepted Google request. This test-only mutation does
  not add a provider credential lifecycle API.
- Inactive Google/Deepgram bindings produce safe failure/history before a destination request,
  while the source still responds. Drafts, prepared plans and event/history projections exclude
  secret markers. The Google request uses the existing loopback SSE fixture; no live provider runs.
- The initial attempt had three fixture failures because SendText lacked correlation_id. Adding
  the required generated correlation and removing an unused alias corrected the fixture. The
  tagged run passes: 3 tests, 0 failures, --include integration, seed 235296.
- Independent GPT 6 Astra xhigh review and final bounded re-review found no blocking issues or
  scope/evidence inconsistencies. These checks cover the remaining checkpoint 2 evidence gaps
  alongside existing opening, connection, briefing, restoration and privacy checks.

Run from `apps/vxpipe_persistence`:

```shell
mix test test/integration/destination_credential_activation_test.exs --include integration --seed 235296
```

## Umbrella verification

- Initial format, warnings-as-errors compile and strict Credo gates passed. Tests reported 1,532
  tests, 1 failure and 33 exclusions: the unchanged five-participant native WebRTC handoff timed
  out waiting for 250 Hz caller audio after cue-time listener removal/rejoin. All credential tests
  and other umbrella suites passed; the driver stopped before the unused-dependency gate.
- That native case passed unchanged in isolation: 1 test, 0 failures, 67 excluded, 95.7 seconds.
  Independent review identified an assertion requiring transient wait audio even when the
  listener graph was already ready. The separate [native assertion correction](20260915-2317-native-readiness-assertion.md)
  removes that unsupported timing assumption; its focused case passes. The exact scheduling of
  the original failure remains untraced.
- Final root gates all pass: format, warnings-as-errors compile, strict Credo, tests and unused
  dependencies. The umbrella test run reports 1,532 tests, 0 failures and 33 exclusions, seed
  235296. This includes 695 Engine, 413 Gateway and 87 Persistence tests. The three new tagged
  DB integration cases passed separately; live providers were not exercised.
- Checkpoint 2 is complete. The milestone now has 2 of 7 complete, 1 partial and 4 not started;
  the overall milestone remains unchecked. Telnyx credential readers are next.
- Work was committed in separate reviewed chunks: save validation (`75ad08f`), constructors
  (`a593662`) and DB activation (`a6a4b7d`). The native assertion correction is `61d7a2b`.
- Final documentation verification passes: all 153 local links across the four related documents
  and two labnotes resolve. Checkpoint 2 has all eight task boxes checked; the overall milestone's
  index entry remains unchecked. Parsed test totals match the recorded evidence.
- Final independent acceptance review caught an old checkpoint count in the index's specification
  review table; updated it to match the live ledger. Historical scope-correction counts remain
  explicitly qualified.

Final root commands:

```shell
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix test --preload-modules --max-requires 1 --max-cases 4 --seed 235296
mix deps.unlock --check-unused
```
