# Retire private briefing

## Contract and ownership review

The human destination's TTS exists to synthesize its private briefing. Once the output sink
acknowledges completed playback, that capability has no remaining work in the resulting human
conversation. Keeping it alive until final transfer completion also lets an irrelevant later
provider failure cancel the transfer. Source TTS remains available for bounded caller recovery;
selected destination STT remains required through release.

`HumanBriefing` already owns the request and matching playback notifications. It now owns
completion cleanup through the existing capability supervisor operation: stop/demonitor the
briefing TTS, clear its retained request and capability handle, then expose acceptance readiness.
No additional actor, configuration field, timeout or UI is needed. Notification routing tolerates
an absent retired handle; delayed completion, provider-unavailable and monitor events are ignored.
The prepared destination type explicitly permits the retired TTS handle to be nil.

This is one part of the human private-resource cleanup item. Candidate preparation also owns
room/mixer/router/recording leases and connection preparation; these use the existing discard
path when no longer present in a refreshed graph. Native removal/retention evidence currently
covers STT and media, while the broader resource and changing-audience acceptance remains open.

## Red-green evidence

- Red: extending the existing private-briefing acceptance test failed at the expected missing TTS
  termination after playback completion. The capability remained alive while waiting for acceptance.
- Green: the same test keeps TTS alive before playback acknowledgement, observes capability and
  transport termination after it, preserves source TTS, ignores retired notifications and completes
  the ordinary transfer. Private usage attribution and retained room services still pass.
- All 34 owning-engine human handoff cases pass, including preparation/cue failures, removed and
  changed STT demand, release cancellation and source recovery.
- Three focused native cases pass: custom-URL and silent ordinary handoffs retire briefing TTS
  before acceptance, prepare the demanded recognizers and recording path, then exchange ordered
  cue/conversation audio; destination disconnect after briefing restores spoken caller conversation
  through retained media and source TTS.
- All five root gates pass: `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix credo --strict`, `mix test --max-cases 4 --seed 235296`, and
  `mix deps.unlock --check-unused`. The suite reports 1,386 tests, zero failures and 16 integration
  exclusions. All eight default-lane ordinary native handoffs now assert briefing transport cleanup;
  the existing phone and real local Morse cases also pass. The public-URL integration was not rerun
  for this lifecycle-only change.
- Changed Markdown links resolve and `git diff --check` passes. No unrelated work is included.
  The milestone still has 22 broad checkpoint tasks; private-resource cleanup remains open for
  the remaining capability kinds and complete audience acceptance.
