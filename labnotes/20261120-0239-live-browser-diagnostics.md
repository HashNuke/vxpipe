# Live browser diagnostics

## Bounded acceptance plan

Reuse StructuredBrowserSite and the production PlaygroundApp to prepare and join
an actual Gateway WebRTC call in Chrome. A dedicated fixture microphone plays the
already-approved public human OSR crop through WebAudio/MediaStreamDestination;
Chrome encodes RTP and the production Gateway delivers it to real ElevenLabs
Scribe. Run actual native Silero both as fallback and as operational reuse. LLM
and TTS are deterministic local fixtures, explicitly not live provider coverage.

Inspect the same persisted call through the production admin route after real
Identity login (reuse the existing settings browser setup pattern). No test-only
renderer substitutes for the required admin UI. Exercise ordinary turns,
pause/resume, sustained response plus human interruption, actual tool-only end,
and final disconnect. Compare stored endpointing/barge-in rows, bounded provider
and clock evidence, fixture reference bands and rendered millisecond values.

The tagged test contract is written first. The scenario helper is deliberately
not implemented yet pending a safe focused red lane; no live request is authorized
until the parent coordinates it. No credentials or prohibited env file read.

## Preparation evidence and current boundary

The offline microphone acceptance first failed because the browser helper did not
exist, then passed in real Chrome (1/1, seed 137530; rerun 1/1, seed 660141).
It verifies the real human WAV decode, 8 kHz source, 268985 source frames, exact
27200-frame crop, nonzero PCM, stable getUserMedia audio track and playback end.
Logs: vxpipe-live-microphone-red.log, vxpipe-live-microphone-green.log and
vxpipe-live-microphone-final.log. It does not claim RTP/provider/native validation.

The concrete live scenario and driver are prepared but unrun. The local host only
serves the fixture WAV/status and existing production playground. The same browser
then logs into real Identity and inspects the persisted call on the production
admin route. Exact persisted primary millisecond values must appear in the table.
The call uses real managed WebRTC cleanup and durable archive projection. Native
VAD and Scribe remain real; model replies, the actual host tool and paced TTS tone
are deterministic fixtures. No live request or secret file access has occurred.

User scope corrections: database CPU, inference-coverage thresholds and model
accuracy are not acceptance gates. Setting changes affect new calls only; this
scenario sets collection before admission and never toggles/revokes active calls.
The parent owns the new call-start settings contract; its integration into this
helper is pending. No UI copy or production files were changed.

The new call-start contract is now wired: the scenario supplies only
`diagnostics_settings_loader: &DiagnosticsSettingsStore.snapshot/0` in the runtime
configuration before admission. Removed SettingsSupervisor/Projection setup and
all projection options. No process acknowledgement, polling or global propagation
is part of the test. Focused compilation awaits the backend migration lane.

After the call-start settings migration, the offline microphone regression remains
1/1 green (seed 936911, vxpipe-live-microphone-reviewed-prep.log). The complete new
support code compiles. The pending live test now records exact model-request source,
connection and canonical turn/command identities by scenario phase, requires actual
host-tool execution, and matches the interrupting row to the previous output's
identity. Production admin verification includes Technical events off by default,
visible after enabling, hidden again, plus exact persisted primary values in ms.
The live test has `diagnostics_vad: false/true` tags for a bounded single-mode first
run. No live request has yet been made; Astra preflight review is pending.

## First bounded live attempt

Astra preflight identified and corrected missing global Ecto repository wiring for
production admin/API reads, cleanup on failed test/browser tasks, weak whole-table
substring comparisons, and an invalid synthetic provider interruption acknowledgement.
The final preflight microphone check passed 1/1 (vxpipe-live-microphone-preflight.log).

The authorized first fallback attempt ran via bin/livetests and failed once after
48.5 seconds: fixture TTS reported provider_failed during room startup, then the
browser readiness wait expired. No primary-metric scenario completed. Diagnosis:
production Gateway admission passes per-call speech_runtime into RoomSupervisor;
setting only the Application's TTS fixture config (as TestCallStartup helpers use)
did not override this path. The admission options now explicitly pass the real STT
and local synthetic TTS runtime configurations. Stage-only progress output was added.
No repeat has run yet. Log: vxpipe-live-diagnostics-fallback-first.log.

ExUnit includes override excludes; --only live_elevenlabs combined with a VAD-mode
exclude is not a reliable mode selector. That first attempt happened to run false
and stopped at its first failure. Future single-mode command uses the exact file
with --only diagnostics_vad:false --max-failures 1; this contains only Scribe tests.

## Second fallback attempt: asynchronous browser predicate defect

The exact fallback-only selection ran one test with the operational mode excluded and failed at the barge-base browser speech-start wait (60.3 seconds). The earlier normal/pause stage lines did **not** establish completed turns: offline Chrome reproduction showed `agent-browser wait --fn '(async()=>false)()'` returned success immediately with result false. Async server-status predicates therefore advanced before the fixture had completed those phases.

Replaced the driver predicate helper with explicit awaited polling through `eval`, bounded at 40 seconds. Offline checks confirmed an always-false asynchronous predicate now throws the expected timeout and a delayed true predicate succeeds. Added bounded failure evidence containing only browser event types/timestamps/connection states, archive fact kind counts, fixture model/TTS phase labels, and audio rejection reasons. No transcript/provider payload is logged. The second live attempt is retained at `vxpipe-live-diagnostics-fallback-runtime.log`; no acoustic or successful barge-in claim follows from it.

## Third fallback attempt: wrong Scribe profile

With awaited predicates, the next attempt stopped during normal-turn completion (38.3 seconds, one selected failure). Bounded browser evidence showed a connected peer, one speech-start event and three real transcription events; no model request or TTS Speak occurred. Archive fact counts showed an accepted start but no completed input. The source omitted `options.commit_strategy`, selecting Scribe's default manual adapter instead of the milestone's supported automatic `vad` commit profile. Added the explicit provider option for both operational modes. The participant-level `vad` boolean remains separate and controls operational Silero reuse versus benchmark fallback. Also corrected fixture model responses to name the actual `assistant` participant, rather than the copied `agent` name. Log retained at `vxpipe-live-diagnostics-fallback-polling.log`.


Correction after the fourth attempt: the low-level STTSession default does not determine configured-call behavior. CapabilityCatalog chooses `:vad` for inline ElevenLabs selections, and STTSelectionTest explicitly rejects a public commit_strategy option. The fourth attempt failed call-spec validation before admission/provider access (0.4 seconds), so the unsupported option was removed. The third attempt already used automatic Scribe; its missing completion is not diagnosed as manual segmentation. The corrected assistant participant and final persisted profile assertion remain. No successful turn-completion claim has been made.

## Proven microphone discontinuity and focused fix

The diagnostic fallback attempt ended normally as a test failure (38.0 seconds). Real Scribe saw three non-empty partials and **108,800 total PCM bytes**, exactly 3.4 seconds at 16 kHz mono PCM16. Chrome independently reported 170 outbound audio packets and 3.4 seconds of media-source samples. No silence followed the clip: disconnecting the only AudioBufferSource stopped the virtual microphone clock. Thus automatic Scribe had no post-speech silence to finalize; no provider-control change was needed.

Added a continuously connected, zero-valued ConstantSource to the fixture microphone. The focused offline Chrome test now uses an actual local WebRTC pair and measures additional media-source sample duration after the human crop ends. RED: additional duration 0, expected at least 0.2 seconds. GREEN: 1/1 passing with the constant silence source (4.7 seconds). Preserved the human crop unchanged. Real wire diagnostics use a small Console-only production Socket/ScribeSocket delegate, observing only event type/empty flags and aggregate PCM bytes; production decode/send behavior is unchanged. Logs: `vxpipe-live-diagnostics-fallback-wire.log`, `vxpipe-live-microphone-silence-{red,green}.log`.

## TTS credit and tool continuation fixture contracts

After silence continuity was corrected, live Scribe produced a committed segment followed by empty partial and the model/TTS response began. That attempt failed at synthetic audio delivery (`audio_output_failed`, 9.9 seconds). Static verification confirmed 48 kHz mono PCM matches Gateway output; the fixture nevertheless violated production TTSSocket's one-outstanding-frame credit contract by timer-pushing. Changed only fixture delivery to send the next frame after its matching successful wire acknowledgement. The exact branch of the earlier rejection remains unproven, but the next attempt successfully completed normal, pause, barge-base and barge responses.

That next attempt stopped in tool follow-up (32.2 seconds): the fixture incorrectly required every model request in a phase to have the initiating human command/turn IDs. Production CompletionContinuation intentionally creates ContinueAgent with fresh IDs. The fixture now retains the initiating human identity and permits a separate continuation only with an actual engine-origin `tool_invocation_completion` observation for the exercised tool and unchanged room/source/connection/agent metadata. It waits for this continuation before finishing the tool stage. Stored metric assertions still use the initiating canonical human turn. Logs retained: `vxpipe-live-diagnostics-fallback-{silence,credit}.log`.

## Production admin no-run diagnosis

The continuation-corrected call completed five human turns, the real tool completion, one acknowledged agent interruption, and hangup. An initial admin pass hit a CDP execution-context replacement during login; split explicit asynchronous phase polling from native navigation/DOM waits. The next attempt reached the actual call details and diagnostics UI, but found no selectable run (79.5-second timeout). No API/UI success was claimed.

After reviewer corrections, the wire observer delegates to production ScribeSocket **before** inspecting payload metadata, preserving production receipt timestamps. Failure reporting tolerates calls that never reached admission. A bounded diagnostic attempt then established the capture blocker: the real Scribe session acknowledgement contains the expected eight other fields but **omits `commit_strategy`**. RoomService reports zero active sources and `profile_unavailable`; the authorized production API returns HTTP 200 with zero runs. The strict complete-echo capture gate rejects this actual provider acknowledgement. This is not a UI rendering or native Silero failure. No production contract was relaxed by this harness. Evidence is retained in `vxpipe-live-diagnostics-fallback-source.log`; earlier UI attempts are `vxpipe-live-diagnostics-fallback-{tool,navigation}.log`.

## Review follow-up: real terminal call and faithful acknowledgement

Earlier peer disconnects detached the connection but left the prepared call running; their `hung_up` constant was not acceptable terminal-call evidence. Pending harness correction now invokes production `Gateway.CallHangup.request` using the fixture tenant principal, waits for `Calls.fetch_call` to report durable `:ended` plus hangup intent, and only then opens the production admin page. Final inspection independently rechecks that stored terminal state. This uses production lifecycle operations, not fixture DB mutations.

Final profile assertions now compare stored acknowledgement keys with the actual live socket’s echoed field names and require all actually missing fields to remain absent in API output. The configured outer profile must remain `:vad`; the entire API profile must equal persisted data. This preserves both valid eight-field and historical nine-field handshakes without inventing a provider echo. Backend compatibility changes are owned by another agent; live attempts remain held until their focused checks and review pass.

## Real receipt jitter invalidated acoustic clock positions

After reviewed provider-acknowledgement compatibility landed, actual capture attached and persisted one run with five turns. Production hangup reached durable `:ended`; API and admin now displayed the real run. Numeric primary timings remained unavailable with `clock_uncertain`.

One approved bounded diagnostic inspected only eight sample-clock metadata frames from this call's own SourceWorker (no PCM/text). At 16 kHz, consecutive sequences 279/280/281 had timestamps 149358612/149358932/149359252 and 320 samples per frame (20 ms). Receipt offsets were 5673029/5689029/5705029 microseconds: strictly increasing, at 16 ms intervals. The latter two frames were marked clock-uncertain with 5000 µs uncertainty; 190 of 256 retained frames were flagged. SampleClock's `received_offset_us - duration < previous_received_offset_us` condition interprets overlapping receipt-estimated intervals under ordinary scheduling jitter as unusable clock evidence. Actual receipts and sample order did not reverse.

The diagnostic run ended in 34.0 seconds at the honest numeric-endpoint assertion (0 available, expected at least 3). Exact storage/API profile and row comparisons, production UI unavailable values/reasons, expanded interrupted-output evidence, technical-event visibility, and terminal-call checks passed beforehand. Endpoint durations were five nulls, with no available barge duration. Rendered Chrome screenshot inspected: `vxpipe-live-diagnostics-a8db3b8b-9ca8-4072-a939-dc6e1478a23b.png`; log `vxpipe-live-diagnostics-fallback-clock.log`. Backend clock correction is separately owned; no further provider attempt until it is reviewed and green.

## Fallback passed; reuse exposed clean-settlement reset handling

After the reviewed receipt-jitter fix, fallback live acceptance passed: **1/1, 34.9 seconds**. Real automatic Scribe, native room-source Silero, ordinary/pause/barge/tool scenarios, production whole-call hangup, durable storage, faithful API profile/turn identity, and actual production admin row/subrow values all passed. Informational endpoint durations were 2361.448, 1976.898, unavailable, 2422.374, and 2407.297 ms; acknowledged barge-stop delay was 1160.271 ms. These values are measurements, not thresholds. Rendered screenshot inspected: `vxpipe-live-diagnostics-42f48998-a1a1-49d6-8f60-1bcf94fd8366.png`. Log: `vxpipe-live-diagnostics-fallback-clock-fixed.log`.

The unchanged harness then exercised operational reuse separately: **1 failure, 33.9 seconds**. All stored/API/UI and terminal-call boundaries passed, but five endpoints and the barge duration were unavailable. Screenshot `vxpipe-live-diagnostics-a282b002-7e62-4ee7-a64a-d2713e839af4.png` shows `inference reset`, distinct from the repaired clock uncertainty. Static cause candidate passed to backend owner: normal ConversationalSTT settlement emits `provider_turn_settled` as a clean epoch reset, whereas LiveReport currently includes every reset in acoustic invalidation and maps this normal reason to generic `inference_reset`. A focused deterministic report regression can prove that boundary without another live call. Reuse acceptance remains open; no further retry until reviewed fix.

Acceptance scope correction: removed the arbitrary requirement for three finite endpoints. The harness separately reports/checks five actual canonical human turns and the count of available measurements. It requires a finite endpoint on the known pause/resume scenario and a finite barge measurement matching the known interrupted output; exact arithmetic, API/UI, and unavailable reasons remain checked. This demonstrates both measurements without an inference-coverage threshold. Prior fallback already demonstrated both; reuse's all-null result still cannot satisfy the functional measurement gate.

The next reviewed reset-patch reuse attempt measured both primary values: one endpoint **2131.931 ms** and the exact interrupted-output barge delay **147.197 ms** (five canonical turns, 34.1 seconds). It failed an over-specific harness condition requiring the pause/resume turn itself to supply the finite endpoint. The milestone requires that scenario be exercised with faithful timing or unavailable reason; it does not require its timing to be numeric. Corrected the final harness to require at least one fully evidenced canonical endpoint (exact arithmetic), independently retain pause/resume identity plus its explicit unavailable reason when needed, and keep the exact finite interrupted-output barge assertion. The prior run remains recorded as a test failure rather than relabeled green. Further source epoch review is being completed before the final two-mode rerun.

The next reuse call produced five canonical turns and a 168.653 ms barge-in
delay. It failed the endpoint assertion because all five endpoint durations
were unavailable. A subsequent instrumented call passed all assertions in
35.7 s, including a 2061.980 ms endpoint delay and a 143.183 ms barge-in delay.
On four turns with confirmed acoustic endpoints, the provider's accepted
sample count extended 256, 0, 256 and 448 samples beyond the last complete
inference window respectively. Only the aligned turn supplied a numeric
endpoint. The initial partial turn had no complete endpoint. The temporary
worker inspection was removed after this observation. Final verification uses
the ordinary browser, stored report, API and admin UI.
