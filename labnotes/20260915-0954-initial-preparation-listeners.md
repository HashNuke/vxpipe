# Listener arrival during initial preparation

The previous goal turn made progress: `3da7a6a` commits native listener re-entry
through accepted preparation and unfinished cues. All five root gates passed
with 1,435 tests, zero failures and 16 exclusions. Eight checkpoint tasks remain.

The next whole-audience boundary is initial destination construction. Phase
currently captures the audience and runs destination preparation in the same
worker, publishing the audience only after preparation returns. A model or tool
initializer can therefore delay waiting playback for a newly joined listener.
Extend the existing native AI model/voice delay case: admit its planned monitor
while the model is blocked, require received wait audio before releasing it,
and retain the caller player, resources and original deadline through final
cue/greeting. Run that regression before changing the phase lifecycle.

Two initial fixture runs exposed mistaken helper names/registry keys; correct
those before treating a result as a behavior regression. The valid red native
case fails in 3.0 seconds because the added monitor receives no 250 Hz waiting
audio while the destination model remains blocked.

Publish the initial audience from the destination worker before model/tool
construction continues. Track that worker separately from the existing audience
refresh/handoff worker. The phase can refresh waiting listeners during expensive
construction; preparation results keep their own task-reference fence, and
acceptance still queues behind any audience refresh. Both workers remain linked
under the existing room transfer supervisor and share the original deadline.
No new supervisor, increased child limit, polling loop or generic coordinator is
introduced. Adjust the existing destination-exit fixture to monitor the named
preparer instead of the handoff worker.

The first runtime recheck stopped before destination model construction.
Temporary atom-only phase diagnostics showed `stale_handoff` during the initial
hold: Gateway authorized only `phase.worker`. An initial acknowledgement-routing
hypothesis was incorrect and its attempted change was removed. Permit the exact
phase preparer to issue only `hold`; adoption, recovery and release retain the
existing handoff-worker authorization and incarnation/attempt/deadline fences.
Remove all temporary diagnostic output.

The next native run received waiting and cues on the added monitor, but the
fixture incorrectly expected the AI greeting there. The existing first-message
contract targets the caller. Preserve that behavior: verify the caller's greeting
and the monitor's cue followed by permitted live caller audio. The final native
case passes in 4.3 seconds, including retained caller player, room/connection
bindings and original deadline while the model is blocked.

The first 52-test engine group encountered three cue/partial-release timing
failures while another native compilation/run overlapped. Re-run the owning group
on its own with serialized file compilation before deciding whether there is a
runtime regression; do not change deadlines or weaken assertions on that evidence.

All 52 owning engine checks pass in the isolated rerun (65.3 seconds), covering
agent preparation deadlines and re-entry, human web acceptance/worker loss,
policy/cue/adoption/partial-release behavior, and human phone transfers. Begin
all five root gates with the same module-preloading, serialized-file-compilation,
seed and concurrency settings as the previous passing root checkpoint.

Read-ahead for the remaining acceptance tasks: native human recovery already
performs a second briefing/admission/acceptance after destination loss, retaining
the caller peer and rejecting stale admissions. The engine re-entry case already
runs reception → billing → reception → billing with fresh activations, retained
identity/history and no repeated greeting. Extend that established sequence to
native audio/transcripts rather than inventing human-to-human transfer controls.

The native post-adoption policy cases revise an already connected observer.
They prove removed/unchanged/replaced speech demand and retained resources, but
do not prove the membership-to-attachment gap for a newly arriving listener after
adoption while conversation is still held. The adopted preparation branch uses
`Preparation.run`, unlike the pre-adoption missing-connection retry. Exercise
that distinct boundary before checking off the broad audience-reconciliation
item. Failures after conversational release starts must retain the established
room-closure behavior.

The full root run has passed all 653 engine checks and reached Gateway. A fresh
presence-only check confirms both live carrier lanes still lack their enable
flags, credentials, approved test numbers and callback/media URLs. No values
were printed and no carrier call was attempted. This external item does not
block the remaining native audience and repeated-transfer work.

Final root verification passes all five gates: formatting, compilation with
warnings as errors, strict Credo, tests and unused dependencies. The full suite
reports 1,435 tests, zero failures and 16 integration exclusions, including all
653 engine and 410 Gateway checks. The earlier three focused timing failures did
not recur in the isolated group or full root run; no runtime deadline or test
assertion was weakened. Documentation links and whitespace checks also pass.

Keep all eight compound checkpoint tasks open at their current boundaries. This
commit closes initial-construction listener arrival with a runnable native call;
it does not claim post-adoption membership, repeated-transfer acceptance or live
carrier audibility. No UI or dependency changes are part of this checkpoint.
