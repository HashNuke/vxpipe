# Caller recovery after speech recognition or room audio failure

**Status:** The configured harness exercises recognizer replacement, carrier disconnect and transfer. Live ElevenLabs recognizer replacement and the isolated release and call-spec rollback passed. The live unanswered transfer preserved the caller leg for the callback recording. A confirmed answered handset bridge and a repeated question receiving one audible answer remain open. See the [implementation evidence](../20261124-0822-implement-caller-recovery.md). The user approved bounded in-room recovery and a carrier-controlled exit. The timings and configuration below are proposed implementation choices. Track design review in the [planning record](../20261124-0807-caller-recovery-milestone.md).

## Runnable outcome and dependencies

An inbound Telnyx caller interrupts a speaking agent and asks a question. If recognition stalls, the caller hears a recovery cue, gets one opportunity to repeat after listening resumes, and receives one answer. If room audio fails, the caller hears a recording directly on the carrier leg and gets a transfer or a clean disconnect. An unavailable carrier is recorded as an unknown outcome until reconciled.

Read the [ownership decision](../../docs/design/caller-speech-recovery.md), [call lifecycle](../../docs/en/development/call-runtime.md), [speech contracts](../../docs/en/development/speech-runtime.md) and [QA baseline](../20261124-0743-caller-barge-in.md). Completed prerequisites are [telephony lifecycle](outgoing-calls-and-live-telephony.md), [shared Telnyx routing](shared-telnyx-applications.md), [persistent speech sessions](persistent-speech-sessions.md) and [operational Silero onset](transcript-start-and-optional-vad.md). Reuse [passive diagnostics](passive-call-latency-diagnostics.md) for comparison when enabled. Recovery must also work with diagnostics off. The [voice policy milestone](voice-agent-turns-and-listening.md) owns backchannel classification, listening cues and endpoint quality. The prompts here explain a service failure.

First acceptance profile is an established inbound, main-media, English-language Telnyx leg with human Scribe v2 realtime input. Retain current behavior for other transports and providers until their carrier or media contracts are verified. No global VAD default change. Complete checkpoints in order. Every behavior task starts with a failing project-owned test in its owning umbrella app.

## A. Carrier announcement and bounded disconnect

- [x] Reproduce the incident with a configured gateway integration test. Start an answered leg and interrupt output, fail STT, observe room media detach and demonstrate that the active carrier currently receives no exit command. Keep this test independent of the specific Scribe failure cause.
- [x] Carry the reason, leg, room incarnation and connection generation to the surviving leg owner. Handle an unexpected loss of established main media once. Distinguish normal caller hangup, intentional stream stop, hold, transfer preparation, replacement of a connection and shutdown. Monitor loss as well as explicit failure so a crashing media worker cannot lose the notification.
- [x] Provision a short English callback recording accessible to the carrier independently of the deployment's media WebSocket and live TTS. Extend the Telnyx voice client and signed webhook dispatch for playback. Validate carrier asset format, playback targeting on the caller leg after stream loss, completion correlation and duplicate command semantics against a real test number. Reuse the service's existing credential resolution.
- [x] Implement bounded phases for playback request, completion and hangup. Initial QA budgets: allow 5 s for a carrier command acknowledgement and the known clip duration plus 2 s for completion. Bound the entire exit using one absolute deadline. An ambiguous command result reuses the same command identity. Playback failure/expiry still initiates hangup. Caller hangup wins in every phase.
- [x] Have the original leg owner accept carrier-recovery ownership for the current binding before initiating AI room teardown. Serialize media loss, room DOWN and carrier commands in that owner. Once accepted, room DOWN retires AI resources while carrier playback, ringing or a human bridge continues. If room DOWN wins before handoff, run ordinary leg termination; stale recovery cannot reopen a closing leg. An explicit whole-call hangup overrides either owner state and ends every owned leg. Test both message orders and simultaneous hangup.
- [x] While its original owner lives, bind each effect to one tenant/call/incarnation/leg/attempt/phase. Journal intent before sending, with a 1 s storage budget inside the phase deadline. On unavailable or ambiguous storage, fall back to callback announcement and hangup on the known caller leg using stable command IDs retained by that owner. Suppress new dial/transfer effects until intent is durable. After a possibly submitted transfer, reconcile the existing effect under B. Retry evidence writes when storage returns; cleanup acknowledgement still requires durable final usage, drained commands and carrier evidence. Test write failure before first playback and ambiguous writes at each transition.
- [x] On HTTP-worker death the surviving owner reads its journal (or retained degraded-state intent), checks for a matching callback, and reconciles only that effect. Model a bounded, same-ID termination retry explicitly even when the old worker left command drainage unknown. Preserve the outstanding drainage evidence independently of this retry. Deduplicate late replies and never assert successful drainage from a new worker alone.
- [x] Treat original temporary leg-owner death and node restart as separate failure scopes. A reconciler may reload durable attempt metadata and match signed terminal events to an exact binding. It cannot recreate a leg owner or claim cleanup membership from a stored row. Without a living fenced owner or conclusive carrier evidence, record unresolved disposition for operator follow-up. Test worker death after send, owner death before/after send and node restart with delayed callbacks; assert who can issue effects and who can acknowledge cleanup.
- [x] Gate: fake carrier covers accepted, rejected, timeout, duplicate/reordered/missing callbacks, worker death after command send and concurrent remote hangup. Real handset hears the complete callback recording before disconnect. Confirm terminal carrier evidence and matching stored leg/call state.

The live playback retry gate passed on the two controlled Rocksalt numbers.
The far leg transcribed the callback. Reissuing its completed command with
the same ID was accepted and produced no second distinct completion during
the observation window. A fresh command on the same leg produced its own
signed completion. Both calls ended and the numbers returned to their original
QA application.

The leg watches the established media process and its socket and stream ID.
A matching Telnyx stop retires that watch before the socket closes. The
gateway harness covers a crash after stream stop, a voice failure while held
for transfer, and a valid failure following stale socket, stream, media PID,
room incarnation and leg signals. Replacing a registered session requires the
new process to establish eligibility.

A cold-restart drill wrote the opening intent to disposable PostgreSQL, stopped
the VM, and submitted a delayed callback to the mounted route on a fresh VM.
The expired attempt remained unknown until the original service authenticated
the hangup. The signed event ended the leg. The call retained its outstanding
cleanup acknowledgement and the leg supervisor had no children. Focused tests
also kill the live leg owner before and after playback submission and kill an
HTTP worker while its carrier command is in flight.

The initial announcement intent now carries the classified media failure. An unexpected media process exit records `media_process_lost`. Retries retain the first recorded reason and deadline.

A real Telnyx-to-Telnyx call passed the callback-and-end test. The far leg
transcribed the initial greeting, the incoming room lost both recognizers,
Telnyx confirmed completion of the callback recording, and both rooms ended.
On a separate QA handset call, the caller heard the complete callback recording. The call and leg both reached ended, with signed playback completion and carrier hangup recorded. Live transfer outcomes and successful in-room handset recovery remain open.

## B. Configured human fallback

- [x] Add an optional, revision-pinned inbound recovery destination to the call spec. Select one validated tenant-authorized PSTN destination through the existing service/routing policy, reject self-routing loops and invalid numbers before publication, and preserve old pinned revisions. Omission selects checkpoint A. Inspect current transfer contracts before deciding whether an existing destination reference can be reused.
- [x] Add a separate transfer announcement and a carrier-native transfer command using the original caller leg. Correlate the resulting leg and terminal events to this single attempt. Track answered/bridged, busy, rejected, unanswered, ambiguous and caller-abandoned outcomes. The gateway owns carrier effects even after room teardown.
- [x] Bound ringing (initial QA budget 20 s). On confirmed failure, if the caller leg remains controllable, play the callback recording then hang up. On ambiguous status reconcile before issuing conflicting commands. Establish through provider testing whether the original leg survives an unanswered transfer; if it does not, select a carrier-supported dial/bridge flow preserving the caller before enabling the option.
- [ ] Register both carrier legs with their owning cleanup lifecycle before declaring a successful handoff. Keep the carrier owner through human conversation. Track terminal webhook and usage evidence separately for each leg. A bridge event ends recovery timers, while caller abandonment or explicit platform hangup tears down outstanding dialing/bridged legs. Exercise room death during the announcement, ringing and an established bridge, including a concurrent platform hangup.
- [ ] Gate: one transfer for duplicate callbacks and retries. A successful human conversation survives AI room cleanup. Exercise no answer and caller hangup during ringing on test numbers. Check announcement ordering, call finalization, carrier cleanup and usage for both legs.

The signed-webhook harness distinguishes a declined transfer, busy line, and
unanswered call, and exercises room shutdown before dialing, while ringing
and after bridge confirmation. On the first live handset transfer, the caller
heard the transfer announcement and then “We have lost the audio connection,
please call back.” The runner observed `transfer_unanswered`, signed callback
playback completion and terminal evidence on the original caller leg before
opening the answered-transfer gate. This verifies that an unanswered linked
dial preserves the caller leg for the callback. The second handset call lost
agent speech output before the runner observed its spoken trigger; it did
not establish an answered transfer. A configured regression now covers the
carrier handoff on agent voice failure. A live two-number test verified
callback completion and caller hangup after that failure. The handset runner now
requires durable managed cleanup and separately identified terminal usage for
both attempts. A linked-leg test also verifies that carrier hangup persists
final usage after loss of its end-command observer while cleanup stays pending.
The stronger handset check still needs a coordinated call.

## C. Restore recognition while room audio remains usable

- [x] Expose operational acoustic transitions from ConversationalSTT independently of canonical caller-turn events. Carry allocation generation, input source epoch, segment sequence and sample index, anchored to a monotonic capture timestamp and sample rate for that epoch. Reject events from retired sources, duplicate segments and late inference from an earlier generation. Emit resumed speech even if the same transcript turn stays open. Test speech → confirmed offset → new speech without text → original timer expiry, with diagnostics off. The original timer must be inert.
- [x] Begin with the completed caller question and delayed final transcript in a configured-room test. Maintain an explicit active-turn identity and consume operational speech-end evidence. Trial 4 s of waiting from acoustic end, accounting for offset confirmation time. Disarm on resumed speech, normal completion, source change or caller departure. Long speech, ordinary silence before a turn, and passive-only VAD must never fire the timer.
- [x] Route confirmed STT failure immediately according to path health. If ingress and output can remain bound independently of the failed recognizer, preserve audio and attempt recovery. If room media is lost or its output cannot play the cue, yield to A/B. Define the recovery decision before the current connection-unavailable notification tears down the path.
- [ ] Play a prepared system cue (“One moment, I’m having trouble hearing you”). Deliver both prompts only to the affected caller's current main output. Arbitrate with that sink's existing playback and wait for clear acknowledgement before injecting audio. Leave other sinks and participants’ playback alone. Hold or private briefing withdraws eligibility, cancels pending prompts and fences delayed callbacks; recheck source ownership on return. Where a caller-only route cannot be established, skip the cue and use the carrier exit only for an eligible failed main leg. Test a second participant and private briefing for disclosure and unintended output cancellation. Start one fresh allocation for this participant on the pinned configuration. Require provider readiness and successful ingress binding within a proposed 5 s from recovery start. Escalate a second failure within this recovery episode. Never replay buffered caller audio across generations.
- [ ] Define the atomic decision point between accepting a late valid final and retiring the old allocation. Normal completion before this point cancels pending effects; later old partials, finals, timers and readiness are discarded. On successful replacement ask once, “I missed that last part. Could you repeat it?” Admit fresh caller input while the prompt plays and stop the prompt on new speech. Keep interrupted/lost input and system messages out of agent-authored history and bill actual usage once.
- [ ] Gate: controlled-clock tests for late final on each side of cutover, continued speech, missing transcript, provider crash, stale media events, repeated failure, hangup, transfer and hold. One accepted repeated question produces exactly one answer. Recovery leaves unrelated participants and tools intact. On cue failure or readiness timeout the caller enters A/B once.

### Deadlines and episode boundaries

These are initial QA budgets. Use monotonic deadlines in a running owner. Durable records retain the original expiry for reconciliation. Duplicate events never extend a deadline.

| Phase and deadline origin | Success | Expiry or failure |
| --- | --- | --- |
| Caller stops speaking on an open turn, 4 s from last operational offset | Scribe completes the turn, or resumed speech cancels the watch | Begin one recovery episode and retire the failed input at cutover |
| Replacement admission, 5 s from episode entry including cue arbitration | Fresh provider ready and ingress bound, issue repeat prompt | Enter carrier exit once |
| Repeat prompt, known clip length + 2 s from request | On caller speech stop prompt immediately; otherwise allow 10 s from playback completion for speech to start | Missing playback completion with no speech, or no repeat within 10 s, enters carrier exit |
| Repeated utterance, same episode | First accepted fresh final ends episode and restores normal retry budget for a future independent turn | Provider failure or 4 s after the repeated utterance's last confirmed offset enters carrier exit without another allocation. Resumed speech cancels the offset timer. Normal ongoing speech can continue |
| Carrier exit, 60 s absolute from handoff, reserve final 5 s for termination | Playback acknowledgement within 5 s and completion within clip duration + 2 s advance the selected branch | Missing completion on transfer announcement selects callback-and-end if budget permits. Missing callback-clip completion advances to hangup. Skip clips which cannot fit before termination reserve |
| Transfer, 20 s from submission to bridge, then up to 5 s to reconcile signed evidence within exit budget | Confirmed bridge retires recovery timers; confirmed unsuccessful attempt with a controllable caller leg uses callback-and-end | At ambiguous expiry stop dialing/retrying, cancel outstanding owned destination and request end of known owned legs using stable IDs. A late bridge cannot reverse termination intent |
| Carrier end, by absolute exit deadline | Verified terminal evidence for each leg settles its outcome | End foreground waiting, surface unknown and continue existing cleanup reconciliation. Local deadline is never proof of remote hangup |

Exercise no repeat, resumed speech, ready-then-failed replacement, missing clip completion, ambiguous transfer and late bridge at expiry using a controlled clock. Clamp every subordinate timer to the applicable parent deadline.

Configured harness evidence: an open commercial-property question reaches one
fresh Scribe allocation after an injected offset deadline. The test waits for
both caller-specific recordings to finish before submitting the repeat and
observes one agent request. A second configured test starts the repeat during the
prompt, confirms the fresh question reaches the model once, and observes the
answer submitted for synthesis. The room test delivers both an expired timer
and a failed playout callback after caller onset. Separate tests exercise resumed speech, a final
before cutover, readiness timeout, missing repeat and replacement failure.
The recognition test delivers an old partial, final and session-close notification
after the replacement has started transcribing the repeated question. The fresh
session stays active and emits exactly one completed turn, from its own final.
A two-participant room-authority test also covers an expiring repeat prompt
during hold and during private briefing. Only the affected caller receives a
stop command, and a delayed playout failure cannot interrupt the other participant
or trigger carrier exit. Handset evidence and the full checkpoint acceptance
matrix are still open.

## D. Prove the caller experience and operability

- [ ] Record source generation, trigger, classified failure or unknown cause, cue request/playout, readiness, repeat, carrier command and terminal evidence with turn/leg correlation and monotonic timings. Keep transcripts, credentials, phone numbers and audio out of diagnostic labels. Distinguish server playback evidence, carrier acknowledgement and handset listening. Make the sequence inspectable with existing call details.
- [x] Add scoped QA fault injection via test dependencies/harness: drop STT after barge-in, delay a final on a healthy stream, fail replacement readiness and suppress a playback completion. Keep injection unavailable to ordinary callers. Use synthetic equivalents of the gardening/commercial questions and a short acknowledgment as a healthy control.
- [ ] On a real QA handset run healthy, recovered, announced-disconnect, successful transfer and unanswered-transfer cases. Record perceived silence, exact prompt heard, whether the repeat was captured, number of agent answers and confirmed final disposition. Measure fault-to-first-audible-cue and total time to recovery/exit against the checkpoint budgets. Verify no competing voices or silent active leg after a recoverable carrier outcome. Redact sensitive data from evidence.
- [x] Run focused suites, umbrella formatting, warnings-as-errors compilation, strict Credo, tests, unused dependency check and Lean state-machine verification. Update operator troubleshooting and the evidence ledger. Deploy only through the normal authorized QA flow. Gate broader rollout on handset evidence and an exercised rollback to the prior call spec/compatible release.

Call details expose the original carrier owner's monotonic phase offsets under
each leg's `caller_recovery`. Queued journal retries retain the first offset.
Terminal evidence reconciled without the owner carries its wall timestamp only.

The remaining handset repeat and answered-transfer checks can use one
coordinated call to the pool receiver. The test waits for spoken consent and
uses an authenticated carrier bridge event and destination-side transcription.
The operator records audibility and perceived delays. [Handset procedure](../../docs/en/development/testing.md)

The QA release at `4f1283be` returned HTTP 200 on its public health endpoint. The
umbrella suite reported 6,571 tests and zero failures. Formatting,
warnings-as-errors compilation, strict Credo, unused-dependency checks and
the Lean verification lane passed. The later single-call test runner change
(`9fab161e`) passed the Console suite with 679 tests. The handset gate above
still controls broader rollout. [Operator troubleshooting](../../docs/en/development/call-runtime.md#diagnosing-a-caller-left-in-silence)

The release rollback rehearsal used a disposable database. Release `9e320582`
published the original inbound spec. Release `615f6975` enabled a recovery
destination, then the previous release republished the original source.
Inbound route resolution selected the expected revision at each step.
