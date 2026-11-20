# Diagnostics ingress latency

## Boundary and design review

The configured external workload now records successful push invocation to
synthetic provider receipt. Construct the audio frame before the ingress timestamp;
take the provider timestamp in the fixture wire callback, before sending its
observer notification. Both use the measured VM's monotonic microsecond clock.
Retain wire ordinal and timestamp with the PCM in the same optional notification.
Other fixtures retain their existing message shape.

Existing exact PCM and frame-count assertions prove delivery. Reject an unknown
wire, extra/missing ordinal or negative elapsed time. Retain every raw pair and
select the warm cohort from the predetermined sequence/phase schedule, not from
observed completion times: all 625 measured frames per input remain represented,
including deliveries beyond the nominal interval. Signed timestamps and zero
elapsed durations are valid. Independent Elixir/Python calculations use nearest-
rank p95 and require the full source/frame population before accepting summaries.

Astra design review is clean. It required timestamping after frame construction
and combining receipt time with PCM notification; both are implemented. The
measurement plan records the precise boundary and rejects interpreting it as
microphone, network or observer-mailbox latency. Response dispatch/egress and the
other open measurement gates remain unchanged.

## Red-green evidence

Artifact names refer to the host temporary directory.

- `vxpipe-ingress-latency-red.log`: three Console tests failed on the absent
  summary boundary; the first invocation ran the explicit path from the umbrella
  root, where only Console matched. Subsequent focused runs use the owning child.
- `vxpipe-ingress-wire-red.log`: optional timestamp/ordinal receipt assertion
  failed with the existing three-element message, while the legacy test passed.
- `vxpipe-ingress-python-red.log`: independent validator import failed before the
  implementation existed.
- `vxpipe-ingress-latency-green.log`: Console 4/4, including late-tail p95,
  four-input coverage, missing/reordered/negative samples and all smoke frames.
- `vxpipe-ingress-wire-green.log`: Engine 2/2, proving callback timestamp lies
  within the synchronous call, successive ordinals, and legacy notification shape.
- `vxpipe-ingress-python-green.log`: 57/57 diagnostic Python tests, including raw
  count/order/type/duration validation, forged summaries and runner integration.

No live providers or Telnyx numbers are used. This checkpoint changes test
instrumentation and validation, not production VAD or provider behavior.

## Review correction

Independent review used the actual first enabled report to swap measured frames
200/201's timestamp pairs, leaving ordinals and p95 unchanged. Both validators
incorrectly accepted clocks moving backwards within one input. Retained Python
and Elixir regressions fail before correction (`vxpipe-ingress-order-red.log`,
`vxpipe-ingress-order-elixir-red.log`); both now require independently nondecreasing
ingress and provider clocks. Equality and overlapping in-flight frames remain
valid. Tests vary each clock independently and together. The focused checks above
are green after this correction.

The initial `vxpipe-ingress-latency-warm-on` remains evidence for the previous
validator: it completed cleanly with 625 measured receipts, ingress p95 276 us,
2.55 CPU-seconds, HWM 250284 KiB and ten measured turns. Corrected-validator phases
are rerun rather than silently relabeling that earlier provenance.

The first corrected enabled attempt (`vxpipe-ingress-latency-warm-on-reviewed`)
fails the existing resource-boundary timing gate: the initial sample finished
2,650,575 ns late, beyond the 2 ms limit. The wrapper exits nonzero and cleans its
scope/database. This attempt remains retained and excluded from valid comparison;
no timing budget was relaxed. The retry uses a new artifact directory.

## Corrected configured warm evidence

The valid one-input phases are `vxpipe-ingress-latency-warm-off` and
`vxpipe-ingress-latency-warm-on-retry`. Each has ten measured canonical turns,
782 raw frame receipts / 625 measured latency samples, 201 resource samples,
maximum threads 11 and clean scope/database teardown.

| Collection | Ingress p95 | CPU seconds / cores | Interval seconds | HWM KiB | PCM pacing p95 ns |
| --- | --- | --- | --- | --- | --- |
| Off | 309 us | 0.75 / 0.037501 | 19.999232 | 203184 | 349947 |
| On | 300 us | 2.61 / 0.130506 | 19.999129 | 247000 | 225873 |

The preliminary ingress p95 delta is -9 us, within this stage's unchanged 2 ms
regression budget. The CPU delta is 0.093004 cores, still above the 0.08-core
one-input budget. Neither one comparison nor a passed ingress stage establishes
full paired acceptance: repetitions, remaining topologies, cold startup, response
dispatch/egress latency, database CPU, inference coverage and accuracy remain open.
The instrumentation is identical in both phases; earlier pre-instrumentation
CPU measurements do not substitute for this baseline.

The two-room/two-human operational-reuse phase
`vxpipe-ingress-latency-warm-reuse` passes with per-input raw counts
782/781/781/781, 2500 measured latency samples, p95 311 us and measured turn counts
10/11/10/10. Resource evidence: 19.999559 seconds, 8.13 CPU-seconds / 0.406509 cores,
HWM 299200 KiB, maximum threads 11, 201 samples and PCM pacing p95 217277 ns.
Owned scope/database cleanup is clean. This verifies multi-input receipt accounting
and reuse behavior; no matched reuse-off overhead comparison is claimed.

Final root format, warnings-as-errors compile, strict Credo and unused-lock checks
pass (`vxpipe-ingress-format.log`, `vxpipe-ingress-compile.log`,
`vxpipe-ingress-credo.log`, `vxpipe-ingress-deps.log`). Local documentation links
resolve. This test-instrumentation change does not alter source-cutover or speech
state-machine transitions. Full umbrella tests remain deferred until milestone
implementation is complete; no Lean, live provider/Telnyx test or deployment is
claimed by this checkpoint.

Final GPT-6 Astra xhigh review is clean. The exact real-artifact ordering probe
passes 2/2 (`vxpipe-ingress-order-fixed-review.log`). Independent artifact review
recomputes latency populations/p95, resource samples, pacing, identity, readiness
and cleanup, and verifies all 26 source hashes match both current files and one
another across corrected phases (`vxpipe-ingress-artifacts-review.log`). It also
confirms the rejected attempt and outstanding CPU-budget failure are accurately
retained in the documentation.
