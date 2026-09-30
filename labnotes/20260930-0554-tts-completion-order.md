# TTS completion ordering

## Observed failure

The full umbrella run with seed 412687 exposed Deepgram's second phrase returning
`:busy` after generation completion, consumer ACK and playback settlement. The
channel still held the earlier input worker command: provider events can outrun
the worker's asynchronous callback-result cast.

## Red, green and rejected approach

- A supervised completion probe emits submitted PCM and completion, then holds
  the speak callback until an explicit message. Three focused tests failed on
  the original implementation because playback settlement returned `:ok` while
  callback success/failure/expiry remained unresolved.
- The first attempted fix delayed terminal delivery. Its focused tests passed,
  but the shared speech suite found two failures in terminal usage survival and
  pre-delivery promotion. That approach was removed completely: terminal evidence
  must retain its existing independent delivery contract.
- Settlement now validates completed output, retains its caller and the settled
  playback state on the matching input command, and waits for that command's
  result. Existing input failure/deadline handling also replies to this caller.
  No input timer is extended, result is discarded, or sleep added.
- Successful input completion installs settled output before replying, so the
  next phrase is admissible. Explicit failure and the original deadline both
  fail settlement and close the allocation.

## Verification

- Revised regression: 3 expected red failures, then green.
- Completion, usage survival and Deepgram session suite: 28 tests, zero failures.
- Shared speech, opening-audio and Deepgram session suite with seed 412687:
  318 tests, zero failures (4 excluded).
- Root format, compile with warnings as errors, strict Credo and unused-lockfile
  checks pass. `bin/verify-lean` builds, checks oracle drift and passes its replay.
  The Lean lane covers its existing modeled transitions; the new callback-order
  branches are covered by the deterministic Elixir tests.

## Additional suite findings

- Opening-audio's terminal telemetry refutation accidentally matched an unrelated
  room's 30-second startup timeout. Capture the emitter only in test metadata,
  scope duplicate checks to the expected lifecycle PID, and stop rooms created
  by that file in `on_exit`. Production telemetry remains unchanged.
- The full suite's WebRTC reconnection tone failure passed in isolation with the
  same seed (one test, 167.6 seconds); no cause or runtime repair is claimed.
- The next full run exposed an STT test reading the capability's session before
  its asynchronous replacement-start result. Use the observed fake transport's
  owner for the existing initialization acknowledgement, matching other tests
  in that file. A subsequent root run revealed that the test also left the denied
  allocation's transport-start notification unread. Consume it before restoration
  and assert that the replacement is distinct. This explains the stale/dead PID
  seen in the root run; it is not a provider runtime failure. Its 23-test file
  passes with seed 412687. One unrelated probe-start acknowledgement now allows
  a bounded second instead of the default 100ms under concurrent suite load.
  Final umbrella evidence remains pending.

The provider milestone remains incomplete. No new live API calls were made for
this race repair, and the private credentials file was not read or modified.

## Final current-checkpoint evidence

The same-seed root rerun passes all 1683 CallEngine tests after the STT fixture
correction. Across the umbrella it reports 2885 tests, with one remaining failure
in Gateway's `after_speech_adoption` preparation case while waiting for another
progress notification. The same-seed selected case passes one test in 161.3
seconds (67 excluded); this does not establish its cause or a repair. Root
format, compile, strict Credo and unused-lock checks still pass, and the earlier
Lean result covers the unchanged TTS runtime checkpoint. Full acceptance remains
open instead of being inferred from passing focused reruns.
