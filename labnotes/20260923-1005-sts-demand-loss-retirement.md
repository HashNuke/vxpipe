# STS activity demand-loss retirement

Milestone B already requires room-controller retirement when selected human-STT
activity demand disappears mid-turn: closing a recognizer cannot be assumed to
emit a final boundary. The approved room-control design requires fail-closed
retirement of the old external/hybrid pair and no response from a late end.

Current code routes scoped audio-policy changes through the STS capability's
`Input.activity_origin_rotated?/2`, closes its ingress, notifies the room and
has `OriginRecovery` stop the old allocation. Existing room tests covered a
queued old onset when demand disappeared, but did not first establish a live
room controller pair. No runtime edit was made for this checkpoint.

Two compiled-room tests now cover external and hybrid modes. They admit the
selected STT onset, deliver distinguishable old `NO` PCM into STS, require the
room's active controller pair, then deny the audio route while leaving the
recognizer's final end unavailable. They monitor exact old-capability teardown,
require no current activity origin, inject a late old-generation end, and
require no allocation or agent completion/output afterward. This is local
room/policy evidence, not native transport source-time hold/reopen or provider
late-evidence isolation.

The first version passed 2/0 and the 28-test room file passed seeds 0 and 1,
but independent Astra xhigh review reproduced two test false positives, not
runtime defects. First, the synthetic late end hardcoded policy revision 0;
both old caller turns used revision 1. Sending the revision-0 signal *before*
demand loss left the active pair unchanged, while revision 1 closed it and
produced 64,640 bytes decoding to `RECEIVED NO` in both modes. Second, a
controlled direct `STSIngress.activity(ingress, :ended, old_epoch,
old_intervals)` with a 300-ms delayed sink-finish notification delivered the
same old reply while the test's immediate finish/completion refutations still
passed. The reviewer used local in-memory controls with `MIX_ENV=test mix run
--no-compile -e` and `Code.compile_string/2`; no hosted calls. Preserve these
methods for future gate reviews. The proof must capture the real old caller
revision and assert no audio or speech-start after explicit sink/room barriers.
The revised tests capture the active caller turn's policy revision and provider
turn index, compare its native reference/generation with the room pair, and
barrier through the room and sink before refuting frames, finish and public
agent-start/completion events. Both focused cases pass 2/0, seed 0; the
adjacent three-file room group passes 52/0 on seeds 0 and 1. Scoped re-review
confirmed both former false positives are fixed: before demand loss, the new
exact end closes the pair and yields 64,640 bytes of `RECEIVED NO`; under the
300-ms delayed-finish injection, both revised tests now fail on the unexpected
audio frame. Ordinary focused cases pass 2/0. No production retirement defect
was found. Post-commit root format, warnings-as-errors compile, strict Credo
(1,102 files, no issues), unused-lock and socket-backed test gates all exit 0.
The root test run with `PGHOST=/var/run/postgresql` and seed 0 reports 2,671
tests, zero failures, 58 excluded, including Call Engine 1,503/0, Gateway
500/0 and Persistence 186/0. This does not close the remaining milestone
native/hosted/lifecycle/final acceptance gates.
