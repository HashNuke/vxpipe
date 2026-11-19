# Configured diagnostic drain

The f5a20d3b frozen root run is active in session71378; log
vxpipe-delayed-timing-final-umbrella.log. Keep repository runtime/test/build source
unchanged until it finishes. Temporary acceptance files are
vxpipe_configured_drain_test.exs and vxpipe_held_latency_store.ex.

The configured two-turn fixture now runs through a bounded test repository wrapper
that forwards normal writes to LatencyStore and deliberately holds the terminal
run write. The room shutdown returns and its DOWN is observed, the collector exits,
and a direct DB read still shows the running run while the writer remains pending.
After explicit release, writer DOWN is observed and the terminal run plus both
turn records are reread. This demonstrates post-call terminal-write drain, not a
turn revision blocked before shutdown or deadline/drop acceptance.

Initial wrapper matched only state:closed and therefore missed an honest incomplete
terminal run. Corrected to closed_at:DateTime (both terminal states); that was a
harness assumption, not a product defect. Corrected fixture passes1/0. Astra xhigh
independent review/rerun also passes1/0 and is clean; reviewer agrees it closes the
scoped configured-fixture acceptance once retained and final gates pass.

Next integrate the wrapper under Console test/support and the strengthened fixture,
then update the configured-fixture milestone item after its verification gates.
No production change is needed for this acceptance extension.

Related next contract inspection: ContinuousSTT already sends an explicit manual
commit when flushing a stable post-commit draft despite using provider-VAD mode.
Its real socket-send timestamp is not yet captured. Existing offline replay covers
that flush, but supplies scenario offsets, so it does not prove live timing.
Astra design review requested for an optional timed-commit socket API preserving
exactly one commit and original operational behavior; no implementation yet.

User scope correction: no real Telnyx numbers, no live Telnyx provider tests and no
Telnyx code changes. Existing root-suite Telnyx test uses local fixtures; no real
calls were made. Stopped the Telnyx failure investigation at the user's direction.
The root f5a20d3b run71378 finished exit2: Gateway had one local startup harness
failure (focused five generated startup cases passed5/0 afterward); Console had
one configured diagnostic discovery failure (room_unavailable before the fixture's
only discovery frame). Neither failure is relabelled as a passing suite. The VAD
fixture needs a discovery readiness barrier before its first audio frame.

Integrated the reviewed fixture and wrapper. Discovery now sends paced512-sample
silence until its own wire reports observation; later sequences/sample positions
start at that warmup's exclusive end. Warmup inference proceeds normally while
speech jobs remain explicitly held. This repairs the observed one-frame readiness
assumption without modifying production discovery. Focused test1/0; independent
Astra xhigh source review and rerun1/0 are clean. The milestone's configured fixture
acceptance is checked; final full suite remains deferred as directed by the user.
