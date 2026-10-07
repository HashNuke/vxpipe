# Stream wait sounds; keep Gemini calls alive on missing caller finals

## Scope

User decisions (2026-10-07): choose what is best for the caller's experience for wait-sound
playback and implement it; verify the Codex Gemini Live work (`8a37fbff`) and fix any issue
it found, including long Gemini calls failing with `ambiguous_input`.

## Wait-sound player

Cause established earlier (see `labnotes/20261006-2344-gpt-live-phone-scenarios.md`): the player
sent one 20 ms frame as its own playback segment and waited for that segment to complete
before the next. Sinks play one turn at a time, so each frame paid a round trip with nothing
queued: audible gaps on a busy server, and a 250 ms transfer cue took up to 1,024 ms, ending
calls when failed-transfer recovery missed its 750 ms budget.

Decision: one output turn per run, five frames (100 ms) ahead of real time scheduled from the
run start; pause/stop interrupt the sinks and use the reported played duration as the cursor;
cues finish once and complete after playback and drain. Rejected: raising the recovery budget,
larger segments, pushing until sink backpressure (the phone output queues 10 s), multi-turn
sinks. See `docs/wait-sound-streaming.md`.

Red tests first (`wait_sounds/player_test.exs`): queued window in one turn, exact pause via
interrupt, streamed cue with one finish, immediate stop. Old per-frame tests were rewritten to
the same intents. Room tests (`opening_audio_room_test.exs`, `call_lifecycle_room_test.exs`)
now expect the wait to be interrupted rather than played out when readiness or the opening
notice arrives. Gateway `human_transfer_webrtc_test.exs` pauses by counting accepted frames
(a `:sys` debug hook receives the process name, not its state) and asserts recorded cursors
are retained.

Evidence: player file 20/20; Call Engine suite 1,926 tests, 0 failures. Transfer cue step
259 ms unloaded (previously 265 ms with per-frame gaps), and `OutboundPhoneTransferTest`'s
machine-detection cases went from 7/10 failing on a saturated 4-core machine to 0/10. With all
cores saturated by spin loops, the 250 ms cue still takes about 830 ms: every frame is queued
ahead, and the remaining delay is the real-time media pipeline starved of CPU.

## Readiness push follow-up

`AI handoff gates MCP and local tools` failed 1/3: its hook waits for the transfer collector's
next tools probe, but readiness notifications can let the collector see tools ready before the
hook is installed, after which tools are never probed again. The test now refreshes the
room's readiness collectors after installing the hook. 4/4 runs of all four variants passed.

## Gemini `ambiguous_input`

Codex's commit records long Gemini calls failing at `activity_start: ambiguous_input`: a caller
turn without an input transcription (noise, cut-off speech) followed by the next turn made the
provider fail the session, ending the call, rather than guess whose late final arrives next.

Decision: never end a call over transcript attribution. The earlier caller is settled with an
empty final, resumption is marked ambiguous, and the new caller's first final is settled empty
as well because it may be the earlier caller's late final. External turn control follows the
same rule. The room treats an empty final as settled evidence, not text.

Red tests: Google controller "a competing caller onset settles the missing final without text
and keeps the call" and the external variant (session previously shut down); room "an empty
final settles the caller turn without publishing a transcription" exposed that an empty final
would have crashed the room (`SpokenHistory.confirm_user/2` rejects empty text). All pass;
188 Google/controller tests and 64 room STS tests pass.

## Codex review

Reviewed `8a37fbff`: Google STS registration and settings validation, `public_options`
normalization, async sink delivery keeping one channel credit, fenced-output credit release,
padded-playback settlement, provider-turn-control interrupt fencing, burst compaction within the
byte budget, failure telemetry. No defects found besides `ambiguous_input`.

## Gemini fixed-opening verification

Verifying Codex's work against the real service, the direct hosted test "configured fixed
opening and subsequent turn" failed 2 of 8 runs with `:session_failed`; telemetry showed
`stage: :fixed_opening, reason: :unverified_opening`. Temporary logging (removed) found three
real-world orderings for the fixed opening "Alpha.":

1. Audio and `generationComplete` arrived before the output transcript, which then followed.
   Verification ran at generation completion and failed. Fix: hold the audio after generation
   completes and verify when the transcript arrives or the turn completes. Red test: "verifies
   a transcript that follows generation completion" (both response-start profiles).
2. The transcript arrived as "Alpha" (no period). Fix: compare words case- and
   punctuation-insensitively, keep rejecting wrong or extra words as fragments arrive, and
   publish the author's exact text once verified. Red test: "verifies the words, not
   punctuation".
3. No output transcript at all, before or after `turnComplete`, although the audio played
   (3 of 26 runs). The user suspected prompting. Saving the held audio of those three
   openings (temporary instrumentation, removed) showed about 0.5 s of two-syllable speech
   each, and an independent Deepgram transcription returned "alpha" for all three. Gemini
   spoke the opening correctly; only its output transcription was missing, so the fail-closed
   check rejects correct openings. Policy (retry, play, or fail) is still the user's decision.

## Phone lanes blocked

`bin/livetests run --only live_telephony_sts ...` stopped before dialing: Twilio's API returned
HTTP 401 "account ... is not active". The Gemini phone round trip, barge-in and long session
(which exercise the `ambiguous_input` fix over a real call) could not run.

## Telnyx-only telephony (2026-10-07)

Twilio's API returned HTTP 401 "account is not active", which stopped every telephony run
during resource discovery, before any call, even for tests that only used Telnyx. The user
asked for Telnyx to carry every telephony test that is not about Twilio itself.

- `bin/livetests` provisions a second Telnyx number (exact tag `vxp-test-<machine>-b`, same
  Voice API application) and exports `TELNYX_TEST_TO`/`TELNYX_TEST_DESTINATION`. Twilio is
  required only for Twilio selections; otherwise its errors are reported and the run continues.
  Carrier error text no longer prints the Twilio account SID. Shell suites written red first.
- The fixture maps the `telnyx-b` endpoint to the `live-telnyx` service and registers Twilio
  only when its settings are present. Default carrier, GPT-Live, Gemini, barge-in, long-session
  and unanswered cases dial Telnyx -> Telnyx; Twilio round trips and the Twilio transfer carry
  `live_twilio`.
- The user approved buying the second number (+16182609966). Live results: Telnyx -> Telnyx round
  trip passed; GPT-Live and Gemini round trips passed; Gemini barge-in 2/2; GPT-Live barge-in 1/2
  plus one run where a GPT-Live session failed about 31 s in and the room correctly ended the call.
