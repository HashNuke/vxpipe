# Participant diagnostic workload

Artifact names below refer to the host temporary directory, not repository paths.

## Change

Added `--inputs-per-room 1|2` to the bounded smoke runner, with at most 16 human
STT inputs in total. The two-human room uses the existing configured caller and
a declared guest joined through the normal CallEngine participant command. Both
attach independent STT streams; they share the room's response agent. Completions
are keyed by room and source participant, never by room alone. Input text and PCM
fingerprints distinguish sources. The revised fixed-window profile sends 192 frames per input and completes
two canonical turns, with one participant-owned diagnostic run and two rows when
collection is enabled; disabled collection creates no runs.

The fixture's optional scoped audit mode records the receiving connection while
preserving original event forwarding. Each participant's own six-event turn trace
is checked separately. Transcript and agent-text copies delivered to the other
human must match exactly and in order. No unexpected public events may remain.
Stored turn IDs must equal that participant's canonical completion IDs, not just
match a row count. The original single-room audit mode remains unchanged.

## Initial synthetic schedule — superseded below

The original simultaneous provider settlements put human onsets only about 16 ms
apart. The first human's response could still be running when the second began.
The bounded interruption probe explicitly observed input 0 being interrupted by
input 1; this was normal room behavior, not a diagnostic runtime defect.

Provider settlements now use fixed 32-frame windows. Slots spread rooms across
the window and place the two humans in each room 16 frames apart. There are still
two settlements per input in the 64-frame smoke. They depend on frame position,
never on response acknowledgements. The actual emitted frame/turn pairs are
recorded and checked against the pure schedule; output reports those observations.
An initial missed receive-loop replacement left old 32/64 emissions behind while
metadata described the new schedule. That invalid attempt is retained, and the
observed-versus-declared assertion prevents repeating that reporting mistake.

A subsequent strict trace check found a real trailing ParticipantTurnStarted:
operational Silero detected speech after an early source's final settlement while
its PCM continued. The single-case probe records two complete six-event turns
followed by that start. The synthetic generator now fills only frames strictly
after each source's final declared settlement with silence; it retains every
frame, source marker and deadline. The manifest records settlement frames and
`silence-after-last-settlement`, and the Elixir fixture independently verifies
those phases. Marker-only silence cannot satisfy native speech-bearing inference
proof. The original one-input 64-frame audio is byte-for-byte unchanged, since its
last settlement is 64. No operational VAD, provider configuration or call-control
behavior changed. This is a declared synthetic load fixture, not acoustic-accuracy
ground truth or acceptance of overlapping/interrupted live conversations.

## Initial 64-frame red-green and review evidence — historical

- Initial two-human run failed all four cases because the old fixture declared
  only one human (`vxpipe-two-human-workload-red/`).
- Scoped audit tests started red and now verify both original and scoped event
  forwarding. Schedule tests started red and verify exactly two settlements,
  distinct phases and same-room half-window separation across supported shapes.
- Astra reproduced reordered peer copies and swapped canonical turn IDs passing
  the old count/selective-receive assertions. Permanent tests against the actual
  helpers failed for both gaps before the fixes
  (`vxpipe-participant-oracles-red.log`). The focused helper selection now
  passes 3/3; schedule/audit tests pass 4/4. Independent reviewer controls pass 5/5.
- Python tests pass 34/34, including topology/frame evidence, exact silence-tail
  boundaries, unchanged one-input bytes and invalid settlement shapes.
- Independent review checked actual receive-loop scheduling and generator PCM,
  phases, markers and all deadlines across all 24 allowed room/input shapes.
  Reintroducing the old receive branch fails the schedule controls. These are
  fixture checks, not native performance acceptance for all 24 shapes.
- An overbroad `--include test` selection was stopped once recognized; it supplies
  no acceptance evidence. The corrected focused selections above were run instead.
- Root format, warnings-as-errors compile, strict Credo and unused-dependency
  checks passed before the final native runs. Full-suite execution remains deferred.

## Initial retained attempts — historical

`vxpipe-two-human-workload-first/` exposed legitimate peer text copies and one
incomplete response. `vxpipe-two-human-workload-projections/` narrowed that
response failure to one completed turn despite all 64 provider frames. The explicit
interruption probe confirmed the cause. `vxpipe-two-human-workload-staggered/`
retains the unwired-schedule attempt. `vxpipe-two-human-workload-wired/` exposed
trailing onset, and `vxpipe-two-human-tail-onset-probe/` identifies its exact
13-event trace. None is passing acceptance evidence.

Earlier one-room/two-human evidence at
`vxpipe-two-human-workload-tail-silence/` passes 4/4, with committed rows and
no abort, cleanup errors or retained databases. This single topology does not
accept the pending checkpoint: the two-room case fails as recorded below.

Full warm/cold paired duration, coverage, latency budgets and acoustic accuracy
remain open. No live provider/Telnyx calls or production deployment occurred.

## Two-room acceptance failure — 2026-11-19

Recovered the existing terminal run at
`vxpipe-two-human-workload-two-rooms/`; its process handle was gone and its
report records exit 2, three successful cases and one failure. Operational Silero
with collection enabled persisted one row rather than two for an input. All
owned scratch databases were dropped; there was no watchdog abort or cleanup error.
At that point the checkpoint remained unaccepted and uncommitted.

A bounded diagnostic run at `vxpipe-two-human-missing-row-probe/` reproduced
that failure. Temporary failure-only output identifies input 0: its first canonical
turn is missing, while the second canonical ID is persisted. This rules out a
simple count mismatch between participants. The source's first scheduled provider
settlement is frame 8 (about 224 ms). RoomService's asynchronous attachment and
250 ms reconciliation are a plausible startup explanation, not yet proved by
attachment-time evidence. A run anchor can predate actual subscription and is not
sufficient to prove that attachment was ready.

A subsequent exact `external_case:true/true` probe at
`vxpipe-two-human-startup-anchor-probe/` failed earlier with input 0's response
interrupted by input 1 (one selected test). The generator's broken pipe followed
that assertion and test teardown. Its overall four-case smoke report is necessarily
incomplete. This shows that separating provider settlements by half a window is
not sufficient to exclude acoustic interruptions: the generator still feeds the
same speech waveform to both humans before their final silence tails. The
assertion remains strict. Temporary verbose event output was removed after the
investigation.

The investigation identified that subsequent work must distinguish attachment startup from subsequent coverage loss and
make synthetic participant speech windows consistent with the intended sequential
conversation. Do not change operational turn acceptance, suppress interruption
messages, claim missing rows are acceptable, or retry until a pass. Preserve cold
startup gaps as separate acceptance evidence; a primed functional fixture would
need explicit setup provenance and would not prove cold coverage. The original
single-input regression and final Astra artifact approval were still pending. No full
suite, live provider call, or deployment ran during this investigation.

## Fixed participant speech windows — 2026-11-19

Replaced the continuous shared waveform with declared, non-overlapping per-human
speech windows. The fixed schedule is now 192 frames (6.144 seconds) per input:
first settlement = 64 + floor(64 × (slot + 1) / total inputs), second = first + 64,
where slot = human index × room count + room index. Each settlement ends a
32-frame replay of the original fixture's first 16,384 samples. Silence fills all
other frames, then the usual source marker is applied. The manifest pins the
clip offset/length/hash and transformation. Sample epochs, sequence continuity,
source-specific PCM accounting and exact public/row identity assertions stay intact.

The leading silence is an explicit functional-smoke priming period (at least 36
frames), identical across all modes. It does not prove cold startup coverage or
resolve the old missing-first-row mechanism. Adjacent same-room speech windows
have no guaranteed response-completion gap; an interruption remains a failure.
No readiness/response acknowledgement delays the external generator. Operational
VAD, provider configuration and dispatch behavior were not changed.

Astra caught an arithmetic error in the initial proposed formula before it was
used: multiplying slots by 32 would leave 16-frame overlaps. The corrected factor
64 gives 32-frame same-room separation. Python tests check exact PCM bytes, clip
hash, source markers, every deadline, no overlap, leading/trailing silence and
exact counts across all 24 allowed topologies. The new contracts failed against
the old generator/runner (6 failures) and old Elixir schedule (2 failures), then
passed: Python 33/33 and schedule/audit 4/4. A separate clip-manifest assertion
failed before the metadata was added. The original unprofiled generator retains
its wrap/pacing tests. Native and final review evidence follows when available.

## Final-profile verification

The revised two-room/two-human run at
`vxpipe-two-human-speech-windows/` passes all four operational-VAD/collection
combinations. Each case delivered 768 frames across four inputs with exact two-turn
public traces, participant-specific canonical row IDs and independently visible
committed rows. Observed settlement pairs were 80/144, 112/176, 96/160 and 128/192.
The report has 507 samples over 51.73 seconds, peak VM RSS 854,016 KiB and minimum
host available memory 2,576,700 KiB. Generator p95 lateness was 90,538 / 239,357 /
302,584 / 329,464 ns. All four owned databases were dropped; no watchdog abort,
cleanup error or retained database occurred. These are functional/resource-watchdog
results, not paired CPU/RSS regression acceptance or complete inference coverage.

Root format, warnings-as-errors compile, strict Credo and unused-dependency checks
passed for the revised profile. The focused trace-oracle rerun exposed an invalid
mock: an unexpected-room event was a plain map, causing the assertion formatter to
raise KeyError instead of the expected assertion failure. Replacing only that mock
with an actual ParticipantTurnStarted struct preserves the wrong-room stimulus;
the focused selection passes 3/3. This test-only edit occurred after the two-room
artifact's source hash; its selected native workload is unchanged. Evidence is in
`vxpipe-participant-windows-oracles.log` and the corresponding `-green.log`.

The final single-input regression at
`vxpipe-participant-windows-single-regression/` also passes 4/4 with the same
192-frame profile, both expected canonical rows when enabled and no rows when off.
All owned databases were dropped with no abort, cleanup errors or retained names.
Independent Astra review verified the corrected generator across all 24 shapes,
the actual Elixir receive-loop schedule, exact raw lateness p95 and the two-room
resource/cleanup evidence. Final Astra source/docs/artifact review is clean with no remaining findings.
The single-input artifact hashes match final source; the two-room difference is
exactly the documented, unselected test-fixture correction. Independent checks
pass Python 33/33, assertion controls 5/5, fixture tests 4/4 and receive-loop
probes 2/2. Single-input p95 lateness was 72,009 / 330,138 / 72,169 / 187,973 ns;
491 samples over 50.03 seconds recorded peak RSS 900,476 KiB and minimum host
available memory 2,490,188 KiB. The participant functional checkpoint is accepted;
full paired performance, cold coverage and acoustic accuracy remain open.
