# Private cleanup race

## Evidence and scope

The previous goal turn made concrete progress: four tested commits landed, including a
deterministic fix for handoff progress after destination promotion. The remaining inline
credential/schema checkpoint has 111 staged paths. Its latest umbrella run has one failure
in the native private-media cleanup test (`:noproc` instead of `:shutdown`), with all other
applications passing. No test process remained running at the start of this continuation.

## Monitoring before preparation

- Moved the native test's connection monitor to the first confirmed connection binding.
  Added nonblocking assertions that the connection has not exited before or during private
  candidate preparation. This preserves the expected shutdown reason and prevents a premature
  exit from being mistaken for the deliberate target failure.
- The three private-media cleanup variants pass with those stronger assertions: **3 tests,
  0 failures, 65 excluded**, seed 235296. No production behavior changed, and this isolated
  result does not establish the cause of the earlier exit.
- Source review: Collector termination cancels its probe task and timer; it does not directly
  own connection resources. PrivateMedia monitors speech and room-media actors, while the
  connection also watches its room, admission, peer and handoff gate. An earlier failure at
  one of those boundaries still needs evidence before changing production behavior.
- The complete native handoff file is running to check the surrounding-test context with
  the stronger lifetime assertions. Avoid further blanket umbrella retries without new evidence.
- The complete native handoff file passed **67 tests, 0 failures, 1 excluded**, seed 235296.
  The monitor-placement change is test hygiene, not evidence that the underlying earlier exit
  or earlier audio observations have been fixed. Keep the stronger checks in the migrated fixture.

## Umbrella closeout

The subsequent umbrella run passed **1,489 tests, 0 failures, 30 excluded**, seed 235296.
The earlier native Morse observation was documented in the primary checkpoint notes and now has
decoder-state context in its assertion message. These results support committing the migrated
fixture with its stronger lifetime checks, not claiming a causal fix for the intermittent exits.
