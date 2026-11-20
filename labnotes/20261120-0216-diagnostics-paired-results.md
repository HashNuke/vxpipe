# Diagnostics paired results

## Checkpoint

Add a narrow offline comparison for existing single-phase warm runner artifacts.
The CPU target is advisory under the user's 2026-11-20 decision; RSS, ingress and
response-dispatch regressions retain the predeclared measurement-plan budgets.
No new workload, native execution, provider request or deployment is involved.

## Implementation and decisions

- `scripts/diagnostics/paired_warm_results.py OFF_REPORT ON_REPORT` revalidates
  completion/cleanup, exact single-phase warm workload and raw resource/latency
  evidence through the existing independent validators before comparing results.
- Require distinct off/on run identities, identical source commit and recorded
  file hashes, operational mode and room/input topology. Historical matched
  artifacts are allowed; current HEAD is not substituted for measured provenance.
- The existing provenance's dirty-worktree flag is retained but is not evidence
  of code equivalence. Matching recorded source and hashes are required. This
  report does not certify unrecorded source files in a dirty tree.
- Preserve phase CPU seconds/rates/durations and high-water RSS, latency sample
  counts and p95s, enabled-minus-disabled deltas and original budgets. CPU target
  overrun does not change `measured_gates_pass`.
- `milestone_acceptance_complete` is always false. Egress latency, database CPU,
  inference coverage, cold phases, repeated topology matrix, acoustic accuracy and
  live acceptance remain separately required. This tool does not orchestrate or
  claim those checks and does not close the milestone performance checkbox.
- CLI exit 0 means only its measured RSS/ingress/dispatch gates passed; 1 means
  one of those regressions exceeded budget; 2 means invalid/incomparable evidence.

## Verification

Initial focused tests failed with `ModuleNotFoundError: paired_warm_results`
(`/tmp/vxpipe-paired-warm-red.log`), then passed after implementation.

- Paired comparison tests: 7 passed, covering advisory CPU, inclusive RSS/latency
  boundaries, reuse target, invalid/nonfinite measurements, mismatched provenance,
  malformed cleanup, and raw evidence inconsistent with saved summaries.
- Existing ingress/response validator tests: 8 passed.
- Existing smoke/watchdog validator tests: 16 passed.
- No Mix, live-provider or new native benchmark run was performed.

## Historical artifact demonstration

Revalidated the existing `vxpipe-response-latency-warm-off-reviewed/report.json`
and `vxpipe-response-latency-warm-on-reviewed/report.json` artifacts under `/tmp`,
writing `/tmp/vxpipe-paired-warm-reviewed.json`. Their measured source commit is
`4a60e4e1f5d145d0c6469f25d11270f69de80093`; this is not a current-HEAD measurement.

For fallback, one room and one input:

| Quantity | Enabled-minus-disabled | Budget | Result |
| --- | --- | --- | --- |
| CPU cores | 0.105005749 | 0.08 | Advisory target exceeded |
| High-water RSS | 45,460 KiB | 139,264 KiB | Pass |
| Ingress p95 | 21 us (266 → 287) | 2,000 us | Pass |
| Dispatch p95 | 842 us (252 → 1,094) | 2,000 us | Pass |

The report retains 625 ingress samples and 10 dispatch samples per phase, and
explicitly reports incomplete milestone acceptance. This demonstration is one
historical pair, not the repeated warm/cold matrix or acoustic-accuracy evidence.

## Astra review corrections

The review reproduced invalid acceptance of infinite generator elapsed time and a
truthy string in place of a successful high-water-reset marker. A malformed list
of measured turn counts escaped as an AttributeError instead of invalid evidence.
It also showed that differing off/on dirty-worktree flags lost the enabled-phase
provenance in the result.

Added CLI-level regression cases and a provenance-preservation assertion first:
all four checks failed as reported (`/tmp/vxpipe-paired-review-red.log`). The
artifact boundary now requires integer elapsed time, a turn-count map, and exact
boolean reset markers (first sample true, all later samples false). Both complete
provenance objects are reported under `provenance.off` and `provenance.on`; matched
hashes remain comparable even when dirty flags differ, with neither flag hidden.
The fixes are confined to the paired reader, avoiding concurrent edits to the
shared smoke runner. Nine paired tests, ten latency tests (including the concurrent egress additions) and sixteen smoke
validator tests now pass. Historical comparison was regenerated successfully;
its budget results are unchanged. No native/provider execution was needed.

Re-review found a nonfinite optional dirty flag could escape during output
serialization. Two additional CLI mutation subcases first failed (dirty flag and
extra provenance field; `vxpipe-paired-provenance-red.log`). The optional flag is
now boolean-only, and JSON serialization stays inside the invalid-input boundary.
All nine paired tests pass, including those subcases, with invalid evidence
returning exit 2 without a traceback. Final GPT-6 Astra xhigh re-review is clean
and independently confirms all nine paired tests pass.
