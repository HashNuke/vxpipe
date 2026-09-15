# Listener changes before acceptance

The previous goal turn made progress: `618fddd` committed native monitor
connection loss/replacement with all five root gates passing (1,433 tests,
zero failures, 16 exclusions). Nine compound milestone tasks remain.

Extend the same native call with an additional planned monitor joining while the
destination is still waiting to brief/accept. Require immediate private waiting,
then remove that participant through its owning supervisor and readmit it during
the same transfer. Its new episode starts independently; every original player,
room service and transfer deadline remains. Continue through the existing exact
seven/three-second cursors, monitor connection replacement and cue-ordered
conversation to make this a runnable checkpoint.

Source inspection shows that Phase captures its initial audience once. New
connections are immediately held, but waiting-player reconciliation runs only
after acceptance. It also treats every initial player exit as a transfer failure,
including when the participant has actually left. These are hypotheses until the
native regression reproduces them. Reuse the existing phase and handoff helpers;
do not add a second coordinator or change the configured deadline.

For iteration, the temporary AST extraction from the preceding checkpoint keeps
this exact native test, setup and helpers while omitting unrelated generated test
cases. Final acceptance still requires the original module in the full umbrella.
No UI work or dev-server restart is required.

## Native regression and reconciliation

The native case first failed waiting for the late monitor's 250 Hz audio
(`vxpipe-preacceptance-native-red.log`). Connection attachment/removal now informs
the existing transfer phase. While waiting for acceptance, it runs the existing
audience capture/hold/playback helpers in a supervised refresh worker, keeping
Phase responsive to media-gate authorization. Changes arriving during a refresh
are coalesced; an acceptance arriving then waits for that refresh before starting
preparation. The same phase, owner, generation and absolute deadline apply.

Removed players are stopped and monitored to termination independently of the
retained players. Their expected departure cannot be mistaken for loss of a
required wait. Newly added players belong to the phase, so they survive the short
refresh worker. Once preparation starts, the established preparation worker owns
ongoing graph reconciliation.

The first implementation run exposed an existing telemetry enum boundary: the
internal refresh stage was not an accepted phase duration kind. Record that work
under the existing audience kind rather than introduce a new public phase. The
next extracted native run passes in 12.9 seconds. A late monitor joins before
briefing, pauses at two seconds, leaves through its owning participant supervisor,
and rejoins with a different player paused at half a second. Original players
remain, and the call completes its independent seven/three-second positions,
post-acceptance connection replacement and cue-ordered conversation. Forty-eight
focused engine/player/web/phone checks also pass.

Focused acceptance-race checks pause an actual connection readiness request while
the audience refresh is in flight, then accept from the authorized support
connection. Both completing and losing that refresh worker pass. The fixture
verifies the paused process is the phase's current refresh worker and that more
than five seconds remain on the original deadline, ruling out a timeout-based
false pass. Worker loss already propagates through the linked task and existing
room failure path; no new failure handler is needed.

The intervening goal turn only reported status and sent the requested push; it
was no implementation progress. Reinspection confirmed the acceptance-race run
finished with two tests and zero failures. Final umbrella checks and commit
remain pending. Changes during post-acceptance preparation/cues and repeated
changing-audience transfers remain separate acceptance work.

The final owning engine group passes all 50 tests. Formatting, compilation with
warnings as errors and strict Credo pass. The first umbrella run reports a
one-second `RoomMixer.flush_through/2` timeout in the existing partial recording
preparation test; that test does not run participant transfers. Keep the run
alive, check the recording group independently and inspect the completed results
before attributing this to scheduling or changing production code.

All five recording checks pass independently in 1.5 seconds. The first complete
engine lane reports 653 tests with that one failure; other lanes are still
running. No recording implementation or timeout has been changed on this
evidence.

The first umbrella run completed with exactly that recording failure: 1,435 tests,
one failure and 16 exclusions. All 410 Gateway checks passed, including the
original expanded native test module. Repeat the complete umbrella with the same
seed (235296) and concurrency (four), preserving the first log. A repeat pass
would establish current suite acceptance without establishing the cause of the
original timeout; do not describe an unproven root cause as fixed.

The identical recording timeout recurred in the second umbrella run. That run
was explicitly interrupted after the failure. A temporary stack-only diagnostic
in the failing recording test reproduced the timeout in the full engine lane:
the mixer was waiting in `:code_server.call/1` / `:code.ensure_loaded/1`, reached
from `Membrane.RawAudio.sample_size/1` during PCM mixing. Other short-deadline
fixtures also missed acknowledgements while the code loader was busy. The
diagnostic printed no process state or audio and was removed after capturing the
stack. That diagnostic run finished with 653 tests and seven failures; an
interrupt attempt arrived after it had already completed.

`mix help test` documents `--preload-modules`, which loads application modules
before tests execute. Verify with that existing option instead of adding preload
code to production/tests or increasing any runtime deadline. The full engine
lane is running with preloading, the same seed and concurrency. This is a
verification-environment detour, supported by the captured code-loading stack;
the outcome still needs verification.

With preloading, the recording failure disappeared in the full 653-test engine
lane. Its only failure was a distinct existing tool-worker monitor assertion:
successful completion arrived, followed by `:DOWN` with `:noproc` instead of
`:normal`. The [tool-worker labnote](20260915-0849-tool-worker-monitoring.md)
records the fixture acknowledgement correction and seven passing focused checks.
Keep that one-line test change in its own commit. Run the final umbrella with
module preloading and unchanged seed/concurrency/runtime deadlines.

The final root run now passes all 653 engine checks with one integration
exclusion, including recording and the corrected worker fixture. Gateway
acceptance and the remaining root lanes are still running.

That root run later reported a separate ordinary human-only WebRTC failure:
after a restrictive specialist joins, one caller packet did not produce the
expected specialist output within five seconds. The test has no pending
participant transfer. The captured failure is at
`HumanOnlyWebRTCTest`'s restrictive-routing case; retain it and recheck that case
directly before changing its fixture or attributing it to timing. This adds no
new transfer requirement. The full run remains active while the focused native
recheck runs in an independent test VM.

## Checkpoint result and remaining verification

The isolated restrictive-routing case passes (one test, five excluded). Its
complete owning module then fails (six tests, one failure), this time awaiting
the initial caller-to-receiver packet before any restrictive participant joins.
This is not yet explained; do not call it an isolated transient or a policy
regression. No change has been made to that test or its media path.

The latest complete umbrella run has 1,435 tests, one human-only routing failure
and 16 exclusions. All 653 engine checks and the expanded native listener test
pass. Formatting, compilation with warnings as errors, strict Credo and unused
dependency checks pass. The original native module also passed in the first
umbrella run, whose separate recording load timeout is recorded above.

Commit the verified listener implementation and the tool-worker fixture
correction separately, preserving these failed-check results. The milestone
explicitly allows several implementation-progress commits before a delivery
checkpoint passes all acceptance gates. Do not check off the slice or claim an
all-green umbrella. Next investigate the ordinary native packet path, then
continue membership changes during preparation/cues and repeated transfers.
Nine compound tasks remain; full milestone acceptance and its root test gate
remain open. No UI or development-server change was made.

Read-ahead for the next acceptance boundary: during accepted preparation,
`await_preparation_change/5` treats a wait-player failure as fatal before checking
whether the player belongs to a removed listener. During cues, `await_players/5`
also treats player failure as fatal, while its existing candidate-change retry
waits for the old players and clears the old connections. Exercise actual
membership removal in those stages before deciding which existing reconciliation
path needs adjustment. These are source-inspection hypotheses, not reproduced
failures or extra requirements.
