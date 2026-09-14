# Recovery readiness race

## Failure localization

Continue the human cleanup acceptance after `5776a2c`. The historical destination-loss failure
ended with a bare `{:error, :unavailable}` from the recovery worker. Most capability preparation
failures attach a resource kind/scope, which narrows the bare result to capture/gate operations
or an outer preparation failure. The historical log did not trace individual operation returns.

`RoomAudioEgress.OutputGate.change/3` reads its shared pipeline's readiness before holding it.
That reaches `OutputArbiter.Readiness.observe/2`, which originally required identical before/after
maps including `status`. A normal clear/drain transition can change only that status while the
native output is being queried. The observer then reports unavailable, and the recovery gate
fails instead of waiting for its still-healthy output. The collector handles unavailable as
preparing, but this earlier gate does not use the collector.

## Deterministic regression

Two owning Gateway cases pause a real native readiness query after its first arbiter binding
read, begin an actual output clear, and then resume the query. The native pacer withholds the
last-frame acknowledgement so clearing remains observable. Both private and room readiness
must report the same resource as preparing, then ready after actual clear completion.

Both cases fail with `{:error, :unavailable}` before the fix. Comparing binding identity without
its transient status and reporting the freshly read status makes both pass. Native adapter and
resource identities still have to match; replaced room tokens remain invalid. No recovery
deadline, retry policy, process or public configuration is changed.

Logs: `vxpipe-output-readiness-race-red.log` (two expected failures) and
`vxpipe-output-readiness-race-green.log` (two passes). The native caller/desk case below places
this same interleaving inside actual destination-disconnect recovery.

## Native fixture corrections

The first native attempt called clear while cancellation's original wait clear was still in
flight, so it stopped at the fixture's `{:error, :clearing}` assertion. Use a temporary readiness
collector to acknowledge completion of that clear before injecting the controlled second one.
The collector's default child ID includes the attempt ID; the initial cleanup incorrectly used
only its module name. The helper now supplies an explicit child ID and stops exactly that child.
One already-running attempt still exercised the prior helper and reported the same cleanup error.

The output observer uses OTP's actual debug reply shape, including the full `{pid, tag}` caller.
Both the native-query and native-clear pauses have bounded fallback release and explicit cleanup.
The transfer/recovery deadlines are unchanged. The native case also requires spoken source
recovery, another caller turn, and a successful subsequent transfer on the original connection.

The old comparison was tested in a separate test VM by compiling its prior implementation
there from the current source. This did not change the production source, compiled artifacts or
development server. The fixture corrections are separate from the production readiness fix.

## Native causal reproduction

With the fixture corrected, the old observer fails at the same `await_recovered` assertion as
the historical destination-loss case. RoomAuthority terminates with `:handoff_recovery_failed`;
its last message is exactly the recovery worker's `{:error, :unavailable}` result. The injected
interleaving changes only clearing status while the actual recovery hold reads the same output.
No provider, room, connection, codec or binding has been replaced or failed.

This establishes a concrete cause of that fatal recovery outcome, rather than inferring a fix
from successful repetitions. The historical log did not record individual operation returns,
so it cannot independently identify its original observer call. The deterministic case now
covers that failure class and must pass with the fixed observer, including the retained caller,
spoken recovery, next caller turn and a later accepted human transfer.

Native baseline: `vxpipe-native-recovery-clear-baseline.log`, one expected failure, 61 excluded.
The final root result against the fixed implementation is recorded below.

## Human cleanup acceptance audit

The owning human-transfer cases cover exact authenticated control, early/duplicate acceptance,
private capability loss, destination and phase loss, late readiness after expiry, cue drain/loss,
readiness loss, changed policy/bindings before commit and after adoption, and failed privacy
application. Seven partial-release cases cover changed policy, connection generation, explicit
release error, final-completion policy change, deadline, phase loss and required speech loss.
Those paths close without activation when admission has become uncertain. Queued successful
recovery cannot win after cancellation, and retired briefing events cannot crash pending recovery.

Native acceptance additionally covers actual briefing/acceptance expiry and disconnect, exact
admission release, source conversation, independent destination/remaining-human/recording loss,
ordered cues, retained media and successful re-entry. The new output-clear interleaving covers
the reproduced recovery race before readiness collection. Existing web controls intentionally
have acceptance only; declining is disconnect or expiry, not an unimplemented reject operation.

This audit does not complete AI model/tool/MCP readiness, phone playout, the five-participant
changing-audience matrix or the final milestone audit. Those remain separate delivery tasks.

## Root-run failures and corrections

The first full run passed format, compilation and Credo, but failed two native assertions.
The existing three-peer recovery case waited for progress on the destination transport that
the injected speech loss was disconnecting. Enqueuing progress before cleanup cannot guarantee
delivery on a closing SCTP connection. Its recovery/reason assertion now belongs to the retained
caller and still checks reason continuity through the final recovered event. Connected-desk
progress remains covered by ordinary preparation/release cases; this does not weaken caller
failure delivery or require an acknowledgement from an unavailable destination.

The new clear-race case passed its forced observation but its own `after` block sent a second
`continue_native_gate` message to the real caller connection after its debug hook had resumed.
That test-only message reached the ordinary handler and crashed the connection. Remove that
duplicate release; the one-shot connection gate is already unconditionally released at the
start of the try block. Native output fallback releases remain harmless and bounded.

Root evidence: `vxpipe-recovery-readiness-gates-test.log`; all other tests passed. The corrected
two native cases pass together (`vxpipe-native-recovery-clear-focused.log`: two tests, zero
failures, 60 excluded). This verifies cue/spoken recovery and subsequent accepted transfer for
the new race, plus retained resources and recorded conversation for the existing three-peer case.
The final root rerun uses the same seed and concurrency.

The milestone index is consolidated into current slice status and links to the detailed ledger.
Earlier findings, commits and detours remain in the milestone and their original labnotes. A stale
20-task summary was first corrected to match the actual 19 open checkpoint tasks; final human
acceptance below reduces the count to 17.

## Final verification and human slice completion

All five final root gates pass: format, compilation with warnings as errors, strict Credo,
`mix test --max-cases 4 --seed 235296`, and unused dependency locking. The suite contains
1,411 tests, zero failures and 16 integration exclusions. Gateway contributes 397 tests,
including 61 default native startup/transfer cases; Call Engine has 642 and Console has 95.
The final run includes both corrected native recovery cases and the unchanged failure matrix.
Results are in `vxpipe-recovery-readiness-final-results.json` and the corresponding check logs.

The human web handoff slice is accepted with its existing configuration, privacy, complete-resource,
cue ordering, failure, diagnostics, admission and rendered-sample evidence. This checkpoint closes
its remaining cleanup/commit tasks. Initial caller waiting was already accepted. Seventeen tasks
remain: AI three, phone six, changing/multiple listeners six and final audit two. The complete
milestone remains open. The next delivery slice is AI handoff, including independent tool/MCP
readiness, URL/nil waits and exactly-once greeting/completion evidence.

No UI, dependency, definition or deadline change was required. The production change only separates
transient output status from stable resource identity. Other-agent documentation-site changes
remain untouched. The index now summarizes accepted and remaining slices; earlier checkpoint
details and their historical limits remain in the milestone ledger and original labnotes.
