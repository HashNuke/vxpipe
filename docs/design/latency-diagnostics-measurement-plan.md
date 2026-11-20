# Passive diagnostics measurement plan

Status: evaluation plan declared 2026-11-19, with preliminary configured warm
measurements recorded in the milestone. Full paired
measurement acceptance remain open. Thresholds below are engineering acceptance budgets,
not measurements or promises of production capacity.

User decision, 2026-11-20: the measured CPU overhead is acceptable for optional
benchmarking. Report CPU use and the original targets, but CPU target overruns
are advisory and do not block milestone completion or release. Further CPU
optimization is out of scope. Historical target misses remain accurately recorded;
this is an explicit acceptance change, not a retrospective measurement pass.
Correctness, latency, bounded resources, coverage and cleanup remain required.

User scope correction, 2026-11-20: dedicated database CPU measurement, inference
coverage percentages and model-accuracy benchmarking are not acceptance gates.
Silero loading and running is sufficient for the model. Verify project-owned
source routing, reuse/fallback wiring, timing correlation, persistence, UI and
failure isolation. Keep missing/reset evidence honest, but do not require a
numerical inference-coverage threshold. Existing acoustic results remain optional
historical evidence; no further model-validation tests are required.

## Candidate isolation and its limits

Use the implemented room-owned source workers with shared, bounded inference in
supervised BEAM tasks for this evaluation. Keep diagnostic model loading outside room
readiness. Reuse operational Silero evidence where present; only fallback streams
submit additional model work. Each source has independent recurrent state.

`Speech.ActivityRuntime` retains a retired job's admission until its task reports
DOWN. A timeout or cancellation fences results; it does not establish that native
execution stopped. The patched Ortex binding keeps model initialization on DirtyIo schedulers.
Production Silero uses an explicit DirtyCpu inference entry; tensor binary
conversion also uses DirtyCpu. The legacy Ortex inference entry retains DirtyIo
for other callers.
Dirty scheduling keeps these calls off normal schedulers, but does not isolate
memory, native threads, process crashes or CPU contention from the BEAM VM.
There is no promise of protection from a VM-wide native fault or zero overhead.

An external inference process would provide an operating-system fault boundary,
at the cost of PCM transfer, protocol/backpressure and process lifecycle work.
It is deferred while the existing bounded implementation is evaluated. A missed
non-CPU acceptance budget blocks pilot activation: reduce and document supported capacity or revise
isolation, then predeclare and repeat the affected measurements. Do not raise a
budget retrospectively to pass. Native fault containment, if required, needs the
external process regardless of these performance results.

### Production session-thread revision, 2026-11-20

Following the first warm CPU evidence, the
[Silero threading decision](silero-native-threading.md) explicitly selects one
intra-op thread through a verified Ortex binding patch. This is production loader
behavior, shared by operational and fallback VAD. It preserves model weights,
source ownership, admission and budgets; it does not impose a whole-VM thread cap.
The existing native fault boundary remains. Old default-pool measurements remain
historical evidence, and new paired phases must both use the revised implementation.
CPU cgroup enforcement remains mandatory even when no extra pool threads appear.

The [report-progress checkpoint](../../labnotes/20261120-0020-diagnostics-inference-overhead.md)
retains unchanged reports between mapped provider-end coverage thresholds while
still recording every progress cursor. First progress, all other evidence kinds,
validation and memory bounds retain the full existing behavior. This reduces
repeated historical projection work; its single warm run still does not meet the
one-source CPU regression budget or complete paired acceptance.

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
The [external-workload smoke](../../labnotes/20261119-2128-diagnostics-external-workload.md)
exposed ONNX Runtime overriding inherited `taskset`
affinity: native workers selected CPUs 2 and 3 despite a 0–1 launch mask. Enforce
the measured VM's entire lifetime with an isolated cgroup `AllowedCPUs=0,1`, and
audit every native thread's allowed mask. The reference host needs a transient
system scope for that controller; run its workload as the ordinary checkout user.
Do not modify production units or the model's thread settings to conceal this.

The external generator must start outside that measured cgroup: a direct Port
child inherits the restricted cpuset. The smoke uses a transient user-manager
service with piped packet output, pins the Python generator to CPUs 2–3, and
records its actual mask. Its lifetime is limited to 45 seconds with a two-second
stop timeout, with an exact owned-unit stop on test cleanup. The smoke watchdog
also stops its owned generator units on abort. The fixed pacing method sleeps until two milliseconds before each
absolute deadline, then spins for the remaining bounded interval; its CPU cost
is reported separately. The original 2 ms p95 write-completion lateness limit
still applies. Retain invalid attempts; neither the spin guard nor CPU placement
is an increase to the acceptance budgets.
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
local provider and response fixtures. Persistence uses a fresh migrated disposable
PostgreSQL database for each phase, with an ordinary ten-connection pool matching
the deployment default. Do not wrap the workload in SQL Sandbox's outer rollback
transaction: that would exclude per-transaction commit costs and serialize otherwise independent
writers through a shared connection. Complete database creation/migrations before
the resource interval; room preparation and diagnostic writes stay within their
specified warm/cold intervals. Verify call and diagnostic rows from an independent
connection after drain. The ordinary sandbox smoke remains functional evidence
only. The committed-write smoke mode exercises the same database contract used
by the warm/cold repeated-pair runner; native matrix acceptance remains pending.
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
with phases staggered across participants. In the synthetic multi-input workload,
replace the first 16-bit sample of each frame with the input index plus one and
record that encoding in the manifest; retain the other 511 samples. This makes
source fingerprints distinct for routing/inference checks. It is not labelled
acoustic-accuracy input. Single-input fixture samples remain unchanged.
Use deterministic repeating speech,
silence and pause/resume PCM with fixed provider settlements and response events.
Record fixture hash and schedule. These fixtures test workload, not acoustic
accuracy. Generate at least ten completed canonical turns per input per measured
phase. Do not wait for a downstream acknowledgement to pace the next frame.
Record generator lateness; missing frames or p95 scheduling lateness above 2 ms
invalidate the pair. Preserve and report invalid attempts; rerun only after
identifying the environmental/harness cause, with the same budgets.

### Fixed warm workload implementation

The configured runner supports `--workload warm` and an optional single `--case`
(`fallback-off`, `fallback-on`, `reuse-off`, `reuse-on`). Warm mode forces fresh
committed databases and scoped resource sampling. It emits audio over [0, 25 s),
measures [5 s, 25 s), and retains 201 resource samples. Each source has exactly
625 measured frames; its full-run count is 781 or 782 according to its stagger.
The 24-frame speech clips use a 60-frame cadence with separate same-room human
windows. Both full-run and measured-only PCM p95 must meet the 2 ms limit.

The fixture checks ten completed canonical turns per input using conservative
VM receipt bounds: first measured-resource packet receipt through the timestamp
before generator launch plus 25 seconds. Successful speech-bearing native inference
must complete by the pre-launch timestamp plus five seconds for each required
source. Neither model readiness nor response acknowledgements change pacing.

The configured workload records ingress, response dispatch and synthetic
server-egress acknowledgement latency. See the
[warm-workload checkpoint](../../labnotes/20261119-2345-diagnostics-warm-workload.md)
for its original verification and limitations.

### Cold workload and repeated cells

The cold extension uses a 20-second audio window (625 frames per input), a fixed
56-frame settlement cadence, 32 leading frames and 24-frame speech clips. This
provides at least ten canonical turns per source, including two non-overlapping
human windows in each room. Static fixture reading/hashing and manifest output
finish before the resource reset. The reset is acknowledged before room creation;
periodic sampling then continues through preparation and audio without restarting.

A `ready` packet sent immediately after final STT attachment records readiness
and a separate CPU/RSS sample. A `start` packet after response-trace setup releases
the fixed audio schedule. STT readiness is bounded by fifteen seconds; post-ready trace setup stays within
the existing 45-second generator lifetime, reserving twenty seconds for audio. This separates STT
readiness from trace setup while including both in combined CPU/RSS accounting.
The readiness sample contributes peak RSS/HWM/thread counts and must fit the
chronological CPU samples around it. Its raw counters are retained separately
from the periodic sample population. All timestamps in each subtraction share
one clock; VM and external generator timestamps are never subtracted.

`scripts/diagnostics/repeated_pairs.py` runs one declared topology/mode cell as
three serial pairs in off/on, on/off, off/on order, each through the existing
watchdog. It retains commands, all artifacts, per-pair comparisons and worst
deltas. Invalid phases or measured-budget failures stop without automatic retry.
Cold readiness uses nearest-rank p95 across three phases of each collection state.
Source hashes and the actual emitted PCM digest must agree across all six phases.
A completed cell is not the entire topology matrix or milestone. Native execution
and acceptance evidence remain pending in the
[cold-pairs checkpoint](../../labnotes/20261120-0309-diagnostics-cold-pairs.md).

## Measurements and predeclared pass criteria

Measure process CPU time across all threads, wall duration, sampled RSS and OS
high-water RSS. CPU cores consumed means CPU seconds divided by elapsed seconds.
BEAM heap size/reductions alone omit native work and are insufficient. Keep raw
samples and phase summaries. Include cold loading and all diagnostic workers in
the measured process. Dedicated database CPU sampling is out of the required
scope; bounded asynchronous writes and storage-failure isolation remain required.

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
mandatory. The four-case smoke watchdog is available with:

```shell
python3 scripts/diagnostics/smoke_runner.py --committed-writes --output /tmp/diagnostics-smoke-unique
```

`--rooms N --inputs-per-room M` exercises N rooms with one or two human STT
inputs each, with at most 16 total inputs. Each input must deliver all 192 frames
and two complete turns. This is still a short functional smoke, not a full matrix
cell or evidence that every allowed topology has passed native acceptance.

Synthetic provider settlements use a fixed 64-frame cadence. For input index i,
room count R and humans per room H, slot = (i mod H) × R + floor(i / H), and the
first settlement is 64 + floor(64 × (slot + 1) / (R × H)); the second is 64 frames
later. Same-room humans are 32 frames apart. Each settlement ends a 32-frame speech
window replaying the first 16,384 samples of the pinned fixture. Outside those
windows the PCM is silence, before applying the source marker. The manifest pins
the clip's offset, length and SHA-256, declares silence/window encoding and lists
per-input settlement frames. The fixture checks actual emitted settlements, exact
PCM delivery, canonical IDs, native fingerprints and full public event traces.

This 192-frame/6.144-second normal-conversation smoke intentionally primes inputs
with at least 36 silent frames before the first speech window. It is not cold
startup coverage or the full paired workload. All four modes have identical
scheduled PCM and deadlines; no observer or response acknowledgement changes the
schedule. Same-room windows do not overlap, but there is no guaranteed response
completion gap: an interruption still fails the strict normal-conversation oracle.
The earlier continuous-speech, staggered-commit attempt exposed interruptions and
an early missing diagnostic row; those attempts remain recorded, not accepted.
Overlapping speech and interrupted turns remain separate functional/live cases.

`--committed-writes` creates a separate migrated database for each of the four
cases and verifies committed rows through an independent connection. Normal ExUnit
cleanup drops each database. A forced VM termination can bypass that cleanup:
the runner reports exact pending database reservations in `retained_databases`
and refuses a passing result. Each four-case run reserves at most four scratch
databases; a reservation may precede successful creation. Stop after an invalid
run and inspect those exact names before another run; do not accumulate retries
or delete databases by a wildcard. This mode does not promise database deletion
after a killed VM. Omit the option for
the original rollback-sandbox functional smoke. Both modes use the same audio,
real model and correctness assertions; only committed mode is suitable as the
foundation for database-write overhead measurement.

Use a new output directory; existing evidence is never overwritten. It requires
noninteractive sudo for its uniquely named transient system scope, while the
workload runs as the invoking checkout user. The report records source/model hashes,
raw resource samples, generator reports and cleanup failures. Invalid output,
process replacement, resource/affinity violations and incomplete evidence prevent
a passing result. Cleanup targets only the scope and registered generator units
belonging to that run. Finite unit lifetimes remain the fallback if cleanup fails.
This is functional smoke evidence. The full configured workload driver and paired
report integration remain to be completed.

Optional `--sample-resources` samples the isolated VM on the generator clock,
starting immediately before paced audio and ending at its declared end. The
192-frame smoke has 63 samples over 6.144 seconds; it measures audio only, excluding
room/STT/model preparation, and is not cold acceptance. The generator pins the
process start ticks and resets high-water RSS through a retained procfs descriptor
after rechecking identity. Raw samples are streamed to the workload log before
the final resource summary, and the watchdog verifies the measured BEAM identity.

Resource timing contract `boundary-2ms-no-skipped-slot-v1`: the first and last
reads must finish within 2 ms of their scheduled boundary. Each interior read must
finish strictly before its next declared sample deadline, including the shorter
final slot. Samples are scheduled every 100 ms; actual adjacent gaps may approach
200 ms. Retain and report all planned/actual read times, interior lateness and gaps;
calculate CPU rate with actual sample timestamps. These checks are separate from
PCM p95 lateness. Boundary precision prevents diluting CPU rate with idle time after
audio; interior deadlines prevent silently skipping scheduled samples. The complete
raw interval must reproduce every summary field and match the observed VM identity.

This corrects an overly strict every-read 2 ms/102 ms rule introduced during the
sampler checkpoint, beyond the original plan's periodic sampling requirement.
The earlier probes remain invalid under their original contract; they are not
relabelled as passes. The numerical CPU targets, RSS budgets and PCM timing limits are unchanged;
CPU targets are advisory under the user decision above.
Missing/reset-failed/incomplete or replaced-PID intervals fail. Linux-reported HWM
may dip slightly; retain its maximum observed value after reset. A generator start
offset also applies to the short smoke; 5000 ms there leaves only
1.144 seconds. The separate warm profile above provides the full 20-second interval.
Cold preparation accounting and the serial repeated-pair runner are implemented;
actual native warm/cold matrix acceptance remains outstanding.


Compare each matched pair separately. All valid repetitions must pass; also
publish the worst result. Let N be the number of accepted human STT inputs:

| Quantity | Maximum enabled-minus-disabled regression |
| --- | --- |
| Fallback CPU (advisory reporting target) | 0.05 + 0.03 × N CPU cores |
| Reuse CPU (advisory reporting target) | 0.02 + 0.005 × N CPU cores |
| Peak RSS, fallback or reuse | 128 + 8 × N MiB |
| p95 accepted ingress → synthetic provider receipt | max(2 ms, 10% of disabled p95) |
| p95 canonical input completion → matching response dispatch | max(2 ms, 10% of disabled p95) |
| p95 canonical input completion → matching egress acknowledgement | max(2 ms, 10% of disabled p95) |

Calculate latency within the measured VM's monotonic clock, never by subtracting
generator and target clocks. Publish sample counts and nearest-rank p95 per phase.
The ingress stage is measured from immediately before a successful
`CallEngine.push_audio` invocation, after constructing the frame, to receipt inside
the synthetic wire's audio callback. Thus it includes synchronous admission and
queueing; it is not microphone/network latency or observer-mailbox receipt time.
The exact PCM/count checks prove the invoked frames were delivered. Both endpoints
use signed microsecond monotonic timestamps in the measured VM. An opt-in fixture
notification carries wire identity, ordinal, PCM and receipt time together.

Retain all frame timestamp pairs. Validate complete ordered per-input ordinals,
nonnegative elapsed times, independently nondecreasing ingress/provider clocks
and exact frame counts before summarizing. Equal timestamps and overlapping
in-flight frames remain valid. The warm
population is selected by the fixed sequence/phase schedule in [5 s, 25 s), exactly
625 frames per input; delayed receipts remain included even beyond that interval.
The external validator independently reconstructs that population and nearest-rank
p95 from raw pairs and rejects missing or conflicting summaries. Both collection
off/on phases use the same instrumentation. These timestamps do not establish
response-dispatch or egress acknowledgement latency, which remain separate gates.

The response-dispatch stage uses a test-only isolated
[OTP trace session](https://www.erlang.org/doc/apps/kernel/trace.html) on the exact
configured RoomAuthority PIDs. Its boundaries are entry to audio
`ParticipantTurnCompleted` publication and entry to `TextCapability.respond/2`.
The latter includes any pending first-message queue delay; it does not include
capability execution or model latency. Both collection states use the same trace.
Local function matching covers the publication's default-argument wrapper; arity
and bounded identity-only match messages exclude State and conversation content.
Trace monotonic nanoseconds are converted explicitly to microseconds. Fence each
exact authority PID after teardown, including dead PIDs, before finalizing samples.

Retain source mappings, authoritative public canonical-turn order and raw trace
events. Require one matching completion and dispatch per turn with all source,
incarnation, connection, correlation and command identities preserved. Completion
trace order must match canonical ordinals independently per input, preventing a
slow measured turn from being relabelled as warm-up. Dispatches may interleave;
per-room timestamps must remain monotonic. Use the fixed provider-settlement frame
schedule for the warm cohort and retain late dispatches beyond the nominal end.
An independent external validator reconstructs the cohort and p95 from these raw
records. Successful configured response traces remain mandatory.

The [egress checkpoint](../../labnotes/20261120-0226-completion-egress-benchmark.md)
adds deterministic TTS and separate human output sinks. Its endpoint is publication
of `AgentSpeechStarted` after the sink's playback-start acknowledgement, matched
to the independently retained `TextOutput.id` and exact input/source/command.
This synthetic server boundary does not prove remote audibility. All three trace
stages must preserve per-room chronology, and the dispatch and egress reports must
describe the same canonical population. The paired comparator enforces the same
p95 budget when both phases supply egress; historical dispatch-only artifacts
remain explicitly partial. Native repeated measurements remain outstanding.

The same budgets apply to warm and cold phases; cold incomplete diagnostics must
remain explicit. Additional correctness gates apply regardless of CPU results:

- Exact admitted PCM delivery, canonical turns and normalized provider/control/
  response trace must match within each pair. Normalize generated identifiers
  and timestamps only, retaining per-source/per-command event ordering and causal
  correlation relationships. Independent rooms need not interleave identically.
- No duplicate model work in reuse mode. Off creates no diagnostic work or rows.
- Report drops, resets, missing boundaries and startup gaps honestly. Verify the
  application's observation path works; no inference-coverage percentage or
  additional model-validation acceptance is required.
- No missing response samples may disappear from the latency population. Missing
  delivery, unmatched output, unavailable source or unexpected timeout fails.

## Separate application stress checks

Normal paired performance is not saturation proof. Run synchronized input bursts,
slow inference, full handoffs, writer crashes, blocked persistence and 20 cycles
of source replacement and room teardown separately, retaining each call’s initial
settings snapshot. Assert configured queue/byte/
task bounds, bounded retries and drain, stale-result rejection and unchanged
normalized call-control traces. After each drain, no diagnostic source/task slot
may remain charged except a deliberately held native task; release that task and
require its DOWN before asserting the slot returned. Report mailbox maxima.
After a completed cycle's drain, compare median RSS of the first five and last
five cycles: growth must be at most 16 MiB. This is a bounded-run leak screen,
not proof of indefinite stability.

Acoustic/model-accuracy benchmarking is optional historical evidence, not a
completion requirement. Existing replay results must retain their uncertainty
and limited scope. Project-owned transport/reset handling and Scribe/browser
latency verification remain required. No live Telnyx measurement is authorized.

## Evidence and decision state

Source inspection covers `Speech.ActivityRuntime`, `Diagnostics.RoomService`,
the pinned Ortex native bindings and the runtime limits document. Focused runtime
tests cover cancellation, owner loss, deadlines and admission retained until DOWN;
they do not simulate native VM faults. The
[checkpoint labnotes](../../labnotes/20261119-1931-diagnostics-load-plan.md) record
the focused checks and independent design review. The measurement harness/results
remain outstanding. The pilot remains blocked until all milestone gates pass.
