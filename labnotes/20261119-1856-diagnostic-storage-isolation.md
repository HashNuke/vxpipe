# Diagnostic storage isolation

## Scope and evidence

The configured synthetic Scribe call now injects failure only at the diagnostic
repository boundary. Ordinary call/settings storage stays on the real sandbox Repo.
Eight cases cover returned repository errors and indefinitely blocked writes,
operational Silero off/on, and diagnostic collection off/on. This is acceptance
coverage of existing asynchronous writers; no runtime/provider code changes.

Enabled cases must observe the repository attempt. For blocked writes, an explicit
acknowledgement from the same still-blocked task after both conversational turns
proves the call progressed before that attempt ended. Each case checks exact
provider PCM, canonical transcripts, matching response correlation and text,
no duplicate marked PCM, and no extra provider commit or connection failure.
Operational Silero cases also require their original inference deliveries.
Disabled cases must never invoke the diagnostic repository.

Room completion precedes diagnostic drain; writer/collector/source children and
write tasks must disappear. A five-second test observation window accommodates the
production two-second writer drain plus asynchronous retirement; it does not change
runtime deadlines. Missing persisted diagnostic runs are expected for failed writes.

## Verification

Initial focused selection passes 8/8 (`/tmp/vxpipe-storage-isolation-first.log`).
Independent review and final configured results are recorded below. The combined
failure-parity milestone remains open for remaining saturation/control-trace gates.
No live providers, Telnyx changes, full-suite run or deployment.

Independent Astra scoped review is clean. Its baseline passes 8/8 and a fast-return
control fails both enabled blocked cases at the required same-task acknowledgement
(`/tmp/vxpipe-storage-ended-attempt-review.log`). A separate 600 ms-per-response
control also outlives the unchanged one-second attempt deadline and correctly fails
that overlap assertion. The test proves overlap for synthetic fast turns, not a
latency or load guarantee. Root format, compile with warnings as errors, strict
Credo and unused-lock checks pass. No runtime change requires a new Lean run.

## Broader configured run and unresolved readiness failure

Two untraced runs with seed 214098 each pass 33/34. The existing external
STT-to-STS audio-policy routing case with Silero off fails in call/3 while waiting
for test_call_ready, before its diagnostic assertions. Both logs show a further
scribe_started message after the fixture acknowledged its initial Scribe wire,
and a redacted speech-to-speech capability termination. The cause is not established;
do not claim that the storage tests caused it or that it is fixed.

Reproduce from the Console child with:
`mix test test/integration/configured_latency_diagnostics_test.exs --seed 214098`.
Logs: `/tmp/vxpipe-storage-configured-final.log` and
`/tmp/vxpipe-storage-configured-repeat.log`. Independent review's same-seed full
run with tracing passes 34/34 (`/tmp/vxpipe-storage-current-order-review.log`).
The previous HEAD file's four isolated STT-replacement cases also pass; that does
not rule out an ordering/race issue. Keep this evidence visible for the milestone's
final gates. No speculative STS runtime or fixture change is included here.
