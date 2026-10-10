# Room activity admission

Scope: existing B external/hybrid room-control task. The compiled-room Morse
external/hybrid tests in `sts_transcript_modes_test.exs` are red because the
selected human STT's start/end signals only publish caller turns; RoomAuthority
does not submit them through the ordered `STSIngress.activity/4` path.

Current boundary inspected before edits: STT private `Signal` freezes native
allocation generation, turn reference and caller audio-input/output intervals
at capability emission. `SpeechToText.input_binding/1` exposes the current
selected activity origin when ready. `STSIngress.activity/4` shares one
bounded credit with PCM, validates epoch and scoped intervals, and its
capability delivery rechecks identity, presence, routes, hold and policy.
RoomAuthority must match the frozen signal against that current origin and
exact source/agent allocation before enqueuing a boundary. It must not mint
provenance for a late signal. Initial external mode needs one start and one
matching end; hybrid needs only the end, with provider onset retained.

The pre-existing red tests and the approved design/task breakdown are in
`labnotes/20260923-0121-external-room-control.md`,
`labnotes/20260923-0131-sts-external-room-control.md`, and the B checklist. This checkpoint
does not claim hold/reopen or native source-time acceptance. Those require
acknowledged upstream cutover and recognizer retirement before regrant.

Focused red rerun: `mix test` at the two external/hybrid room-test locations
failed 2/2 with no sink reply. The first room implementation validates exact
source connection, selected STT capability's current activity origin,
allocation generation, frozen source audio intervals, participant presence,
both audio routes and the active STS input epoch before placing a boundary on
`STSIngress`. External sends start and matching end; hybrid records the STT
pair but sends only end, retaining provider onset. The two original room
tests pass after that wiring. Provider-controlled mode still sends no room
activity control.

Before committing, the existing hold gap was converted into a focused room
red: an idle external STS allocation survived `SpeechToSpeech.hold/1` while
its selected STT allocation retained the same generation. The test failed at
the still-bound STS capability. The interim fix now closes/fences the STS
capability and retires the whole external/hybrid allocation on room hold,
without claiming reusable hold/release. The room test also verifies the STT
allocation's generation survives that hold, while a delayed signal carrying
it cannot acquire a new STS epoch because the STS allocation remains retired.
A second red held STS ingress while
presenting an otherwise current external start: `STSIngress.activity/4`
rejected it, but the room kept the STS allocation. A matching end rejection
had the same failure. The room now stops that allocation on either rejected
current boundary. Stale-generation signals are ignored rather than relabeled.
The compiled-room file passes 14/0 on seeds 0 and 1. This is initial room
response timing and fail-closed admission, not provider-late-evidence,
source-time, transfer or full lifecycle acceptance.

The adjacent 93-test room/capability/turn-control group initially failed a
separate 100-ms async-ready assertion on seeds 0 and 1; the method and
separate test-only repair are in `labnotes/20260923-0744-turn-control-ready-wait.md`.
After that bounded test repair, the group passes 93/0 on both seeds. The
independent Astra xhigh review findings follow.

Independent Astra xhigh review reproduced two additional replacement-transition
failures in four bounded probes (external and hybrid for each): a retained
active controller pair blocks a fresh selected-STT generation after a scoped
recording-only interval change, and a delayed stale STT start occupies the
public room turn before activity-origin validation so the fresh start cannot
be admitted. Both led to no fresh reply while caller and agent remained
present. The reviewer found no additional defect in identity, duplicate,
hybrid-onset, hold or ingress-rejection probes, and cleared the separate
five-second ready-wait test repair. These are review findings; the parent
must rerun and formalize their focused reds before changing runtime. The
milestone now breaks them into tasks under the existing B room-control gate.

Parent reran the reviewer's exact in-memory fixture extension from the Call
Engine child: `MIX_ENV=test timeout 40s mix run --no-compile -e
'Code.eval_string(IO.read(:stdio, :eof))'` with the existing
`sts_transcript_modes_test.exs` loaded and an extra `privacy` human participant
whose presence turns `record_audio` off. Four tagged probes run only external/
hybrid × normal/delayed onset. Each obtains the real selected STT origin,
feeds a short real Morse onset, admits `privacy` through
`MediaPolicy.Authority.admit/2`, verifies caller/agent remain present and STT
generation changes, then feeds fresh PCM and completes the STT utterance.
The delayed variant suspends RoomAuthority until the old STT start is queued
and resumes it after the replacement. The parent run finished in 11.3 s with
4/4 expected failures at the two-second sink-output assertion. Diagnostic
state was `pair_present: true` for normal replacement and `false` for delayed
onset in both modes. The probe used bounded source-cutoff retries (up to 100)
instead of sleeps and wrote no files. This is now independently reproduced;
the next step is owning automated regressions before repair.

Formal owning reds now extend the compiled room fixture with the same optional
recording-toggle participant (without changing existing calls). Four generated
external/hybrid × delayed/non-delayed tests use real Morse STT/STS sessions,
`MediaPolicy.Authority.admit/2`, exact generation checks, and explicit process
barriers; the bounded source-cutoff retry uses no sleeps. Running only their
shared source location (`sts_transcript_modes_test.exs:229`) exits 2 with 4/4
expected failures, all at `STS reply did not reach the room sink`, in 9.8 s.
These tests now preserve the review method in the default project test lane;
do not use a broad umbrella run to establish their TDD red state.

Scoped Astra xhigh design review found that clearing only the room
`activity_turn` cannot discard old provider input. Morse marks an accepted
external start dirty even without PCM, and an ordinary `:ended` can prompt an
old reply. A safe replacement requires a closed admission boundary, then either
acknowledged quiescence or retiring the old STS allocation. The conservative
next step is allocation replacement with a fresh ingress/input epoch; source
and recognizer reopening still need coordinated readiness and cutover proof.
The reviewer also noted that the first four reds only primed STT, so the
fixture now sends distinguishable old `NO` PCM to STS before rotation and
requires the fresh `RECEIVED HI` reply afterward.

For public caller turns, `InputTurns` now compares the frozen native allocation
generation and source audio intervals with the selected STT's current origin
before admitting selected external/hybrid signals. Its active-turn association
also includes native generation and turn reference, so a fresh start can
supersede an old unfinished turn even if the transcript interval is unchanged.
The original external/hybrid response tests remain green (2/0). With the
revised four replacement cases, delayed stale-onset variants now pass their
public-turn and reply assertions, while both normal-onset variants remain red
at the missing STS sink reply (2/4 failures, seeds 0 and 1). The old-PCM
fixture uses a bounded ingress-credit acknowledgement loop after a seed-1
scheduling race exposed an in-flight chunk; it does not sleep or widen any
runtime deadline. This is partial P2 evidence, not completed replacement or
full native lifecycle acceptance.
At this intermediate point the active-pair reset/source-reopen repair was still
open; no umbrella gate or room checkpoint commit was run against those reds.

The policy-origin implementation now closes an external/hybrid capability's
ingress before acknowledging a scoped caller audio-input/output interval
rotation, fences output and sends a capability-qualified room notification.
RoomAuthority retires that allocation, retains the old prepared track, waits
for the selected STT's fresh activity origin, starts a new STS allocation and
ingress, prepares that exact track and releases a fresh input epoch. If no
fresh selected origin is ready, it remains closed and retries only on STT
connected evidence. The original source attachment's STS handle resolves the
current registered ingress at push time; no old provider state is reused.
The compiled-room old `NO`/fresh `HI` matrix passes 4/0 on seed 0 and the
whole transcript-mode file passes 18/0 on seed 1.

The adjacent five-file room/capability/turn-control group exposed one prior
capability test that expected same-allocation reuse after source-audio revoke/
regrant. That expectation conflicts with the newly required provider-input
retirement: the capability is now held and notifies its owner instead. The
test now asserts both bounded policy-origin notifications and held admission.
The focused compiled-room matrix now splits fresh STT PCM at onset, injects
a late old-generation end while the fresh pair is active, proves it cannot
close that pair or publish a caller completion, then feeds the remaining PCM.
All four mode/order combinations pass on seeds 0 and 1. An adjacent capability
test also proves an unrelated policy revision preserves the external input
origin and emits no replacement notice. The resulting 98-test focused group
passes on seeds 0 and 1. These checks prove
local compiled-room replacement, not the still-open room-coordinated native
source hold/fence, transfer or Google hosted gates. Independent review is
pending before committing this checkpoint.

First Astra xhigh review reproduced two further transition defects without
edits. With RoomAuthority suspended, it queued a real 640-byte STT onset,
admitted a privacy participant denying audio routes, verified the selected
activity origin became nil, then resumed the room. Both external/hybrid rooms
crashed with `BadMapError` in `InputTurns.current_native_signal?/3`. The
owning two-test red reproduced 2/2 crashes (seed 0); the room now treats a nil
current origin as stale evidence, and those two tests pass. The policy leaves
STS closed and publishes no stale caller start.

The reviewer also admitted a participant setting `save_transcripts: false`
while a pair was active. Selected STT changed native generation but its scoped
audio intervals did not change, so the old STS pair blocked the fresh turn.
The owning two-test red reproduced 2/2 missing replacement allocations (seed
0). External/hybrid STS origin rotation now includes the selected caller STT
transcript interval as well as source audio-input/output intervals. Both tests
pass with a fresh-only `RECEIVED HI` reply; public caller and agent text still
publish through permitted live transcript routes because disabling saved
transcripts alone does not deny those routes. The two reviewed follow-up cases
plus the earlier four room matrix cases pass on seeds 0 and 1. A second
independent review is pending; root gates await a coherent commit.

During the adjacent 102-test group, the transcript-only case once exhausted
its initial 200 immediate `input_binding/1` queries before asynchronous STT
startup completed (seed 1). This was a test observation window, not a runtime
timeout. The fixture now polls the exact STT binding up to the existing
five-second startup budget, leaving runtime deadlines unchanged. The same
five-file group passes 102/0 on seeds 0 and 1. The policy-only case correctly
continues live public transcript publication: `save_transcripts: false` affects
storage, not permitted live transcript routes. Second review remains pending.

Future `bin/teammate` tasks in this milestone should reuse the reviewed
reproduction method: start a compiled Morse external/hybrid room with a selected
human STT; send a short real STT onset and distinguishable old STS PCM; vary
the policy with an unjoined `privacy` participant (`record_audio: false`,
`save_transcripts: false`, or `audio_routes: %{}`); verify native STT origin
generation and scoped interval changes separately; suspend RoomAuthority to
queue pre-change STT evidence; and require a fresh-only reply or a cleanly
closed input as appropriate. Inject an old-generation end only after a fresh
pair starts to test exact retirement. Run focused owning tests first, with
seeds 0 and 1 under the adjacent five-file group; do not use a full umbrella
suite to establish the initial red. Preserve any new failing method as an
automated regression and task before editing runtime behavior.

Second Astra xhigh review reran the four first-review cases and the 102-test
group on seeds 0 and 1 without recurrence, then reproduced another regression
in four in-memory probes (external/hybrid × ordinary/explicit-origin-binding).
It denied audio routes while leaving human transcription permitted, rotated
the STT native generation, and fed fresh Morse `HI`. With normal room binding,
STT ingress retained a stale audio origin after STS retirement, so the provider
never emitted a fresh turn. Explicitly binding the fresh `audio_origin`
isolated the second path: a real `turn_ended` reached suspended RoomAuthority,
but public publication was suppressed because `activity_origin` was nil.
Both seeds 0 and 1 failed 4/4 at the expected missing final transcript.

Two owning compiled-room reds under `sts_transcript_modes_test.exs:441`
reproduced missing permitted human transcription (2/2, seed 0). The fix binds
the selected entry human's current STT `audio_origin` through the planned STS
agent identity even when no STS capability is live. Public STT signal
validation uses that audio origin; only external/hybrid control admission
requires the separately permitted `activity_origin`. The two focused room
tests now pass 2/0 on seed 0, publishing final `HI` while producing no agent
audio. The adjacent five-file room/capability/turn-control group passes 104/0
on seeds 0 and 1 after formatting. A third independent review of this final
transcript/control seam is pending; no hosted service was used.

The compiled replacement matrix now also injects an old-capability policy
notification after the fresh allocation has opened and verifies that the
room retains the new capability. The route-denial test calls the recovery
boundary with the selected activity origin unavailable and verifies that
input remains closed. The six focused transition cases pass 6/0, seed 0;
broader native source-time cutover is still an unchecked milestone gate.
