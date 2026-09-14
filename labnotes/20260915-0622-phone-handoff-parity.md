# Phone handoff parity

Continue the phone slice after AI acceptance in `68e4150`. Human web, AI and
initial waiting are accepted; fourteen checkpoint tasks remain overall.

## Boundary review and intended evidence

Existing signed incoming Telnyx/Twilio harnesses run the ordinary call, private
briefing and press-1 transfer even after simulated admission storage failure.
They selected STT only for the caller, so destination readiness and post-transfer
recognition were unproven. Extend those runnable flows with destination STT,
recording and default/URL/nil waits. The real provider media adapters and native
Opus/PCMU codecs remain in use; synthetic sockets supply controlled acknowledgements.

The receiving socket withholds its actual cue drain mark. Replaying earlier marks
must leave destination admission private. A fresh cue mark permits source teardown
and live conversation on retained media actors. Real provider audibility remains a
separate acceptance item; the existing live API lanes only establish control calls,
not received audio or physical playout.

## Work and detours

- Added the selected support STT option and recording options to the shared test
  scenario, extended both provider harnesses to three wait configurations, and
  added a shared phone media assertion fixture. No production behavior has changed.
- Added a fixture switch for automatic mark replies and explicit mark replay through
  the real socket decoder. Test media timestamps follow elapsed monotonic time from
  the first media input; large arbitrary sequence-derived timestamps would create
  artificial future audio.
- First focused URL run: two failures before source startup. The synthetic fetcher
  had been supplied as an engine-only per-call option that Gateway admission does
  not forward. Ordinary admission uses application audio settings. Configure the
  controlled fetcher at that existing boundary; retain the harness's original
  application restoration. Do not expand runtime configuration for a fixture.
  Evidence: `vxpipe-phone-parity-first.log` in the local temporary directory.

At this point verification was still in progress; no task checkbox was complete.

- Second URL run reached the cue barrier. Twilio retained an obsolete assertion
  for any outgoing media packet after the new helper had already decoded/drained
  the cue; remove that duplicate observation. Telnyx received a recording chunk
  asynchronously after the hold began. The signed-call prelude deliberately sends
  one permitted silence frame, so check that any such chunk belongs only to the
  caller and contains silence; reject non-silent private audio rather than silently
  discarding earlier recording messages. Evidence: `vxpipe-phone-parity-second.log`.

- The third focused URL run passed both providers, including received conversation
  audio after a withheld cue mark. The first full configuration run reached the
  new transcript check but its constructed provider signal omitted mandatory
  `words` and used the wrong end-turn field. Corrected it to the existing Flux
  protocol (`words: []`, `trigger: "model"`). The check observes actual transcript
  events delivered to the opposite phone media session. Source acknowledgement
  model requests already queued before departure are separated from forbidden new
  model turns after the room becomes human-only.

## Focused results and remaining boundary

- Six default/URL/whole-object-nil phone handoffs pass with received Opus/PCMU
  waits, held cue drain, retained caller/destination media and caller STT, recorded
  conversation and opposite-recipient transcript delivery. Evidence:
  `vxpipe-phone-parity-matrix-final.log`, six tests, zero failures.
- Four provider disconnect cases pass: destination loss during STT preparation
  with URL waits and loss while its cue mark is held with nil waits, for both
  carriers. The exact destination STT dies; the original caller/room/source
  providers remain, the failed tool is published after recovery, received cue
  precedes source speech, and another recognized caller turn reaches the source.
  Evidence: `vxpipe-phone-recovery-first.log`, four tests, zero failures.
- The final fixture additionally checks one configured URL fetch with no replay-time
  fetch, and acknowledges the old mark after successful release without reactivation.
  The existing web-to-phone admission/wrong-source/press-1 checks and both socket
  mark/foreign-stream/busy-dispatch cases run in the focused regression group.
- Read the guarded Telnyx/Twilio integration tests before running them. Neither live
  enable flag is set in the test environment, and carrier credentials, authorized
  test numbers and public callback/media URLs are absent. The guards skip before
  reading credentials or placing calls. Even an enabled API acceptance test only
  proves a control submission; it does not establish physical audibility. Live
  wait/cue/clear/recovery playout therefore remains an explicit external acceptance
  item. Independent changing-listener work can proceed after local phone acceptance.

Focused regressions and the final root gates were still pending at this point. No production change or
new UI is included in this checkpoint. The configured 10-second transfer deadline
and production 750 ms recovery budget remain unchanged.

## Local regression evidence

The focused Gateway group passed 50 tests with zero failures: both signed incoming
harnesses (including startup cases, six completed handoffs and four disconnect
recoveries), existing outbound web-profile phone transfers, both media session
paths and both provider socket mark/stream checks. The owning phone-room group
passed three tests. The guarded provider API lane reported two skipped tests and
zero failures; no provider call was made.

Logs: `vxpipe-phone-parity-focused.log`, `vxpipe-phone-parity-engine.log`, and
`vxpipe-phone-live-guards.log`. The final root run also checks an added explicit
comparison of all participant capability bindings during source recovery.

## Local phone acceptance audit

- Supported configured media: Telnyx mono Opus at 16 kHz and Twilio mono PCMU at
  8 kHz enter the actual provider socket decoder and native room conversion path.
  Both caller and incoming human select STT. Readiness is delayed after authenticated
  press-1; conversation reaches both retained recognizers only after release.
- Private setup: early press-1 cannot admit the phone before briefing completes.
  Default/URL/nil waiting applies to both participants. Private briefing, waiting,
  cues and held microphone tones produce no non-silent recordings. A delayed
  pre-hold caller-silence chunk is identified by source identity and sample content.
- Cue completion: the final cue is decoded but its mark remains unacknowledged.
  Earlier clear marks cannot complete that drain, admission stays private and the
  original attempt/deadline remains unchanged. The exact fresh mark opens handoff;
  duplicate old completion is harmless. Existing socket checks cover foreign streams
  and processing marks independently of a busy event dispatcher.
- Conversation: both peers receive actual encoded audio after the cue, and the
  opposite media session receives each permitted final transcript. Human-only
  transcripts cannot start another model turn. Configured URL bytes are fetched
  once, not per loop or player. Room and codec/ingress/egress identities remain.
- Recovery: actual socket loss before readiness and while cue drain is held removes
  the exact private destination and its STT. The source, caller speech/media and
  room actors remain. Caller receives a cue followed by source speech and a later
  recognized caller turn. Existing outbound web-profile checks retain their
  allowlist, wrong-source DTMF, machine-result and admission behavior.
- Limits: these are real adapter/codec/control paths driven by synthetic sockets
  and speech providers, not physical carrier playout. The live check stays open.
  Changing/five-participant audience cases remain in their separate checkpoint.

## Root gates and checkpoint outcome

All five root gates passed: `mix format --check-formatted`,
`mix compile --warnings-as-errors`, `mix credo --strict`,
`mix test --max-cases 4 --seed 235296`, and `mix deps.unlock --check-unused`.
The umbrella run reports 1,423 tests, zero failures and 16 integration exclusions;
Gateway contributes 409 tests. The last added participant-binding recovery assertion
is included in this run. Logs use the `vxpipe-phone-parity-` prefix and the results
manifest is `vxpipe-phone-parity-results.json` in the local temporary directory.

Close the five local phone implementation/acceptance tasks with this checkpoint;
leave physical carrier audibility open. The milestone and index now count nine
remaining tasks: one live phone check, six changing/multiple-listener tasks and two
final audit tasks. The owning phone-room checks also retain actual configured
attempt expiry and exact outbound-owner loss, with no deadline extension.
