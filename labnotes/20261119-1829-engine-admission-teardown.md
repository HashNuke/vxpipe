# Engine admission teardown

## Acceptance gap and fixture

The earlier controlled-root admission test used generic Agents; actual planned-room
completion was verified separately. This checkpoint combines the real Engine
application root, a real planned room, room-owned SourceWorkers in operational
reuse and fallback modes, and an unreturned worker start. It runs in an isolated
peer VM, leaving the parent test runtime and deployed service untouched.

The peer starts its own enabled settings projection and synthetic inference runtime.
SourceAdmission admits the real workers under the actual room diagnostic worker
supervisor. A test-only start wrapper creates a third real SourceWorker but holds
its start_link result; a system callback injects that start into the actual
AttachmentRunner's IO process. This tests unresolved-start ownership and shutdown,
not accepted-STT discovery (covered elsewhere). The pending worker, normal workers,
runner and Engine root are individually monitored.

Engine stop kills the runner but cannot complete while its worker supervisor still
has the unresolved start. A concurrent application restart request also waits,
with the old gate still present. Releasing the start permits teardown; all three
old workers and the old root must be DOWN before the fresh gate is inspected and
new admission succeeds. The test does not change production startup or stop logic.

## Verification so far

Initial fixture runs exposed missing ExUnit configuration in the peer and missing
synthetic diagnostic_capacity; both fixture requirements are now explicit. The
real-root test passes, including concurrent restart. Focused Engine diagnostics
and application checks pass 239/239; root static gates pass. Independent review is
running. The held start is unconditionally released in an after block, including
when an assertion fails, so diagnostic fixture cleanup cannot hide the original
failure behind a blocked application stop.

The ordering oracle was strengthened before final review: ordinary admitted PIDs
must exactly match the real room worker supervisor's children, and the blocked
start wrapper must execute in that supervisor. Immediately after Application.stop
returns, the stop task creates fresh monitors for all three old workers and
requires noproc. Waiting later for normal DOWN would allow a post-root grace
period to hide overlap. The strengthened probe passes 1/1. The generic startup
result is received before entering the unconditional-release block, so even a
failed child start cannot strand the wrapper before cleanup is installed.

## Final review and acceptance

Independent scoped Astra review is clean. Three independent probes pass: real-root
teardown, an assertion raised while startup is held, and a failed startup result.
Both fault controls return the intended ExUnit assertion promptly rather than a
peer timeout. Review confirms actual room-worker membership, executing-supervisor
identity and the immediate noproc oracle. The final stronger parent probe passes
1/1, following the 239/239 focused Engine/application selection. Static gates pass.
No runtime changes require a new Lean run. The milestone's port/admission/root
teardown task is checked using this proof plus the retained absence/restart tests.
The broader lifecycle matrix and settings/UI/E/F work remain open.
