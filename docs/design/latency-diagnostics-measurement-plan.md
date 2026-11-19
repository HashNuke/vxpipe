# Passive diagnostics measurement plan

Status: predeclared evaluation plan, 2026-11-19. No load results or acoustic
accuracy claims yet. This implements the planning part of milestone E; its paired
measurement gate remains open. Thresholds below are engineering acceptance budgets,
not measurements or promises of production capacity.

## Candidate isolation and its limits

Use the implemented room-owned source workers with shared, bounded inference in
supervised BEAM tasks for this evaluation. Keep diagnostic model loading outside room
readiness. Reuse operational Silero evidence where present; only fallback streams
submit additional model work. Each source has independent recurrent state.

`Speech.ActivityRuntime` retains a retired job's admission until its task reports
DOWN. A timeout or cancellation fences results; it does not establish that native
execution stopped. The pinned Ortex binding schedules model initialization and
model execution on DirtyIo schedulers; tensor binary conversion uses DirtyCpu.
Dirty scheduling keeps these calls off normal schedulers, but does not isolate
memory, native threads, process crashes or CPU contention from the BEAM VM.
There is no promise of protection from a VM-wide native fault or zero overhead.

An external inference process would provide an operating-system fault boundary,
at the cost of PCM transfer, protocol/backpressure and process lifecycle work.
It is deferred while the existing bounded implementation is evaluated. A missed
budget blocks pilot activation: reduce and document supported capacity or revise
isolation, then predeclare and repeat the affected measurements. Do not raise a
budget retrospectively to pass. Native fault containment, if required, needs the
external process regardless of these performance results.

## Reference environment and safe execution

Observed evaluation host: KVM x86_64, AMD EPYC-Genoa, four logical CPUs, 7,745 MiB
RAM, no swap; Linux 7.0.0-43-generic, Erlang/OTP 28 (erts 16.4), Elixir 1.19.5.
The user service cgroup reports `cpu.max = max 100000` and `memory.max = max`;
these are not resource isolation for the measurement. Record ancestor limits,
CPU affinity and actual free memory at execution time as well.

Run one isolated test VM at a time, with no real provider connections, no real
Telnyx calls and no change/restart of `vxpipe.service`. Pin its entire process
(including inherited native threads) to two CPUs and use two BEAM schedulers.
Record dirty scheduler counts and native thread counts; scheduler flags alone
are not a native-thread CPU cap. Both phases use identical affinity and flags.
Start only with at least 1,536 MiB available host memory. An external watchdog
samples every 100 ms and aborts the test VM if its RSS exceeds 1,024 MiB or host
available memory falls below 768 MiB. This is sampled protection, not a hard
memory bound. An abort invalidates the run and is reported, never a passing result.

Pin the source commit, Nx/Ortex lock revisions, CPU execution provider and model
checksum in each result. Current model is `silero_v6.2.3.onnx`, SHA256
`1a153a22f4509e292a94e67d6f9b85e8deb25b4988682b7e174c65279d8788e3`.
Measure the actual pinned Silero model, not a fake probability classifier.

## Paired workload

Use the configured room/STT/diagnostic collector/writer path with deterministic
local provider and response fixtures. Persistence uses an isolated test database.
No benchmark bypass of room service, settings authority, capture admission or
durable writes is allowed. The generator runs outside the measured VM; report its
CPU separately. Operational VAD configuration stays fixed within each pair.
Use production defaults: 16 diagnostic source slots, one shared diagnostic
inference job, 15-second load timeout and 2-second inference timeout. Preserve
the capture/writer limits in the runtime-limits document; record their values
in results. Do not increase concurrency or buffers to rescue a failing cell.

Evaluate both modes: operational Silero off (diagnostic fallback) and operational
Silero on (diagnostic reuse). For each mode evaluate these room/input topologies:

| Rooms | Human STT inputs per room | Total inputs |
| --- | --- | --- |
| 1 | 1 | 1 |
| 2 | 2 | 4 |
| 16 | 1 | 16 |
| 8 | 2 | 16 |

For every cell run three off/on pairs, alternating phase order. Each phase starts
a fresh VM, warms the ordinary lifecycle for five seconds, then measures 20
seconds. Readiness is required only for models needed by that phase: operational
VAD off plus collection off must load no model. A required model not ready by the
warm measurement start fails readiness; do not silently extend warm-up.

Separately run three cold pairs for each mode at 1 room/1 input and 8 rooms/2
inputs. Start cold CPU/RSS accounting immediately before room/STT preparation,
then drive a 20-second audio window once all STT inputs accept audio. End resource
accounting after that window. This combined interval explicitly includes
operational Silero's pre-admission warmup, plus fallback loading during accepted
audio. No model preload or initialization cost is discarded. Require STT readiness
within 15 seconds of preparation; timeouts fail rather than removing samples.
Record preparation-to-ready duration and cumulative CPU seconds separately, as
well as the combined interval's CPU rate and peak RSS used by the budgets below.
The enabled-minus-disabled p95 readiness regression across the three cold pairs
must be at most max(100 ms, 10% of disabled p95). Report diagnostic attachment/model
readiness and coverage separately; diagnostic readiness must never gate STT.

Deliver 512-sample 16 kHz frames every 32 ms per input using an absolute schedule,
with phases staggered across participants. Use deterministic repeating speech,
silence and pause/resume PCM with fixed provider settlements and response events.
Record fixture hash and schedule. These fixtures test workload, not acoustic
accuracy. Generate at least ten completed canonical turns per input per measured
phase. Do not wait for a downstream acknowledgement to pace the next frame.
Record generator lateness; missing frames or p95 scheduling lateness above 2 ms
invalidate the pair. Preserve and report invalid attempts; rerun only after
identifying the environmental/harness cause, with the same budgets.

## Measurements and predeclared pass criteria

Measure process CPU time across all threads, wall duration, sampled RSS and OS
high-water RSS. CPU cores consumed means CPU seconds divided by elapsed seconds.
BEAM heap size/reductions alone omit native work and are insufficient. Keep raw
samples and phase summaries. Include cold loading and all diagnostic workers in
the measured process. Report database CPU separately and isolate its per-phase
statistics; host-wide CPU is supplementary evidence, not a substitute.

Resource interval clarification, before measurements: reset the isolated test VM's
Linux RSS high-water counter at the measurement boundary (`clear_refs` value 5),
after warm-up for warm phases and immediately before room preparation for cold
phases. Resetting the counter does not free memory. Record both sampled RSS and
that interval's OS high water; apply the peak-RSS budget to the latter so a peak
between samples is retained. A lifetime high water from VM startup/warm-up must
not mask the measured phase. Missing reset support/permission invalidates the
phase; do not silently substitute a lifetime counter. Linux documents this reset
in [procfs](https://www.kernel.org/doc/html/latest/filesystems/proc.html).

The external Python helper in `scripts/diagnostics/measurement.py` reads aggregate
process CPU ticks, resident memory and thread counts; it fences PID reuse using
process start ticks and rejects missing, nonfinite or nonmonotonic samples. Its
resource comparison alone cannot establish a passing workload: correctness,
coverage, generator timing, readiness and all latency budgets below remain
mandatory. The configured workload driver, watchdog and paired report integration
remain to be completed.

Compare each matched pair separately. All valid repetitions must pass; also
publish the worst result. Let N be the number of accepted human STT inputs:

| Quantity | Maximum enabled-minus-disabled regression |
| --- | --- |
| Fallback CPU | 0.05 + 0.03 × N CPU cores |
| Reuse CPU | 0.02 + 0.005 × N CPU cores |
| Peak RSS, fallback or reuse | 128 + 8 × N MiB |
| p95 accepted ingress → synthetic provider receipt | max(2 ms, 10% of disabled p95) |
| p95 canonical input completion → matching response dispatch | max(2 ms, 10% of disabled p95) |
| p95 canonical input completion → matching egress acknowledgement | max(2 ms, 10% of disabled p95) |

Calculate latency within the measured VM's monotonic clock, never by subtracting
generator and target clocks. Publish sample counts and nearest-rank p95 per phase.
The same budgets apply to warm and cold phases; cold incomplete diagnostics must
remain explicit. Additional correctness gates apply regardless of CPU results:

- Exact admitted PCM delivery, canonical turns and normalized provider/control/
  response trace must match within each pair. Normalize generated identifiers
  and timestamps only, retaining per-source/per-command event ordering and causal
  correlation relationships. Independent rooms need not interleave identically.
- No duplicate model work in reuse mode. Off creates no diagnostic work or rows.
- After readiness, at least 99% of offered eligible frames must have diagnostic
  evidence or consumed reuse evidence in warm phases. Report all drops, resets,
  missing boundaries and coverage reasons; low overhead achieved by discarding
  diagnostics fails. Cold phases require positive processed coverage for every
  source and separately disclose the startup gap.
- No missing response samples may disappear from the latency population. Missing
  delivery, unmatched output, unavailable source or unexpected timeout fails.

## Separate stress and accuracy gates

Normal paired performance is not saturation proof. Run synchronized input bursts,
slow inference, full handoffs, writer crashes, blocked persistence and 20 cycles
of enable/revoke/re-enable/room teardown separately. Assert configured queue/byte/
task bounds, bounded retries and drain, stale-result rejection and unchanged
normalized call-control traces. After each drain, no diagnostic source/task slot
may remain charged except a deliberately held native task; release that task and
require its DOWN before asserting the slot returned. Report mailbox maxima.
After a completed cycle's drain, compare median RSS of the first five and last
five cycles: growth must be at most 16 MiB. This is a bounded-run leak screen,
not proof of indefinite stability.

Acoustic accuracy still needs independently labelled caller-only audio covering
quiet tails, pauses, noise, echo, overlap and resumption. Record signed and absolute
boundary error and incomplete rate separately by mode and condition. Synthetic
probabilities, model frame size and the load fixture cannot satisfy that gate.
Transport loss/reordering/resampling/reset checks and Scribe/browser live acceptance
also remain separate. No live Telnyx measurement is authorized.

## Evidence and decision state

Source inspection covers `Speech.ActivityRuntime`, `Diagnostics.RoomService`,
the pinned Ortex native bindings and the runtime limits document. Focused runtime
tests cover cancellation, owner loss, deadlines and admission retained until DOWN;
they do not simulate native VM faults. The
[checkpoint labnotes](../../labnotes/20261119-1931-diagnostics-load-plan.md) record
the focused checks and independent design review. The measurement harness/results
remain outstanding. The pilot remains blocked until all milestone gates pass.
