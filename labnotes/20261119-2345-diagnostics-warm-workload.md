# Diagnostic warm workload

## Scope and decisions

Extend the existing configured workload with a fixed 25-second profile: five
seconds of warm-up followed by exactly 20 seconds of measurement. The generator
keeps absolute 32 ms deadlines, emits 781 or 782 frames per source depending on
its phase, and measures exactly 625 frames per source. It samples resources at
201 declared boundaries. Speech clips span 24 frames on a 60-frame cadence;
two humans in a room have distinct nonoverlapping windows. No response or model
acknowledgement delays the generator.

`--workload warm` requires committed writes and resource measurement. `--case`
selects exactly one operational-VAD/collection combination in its fresh VM.
The external fixture alone has a 90-second timeout; generator and scope lifetime
limits remain 45 and 300 seconds. This is a workload foundation, not completed
paired performance acceptance. Database CPU, response/egress latency, full
inference coverage, cold preparation and repeated paired comparisons remain open.

The fixture requires at least ten completed canonical turns per input inside a
conservative measured window. Its lower bound is the test VM's receipt of the
first resource sample; its upper bound is the pre-launch VM timestamp plus 25
seconds. Each count links a source settlement and unique canonical completion to
its matching AgentTurnCompleted receipt. Required native readiness is a successful
speech-bearing Silero inference timestamped immediately after push returns, by
the pre-launch timestamp plus five seconds. Smoke does not claim this deadline.

## Focused verification and review

Artifact names refer to the host temporary directory. No live provider tests,
Telnyx calls, production deployment or full suite run belongs to this checkpoint.

- Profile, schedule, window, generator and runner regressions began red in
  `vxpipe-warm-profile-red.log`, `vxpipe-warm-schedule-red.log`,
  `vxpipe-warm-window-red.log`, `vxpipe-warm-generator-red.log` and
  `vxpipe-warm-runner-red.log`.
- Schedule checks pass 4/4 (`vxpipe-warm-schedule-green.log`); configured trace
  oracles pass 3/3, 55 excluded (`vxpipe-warm-oracles-green.log`).
- An accidental combined selector included `--only test`, which was broader than
  intended. Its own BEAM was stopped after about 14 seconds. That partial run,
  `vxpipe-warm-compile-probe.log`, is not acceptance evidence. The two intended
  focused files were then run separately to completion.
- Independent review reproduced warm-up dilution: 35 measured frames late by
  3 ms among 625 measured frames failed the intended p95 budget, but among all
  782 frames the reported p95 was zero. Permanent generator and runner controls
  failed before the fix (`vxpipe-warm-p95-red.log` and
  `vxpipe-warm-p95-runner-red.log`). Both full-run and measured-only p95 now must
  pass; raw measured lateness remains in the generator report.
- Review also demonstrated that the initial warm frame-count test accepted a
  mutant which emitted nonzero PCM during declared silence. The new independent
  exact-byte oracle checks every supported room/participant shape, source markers,
  speech clips, silence and same-room nonoverlap. It rejects that mutant at the
  first frame (`vxpipe-warm-window-fixed-review.log`). The original timing probe
  correctly rejects late measured delivery (`vxpipe-warm-p95-review-green.log`).
- Python focused checks pass 53/53 (`vxpipe-warm-python-green.log`).

## Native warm phase evidence

`vxpipe-warm-fallback-off` and `vxpipe-warm-fallback-on` each pass as a single
fresh-VM phase with one room and one human. Each proves ten measured completions,
782 total / 625 measured frames, 201 raw resource samples, committed canonical
rows and no leftover database, watchdog abort or cleanup error.

| Collection | Resource duration (s) | Process CPU (s) | Interval HWM (KiB) | Measured PCM p95 (ns) |
| --- | ---: | ---: | ---: | ---: |
| off | 19.998913 | 0.67 | 200220 | 253742 |
| on (fallback) | 19.999061 | 34.17 | 252496 | 414460 |

Fallback native inference was ready 1,729,271 microseconds before its fixed
warm-up deadline. The large CPU difference is a concern to investigate; these two
runs are not the required three alternating paired repetitions or complete
performance acceptance. Local source inspection shows Ortex.load exposes execution
providers and optimization level, but no session thread-pool controls. No runtime
or dependency changes were made to reduce the observed cost.

`vxpipe-warm-reuse-on-two-human` and `vxpipe-warm-reuse-off-two-human`
each pass with two rooms and two STT humans per room. Both prove measured turn
counts 10/11/10/10, 3125 total / 2500 measured frames, 201 resource samples,
source-specific native readiness, exact output/peer projections and committed
canonical rows. Both clean up without watchdog abort, cleanup error or retained
database. Reuse mode never loads a benchmark model.

| Collection (operational VAD in both) | Resource duration (s) | Process CPU (s) | Interval HWM (KiB) | Measured PCM p95 (ns) |
| --- | ---: | ---: | ---: | ---: |
| on | 19.999512 | 37.89 | 301672 | 630932 |
| off | 20.000122 | 38.42 | 277804 | 405247 |

Independent review recomputed the resource summaries, checked source/model hashes,
frame/pacing evidence and database cleanup. Per-source measured completion counts
are enforced by the configured fixture's causal-window assertions; the final
artifact does not include every raw per-turn receipt timestamp for independent
count reconstruction. No complete paired performance claim is made.

Root `mix format --check-formatted`, `mix compile --warnings-as-errors`,
`mix credo --strict` and `mix deps.unlock --check-unused` pass in the
`vxpipe-warm-format.log`, `vxpipe-warm-compile.log`, `vxpipe-warm-credo.log` and
`vxpipe-warm-deps.log` artifacts. Changed documentation links and `git diff --check`
pass. No source-cutover or speech state-machine behavior changed, so no new Lean
run is claimed. The full suite remains deferred until milestone implementation
is complete, as requested.

Final GPT-6 Astra xhigh checkpoint review is clean. Its independent Python run
passes 53/53 (`vxpipe-warm-python-independent.log`). Its four-artifact audit
(`vxpipe-warm-artifacts-review.log`, driver `vxpipe_warm_artifacts_review.py`)
checks the 201-sample intervals, timing evidence, requested cases/shapes,
per-source readiness, cleanup and all 12 provenance hashes. Both reproduced
review findings above are resolved; remaining milestone acceptance stays open.
