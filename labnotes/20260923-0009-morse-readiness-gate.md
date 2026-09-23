# Morse readiness gate

2026-09-23 UTC. Branch `sts-impl`, after `2820daac`.

- A full call-engine child run at seed 473663 failed the Morse STS conversation
  test's ready assertion. Its isolated rerun passed 1/0. A post-commit run at
  the identical seed reproduced exactly the same 100 ms ready timeout and
  finished 1,414 tests, one failure, 30 integration exclusions. This is a
  deterministic suite-load reproduction, not a claimed Morse runtime defect.
- Added the specific repair and verification tasks to the STS milestone before
  editing the test. `start_session/1` awaited the asynchronous provider ready
  event with ExUnit's default 100 ms `assert_receive`; the allocation had
  already returned `:starting`. The test then requeues that event for its own
  public-contract assertion.
- Changed only this helper wait to an explicit 1,000 ms bound. This is a local
  supervised-provider initialization wait, not a request/turn/output timeout;
  it remains bounded and shorter than the allocation's five-second call budget.
  No production deadline or provider behavior changed.
- Focused rerun after the change: 1 test, zero failures. Same-seed full child
  rerun completed 1,414 tests, zero failures, 30 integration exclusions in
  115 seconds. The same seed failed 1,414/1 before the change; it passed the
  original failure point and the full suite after the bounded wait.
