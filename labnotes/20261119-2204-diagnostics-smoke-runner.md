# Diagnostics smoke runner

## Checkpoint

Added a reusable external watchdog for the four configured real-Silero functional
smoke cases. Run `python3 scripts/diagnostics/smoke_runner.py --output NEW_DIRECTORY`
from the checkout. This is tooling for E acceptance, not the complete paired-load
matrix or acoustic accuracy evidence; those checklist items remain open.

The runner requires an ordinary checkout user and noninteractive sudo for its
own uniquely named system scope. It enforces CPUs 0–1 for the VM, retains the
existing generator CPUs 2–3 and 45-second/2-second service bounds, samples every
100 ms, and invalidates memory, affinity, deadline or process-identity violations.
The measured scope has a 300-second lifetime and two-second stop timeout. Output
records source/model hashes, raw samples, four functional reports and cleanup
errors. Existing output directories are refused. Configured tests register exact
run-owned generator unit names before starting them so the watchdog can clean up
even if ExUnit does not reach its own cleanup.

Cleanup stops only this run's system scope and registered user generator units.
Failures remain invalid evidence; finite unit lifetimes are the fallback when
explicit cleanup cannot finish. No production unit or provider settings changed.

## Red-green and review evidence

- Initial missing-module test established the runner contract. A kill timeout
  subsequently reproduced skipping generator cleanup; nested cleanup handling
  now preserves that attempt. Zero-duration completion evidence was also rejected
  after a failing control.
- Astra review reproduced two further failures: replacing the measured VM between
  samples still passed, and two malformed registrations hid a later owned unit
  from cleanup. Root independently reproduced both in
  `/tmp/vxpipe-smoke-review-root-red.log`; permanent tests failed for those same
  reasons before the fixes. Identity is now fenced across samples, and invalid
  lines mark the run invalid while remaining registrations are still scanned.
- Final Python selection: 26/26 passed. Independent Astra probes passed, with no
  remaining source findings. Cleanup command assertions exercise the actual
  subprocess boundary rather than an unused helper.
- Root format, compile with warnings-as-errors, strict Credo and unused-dependency
  checks passed. Full suite remains deferred until milestone implementation ends.

## Actual workload verification

The initial runner completed all four cases with 249 resource samples. After the
review fixes, `/tmp/vxpipe-smoke-runner-reviewed/` retains the final log and JSON
report: four tests passed in 23.2 seconds, 256 samples, exit zero, no abort and no
cleanup errors. Maximum sampled VM RSS was 844,028 KiB; minimum available host
memory was 2,399,200 KiB. Observed native thread masks were `0-1` and `1`.

Each mode sent 64 frames over at least 2.048 seconds. Generator p95 write lateness
was 0.042 ms (VAD off/collection off), 0.834 ms (off/on), 1.795 ms (on/off), and
0.056 ms (on/on), all below the unchanged 2 ms limit. The test asserts real Silero
execution on generated audio when applicable, exact provider bytes, canonical
control events, expected persistence, room termination and diagnostic drain.

These are functional smoke measurements with synthetic providers and real pinned
Silero. They do not establish full paired throughput/latency or durable-write
costs under production transaction semantics. No live provider/Telnyx test or
production deployment was performed.
