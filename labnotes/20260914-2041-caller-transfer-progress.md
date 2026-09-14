# Caller transfer progress

- Previous checkpoint `ebdf61a` committed AI waiting/readiness/cue/recovery. The other agent's
  docs-site and visual labnotes remain untouched.
- The caller projection was missing: engine progress targeted only the private destination, and
  only the desk channel encoded it. The caller SDK already supports RTVI server-message extensions.
- Added `vxpipe.transfer` v1 using that envelope, with only attempt ID, definition-local destination,
  closed phase/blocker categories and elapsed milliseconds. The owning authority publishes initial
  preparation, actual readiness/cue/release, recovery and terminal states. The desk wire format
  stays compatible. No core RTVI type or provider payload is exposed.
- Extended the ordinary native WebRTC AI case to require a delayed-TTS blocker and completion;
  existing human/AI recovery variants now require recovered status. The valid red timed out on the
  missing caller server message (`vxpipe-caller-transfer-progress-red-valid.log`). A preceding
  test-helper guard compilation error was corrected before that behavioral red. All 18 existing
  WebRTC transfer cases passed after implementation (`vxpipe-caller-transfer-webrtc-all.log`).
- UI detour: drafted and checked caller title/error changes, including 13 frontend checks and a
  bounded rendered desktop/mobile pass using real components with controlled callbacks. The user
  clarified that this milestone should primarily use native WebRTC testing and avoid UI changes.
  Removed all three uncommitted frontend edits and their added tests. Only the protocol projection
  remains. The UI work and its checks do not describe the final implementation.
- The live browser's pre-transfer connection failures remain unexplained; no causal conclusion was
  established. Closed that session and stopped browser-driven provider debugging. The separate
  native Morse checkpoint records the actual audio boundary defect found without a browser.
- All five root gates pass on the combined protocol/native-audio worktree: format, ordinary
  warnings-as-errors compile, strict Credo, unused-lock check, and 1,303 tests with zero failures
  and 15 exclusions at concurrency four, seed 355428. Logs use the
  `vxpipe-native-checkpoints-final-` prefix. Earlier phase-loss failures and their unreproduced
  cause remain recorded in the native-audio labnote; this does not complete milestone acceptance.
