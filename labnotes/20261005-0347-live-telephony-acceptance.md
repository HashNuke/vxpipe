# Live telephony acceptance

Started read-only harness preparation while the duplex-opening root gate runs. This is
checkpoint E of the existing goal, not a new provisioning or account-wide configuration task.
No call, paid speech/model request, new resource, credential-file read, or env-file edit occurred.

A temporary executable substituted only for the runner's child Mix command and reported
present/missing booleans for all six telephony/Tailscale settings plus `GEMINI_API_KEY` and
`DEEPGRAM_API_KEY`; all eight are present. It used `bin/livetests run --only live_deepgram`
only to select the child loader path: it did not run Deepgram tests or call any provider.
The executable was removed afterward. No values were printed or passed in arguments,
and this selection started no node/Funnel. Presence is not hosted speech authentication.

## Contracts confirmed in the repository

- Console owns the composed test. The live lane must serve `Vxpipe.Gateway.HTTP.Endpoint`
  through Bandit on the runner port, enable real telephony ingress, and require public `/healthz`.
  Existing Gateway REST-only dial tests are insufficient evidence and must not substitute for E.
- Ordinary `Repo` SQL sandbox supports a shared owner for callback/room/archive processes;
  do not pass new database configuration. Restore Engine application provider configuration
  after each selected test; its default model fixture must not silently replace real inference.
- Encrypted test credential options compose `CredentialStore`, `ProviderCredentialStore` with
  an in-memory keyring, `TelephonyServiceStore`, `CallSpecStore`, `CallStore`, `ArchiveStore`,
  and `InspectionStore`. Room startup resolves through `ProviderCredentialSource`.
- Telnyx's platform webhook requires a platform `telnyx` named credential with API key and
  public key, plus a tenant application mapping to the discovered connection ID/outbound number.
  `OperatorTelephonyApplications.create/4` is the existing trusted mapping workflow.
- Twilio uses `account_sid_auth_token` authentication and a tenant service with fixed ingress
  key `vxp-test-twilio`, account connection ID and discovered outbound number.
- Gateway `CallAdmission.configure_telephony/3` supplies the production outgoing connector.
  Supply normal archive options (`enabled: true`, `EctoStorage` writer with repository options,
  bounded queue/retries/drain). `CallEngineOptions.build/1` carries archive, connector and
  credential source into both outgoing and incoming startup.
- Persist and publish an incoming spec for the receiving number and an outgoing spec for the
  dialing service; submit through the authenticated outgoing endpoint exactly once. Observe
  each room's *remote human* final transcription containing the opposite fixed phrase. Own
  generated/delivered transcript alone cannot prove cross-carrier audio.
- `Calls.list_calls/2` and `Calls.fetch_call_facts/3` permit tenant-scoped durable observation,
  including discovering the inbound call by publication. Calls have bounded outcome/timestamps.
- Tests must register cleanup before dialing, bound ring and total room duration, close both
  room processes and assert monitor notifications, then await durable closure. Polling should
  use a bounded receive timer rather than `Process.sleep` or liveness assertions.

## Next checkpoint

Write the smallest local encrypted-publication/harness-boundary test first and run it red,
then implement the Console fixture. Add three individually selectable live cases: Twilio to
Telnyx, reversed direction, and a five-second non-answer with no published receiving route.
Use approved Gemini 3.5 Flash Lite + Deepgram fixed greetings for primary acceptance; Morse
remains optional. Keep the two distinct phrases short and stop after reciprocal evidence.
Do not run existing REST-only calls first or automatically retry a paid case. A failed carrier
attempt is evidence to diagnose locally before any explicitly bounded follow-up.

Default tests exclude the live cases. No E checkbox is accepted by this research.

## Console fixture implementation

- Added a local encrypted-publication test first. Red: missing fixture module, one test/one
  failure, seed 917809, temporary log `vxpipe-live-harness-red.log`.
- Implemented platform speech/Telnyx credentials, tenant Twilio binding, opposing saved and
  published specs, bounded fixed greetings and Gemini 64-token replies. Initial validation
  rejected omitted Deepgram encoding/sample rate; corrected the fixture's public selections.
  Green: one test, zero failures, seed 377419, `vxpipe-live-harness-green2.log`.
- Added assembled production endpoint authentication test next. Red: missing endpoint factory,
  two tests/one failure, seed 963533, `vxpipe-live-endpoint-red.log`. Green: two/zero, seed
  873464, `vxpipe-live-endpoint-green.log`. Neither test starts a room or dials.
- The endpoint carries production repositories/credential source/archive writer and normal
  telephony ingress/backend. Added UsageStore so usage facts cannot block archive draining.
- Added three individually tagged live cases. Dial POST uses `retry: false`; only public health
  checks retry. Answered cases demand the opposite fixed phrase on each call's human participant
  final transcription, require both room monitor notifications after ending the outgoing room,
  and await durable closure/outgoing timestamps. Non-answer has no published receiving route,
  a five-second ring timeout, bounded terminal outcome, no answer timestamp and one call record.
- Register tenant-room cleanup before dialing; also clean up in `after`. Use Registry rather
  than SQL for backup cleanup so room retirement still works if the database test owner stops.
  Existing incoming/outgoing leg room monitors own explicit carrier hangup.
- Default local check: two tests, zero failures, three excluded, seed 441669,
  `vxpipe-live-harness-local.log`. Diff check passed. Selected paid acceptance is pending.

## First selected run: no dial

The Twilio-to-Telnyx selection failed before outgoing dialing, with HTTP 503 and startup
`unsupported_text_to_speech_configuration`. Engine state showed no outgoing task/leg and a
pending fixed greeting. Seed 715599, one test/one failure, four excluded, temporary log
`vxpipe-live-twilio-first.log`. Runner cleanup left the node stopped. No carrier call,
speech request, or hosted inference occurred: TTS runtime construction failed before its wire.

Found an omitted required host setting: Deepgram `maximum_requests` was nil. Added a local
compiled-room startup test using encrypted synthetic credentials and a fake TTS transport,
with a blocking fake outbound connector. The initial test mistakenly held outgoing *admission*,
which also postpones handler preparation; corrected that fixture before the real behavior red.
Valid red: three tests/one startup failure, three excluded, seed 927189,
`vxpipe-live-speech-startup-red-valid.log`. The live fixture now supplies four TTS request slots.
Local green: three tests, zero failures, three excluded, seed 486107,
`vxpipe-live-speech-startup-green.log`. Native fake TTS and the blocked fake dial both start;
no caller media means no greeting/model request. Repeating only the Twilio selection after
this diagnosis and local fix; no automatic retry occurs.

## Dial diagnosis

Second Twilio selection reached beyond speech configuration but returned HTTP 503, seed
572256, one failure/five excluded, `vxpipe-live-twilio-second.log`. Read-only account/number,
Call list and recent Monitor Alerts GETs through the child runner showed an active Full
account, one matching machine number, no recent calls from it and no recent alerts. The
temporary child helper printed only status/count/date/duration/price/error-code fields,
no numbers, IDs, tokens or request/response bodies, and was removed. No Funnel was started
for those GETs. Monitor source: https://www.twilio.com/docs/usage/monitor-alert . These
reads do not establish which internal boundary failed.

Added a production outgoing-connector local test with a simulated carrier, preserving
encrypted service resolution and normal API submission/leg ownership. Red: missing adapter
override option, `vxpipe-live-connector-red.log`. Green: four local tests/zero failures,
three excluded, seed 37499, `vxpipe-live-connector-green.log`. It submits exactly once and
hangs up on room closure. Live cases still use the default production adapter.

Twilio VoiceClient discarded numeric REST rejection codes. Added a safe telemetry event
containing only HTTP status, provider, operation, and an optional positive bounded numeric
error code. Raw body/headers/message/resource IDs never enter it. Adapter results are
unchanged and no retry is introduced. Tests first failed for missing telemetry (eight tests,
two failures, seed 764657, `vxpipe-twilio-rejection-red.log`), then pass (eight/zero, seed
678850, `vxpipe-twilio-rejection-green.log`), including poisoned/non-numeric/oversized codes.
Four Console tests still pass, three excluded, seed 300108, `vxpipe-live-harness-final-local.log`.
The live failure now includes only that bounded rejection and public stored outcome flags.
One further selected Twilio attempt is running to collect the missing reason, not an
automatic redial. All E gates remain open pending actual signed/media/closure evidence.

The third selected Twilio run failed with bounded HTTP 400/code 21215 (dial operation),
and durable flags `failed`/`failed`/submitted true. Seed 909887, six excluded,
`vxpipe-live-twilio-third.log`. Official error reference identifies a Geo Permissions block:
https://www.twilio.com/docs/api/errors/21215 . Read-only GET of the US country resource
confirmed low-risk, high-risk-special, and high-risk-tollfraud flags all false. See
https://www.twilio.com/docs/voice/api/dialingpermissions-country-resource . Its temporary
child helper printed only the country code and three booleans, then was removed.
Requested user approval to enable only low-risk US/Canada dialing, leaving both high-risk
flags disabled, because the approved harness excludes account-wide Geo Permissions changes.
Question acceptance is not approval; no setting has changed. Sent pushnotify and started
only Telnyx-to-Twilio while this independent approval remains pending. No further Twilio
outbound attempt should occur until the permission is enabled.

User explicitly approved low-risk US/Canada dialing. Applied a single-country (`US`)
BulkCountryUpdates POST through the runner child, setting low-risk true and both high-risk
flags false. Response update count was one; a subsequent GET verified exactly those flags.
No other country or account setting changed. Temporary helper removed. This is an explicit
approved exception to the harness restriction on account-wide changes; provisioning remains
unable to alter Geo Permissions automatically. API source:
https://www.twilio.com/docs/voice/api/dialingpermissions-bulkcountryupdate-resource .

First selected Telnyx-to-Twilio attempt timed out waiting for the incoming room, seed 965636,
one failure/six excluded, `vxpipe-live-telnyx-first.log`. Unlike rejected Twilio dials, this
attempt may have placed a paid carrier call. Inspect provider events before repeating it.

## Public ingress diagnosis and first real signed admission

After the approved Geo Permissions update, Twilio accepted the fourth dial, but incoming-room
acceptance timed out (seed 827659, `vxpipe-live-twilio-fourth.log`). Read-only carrier logs
confirmed canceled outbound and busy inbound calls with zero duration. Detailed Twilio events
reported HTTP 502/HTML for early callbacks and the incoming Voice request, then HTTP 503 with
the project-owned processing-unavailable response after leg retirement. Telnyx delivery logs
also showed unsuccessful initiated deliveries and a later 503 hangup. Helpers emitted only
status/date/count/code/field-name or fixed body-category evidence and were deleted.

A signed synthetic Twilio incoming request passed normal encrypted admission over loopback:
five local tests, zero failures, seed 261722. Its public-URL variant also passed (seed 358784),
but that URL resolves privately on this machine. Public DNS via Google's HTTPS resolver gives
Funnel relay addresses instead; the local URL check had not proved internet ingress.
Read-only Deepgram projects and Gemini model requests both returned HTTP 200. One selected
native Deepgram TTS probe streamed real audio and completed, seed 15667; no broad provider
suite ran (`vxpipe-live-telephony-tts-probe.log`).

Added a public-DNS test helper that connects to relay IPv4 addresses while preserving the
original hostname for TLS/SNI and HTTP. Certificate verification remains enabled. Public
synthetic acceptance now covers that path and requires public health before submitting.
An immediate request failed with a transport timeout, seed 133127. Requiring every advertised
relay was too strict: individual relays can remain unavailable while another serves verified
HTTP 200. Bounded readiness chooses a responding public relay; no dial POST retries.
Initial health reports contain only status or a bounded transport atom, never addresses or
request bodies. Default local tests pass: five/zero, four excluded, seed 724508.

A temporary parent process kept this machine's node online during a bounded public TLS/health
probe and the selected test runs, then stopped it. Public health became ready on the third
probe. The public signed synthetic test passed, seed 217713. One further selected Twilio dial
then created the incoming Telnyx room through the production signed platform route, proving
that TELNYX_PUBLIC_KEY matches this account's callbacks. It failed reciprocal remote audio
transcripts (seed 778738, `vxpipe-funnel-stabilization.log`); media/closure and both complete
answered directions remain unproved. No automatic redial occurred. Added bounded failure
diagnostics for public call state, human admission, fact-kind counts and membership of only
the six expected synthetic words; no raw transcripts, IDs or numbers are printed.

Format and warnings-as-errors compilation passed after the public helper. Strict Credo and
unused dependency checks were started; full root suite has not yet run for this checkpoint.

Further read-only carrier evidence for the answered attempt: Twilio reported completed with
zero-second duration and zero price, with Monitor error 31924. Its official reference describes
a WebSocket protocol error: https://www.twilio.com/docs/api/errors/31924 . Telnyx delivery records
show initiated/answered delivered with HTTP 200, then hangup (normal clearing, SIP 200) and
streaming stopped. The attempted Twilio Streams list GET returned HTTP 405; removed that read,
then completed the independent diagnostics. A bounded Monitor-text classifier found no extra
reason words; it does not establish the exact offending frame. All temporary helpers removed.

Default local tests after bounded media diagnostics still pass: five/zero, four excluded,
seed 700659, `vxpipe-live-local-diagnostics.log`. The first five-second unanswered selection
failed public health before publication/submission (seed 743241, one failure/eight excluded,
`vxpipe-live-unanswered-first.log`); no carrier dial was submitted by that case. Tools status
confirmed stopped. Strict Credo passed 1,196 source files; dependency-unlock check also passed.
Started the full default umbrella suite in `vxpipe-live-root-test.log`; no live lane is included.

For the next media attempt, the live fixture additionally observes the existing bounded HTTP
request-stop telemetry. Failure output counts only operation/outcome/status maps, allowing
authentication or upgrade failures to be distinguished without paths, headers, bodies or IDs.
No production HTTP behavior changed. Documentation links/fences verified (155 local links,
zero issues); diff check passed. Engine and Calls root suites have passed while Gateway remains
running; final aggregate evidence will be recorded after the existing process is terminal.

Full root suite completed with one failure: 3,150 tests, one failure, 102 excluded, seed
930118. Engine 1,881/zero and Console 201/zero passed. Gateway 543/one failed its signed
incoming press-1 transfer recovery case with custom-URL waits and destination loss:
`missing source recovery speech` in the shared phone handoff helper. The exact case passes
in isolation using its existing `phone_loss:destination` tag and the same seed (one/zero,
twelve excluded, `vxpipe-phone-recovery-focused.log`). This is not a fix or a passing root
gate. Started a bounded ten-repeat diagnostic of that selected synthetic case; it places
no carrier calls. No implementation change has been made without a reproducible cause.

The selected case passed the initial run plus ten repeats with seed 930118 (eleven executions,
zero failures, `vxpipe-phone-recovery-repeat.log`). No timeout was widened and no assertion
removed. Began a full same-seed umbrella recheck in `vxpipe-live-root-recheck.log` to determine
whether the full-suite failure repeats. The first failed run remains recorded; repetition
is evidence gathering, not a claimed repair. The new default Console code, including bounded
HTTP failure observation, compiled and passed in the first root run.

The same-seed root recheck is still live but has a different failure: Engine's overlapping
transfer/source-cutover test exhausted a 200-iteration busy poll before asynchronous STT
startup reported ready. Unlike its existing five-second native-origin helper, that poll had
no elapsed-time budget or scheduler wait. Replaced the held/failed/reopened cutover polls
with state acknowledgements and bounded ten-millisecond waits inside the same five-second
startup budget used elsewhere in the file. All phase, privacy and overlap assertions remain.
This is test synchronization only; no source-cutover or speech-state-machine behavior changes.
The root failure is the red evidence. A focused same-seed repeat was started after this change.

The overlapping-transfer case passes its initial run plus ten repeats after the polling
repair (seed 930118, `vxpipe-cutover-wait-focused.log`). Started the complete 37-test owning
file. Moved the synthetic loopback HTTP check into the explicit `integration` lane to comply
with the repository's network-test rule; it is still verified with `--include integration`
against the focused Console file, excluding all live-provider cases. Four pure Console cases
remain in the default suite. This tag change skips no failing test.

The owning cutover file passes all 37 tests (seed 930118); focused Console including the local
integration case passes five/zero, four live cases excluded (seed recorded in the local log).
The second full root run is terminal with 3,149 tests/two failures/103 excluded: the already
diagnosed cutover busy poll and the same missing recovery speech in Telnyx's silent-all/cue-loss
phone case. It loaded the cutover tests before their synchronization repair. The common fake
recovery provider was sent a final response without acknowledging its live stream. Added the
existing project-owned delta acknowledgement before completing that same synthetic response;
the recovery speech and audio assertions are unchanged. This makes a stale/cancelled model
stream fail at its actual boundary rather than silently accepting a send to a dead provider.
Started a focused same-seed cue-loss repeat; broad confirmation is still required.

Added Gateway-owned, test-only observation wrappers for HTTP media signature variants and
real socket callbacks. A variant-signature test first failed on missing wrapper, then passed
nine/zero (seed 962007). A malformed-frame observation test first failed on the missing socket
wrapper, then passed ten/zero (seed 506850). The wrappers delegate unchanged to production
Endpoint/Socket logic; alternate URL signatures remain unauthorized. Observations contain only
four signature booleans or bounded event/format/result/close-code fields, never headers,
URLs, identifiers, frame bodies or audio. Live Console uses those wrappers to diagnose the
next single paid call; no credentials or production verifier policy changed.

The initial acknowledged recovery check failed because these phone harnesses configure the
selective fake provider, which did not implement the three-element delta acknowledgement
already supported by the ordinary fake provider. Added that test-only protocol to the
selective provider, preserving the actual emit result. Telnyx cue-loss then passed its initial
run plus five repeats; both complete phone harness files and the media observer cases pass
36 tests/zero failures (seed 930118). This establishes focused evidence, not proof that the
previous full-suite recovery race is resolved. The recovery speech wait was already increased
from two to five seconds during earlier diagnostics; the latest acknowledgement did not
change it. Broader verification remains required.

Media signature observation now rescues lookup/probe exceptions and exits before delegating
to the production Endpoint, so diagnostics cannot make a normally handled request fail.
Started one selected public signed-admission check followed by at most one Twilio self-call,
only if public health and that free admission check pass. The parent owns node shutdown in
all paths; no automatic redial is used.

The selected public synthetic case passed (seed 212949); the single paid Twilio-to-Telnyx
case failed reciprocal transcripts (seed 386272). New bounded observations establish exact
WSS Twilio signature validation, both HTTP 101 upgrades, accepted Twilio mulaw/8 kHz and
Telnyx Opus/16 kHz start events, and incoming media on both sockets. No alternate signature
variant matched. Both sockets later stopped with 1011 after agent/media unavailability.
The first upstream cause is TTS output returning `{:error, :unsupported_audio}` for the
fixture's linear16/24 kHz synthesis. Gateway output validation requires linear16/48 kHz mono.
This is a harness configuration error; the carrier protocol rejection is downstream and
does not justify loosening signatures or frame validation. The six named credentials now
have successful REST/OAuth or real callback/media authentication evidence, while full
bidirectional audio and closure remain unaccepted.

Added an assertion on the actual fake Deepgram wire URL to require negotiated sample_rate
48000. It failed as expected with 24000 (five tests/one failure, seed 677394). Changed only
the configured telephony fixture's TTS sample rate to 48000; started the same five local
cases. No production media-format contract changed. The first temporary parent diagnostic
had captured stderr held open by the background daemon's progress descriptor; interrupted
it cleanly, corrected stderr handling and completed the second run with node shutdown.

The 48 kHz fixture check passes five/zero (seed 687328). The next public synthetic case
also passed (seed 907326), but its single paid Twilio call had no WebSocket observations or
HTTP upgrades and timed out on reciprocal speech (seed 311496). This does not verify or
refute the corrected synthesis path because no carrier media attached. Started a separate,
bounded ten-minute public-relay stabilization diagnostic, requiring all three advertised
IPv4 relays healthy for three consecutive probes before any paid attempt. It issues only
health GETs while waiting and at most one selected self-call if the gate passes. The node
reports Running/online with no health entries. Public A and AAAA records both have three
answers and 300-second TTLs; no DNS result bodies or tailnet peer identities were logged.
The ten-minute limit follows Tailscale's documented public DNS propagation allowance; it
does not establish propagation as the cause of these TLS failures.

Started a full same-seed umbrella recheck after the fixture and local synchronization
changes. Warnings-as-errors compilation, strict Credo and unused-dependency checks pass;
the new root run remains pending.

All three public IPv4 relays became healthy by probe eight; probes eight through ten passed
consecutively. The public synthetic case passed (seed 415361). The following single Twilio
call (seed 368816) carried substantial audio in both directions and yielded three/four final
remote human transcripts, proving that the corrected synthesis path reaches both carriers.
It still failed the distinct greeting check: only `check` from the expected phrase vocabulary
appeared, and both rooms recorded interrupted agent turns. Both sockets remained active until
test cleanup. Concurrent greetings and ordinary barge-in are a plausible explanation, not
a proven root cause; no raw transcript was logged. Changed the fixture's distinct fixed
greetings to the shorter `Alpha.` and `Bravo.` to reduce overlap. Acceptance still requires
each human participant's final remote transcript to contain the opposing distinct greeting,
followed by both natural room/archive closures. No speech/interruption policy was bypassed.
This is a fixture configuration adjustment; the examples in the specification are illustrative.

The brief-greeting local lane passed five/zero (seed 103295). With all relays healthy for
three consecutive probes, the public synthetic case passed (seed 81437). Its selected
Twilio call (seed 142991) transcribed Alpha on the incoming human, and acknowledged on both
humans, but Bravo was absent from the outgoing human. This establishes actual reciprocal
speech with hosted STT/TTS/model use, while the exact marker gate still failed. A peer missing
the first brief greeting during stream startup is plausible; this run does not prove the
timing cause. Adjusted each agent's prompt to answer only with its own distinct marker.
This lets the marker return through ordinary speech after remote startup while preserving
the fixed first message and all human-only proof/closure requirements. It proves reciprocal
marker audio, not that the remote peer heard the very first utterance. Native fixed-opening
once behavior remains covered by A–D's local acceptance. Marker matching now uses whole
normalized words, avoiding substring false positives for the shorter utterance.

The temporary parent can run explicitly selected cases sequentially, at most once each,
stopping after the first failing case and always stopping its node. This avoids restarting
Funnel between the required two directions and non-answer case; it never invokes all live
providers or automatically retries a carrier dial.

The full umbrella recheck is terminal and green: 3,151 tests/zero failures/103 excluded,
seed 930118 (`vxpipe-e-root-current.log`). All 1,881 Engine and 545 Gateway tests pass,
including both previously failing synchronization cases and the two new observer tests.
Console passes 200 default tests; its local HTTP integration remains opt-in and was verified
with the four pure harness cases. The final marker-reply configuration passes all five local
cases (seed 871247). Full-suite success does not establish live acceptance. Formatting,
warnings-as-errors compilation, strict Credo and unused-dependency checks pass; 155 local
documentation links and code fences were checked without issues. The current sequential
live selection has only issued public health GETs so far and will stop after any case fails.

After all relays stabilized, the public synthetic case passed (seed 176395). The next
Twilio-to-Telnyx case (seed 327674) passed reciprocal marker transcripts, then failed before
the hangup proof with `FunctionClauseError` at the second `monitor_room/3`: the previously
fetched incoming durable record still had nil incarnation_id. Records are immutable snapshots;
that value is projected asynchronously and must not supply live monitor identity. No reverse
or unanswered call ran because the sequential parent stopped after this failure. Cleanup
stopped both rooms and the node.

Extracted the existing monitor lookup and added a local signed-incoming assertion using a
durable snapshot with nil incarnation_id. It reproduced the same FunctionClauseError:
five tests/one failure, seed 128760. The helper now obtains the exact live incarnation from
the public `CallEngine.participant_snapshot/3` API before installing its room monitor.
It does not read private Engine state or change durable projection semantics. The local
integration assertion also proves the installed monitor receives DOWN on room cleanup.
Started the five-case green run before any further paid attempt.

The monitor regression passes five/zero (seed 54330); Console's complete default suite passes
200/zero/seven excluded (seed 210099). Formatting and warnings-as-errors compilation pass
after the monitor change. The next sequential parent's public synthetic case passed (seed
855995). Its one selected Twilio case passed reciprocal marker transcripts and outgoing
room DOWN, then missed receiving-room DOWN within ten seconds (seed 201787). It stopped
before reverse/unanswered selection, cleaned up both rooms and stopped the node. No automatic
redial occurred. The three E acceptance gates stay unchecked.

Source review identifies a concrete missing boundary: production
`Gateway.CallAdmission.handle_live_event/5` handles media_started/media only; an ended event
returns telephony_event_not_supported. The incoming Leg forwards authenticated running
events there. The terminal callback therefore lacks a room-ending path, consistent with
prior Telnyx hangup HTTP 503 evidence and the receiving-room timeout. No carrier hangup
delivery query was made for this latest call, so source review establishes the missing
handler but not every detail of the latest carrier timing. No production fix has been
written for this gap. The next checkpoint needs focused red-green tests for signed incoming
terminal events (including before media start), a trusted Engine termination API scoped to
tenant/room/exact incarnation, stale-identity isolation, and ordinary archive closure. Avoid
calling private Engine state or terminating an arbitrary Registry result from Gateway.
Existing agent hangup already uses RoomAuthority's normal stop/supervision path; a carrier
API should preserve that lifecycle with explicit scoped authorization. No new credentials
or account-wide permissions are required for this implementation work.
