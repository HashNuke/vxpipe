# Participant input completion

## Contract

Accepted canonical STT turns produce diagnostic completion evidence independent of
selected response capabilities. Remove only the diagnostic text/STS gate; preserve
source/turn authorization, owner checks, operational dispatch and activity control.

## Red/green evidence

- New no-response and STS-capability unit cases failed on absent completion
  evidence (15 tests, 2 failures); normal turn-completed events still arrived.
- A published human-only incoming call reached STT transcription and a persisted
  run but timed out waiting for a diagnostic turn row before the change.
- Fixture setup required receive/start_call connections for both entry humans;
  unsupported join_call/transfer intents were corrected, and both humans attach
  and acknowledge Scribe readiness before room startup finishes. These were test
  construction failures, not runtime fixes.
- Removed selected-text/STS conditions from the private completion observer;
  reference validation and CaptureHandoff owner/authority checks remain unchanged.
- Updated the obsolete negative no-LLM expectation. Unowned capture is still
  rejected with and without an agent. Focused unit suite passes 15/15.
- Actual configured two-human cases pass 2/2 with local Silero off/on. Each input
  retains its own run and canonical turn, exact marker provider bytes and one
  expected inference path. Response landmarks remain absent; no model agent exists
  in the published plan. Added diagnostic teardown drain before sandbox cleanup.

## Review and final verification

- Full configured diagnostic selection passes 12/12. Final two-human cases pass
  2/2 after checking actual room completion DOWN, writer/collector drain and no
  extra marker inference, provider bytes or commits after teardown.
- Reviewer reproduced an ineffective model-request assertion: the configured
  AgentRuntimeModelProvider never emits the watched test stream message, even
  after a successful request. Replaced it with an armed non-default ModelFixture
  scenario, checked unconsumed after room completion. Final two-human rerun passes
  2/2. Independent final review is clean. Its positive control confirms an actual
  model adapter request consumes the armed scenario and fails the retained check.
- Root format, warnings-as-errors compile, strict Credo and unused-lock checks pass.
  Lean builds and replay passes 1/1.
This checkpoint does not claim mixed-room STT-to-STS control/real replacement
acceptance, no-STT allocation proof or full milestone completion. No Telnyx code,
live provider tests, full suite or deployment changes.
