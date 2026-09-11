# Twilio phone calls

## Scope and current-provider research

Milestone 18 must run the existing provider-neutral incoming-call and private human-transfer path
through Twilio without changing participant definitions or room orchestration. Docker packaging and
whole-call retention remain outside this work and behind the user-requested post-milestone-22 review
hold.

Current Twilio documentation was checked on 2026-09-11. Incoming Voice webhooks are form-encoded
requests which must receive TwiML. Bidirectional media uses `<Connect><Stream>` over WSS. Its wire
format is fixed mono `audio/x-mulaw` at 8 kHz; inbound messages include connected, start, media,
DTMF, mark, and stop, while outbound control supports media, mark, and clear. A returned mark is the
playback acknowledgement for a previously queued media/mark pair. Request authentication uses
`X-Twilio-Signature`, HMAC-SHA1 over the exact public URL plus sorted form parameters. The initial
WebSocket upgrade must be signature-checked too.

Outbound calls use the form-encoded Calls REST resource with HTTP Basic authentication. The call's
`Url` supplies TwiML for its bidirectional stream; `StatusCallback` supplies initiated, ringing,
answered, and completed progress with a `SequenceNumber`, and async AMD supplies `AnsweredBy`.
Unknown command outcomes remain no-retry. We will select async `MachineDetection=Enable` only when
the configured service enables detection, then wait for the existing explicit press-1 acceptance
after a human/unknown result. Media/AMD stream-count interaction must be verified in the live lane.

The first genuine common-contract gap is provider identity. Twilio supplies Account SID and Call
SID but no distinct equivalent of Telnyx's call-session ID. Account SID is the configured provider
connection identity; Call SID is both the addressable call-control resource and exact provider leg.
The optional session field must therefore remain `nil` for Twilio instead of copying the Call SID
and falsely claiming three independent identifiers. Exact comparison still includes the optional
field, so a carrier that supplies one cannot lose it.

Implementation checkpoints planned from this evidence:

1. Make provider session identity optional across common admission/persistence/media contracts.
2. Add provider-specific configured-service validation and Twilio form-signature/webhook/TwiML
   ingress without adding Twilio data to participant definitions.
3. Add no-retry REST dial/end operations and exact status/AMD correlation.
4. Add an authenticated media socket and Membrane G.711 pipelines. The released
   `membrane_g711_plugin` implements PCMA only, while Twilio requires PCMU, so it cannot be used for
   this path. Keep the pipeline lifecycle in Membrane and implement a narrow tested PCMU codec plus
   fixed 8/48 kHz conversion rather than introducing FFmpeg.
5. Reuse the full provider-neutral private-transfer harness for parity, then add a guarded tagged
   live-provider lane with no unapproved destination.

Official references are recorded in the milestone/architecture documentation as implementation
decisions become durable.

## Checkpoint 1 red: honest optional provider session identity

Added Calls and PostgreSQL boundary tests for an authenticated Twilio-shaped incoming event whose
Account SID identifies the configured connection, whose Call SID identifies control and leg, and
whose provider session ID is absent. The expected claim and stored telephony leg preserve `nil`.
This is project-owned normalization behavior; it does not test Twilio itself.

The Calls test failed first with `invalid_incoming_telephony_event`, as expected, because admission
required a non-empty session ID. Normalization now requires connection/control/leg and accepts only
`nil` or a non-empty session value. Its focused six tests pass.

The first persistence run then failed all five inserts. The schema patch had removed the session
field from `cast/3` instead of only removing it from `validate_required/2`, so even Telnyx values
were discarded and rejected. Restoring the cast and making only the requirement optional fixed the
regression. A forward migration changes the existing column from non-null to nullable. The focused
PostgreSQL suite now passes all five tests, including both Telnyx and Twilio shapes.

Root formatting, warnings-as-errors compilation, strict Credo, and the unused-dependency check pass.
The complete umbrella run passed all seven application lanes: MCP 37, Agent Runtime 58, Call Engine
351, Calls 45, Persistence 31, Gateway 176, and Console 59—757 tests with zero failures.

## Checkpoint 2: provider-specific configuration and verified incoming normalization

The next focused tests added a Twilio configured service and an incoming form webhook passed through
the public common adapter wrapper. The first run failed at compilation because `Webhook` had no URL
field. That is the expected abstraction difference: Telnyx signs its body and timestamp, while
Twilio signs the exact public request URL plus decoded form fields.

`ConfiguredService` now owns only the common service envelope. A small closed profile dispatcher
selects Telnyx or Twilio validation, and each provider module owns its own credential shape, default
adapter, verifier options, and safe provider-connection identity. The Telnyx rules moved without
semantic changes. Twilio accepts Account SID plus Auth Token, derives connection identity from the
Account SID, rejects credentials from the other profile, and keeps secrets out of inspection. The
common `IngressIdentity` type now honestly names both supported providers.

Twilio form decoding rejects duplicates, excessive field count/size, missing values, and malformed
percent encoding. Verification parses the raw form, sorts case-sensitive keys, computes the
documented HMAC-SHA1 input using the exact configured URL, base64-encodes it, and compares it in
constant time. The decoder rechecks configured Account SID, validates Account/Call SID shapes, and
normalizes a signed inbound request with Call SID as control+leg and no invented session. Changing
the signed `From` field fails authentication before decoding.

Only verify/decode is implemented on the Twilio adapter in this checkpoint. Dial, answer, end, and
media callbacks return explicit unsupported errors until their owning checkpoints, and no Twilio
HTTP route is exposed yet.

Focused green evidence:

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/telephony/configured_service_test.exs \
  test/vxpipe/gateway/telephony/service_registry_test.exs \
  test/vxpipe/gateway/telephony/telnyx/adapter_test.exs \
  test/vxpipe/gateway/http/telnyx_events_test.exs \
  test/vxpipe/gateway/telephony/twilio/adapter_test.exs
# 23 tests, 0 failures
```

Root formatting, warnings-as-errors compilation, strict Credo, and the unused-dependency check pass.
The complete umbrella run passed MCP 37, Agent Runtime 58, Call Engine 351, Calls 45, Persistence
31, Gateway 180, and Console 59—761 tests with zero failures.

## Checkpoint 3: synchronous incoming Voice and TwiML

The next red tests sent a signed Twilio form through the real Gateway endpoint and required an XML
`<Connect><Stream>` response only after dispatch, plus rejection of a changed signed field before
dispatch. The activation test also required the common incoming workflow to preserve and return the
generated WSS media URL. The first focused run failed at compilation because there was no typed
activation result capable of carrying that URL.

Incoming activation now returns `IncomingLegActivationResult` with the common media binding, exact
private WSS URL, and provider submission. Twilio's synchronous Voice flow validates the configured
account/token, Call SID, and secure media URL and records an accepted submission without making a
second answer request. Its HTTP route preserves the raw form body, authenticates against the exact
configured public Voice URL, starts the common admission path, and builds the TwiML response from the
result. Telnyx retains its asynchronous `200 ok` behavior while consuming the same result shape.

A provider-neutral `TelephonyIngressConfig` now owns the shared registry/handler/body-limit setup
that had previously lived in `TelnyxEvents`. Provider endpoint selection is similarly closed and
small. This avoids making either carrier's HTTP handler the configuration owner for the other.

Focused green evidence:

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

Two concurrent full-suite runs each exposed a different pre-existing media-shutdown assertion whose
100 ms receive deadline elapsed under Membrane load. The relevant failing test passed five isolated
runs, and the complete gateway suite passed with one test process. No production change or deadline
weakening was made for that unrelated observation.

The subsequent ordinary root run passed all seven application lanes: MCP 37, Agent Runtime 58,
Call Engine 351, Calls 45, Persistence 31, Gateway 183, and Console 59—764 tests with zero failures.
Formatting, warnings-as-errors compilation, strict Credo, and the unused-dependency check also pass.

This checkpoint stops at the authenticated synchronous control handoff. It does not yet expose the
Twilio media WebSocket or claim bidirectional G.711 audio, DTMF/status/AMD callbacks, outbound calls,
or private-transfer parity.

## Checkpoint 4: outbound Calls API and signed callbacks

Current Twilio Calls API, status callback, and asynchronous AMD documentation was checked before
implementation. Create is a form-encoded `POST` under the configured Account SID with HTTP Basic
authentication. Inline `Twiml` is accepted in place of a separate URL. Status callback events are
individually repeated form parameters, and Twilio documents that callback delivery order is not
guaranteed. Ending a live call updates the exact Call SID with `Status=completed`. Async AMD uses
`MachineDetection=Enable`, `AsyncAmd=true`, and a signed result callback.

Four focused adapter tests were red with `twilio_command_not_supported`. The implementation was
split into credential, REST transport, dial-form, end-call, and incoming-answer modules instead of
growing the adapter. The tests then proved the exact request target and fields, Basic auth, accepted
Call SID, bounded 4xx rejection, unknown 5xx outcome, no retry, and exact call termination.

The first four HTTP callback tests were red because Plug's JSON parser attempted to decode Twilio's
form body before the route could authenticate it. The raw-route predicate now includes the exact
callback path. A shared Twilio request extractor owns form content type, bounded raw bytes,
signature header, configured endpoint construction, verification, and adapter ingestion; the HTTP
handler owns only routing and responses. Status and AMD decoders remain separate from incoming
Voice decoding. A signed callback for another leg path fails authentication, and an authenticated
but unconsumed `queued` status returns success without dispatch.

The first out-of-order contract test then failed with `{:error, :leg_not_found}` when an `answered`
callback arrived before `initiated` after an unknown create result. Pending outbound routing now
uses the opaque internal leg ID only to locate the existing owner. That owner still requires valid
provider/account/origin/destination identity before registering the Call SID and binding media. An
answered or terminal progress event can therefore settle an ambiguous create without issuing a
second dial.

Focused and application evidence:

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
The full umbrella suite passes all seven application lanes—775 tests with zero failures.

The authenticated media WebSocket, G.711 conversion, media DTMF/control, complete shared transfer
harness, and tagged live-provider proof remain pending. This checkpoint makes no live-media claim.

## Checkpoint 5: authenticated media WebSocket and wire events

Twilio's current Media Streams documentation was checked again before this checkpoint. The initial
WebSocket upgrade carries `X-Twilio-Signature` over the exact configured WSS URL. A bidirectional
stream then sends `connected`, `start`, inbound `media`, DTMF, `mark`, and `stop` JSON messages.
The start message declares mono `audio/x-mulaw` at 8 kHz; media payloads are base64-encoded raw
PCMU bytes. Outbound messages later use media, mark, and clear. A mark is returned only after the
associated buffered playback reaches the caller, while clear flushes queued audio and returns the
pending marks.

The released Membrane package search exposed an important constraint: `membrane_g711_plugin` 0.1.2
implements A-law/PCMA only. `membrane_g711_format` can describe PCMU but does not encode or decode
it, and the readily available resampler uses FFmpeg's swresample. The next pipeline checkpoint must
therefore use Membrane for lifecycle and flow control with a narrowly scoped pure-Elixir PCMU codec
and deterministic fixed-rate converter. This avoids both the wrong codec and an unnecessary FFmpeg
runtime.

The first endpoint test failed with `404` because the Twilio WSS route did not exist. The resulting
boundary verifies upgrade shape, configured service, and exact URL signature before it consumes the
one-time media token. The test demonstrates that a request signed for a trailing-slash variant gets
`401`, after which the exact signed request can still upgrade; only that successful admission
consumes the token.

Four initial decoder cases failed with the adapter's explicit
`invalid_twilio_media_message` response. Separate field, start, packet, and control decoders now
pin Account SID, Call SID, one MZ Stream SID, format, sequences, timestamps, bounded payloads, and
DTMF. They leave PCMU as a provider packet for the later Membrane pipeline. Three socket tests were
then red because `MediaSocket` did not exist. The socket now monitors the exact leg, dispatches
start/media/DTMF through the common leg contract, and closes on cross-call frames or owner exit.

Focused and application evidence:

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
The complete umbrella suite passes all seven application lanes—784 tests with zero failures.

This is authenticated ingress and wire normalization, not live Twilio audio. PCMU decode/encode,
8/48 kHz conversion, outbound media/clear, Membrane pipeline selection, full transfer parity, and
the tagged provider lane remain pending.

## Checkpoint 6: PCMU conversion and live-session routing

The media implementation was divided at the same provider boundary used by Telnyx. Small pure
modules own G.711 PCMU companding and the fixed 8/48 kHz conversion. Small Membrane filters wrap
those operations, while provider pipelines own clock alignment, framing, real-time pacing, and the
Twilio JSON envelope. The WebSocket only translates internal encoded-media messages into WebSocket
pushes. Room and participant processes continue to see the existing 48 kHz signed 16-bit PCM
contract.

The standard codec-vector and streaming-boundary tests were red because the codec and converter did
not exist, then passed with zero dependencies added. The upsampler retains the last 8 kHz sample and
linearly interpolates each next interval into six samples, introducing only its fixed one-sample
causal delay. The downsampler averages each complete six-sample group and retains any partial group
for the next buffer. This is intentionally bounded, deterministic voice-band conversion rather
than an invocation of FFmpeg's general-purpose resampler.

Ingress, room-egress, and direct-output pipeline tests were next red because the three Twilio
pipelines did not exist. They now prove 20 ms frame size/timing, provider format rejection,
identity/order checks, exact Stream SID envelopes, and pacing acknowledgements. An initial parallel
run observed pipeline-start scheduling past the test's two-second receive window; running these
Membrane lifecycle tests non-async and in the established single-case lane removed that test-only
contention without relaxing production deadlines.

The common media-session test was red with `unsupported_media_provider`. Adding Twilio to the
closed `MediaPipelineSet` and carrying its authenticated Stream SID into direct and room output
pipelines made the same session attach a caller, accept PCMU into room ingress, and produce outbound
PCMU from 48 kHz agent audio. The first socket-output test was red because the message was ignored;
the socket now emits only internally generated media messages after its Stream SID has been pinned.

Focused and Gateway evidence:

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

The umbrella completion gates also pass: formatting, warnings-as-errors compilation, strict
Credo, 797 tests across all seven applications, and the unused-dependency check.

The remaining Twilio work is explicit remote-buffer clearing on interruption/privacy changes, the
full common private-transfer harness, and a guarded tagged provider lane. No live-provider claim is
made from the deterministic pipeline proof.

## Checkpoint 7: remote playback clear

Twilio buffers outbound media after the server sends it, so terminating the local Membrane
pipeline alone is insufficient for interruption and privacy transitions. A transport-owned
`PlaybackClearer` contract now sits beside the direct and room-egress pipeline selections. The
shared replacement workflows terminate the old producer synchronously, invoke the clearer with its
pinned transport options, and only then start a new pipeline. The stop-clear-start order prevents
old paced buffers from being delivered after the remote clear. Twilio sends `clear` with the exact
Stream SID; the existing non-Twilio paths retain an explicit no-op clearer.

The initial focused run produced the expected three failures: an undefined Twilio clearer and no
clear notification from either replacement workflow. After the contract was wired through both
output states and telephony session setup, the tests proved exact command encoding, invalid target
rejection, and lifecycle ordering. The common Twilio media-session test now queues multiple PCM
frames, interrupts that turn, and observes the same clear command through the configured socket
owner.

Combining that session test with the shared lifecycle tests exposed an existing fixture collision:
all direct-output tests reused one Registry key while a spawned pipeline from the previous test
could still be unregistering. Per-test connection identities fixed the test ownership boundary;
no sleep or production timeout changed. The combined group passed twice consecutively.

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

The umbrella completion gates pass: formatting, warnings-as-errors compilation, strict Credo, 799
tests across all seven applications, and the unused-dependency check.

Private-transfer parity and tagged live-provider verification remain. This checkpoint does not
claim either one.

## Checkpoint 8: provider-paired outbound transfer scenario

The existing outbound private-transfer test was hard-coded to one configured carrier even though
the production orchestration already accepts the common telephony contract. The test body was first
put behind a provider-shaped scenario entry while retaining its original case; that mechanical
step stayed green with two tests.

A Twilio case was then added with its real identity shape: Account SID as configured connection,
Call SID as control and leg, no provider session ID, and a pinned Stream SID. The first run failed
at the intended test boundary. The private briefing reached the Twilio PCMU Membrane egress, but the
shared fake socket had no clause for the Twilio delivery message and terminated. Adding Twilio
media/clear observation to that fake allowed the unchanged transfer assertions to pass.

The scenario now covers both success and configured machine detection for Telnyx and Twilio. The
success path proves one dial, private destination briefing, rejection of acceptance from the wrong
process, destination press-1, no commit before briefing completion, one tool completion, main-media
promotion, and harmless repeated DTMF. The machine path proves exact-leg termination, tool failure,
source retention, and no duplicate end command.

To avoid growing the test into another fixture owner, call-plan compilation, connector/service
construction, commands, normalized events, briefing completion, and identifiers moved to the
cohesive `PhoneTransferScenario` test-support module. The assertion module fell from 613 to 362
lines.

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/telephony/outbound_phone_transfer_test.exs --max-cases 1
# initial provider-paired run: 3 tests, 1 failure (Twilio message unsupported by fake socket)
# final run after success + machine parity and refactor: 4 tests, 0 failures
```

The complete Gateway lane passes 220 tests. Root formatting, warnings-as-errors compilation, strict
Credo over 601 source files, all 801 umbrella tests, and the unused-dependency check pass.

This is deterministic outbound-transfer parity. It is not the signed Twilio inbound-to-outbound
harness and is not live-provider evidence.
