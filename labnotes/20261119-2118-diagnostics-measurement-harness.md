# Diagnostic resource measurement foundation

## Decision and scope

The existing Engine call-load runner targets other speech scenarios and does not
exercise the configured Calls diagnostic collector/persistence path. It cannot
satisfy this milestone's paired workload gate. Build the required external process
measurement path using the standard library, keeping application CPU accounting
separate from the generator and database.

This checkpoint adds only the reusable Linux resource sampler, interval summary
and predeclared CPU/RSS comparison. It does not yet drive the configured calls,
schedule external PCM, enforce all latency/coverage gates or run the paired matrix.
Those remain necessary; no milestone measurement checkbox is checked.

`/proc/PID/stat` supplies aggregate process CPU ticks and start identity; `status`
supplies RSS/high water/thread count, including native allocations. Reading BEAM
heaps alone was rejected because it omits native memory. Samples retain process
identity, timestamp, CPU, sampled RSS, OS high water and thread count. Missing or
invalid samples, process replacement and backwards counters fail explicitly.

Lifetime high water can contaminate a warm interval: a larger pre-window peak in
the disabled phase can mask memory regression during its measured phase. Reset
only the isolated test VM's high-water counter at the declared boundary, using
[Linux procfs clear_refs value 5](https://www.kernel.org/doc/html/latest/filesystems/proc.html).
The helper marks the initial sample and refuses unscoped or mid-interval resets.
This resets accounting only; no GC, memory freeing or workload change. Permission
or platform failure invalidates measurement. The measurement plan now records
this clarification before running the actual workload, with unchanged budgets.

Resource comparison uses 0.05 + 0.03*N fallback cores, 0.02 + 0.005*N reuse cores,
and (128 + 8*N) MiB peak RSS. Every matched pair still must satisfy the complete
plan; this helper's resource result alone cannot be reported as load acceptance.

## Verification

Small focused tests were written first. Initial import failed with the expected
missing `measurement` module. Initial implementation passes 8/8 standard-library unittest
cases: tricky process-name parsing, CPU delta, PID replacement, missing/invalid
samples, scoped high-water accounting, different inference-mode budgets, a native
high-water spike between samples and invalid capacity/mode rejection.

```sh
python3 -m unittest discover -s scripts/diagnostics -p test_measurement.py
```

A local isolated Python child (no provider or production process) acknowledged
readiness, then allocated and held 20 MiB after `begin_interval`. The sampler
observed at least 19 MiB RSS growth, peak RSS/high water 30252 KiB, one thread,
and 0.01 CPU seconds over approximately 0.01 seconds. This is an OS-interface
smoke check, not a precise short-window CPU benchmark or actual-Silero measurement.
The child exited normally after acknowledgement.

Root format, warnings-as-errors compile, strict Credo and unused-lock checks pass.
Independent review reproduced an exact-budget rounding failure: 400 versus 560
CPU ticks at 100 Hz over 20 seconds should yield an allowed 0.08-core delta, but
floating subtraction yielded 0.08000000000000004 and rejected it. Root reproduced
the failure and added a permanent regression before the fix (9 tests, one expected
failure). Comparison now permits only four ULPs of arithmetic roundoff, reports
that allowance explicitly, and preserves the numeric engineering budget. The
regression also rejects a 0.000000001-second excess CPU total. All 9 tests pass.
Final independent Astra xhigh design/code review is clean: repository tests 9/9
and isolated review probes 4/4 pass. Probes verify inclusive CPU boundaries,
one-extra-tick rejection, both PID-replacement fences and real high-water reset
excluding a released pre-phase allocation. This is helper/design acceptance only;
the actual configured paired workload gate remains open. No full suite, live providers,
deployment, or production configuration changes.
