# Integrate speech topology

## Authorization and starting state

- The user authorized production integration after the isolated D0 topology proof.
- Update the milestone before runtime edits. D2a freezes the existing paired
  pending-Input cancellation failure and records a current split-production load
  baseline. D2b moves output state into Channel, D2c removes Output, and D2d repeats
  production and topology load plus review/root gates.
- Checkpoint D remains unaccepted. The existing seed-530504 reproduction is the
  required red starting point; production rooms remain on the legacy path.

## D2a split-production baseline

- Commit under test: `ef9e6a0c6f704058ddebe1799e4f9aad441be293`, with the existing
  uncommitted production D source and test files preserved.
- Machine/runtime: Apple M2, 8 physical/logical cores, 16 GiB RAM, macOS Darwin
  25.4.0, Elixir 1.19.5, OTP 28, 8 online schedulers.
- Red contract: `mix test
  test/vxpipe/call_engine/speech/tts_admission_cancellation_test.exs --seed 530504`
  produced 2 tests, 1 failure. The cancel-first case returned `{:error, :busy}`;
  the Input-first control passed. This is the expected pre-change failure.
- Cancellation load: two fresh `MIX_ENV=test mix run
  bench/tts_cancellation.exs ...` attempts failed at the same cancel assertion.
  The first completed 2,208 cycles before a failure in repeat 2, scopes 32,
  credited mode. The preserved second-run log completed at least 2,208 cycles
  before two concurrent `{:error, :busy}` results during repeat 2, scopes 32,
  credited mode. Because the test failed, it correctly wrote no success JSON.
  Raw evidence: `20260920-0745-tts-cancellation-split.log`.
- Handoff/fault load: `MIX_ENV=test mix run bench/tts_handoff.exs ...` passed
  36/36 trials: 3 repeats x 1/8/32 scopes x 0/2 ms sink delay x direct/adopted
  ownership. It completed 3,936 TTS turns, 3,936 independent STT turns and 492
  intentional Output failures/replacements. The maximum recorded post-trial
  process count was 245; peak post-trial total memory was 87,879,772 bytes. Evidence:
  `20260920-0745-tts-handoff-split.json` and matching `.log`.
- Interpretation: the clean handoff lane freezes current split-topology behavior;
  the cancellation lane proves the already-approved pending-Input defect is also
  reachable under concurrent load before the Channel ownership change. It is not
  a new regression caused by the integration.

## D2 implementation, tested pause and repair

- Moved the single authoritative TTS request, credit, playback and fence state
  into Channel, kept provider calls in Input, routed provider chunks and consumer
  audio operations to Channel, removed the Output child, and updated Morse/tests.
- The original paired regression turned green: 3 tests were expected after the
  later review case was added; before that addition the two arrival-order cases
  passed. The full focused TTS selection passed 24 tests, and the speech/Morse
  selection passed 124 tests (seed 530504).
- Merged production cancellation load passed 18 trials and 5,904 complete
  cancellation/replacement/STT cycles. Merged handoff load passed the same 36
  trials, 3,936 TTS turns, 3,936 STT turns and 492 intentional allocation faults
  as the split baseline. Reports and raw logs are retained beside this labnote.
- The isolated post-integration adapter ramp produced one failed report: merged
  first-audio p99 crossed the 10 ms gate at 8 and 32 scopes, while split first
  missed at 64. Two fresh identical reruns passed with split/merged first misses
  of 64/64 and 32/128. The adapter runtime did not change with the production
  merge, so the failure is preserved as an unexplained, nonrepeated threshold
  miss rather than attributed to the production change.
- Root format and warnings-as-errors compile passed. Root Credo then rejected the
  930-line Channel, requiring a cohesive pure-state extraction or equivalent SRP
  refactor before acceptance.
- Independent review found a lifecycle gap. The added test `clean rejection after
  fencing settles when cancel arrives later` fences while provider acceptance is
  pending, releases a clean rejection, acknowledges the exact failed event, then
  calls `cancel(ticket, 0)`. The seed-530504 run produced 3 tests, 1 failure:
  Channel crashed in `record_playback/2` because rejection had cleared `request`
  while retaining `cancellation`; the facade returned `{:error, :closed}`.
- This reproduced instability in the in-progress D workflow through the public
  API. No repair preceded the user's approval, and work paused under the user's
  tested-instability instruction.

## Approved clean-rejection repair

- The user authorized the repair. A clean provider rejection under an active
  fence now retains only the bounded terminal request facts needed for settlement,
  including the playback ceiling. A later authorized `cancel(ticket, 0)` records
  local playback and settles the fence without calling provider cancellation or
  inventing a cancelled event. A queued cancel uses the same path. Replacement
  stays blocked until settlement, the original fence timer is cancelled, and a
  duplicate cancel replays the cached playback result.
- Red/green evidence: the public-boundary case first crashed Channel and returned
  `{:error, :closed}` (3 tests, 1 failure, seed 530504). The unchanged command now
  passes all 3 cases. The complete focused TTS selection passes 25 tests, and the
  speech plus Morse selection passes 125 tests with the same seed.
- The final production cancellation lane passes 18/18 trials: 5,904 cancellation,
  replacement and independent STT cycles, with 244 processes after every trial.
  Evidence: `20260920-0745-tts-cancellation-final.json` and matching `.log`.
- The final production handoff lane passes 36/36 trials: 3,936 TTS turns, 3,936
  independent STT turns and 492 intentional Channel failures/replacements, with
  245 processes after every trial. Evidence:
  `20260920-0745-tts-handoff-final.json` and matching `.log`.
- The first isolated post-integration topology report remains preserved. It
  crossed the merged first-audio budget at 8 scopes while split first crossed at
  64. Three consecutive identical reruns passed with split/merged first misses of
  64/64, 32/128 and 128/128. This adapter uses the production Morse encoder/decoder but does not run
  the production Channel merge, so the nonrepeated miss is not causal evidence of
  a production regression. These reports do not establish production fixed-budget
  latency parity.
- GPT-6 Astra xhigh re-reviewed the final source and found no remaining blocker
  for this bounded D2 repair. The extracted `OutputState`, `EventQueue` and
  `TTSFlow` modules are pure state/workflow code and add no process, authority
  owner, registry or callback cycle. Channel remains the sole output-state owner;
  Input remains the blocking provider worker.
- Root format, warnings-as-errors compile, Credo and unused-dependency gates pass.
  The first complete umbrella test run exposed two timing cases outside the
  changed path; both pass together in isolation with the same seed. A second run
  exposed three new TTS tests waiting only 500 ms for readiness even though their
  public startup budget is 5 seconds, plus one existing WebRTC case. The WebRTC
  case passes alone. The TTS tests now use the public startup budget for readiness
  only; their request and cancellation assertions retain their tighter bounds.
  The full 807-test Call Engine suite passes with zero failures at seed 530504.
  The complete umbrella then passes 1,905 tests with zero failures and 40 excluded
  at the same seed. Root format, warnings-as-errors compile, strict Credo and
  unused-dependency checks also pass. D2 and D2b–D2d are accepted; D4/D5 and Exit D
  remain open.
