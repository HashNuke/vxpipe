# Implement caller recovery

## Carrier exit

Ran checkout setup. The configured gateway test first failed waiting for a carrier command after disconnecting the Scribe transport on an answered Telnyx call. Added the exact-binding handoff to the original leg and packaged a 3.15 s mono 8 kHz PCM WAV. The Telnyx playback command sends the WAV inline to the caller. The recording is generated with FFmpeg's flite filter using the slt voice and the phrase “We have lost the audio connection. Please call back.”

The test then observed playback followed by hangup after a matching signed callback. A second red test killed the media process outright. Monitoring the exact registered media generation made that case pass. A third path disconnects recognition with storage unavailable. Verified caller-initiated hangup, missing completion, mismatched/duplicate callbacks, and the production adapter's payload in the gateway suite.

The journal test initially failed at the missing Calls boundary; it now exercises PostgreSQL, rejects another incarnation, and retains the first event deadline on retry. A terminal event can update the stored leg to ended. Missing storage evidence remains queued with the live owner. A separate recovery lookup test verifies scope, all carrier identities and the retained deadline. Signed HTTP replay with no live owner verifies against the pinned Telnyx credential before writing terminal evidence. Both persistence and gateway focused suites passed. Live handset outcomes remain open.

An exact-media failure signal is queued to the leg owner. A regression test
suspends the owner while closing the recognizer and confirms that teardown can
finish before the owner resumes and requests playback. Nine scoped gateway
cases passed. An additional configured French-language call exposed delivery
of the English recording. The activation filter now checks the pinned language,
using English for the QA default where no language was specified.

The live harness discovers the machine's two Telnyx test numbers. No personal
number is needed for automated carrier interoperability. A controlled listener
is still needed to attest to the words heard and the length of perceived silence.
This checkpoint implements callback-and-end. Transfer and recognizer replacement
remain separate milestone checkpoints.

The broader suite caught a source hold/arm path without a carrier binding.
Recovery now requires an explicit eligible binding before inspecting the
attachment. The hold/arm regression and French-language case passed together.

Release verification passed on the staged implementation: umbrella format,
warnings-as-errors compilation, strict Credo, unused dependency check, Lean
build and oracle replay, and all ten default umbrella test suites. Gateway
reported 916 tests with zero failures. Live carrier and handset checks run
separately.

Shared QA deployed revision `043a3845`; its migration and HTTP health check
passed. A subsequent configured-room test plays the agent's gardening response
through Telnyx media, injects a commercial-property partial on Scribe, observes
a caller-stream clear, and disconnects the recognizer before its final. A
matching carrier completion advances to hangup. Killing the playback observer
while its simulated HTTP request remains in flight exposed premature hangup.
The leg now retains its existing deadline and accepts signed completion.
Killing a hangup observer after submission permits one same-leg retry and
retains uncertain drainage after a signed terminal event. The focused gateway
recovery selection passed 13 tests.

The live carrier runner found the machine's Telnyx application but neither QA
number. Non-purchasing provisioning reported the tagged number pool exhausted.
The new tagged live test has not placed a call. It uses a synthetic recognizer
transport inside a carrier-to-carrier call and checks for signed playback and
termination. This requires a separate handset listening result.

The live retry reached three healthy Funnel relays and dialed. The Scribe test
transport did not signal startup before the test deadline. The number-switch
journal returned both QA numbers. Callback audibility remains unconfirmed.

For checkpoint C, the conversational recognizer now emits operational Silero
boundaries to its allocation consumer. The first admitted PCM in a recognition
epoch anchors the 16 kHz sample offsets in monotonic milliseconds. A focused
regression initially received no offset. With the change, the probe receives
onset, offset and resumed onset on one canonical turn with no transcript.
The capability now schedules a 4 s absolute deadline from the acoustic offset
on a current open turn. A resumed onset cancels the original timer; a valid
final cancels a queued expiry. Silence after resume arms a fresh timeout.
An additional regression exposed the old orphan timer ending an utterance
during sustained speech; it now starts on confirmed offset for that case.
Across three focused STT files 41 tests passed. The room-level response to
the stall, allocation cutover and caller-only playout remain pending.

The confirmed-offset and confirmed-provider-loss paths now share one
caller-specific recovery attempt. The room checks the current capability,
connection and allocation, asks the original media owner to clear its output,
then checks the stall again when retiring the recognizer. A final or resumed
speech received before retirement cancels replacement. A fresh allocation
uses the pinned recognizer configuration and a fresh usage attempt. The
gateway plays two finite PCM recordings through only the original output.
Room hold or a private-output owner fences conversation playback.

A configured Telnyx harness call held the commercial-property partial, forced
the acoustic watchdog deadline, observed both playouts finish, delivered the
repeated question to fresh Scribe, and observed an agent request. Separate
cases reached callback playback and hangup on readiness timeout, no repeat,
and a second provider failure. The confirmed first provider failure case
also recovered without requiring a local acoustic offset. The 46-case
configured carrier harness passed. Including media-session, output-arbiter
and recovery-asset tests gave 88 passing tests. These use an in-process
carrier and controlled recognition; they do not establish handset audibility.

Source evidence now includes the allocation, actual input epoch, ordered
boundary sequence, sample index and rate, and a monotonic capture anchor.
Epoch changes cancel the old timer and invalidate outstanding detector work.
The focused epoch suite passed 21 tests and the gateway harness passed 47.
A stale playout request exposed a missing media-owner check. The media owner
now grants hearing and repeat playout in order for one cleared output
generation, and withdraws that grant on hold. The media-session and harness
selection passed 58 tests. A separate no-repeat test initially failed during
synthetic socket setup. It now supplies the signed terminal event after the
fallback hangup; four consecutive focused phase runs passed.

Call details now project recovery events onto the affected participant. Five
persistence tests passed. The editor validation suite passed 91 tests. In
Chrome the JSON editor rejected an unavailable transfer destination at desktop
and handset widths. Formatting, compilation with warnings as errors, strict
Credo, the unused dependency check and the Lean oracle passed. The live Telnyx
trial reached dialing but timed out waiting for the receiving recognizer. Both
borrowed numbers were restored. Handset audibility remains unverified.

The first umbrella pass caught three failures in diagnostic inference reuse.
Frames lacking a capture timestamp now use local monotonic receipt time, and
the first source binding preserves the initial detector epoch. All 25 speech
tests passed after the correction. A separate regression test delivered a
playback mark before the corresponding finish reply and reproduced a lost
completion. The player now waits for both messages in either order. All 14
player tests passed, including the reordered mark. The configured commercial
question also passed four consecutive runs in isolation.

The corrected call-engine suite passed 2,937 tests. The preceding umbrella
pass reported zero failures in the gateway (942), persistence (586) and
console (677). The existing QA release image was retained locally for the
rollback exercise.
