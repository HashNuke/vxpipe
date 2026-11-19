# Diagnostic phase resources

## Purpose and scope

Add resource boundaries tied to the external generator's absolute clock. The
existing watchdog's full-VM-lifetime samples protect the host but do not isolate
a measured interval. This checkpoint introduces an opt-in audio-only interval;
it does not complete the warm/cold paired driver, database CPU accounting,
coverage, response/egress latency, or performance acceptance.

`--sample-resources` on the smoke runner passes only the isolated test VM's own
PID to its external generator. The generator pins PID/start ticks, resets that
VM's RSS high-water counter at the scheduled boundary, samples aggregate process
CPU/native RSS every 100 ms and records an exact end sample. PCM deadlines remain
absolute and never wait for a response or observer acknowledgement. Every completed
resource sample is streamed as packet 3 and retained in workload output, including
samples before a later failure. The final report uses actual sample timestamps.

The 192-frame smoke measures 6.144 seconds of accepted audio after room preparation.
It excludes model/STT preparation and must not be labelled cold. The generator
also supports a declared start offset for later warm phases; a 5000 ms offset in
this smoke leaves only 1.144 seconds, not the required 20-second paired phase.

## Boundary and ownership contracts

Record each planned sample time and actual read start/finish. The final versioned
contract is described below; all summary CPU rates use actual sample timestamps.
Coincident periodic/end boundaries produce one sample. Missing/incomplete intervals,
changed process identity, nonmonotonic CPU/time counters or reset failure invalidate
the run. The watchdog cross-checks resource identity against its observed BEAM and
requires the complete 63-sample audio interval when resources were requested.

Independent review reproduced a reset-authority race in the old helper: a process
could exit and its numeric PID be reused after the pre-read, causing the replacement
counter to be reset before identity rejection. The helper now opens `clear_refs`
without truncation, rechecks identity before writing through that descriptor and
checks again after the write. The initially pinned start ticks are also required.
Linux resolves the target of that write from the opened file's task inode
([kernel implementation](https://raw.githubusercontent.com/torvalds/linux/master/fs/proc/task_mmu.c)).
No process search, production reset or wildcard operation is used.

## Focused verification

Artifact names here refer to the host temporary directory, not repository paths.

- `vxpipe-resource-schedule-red.log`: missing resource scheduler fails before implementation.
- `vxpipe-resource-identity-red.log`: expected identity cannot be supplied to the old helper.
- `vxpipe-resource-generator-red.log`: generator rejects the new resource sampler argument.
- `vxpipe-resource-watchdog-red.log`: requested-resource validation is absent.
- Permanent PID-replacement tests use actual fake proc directories and swap the
  target before and after opening the descriptor. The reviewer reproduced the
  old replacement mutation, then verified the retained-descriptor fix.
- Python passes 46/46 at `vxpipe-resource-python-green.log`, including fixed
  deadlines, reset-once behavior, end sampling, incomplete/reused interval denial,
  explicit slow-sample timing failure, streamed raw samples, unchanged PCM timing,
  source identity, and watchdog acceptance requiring the complete resource interval.

Native evidence and final review follow after completion. No live provider tests,
Telnyx calls, full suite or production deployment are part of this checkpoint.

## Native probes and follow-up fixes

The first full four-mode run, `vxpipe-audio-resource-interval`, is invalid: three
cases failed because Linux-reported VmHWM decreased slightly and the fourth failed
the new resource timing gate. All four completed 63 resource samples; cleanup
dropped all owned databases without watchdog abort or cleanup errors. The HWM dips
were 236144 to 235980 KiB, 250764 to 250400 KiB and 257232 to 257076 KiB. CPU and
wall time remained monotonic. Linux's reported HWM includes current approximate
RSS as well as stored hiwater and is not guaranteed to be a monotonic snapshot.
A permanent regression based on the first dip failed before the summary was fixed
to retain the largest observed HWM without rejecting a decrease alone. Explicit
reset markers, CPU/time monotonicity and source identity remain mandatory.

Independent review then reproduced an acceptance gap: missing/invalid CPU/RSS
summary fields, replayed raw samples and counters disagreeing with the summary
could pass the initial runner check. The runner now collects at most 252 raw samples,
associates 63 with each interval, reconstructs ProcessSample values and recomputes
the entire summary. It validates read spans, exact scheduled deadlines, measured
VM identity, actual timestamps and timing fields. Missing, malformed, replayed or
inconsistent evidence fails. Permanent controls started red; they also verify
that four valid intervals are retained by the actual watchdog and that intervals
cannot overlap or rewind the same VM's CPU counter.

Retained proc descriptors reduce repeated open/close work and are reread at offset
zero. A permanent test proves counter refresh and that recycled numeric paths are
not followed. This optimization did not resolve timing: the exact fallback-on
probe `vxpipe-resource-read-cost-probe` still had interior reads taking 2.4–5.1 ms
wall time but only 0.34–0.41 ms of thread CPU. A temporary per-file timing probe,
`vxpipe-resource-syscall-probe`, found no file read over 1 ms, but one wake started
3.488 ms late before a 0.180 ms read. Ordinary scheduling delay therefore remains
a demonstrated cause of invalid resource timing. Both single-case probes retain
all raw samples and are not four-mode acceptance. Temporary diagnostic prints were
removed. No timing gate or performance budget has been relaxed at this point.

## Corrected sampler timing contract

Independent design review checked HEAD's approved plan: it requires scheduled
100 ms sampling and actual-duration accounting, with a 2 ms p95 limit for PCM.
The every-resource-read 2 ms / 102 ms-gap rule was an additional constraint added
in this uncommitted checkpoint. CPU-rate precision depends on the first and last
reads; interior samples need to preserve cadence and retain actual timestamps.

The corrected, predeclared `boundary-2ms-no-skipped-slot-v1` keeps first/last read
completion within 2 ms. Every interior read must finish strictly before the next
declared deadline, including the shorter final slot. Actual gaps may approach
200 ms and are reported, not described as exact 100 ms intervals. No CPU, RSS or
PCM regression budget changes. The old probes remain invalid under their original
contract and require new evidence. The retained descriptor optimization remains an
overhead reduction, not a proven fix for all scheduling jitter.

Focused tests started red for the new versioned contract, then cover an allowed
late interior sample, exact missed-slot rejection, a 500 ms late final read, and
coincident final/periodic deadlines. The independent watchdog recomputes the same
rules from raw samples, rather than trusting the producer's timing-valid flag.

## Final versioned native evidence

`vxpipe-audio-resource-interval-v1` passes all four operational-VAD/collection
combinations with `boundary-2ms-no-skipped-slot-v1`. The watchdog independently
validates 252 raw samples (63 per interval), successful fixture exits/reports and
owned-resource cleanup. The Console fixture asserts complete PCM, exact canonical
rows and committed visibility. No watchdog abort, cleanup error
or retained database occurred. Its 490 lifetime-watchdog samples span 49.95 seconds,
with peak VM RSS 875,424 KiB and minimum host available memory 2,551,540 KiB.

| Operational VAD / collection | Actual resource duration (s) | Process CPU (s) | Interval HWM (KiB) | PCM p95 lateness (ns) | Start/end read lateness (ns) |
| --- | ---: | ---: | ---: | ---: | --- |
| off / off | 6.143716 | 0.36 | 231428 | 220022 | 461019 / 168881 |
| off / on | 6.144005 | 10.56 | 260532 | 391541 | 366070 / 372423 |
| on / off | 6.143742 | 10.45 | 254384 | 378626 | 443710 / 166751 |
| on / on | 6.143882 | 10.22 | 258804 | 477331 | 386699 / 261703 |

Maximum observed adjacent sample gaps are 101.851 / 102.416 / 101.785 / 100.637 ms.
They are disclosed as actual gaps, not claimed to be exact 100 ms sampling. These
short, sequential cases in one VM are not fresh-VM warm/cold matched pairs; no CPU
regression budget is declared passed from them. The model-on CPU cost merits
investigation during the full paired workload rather than ignoring it.

Final focused Python checks pass 46/46. The exact skipped-slot unit test initially
used a fake clock with identical adjacent counter timestamps, which correctly
failed monotonicity; the fixture now distinguishes counter-read and completion
timestamps so it tests the intended slot boundary. No measured implementation
changed after the final native run. Root format, warnings-as-errors compile, strict Credo and unused-dependency
checks pass. Final independent Astra review is clean: Python 46/46, corruption
controls 5/5 and boundary controls 7/7 pass; all 252 raw samples, summaries, timing
fields, owned database cleanup pairs and 11 provenance hashes match exactly.
The audio-resource checkpoint is accepted, while the full paired workload stays
open. Full-suite execution remains deferred until milestone implementation ends.
