# STT transport readiness

Date: 2026-09-26. Starting revision: `97e5c0af` plus uncommitted Package 8
transfer and publication-worker test work.

## Finding

- The first final umbrella run reached 1,668 CallEngine tests with one failure
  in `SpeechToTextTest`'s selected input-binding case. The test received the
  replacement fake transport's `started` notification, sent `Connected`, then
  timed out after one second waiting for the capability's connected signal.
  A focused rerun at the same seed passed one test.
- The fake transport sends `started` from its `init/1`, before its parent
  provider necessarily finishes `DynamicSupervisor.start_child/2` and stores
  the new wire in its state. Sending `Connected` immediately after the
  notification can race that binding. A provider state acknowledgement after
  the notification is the project-approved synchronization mechanism.

## Verification

- First umbrella run: CallEngine 1,668 tests, one STT failure; Calls 120 tests,
  zero failures. It was stopped during Gateway after the known failure.
- Focused STT test at the umbrella seed: one test, zero failures.
- The focused test now waits for the replacement provider's state after the
  transport start notification, before delivering `Connected`. This waits for
  the provider to finish binding the wire without a sleep or liveness probe.
  The full STT test file passed 23 tests with zero failures. The final umbrella
  rerun passed CallEngine's 1,668 tests and all 2,859 tests with zero failures
  and 59 tagged exclusions.
