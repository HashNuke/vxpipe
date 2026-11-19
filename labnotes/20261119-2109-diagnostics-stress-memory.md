# Diagnostic lifecycle stress memory

## Scope

Extend the existing 20-cycle configured lifecycle acceptance in both operational
VAD modes with the complete public connection-event oracle and optional Linux
process RSS samples after room completion and diagnostic drain. This uses the
existing deterministic classifier. The fallback pool still loads the packaged
Silero model, so RSS can include native model allocations, but inference uses
fixture probabilities. This measures lifecycle retention and cannot satisfy the
actual-model-inference paired load gate. No production behavior changes.
Acceptance-only additions can start green; no new runtime implementation is added.

Opt in with `VXPIPE_DIAGNOSTIC_STRESS_RSS=1`. Compare first-five and last-five
median process RSS against the predeclared 16 MiB growth budget. Print every sample
and both medians; do not force garbage collection or omit failing samples. Ordinary
test runs retain the full control-trace checks without requiring Linux procfs.

Run in a two-CPU-affinity test VM with two normal schedulers and an external
100 ms RSS/available-memory watchdog using the measurement plan limits. Retain
raw samples and command/environment metadata. No live provider or service change.

## Evidence

Measured configured selection: 2/2 pass, seed 0, 92.9 seconds. This covers
40 complete rooms, 120 canonical turns and 720 public connection events. Each
room has enabled, disabled and re-enabled turns and a completed resource drain.

| Operational VAD | First-five median KiB | Last-five median KiB | Growth KiB | Budget KiB |
| --- | ---: | ---: | ---: | ---: |
| Off / fallback | 269620 | 250920 | -18700 | 16384 |
| On / reuse | 244144 | 247872 | 3728 | 16384 |

Both modes pass the predeclared growth limit. The two cases share one fresh test
VM, each with independently restarted fixtures and 20 cycles; this is not paired
fresh-VM performance evidence. No forced GC, warm-up extension, dropped cycle or
budget adjustment was used. Process RSS includes the application, fixture and
native allocations; it does not attribute growth to a particular component.

The external watchdog observed 955 samples over 96.1 seconds: sampled peak VM RSS
801664 KiB, minimum host available memory 2168236 KiB, at most 14 VM threads.
No watchdog abort. It enforced the 1024 MiB RSS / 768 MiB available limits and a
300-second deadline. Raw watchdog samples and runner remain in the local temporary
`vxpipe-diagnostic-stress-memory.json` and `vxpipe-diagnostic-stress-watchdog.py`
artifacts; all post-drain acceptance samples are preserved below.

Execution from `apps/vxpipe_console`, under the external 100 ms watchdog:

```sh
VXPIPE_DIAGNOSTIC_STRESS_RSS=1 ERL_FLAGS='+S 2:2 +SDcpu 1 +SDio 1 +A 2' \
  taskset -c 0,1 mix test test/integration/configured_latency_diagnostics_test.exs \
  --only repeated_lifecycle --seed 0 --max-cases 1
```

Root formatting, warnings-as-errors compile, strict Credo and unused-lock checks
pass. Independent Astra xhigh review is clean; the reviewer independently
recomputed both medians and watchdog bounds. The two settings-store cases affected
by the shared completion-wait helper pass 2/2, seed 533756, 16.5 seconds. No
production change, full suite, live provider test or deployment.

## Raw post-drain samples (KiB)

```json
{"operational_vad": false, "rss_kib": [288044, 273472, 269620, 258396, 255348, 247052, 247852, 249580, 247856, 247860, 245868, 241804, 245444, 249652, 254336, 250920, 249192, 249216, 253528, 250968], "first_five_median_kib": 269620, "last_five_median_kib": 250920, "growth_kib": -18700, "budget_kib": 16384}
```

```json
{"operational_vad": true, "rss_kib": [244688, 244144, 244056, 244068, 246636, 245016, 245500, 248944, 247476, 247520, 248536, 246856, 244852, 242612, 248116, 247872, 245296, 243040, 251544, 250072], "first_five_median_kib": 244144, "last_five_median_kib": 247872, "growth_kib": 3728, "budget_kib": 16384}
```
