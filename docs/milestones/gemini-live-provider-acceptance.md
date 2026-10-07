# Gemini Live provider acceptance

Status: in progress. The user authorized configured `gemini-3.8-live` and real
Google/carrier checks on 2026-10-07, including a later explicit approval for the
long call. This supersedes the older Google selection deferral for this slice.
The broader [agent STS milestone](agent-speech-to-speech.md) remains incomplete.

Prerequisites: the implemented Google STS adapter and protected openings in
[agent speech-to-speech](agent-speech-to-speech.md), the registry/credential
contracts in [provider integration packages](provider-integration-packages.md),
and the [live telephony harness](../live-telephony-harness.md).
Reference: [GPT-Live acceptance](gpt-live-speech-to-speech.md).
Design sources: [semantic speech contract](../speech-provider-contract.md),
[Google speech integration](../google-speech-integration.md),
[protected openings](../protected-agent-openings.md).

## Approved contracts and design review

Reviewed before implementation, 2026-10-07: Call Engine owns configured speech
selection and private tenant-key resolution; Providers declares capabilities;
Console owns configured call publication and real carrier test fixtures. Reuse
Google's existing API key and STS adapter. Accept only `gemini-3.8-live`, voice
and supported turn control in public options. No fallback model or exposed key.
Add no new dependency or transport owner. Preserve full regulatory opening
playback, drop STS caller PCM during it, and convert output into the phone sink.

Gemini declares room-owned barge-in, so its phone interruption must record a
room interruption rather than GPT-Live's provider-owned overlap outcome. A
second GPT-Live STS agent provides actual speech during the count; a text-agent caller
cannot reliably do so. The long session trades Ping/Pong over the same carrier
pair and remains excluded by default and all ordinary provider tags. Run it
only with its explicit long tag. The user approved its execution separately.

Rejected alternatives: substituting a general text model or chaining STT/TTS
would not exercise Gemini Live; increasing wait bounds would conceal faults;
adding provider tags to the long call would accidentally authorize billed soak
runs. Hosted evidence establishes only the scenarios actually run, not every
pending tool/history/transfer contract in the parent milestone.

## Discovered runtime tasks

- [x] Preserve caller input and interruption while a native sink push is blocked.
  The shared STS mailbox red timed out under fake-sink backpressure. Owned tasks
  isolate delivery while the exact channel credit remains withheld; fencing
  retires that credit without resurrecting old output.
- [x] Compact small wire-packet bursts within the existing response PCM budget.
  Live failure telemetry captured `stage: :audio, reason: :audio_overflow`.
  A pure Google response-owner red rejected packet seventeen. Compact only one
  response's pending data, preserving order, sixteen chunks and the 131,072-byte
  chunk limit. Keep full-budget overflow fail-closed.

Design review of these discoveries, 2026-10-07: packet boundaries carry no
response identity; compaction is confined to one response and retains the byte
bound. Blocking transport delivery belongs to an owned task, with exact credit
and generation fencing left in the capability/channel. Rejected alternatives
are queue/time-bound increases and dropping audio. Provider-specific buffering
belongs to pure Google tests; shared responsiveness and duration settlement
belong to the common STS suite across supported sample rates.

- [x] Settle provider PCM duration independently from padded phone playback.
  A live trace captured `:invalid_playback` after valid opening output and
  generation completion. Native egress pads to 20 ms packets; the provider
  settlement bound counts original samples. Preserve the actual physical
  completion fence and transport estimate while capping provider settlement
  at accepted source PCM duration. A partial-frame controller red must prove
  transcript completion and the next turn survive.

- [x] Select the response-start Google profile at configured startup. Direct
  hosted PCM works with response starts; the legacy configured phone profile
  failed during its opening. Require the profile through a focused startup red.
- [x] Preserve the Google allocation after genuine provider-reported caller onset:
  fence its local output while awaiting Google's actual interruption boundary.
  A focused controller red reproduces the allocation dying at that onset.
  Keep an unrelated manual cancel fail-closed because the wire has no standalone
  history-neutral cancellation command; never synthesize user activity.
- [ ] Diagnose and repair the real phone failure before long-session acceptance.
  Opening, round-trip and barge-in now pass. The approved long call ended
  around two minutes while Ping/Pong was active. Capture its lifecycle cause
  and reproduce it locally; preserve explicit failure for unsupported history
  or manual cancellation operations.

## Tasks and acceptance

### Fixed opening transcript omission (2026-10-07)

Design review: Gemini may complete correct fixed-opening audio while omitting
output transcription. The user approved playing that completed bounded waveform
without runtime verification or expected-text substitution. The adapter continues
rejecting present mismatched/incomplete words, interruption and overflow. The
capability must preserve the exact opening's physical playback fence and publish
no agent transcript when it has none. This does not relax ordinary-response or
generated-opening transcription contracts. Tagged tests use existing Deepgram
recognition of actual PCM when Gemini text is missing; dependencies remain within
Call Engine's existing speech boundary. No timeout increase is permitted.

- [x] Provider red/green for missing transcript in both Google response profiles;
  retain mismatch, partial text, interruption, overflow and empty-audio rejection.
- [x] Capability red/green for protected physical playback, no invented transcript
  and a working subsequent turn.
- [x] Repeated hosted Gemini runs, including independent Deepgram confirmation.
- [x] All root/Lean gates for this checkpoint: 3,266 default tests, zero failures,
  114 exclusions (seed 576967), plus formatting, warnings-as-errors compilation,
  strict Credo, unused dependencies and Lean build/oracle/replay.
- [ ] Additional Gemini phone regression: the Telnyx pair's two cases fail to
  hear the expected opening/count (seed 502758). Both rooms remain running and
  no Google failure is recorded; bounded mixer diagnostics show many buffer
  overflows. The cause is not established. Do not claim carrier acceptance.

Live evidence: thirty consecutive full hosted selections pass, 90 tests with no
failures. Seven naturally omitted opening transcripts are independently recognized
as Alpha from captured PCM; every run also verifies the subsequent turn. Each
selection includes an additional independent Deepgram opening check even when
Gemini provides text. The initial streaming-recognition probe did not reliably
finalize a short clip; the final test-only helper uses finite Nova-3 recognition
of unmodified 24 kHz PCM, without expected-word hints, retries or longer deadlines.
Its five local request/error boundary tests pass.

Evidence is recorded in [the checkpoint labnote](../../labnotes/20261007-1616-gemini-opening-transcript.md).

### Configured provider acceptance

- [x] Red/green configured Google selection, exact model/options validation,
  manifest discovery and existing saved-key startup; enable runtime settings.
- [x] Direct hosted real-Google test (`live_providers`, `live_gemini`), with
  credited PCM, transcription, completion and subsequent-turn behavior.
- [x] Red/green provider-selectable phone fixtures preserving existing GPT cases.
- [x] Real phone Alpha/Bravo/Charlie round-trip (`live_telephony_sts_gemini`).
- [x] Real phone barge-in (`live_telephony_sts_gemini_barge_in`), including
  actual room interruption and a spoken stopped reply before thirty.
- [ ] Separately tagged long call (`live_long`,
  `live_telephony_long_google_gemini_live`); prove continuing audio and live rooms.
- [x] Render the service catalog to verify the advertised Google STS badge.
- [x] All five root gates and Lean verification; review exact diffs and preserve
  unrelated work. The user authorized committing this checkpoint after verification.

## Verification evidence

- Configured selection, private-key startup and owning fixture/API checks pass;
  the catalog advertises Google STS. Frontend: 219 tests, type check and lint pass.
  Rendered Chrome review covers desktop and mobile.
- Original controller duration reds are now covered by eight common STS cases
  across 8/16/24/48 kHz, without a network dependency. The pure Google burst
  test checks byte order, bounded chunks and full-budget overflow. The relevant
  Google/common STS/startup group passes 260/0 (seed 472509).
- Direct hosted microphone and fixed-opening/subsequent-turn checks pass, 2/0
  in 8.3 s (seed 95203). Real phone round-trip and barge-in pass, 2/0 in 35.1 s
  (seed 681262), including the room interruption and stopped response.
- Fresh shared carrier regression passes all four Google/OpenAI round-trip and
  barge-in cases, 4/0 in 81.0 s (seed 990382).
- The approved ten-minute call failed at its 120 s check (seed 305445); prior
  checks showed recent Ping and both rooms live. A diagnostic rerun captured
  `activity_start: ambiguous_input`: the earlier ended caller still lacks its
  independent final transcription. The ordinary Google controller test already
  requires this fail-closed boundary. Correcting the long receiver's unrelated
  Bravo opening preserves it (seed 133655, stopped after 37 s).
  Qualified caller association remains an open parent dependency; retaining the
  guard avoids guessing which caller owns late text. Long acceptance stays
  unchecked. No timer was raised.
- Static root gates pass. The first default run found twelve Morse manual-clock
  fixture races with asynchronous delivery and two obsolete Google-gating
  assertions. The affected three suites pass 63/0 after fixes (seed 566185).
  Final umbrella: 3,246 tests, zero failures, 112 exclusions (seed 912062),
  including Call Engine 1,923/0 and Gateway 571/0. `bin/verify-lean` builds all
  four jobs, finds no oracle drift and passes the conformance replay (seed
  128278). Changed Markdown links and index counts pass review. Public test
  tools have been stopped; unrelated Wrangler labnotes remain untouched.
- Detailed red/green evidence and discarded diagnostic hypotheses are in
  [the labnote](../../labnotes/20261007-0824-enable-gemini-live.md).

## Reproduction commands

Run all real-provider checks through `bin/livetests run`; it owns private env
loading. These selections keep the long lane separate:

```shell
bin/livetests run --only live_gemini apps/vxpipe_call_engine/test/integration/gemini_live_hosted_test.exs
bin/livetests run --only live_telephony_sts_gemini apps/vxpipe_console/test/integration/live_telephony_test.exs
bin/livetests run --only live_telephony_sts apps/vxpipe_console/test/integration/live_telephony_test.exs
# Explicitly approved long call; currently reproduces ambiguous_input.
bin/livetests run --only live_telephony_long_google_gemini_live apps/vxpipe_console/test/integration/live_telephony_test.exs
```

Adapter backlog/credit/caller-control failures belong to ordinary Google tests.
Playback-duration and sink-responsiveness regressions belong to the common STS
suite with a controlled provider/sink. The live lane proves upstream wire and
carrier behavior and exposes the remaining qualified-attribution dependency.

## Follow-up (2026-10-07)

- `ambiguous_input`: a competing caller onset no longer fails the session. The earlier caller
  and the next final are settled without text; the room treats an empty final as settled
  evidence. See [the controller doc](../google-sts-controller.md). Red tests in the Google
  controller and room STS suites. Live phone re-verification is blocked: Twilio's API reports
  the account as not active.
- Fixed-opening verification failed live sessions when the transcript followed
  `generationComplete` or lacked punctuation. Both fixed with red tests; verification now waits
  for the transcript until the turn completes and compares words.
- Open: Gemini sometimes sends no output transcript for the opening at all (3 of 26 direct
  runs). Independent Deepgram transcription of the held audio returned "alpha" each time, so
  the openings were spoken correctly and only the transcript was missing. The session still
  fails closed there; the policy (play, retry once, or fail) needs a user decision.
- Phone lanes now dial Telnyx -> Telnyx (Twilio's account is inactive): Gemini round trip and
  barge-in (2/2) pass.
