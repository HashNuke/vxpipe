# Owned catalog discovery

Baseline 9b0d75d9 is committed, pushed and clean. CatalogLoader still used open/2
and left its global session alive after discovery. This checkpoint moves that
existing operation to a temporary named host using the established session API.
Console ConnectionCheck already has an independent bounded lifetime and remains
unchanged; it does not need a new lifecycle implementation.

Initial boundary tests failed in four of five cases (seed 654947): no explicit
operation ownership or acknowledged cleanup on success/failure/caller death,
and a blocked discovery callback outlasted the configured budget. The loader now
links a temporary DynamicSupervisor to the caller and executes opening/discovery
in one bounded linked task. Providers must implement open/3 and return an exact
owned handle. The remaining absolute budget goes to Discovery. Cleanup stops
the task, retires exact owner sessions with the existing batch API, then observes
host termination; incomplete cleanup cannot publish success. Foreign handles are
rejected without changing their owner's session.

Astra's initial design review supported this local composition and identified
an embedding concern: an existing exit-trapping caller receives normal helper
EXIT messages. A project-boundary test reproduced it (7 tests, 1 failure,
seed 861863). Cleanup now consumes only the owned helper/host EXIT messages,
preserving the caller's flag and unrelated messages.

The final catalog loader/refresh/refresher/wire lane passes 24 tests,
seed 867653. It covers blocked open/discovery deadlines, caller death, foreign
handles, ordinary invalid-catalog cleanup, and real held initialize/tools-list
POST socket closure. Real protocol acceptance refreshes the same grant while an
agent session remains live, sees separate discovery sessions and their DELETEs,
then invokes a tool through the original agent session. The wire file now has
the explicit integration tag. Legacy fixture open/2 and global-key cleanup are
removed from these migrated callers.

Existing ConnectionCheck unit and real protocol regressions pass all 7 cases,
seed 195672, including success, caller cancellation and stalled DELETE sockets.
All five root gates pass. The umbrella suite completes 5,056 tests with zero
failures and 338 excluded, seed 349432. Format, warnings-as-errors compilation,
strict Credo and unused-dependency checks pass. Independent source and staged
documentation review finds no outstanding issues; the final evidence update
precedes commit. Local documentation links and staged whitespace checks pass.
The persistent tenant queue, timestamp work, renewal cancellation and library
ownerless API removal remain separate milestone work.
