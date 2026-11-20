# Diagnostics cold pairs

## Scope and implementation

Extend the existing configured native-performance fixture and Python runner with
cold accounting and a thin six-phase runner for each declared topology cell.
CPU remains advisory. No database-CPU, inference-percentage or acoustic-accuracy
gate is added; the existing initial working-model check remains.

Cold accounting starts with an external sampler reset before the first room/STT
preparation call. The test receives that initial sample before creating rooms.
Static PCM reading, hashing and manifest output finish before reset. Sampling
continues every 100 ms while the Python helper awaits the exact `ready` packet,
sent immediately after final room/STT attachment. A separate `start` packet after
trace setup releases fixed twenty-second audio; this prevents trace/manifest work
from inflating STT readiness. STT readiness is bounded by fifteen seconds; subsequent trace setup is bounded
by the existing 45-second generator lifetime (leaving twenty seconds for audio).
No response acknowledgement changes the audio schedule; the same resource
interval includes readiness, trace setup and all twenty audio seconds. No second reset can discard initialization CPU/RSS.
The report retains preparation duration and CPU seconds with its raw resource
sample, plus combined CPU/rate/high-water RSS. VM and generator clocks are never
subtracted from each other.

Cold uses 625 frames per source, a 56-frame settlement cadence, 32 leading frames
and 24-frame speech clips. This fixes at least ten complete canonical turns per
input in twenty seconds, with non-overlapping speech windows for two humans in
one room. Warm and short-smoke schedules are unchanged. Cold ingress, dispatch
and acknowledged egress populations reuse the existing independent validators.

`repeated_pairs.py` runs exactly three serial pairs per selected declared cell,
alternating off/on then on/off then off/on. Every phase invokes the existing
watchdog and writes to a new directory. An invalid phase or measured regression
stops the cell immediately without retry/deletion. The manifest records commands,
all completed pair comparisons and worst observed deltas. Cold readiness p95
across the three repetitions (nearest-rank maximum) must regress by no more than
max(100 ms, 10% of disabled p95). A cell result never claims the entire milestone
or all topology cells passed.

Example, only after quiet-host coordination:

```sh
python3 scripts/diagnostics/repeated_pairs.py --workload cold --mode fallback \
  --rooms 1 --inputs-per-room 1 --output /tmp/vxpipe-cold-fallback-one-unique
```

Required warm cells remain 1x1, 2x2, 16x1 and 8x2 for fallback/reuse; cold cells
remain 1x1 and 8x2 for fallback/reuse. Six isolated phases are required per cell.

## Focused verification

- New Python profile, cold handshake/resource accounting, artifact validation and
  serial repetition tests were first run red (missing cold profile/method/helper,
  rejected cold artifact and missing repeated runner), then green.
- DiagnosticsSchedule cold test failed with missing `profile(:cold)`, then passed:
  5 tests, zero failures. Red/green logs are `/tmp/vxpipe-cold-schedule-{red,green}.log`.
- Initial diagnostic Python lane: 96 tests, zero failures
  (`/tmp/vxpipe-cold-python.log`). Includes fake-clock proof of one reset across
  preparation+audio, fifteen-second timeout, exact20s audio, invalid preparation
  metadata rejection, source/workload pairing and no retries after failed phase.
- The root-path attempt at the schedule command did not select the child test;
  the recorded successful run used the Console child directory.
- Existing configured native integration test has been edited but has not yet
  been executed with the cold mode. Native measurement requires review and an
  otherwise quiet host; no new native or live-provider run occurred in this task.
- Final fixture format/compile and Astra review remain pending before native use.


## Astra review corrections

Red regressions reproduced readiness polluted by post-ready manifest work,
ignored ready-sample memory peaks/nonmonotonic CPU, and acceptance of different
actual emitted PCM hashes. See `/tmp/vxpipe-cold-review-red.log`.

The two bounded handshake messages above separate final STT readiness from audio
release. The additional readiness sample contributes RSS/HWM/thread maxima and
must fit its chronological periodic CPU neighbours. Periodic sample count stays
explicit; the separate sample is retained in `preparation_sample`. The runner
hashes the actual PCM fixture path, and every emitted fixture digest is retained
and required to match throughout the six-phase cell. Historical artifacts lacking
this digest remain readable individually but cannot satisfy the repeated runner.

The excluded-integration compilation command unintentionally also ran 59 default
cases in the configured test file: 4 excluded and 2 failed mixed-STS assertions
for a missing asynchronous room-completion landmark (external/hybrid, local VAD
false). It compiled successfully but is not recorded as a passing suite. Root is
fixing those separate row-await assertions and owns their verification. No claim
that those failures predated this checkpoint is made. Log:
`/tmp/vxpipe-cold-fixture-check.log`, seed159480.

Final focused checks after review corrections:

- 106 diagnostic Python tests passed in 2.725 seconds
  (`/tmp/vxpipe-cold-python.log`).
- Exact `ready`/`start` framing, static manifest before reset, preparation versus
  audio-release separation, readiness near15s with post-ready trace work, and a
  periodic sample-slot rollover are covered by fake-clock/protocol tests.
- The residual deadline checks first failed in
  `/tmp/vxpipe-cold-deadline-red.log`, then passed. Final STT readiness keeps its
  fifteen-second limit; trace setup uses the existing generator lifetime safety
  bound, reserving twenty seconds for audio. Crossing a periodic sample deadline
  alone is not a readiness timeout.
- Three edited Elixir files formatted. Final focused DiagnosticsSchedule run:
  5 tests, zero failures (`/tmp/vxpipe-cold-schedule-final.log`).
- `git diff --check` passed. No active process or Mix lane retained.
- Astra reviewer rechecked the readiness edge, extra sample accounting and PCM
  binding; root owns the final review decision and checkpoint commit.
- Native measurements remain unrun for this checkpoint. This is harness
  verification, not a performance acceptance pass.

A final reviewer probe held trace setup until22s after readiness at1s. It exposed
premature sampler closure at ready+20s before audio was released. The new bounded
fake-clock regression failed on the resulting spin, then passed after removing
the two premature end/audio assignments from `cold_ready`; only
`cold_audio_start` now fixes the audio endpoint. No scope or budget changed.
`/tmp/vxpipe-cold-late-start-red.log` records red; final diagnostic Python run:
107 tests passed in 3.066 seconds. The final report guard also refuses a cold
interval without audio release. No Mix/native/provider run was added.

Independent Astra xhigh final review is clean, including the held-trace
reproduction. Native execution remains the next step.
