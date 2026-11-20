# Diagnostics egress latency

## Scope correction

During this work the user accepted the measured CPU cost for optional benchmarking.
The milestone and measurement plan now make CPU targets advisory, retain measured
numbers and historical misses, and stop further CPU optimization. Correctness,
latency, bounded resources, coverage and cleanup remain required. The user also
requested clearer progress and less fragmentation; remaining measurement work is
being consolidated instead of producing a checkpoint for every small addition.

## Work in progress

Extend the configured workload with synthetic TTS and per-human output sinks.
Trace room-authorized AgentSpeechStarted publication as egress acknowledgement,
keeping source participant, command/correlation and output identity. This is a
synthetic transport acknowledgement, not physical audibility. Provider audio alone
must not count as acknowledgement; fixed input pacing continues independently.
Focused red tests currently cover the additional trace boundary and matching output
identity. The end-to-end audio workload is not yet complete or accepted.
