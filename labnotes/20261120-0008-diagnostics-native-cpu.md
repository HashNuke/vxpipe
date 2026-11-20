# Diagnostics native CPU

## Investigation and decision

Follow the warm workload's high fallback CPU result. The previous checkpoint is
pushed at `e938c1ef`; this checkpoint changes production session configuration,
not benchmark-only behavior. The [design decision](../docs/design/silero-native-threading.md)
records evidence, rejected alternatives and implications.

Artifacts below are in the host temporary directory. `vxpipe-native-cpu-profile`
is a configured warm fallback-on probe with per-thread proc counters. Three threads
created during model loading consumed 31.91 of 33.69 sampled thread CPU-seconds;
the existing calling dirty-I/O thread consumed 0.56 seconds. Names are inherited
from that thread. Perf was denied by the existing perf_event_paranoid policy;
no system-wide setting was changed. The configured workload completed and cleaned
its owned database/unit; profiling makes this diagnostic evidence, not paired
performance acceptance.

The pinned Ortex and current upstream expose no session-thread parameter. Reuse
the repository's checksum-pinned dependency patch workflow to expose one optional
intra-op count, preserving default zero and legacy arities. Production Silero
passes one. Sequential graph execution means no inter-op setting is needed.
The NIF decodes i32 and rejects negatives before conversion to usize; overflow and
nonintegers fail decoding. Model weights, capacities and numerical budgets stay fixed.

## Focused verification

- `vxpipe-native-thread-red.log`: isolated Linux regression fails with three newly
  created workers. An initial launch omitted MIX_HOME/HEX_HOME and failed before
  tests; the corrected wrapper preserves the same four environment keys as the
  workload runner. Only the terminal three-worker failure is red evidence.
- `vxpipe-native-thread-green.log`: 3/3 for no extra worker pool, invalid native
  counts and legacy loading arities. Fresh VM uses its own transient scope,
  AllowedCPUs 0–1, MemoryMax 1 GiB, RuntimeMax 120 seconds and two-second stop.
- `vxpipe-single-thread-silero-green.log`: existing probability reference, chunking,
  reset, invalid input, silence/tone/noise and supervised inference tests pass 4/4.
- `vxpipe-ortex-patch-red.log`: five preparation tests fail before the installer
  exists. `vxpipe-ortex-patch-green.log`: 5/5 for pristine/repeated application,
  modified patch, unknown sources, wrong revision and mixed-state preservation.
- Setup initially failed because its dependency mocks did not stub the new patch
  command. After updating the mock and expected compilation sequence, plus checking
  Ortex patch failure stops setup, `vxpipe-ortex-setup-green.log` passes 35/35.
- `vxpipe-native-cpu-python.log`: diagnostic runner checks pass 53/53. Provenance
  now includes the patch/manifest, native sources and the compiled Ortex library.
- Ortex test compilation succeeds; existing upstream Rust lifetime warnings remain
  unrelated to the patch. No dependency version or model checksum changed.

## Configured warm evidence

Both `vxpipe-single-thread-warm-fallback-on` and
`vxpipe-single-thread-warm-fallback-off` complete the one-room/one-human phase with
ten measured canonical completions, 625 measured frames, 201 resource samples and
clean owned-resource/database teardown. Maximum VM threads remain 11 in both.
The enabled phase uses 3.44 CPU-seconds / 0.172008 cores; disabled uses 0.84 /
0.042000 cores. Measured PCM p95 is 239023 ns enabled and 342041 ns disabled.
Interval HWM is 286676 KiB enabled and 206108 KiB disabled.

The worker-pool fix reduces enabled process CPU from the previous 34.17 seconds
by about 90%, while preserving model and configured call behavior. However, this
single new on/off comparison still has a 0.130008-core delta, above the declared
one-source fallback budget of 0.08 cores. The fix is useful but does not pass that
gate. Investigate the remaining cost; do not raise the budget or enable the pilot.
Full alternating repetitions, coverage, latency and cold acceptance remain open.

The two-room/two-human `vxpipe-single-thread-warm-reuse-on` phase passes with
measured turn counts 10/11/10/10, 2500 measured frames, 201 samples and all four
source readiness deadlines. Process CPU is 10.91 seconds / 0.545510 cores, maximum
threads 11, interval HWM 296124 KiB and measured PCM p95 235540 ns. Cleanup is clean.
This is reuse correctness evidence, not a paired reuse-budget comparison.

Dev and test Ortex compilation succeed. Root format, warnings-as-errors compilation,
strict Credo and unused-lock checks pass in the `vxpipe-native-cpu-*.log` artifacts.
All three configured artifacts' 17 provenance hashes still match after dev
compilation. Changed documentation links and whitespace checks pass. No speech
state machine or source-cutover behavior changed; no new Lean run is claimed.

## Review correction: cold dependency compilation

Independent review reproduced a fresh-build failure in the initial setup/CI/release
commands: compiling only Ortex before its dependencies raises unavailable Rustler
and Nx.Container errors (`vxpipe-ortex-bootstrap-review.log`). Cached builds had
hidden the issue. All three paths now compile Ortex with `--include-children`;
the setup command-order test tracks this dependency order. The independent retry uses the same isolated empty BEAM build directory and
passes (`vxpipe-ortex-bootstrap-green-review.log`), compiling Rustler/Nx and the
other children before Ortex. Cargo reuses its native cache: this proves clean BEAM
dependency bootstrap, not a pristine Rust toolchain rebuild. The CI dependency
cache key includes the Ortex patch files, and its fresh build runs the native
thread contract separately from the default suite. Setup passes 35/35 again.

No Telnyx/live provider tests, full umbrella run or production restart was performed.
Final GPT-6 Astra xhigh review is clean after the reproduced bootstrap correction.
The reviewer independently passes installer tests 5/5, verifies all three warm
artifacts against raw resource/pacing evidence and all 17 provenance hashes, and
confirms API compatibility, argument validation, build paths and documentation.
The remaining fallback CPU budget miss remains explicit and blocks pilot acceptance.

The final staged whitespace check reported the unified patch's required single-space
blank context markers; the commit command continued despite that nonzero check.
A narrow Git attribute exempts the Ortex patch artifact from source whitespace
rules without changing its bytes, checksum or applied source. `git show --check`
then passes for the runtime checkpoint. This is a follow-up metadata correction;
no history is rewritten and no native evidence is relabelled.
