# Acknowledge the admission monitor

The listed OAuth checkpoint's first full umbrella run (seed 181095) failed the
unchanged outgoing-call test for loss of a pending admission controller. Its
monitor received `:noproc` instead of the exact expected
`{:shutdown, :outgoing_admission_abandoned}` reason. The focused test then passed
50 same-VM repetitions, and the complete 29-test file passed five repetitions.
Those passes establish intermittence, not the cause of the original execution.

Independent source review identified a concrete race consistent with the failure.
OTP 28.5 documents monitor requests as asynchronous signals. The test created an
owner monitor, then sent `:finish` to a different controller process. That
controller's established monitor could notify the owner before the test's monitor
was installed; ordering across different senders is not guaranteed.

After creating the monitor, the test now calls the existing owner
`readiness_binding/1` operation and asserts `{:error, :startup_preparing}` before
terminating the controller. The call/reply acknowledges the earlier same-sender
monitor signal and checks the intended pending-admission state. The exact DOWN
reason and no-dial assertion remain unchanged. No production state machine or
runtime behavior changed; the Lean lane is not required for this test correction.

Verification: the synchronized focused test passes 50 repetitions and all 29 tests
in the complete file pass. Independent adversarial exact-index review is clean.
The subsequent full umbrella rerun passes all 4,931 tests (201 excluded, seed 181095).
The correction is also tracked in the Integrations milestone acceptance tasks.
