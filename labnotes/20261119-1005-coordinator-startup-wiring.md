# Coordinator startup wiring

Previous checkpoint fb21396f is pushed and both Astra reviews are clean. Its frozen
root suite is still running; no runtime/test/build files changed during that run.

Next contract: one local coordinator-owned helper executes the whole attachment.
The coordinator remains responsive, adopts only a current result before the startup
deadline, and cancels the lease before killing an expired helper. A normal shutdown
must explicitly retire the helper; abrupt coordinator death is fenced by links and
lease ownership. Active worker monitors must be installed by the coordinator,
never by the short-lived helper. Source context carries the real coordinator PID.

The whole attempt and all nested supervisor operations share one startup lease.
Unknown killed admission retains its capacity debt. SourceSupervisor receives a
shared gate from its parent (eventual Calls diagnostics root); restarting just the
source subtree must not reset admission debt while collector/writer queues survive.
Standalone test source pools can own their gate because their collectors are fake.

A temporary test copy outside the worktree probes the currently blocking collector
callback while the frozen root suite runs. The first selection used a setup line
and excluded all tests; that invocation is not verification. The corrected test
selection is line150 in /tmp/vxpipe_coordinator_startup_probe_test.exs.

The corrected stalled-factory probe failed1/1: SourceCoordinator.status timed out
at250ms while the factory was blocked. Prepared candidate source files under
/tmp/vxpipe-coordinator-wiring without changing runtime/test/build files in the
checkout. A separate Mix test VM uses Code.compile_file to load those candidates
in memory only (no beam writes): the same probe passes1/0. Whole attempt admission
and worker startup share the lease, real coordinator PID is preserved, and worker
monitor creation moves to successful coordinator adoption. Candidate baseline
coordinator tests are now being checked for asynchronous transition expectations.

Existing coordinator tests initially failed10/16 against the candidate because
collector-start notification no longer implies attachment completion. Updated the
temporary test copy to poll the existing status boundary until pending=false with
a2s deadline; no sleeps or process-liveness assertions. Candidate16/0 passes.
Additional baseline probes reproduce blocked worker admission (status timeout) and
the absence of a separately owned helper on normal coordinator shutdown:2/2 red.
Expanded candidate suite is now running with both lifecycle cases.
Expanded candidate coordinator tests pass18/0, including real timeout cancellation,
normal shutdown helper retirement and blocked worker admission with retained debt.
Astra xhigh review of the exact candidate files is in progress while the prior
checkpoint's root suite remains live. No source/test files in the checkout changed.
Astra xhigh final review of the coordinator candidate is clean. Independent20/0
includes two additional cases: a completed helper result queued beyond its deadline
is rejected and releases resolved debt; abrupt coordinator failure retires the
helper while the explicit parent-supplied gate retains unresolved debt across
subtree restart. Both probes are included in the prepared retained test file under
/tmp/vxpipe-coordinator-wiring/source_coordinator_test.exs. The prior root suite has
passed Engine2752/0 and Calls445/0 and continues through later applications.

While waiting for the frozen root suite, a separate Calls composition probe failed
1/1 on missing coordinator (expected: configured parent starts a coordinator while
settings remain off). Candidate Calls supervisor source composition now passes1/0
in memory: /tmp/vxpipe-coordinator-wiring/calls_supervisor.ex and
/tmp/vxpipe_diagnostics_composition_candidate_test.exs. The parent owns the shared
startup gate and injects the real Attachment factory, selected projection and
persistence pools; source supervision remains lazy while off. This composition
candidate is not yet reviewed or applied. One initial command used a root-relative
copy path from the Calls child directory and failed before making any edit; it is
not verification evidence. Runtime Application configuration remains unimplemented.
The parent composition candidate now passes2/0: off does not load a model or create
collectors, and explicitly restarting only the source child preserves the parent
admission gate/reservation; replacing the entire diagnostic parent creates a fresh
gate after its old destinations are gone. This candidate remains unreviewed.
Frozen prior-checkpoint suite now also passed Gateway891/0 and the20-test package;
Persistence and Console remain running/pending.

Frozen fb21396f root suite completed with exit0 before applying any candidate:
106/222/35/567/2752/445/891/20/580/591 tests, all0failures (standard exclusions).
This verifies the startup-factory checkpoint and prior acknowledged-profile changes.
Applied the reviewed coordinator/source attachment/source supervisor candidates and
retained20-case coordinator test to the checkout. Focused Engine diagnostics and
root static/Lean checks now run on the actual files. Calls composition remains in
/tmp only until its review and Application integration are ready.
Actual checkout Engine diagnostics149/0 pass, as do root formatting, compile with
warnings-as-errors, strict Credo, unused-lock checks and Lean. Astra's20/0 reviewed
candidate is identical to the applied runtime code. This source-coordinator slice
is ready to commit; the prior root suite is baseline evidence, not verification of
these new source changes. Parent/Application production composition continues next.
