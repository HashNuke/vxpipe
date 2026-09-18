# Twilio through the common telephony contract

Status: implementation in progress. Specification review: approved (2026-09-08).

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
- [ ] Live audio works in both directions with correct clock/format mapping; provider disconnect is normalized without blanket multiparty hangup.

## Manual verification

1. Run shared fake-provider conformance scenarios for both adapters.
2. Configure authorized Twilio test ingress/destination and repeat the previous milestone's inbound and private transfer flow.
3. Change only the configured service binding, not room/participant semantics, and compare outcomes.
4. Document any unsupported media/control combination as unsupported rather than bypassing Vxpipe mixing or acceptance.

## Scope boundaries

No automatic cross-carrier fallback, generic provider-specific JSON escape hatch, voicemail delivery, automatic redial, or production calls to unapproved destinations. This slice validates the abstraction with a second provider.

## Completion and evidence

- [ ] Demonstrate the runnable outcome and every acceptance/failure check above.
- [ ] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [ ] Update this milestone, the index checkbox, relevant architecture/user docs, and
  implementation labnote with actual test/browser/integration evidence in the implementation commit.

Implementation is in progress. Do not mark this slice complete until all checklist and acceptance
items have evidence.

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

An `:integration`/`:twilio_live` test now exercises the production Twilio Calls client against an
explicitly authorized destination. The lane remains excluded by default and additionally skips
unless `VXPIPE_TWILIO_LIVE=1`. When enabled, it requires `TWILIO_ACCOUNT_SID`,
`TWILIO_AUTH_TOKEN`, `TWILIO_TEST_FROM`, `TWILIO_TEST_DESTINATION`,
`TWILIO_TEST_WEBHOOK_URL`, and `TWILIO_TEST_MEDIA_URL`. The two URLs must be public TLS endpoints
owned by the operator running the test. The test submits one call with the configured media and
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

The guarded lane compiles and skips safely in this checkout because no live-test credentials or
authorized numbers are configured:

```text
cd apps/vxpipe_gateway
mix test test/integration/twilio_voice_api_test.exs --include integration
# 1 test, 0 failures, 1 skipped
```

This test proves only that the provider accepts the configured control request when explicitly
run. It does not by itself observe a provider WebSocket or establish audible bidirectional media.
The existing deterministic socket, codec, Membrane, room-mixing, interruption, and complete-call
harness tests cover those project-owned boundaries. The remaining milestone acceptance check is an
authorized manual carrier call confirming audible ingress and egress plus isolated leg cleanup.

Local verification passes formatting, compilation with warnings as errors, strict Credo over 601
source files, all 802 umbrella tests in the serial lane, and the unused-dependency check. Gateway
contributes 221 passing default tests with six integration tests excluded.

## Specification review

Reviewed independently by milestone_review_a on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Approved initial draft; shared contract order and separate vendor verification, media/acceptance/failure parity sufficient.
This is specification evidence only; implementation and runtime verification remain unchecked.
