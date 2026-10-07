# GPT-Live phone scenarios

## Scope

Checkpoint F's remaining hosted phone scenarios for GPT-Live, as live provider tests:
interruption over a phone leg, speakerphone echo, and a session-length check (run only
with explicit approval because it is long and billed). Tool, reseed and the other
checkpoint A residual items were judged covered elsewhere; hold/release is deferred.

## Interruption over a phone leg (done)

Test: `GPT-Live yields when the phone caller speaks over its reply` in
`apps/vxpipe_console/test/integration/live_telephony_test.exs`, tags
`live_telephony_sts` and `live_telephony_sts_barge_in`. Fixture scenario `:barge_in` in
`ConfiguredTelephonyFixture.sts_sources/4`; fixture shape is covered by
`configured_telephony_transfer_fixture_test.exs`.

Run: `bin/livetests run --only live_telephony_sts_barge_in apps/vxpipe_console/test/integration`

Design iterations, in order, and why each changed:

1. GPT-Live dials and counts after the receiver's Delta; a text-agent receiver answers
   everything with Delta; assert `agent_turn_interrupted` in the GPT-Live room. Never
   passes: GPT-Live has `barge_in: :provider`, so its yield is `AgentTurnCompleted`
   with outcome `:overlapped`. The interruptions seen belonged to the text receiver.
2. Same, asserting `:overlapped`. The receiver's own room interrupts every reply on the
   next number's onset, so GPT-Live hears nothing mid-count (run 5: five receiver
   interruptions, GPT-Live heard one Delta).
3. Protected receiver opening as the overlap ("please stop counting now", which cannot be
   interrupted). GPT-Live's opening starts about 3 s after answer while its session
   starts, so it heard the request before counting and never counted (runs 6, 7). Run 6
   did show one `:overlapped` GPT-Live turn and an "Echo" answer (transcribed as
   "Héctor"), so single-word answers are unreliable for STT; use "I have stopped".
4. Text receiver answering numbers with "Stop." and other speech with "Okay." Counting
   then works (run 12, one to fifteen and on) but each "Stop." is interrupted before
   it plays.
5. Final: a second GPT-Live answers the receiving number (`wait_for_input`), says Ready
   after Alpha, and talks over the count at three. It owns its barge-in, so the room
   does not cut it.

Results with the final design: runs 15, 17, 20 and 21 passed. Run 19 stopped at "six"
and said "I have stopped" but recorded `:overlapped` on the receiver's turn (the
interjection fell between numbers); the assertion now accepts an overlapped turn in
either room. Run 18 never heard the receiver's Ready. Run 16 lost the dialing GPT-Live
session mid-call; the room ended the call with `agent_unavailable`.

## Barriers and workarounds

- Funnel relay warm-up exceeded 300 s on relay 185.40.234.55 twice tonight, and once
  tailscaled registration took 31 s and the start failed. Workaround: `bin/livetests
  tools:up` once, then `run` reuses the running node. Stop it with `tools:down`.
- Room facts are the only reliable view of what each side heard; `print_heard/3` prints
  timestamped finals, completed-turn outcomes and interruptions on failure.

## Observation for the failed-opening work

Run 14: the dialing GPT-Live capability stopped about 5 s into the call, before its
opening. The room cleared the capability and kept the call silent for 40 s with no
failure fact. GPT-Live session failures collapse to `:session_failed` and the crash
report is redacted. A temporary, uncommitted log of decoded events (runs 17-19, then
reverted) showed only `session.started` and `session.instructions.appended` besides
audio/transcript traffic, with no failure in those runs. Recorded in the GPT-Live
milestone next to the speech-to-speech failed-opening task. Reproduced and fixed later the
same day; see "Review findings fixed" below.

## Open

- Speakerphone echo needs a loopback receiver. Neither carrier offers an echo verb;
  options are a test-only echo media endpoint behind an extra Funnel path, or a
  test-only echo STS provider for the receiving room. Awaiting a decision.
- Session length: no documented limit; a bounded long call needs explicit approval.

## Review findings fixed (2026-10-07)

User instruction: prove each defect with a failing test, fix it, prove it fixed.

- Failed text opening: two red tests in `opening_audio_room_test.exs` (caller text after
  the failure, and text queued during the opening). Fix: `AgentOutput.failed/4` calls
  `FirstMessage.complete/2`. Decision taken here: release protection and continue; the user
  may choose to end the call instead.
- STS agent lost while starting: red test in `room_authority/speech_to_speech_test.exs`.
  Exploration in `outgoing_call_room_test.exs` showed the capability does not exist at dial
  time (it starts after callee media attaches), so the window is reproduced on the room
  module with a bound, not-ready capability. Fix: `handle_unavailable/3` notifies
  connections with `:agent_unavailable` and drops the monitor.
- STS opening cut by a hold: red test in `gpt_live_fake_socket_test.exs` (after release the
  provider received `<<0, 0>>` silence instead of the caller's `<<7, 0>>`). Fix:
  `Output.fence_output/2` ends the opening. Not reproduced: an opening that never produces
  audio at all.
- Mono 16-bit assumption: closed without code; the descriptor contract rejects other STS
  output formats.

## Flaky opening tests (2026-10-07)

The committed `opening_audio_room_test.exs` failed 7 of 20 solo runs (always the protected
opening tests from `465d563c`, at the first wait after attach) and 7 of 10 runs with four
CPU-bound processes on this 4-core machine.

- Ending the new tests' rooms made no difference (6 of 20 failed), which ruled out leakage.
- A first attempt raised the Call Engine `assert_receive_timeout` to 1 s. The user rejected
  that as hiding the cause, and it was reverted.
- Timestamped tracing of 200 openings (temporary logging, removed) found two causes.
  Speech resources still connecting at the first readiness probe were only noticed at the
  collector's next 100 ms poll: openings started at 102-107 ms, a latency live calls had
  too. And the first test in each test VM paid lazy module loading (median 50 ms).
- Fixes: owners push readiness changes through `Readiness.Watch` so the collector re-probes
  at once (see `docs/readiness-change-notification.md`), and the test helper preloads
  modules as a release does. After: all 200 traced openings started within 10 ms.

## Long session (2026-10-07)

`a GPT-Live phone call stays live for the whole long session` (tags `live_long`,
`live_telephony_long_openai_gpt_live`; minutes from `VXPIPE_LIVE_LONG_SESSION_MINUTES`,
default 10). First run failed after two minutes in the harness, not the call: the Ecto sandbox
owner's default ownership timeout (120 s) reclaimed the connection. The setup now uses the
test's timeout. Second run passed: 10 minutes, 26 pings heard, both calls running throughout.
Gemini Live cannot run over a configured call yet (`CapabilityCatalog.speech_adapters/1`
lists only Morse and GPT-Live for speech-to-speech).

## Gateway flakes (2026-10-07)

The full suite showed one Gateway failure per run, a different test each time. All predate
this work (reproduced with the readiness change stashed: 8 of 10 saturated runs failed).

- `RoomAudioEgressTest` / `OutputArbiterTest`: the egress stopped with a non-shutdown reason,
  so OTP formatted a crash report of its state inside the dying process: 12-20 ms unloaded,
  up to 142 ms loaded, before its exit. Stopping with `{:shutdown, ...}` exits in about 1 us.
  Saturated runs went from 10 of 10 failing to 0 of 10. Restart is `:temporary` and only the
  tests matched the exit reason.
- `OutboundPhoneTransferTest` machine-detection cases (7 of 10 saturated runs failed): after a
  failed transfer, recovery must finish within 750 ms or the room stops with
  `:handoff_recovery_failed`, ending the call. Step timing showed everything except the
  recovery cue completes in under 40 ms; the 250 ms cue took 265 ms unloaded and up to 1,024
  ms loaded. Cause: `WaitSounds.Player` sends one 20 ms frame, closes it as its own playback
  segment and waits for that segment's completion before building the next, so per-frame
  round-trip latency accumulates (13 round trips for the cue) and output can gap under load.
  A timeout increase was measured only to see the distribution and reverted; the fix is a
  bounded window of queued frames with exact played-offset tracking. Awaiting the user's go-ahead.
