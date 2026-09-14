# Initial wait acceptance

## Remaining startup behavior

The previous release checkpoint recorded a fast-start gap: output preparation can finish after the
initial resource graph is ready, so setup skips creating a wait player. If final release subsequently
finds pending readiness, the stopped wait is never reconsidered. Reproduce this with the real room:
hold only the embedded output-preparation callback, let room preparation finish, then delay the next
connection readiness acknowledgement. This fixture hook is opt-in; its normal tracks, codecs and
speech preparation remain unchanged. No native/browser or live-provider behavior is inferred from
that precise race fixture. Native configuration acceptance follows separately.

The focused test fails at the expected missing private wait frame after the late readiness check
(`vxpipe-initial-wait-red.log`). Reconsider stopped waits through the existing start/no-sound
selection whenever startup reconciles. Paused players retain their existing resume path and cursor;
explicit nil still resolves to no player. No provider, policy, deadline or admission behavior changes.

The focused late-wait regression passes (`vxpipe-initial-wait-green.log`). Native configuration
acceptance then passes ten cases (`vxpipe-initial-wait-native.log`): default/custom/per-slot nil/
whole-object nil startup; independently ready STT/TTS and a preparing room recording writer; held
microphone input absent from STT/recordings; later conversation reaching both; one fixed greeting
despite repeated client-ready; and file/text opening priority followed by waiting with model setup
still blocked. Opening text stays out of the first admitted model request. Existing engine tests
retain exact PCM cursor, private opening/recording isolation, generated greeting and lifecycle
evidence. Custom URLs use the controlled fetcher, not a live network download.

## Required phone cleanup

Phone acceptance uncovered incoming legs remaining open after room failure. The reproduced failure,
engine monitor boundary, pinned-service cleanup and 18 passing phone checks are recorded in the
[incoming-leg labnote](20260915-0121-incoming-leg-lifetime.md). This is committed separately from
wait selection and native acceptance because it owns the incoming provider leg's lifetime.

## Final verification

The first complete root run passes all five gates: 1,362 tests, zero failures, 15 exclusions,
seed 652745 at concurrency four (`vxpipe-initial-wait-gates-*`). A later focused rerun after
moving case selection into ExUnit tags exposed a synchronization error in the new greeting-history
assertion. It admitted another caller turn after hearing greeting audio but before actual greeting
playout completed. The history assertion then legitimately saw an interrupted greeting. Wait for
the existing RTVI `bot-stopped-speaking` completion event before making that next request; do not
add a sleep or alter greeting/history behavior. All ten native cases pass after that correction
(`vxpipe-initial-wait-native-completion.log`). The final root run after that correction passes all
five gates: format, compile with warnings as errors, strict Credo, tests and unused dependency
checking (`vxpipe-initial-wait-completion-gates-*`). Tests run with `--max-cases 4`, seed 307676:
1,362 tests, zero failures and 15 exclusions. Application counts are MCP 37, agent runtime 91,
engine 625, Calls 81, Gateway 366, artifacts 19, persistence 49 and Console 94. This adds two
engine checks and 23 Gateway checks over the previous checkpoint.
No development server restart or UI changes. Preserve the other agent's
documentation-site and visual-labnote work.


## Design review and milestone reconciliation

Accept the initial caller-waiting slice using native WebRTC configuration/audio checks, exact
engine ordering/isolation checks, and deterministic incoming phone lifecycle checks. Keep live
URL retrieval and physical carrier audibility in their existing human/phone transfer acceptance
tasks; controlled fetches and adapter submissions do not establish those outcomes. This changes
acceptance evidence, not the approved call definition or provider readiness contract.

The initial slice has no remaining tasks. The milestone retains 24 tasks: human web handoff 7,
AI handoff 3, phone handoff parity 6, changing/multiple listeners 6 and final audit 2. The 13 open
acceptance/summary boxes elsewhere overlap those tasks. Keep the full milestone index unchecked.
Separate the phone-lifetime fix and initial-wait acceptance into coherent checkpoints, each with
its own implementation, tests and notes. The four transfer slices remain unfinished.
