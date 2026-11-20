# Diagnostics advisory costs

## User scope decision

The user explicitly chose “Record measured costs as advisory” and clarified that
VAD is being used to measure, not to fail performance budgets. CPU, RSS and
latency costs (including cold readiness regression) are informational. The load
matrix is no longer mandatory for milestone completion. Root owns the milestone
and design-document updates; this checkpoint only adjusts the optional tools.

## Minimal compatibility change

- Keep measured values, deltas and original targets. Existing `passed` fields
  still describe comparison with the original numerical target; add explicit
  `within_original_target` and `advisory: true` for RSS and latency/readiness.
- `cost_targets_within_original_limits` summarizes those historical target
  comparisons without controlling acceptance or process exit.
- Retain `measured_gates_pass` for output compatibility, explicitly documented as
  dataset validity only. Invalid/incomplete datasets still raise or return invalid
  evidence; validated datasets are not rejected for measured cost.
- Optional repeated runs continue through all three pairs despite cost overruns.
  `performance_cell_complete` means the requested data were collected. It does
  not certify a performance budget or complete milestone acceptance.
- Remove cold-phase and repeated-matrix entries from `missing_acceptance_evidence`
  because they are no longer milestone gates. Keep historical JSON unchanged.
- Preserve all source/model/fixture matching, raw population/resource integrity,
  sampler pacing, cleanup/watchdog and absolute fifteen-second STT-readiness
  validity checks. Cold readiness *regression* is advisory; its absolute operational
  deadline is unchanged. No native, model, live-provider or Mix run is needed.

## Verification

Changed the focused tests first. Red evidence is retained at
`/tmp/vxpipe-advisory-costs-red.log`: valid high-memory runs stopped after the first
pair; comparator cost gates rejected overruns; readiness lacked advisory status.

After implementation, 15 comparator and 5 repeated-run tests pass. Coverage
retains invalid/incomplete evidence and source mismatch failures; additionally it
proves that valid memory overruns collect all six optional phases, latency/RSS
numerical misses remain visible, and cold readiness regressions do not reject
otherwise valid data. `git diff --check` passed. No historical result file was
rewritten, and no measurements, commits or deployment were performed.

Independent Astra xhigh review is clean. It replayed the archived cold pair:
the optional CLI accepts valid data while retaining original RSS/dispatch target
misses, and rejects a deliberately removed egress observation. Current milestone,
authoritative index and handbook agree that no load matrix is required.
