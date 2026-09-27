# GPT-Live hosted check

Date: 2026-09-26. Starting revision: `68fa5a56`; Package 8 transfer work is
still uncommitted.

## Research and decisions

- Read Package 9 in `docs/gpt-live-completion-plan.md` and the F acceptance
  checklist. The tagged hosted check is opt-in, requires explicit billable
  authorization, and is capped at five sessions and three minutes of voice.
  A real Twilio or Telnyx leg is also required for manual backchannel,
  interruption, and speakerphone-echo observations.
- Official OpenAI GPT-Live WebSocket documentation specifies a primary
  connection to `/v1/live/sessions`, `session.start` as the first message,
  `session.started` before audio, raw mono 24 kHz PCM16 input/output, and
  input muting acknowledged by `session.input_audio.muted` / `unmuted`.
  Delegated function calls require a result for each pending call before
  `response.create`. Sources:
  https://developers.openai.com/api/docs/guides/voice-websockets,
  https://developers.openai.com/api/docs/guides/live-conversations,
  https://developers.openai.com/api/docs/guides/live-delegation.
- `ffmpeg` on this host has a `flite` filter and can synthesize a short spoken
  PCM fixture locally. A test command produced 96,720 bytes of 24 kHz mono
  PCM16 for a short phrase without using another hosted service or credential.
  The default integration lane will skip the hosted test when the explicit
  run flag or `OPENAI_API_KEY` is absent. The key is absent in this shell; its
  value was not read or logged.

## Local harness

- Added two tagged integration tests with a 120-second timeout and skip unless
  both the explicit run flag and API key are present. The test uses the normal
  `GPTLiveSession` and a private real-WebSocket wrapper that forwards frames to
  the adapter while reporting only event types to the observer.
- Three `flite` PCM fixtures (greeting 132,000 bytes, interrupt 124,560,
  ping 74,160) are mono 24 kHz signed little-endian PCM16. Fixed test calls
  submit 462,720 bytes total (9.64 seconds) with no retry submitting input:
  each fixture is submitted once via `submit_fixture`, and the reseed path
  appends history then submits one greeting fixture with no resubmission
  loop. Two test sessions can each reseed once after an incidental
  connection loss, so the theoretical maximum is four sessions, below the
  plan cap of five. No hosted connection has been made.
- `mix test --include integration test/integration/gpt_live_hosted_test.exs`
  compiled the test helper and skipped both tests without the run flag/key.
  Repeated after the review fixes with the flag unset: two tests, zero
  failures, two skipped. The default test lane excludes this tagged file
  entirely; it does not execute the hosted assertions.
  The pure synthetic `GPTLive.new/1` tool configuration validated with
  `MIX_ENV=test mix run --no-start`. The first attempt with default `mix run`
  failed because this umbrella's development runtime could not load the
  persistence keyring; the test-environment no-start command was the local
  workaround.
- Two independent subagent reviews of the prior fix found (a) an unsettled
  second-turn output slot before the forced reconnect, (b) a wrong
  three-session budget, (c) overstated room conversion evidence, and (d) a
  stale review-in-progress line; this loop addresses all four. No hosted run
  was made (run flag absent, key absent/unread), with no hosted output and
  no credentials recorded.
- Follow-up harness fix: carry admitted `OutputTurn` handles in explicit
  await state, settle on `:output_completed` before admitting a later burst,
  and settle final output before exit; exercise talk-over via interruption
  audio plus `interrupt/2`, await completion/settle, then require the next
  response, await its audio and completion/settle, and only then force the
  reconnect while idle (no mid-reply reconnect claim; direct-session
  room-yield simulation; real service/carrier interruption still pending);
  wait for provider `ready?` plus the new wire after `session.started` with
  a deadline instead of trusting the socket event alone; assert busy push
  while hold is active; report idle `output_audio.delta` as a boolean in a
  bounded 1-second window; close the forced-loss socket with
  `GenServer.stop/1` rather than killing the pid. The direct Session
  harness checks documented wire PCM format only (24 kHz mono PCM16
  framing); room 24 kHz conversion-path quality and carrier audibility
  remain manual phone observations.

## Pending

- Arrange explicit billable authorization and a live phone participant for
  the final hosted acceptance run. Record sanitized observations only.
