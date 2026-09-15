# Repair carrier claim fixture

- Full umbrella verification at `68989dd` ran 1,588 tests with 89 failures and 38 exclusions.
  Twenty-six Telnyx/Twilio harness cases failed while constructing the shared fixture because
  `struct!(TelephonyAdmissionClaim, ...)` lacked the newly required `service_id`. The earlier
  constructor search covered literal struct syntax and missed this dynamic constructor.
- Both harness setups changed the global Engine configuration before building that fixture,
  but registered restoration afterward. A build failure therefore left test-owned transports
  and wait-sound settings installed. Later Gateway/Persistence errors reported unavailable audio.
  This is a project-owned fixture defect, not evidence of an external carrier failure.
- Added the synthetic canonical UUID used by the other standalone Gateway claim fixtures.
  Registered configuration restoration immediately after capturing the original settings in
  each setup, preserving the later room/leg cleanup. No production code or auth support changed.
- The existing root failures supplied red evidence. Both complete carrier harness files now pass:
  26 tests, zero failures, seed 235296, concurrency four. Log: `tmp/carrier-claim-fixture-focused.log`.
- Independent GPT 6 Astra xhigh review found no blocker. Format, warnings-as-errors compilation,
  strict Credo and unused-lock checks pass; the correction changes only test fixtures and evidence.
- Full umbrella verification will rerun after this small correction commit. Milestone progress
  remains four of seven complete, three partial; the preceding focused identity/storage evidence
  remains valid, while common acceptance is open until the corrected root run passes.

## Full verification after correction

- The full root retry at `d2fbbd7` completes 1,588 tests with one failure and 38 exclusions
  (seed 235296, concurrency four). MCP 37, Agent Runtime 95, Engine 697, Calls 84, Artifacts 20,
  Persistence 136 and Console 106 have zero failures. Gateway has 413 tests and one failure.
- The carrier constructor failures and subsequent audio-preparation cascade are gone. The only
  failure is the native five-participant handoff case waiting for 250 Hz audio after reconnection
  (`human_transfer_webrtc_test.exs:518`). Its source is unchanged since the passing `9026af2`
  umbrella run. Prior labnotes also record intermittent failures in this case; this run alone
  does not establish their cause.
- Log: `tmp/carrier-claim-fixture-root-test.log`. Common umbrella acceptance remains open.
- The unchanged case passes in isolation: one test, zero failures, 67 excluded, same seed.
  Log: `tmp/carrier-claim-fixture-native-isolated.log`. This narrows the observation but does
  not explain the full-suite timeout or turn the failed umbrella run into a pass.
