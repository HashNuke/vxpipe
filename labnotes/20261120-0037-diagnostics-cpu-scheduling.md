# Diagnostics CPU scheduling

## Decision and red-green evidence

Production Silero's CPU execution provider now uses an explicit `Ortex.run_cpu/2`
entry scheduled as DirtyCpu. Legacy `run/2` retains DirtyIo, and both entries share
tensor conversion, result unpacking, errors and the native model implementation.
Initialization remains DirtyIo. No model, admission, source lifecycle, VM flags or
benchmark thresholds changed. Native execution remains in-process and cannot be
cancelled merely by retiring its task. The durable decision is recorded in
[Silero native threading](../docs/design/silero-native-threading.md).

Artifact names below refer to the host temporary directory.

- `vxpipe-silero-cpu-scheduling-red.log`: the new boundary regression failed because
  production Silero invoked the legacy I/O entry once, expected zero.
- `vxpipe-silero-cpu-scheduling-green.log`: 6/6 native contracts pass, including
  positive CPU-entry invocation, zero legacy-entry invocation, identical output
  bytes, scalar reuse, thread count, argument rejection and legacy load arities.
- `vxpipe-silero-cpu-reference-green.log`: 4/4 existing model probability,
  chunk/reset, silence/noise and supervised inference checks pass.
- `vxpipe-ortex-scheduling-upgrade-red.log` and
  `vxpipe-ortex-scheduling-state-red.log` retain missing-upgrade and unsafe
  checksum/previous-state failures. `vxpipe-ortex-scheduling-upgrade-green.log`
  passes all seven installer cases.
- `vxpipe-ortex-upgrade-independent.log`: independent review passes 10/10,
  including the actual committed prior patch and preservation of unknown/mixed
  previous edits. Both patch checksums are validated before mutation or success;
  a previous state must match the complete five-file manifest.

The ignored dependency was upgraded through the installer, then compiled using
`MIX_ENV=test mix deps.compile ortex --include-children`. The committed full patch
supports pristine downloads; the upgrade supports existing patched checkouts.
Measurement provenance now records all five applied dependency files and the
upgrade patch, 23 hashes in total.

## Measured evidence

`vxpipe-cpu-scheduler-warm-fallback-on` completes the configured one-input warm
phase with ten measured canonical turns, 625 measured frames, 201 resource samples
and clean scope/database teardown. Actual interval duration is 19.999059 seconds;
CPU is 2.63 seconds / 0.131506 cores, HWM 276180 KiB, maximum threads 11 and measured
PCM p95 lateness 234423 ns. Independent artifact review confirms raw timing,
resources and all 23 hashes (`vxpipe-cpu-scheduler-artifact-review.log`).

The enabled result is lower than the prior 3.26 CPU-second tensor-reuse run, but
one run does not establish repeated paired performance acceptance. Remaining topologies, coverage, response latency, cold startup and accuracy
gates remain open.

The fresh same-revision disabled phase
`vxpipe-cpu-scheduler-warm-fallback-off` also passes with ten measured turns,
625 measured frames, 201 resource samples and clean teardown. It uses 0.63 CPU
seconds / 0.031502 cores over 19.999019 seconds, HWM 198924 KiB, maximum threads 11
and measured PCM p95 lateness 262114 ns. The preliminary enabled-minus-disabled
CPU delta is 0.100005 cores, above the unchanged 0.08-core one-input budget.
This is a failed preliminary CPU budget comparison, not performance acceptance.
The HWM difference is 77256 KiB, below the 136 MiB one-input budget, but repetitions
and the full resource/latency/coverage matrix are still required. Both phases use
the same 23 artifact hashes; no historical disabled result substitutes for this
baseline.

## Verification environment

The first root compilation found a stale development Ortex BEAM without the new
entry; native tests had compiled the test environment only. Rebuilding the dev
dependency exposed the correct exported API, but Mix retained the earlier
cross-module warning. A forced compile of the owning Engine application refreshes
that compiler state before rerunning the root gates. Touching the source did not
clear the content-based cached warning. This is local build-state recovery, not a
source/API change or permission to omit warnings-as-errors.

Root format, warnings-as-errors compile, strict Credo and unused-lock checks now
pass (`vxpipe-cpu-scheduling-format.log`, `vxpipe-cpu-scheduling-compile.log`,
`vxpipe-cpu-scheduling-credo.log`, `vxpipe-cpu-scheduling-deps.log`). Diagnostic
Python tests pass 53/53 and retained installer tests pass 7/7
(`vxpipe-cpu-scheduling-python.log`, `vxpipe-cpu-scheduling-installer.log`).
No source-cutover or speech state-machine transition changed, so this checkpoint
does not claim a new Lean run. Full umbrella tests remain deferred until milestone
implementation is complete. No live provider/Telnyx test, production restart,
deployment or pilot activation occurred.

Independent GPT-6 Astra xhigh source, installer and paired artifact/documentation
review is clean (`vxpipe-cpu-scheduler-pair-review.log`). It independently
recomputes the preliminary CPU failure and confirms identical 23-hash provenance.

The subsequent two-room/two-input-per-room operational reuse phase
`vxpipe-cpu-scheduler-warm-reuse-on` also passes: measured canonical turns
10/11/10/10, 2500 measured frames, 201 resource samples, 19.999482 seconds,
8.48 CPU-seconds / 0.424011 cores, HWM 290944 KiB, maximum threads 11 and measured
PCM p95 lateness 211297 ns. Scope/database teardown is clean. This exercises
shared CPU inference with operational VAD and diagnostic reuse; no matched
reuse-off phase is claimed, so it is functional/topology evidence rather than
reuse overhead acceptance. Local links in all five changed documentation files
resolve successfully.
