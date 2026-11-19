# Diagnostic stress acceptance audit

## Remaining acceptance

Audit milestone E's deterministic stress gate against existing configured and
component evidence. Add opt-in reporting of sampled source-worker queue/byte and
mailbox maxima to the existing 96-frame saturation cases, retaining every bound
assertion and the complete public-event/PCM/commit oracle. No runtime change.
These are observed maxima at defined sampling points, not continuous instrumentation
or an indefinite resource guarantee. Acceptance-only reporting may start green.

Set `VXPIPE_DIAGNOSTIC_STRESS_REPORT=1` for the configured saturation selection.
The workload remains local, synthetic inference; no live provider tests.

## Verification

Configured queue selection passes 8/8, seed 539973, 17.9 seconds. Four enabled
profiles each sample after 96 offered PCM frames and again after both completed
turns, while the diagnostic worker remains suspended. Four off controls retain
no observer or diagnostic report. Command from Console:

```sh
VXPIPE_DIAGNOSTIC_STRESS_REPORT=1 mix test \
  test/integration/configured_latency_diagnostics_test.exs --only saturation
```

| Operational VAD | Frame samples | Queue samples | Peak retained count | Peak retained bytes | Peak mailbox messages |
| --- | ---: | ---: | ---: | ---: | ---: |
| Off | 512 | 97 | 64 | 227968 | 64 |
| On | 512 | 97 | 64 | 227968 | 64 |
| Off | 4096 | 97 | 26 | 260092 | 26 |
| On | 4096 | 97 | 25 | 261796 | 25 |

All sampled values satisfy the configured 64-packet, 262144-byte and 72-message
bounds. Byte accounting includes retained packet metadata. These measurements
cover the suspended source worker mailbox; they are not VM-wide mailbox maxima.
The consumer cannot drain between samples; lifecycle/timer messages may arrive
between them, so these are sampled observed peaks, not continuous exact maxima.

Engine `capture_handoff_test`, `source_worker_test`, `inference_admission_test`
and `speech/activity_runtime_test`: 49/49, seed 770030, 2.7 seconds.
Calls `writer_test`: 15/15, seed 142721, 0.6 seconds. The writer suite exercises
its public Handoff boundary, retry limits, task admission and abrupt-task cleanup.
No production source changes; all commands are focused offline tests.

## Contract-to-evidence audit

| Stress contract | Evidence and boundary |
| --- | --- |
| Slow or failed inference cannot control calls | Configured crash/hang on/off cases keep two canonical turns and exact provider PCM/commits/public events while fallback inference is blocked or crashes; the full 28-case failure matrix is recorded in the control-trace checkpoint. |
| Full count/byte queues stay bounded | Eight configured saturation cases above; source worker suspended, 96 frames offered, both turns finish before resume, explicit overload persists, revocation discards queued capture. |
| Concurrent producer admission | CaptureHandoff: 64 offers with eight concurrent tasks, exactly four reserved messages and 60 full results; Writer: 64 offers with 32 tasks, count <=8 and bytes <=40000. These component cases test shared admission boundaries, not a multi-room throughput benchmark. |
| Blocked storage and writer crashes | Configured error/blocked storage and idle writer-crash cases preserve the complete public trace and provider bytes; Writer tests separately kill an actively blocked writer and require both writer and database-task DOWN. |
| Bounded retries and task capacity | Writer retains the original count/byte reservation on retry, exhausts attempts/deadlines, rejects excess concurrent writes and task admission, and releases retained capacity on bounded drain. InferenceAdmission rejects excess work while the runtime is suspended. |
| Revocation and stale-result rejection | SourceWorker revocation drops queued audio and monitors worker/task death; ActivityRuntime cancellation/deadline cases reject late successful output. A delivered result with a still-held task cannot release admission before its DOWN. This models task ordering, not an unkillable native NIF. |
| Repeated enable/revoke/re-enable/teardown | The lifecycle-memory checkpoint completes 20 rooms per VAD mode, asserts source/inference/writer slots released, checks all 120 canonical turns/720 public events and exact final persisted rows. |
| Bounded-run RSS growth | All 40 post-drain samples are preserved in the lifecycle-memory checkpoint. First/last-five median growth is -18700 KiB fallback and +3728 KiB reuse, each <=16384 KiB. No forced GC or omitted cycles. |

Related evidence: [failure control traces](20261119-2059-diagnostics-control-traces.md),
[lifecycle memory](20261119-2109-diagnostics-stress-memory.md),
[queue saturation](20261119-2006-diagnostics-queue-saturation.md),
[writer recovery](20261119-2022-diagnostics-writer-crash.md).

This audit is for deterministic stress isolation. It does not establish real-model
CPU/p95 throughput, acoustic accuracy, indefinite leak freedom, native VM-fault
containment or every feature/fault combination. Those remain separate gates/limits.
Root format, warnings-as-errors compile, strict Credo and unused-lock checks pass.
Independent Astra xhigh closure review is clean; its saturation selection passes
8/8, seed 30235, 18.1 seconds, reproducing the four sampled maxima exactly. The
milestone deterministic stress checkbox and index are synchronized; remaining
real-model performance, accuracy, distributed effective status and live/final gates
are still open.

