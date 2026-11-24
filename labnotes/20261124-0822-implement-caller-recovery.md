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

QA deployment of runtime revision `9e320582` passed after the complete
umbrella run (6,560 reported tests, 432 excluded, zero failures). The running
container label matched the commit, migration 20261124091700 completed, and
the public health endpoint returned HTTP 200. A read-only instance of the
previous release opened the migrated QA database and read the published
revision relationship. A live traffic rollback and handset acceptance remain
open. The Telnyx pool planner found zero eligible Rocksalt numbers after the
app rename; no numbers were moved during this deployment.

The two active numbers on the Rocksalt QA application carrying both legacy
test tags received the machine and test eligibility tags. The migration
preserved their prior tags and routing. The planner then identified two
eligible QA numbers. Two live test windows each borrowed and restored both
numbers. The final plan confirmed both back on the QA application.

The first trial reproduced the receiving Scribe startup timeout. The live
room takes its speech transport override through call admission. Supplying
the fake transport on that per-call path made the next trial pass. All three
public relays returned 200, the outgoing leg transcribed the greeting,
one replacement Scribe started after the injected disconnect, and its loss
triggered a signed Telnyx playback completion and terminal leg record. Both
rooms ended. Automated carrier test: one passed. This trial did not measure
handset audibility. A separate configured-room control finalized “Okay,”
delivered the retired acoustic-offset timeout and verified the same
recognizer remained eligible with no fallback.

The previous release image starts cold without the recovery destination atom.
A stored policy from the new release could therefore fail its safe term
decoder. A focused regression reproduced the missing historical field.
The codec now omits the unset optional field and encodes configured values
under a string key, normalizing all three historical formats on read. Six
codec tests passed. A cold instance of the actual prior QA image decoded
both an unconfigured plan and a configured plan written by the corrected
codec, preserving the pinned revision and original transfer timeout.

Handset trial at 10:52 UTC on revision 12 with operational VAD enabled:
the caller interrupted the agent to ask about gardening. The room recorded
the interruption at 10:52:37.885 and a missing-final recovery at 10:52:42.619
(4,000 ms from acoustic offset). It requested the hearing cue and selected
carrier exit 12 ms after recovery started. The caller heard only the full
callback message. The archive closed at 10:52:46.613. Logs show an
unavailable STT audio delivery on frame 1279 and media teardown. Existing
phase facts do not identify which transition first selected carrier exit.
This verifies the announced-disconnect handset case. In-room recovery
and the repeat prompt still require a successful handset trial.

The handset call and carrier leg both reached ended. Its journal contains
announcement request and completion, hangup request, and signed carrier end.

With the replacement channel deliberately unavailable during preparation,
a fresh inbound frame blocked the capability. The corrected path drops that
frame before provider submission. A second regression returned a failed
input submission from an active test provider; eligible ingress now drops
the failed frame while the room handles that failure. Other calls retain
their terminal behavior. The room archives the failed phase and a bounded
exit reason. Both focused regressions passed. A real two-number Telnyx call
then transcribed “repeat” on the far leg, followed by signed carrier exit
after the second injected failure. The runner restored both QA numbers.
The receiving Scribe transport was controlled; handset recovery with live
Scribe is still open.

One existing QA call written by the initial recovery release contains the
atom field. Its data remains intact. Use revision 9e320582 or a compatible
build when rolling back over that history. Cold 043a3845 lacks that atom.

Final focused validation passed 26 recognizer and recovery tests, 48 gateway
harness tests and six persisted-plan tests. Formatting, strict Credo,
warnings-as-errors compilation, unused dependency checks and the Lean lane
passed. The far-end repeat test used a real Telnyx call and a controlled
receiving recognizer.

The separate live ElevenLabs + Telnyx trial enabled operational VAD and
used the live encrypted Scribe credential. The first injection correctly
failed the allocation owner check, before disrupting the recognizer. The
verified test stops only its own real Scribe socket after the far end
transcribes the initial greeting. Call details then recorded a different
ready recognizer on the same connection, and the remote leg transcribed the
repeat prompt. The trial passed, and both numbers were restored to QA.

Added an opt-in handset transfer lane for the two-number Rocksalt pool. An
operator's inbound handset supplies the third leg. Only a confirmed “transfer
test” utterance triggers media loss. The second pool number has no receiving
route for the first attempt and a controlled answering route for the second.
The fixture publication test passed for both roles. Actual transfer outcomes
still require the coordinated handset window.

QA deployed `615f6975` with a successful public health check. The live number
plan reported both Rocksalt numbers available on QA. All umbrella children
except Console passed in the umbrella run. That run had loaded Console test
support before the handset fixture was added. The full Console rerun on the
final source passed (678 tests, 141 excluded). Formatting, warnings-as-errors
compilation, strict Credo, unused dependency checks and Lean passed.

Exercised call-spec and release rollback against a disposable database with
the actual QA images. Release `9e320582` published an original spec, release
`615f6975` enabled the transfer destination in a new revision, and the prior
release republished the original source. Each step verified the effective
inbound route. This rehearsal did not switch shared QA traffic.

Exercised the room authority with two participant connections and a pending
repeat prompt as the caller enters hold or private briefing. In both cases the
timeout stopped the caller's cue, the second connection received no command, and
a delayed failure could not close the call. The focused room-authority and
call-spec compiler suites passed together (17 tests). The recovery destination
contract is covered by same-service and allowlist validation, fixed E.164
connection validation, self-loop rejection, compiler pinning, and the two-release
publication rehearsal.

A signed destination decline previously produced the generic transfer failure.
A focused carrier-harness test reproduced it. The decoder now retains the
decline alongside the existing remote-hangup reason, and the original caller
leg journals `transfer_rejected` under the linked dial command. The same
test exercises busy and unanswered calls and checks that the callback plays
before caller hangup. The harness also monitors actual AI room termination
during the transfer announcement, while ringing, and after bridge confirmation.
The six signed transfer cases initially failed only for a decline, which had
been journaled as generic failure. The final targeted gateway run passed all
51 cases. Under concurrent suite load, earlier runs saw one no-repeat test leave
the room before its expected phase and one media-harness startup failure.
Neither failed in the fresh focused run. The original intermittent causes
were not established.

For handset acceptance the operator requested the usual Rocksalt receiver.
The initial window listened on the pool caller and timed out waiting for the
spoken trigger. Updated the handset fixture to use the designated receiver for
both incoming routing and outbound identity, leaving the other pool member as
its recovery destination. A publication test on synthetic numbers passed.
The live runner initially overwrote the selected roles while adding the public
endpoint. Preserving fixture settings fixed the discrepancy; the live
readiness message then confirmed the intended receiver.
The receiver window expired without a confirmed spoken trigger. No transfer
outcome was established. The runner restored both loaned numbers and the
post-restore plan found both on the QA app.

### Handset transfer trial on QA release source `8329df30`

The coordinated runner admitted the operator's call on the designated
Rocksalt receiver. They said “transfer test” and heard the transfer
announcement. On ring-out they heard “We have lost the audio connection,
please call back.” Before admitting the second test, the runner verified
`transfer_unanswered`, callback playback completion and `carrier_ended` on
the original leg. Perceived silence and fault-to-audibility time were not
measured on this call.

On the second handset call the caller interrupted the speaking agent, said
the trigger, and heard silence. At 11:46:53 UTC the text-to-speech allocation
reported `session_failed`; the room notified the established phone media
process of `agent_unavailable`. That process exited with `media_unavailable`
without signalling carrier recovery. The runner expired waiting for the
confirmed trigger and did not inject its test fault or verify a bridge.
The underlying reason for the provider session closure is unknown.

A configured gateway regression disconnected the voice transport on an
established call. It failed waiting for a carrier transfer announcement, then
passed after the media process handed agent and speech-output unavailability to
the surviving leg through the same main-media eligibility check. The harness
observed the announcement before a single linked dial. The live Scribe/Telnyx
case subsequently replaced the recognizer, transcribed the repeat prompt on
the remote leg, injected the observed voice-session closure, and verified
signed callback completion and carrier termination (one test, zero failures).
Both Rocksalt numbers returned to QA. This live check exercised the callback
branch. The successful handset bridge still needs independent evidence.

The umbrella reported 6,570 tests with zero failures. Formatting,
warnings-as-errors compilation, strict Credo, unused dependencies and Lean
also passed. The QA container revision matched `d28a2f25`. Its public
health endpoint returned HTTP 200 after startup.

On the gateway harness, the signed caller hangup during ringing ended the
destination but did not journal the transfer outcome. Added a regression
requiring `transfer_abandoned` with the original linked dial command ID and
observed it fail. The original leg now records abandonment before retiring a
pending peer. Ending an established bridge retains its successful outcome.
The transfer harness covers six outcomes. The worker-loss cases separately
verify a signed playback completion after worker death and a bounded same-ID
end retry that preserves uncertain command drainage.

The journal test simulated committing a record and losing its acknowledgement
at each of the 19 carrier phases. Each retry preserved the claim, phase,
command ID and original deadline. Stale timers and duplicate observations
produced no extra write. The gateway harness separately covers storage loss
before announce or dial, and the persistence tests check incarnation fencing.

Added a single-call handset mode for the two outstanding listening checks.
The original two-outcome mode remains available. After explicit spoken opt-in,
the new mode disconnects the live Scribe session on the next open caller turn,
checks the recovery completion against that turn, and counts completed answers
correlated with the commercial-property question. Saying “transfer now”
allows the same caller to continue to the answered bridge. A local regression
checks that an unrelated acknowledgement cannot count as the answer and that
duplicate completed answers are detected. Human audibility remains unverified.

Reconciled the QA release gate against the running container revision
(`4f1283be`), successful public health probe, 6,571-test umbrella result,
and a fresh successful Lean verification. Release verification and the
isolated rollback rehearsal are complete. The broader rollout gate remains
open pending handset acceptance.

Verified the reverse shutdown order on an established inbound call. After the
room exited and a carrier hangup was in flight, the harness delivered a failure
from the originally bound media process to the leg. The leg stayed closing
with no recovery journal, playback, or dial. The focused run included recovery
before room shutdown, explicit platform hangup, a busy leg with queued media
loss, and six transfer outcomes (10 tests, zero failures).

Verified both sides of the recognizer cutover. A final arriving before
retirement cancels replacement. After replacement starts a fresh turn, a
delayed partial, final, and close from the old session leave it active. Only
the fresh final emits a completed turn. The recognition suite passed all
10 tests. The configured gateway repeat test independently observed one
agent request on the same media socket (one test passed).

The established-media failure notification dropped the room’s classification before carrier handoff. A gateway voice-failure assertion and a PostgreSQL journal assertion reproduced the loss. The leg now records the bounded cause on its opening announcement intent, including transfer announcements, and carries it into its end request. Unexpected process loss has a separate classification. The PostgreSQL suite passed all 11 tests, including duplicate writes with an unchanged first deadline. The initial combined gateway run had two failures during media startup and repeat-prompt handling. The unchanged gateway harness and journal suite then passed all 53 tests. This rerun does not establish the cause of the intermittent failures.

A cold-restart drill used two independent BEAM VMs and a disposable PostgreSQL
database. The first persisted an inbound leg, pinned tenant-local service and
opening announcement intent, then exited. The second found an expired intent
with no room or leg owner. The mounted webhook initially returned HTTP 503 on
the older service format. Those plans pin service and credential IDs but lack
the later credential-owner and credential-name fields.

The webhook now resolves that tenant service, requires an exact match to the
pinned reference and uses its registered Telnyx verification key. The cold VM
rejected a wrong signature with HTTP 401, accepted the matching signed hangup
with HTTP 200 and marked the leg ended. No outbound hangup intent was created,
the leg supervisor remained empty and the call retained a null gateway cleanup
acknowledgement. The disposable database was removed after verification.
The mounted route covers both credential formats and rejects a changed
credential ID. Together with owner death before/after playback submission and
HTTP-worker death after send, 13 focused Gateway cases passed.

The first umbrella run for the cold-restart change failed while opening the
simulated carrier socket, before the platform-hangup test exercised recovery.
With the fixture forwarding the bounded dispatch reason, five recovery cases
reproduced `:media_session_not_found`. The fixture reuses the same leg IDs and
the previous media connection supervisor can outlive the session it owned.
Teardown now terminates those fixture media trees synchronously. A first stress
run also saw HTTP 404 at inbound admission before media startup. The harness
now waits for its scoped webhook registry key to clear before reusing the leg.
The 404 alone does not prove which lookup returned it. The final five-case
group passed 401 consecutive runs at the original seed (2,005 case executions).

The recovery owner previously ignored a validated Telnyx stop frame. A focused
test observed the eligible media monitor still attached after the socket sent
the stop. The incoming leg now remembers the admitted socket and stream ID and
retires only their media watch when the stop arrives. The socket can close
later. The provider-neutral adapter continues to treat stop as a transport
notification. The configured harness kills the stopped media process and checks
for absence of carrier recovery, then submits the signed caller hangup.
It separately exercises a held transfer path and proves a genuine voice failure
still triggers playback after stale failure notifications. A registry test
verifies monitor replacement and fresh eligibility. The focused gateway, decoder,
and socket checks passed 22 tests.

Verified carrier playback retry behavior with the production Telnyx adapter
and two controlled numbers. The first run received signed playback completion
but timed out waiting for a far-leg callback transcript; its logs also recorded
agent failure. The second used the existing recovery fixture with a controlled
incoming recognizer and live far-leg transcription. The far leg heard the
greeting and callback. The carrier accepted an identical playback command ID
after the first signed completion. No second distinct event for that command
arrived in six seconds or before a fresh command on the same leg completed.
Both rooms ended. The pool restore and subsequent plan verified two numbers
back on the Rocksalt QA application after each window. This is automated
carrier evidence; handset repeat and answered-bridge checks remain open.
