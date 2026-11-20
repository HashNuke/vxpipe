# Diagnostics native matrix

## Declared scope

Run the existing reviewed repeated-pair harness at source commit `3bd232e4`.
The measurement plan defines warm cells 1×1, 2×2, 16×1 and 8×2 and cold cells
1×1 and 8×2, each in fallback/reuse mode with three alternating off/on pairs.
Each phase uses an isolated VM and disposable committed database. CPU is advisory;
RSS, timing, complete latency populations and source consistency remain gates.
No database CPU or additional model-accuracy/coverage gate is added.

Only one workload runs at a time, after all live/Mix/browser operations have
finished. Preserve all attempts and stop on the first invalid or failed phase;
identify the cause before any retry. The native runner records host/affinity,
source/model hashes, resources, ingress/dispatch/egress raw samples and cleanup.
No production service restart or live provider call belongs to this measurement.

## Execution

First cold fallback 1×1 cell stopped at its first completed pair because measured
budgets failed. Both phases completed without watchdog abort, cleanup errors or
retained databases. No repeat was started. Source/model/fixture hashes agree.

| Measurement | Off | On | Delta | Current limit | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| Peak RSS/HWM, KiB | 226924 | 415792 | 188868 | 139264 | Fail |
| Ingress p95, µs | 237 | 281 | 44 | 2000 | Pass |
| Dispatch p95, µs | 3059 | 8543 | 5484 | 2000 | Fail |
| Egress p95, µs | 65752 | 60665 | -5087 | 6575.2 | Pass |
| CPU cores (advisory) | 0.09923 | 0.16039 | 0.06116 | 0.08 target | Within target |

Each phase has 625 ingress and ten dispatch/egress observations. STT preparation
was 642.7 ms off and 678.4 ms on; this is not the required three-pair readiness p95.
The matrix and milestone acceptance remain incomplete. The user has been asked
whether RSS/latency costs should also become advisory for opt-in benchmarking;
no scope change is assumed while that answer is pending.

[Compressed raw reports and pair comparison](20261120-0328-cold-fallback-evidence.json.gz)
preserve all measurement values and raw-file SHA256 digests. Compression was
round-trip verified and the artifact contains no local absolute paths. The
runner manifest and original reports remain in the isolated temporary run directory.


Independent Astra xhigh review replayed both archived phases and reproduced the
comparison exactly. Original raw-report hashes, all source hashes, sample counts
and both database drop acknowledgements match. This remains a failed first pair.
