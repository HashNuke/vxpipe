# Duplex STS opening

Continued the active outgoing-call/live-telephony goal after native turn STS acceptance.
No credential-file inspection, purchase, hosted speech request, or carrier call occurred.
Fresh read-only `bin/livetests telephony:status` found both machine numbers and the
Telnyx application/profile. Test node status remained stopped. Sent a pushnotify update.

## Morse duplex

- Extended outgoing room tests to both Morse models, generated `HELLO` and exact `GOOD DAY`.
  Tests decode actual credited PCM after the callee media gate, require agent-only evidence,
  and reject duplicate answer playback.
- An initial 10 ms fixture violated Morse's minimum unit duration; corrected to 20 ms before
  implementation. That first failure is not the behavior red.
- Valid red: 28 room tests, two duplex failures (`first_message_unavailable`), seed 471832.
  Temporary log `vxpipe-duplex-opening-room-red-valid.log`.
- Native opening queues exact encoded text through the existing timeline/reply flow and
  records locally measured command submission without creating a caller turn or reply prefix.
- Green: 28 room tests, zero failures, seed 849310.
  Temporary log `vxpipe-duplex-opening-room-green.log`.

## GPT-Live

- Reused the prior official greeting research: trusted `session.instructions.append`, real
  silence input continues the duplex timeline, and an instruction acknowledgment is not
  exact speech or playback proof. Commentary paraphrases and is unsuitable for fixed text.
- Generated opening red: unsupported operation, 22 tests/one failure, seed 355433.
  Temporary log `vxpipe-gpt-opening-red.log`.
- First attempted submission event was invalid: this adapter reports provider usage, so the
  shared event schema rejects locally measured `input_submitted`. Removed that claim without
  weakening the schema. The input slot records local command acceptance; only actual output
  can announce a response. Generated green: 22 tests, zero failures, seed 813055.
  Temporary log `vxpipe-gpt-opening-generated-green2.log`.
- Fixed red: unsupported operation, 24 tests/two failures, seed 66834.
  Temporary log `vxpipe-gpt-opening-fixed-red.log`. Fixed green: 24/zero, seed 952853.
  Temporary log `vxpipe-gpt-opening-fixed-green.log`.
- Fixed output stays private until one acoustic burst closes and its aligned transcript
  equals the requested text. Its private segmenter admission only permits collection;
  it grants no Channel/room playback authority. Verify transcript end against captured PCM
  duration, reject missing/altered/unmatched text, then announce under ordinary room admission.
- Bounds: 2 MiB total received PCM, 4,096 transcript fragments, requested-text byte limit,
  30-second fenced deadline, at most sixteen 128 KiB playback chunks. Coalescing prevents a
  long verified clip from exhausting ordinary audio/event queue slots. The ordinary 96 KiB
  streaming queue is unchanged. Three seconds of actual PCM is covered by the focused test.
- Lifecycle red: caller speech escaped, deadline ignored, and private burst idle not scheduled:
  27 tests/three failures, seed 91432.
  Temporary log `vxpipe-gpt-opening-lifecycle-red.log`. Green: 27/zero, seed 586423.
  Temporary log `vxpipe-gpt-opening-lifecycle-green.log`.
- Pending fixed output fails without release/reseed on caller speech, hold, provider loss,
  or deadline. Stale deadlines are ignored. Delegation is also rejected during verification.
  Late transcript additions to the verified burst fail rather than changing its exact text.
- Origin red: subsequent real silence rebound the opening to a newer context, 28/one failure,
  seed 568071, temporary log `vxpipe-gpt-opening-origin-red.log`. Retain the admitted opening context through the
  first actual burst, restoring the ordinary latest-input context afterward. Green: 28/zero,
  seed 387445, temporary log `vxpipe-gpt-opening-origin-green.log`.
- Moved idle scheduling to output ownership and opening interruption filtering to opening
  ownership. First strict Credo identified one handler complexity violation; fixed by extracting
  filtering, with the lifecycle semantics preserved. No new dependency.

## Verification complete

Initial root formatting, warnings-as-errors compilation, and unused-dependency checks passed.
Focused duplex regression passes: 161 tests, zero failures, seed 546518,
temporary log `vxpipe-duplex-focused.log`. Strict Credo after refactor passes (1,196 source files,
no issues), temporary log `vxpipe-duplex-credo2.log`. Lean build/oracle/replay passes: one replay
test, zero failures, seed 145929, temporary log `vxpipe-duplex-lean.log`.
Final root formatting and warnings-as-errors compilation passed. Full umbrella tests passed:
3,143 tests, zero failures, 98 excluded, seed 949782 across nine applications, temporary
log `vxpipe-duplex-root-test.log`. All five root gates and Lean pass. Checked 155 local
link targets in five relevant documents and `git diff --check`. D3 is accepted; the full
milestone and all E carrier gates remain open. No hosted GPT-Live evidence is claimed.
After the acceptance/index updates, the final documentation pass checked 158 local link
targets and the diff check passed again. Final tools status is stopped. Sent pushnotify.

The provider has no finite response-completion event: fixed verification uses the already
approved energy-gap acoustic boundary. Provider transcript evidence is not independent speech
recognition; missing or delayed unalignable text fails closed. The existing 2,000-byte trusted
instruction limit can reject a long fixed cue before sending it. Live proof remains separate.
