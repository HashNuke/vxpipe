# Diagnostics acceptance scope

The user rejected dedicated database CPU acceptance and explained that Silero is
already tested: the milestone should verify that the model works, without
additional inference-coverage or model-accuracy tests. Removed those requirements
from the current milestone, measurement plan and paired report's missing-evidence
list. Historical notes and already collected evidence remain historical; the
completed acoustic replay is explicitly optional now.

Application contracts remain: correct source/mode wiring, both latency metrics,
persistence/UI, bounded asynchronous writes, failure isolation, honest missing
status and cleanup. CPU targets remain advisory. Other outstanding performance,
live-browser and final checks remain. The subsequent explicit user decision
replaced cross-worker effective-settings acceptance with a persisted snapshot per
new call and removal of propagation machinery; the milestone tracks that migration
as incomplete until its behavior and cleanup pass review.

A focused paired-report regression first failed because database_cpu remained in
missing_acceptance_evidence (vxpipe-acceptance-scope-red.log). After removing all
three out-of-scope flags, all 11 paired tests pass. No new native/model/provider
runs were required. Independent Astra xhigh checkpoint review is clean.
