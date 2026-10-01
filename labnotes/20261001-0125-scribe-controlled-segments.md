# Scribe controlled segment assembly

## Purpose

Implement the recognition assembly boundary for a composed realtime STT adapter.
An acoustic owner supplies the opaque caller turn reference and endpoint. Scribe
recognition segments remain within that turn. This helper does not classify
speech, advertise conversational STT or change shared STS contracts.

Use manual segments capped at 20 seconds of accepted 16 kHz PCM, below the
documented approximate automatic buffer limit. Permit one outstanding commit;
do not feed later audio until it settles. Reject unexpected commits instead of
assigning them by receipt time. The future session owns bounded waiting input,
commit deadlines, transport failure and acoustic evidence.

## Red-green evidence

The first focused test fails because `ScribeTurn.new/1` is absent: one test,
one expected failure, seed 933414. Implement the smallest pure assembly owner;
the same test passes: one test, zero failures, seed 928443. It proves an
intermediate manual segment retains turn identity and the final snapshot waits
for acoustic endpoint plus the later segment settlement.

Add cases for crossing a segment budget with one accepted chunk, replacing
partials within the current segment, bounded input/final text, unsolicited
messages, idempotent endpoint and private inspection before extending behavior.
Record their initial failures and subsequent green result below.

Five tests initially report three expected failures, seed 469914: a crossing
chunk was rejected and replaceable partial handling was absent. Implement
bounded retained remainder and partial assembly; all five pass, seed 196401.
Duplicate-partial suppression first fails in six checks, seed 861441; implement
per-segment partial tracking without changing settled prefix text. The combined
owning turn/codec/socket lane passes eighteen checks including local transport,
seed 848783. Cumulative text is limited to 65,536 bytes, retained crossing input
to one already accepted provider chunk, and duplicate endpoints publish nothing.

## Selected wire evidence

Run only `live_elevenlabs` with
`apps/vxpipe_call_engine/test/integration/elevenlabs_scribe_controlled_segments_test.exs`.
Use the existing runner without inspecting the private configuration file.
Reuse the public fixture's speech portion ten times plus its known two seconds
of silence: 23.6 seconds total, with a hard 25-second input limit. One connection
uses fixed Scribe manual mode. At twenty seconds, request and await one segment
before resuming audio; at the supplied endpoint, settle the remaining segment.
No retries or fixture generation.

One test passes in 24.9 seconds, seed 512880. Exactly two requested segments
settle and exactly one identified cumulative turn end is produced, retaining
the fixture's known word. No segment is received during the pre-commit pacing
phase. Raw transcripts and credentials are not logged. This is ordered manual
recognition assembly evidence with a supplied boundary; it does not test an
acoustic model, natural-speech quality, room admission, empty/no-ack input or
production timing under concurrent input.

## Required next integration

The pure owner yields wire/event actions. Its future supervised session must
execute them, keep later input bounded while a commit is outstanding, and own
a deadline that fails rather than manufactures settlement. Acoustic onset and
end evidence must come from actual accepted PCM classification. Protect turn
identity through resumed speech, permission changes and delayed responses.
Do not advertise conversational STT before these session/room gates pass.

Format and compilation pass. The existing Lean models and replay lane pass
(one replay test, seed 162750); no new formal model of this private recognition
owner is claimed. The default root suite completes successfully for this
implementation: 2,979 tests, zero failures, 92 exclusions, seed 297292. All five
required root gates pass; the new paid case remains excluded from that suite.

Strict Credo passes on 1,168 source files and the unused-dependency check passes.
Documentation links/diff checks pass; the unrelated user documentation-theme
file remains untouched. After the live run, make its final-word assertion use a
boolean and count/reference checks so a failed expectation cannot print actual
recognized text. This mechanical assertion change does not justify repeating
the already passing paid case.

## Checkpoint context

The preceding long VAD experiment is committed and pushed as `014ad27b`, after
all five root gates pass (2,973 tests, zero failures, 91 exclusions, seed 536614).
Those root gates precede this new implementation and do not verify it.
No paid case has been rerun. External reference names/methods remain outside
repository documents, as requested by the user.
