# Diagnostics inference overhead

## Evidence and scope

Continue from the single-thread Silero checkpoint (`ed1fefd1`). The one-source
fallback CPU delta still exceeds the predeclared budget. Keep production scheduler
settings, model behavior, source admission and numerical budgets unchanged.
Artifact names below refer to the host temporary directory.

`vxpipe-inference-cpu-profile` repeats the fixed warm workload with per-thread
counters and perf sampling restricted to that isolated test VM. The profiler uses
its own target PID after verifying its process start ticks; no host profiling
policy or production process is changed. It captures 287 user-space CPU samples,
with no lost samples. The report (`vxpipe-inference-cpu-perf-report.txt`) attributes
47.38% to scheduler_wait/sched_spin_wait across normal and dirty schedulers.
This is diagnostic evidence, not performance acceptance of an instrumented run.

A separate temporary function-timing probe initially returned inactive patterns:
the target modules had not loaded when trace patterns were installed. That artifact,
`vxpipe-inference-function-profile`, does not prove function costs. The corrected
`vxpipe-inference-function-profile-loaded` explicitly loads each module and asserts
one matching function before tracing. It records 869 report builds, with 242395
microseconds charged to LiveReport.build, 30259 to SegmentProjection.build and
53850 to LiveReport.observe; Silero.push records 780 calls and 583988 microseconds.
These call-time entries are profiler observations, not a partition of all VM CPU.
Temporary fixture instrumentation is restored byte-for-byte before ordinary tests
and the uninstrumented native run.

## Change and invariant

A progress frame previously rebuilt every historical report. Existing same-origin
epoch progress can change report coverage only when it reaches a mapped provider
sample end. Retain the existing reports and unattached segment envelope between
those thresholds. The cursor itself always advances in retained packets, so later
canonical events and caller-supplied segment intervals use current evidence.

The predicate scans provider ends conservatively, even before canonical linkage:
`old_finalized < source_origin + samples - provider_origin <= merged_finalized`,
with a valid mapping and provider sample range. First progress and every other
packet kind still rebuild the full projection. Keep origin/epoch validation,
closed-epoch rejection, packet ordering and final retained-byte limits unchanged.
No new cache/index state or changed persistence behavior is introduced.

## Focused verification

- `vxpipe-report-progress-cost-red.log`: 100 unchanged progress updates after 16
  completed turns cost 6,786,559 process reductions, failing the predeclared 500,000
  regression bound. `vxpipe-report-progress-cost-green.log` passes after the change.
  Process reductions avoid wall-clock timing noise; this is not the milestone CPU
  budget or proof of whole-call overhead.
- `vxpipe-report-progress-green.log`: all 47 LiveReport tests pass. New controls
  cover nonzero mapping origins, exact inclusive coverage crossing, unchanged
  revisions before/after crossing, late mappings/boundaries, reset rejection,
  first observed empty evidence and updated caller-supplied segment intervals.
  Duplicate mapping events force the full projection path and must return exactly
  the same state as optimized cursor updates.
- `vxpipe-progress-cache-warm-fallback-on` passes the uninstrumented configured
  workload: ten measured completed turns, 625 measured frames, 201 resource samples,
  source-native readiness, correct durable rows and clean owned-resource teardown.
  Process CPU is 3.02 seconds / 0.151012 cores over 19.998393 seconds; interval HWM
  is 259188 KiB and measured PCM p95 is 317766 ns. LiveReport source is included in
  the runner's provenance alongside the model, binding and workload sources.

The enabled workload improves from 3.44 to 3.02 CPU-seconds in these single runs.
Compared with the preceding disabled phase's 0.042000 cores, the approximate delta
is still 0.109012 cores, above the one-source 0.08-core limit. This is not a fresh
matched pair or final acceptance. Further overhead work, repeated pairs, full
coverage, latency and cold gates remain required; the pilot stays disabled.

## Final independent verification

GPT-6 Astra xhigh review is clean. Its pre-change/current-module differential
control compares 64 deterministic scenarios: 3,145 accepted states (1,842 progress
packets) and 1,015 identical rejections. Full state and custom segment projections
match (`vxpipe-progress-cache-differential-review.log`). Its focused run passes
47/47 (seed 436584, `vxpipe-progress-cache-focused-review.log`). The native artifact
audit recomputes raw resource/pacing evidence, cleanup and all 18 provenance hashes
(`vxpipe-progress-cache-artifact-review.log`).

Root format, warnings-as-errors compilation, strict Credo and unused-lock checks
pass in `vxpipe-report-cache-format.log`, `vxpipe-report-cache-compile.log`,
`vxpipe-report-cache-credo.log` and `vxpipe-report-cache-deps.log`. Diagnostic Python
checks pass 53/53 (`vxpipe-report-cache-python.log`); changed documentation links
and whitespace checks pass. No source-cutover or speech state-machine behavior
changed, so no new Lean run is claimed.

No full suite, live provider/Telnyx calls or production restart is performed for
this checkpoint. The milestone remains incomplete with its existing budgets.
