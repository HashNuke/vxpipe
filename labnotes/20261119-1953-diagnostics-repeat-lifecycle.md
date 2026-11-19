# Repeated configured diagnostic lifecycle

## Scope

Added configured Scribe fixture acceptance for 20 fresh call lifecycles with local
Silero off and 20 with local Silero on. Each call collects one canonical turn,
disables diagnostics while a second turn continues normally, re-enables into a
new diagnostic run for a third turn, then shuts down the room. Synthetic inference
keeps this a deterministic lifecycle check rather than an acoustic/load claim.

Each boundary verifies exact marker PCM and correlated transcript/response output.
After revocation and teardown, source admission has zero occupied slots, diagnostic
inference admission is zero, and inference/write task pools are empty. Existing
drain checks cover source workers, collectors and writers. Room completion and
diagnostic subtree termination are monitored explicitly. Re-enable must retain the
new settings revision and create distinct run and epoch identities.

The repeated fixture limits writers and collectors to one, so succeeding cycles
must recycle their capacity. It uses a unique synthetic platform credential name
per test tenant to allow multiple calls in one sandbox. No provider/runtime code,
real credentials or Telnyx behavior is changed.

## Verification

Initial fixture run incorrectly addressed the inference supervisor rather than
ActivityRuntime when reading admission. Corrected the test probe to the configured
runtime name. This was not a production defect.

The initial complete 20-cycle matrix passed 2/2 tests, seed 641936, in 87.6 seconds.
Independent review then identified two final-barrier gaps: late duplicate marker
delivery/inference could escape phase-local refutes, and a delayed disabled-period
row could escape the immediate absence assertion. Final assertions now retain all
three canonical IDs/markers and check after room termination and writer drain:
exactly the two enabled turn rows, no disabled ID, and no residual marker, final
transcript or response event.

Review reproduced both gaps with one-cycle-per-mode controls against the original
test: inject extra PCM/inference messages after phase-local refutes, or copy a
valid enabled row under the disabled canonical ID using `LatencyStore.put_turn`
after the immediate nil assertion. Positive post-drain checks proved the extra
messages/row survived, yet both original controls passed 2/2. With the strengthened
test, those same controls fail 4/4 at the intended final assertions: duplicate
PCM rejection and the exact stored run/turn pair set. The reviewer inspected the
controls and failures and found no further source/assertion issue. No production
behavior defect was inferred from this deliberately injected evidence.

Final normal selection passes 7/7, zero failures, seed 27748, in 102 seconds:
both complete 20-cycle modes plus the existing pending/late timing case and four
operational-VAD/collection combinations. The repeated cases exercise 40 rooms,
120 canonical turns and exactly 80 enabled-period diagnostic rows, with all 40
disabled-period canonical IDs excluded after final drain. Final source, fault
controls and passing evidence have a clean Astra xhigh review. Root format,
warnings-as-errors compilation, strict Credo and unused-dependency checks pass.
No UI or runtime/source-state-machine behavior changed, so browser and Lean
verification were not repeated for this test-only checkpoint.

The broader saturation/stress gate remains open. This checkpoint does not measure
RSS, native inference CPU, mailbox high-water counts or acoustic accuracy. Full
suite and live acceptance remain deferred until milestone implementation completes.
