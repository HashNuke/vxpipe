# Twilio through the common telephony contract

Status: complete (2026-10-06). Specification review: approved (2026-09-08).

Credential configuration update (2026-09-16): new legs now resolve encrypted tenant service
records; existing owners retain their initialized configuration. The earlier application-scope
lookup/configuration evidence below is historical and superseded. See
[tenant telephony setup](../tenant-telephony-services.md). This changes credential readers only;
this milestone still owns its original carrier/audio acceptance.

Prerequisites: [Telnyx/common telephony slice](telnyx-calls.md), including its tested provider-neutral adapter contract.
Sources: [Common telephony boundary](../../labnotes/20260905-0405-call-definition-design.md#keep-telephony-provider-neutral-and-pin-the-resolved-definition-in-the-room); [transfer and machine behavior](../../labnotes/20260905-0405-call-definition-design.md#transfer-success-and-failure--approved-g8-baseline); [R32](../call-spec-gap-review.md).

## Runnable outcome

Switch a configured telephony service to Twilio and run the same inbound-agent and outgoing-human-transfer scenarios without changing the participant/transfer/media policy schema or room orchestration.

## Specification

- Implement a second adapter for the same receive/dial/adopt/media/accept/end contracts. Resolve vendor details from application/tenant service configuration; do not embed Twilio command payloads or credentials in participants.
- Verify current vendor webhook/control-response/media APIs during implementation; adapt their real flow rather than assuming the first provider's webhook/API sequence. Prove bidirectional media and usable caller/destination audio through Vxpipe mixing before declaring support.
- Gateway adapter authenticates vendor ingress and normalizes provider/session/leg IDs. Calls selects/pins initial call specs and shared admission; active transfers resolve their existing in-memory participant target, never reselect deployment from a phone number.
- Preserve protected initial-variable dialing, explicit destination-leg press-1 acceptance, isolated briefing/optional notice, privacy-before-bridge, total deadline, one bounded permitted source restoration and internal-only technical reasons.
- Use optional provider AMD where configured; machine disconnects attempted leg, unknown waits acceptance without resetting deadline. Duplicate/out-of-order/late callbacks cannot redial, re-admit or complete another transfer. Unknown submission is not remote failure or permission to retry.
- Normalize provenance for media clocks and future usage/request IDs without inventing equivalence across carriers. Shared models/interfaces change only if a genuine common requirement is discovered and covered for both adapters.

## Implementation checklist

- [x] Reuse common telephony contract tests with Twilio fakes; add red cases for vendor-specific verification and callback/media correlation.
- [x] Implement configured Twilio authentication/control/media adapter in proper gateway/provider boundaries.
- [x] Run inbound and outgoing private-transfer acceptance through the existing room mixer and policy barrier.
- [x] Exercise AMD/DTMF/timeout/cleanup and parity with the first adapter.
- [x] Add tagged real-provider tests and document supported transport/control combinations without untested compatibility claims.

## Acceptance and failure checks

- [x] Same portable participant call spec works by resolving another configured service; no provider-specific room logic is required.
- [x] Tampered/cross-tenant media or callbacks reject; duplicates/out-of-order events keep one mapped attempt and no speculative retries.
- [x] Protected-number violations reject before dial; only destination press-1 accepts and briefing remains private.
- [x] Machine/unknown/busy/no-answer/timeout outcomes preserve the common source/cleanup rules and privacy restrictions.
- [x] Live audio works in both directions with correct clock/format mapping; provider disconnect is normalized without blanket multiparty hangup.

## Manual verification

1. Run shared fake-provider conformance scenarios for both adapters.
2. Configure authorized Twilio test ingress/destination and repeat the previous milestone's inbound and private transfer flow.
3. Change only the configured service binding, not room/participant semantics, and compare outcomes.
4. Document any unsupported media/control combination as unsupported rather than bypassing Vxpipe mixing or acceptance.

## Scope boundaries

No automatic cross-carrier fallback, generic provider-specific JSON escape hatch, voicemail delivery, automatic redial, or production calls to unapproved destinations. This slice validates the abstraction with a second provider.

## Completion and evidence

- [x] Demonstrate the runnable outcome and every acceptance/failure check above.
- [x] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [x] Update this milestone, the index checkbox, relevant architecture/user docs, and
  implementation labnote with actual integration and test evidence. Include this evidence
  with the implementation commit requested by the user.

Implementation and acceptance are complete. The live and local evidence below establishes the
supported carrier/media scope; it does not claim every provider failure was observed live.

## Live acceptance continuation (2026-10-05–06)

At the start of this continuation, the outgoing-calls milestone proved real signed ingress,
reciprocal speech and initial call hangup for Twilio and Telnyx. Its initial-call lane did not
complete this milestone's private-transfer runnable outcome or selective multiparty disconnect
contract. The T1–T4 checkpoints below track that continuation; the old REST-only tagged lane
cannot establish those behaviors.

- [x] T1: locally verify an encrypted fixture using the existing controlled carrier numbers,
  portable incoming/transfer participants and bounded private preparation.
- [x] T2: run a selected real Twilio private transfer with remotely heard briefing, real
  destination press-1 and reciprocal post-bridge speech through Vxpipe mixing.
- [x] T3: disconnect only the destination leg; demonstrate caller/room retention and final
  owned-resource/archive cleanup.
- [x] T4: rerun focused conformance and common gates, then reconcile this milestone and index.

During the blocked 2026-10-05 session, T1's pure source builder validated all three specs with one focused
red-green test. Encrypted publication and assembled runtime verification remained pending then.
A new assertion in the signed Twilio harness proves that a destination stop after private
transfer closes only its leg/media and retains the caller/main-room connection. The
14-test Twilio harness passes; the preceding two-carrier/decoder/ingress group passes 55 tests.
These runs used direct Elixir with the existing compiled dependencies because Mix's local
PubSub socket is denied in this sandbox. They are local evidence, not live carrier acceptance
or a replacement for the root compilation/test gates. PostgreSQL connections also fail
with `eperm`; no additional paid call was attempted. T1–T4 stayed unchecked then.

During the blocked session, the selected `live_telephony_transfer` case was implemented in
Console's `test/integration/live_telephony_test.exs`, but could not run then. Its three-room fixture uses
real Deepgram speech and carrier adapters with a deterministic one-shot model fixture,
limiting the case to one caller dial and one transfer dial. Original initial-call cases
retain real Gemini inference. Private destination bindings remain in a test-owned Registry.
Eleven focused component tests pass (seed 466420); the live module compiles directly without
warnings. These checks do not prove encrypted DB publication, real DTMF or live transfer.
Formatting passed then; remaining root gates were blocked by socket denial.

The execution barrier was revalidated on the third consecutive blocked continuation: local TCP
socket creation and Mix.PubSub still failed with `eperm`. At that point the implementation was
ready, but the milestone remained incomplete pending local socket/DB access and real carrier
and common-gate evidence. Extra fake or REST-only runs could not close those requirements.
Permission recovery and successful acceptance follow below.

See [checkpoint labnotes](../../labnotes/20261005-2227-twilio-live-transfer.md).

### Permission recovery and early-input repair (2026-10-06)

Local socket creation, PostgreSQL, and outbound HTTPS now work. The normal Console fixture,
peer, model and encrypted-database group passes 15 tests (six live cases excluded). The first
selected live transfer published all three specs and connected carrier media, then exposed an
early-input error: private destination packets arrived before input routes were allocated.
Gateway interpreted intentionally disabled routes as unavailable media and closed the socket.
A focused test reproduced this before implementation; the repair drops those early packets
only during private preparation and retains failure handling for real input errors.

The regression and signed two-carrier/decoder/ingress group pass 49 tests (seed 302441).
The next selected live run kept destination media connected and recognized a word from the
private notice, but missed the leading Delta marker (seed 827500). The fixture now repeats
the marker in a full sentence at the end of the notice, retaining every live acceptance
assertion. Subsequent playback-complete runs recognized either Delta or the notice's check
marker. The current probe accepts either distinctive briefing word and forbids both at the
caller; no other fixture utterance contains them. It allows 15 seconds for readiness observation
within the unchanged 30-second application deadline. No real press-1, bridge or selective
hangup was claimed at that point.

Compilation with warnings as errors, strict Credo, formatting, the unused-dependency check,
three runner shell suites and Lean build/oracle/replay passed. The selected live rerun and final
default suite remained pending at that point. No additional resources were purchased. See
[resumption labnotes](../../labnotes/20261006-0206-resume-live-transfer.md).

### Selected carrier acceptance (2026-10-06)

The final `live_telephony_transfer` run passes **one test, zero failures, nine excluded**
(seed 918113, 31.2 seconds). It uses the existing two controlled numbers and encrypted three-room
fixture. The destination recognizes a private briefing marker before sending an actual Telnyx
DTMF command; Twilio delivers digit one with the live `inbound` track label. After accepted
handoff, opposing Alpha/Bravo speech crosses both physical carrier calls and Vxpipe's human
bridge. Neither private marker reaches the caller. Exactly one transfer completes and exactly
three calls exist.

An exact Telnyx destination hangup ends that receiving room and the corresponding Twilio
destination leg/media subtree while caller and reception remain attached. Stopping reception
then ends the opposing caller room. All three durable calls and permitted transcript archives
close. The test node and Funnel mapping are stopped. No new resources were purchased.

Live execution exposed and repaired early private-input handling, the peer helper's name/record
identity mismatch, the real Twilio DTMF label, and a mixer default whose 160 ms buffer could not
cover its 300 ms playout delay. The bounded buffer now holds 640 ms while preserving the delay.
The gated destination model sends its post-bridge response through real Deepgram TTS; the
unproven native-speak stimulus is removed. Local failure, duplicate, timeout, privacy and AMD
coverage remains in the signed conformance lane; those outcomes are not all claimed as live
carrier observations. SIP and unidirectional Twilio streams remain outside the supported scope.

Final common gates pass: formatting, warnings-as-errors compilation, strict Credo (1,196 files),
unused-dependency checks, and **3,171 default umbrella tests, zero failures, 104 excluded**, seed
235060. Lean build, oracle and replay verification pass (replay seed 497321). The runner's three
shell suites pass. The two-carrier conformance group passed 50 tests (seed 655566); final speech
and persistence synchronization checks passed 74 tests (seed 235060). T1–T4 and this milestone's
acceptance/completion checklists are complete.

Three default-suite synchronization races were corrected using readiness and queue acknowledgements
and asynchronous terminal-event injection. An intermittent third-participant WebRTC tone observation
reproduced during investigation, then passed twice at its reproducing seed and in both subsequent
full Gateway runs. Its cause remains unproven; no deadline, frequency threshold or production media
behavior was changed to make that observation pass. The investigation and prior failed runs remain
recorded in the [resumption labnote](../../labnotes/20261006-0206-resume-live-transfer.md).

The ten checkpoints below retain the original implementation history. Their outstanding-work
statements describe those checkpoints; the continuation above records current live acceptance.

## Checkpoint 1: honest provider identity

The common admission and persistence contract now permits an absent provider call-session ID while
continuing to require configured connection, call-control, and exact leg identity. This is a genuine
second-provider requirement: Twilio's Account SID identifies the configured account and its Call SID
is both the addressable call resource and exact leg, but it has no distinct counterpart to Telnyx's
call-session ID. The Twilio value remains `nil`; Vxpipe does not copy Call SID into an invented
session field.

Focused red-green evidence covers both the in-memory Calls workflow and the PostgreSQL repository.
The first Calls run rejected the otherwise valid event as `invalid_incoming_telephony_event`. After
normalization accepted the optional value, the persistence run exposed that the Ecto changeset had
temporarily stopped casting the session field while still requiring it; correcting the cast/required
split and applying the nullable-column migration made both provider shapes green. Existing Telnyx
records still require and retain the value supplied by that adapter.

```text
cd apps/vxpipe_calls
mix test test/vxpipe/calls/telephony_admissions_test.exs
# 6 tests, 0 failures

cd apps/vxpipe_persistence
VXPIPE_TEST_DATABASE_URL=postgres://postgres:postgres@127.0.0.1:55433/vxpipe_test \
  mix test test/vxpipe/persistence/telephony_call_store_test.exs
# 5 tests, 0 failures
```

Root formatting, warnings-as-errors compilation, strict Credo, unused-dependency, and all seven
umbrella lanes pass—757 tests with zero failures.

## Checkpoint 2: configured profile and verified incoming event

Configured services now dispatch only their provider-specific credential profile while preserving
one common service envelope. Telnyx validation moved intact into its profile. A Twilio profile
requires an exact Account SID and bounded Auth Token, derives the configured-provider identity from
the account, defaults to the Twilio adapter, and refuses mixed Telnyx credentials. Both profiles
keep secret-bearing adapter/verifier options out of inspection.

The common raw webhook includes an optional exact public request URL and bounded route parameters
without exposing either in inspection. The Twilio adapter's first implemented operation validates
the current form-signature contract and decodes an incoming Voice request. It parses the raw form
with duplicate/size rejection, orders parameters case-sensitively, computes HMAC-SHA1 over the exact
configured URL and fields, and compares the base64 signature in constant time. Only an authenticated
body is normalized, and its Account SID must match the configured profile. Call SID is retained as
control and leg identity, while provider session remains absent. Unsupported Twilio command and
media operations still return explicit errors; the HTTP/TwiML path is not yet implemented.

The tests were initially red at compilation because the common raw webhook did not retain the URL
required by Twilio authentication. Focused configuration, verifier/decoder, Telnyx profile, service
registry, and Telnyx HTTP regressions now pass together:

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/telephony/configured_service_test.exs \
  test/vxpipe/gateway/telephony/service_registry_test.exs \
  test/vxpipe/gateway/telephony/telnyx/adapter_test.exs \
  test/vxpipe/gateway/http/telnyx_events_test.exs \
  test/vxpipe/gateway/telephony/twilio/adapter_test.exs
# 23 tests, 0 failures
```

Root formatting, warnings-as-errors compilation, strict Credo, unused-dependency, and all seven
umbrella lanes pass—761 tests with zero failures.

## Checkpoint 3: synchronous incoming Voice handoff

Gateway now exposes `POST /api/telephony/twilio/:ingress_key/voice` as a raw form route. It resolves
the configured service, checks the exact form content type and one signature header, bounds the body,
and passes the untouched bytes plus the configured public URL through the common adapter. Only an
authenticated, normalized incoming event reaches call admission. A successful production admission
returns Twilio's WSS media URL and the route responds with XML `<Connect><Stream>` TwiML; tampering is
rejected before dispatch.

Incoming activation now has a typed provider-neutral result carrying its media binding, private media
URL, and command submission. Twilio prepares that synchronous result from the Call SID without
issuing or inventing another answer command. Telnyx continues through the same result contract and
discards the URL at its asynchronous event response. Shared ingress configuration moved out of the
Telnyx HTTP handler so neither provider owns the other's runtime setup.

The red HTTP test initially failed to compile because the typed activation result did not exist.
Focused ingress/activation regressions and the complete gateway suite are green. The latter ran with
one test process because two pre-existing media-shutdown assertions use 100 ms deadlines and proved
scheduler-sensitive under the concurrent Membrane suite.

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/http/telnyx_events_test.exs \
  test/vxpipe/gateway/http/twilio_voice_test.exs \
  test/vxpipe/gateway/telephony/incoming_leg_activation_test.exs \
  test/vxpipe/gateway/telephony/media_session_test.exs \
  test/vxpipe/gateway/call_admission_adapter_test.exs
# 19 tests, 0 failures

mix test --max-cases 1
# 183 tests, 0 failures (5 excluded)
```

Root formatting, warnings-as-errors compilation, strict Credo, unused-dependency, and all seven
umbrella lanes pass—764 tests with zero failures.

This does not yet claim live Twilio media. The authenticated WebSocket upgrade, G.711 audio path,
status/AMD/DTMF callbacks, outbound calls, and full private-transfer parity remain pending.

## Checkpoint 4: outbound control and signed progress callbacks

The Twilio adapter now submits one form-encoded Calls API request with HTTP Basic authentication,
configured origin, authorized destination, inline media TwiML, four progress callback events, and
optional asynchronous AMD. It classifies 4xx responses as bounded rejections and network/5xx
outcomes as unknown; neither outcome is retried. Exact-leg cleanup updates only the returned Call
SID to `completed`.

Gateway now exposes a form callback route whose exact internal-leg path is covered by Twilio
signature verification. Provider-specific decoders normalize progress and AMD into the existing
event vocabulary. Unconsumed authenticated statuses are acknowledged without dispatch. The common
outbound owner can adopt a fully correlated answered or terminal status after an unknown create
response, so callback reordering cannot strand a valid call or cause a second dial. Provider,
configured account, internal leg, origin, and destination must all match before adoption.

The HTTP boundary, raw request extraction, credential validation, REST transport, dial form,
hangup command, and callback decoding remain separate responsibilities. The red tests first failed
with unsupported Twilio commands, then with the form callback being parsed as JSON. A later
out-of-order contract test failed with `leg_not_found` until pending-owner correlation accepted a
fully identified progress event.

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/http/twilio_callbacks_test.exs \
  test/vxpipe/gateway/telephony/twilio/adapter_test.exs \
  test/vxpipe/gateway/telephony/outgoing_leg_test.exs
# 22 tests, 0 failures

mix test --max-cases 1
# 194 tests, 0 failures (5 excluded)
```

Root formatting, warnings-as-errors compilation, strict Credo, and unused-dependency checks pass.
The complete umbrella run passes all seven application lanes—775 tests with zero failures.

Live media is still not claimed. The authenticated Twilio WebSocket upgrade, bidirectional G.711
conversion, media DTMF/control, shared transfer-harness parity, and tagged provider verification
remain pending.

## Checkpoint 5: authenticated media ingress and wire normalization

Gateway now exposes `GET /api/telephony/twilio/:ingress_key/media/:token` as a raw WebSocket route.
It validates the upgrade and the `X-Twilio-Signature` computed over the exact configured WSS URL
before consuming the one-time admission token. A forged request therefore receives `401` without
invalidating the legitimate token; successful reuse receives the same bounded not-found result as
any other consumed token. The binding must also match the configured Twilio service identity.

The socket monitors the exact leg owner and pins the first authenticated Stream SID. Separate
decoders validate Twilio's start, media, DTMF, mark, stop, and protocol-control envelopes. Start
accepts only mono `audio/x-mulaw` at 8 kHz and the bound Account SID/Call SID. Media becomes the
provider-neutral PCMU packet with bounded payload, sequence, chunk, and provider timestamp. DTMF
uses gateway observation time where the wire event has no own timestamp. A second start,
cross-call/cross-stream frame, malformed payload, or binary WebSocket frame closes the socket before
room dispatch.

The first HTTP test was red with `404` because no Twilio media route existed. Four decoder behavior
tests were red with the adapter's explicit unsupported-media response, and three socket tests were
red because no socket module existed. The focused wire boundary and full Gateway lane are green:

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/telephony/twilio/media_socket_test.exs \
  test/vxpipe/gateway/telephony/twilio/media_decoder_test.exs \
  test/vxpipe/gateway/http/twilio_media_test.exs
# 9 tests, 0 failures

mix test --max-cases 1
# 203 tests, 0 failures (5 excluded)
```

Root formatting, warnings-as-errors compilation, strict Credo, and unused-dependency checks pass.
The complete umbrella run passes all seven application lanes—784 tests with zero failures.

This checkpoint still makes no live-audio claim. Twilio's wire codec is PCMU, while the available
`membrane_g711_plugin` release implements PCMA only; using it would be incorrect. The next
checkpoint will keep media lifecycle/routing in Membrane while supplying a narrow tested PCMU
codec and fixed 8/48 kHz conversion without FFmpeg. Outbound media/clear handling, shared transfer
parity, and tagged provider verification remain pending.

## Checkpoint 6: bidirectional PCMU Membrane pipelines

Twilio now resolves through the existing provider-neutral media-pipeline set. Its direct playback,
room ingress, and room egress are supervised Membrane pipelines rather than codec work in the
WebSocket or room authority. Inbound raw PCMU is decoded to signed 16-bit mono PCM, converted from
8 to 48 kHz with continuous fixed-factor linear interpolation, aligned to the room clock, and
framed at 20 ms. Authorized direct or mixed 48 kHz PCM takes the reverse path through a bounded
six-sample averaging converter and PCMU encoder; `Membrane.Realtimer` paces exact Twilio media
envelopes containing the pinned Stream SID.

The codec uses standard independent silence/sign/range vectors. The converter carries interpolation
state and partial downsample groups across buffers. Neither depends on a native codec, an external
process, or FFmpeg. Media session setup now passes the authenticated Stream SID to both output
pipelines while leaving the Telnyx path unchanged.

The three pipeline tests were first red because the modules did not exist. The common session test
then failed with `unsupported_media_provider` until Twilio was added to the closed pipeline
selection and the Stream SID reached its output sinks. The socket egress test also failed until the
WebSocket handled the internal encoded-media message.

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/telephony/twilio/pcmu/codec_test.exs \
  test/vxpipe/gateway/telephony/twilio/pcmu/rate_converter_test.exs \
  test/vxpipe/gateway/telephony/twilio/audio_ingress_pipeline_test.exs \
  test/vxpipe/gateway/telephony/twilio/audio_egress_pipeline_test.exs \
  test/vxpipe/gateway/telephony/twilio/audio_output_pipeline_test.exs \
  test/vxpipe/gateway/telephony/twilio/media_session_test.exs \
  test/vxpipe/gateway/telephony/twilio/media_socket_test.exs --max-cases 1
# 16 tests, 0 failures

mix test --max-cases 1
# 216 tests, 0 failures (5 excluded)
```

Root formatting, warnings-as-errors compilation, strict Credo, the complete 797-test umbrella
suite, and the unused-dependency check also pass.

This proves bidirectional codec conversion and provider-neutral live-session routing with local
deterministic media; it is not tagged real-provider evidence. Explicit `clear` handling for
Twilio's remote playback buffer, full transfer-harness parity, and the guarded live lane remain
pending.

## Checkpoint 7: interruption clears remote playback

Direct playout and room-mixer egress now receive a small provider-neutral playback-clearer
contract. Pipeline replacement synchronously terminates the old supervised producer before it
clears the provider buffer and launches a replacement. This order prevents a paced frame from the
old pipeline racing behind the clear command. The Twilio implementation sends the exact `clear`
event with the authenticated Stream SID; the existing transports that do not yet expose a remote
clear action use an explicit no-op implementation.

The first focused run had three intended failures: the Twilio clearer did not exist, and neither
direct interruption nor a room policy transition invoked a clearer. The green tests prove
stop-clear-start ordering at both shared lifecycles, invalid target rejection, and the exact Twilio
wire command. The real Twilio media-session test additionally interrupts queued speech and observes
that command through the same socket owner selected by the configured pipeline set.

That combined run also exposed an old test-fixture race: all direct-output tests used the same
Registry key while their spawned pipelines unregistered asynchronously at test teardown. Giving
each test a unique connection identity removed the collision without sleeps or weaker lifecycle
assertions. Two consecutive focused runs and the complete Gateway lane pass.

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/media/audio_output_test.exs \
  test/vxpipe/gateway/media/room_audio_egress_test.exs \
  test/vxpipe/gateway/telephony/twilio/playback_clearer_test.exs \
  test/vxpipe/gateway/telephony/twilio/media_session_test.exs --max-cases 1
# 13 tests, 0 failures (two consecutive runs)

mix test --max-cases 1
# 218 tests, 0 failures (5 excluded)
```

Root formatting, warnings-as-errors compilation, strict Credo, the complete 799-test umbrella
suite, and the unused-dependency check also pass.

Full private-transfer harness parity and tagged live-provider verification remain before this
milestone can be marked complete.

## Checkpoint 8: outbound private-transfer parity

The existing outbound human-transfer slice now runs unchanged for both configured carriers. One
provider-neutral scenario builds the call spec, resolves the configured phone service,
constructs normalized media/DTMF/AMD events, and supplies the same participant and transfer
semantics to the room. Carrier-specific test code is limited to credentials, exact provider
identities, and the fake adapter/socket messages at the transport boundary.

For Twilio, the slice proves that the agent's transfer tool starts one exact outbound leg, keeps the
destination in transfer-preparation admission, plays the briefing only through the destination's
PCMU Membrane output, refuses press-1 from another process, and waits for both destination-bound
acceptance and completed briefing before committing. After commit, the source agent terminates, the
destination moves to main admission with live room ingress and mix-minus egress, and repeated DTMF
cannot commit again. A separate provider-paired case proves that configured machine detection ends
only the attempted destination leg, reports failure to the source, and leaves that source active.

The first Twilio run reached the real Twilio output pipeline but failed because the shared test
socket handled only the Telnyx delivery message. Extending that test boundary to observe both
provider message types made the same assertions green. The scenario construction was then moved out
of the assertion module, reducing that module from 613 to 362 lines while preserving the green
behavior.

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/telephony/outbound_phone_transfer_test.exs --max-cases 1
# 4 tests, 0 failures
```

The full Gateway lane passes 220 tests. Root formatting, warnings-as-errors compilation, strict
Credo, all 801 umbrella tests, and the unused-dependency check also pass.

The full signed Twilio inbound-to-outbound harness and guarded tagged provider verification remain.
This checkpoint does not claim either one.

## Checkpoint 9: signed inbound-to-outbound Twilio harness

The complete deterministic call harness now uses the same provider-independent call plan and room
runtime setup for Telnyx and Twilio. Thin carrier wrappers supply only credential and identity
differences. The Twilio test adapter delegates request-signature verification, webhook/media
decoding, and synchronous incoming-answer preparation to the production adapter; it fakes only
outbound network control so no real destination is dialed.

One test now sends a correctly signed form request through the real Twilio Voice route, receives
the generated bidirectional-stream TwiML, and proves a duplicate request neither claims nor answers
the call twice. It authenticates and consumes the incoming WSS media token, pins the Call and Stream
SIDs, starts the real PCMU Membrane pipelines, and attaches the caller to main room media. After
that initial admission, the test disables its backing call store to prove the active room does not
depend on further synchronous admission storage.

The same call then drives an STT turn into the agent, executes the configured transfer tool, starts
one outbound Twilio leg, authenticates its separate media socket, and keeps it in isolated transfer
preparation. Destination DTMF accepts the attempt, but commit waits until the private briefing
finishes. The source agent then exits, the human destination reaches main admission, both human
participants remain joined, and the destination receives Twilio PCMU room output through its
original pinned Stream SID.

The provider-independent scenario extraction preserved the existing Telnyx full-call harness. The
combined call-harness and outbound-leg regressions pass:

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/telephony/twilio_call_harness_test.exs \
  test/vxpipe/gateway/telephony/telnyx_call_harness_test.exs \
  test/vxpipe/gateway/telephony/outgoing_leg_test.exs --max-cases 1
# 13 tests, 0 failures
```

This completes deterministic private-transfer parity. A guarded tagged test against Twilio itself
is still required before checking live audio or completing this milestone.

Gateway verification passes all 221 default tests with five integration tests excluded. At the
umbrella root, formatting, compilation with warnings as errors, strict Credo over 601 source files,
all 802 tests, and the unused-dependency check pass.

## Checkpoint 10: guarded real-provider control lane

An `:live_providers`/`:live_twilio` test now exercises the production Twilio Calls client against an
explicitly authorized destination. The lane remains excluded by default. When selected, it
requires `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_TEST_FROM`, `TWILIO_TEST_DESTINATION`,
and `TELEPHONY_TEST_PUBLIC_URL`; `bin/livetests run` discovers the machine's provisioned numbers
(Twilio calls the Telnyx test number) and public origin and supplies them. The test builds the
per-call status callback and `wss://` media URLs under that origin with the gateway's own Twilio
route shapes. The
test submits one call with the configured media and
callback contract, validates the returned Call SID, and schedules an exact-call completion action.

The currently supported Twilio boundary is deliberately narrow:

- Inbound control is a signed form-encoded Voice request answered synchronously with
  `<Connect><Stream>` TwiML.
- Outbound control is the Calls resource with signed progress callbacks, optional asynchronous
  answering-machine detection, and exact Call SID completion.
- Media is bidirectional WSS with mono 8 kHz `audio/x-mulaw`; Vxpipe consumes start, media, DTMF,
  mark, stop, and connection-control messages and emits media plus playback clear.
- The gateway's Membrane pipelines convert between that wire format and signed 16-bit mono 48 kHz
  room PCM. SIP, unidirectional `<Start><Stream>`, and other Twilio media products are not claimed.

Ordinary Mix execution excludes this guarded live lane and does not load the live-provider
environment. The original control-only checkpoint recorded:

```text
cd apps/vxpipe_gateway
mix test test/integration/twilio_voice_api_test.exs
# 0 tests, 0 failures (1 excluded)
```

This test proves only that the provider accepts the configured control request when explicitly
run. It does not by itself observe a provider WebSocket or establish audible bidirectional media.
The existing deterministic socket, codec, Membrane, room-mixing, interruption, and complete-call
harness tests cover those project-owned boundaries. At that checkpoint, an authorized carrier
call confirming audible ingress/egress and isolated leg cleanup remained outstanding. The
selected automated self-call above now establishes those live observations.

Local verification passes formatting, compilation with warnings as errors, strict Credo over 601
source files, all 802 umbrella tests in the serial lane, and the unused-dependency check. Gateway
contributes 221 passing default tests with six integration tests excluded.

## Specification review

Reviewed independently by milestone_review_a on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Approved initial draft; shared contract order and separate vendor verification, media/acceptance/failure parity sufficient.
This is specification evidence only. Implementation and runtime verification are tracked
separately in the completion checklist and continuation above.
