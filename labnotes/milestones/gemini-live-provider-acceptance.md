# Gemini Live provider acceptance

Status: in progress. The user authorized configured `gemini-3.8-live` and real
Google/carrier checks on 2026-10-07, including a later explicit approval for the
long call. This supersedes the older Google selection deferral for this slice.
The broader [agent STS milestone](agent-speech-to-speech.md) remains incomplete.

Prerequisites: the implemented Google STS adapter and protected openings in
[agent speech-to-speech](agent-speech-to-speech.md), the registry/credential
contracts in [provider integration packages](provider-integration-packages.md),
and the [live telephony harness](../../docs/development/live-telephony-harness.md).
Reference: [GPT-Live acceptance](gpt-live-speech-to-speech.md).
Design sources: [semantic speech contract](../../docs/speech-provider-contract.md),
[Google speech integration](../../docs/google-speech-integration.md),
[protected openings](../../docs/protected-agent-openings.md).

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
- [x] Diagnose the additional Gemini phone regression (seed 502758): repair
  Telnyx sample-clock conversion, pending-opening input protection and peer
  readiness. The final repeated phone evidence is recorded below; the broader
  long-call acceptance remains open.

Live evidence: thirty consecutive full hosted selections pass, 90 tests with no
failures. Seven naturally omitted opening transcripts are independently recognized
as Alpha from captured PCM; every run also verifies the subsequent turn. Each
selection includes an additional independent Deepgram opening check even when
Gemini provides text. The initial streaming-recognition probe did not reliably
finalize a short clip; the final test-only helper uses finite Nova-3 recognition
of unmodified 24 kHz PCM, without expected-word hints, retries or longer deadlines.
Its five local request/error boundary tests pass.

Evidence is recorded in [the checkpoint labnote](../20261007-1616-gemini-opening-transcript.md).

### Carrier clock and startup handshake (2026-10-07)

Design review (separate from implementation evidence): the authenticated Telnyx
16 kHz Opus stream uses sample-clock timestamps, observed advancing 320 per
20 ms packet. Conversion belongs in Gateway's packet source; the room clock,
playout delay, buffer capacity and STS input protection retain their contracts.
The barge-in fixture must start its exchange from the receiving model's audible
Ready opening, with the counter waiting for input. This establishes receiver
readiness through the real carrier path rather than using a short Alpha trigger
that can finish while that model starts. The independent fixed-opening round-trip
still requires remote Alpha, Bravo and Charlie. No extra timer, retry or runtime
verification model is introduced.

Use a generated Ready opening for that readiness signal. A native callback trace
captured GPT's fixed-opening verifier rejecting an output fragment in the
receiver's prelude, before barge-in could start. The barge-in contract requires
remotely heard Ready, counting, overlap and a stopped reply; it does not require
an additional strict fixed-opening verification on its peer. The round-trip case
owns fixed-opening acceptance. A focused fixture red/green establishes the
generated prelude and explicit Ready instruction for both tested providers.

The same review found an allocation boundary that must honor the existing opening
contract: a pending fixed/generated first message protects caller input before
the opening command starts. Initialize that gate from the room's FirstMessage
state, retaining continuous silence, dropped turn-based PCM and physical
playback settlement. Wait-for-input allocations remain open. This belongs to the
common capability, independently of Google or the phone transport.

- [x] Reproduce the original silent Gemini barge-in exchange and compare b5500c30.
- [x] Gateway red/green for two sample-clock packets becoming consecutive room PCM.
- [x] Console red/green for a provider-independent receiver Ready handshake.
- [x] Common capability red/green for pending-opening input protection; affected
  capability, duplex and room suites pass 122 tests with zero failures.
- [x] Repeated Gemini phone pairs, existing GPT-Live phone cases and hosted Gemini.
  Final shared selection: 4/0, seed 690869. Further Gemini pairs: 2/0 with seed
  502758 and 2/0 with seed 839293. Hosted Gemini: 3/0 with independent Deepgram
  output confirmation. All temporary probes are removed.
- [x] All root and Lean gates; temporary probes removed and exact diff reviewed.
  The clean final default run passes 3,269 tests with zero failures and 114
  exclusions (seed 44264), including Gateway 572/0. Formatting, warnings-as-errors
  compilation, strict Credo, unused dependencies and Lean build/oracle/replay pass.

The clock fault predates c7b232b8: numeric probes find it in the baseline too.
It accounts for mixer overflow but repairing it alone does not repair the silent
STS exchange. The paired readiness trace places the receiving GPT model's ready
event only 263 ms before Gemini's opening completes; no Alpha is recognized.
Input remains closed during startup. The barge-in fixture now makes the receiver
initiate the exchange after its own startup. See
[the diagnosis labnote](../20261007-1746-gemini-phone-regression.md)
for unsuccessful runs and subsequent acceptance evidence. Long-call acceptance
remains a separate open gate.

Broader default verification also exposes the previously recorded native WebRTC
handoff intermittence: changing-listener adoption, terminal release-deadline
progress and repeated AI transfers fail in separate full runs. Their owning
handoff suite subsequently passes 67 default cases with zero failures (seed
44264, one integration exclusion). Temporary diagnostic output is removed;
no handoff runtime contract, timeout or assertion is changed. This does not
establish a cause or a repair of those intermittent failures.

The 2026-10-08 user follow-up prioritizes human-caller calls with human or agent
counterparts and transfers to either type. It adds no runtime participation
limits. The five-participant listener-reconnection investigation is deferred.
The deadline-closing bypass now has owning red/green and repeated native proof;
the earlier listener-re-entry audio-loss cause remains unresolved. Evidence lives in
[the owning transfer milestone](transfer-readiness-and-wait-sounds.md#webrtc-transfer-follow-up-2026-10-08).
Run Gemini's phone ten-minute acceptance after these WebRTC repairs are verified.
The later approved hosted longevity slice below is independent of telephony and
does not require those WebRTC repairs.

### Hosted session longevity (2026-10-08)

Design review, before implementation: Google's context limit and socket lifetime
are separate. Enable server-side sliding-window compression; replace local
seven-minute renewal/nine-and-a-half-minute expiry with `goAway`-driven rotation
using the latest safe private handle. Continue input while rotation is pending;
retain one unsent ordered command only during actual replacement setup. Preserve
the five-second setup budget and all caller/model/tool/playback fences. A clean
attributable later exchange can clear old ambiguity; unqualified ends cannot.
Exactly zero microphone PCM does not manufacture an unresolved caller obligation.
Missing/unsafe handles still fail explicitly; unsupported history reconstruction
cannot silently start a new conversation. No dependency or shared-room contract
change is needed. Details and rejected alternatives are in
[Gemini Live session lifecycle](../../docs/gemini-live-session-lifecycle.md).

Follow-up wire-contract design review, before the corresponding fixes: the real
endpoint sends `turnComplete` without `interactionStatus`, and its session tokens
are periodic. Keep the latest non-revoked token; completed work with omitted status
can authorize same-allocation resumption, while origin cutover still requires
explicit idle. Never treat generation completion or a token alone as quiet proof.
The hosted marker probe confirms that an initial token restores subsequently
remembered context, rather than a local initial-state snapshot.

Retirement sends WebSocket close, closes transport explicitly after peer ack, and
waits for monitored termination before replacement. Google can still reject resumed
setup briefly with code 1008 because its old client remains registered. Only this
specific private reason retries after the rejected socket terminates, inside the
original five-second budget. All other rejection is fatal; held input and the
original deadline remain unchanged. No raw close reason, wait or fresh context is
introduced. Local reds precede each change.

The user approved an eighteen-minute **hosted, Gemini-only** run. Its tags are
`live_long` and `live_long_google_gemini_live_hosted`; never ordinary provider or
Gemini tags. It exchanges real caller audio and credited replies while streaming
microphone frames continuously, requires replies past fifteen minutes, and
requires an actual successful resumed connection. If Google has not already
rotated, the test injects one goAway notification at seven minutes; server expiry
timing is not a project-owned test input. Handles, reconnection and continuing
speech remain real, and the controlled trigger is reported explicitly. Existing
reply/setup bounds remain unchanged. This does not establish long carrier playback acceptance.

- [x] Red/green setup compression, continued pending input, held unsent command,
  obsolete timer immunity and clean-exchange ambiguity recovery: ten initial reds.
- [x] Red/green digital silence preserving the checkpoint: two further reds;
  every nonzero sample keeps the prior unresolved-input guard.
- [x] Additional wire-contract red/green: omitted status, retained periodic
  token, peer-close acknowledgement plus termination, and the precise active-session
  rejection. Keep caller-final, stale-idle, playback, tools and private-status guards.
- [x] Owning Google codec/session/controller group and local socket integration
  are green. Default selection excludes both explicitly tagged hosted checks.
- [x] Preserve the user-owned Console long-fixture and bounded lifecycle
  diagnostics; include their owning fixture assertions with this checkpoint.
- [x] Hosted context-retention probe: one real resumed connection, remembered
  word and credited output, 30.7 seconds, seed 431707. The observed single temporary
  code-1008 rejection resolves on the next attempt inside the original budget.
  Clean final selection also passes in 30.8 seconds, seed 107378, with the real
  transport and no temporary wire diagnostics.
- [x] Hosted eighteen-minute acceptance: 72 received replies, 50,776 microphone
  frames and one successful resumed connection; 1080.7 seconds, seed 485926.
  The test controls one goAway notification at 420 seconds; real replacement
  setup acknowledges at 421 seconds and replies continue through eighteen minutes.
- [x] All five root gates and Lean verification for this lifecycle checkpoint:
  3,292 default tests, zero failures, 120 exclusions (seed 492336); focused
  Google/socket group 198/0 (seed 70174); Lean build/oracle/replay passes
  (seed 231893). Final Gateway is 577/0 and Console is 221/0. Earlier local
  transfer intermittence remains recorded without claiming a runtime repair.

Red/green, diagnostic runs and final acceptance are recorded in
[the longevity labnote](../20261008-0220-gemini-session-longevity.md).

Initial hosted evidence: the first eighteen-minute run produces 72 completed
replies but records no rotations. Its observer captured a nil provider PID before
setup readiness, so it cannot establish rotation evidence. Short controlled probes
then expose the omitted status, discarded periodic token and active-client setup
rejection. Temporary wire/close diagnostics are removed; the final long selection
records a controlled notification and genuine successful resumption. It proves
continuity across completed-exchange boundaries; it does not claim a naturally
observed provider expiry or long carrier playback.

The earlier long phone stalled in four runs around 367–502 seconds without a
provider error. The adapter's pending rotation rejected thousands of audio
frames, and latched ambiguity blocked renewal. The current slice repairs those
local lifecycle contracts; it does not claim that every separate phone or
provider-history gate has passed.

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
  guard avoids guessing which caller owns late text. Long phone acceptance stays
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
  [the labnote](../20261007-0824-enable-gemini-live.md).

## Reproduction commands

Run all real-provider checks through `bin/livetests run`; it owns private env
loading. These selections keep the long lane separate:

```shell
bin/livetests run --only live_gemini apps/vxpipe_call_engine/test/integration/gemini_live_hosted_test.exs
bin/livetests run --only live_telephony_sts_gemini apps/vxpipe_console/test/integration/live_telephony_test.exs
bin/livetests run --only live_telephony_sts apps/vxpipe_console/test/integration/live_telephony_test.exs
# Explicit hosted selectors; excluded from ordinary Gemini/provider selection.
bin/livetests run --only live_gemini_resumption apps/vxpipe_call_engine/test/integration/gemini_live_hosted_long_test.exs
bin/livetests run --only live_long_google_gemini_live_hosted apps/vxpipe_call_engine/test/integration/gemini_live_hosted_long_test.exs
# Separate long phone gate; hosted longevity is verified independently.
bin/livetests run --only live_telephony_long_google_gemini_live apps/vxpipe_console/test/integration/live_telephony_test.exs
```

Adapter backlog/credit/caller-control failures belong to ordinary Google tests.
Playback-duration and sink-responsiveness regressions belong to the common STS
suite with a controlled provider/sink. The live lane proves upstream wire and
carrier behavior and exposes the remaining qualified-attribution dependency.

## Follow-up (2026-10-07)

- `ambiguous_input`: a competing caller onset no longer fails the session. The earlier caller
  and the next final are settled without text; the room treats an empty final as settled
  evidence. See [the controller doc](../../docs/google-sts-controller.md). Red tests in the Google
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
