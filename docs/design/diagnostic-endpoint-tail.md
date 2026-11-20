# Diagnostic endpoint evidence at clean operational settlement

Operational Silero reuse resets its classifier at provider turn settlement. The
last accepted PCM block may leave fewer than 512 samples beyond the last finalized
classifier window. Treating this discarded fractional tail as a lost full window
made otherwise complete endpoint measurements unavailable.

A clean settlement now emits the old epoch's contiguous accepted sample end before
its reset. The diagnostic worker issues a separate endpoint-tail certificate only
when the epoch and source origin match, all queued windows are processed, the
boundary is idle with no pending speech or silence candidate, capture covers the
accepted end, and the remaining tail is strictly between zero and 512 samples.
Missing, late, discontinuous or insufficient evidence remains unavailable.

The report accepts the certificate only against its existing exact finalized
frontier and before epoch closure. It can extend eligibility for the provider-end
sample only: the actual acoustic endpoint must already be at or before the
classified frontier. Provider mappings and ordinary validity/ambiguity checks
remain mandatory. Certificates are immutable, identical duplicates are harmless,
and further progress cannot reopen the certified epoch.

This does not classify the tail, manufacture a speech boundary, extend acoustic
segments, or change barge-in coverage. Generic frontier advancement and rounding
provider samples down were rejected because either would claim inference that did
not occur. An unresolved full inference window or pending boundary candidate cannot
receive a certificate. Operational speech control and reset behavior remain unchanged.

Focused verification covers witness ordering, source and epoch fences, pending
candidates, full-window loss, exact provider bounds, endpoint classification,
immutable progress, duplicates, genuine failures, and unchanged segment/barge
projection. See `labnotes/20261120-0416-endpoint-tail-certificate.md` for execution
evidence. Live two-mode verification is tracked separately by the milestone.
