# Endpoint tail certificate

Actual operational-reuse trace showed finalized sample residuals of 256 and 448
samples at clean provider settlement, with complete acoustic endpoints. One zero
residual turn remained available. No PCM, transcript or probabilities were logged.
The exact provider receipt cursor is addressed by a separate checkpoint.

Implemented an explicit pre-reset accepted-tail witness in InferenceTap and a
strict idle/bounded SourceWorker certificate. LiveReport consumes this only for
endpoint/provider-end eligibility; generic progress, segments and barge timing are
not promoted. The durable design is `docs/design/diagnostic-endpoint-tail.md`.

Initial focused red run: 30 tests / 9 failures from absent witness and unsupported
certificate packets. Initial green: 30 / 0. Added pending onset, active speech,
pending offset and invalid-epoch negatives: related seven-file set 50 / 0.

Independent Astra review found two projection fences. Both were reproduced red
(5 tests / 1 failure each): an endpoint inside the unclassified tail, and forward
progress between certificate and reset. Added endpoint <= finalized guard and
immediate progress fencing. Related seven-file set: 51 / 0. Existing operational
wrapper tests then exposed two intentional packet-order expectation changes
(14 / 2); now assert explicit witness before normal reset, including late in-flight
result delivery. Final combined results recorded below.

No live providers, native inference, full suite or Telnyx were run for this
checkpoint. Parent owns final real browser/Scribe verification and live harness.

Final combined eight-file set: 65 tests, 0 failures (seed 551779).
Scoped format check passed. An overly broad expectation edit initially affected
two negative wrapper cases; those retain reset-first behavior and were corrected
before the final green run.
