# Google cutover protocol

## Source distinction

The [official Live WebSocket reference](https://ai.google.dev/api/live)
(checked 2026-09-22) describes realtime modalities as concurrent streams whose
cross-stream ordering is not guaranteed. It says input transcription is sent
independently of other server messages, with no guaranteed ordering. By
contrast, the final output transcription precedes generation completion, and
`interactionStatus` is sent with `turnComplete`. The model `IDLE` boundary is
therefore insufficient evidence that an earlier audio caller's final input
transcription has arrived. A synthetic post-`IDLE` model audio frame is not
by itself evidence of a valid Google sequence.

## Reproduction and decision

The focused opted-in controller red sent A PCM, private model content and
`IDLE`, then released the engine epoch and attempted B PCM. It expected
`{:error, :busy}` while A lacked a final, but got `:ok` (1 test, 1 failure).
If B then receives a caller onset, Google's independently delayed A final
could be assigned to B because the final has no origin ID. Require a bounded
audio-final obligation in addition to model-content, caller, tool, response
and playback quiescence. Actual PCM sends set it; a final associated with the
current caller clears it. No onset/final means no audio-origin cutover or
idle renewal, including silence. This is conservative and needs an explicit
product/hosted policy decision before declaring all lifecycle acceptance.

Independent read-only Astra xhigh review reproduced a follow-up local gap:
A1 PCM, A1 activity start/end, A2 PCM before A1's delayed final, then A1
final and model `IDLE` let B cut over. The focused red returned `:ok` for B
where `{:error, :busy}` was expected (1/1 failure). One audio-final boolean
could not distinguish later PCM from the older ended caller. The provider now
sets a second bounded marker when actual PCM is sent after an ended caller.
That caller's final carries the later-audio obligation forward instead of
clearing it. A later caller final clears it, provided the model reaches a
fresh non-ambiguous idle boundary. If the later PCM is only silence, the
provider remains conservatively busy.

The tests now exercise A audio with no observed final (B blocked), A's final
arriving after model `IDLE` (private settlement releases B without replay),
fully finalized A audio to B audio/text, and completed external A activity to
B activity. After a held epoch changes, the late A final is retired privately,
not published under the new origin. The Google/provider/shared-speech group
passed 276 tests, 0 failures for the initial fix. After the A1/A2 follow-up,
the controller suite passes 76 tests and the Google/provider/shared group
passes 278 tests, both with zero failures. Before the follow-up, the full
call-engine child suite passed 1,407 tests, 0 failures, with 30 integration
exclusions. The post-follow-up full child run executed 1,409 tests with one
unrelated `LiveInspectionTest` failure; a focused rerun reproduced that test's
pre-existing invalid participant-readiness assumption. It is tracked as a
separate root-gate repair, not a Google cutover failure. Independent Astra
xhigh follow-up found no new concrete cutover issue (two A1/A2 tests and
the 76-test controller file green). Root gates remain pending.
