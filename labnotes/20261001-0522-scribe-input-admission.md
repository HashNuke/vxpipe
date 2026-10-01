# Scribe input admission

## Trigger and evidence

The first selected configured-service live room case fails after startup near
initial input, one test, one failure, one exclusion, seed 127428. The room's STT
capability retires as `provider_failed` and a subsequent frame returns unavailable.
That result does not establish the exact original native/provider cause.

Inspection shows two concrete local risks. Scribe rejects a new accepted frame
while its classifier is active; ordinary room delivery treats that rejection as
provider failure. Separately, the native fixture test reproduces an activity
Task.Supervisor admission failure: its hard one-child quota can still count a
finishing worker after ActivityRuntime has published the result and released its
own slot. The supervisor failure is redacted as intended.

## Red/green change

Two focused Scribe checks fail because the second frame is rejected as busy.
Their module initially reports eleven tests and three failures, seed 513171;
the third is the native fixture's task-supervisor race above. A separate modeled
result-before-worker-retirement check first fails in the activity runtime:
eight tests, one failure, seed 104507.

Keep one executing native classification job. Accept additional aligned input
into a bounded PCM buffer and classify it in order when the worker settles. The
existing 96,000-byte retained-input budget now includes the executing chunk and
pending input, as well as recognition and acoustic assembly. Full capacity
still rejects admission; cancellation discards pending PCM with the allocation.

ActivityRuntime retains result and job ownership until the task monitor reports
termination. It publishes outcome and releases admission together at that point.
The runtime's explicit job budget remains the concurrency authority, including
cancelled native jobs until actual retirement. Remove the redundant task-supervisor
quota whose separate bookkeeping races with this ownership decision. Preserve
allocation supervision and fixed safe failure/status output.

The combined Scribe session, compiled room, activity runtime and supervisor suite
passes all 23 checks, seed 200165, including ordered queued PCM, capacity rejection,
hard worker cleanup, result/retirement ordering and packaged native inference.
Final root and Lean gates remain pending. Retry only the failed configured-service
live case after its local harness passes; do not repeat earlier paid successes.

## Broader checkpoint evidence

The subsequent complete source passes all 1,822 CallEngine and 195 Console
checks. The root run finishes with 3,031 tests, two Gateway harness failures
and 97 exclusions, seed 232973. Those failures remain under separate acceptance
investigation; this checkpoint does not claim the final umbrella gate passed.
Format, warnings-as-errors compilation, strict Credo and unused-dependency
checks pass. Lean build/oracle/replay passes one check, seed 116049.
The selected configured-service live retry passes one test, seed 608205,
in 25.8 seconds; earlier paid successes are not repeated.
