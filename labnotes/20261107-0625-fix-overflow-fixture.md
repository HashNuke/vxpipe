# Observe terminal speech overflow through its owner

The second listed OAuth umbrella run (seed 181095) passed the corrected admission
test but failed the unchanged speech-to-speech pending-caller-overflow test. The
seventeenth fixture `GenServer.call` exited `:killed`. That event intentionally
stops the capability and retires its provider. The channel can deliver the event
before its reply reaches the provider, allowing retirement to kill the provider
before the outer call replies. Independent source review confirmed this ordering.

The fixture now accepts an asynchronous emission for this terminal event. The
test retains the first sixteen synchronous emissions and observed events, then
asserts the exact overflow notification, capability exit reason and provider/tree
termination. It no longer waits for a reply from the process being retired.
Production state-machine behavior is unchanged; Lean verification is not required
for this test-only synchronization correction.

Verification: the corrected focused test passes fifty repetitions with the failing
seed, and the complete 63-test file passes. Independent adversarial source review
found no remaining issue. The second umbrella run was interrupted after its known
failure; a clean full rerun remains an open acceptance gate.
