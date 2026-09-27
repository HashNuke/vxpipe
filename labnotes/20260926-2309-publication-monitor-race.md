# Publication worker monitor race

Date: 2026-09-26. Starting revision: `68fa5a56`.

## Finding and decision

- During the GPT-Live Package 8 umbrella gate, the CallEngine suite passed
  1,666 tests, then `Vxpipe.Calls.PublicationWorkerTest` failed because the
  publication worker completed before the test installed its monitor. The
  test received a `:DOWN` reason of `:noproc` after all publication events
  had arrived, while it asserted `:normal` only.
- Keep the completion and publication assertions. Accept `:normal` when the
  monitor attaches before exit and `:noproc` when it attaches afterward.
  Both paths prove the worker is gone after publication; this changes only
  the test's scheduling assumption. The same race exists in the retry and
  deadline cases, including the attempt monitor, so those assertions use
  the same bounded reason sets.

## Verification

- Initial umbrella suite: 120 Calls tests, one failure in this assertion.
- Focused Calls file after the fix: six tests, zero failures. The final
  umbrella rerun passed Calls' 120 tests and all 2,859 tests with zero
  failures and 59 tagged exclusions.
