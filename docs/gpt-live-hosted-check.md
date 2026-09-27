# GPT-Live hosted acceptance check

Status: opt-in local harness added; no hosted call has been run. This is checkpoint
F's final opt-in interoperability gate in
[the milestone](milestones/gpt-live-speech-to-speech.md).

## Decision

Run one tagged, explicitly enabled integration lane against the real GPT-Live
WebSocket using the existing `GPTLiveSession` and speech session boundary.
The repository-wide [live provider test plan](live-provider-tests.md)
distinguishes this direct protocol check from a configured-service call. The
manual phone pass must use the effective tenant or platform service selected
through the normal call path.
Feed three committed, locally synthesized 24 kHz mono PCM16 phrases. The two
test sessions can each reseed once after an incidental connection loss, so the
theoretical maximum is four sessions, below the plan cap of five. Fixed test
calls submit at most 462,720 PCM bytes (9.64 seconds of voice) with no retry
submitting input: each fixture is submitted once via `submit_fixture`, and the
reseed path appends history then submits one greeting fixture with no
resubmission loop. Each test has a 120-second timeout. A test-only transport
forwards provider frames unchanged
to the adapter and reports only event types to the test. A separate manual
phone pass over a real Twilio or Telnyx leg checks backchannels, interruption,
and speakerphone echo.

The lane is excluded by default. Select it with Mix's `--only live_openai`
filter; `OPENAI_API_KEY` is required when it runs. Merely setting a tenant
credential or running the default umbrella suite never starts this lane. The
hosted run requires explicit billable authorization before selecting the tag.

## Automated evidence

The first test records whether an idle socket emits audio (boolean only),
holds input and requires the documented busy push outcome before release,
submits a short spoken turn, admits and acknowledges received audio, supplies
caller speech during a reply, requests the same yield the room would request
through the direct session, awaits completion and settles that admitted burst
without asserting `:interrupted`, requires the following response and audio,
awaits its completion and settles it, then stops the socket transport without
a protocol close while idle and waits for both a replacement `session.started`
and provider readiness after appending representative caller and agent
history. It checks resumed speech on that
session and settles final output before exit. The second test drives a
delegated `ping` function and requires spoken output after its result, then
settles that output before exit. The test transport never sends raw frames,
transcripts, audio or credentials to the observer; its notifications carry
event types.

The hosted run must additionally record whether an idle socket emits audio
(boolean only) and any startup or documented-format handling error. The
direct Session harness checks documented wire PCM format only (24 kHz mono
PCM16 framing) and cannot establish the room's 24 kHz conversion quality.
Carrier audibility and room conversion quality remain manual phone
observations below.

OpenAI's [WebSocket guide](https://developers.openai.com/api/docs/guides/voice-websockets)
requires `session.start` first and `session.started` before audio; its sample
uses raw mono PCM16 at 24 kHz. The [session guide](https://developers.openai.com/api/docs/guides/live-conversations)
specifies mute/unmute acknowledgments. The [delegation guide](https://developers.openai.com/api/docs/guides/live-delegation)
requires a result for each pending function call before continuation.

## Manual phone evidence

Use a configured test number and the same GPT-Live call spec. Record the
carrier, date, device, and sanitized outcomes for:

1. A brief acknowledgment while the agent speaks, which should not cut off
   its answer.
2. A clear interruption during the answer, which should make the agent yield.
3. Speakerphone playback, which should not make the agent answer its own voice.
4. Hold and release, followed by another short utterance on the same session.
5. Forced reconnect, followed by a response grounded in the published text
   history.
6. The room's 24 kHz conversion quality and carrier audibility, with any
   startup or format errors heard on the phone leg.

Do not retain raw call audio or full transcript in the labnotes. Record exact
latency or conversion observations only when measured by the test; an
unmeasured impression remains an observation, not a numeric acceptance claim.

## Alternatives considered

- The fake socket and Morse duplex suites give deterministic local protocol
  coverage, but cannot establish real service or carrier interoperability.
- Exposing a fake transport through public provider configuration would weaken
  the API-key-only setup contract; keep injection private to tests.
- A second hosted TTS service would add a credential and billable dependency.
  Generate the short input fixture locally instead.

## Verification

The live file compiles and its two tests are excluded by default, including
when `--include integration` is used. `--only live_openai` selects both; with
`OPENAI_API_KEY` unset, they fail before connecting. The synthetic tool
configuration validates locally without a network call.
The authorized hosted results will be recorded here and in the checkpoint
labnotes when available. The unresolved items in
[the duplex profile](sts-duplex-profile.md) remain unverified until the
corresponding hosted or phone observation is recorded.
