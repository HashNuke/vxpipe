# Listener changes during preparation

Continue the same native transfer after `036232a`'s pre-acceptance listener
addition/removal/re-entry. While accepted support STT is still deliberately
unready, remove the late monitor's complete participant membership and readmit
it. Require a fresh wait player and decoded waiting audio while all original
players, room resources and attempt/deadline remain. Then finish the existing
cue-before-conversation checks for every listener.

The source currently treats wait-player failure as fatal in
`HumanMediaHandoff.await_preparation_change/5` before reconciling membership.
The extended native case is the regression check; run it red before deciding
how to adjust that existing reconciliation path. No UI, new coordinator or
deadline change is needed by the requested outcome.

The temporary AST extraction retains this exact native test, setup and helpers
while omitting unrelated generated test cases for focused iteration. The full
original module remains required for broader acceptance. The separate
[native routing investigation](20260915-0907-native-audio-routing.md) records
four unsuccessful attempts to reproduce the previous ordinary media failure
with safe diagnostics; that failure remains an open root verification item.

The native regression fails in 16.1 seconds: the returning listener never hears
its 250 Hz wait after leaving during accepted preparation. Before treating a
wait failure as fatal, reconcile the existing candidate against the authoritative
membership. If the failed player is still required, retain the failure; if
reconciliation removes it, continue readiness with the retained players. This
uses the existing graph/wait diff and deadline rather than retrying a failed
required output or restarting unrelated resources. The first implementation
run is in progress.

The first adjustment still failed, now at the returning peer's admission (HTTP
503). Temporary stage/kind/reason-only output showed preparation failing with
missing `media_connection`, followed by recovery failure. Re-entry admits the
participant before its WebRTC attachment finishes; the candidate observes that
short interval without a connection and previously treated it as terminal.

Keep the existing candidate and partial leases while waiting for that specific
missing connection, report the media-connection blocker, and recapture within
the unchanged deadline. Other missing/failed capabilities retain their failure
behavior. This uses the worker's existing readiness polling interval. Remove the
temporary diagnostic output before rerunning the native acceptance check.

The extended native preparation case now passes in 17.7 seconds: removal and
re-entry retain original waits and finish cue-ordered conversation. Extend the
same call through the remaining cue boundary before a broader verification run.
A one-shot debug callback on the returning listener's real output recognizes
the cue episode and pauses its player after the first acknowledged 20 ms frame.
This leaves the output actor responsive and does not depend on winning a 250 ms
polling race. Remove that listener during its unfinished cue, readmit it and
require the final ordinary transfer and cue-before-conversation for the updated
audience. Run this additional boundary red before implementation.

Cue removal/re-entry first failed with HTTP 503. A changed candidate now cancels
the old cue players, clears current live outputs, and reuses preparation to
refresh the audience and replay cues. Failed playback remains fatal when the
inventory has not changed; stale events from retired players cannot fail new
players. Both membership and policy invalidations trigger the refresh.

The next native run completed the transfer but its old assertion rejected wait
audio after any cue. The approved contract requires a new wait/cue sequence when
readiness changes. Keep the default helper strict; only this changing-cue case
allows waiting after a cue and resets the ordering assertion so conversation
requires a subsequent cue. The caller explicitly receives the first cue before
removal and the resumed wait after re-entry. Every later wait must be followed
by another cue before conversation; neither waits nor cues may follow
conversation.

The complete native flow now passes in 21.4 seconds. All 61 focused engine checks
also pass across agent transfers, human web/phone transfers and wait players.
After green, consolidate the three identical participant-removal/monitor steps
into one fixture helper and assert retained room services and surviving original
connection bindings after cue replay too. Recheck the final native case before
the full umbrella gates. Runtime deadlines, default cue duration and ordinary
audio-order assertions remain unchanged.

The final test refactor recheck encountered another valid cue retry for the
caller: removal and re-entry can invalidate separate candidates. Keep the
explicit first-cue-to-resumed-wait assertion, but allow further candidate retries
for the caller too, with the same requirement that each later wait resets the
cue requirement. This does not allow private audio after conversation or alter
the default ordering helper used by ordinary handoffs.

The final native case passes in 14.1 seconds, including the post-replay resource
identity assertions. Start all five root gates. The full suite uses documented
Mix options `--preload-modules --max-requires 1 --seed 235296 --max-cases 4`:
application modules load before tests, test-file compilation is serialized, and
four async test modules can still run. This reduces compilation contention
without changing test assertions, runtime deadlines or integration exclusions.
The prior human-only audio failure stays open until the current full run supplies
fresh evidence.

Read-ahead for the remaining whole-audience task: the phase still captures the
first audience and constructs the destination in one worker. A new listener
arriving while that initial model/tool construction is blocked may wait for
destination preparation before its audience-refresh notification is handled.
The current native case changes membership after private preparation completes.
Exercise the blocked-initial-preparation boundary with the existing native AI
model-delay fixture before checking off the broader reconciliation task. The
existing engine re-entry test already covers fresh AI activation and retained
identity/history; reuse that contract when adding repeated native transfers.

Final verification passes all five umbrella gates: formatting, compilation with
warnings as errors, strict Credo, the full test suite and unused-dependency check.
The suite reports 1,435 tests, zero failures and 16 integration exclusions;
653 engine and 410 Gateway checks include the expanded original native module.
The previous ordinary human-only routing failure did not recur. The full test
command was `mix test --preload-modules --max-requires 1 --seed 235296 --max-cases 4`.

Mark only the five-participant playback demonstration complete. Eight checkpoint
tasks remain: five changing/multiple-listener tasks, one live carrier audibility
task and two final audits. Broader reconciliation, repeated transfers and failure
acceptance retain their open checkboxes. This checkpoint changes the existing
handoff reconciler and native fixture, with no UI or dependency changes.
