# Diagnostics egress comparison

Extend the reviewed paired warm comparator to use the new configured egress
measurement when both phases provide it. Historical dispatch-only artifacts
remain explicitly partial. A pair with egress on only one side is incomparable.

Two focused tests first failed for absent egress output and accepted asymmetric
evidence (`vxpipe-paired-egress-red.log`). The reader now independently validates
raw egress evidence through the normal smoke validator, preserves its counts and
p95, and applies the predeclared max(2 ms, 10% of baseline p95) regression budget.
Malformed output identity, nonfinite values and regressions cannot pass. All
11 paired tests pass. Egress is removed from missing evidence only when measured
on both sides; cold, repeated matrix, database CPU and coverage remain open.

This is test/measurement plumbing, not a new production metric or an actual load
result. It belongs with the completion-egress benchmark checkpoint. Final GPT-6
Astra xhigh review is clean after the shared validators' cross-population and
chronology fixes; 36 focused Python tests pass, including all 11 paired tests.
No native execution or provider request was required here.
