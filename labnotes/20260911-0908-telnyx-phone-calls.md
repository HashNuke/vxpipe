# Telnyx phone calls

## Goal and scope

Implement milestone 17 as a provider-neutral telephony boundary first and a Telnyx adapter second.
The runnable target is one verified inbound phone leg plus one private outbound human transfer with
deterministic press-1 acceptance. The implementation must keep credentials and provider command
payloads out of call definitions and room state, use the existing transfer deadline/privacy commit,
normalize media at the gateway boundary with Membrane where appropriate, and avoid FFmpeg unless a
required format proves impossible without it.

Implementation stops after milestone 22 for an integrated platform/sample review. Docker packaging
and retention remain outside this work until the user explicitly resumes them.

## Vendor research

Official Telnyx documentation checked on 2026-09-11:

- Voice webhooks carry `call_control_id`, `call_leg_id`, `call_session_id`, `connection_id`,
  `client_state`, `from`, and `to`. `call_session_id` relates legs but is not sufficient as Vxpipe
  authority: <https://developers.telnyx.com/docs/voice/programmable-voice/voice-api-webhooks>
- Call Control commands are asynchronous relative to lifecycle webhooks. Dial can lead to answered
  or hangup events; an HTTP command response is not final call-state proof:
  <https://developers.telnyx.com/docs/voice/programmable-voice/sending-commands>
- Media streaming uses a WebSocket JSON envelope with base64 media payloads. Ordering is not
  guaranteed, so `sequence_number`/`chunk` are required at the adapter boundary. Bidirectional media
  supports defined codecs including linear PCM and telephony codecs:
  <https://developers.telnyx.com/docs/voice/programmable-voice/media-streaming>
- Webhook authentication uses the raw payload with the Telnyx timestamp and Ed25519 signature
  headers. Timestamp freshness is part of replay protection:
  <https://developers.telnyx.com/api-reference/callbacks/call-dtmf-received>
- Provider AMD can report human, machine, or uncertain outcomes. Vxpipe will disconnect an exact
  destination leg on machine, while uncertain detection still waits for explicit press-1 within the
  original transfer deadline:
  <https://developers.telnyx.com/docs/voice/programmable-voice/answering-machine-detection>

The historical Callpipe Telnyx adapter, media stream registry/codec, and inbound/outbound examples
were inspected for integration hints. They confirm the usefulness of injectable command clients and
explicit stream/call-control correlation, but Vxpipe will not copy their provider-shaped room
contract or provider-owned bridge path.

## Checkpoint 1: pinned connection intent

Red test:

```text
cd apps/vxpipe_call_engine
mix test test/vxpipe/call_engine/call_definition/telephony_connection_compiler_test.exs
```

The new test initially failed because `NumberFromVariable` did not exist. It covers provider-neutral
receive and dial intent, E.164 literals, mutually exclusive direct variable-backed destinations,
declared string-compatible source variables, and the rule that no agent may write a routing section.

Implementation results:

- Schema `20260911.03` keeps `web` as the fixed receive transport and accepts other validated service
  strings without creating atoms from external input.
- Receive phone intent requires a literal E.164 number and explicit admission.
- Dial phone intent defaults to transfer admission and requires exactly one literal number or direct
  section/variable source.
- Transfer allowlists can target a declared dialing human participant; the generated model tool still
  contains only the participant ref.
- Cross-definition validation rejects absent sections/variables, non-string schemas, and any agent
  write grant on the routing section.
- Calls compiled metadata now serializes string service refs and retains safe destination intent;
  only web connections produce browser participant routes.

Focused green evidence:

```text
cd apps/vxpipe_call_engine
mix test test/vxpipe/call_engine/call_definition/telephony_connection_compiler_test.exs \
  test/vxpipe/call_engine/call_definition/agent_transfer_compiler_test.exs \
  test/vxpipe/call_engine/call_definition/compiler_test.exs
# 30 tests, 0 failures

cd apps/vxpipe_calls
mix test test/vxpipe/calls/definitions_test.exs
# 5 tests, 0 failures
```

The first full Call Engine run completed 342 tests with one unrelated timing-sensitive lifecycle
failure (`:noproc` observed instead of the expected startup-timeout reason). Its focused rerun passed,
and the subsequent umbrella run passed the Call Engine's 342 tests with no failures. No product code
was changed for the transient result.

Umbrella verification used an isolated disposable PostgreSQL 17 container because the ambient local
socket required an unspecified password. With `VXPIPE_TEST_DATABASE_URL` pointed at that container:

```text
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix deps.unlock --check-unused
mix test
```

All checks passed. The default test lanes completed 37 MCP tests (3 excluded), 58 Agent Runtime tests
(2 excluded), 342 Call Engine tests (1 excluded), 38 Calls tests, 25 Persistence tests, 95 Gateway
tests (4 excluded), and 59 Console tests.

## Checkpoint 2: common adapter contract

Red test:

```text
cd apps/vxpipe_call_engine
mix test test/vxpipe/call_engine/telephony/adapter_test.exs
```

The test initially failed while compiling the test adapter because the common `Submission` type did
not exist. The green implementation adds small single-purpose command/value modules plus one adapter
contract. Its deterministic fake covers:

- dial submission with an `unknown` immediate outcome, preserving the no-speculative-redial rule;
- answer and exact-leg end submissions;
- authorized mixed-room frames sent to one exact leg;
- raw webhook verification before decoding;
- incoming, answered, media-started, media, DTMF, human/machine/unknown AMD, and ended events; and
- rejection of output that does not conform to the common contract.

Sensitive raw webhook bytes, phone numbers, DTMF digits, and audio payloads are excluded from the
new structs' inspection representations. Provider media retains codec, sample rate, sequence, and
timestamp until the Gateway's Membrane pipeline can normalize it into the existing room format.

Focused green evidence:

```text
cd apps/vxpipe_call_engine
mix test test/vxpipe/call_engine/telephony/adapter_test.exs
# 4 tests, 0 failures
```

The complete format, warnings-as-errors compile, strict Credo, unused-dependency, and umbrella test
gates also passed. The Call Engine lane now runs 346 tests with one tagged exclusion; all other
application counts remain the same as checkpoint 1.

The next checkpoint is concrete Telnyx webhook verification/normalization and configured service
resolution. No Telnyx module or network request exists yet.

## Checkpoint 3: raw Telnyx webhook authentication

Current Telnyx documentation and the provider's maintained SDK example confirm that the Mission
Control webhook public key is base64-encoded, the signature header is a base64 Ed25519 signature,
and the signed bytes are exactly `timestamp <> "|" <> raw_body`. Telnyx recommends a five-minute
timestamp tolerance. Vxpipe applies that bound in both directions so a far-future signed timestamp
cannot extend a replay window. The event ID remains the separate deduplication key for authenticated
retries.

Red test:

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/telephony/telnyx/webhook_verifier_test.exs
# 4 tests, 4 failures: WebhookVerifier.verify/2 was undefined
```

`Vxpipe.Gateway.Telephony.Telnyx.WebhookVerifier` now has one responsibility: validate configuration,
timestamp freshness, signature encoding, and the signature over untouched bytes. It does not parse
JSON. Configuration failures are distinct internally; every request-authentication failure uses one
bounded error and reveals no key, signature, header, or body. The tests generate an ephemeral
Ed25519 key pair and cover the exact five-minute boundary, altered raw bytes, missing/malformed
headers, stale/future timestamps, and invalid verifier configuration.

Focused green evidence:

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/telephony/telnyx/webhook_verifier_test.exs
# 4 tests, 0 failures
```

The umbrella format, warnings-as-errors compile, strict Credo, default test, and unused-dependency
gates also passed against an isolated disposable PostgreSQL 17 instance.

The verifier is not yet mounted on an HTTP route. The next checkpoint preserves raw Plug request
bytes, normalizes the supported Telnyx event envelope, and proves verification precedes decoding at
the ingress boundary.

## Checkpoint 4: authenticated ignored events

Telnyx delivers lifecycle/status events that Vxpipe may authenticate correctly but deliberately not
consume, including outbound initiation and streaming-status callbacks. Returning an adapter error
for these events would conflate valid input with malformed input and could invite unnecessary provider
retries. The common adapter contract now accepts a closed `:ignore` result only after webhook
verification has succeeded. It remains invalid adapter output in any other shape.

The focused red test observed `{:error, :invalid_adapter_response}` where the new contract required
`:ignore`; after the contract change all five adapter tests pass. This prepares the Telnyx event
decoder to acknowledge unconsumed event types without inventing corresponding room events.

The complete umbrella format, warnings-as-errors compile, strict Credo, default test, and
unused-dependency gates passed against an isolated disposable PostgreSQL 17 instance.

## Checkpoint 5: Telnyx Voice API event normalization

The initial common event was missing two facts required by the approved ingress design:

- Telnyx `connection_id` establishes which configured Voice API service emitted the webhook before
  route selection uses the called number.
- Provider `occurred_at` provides the source observation time needed alongside event-ID
  deduplication when callbacks arrive late or out of order.

Both are now explicit common-event fields. Webhook-origin lifecycle events require an event ID,
leg ID, and parsed occurrence time; inbound initiation additionally requires provider connection
identity. DTMF, AMD, and ended events received the same correlation validation rather than being
accepted from only a call-control ID plus their event-specific value.

Red evidence:

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/telephony/telnyx/webhook_decoder_test.exs
# compilation failed because the required common event fields did not exist
```

The small `WebhookDecoder` module now parses only the authenticated Voice API v2 `data` envelope and
maps incoming, answered, DTMF, standard/premium AMD, and hangup callbacks into common events. It uses
fixed mappings rather than atoms derived from provider input, bounds every retained identifier or
address, maps premium `human_residence`/`human_business` to `human`, premium
`machine`/`silence`/`fax_detected` to `machine`, and `not_sure` AMD to `unknown`. It preserves
actionable timeout/busy/no-answer endings and collapses unknown non-empty hangup causes to generic
failure. Outbound initiation, streaming status, playback status, and future authenticated event
types return `:ignore`. Malformed JSON/envelopes and incomplete consumed events return one bounded
decoder error.

The first decoder green pass covered only the standard AMD values. A follow-up check against the
current premium AMD documentation exposed its distinct result vocabulary; expanded tests failed on
`human_residence` before the event-specific mappings were added, and all decoder tests then passed.

Focused green evidence:

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/telephony/telnyx/webhook_decoder_test.exs \
  test/vxpipe/gateway/telephony/telnyx/webhook_verifier_test.exs
# 9 tests, 0 failures

cd apps/vxpipe_call_engine
mix test test/vxpipe/call_engine/telephony/adapter_test.exs
# 5 tests, 0 failures
```

The complete umbrella format, warnings-as-errors compile, strict Credo, default test, and
unused-dependency gates passed against an isolated disposable PostgreSQL 17 instance.

The HTTP endpoint and service resolver still need to construct the raw webhook, authenticate it,
then invoke this decoder and dispatch only the resulting common event.

## Checkpoint 6: configured raw-body HTTP ingress

The gateway now mounts `POST /api/telephony/telnyx/:ingress_key/events` as a backend-only provider
route. An opaque ingress key resolves to one enabled application- or tenant-scoped configured
service. The resolved service pins the expected Telnyx Voice API connection ID and verifier options,
but the downstream handler receives only a safe service identity plus the provider-neutral event.
Inspection of the registry and configured-service structs omits verifier material.

The endpoint deliberately bypasses `Plug.Parsers` only for this exact route. It reads at most
128 KiB of untouched bytes, extracts exactly one copy of each required Telnyx signature header,
authenticates those bytes, then performs semantic decoding. A signed malformed document therefore
reaches the decoder and returns a bounded request error, while body tampering fails authentication.
An authenticated event whose `connection_id` differs from the configured service is rejected before
dispatch. Authenticated events outside Vxpipe's consumed vocabulary are acknowledged without
dispatch so the provider is not encouraged to retry irrelevant status callbacks.

Red evidence:

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/http/telnyx_events_test.exs
# compilation failed because IngressIdentity and the configured ingress boundary did not exist
```

Focused green evidence:

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/http/telnyx_events_test.exs
# 7 tests, 0 failures

mix test test/vxpipe/gateway/http test/vxpipe/gateway/telephony
# passed after replacing the default anonymous clock closure with an escapable remote function
```

This checkpoint does not yet create a durable call, deduplicate provider event IDs, or map a Telnyx
leg to a tenant/call/participant/incarnation/attempt. Those behaviors remain in the Calls-facing
part of configured service resolution and provider-leg correlation, so milestone checklist item 2
stays open.

Umbrella verification used a dedicated disposable PostgreSQL 17 instance on port 55434. The
following root checks all passed, and the container was stopped afterward:

```text
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix deps.unlock --check-unused
VXPIPE_TEST_DATABASE_URL=postgres://postgres:postgres@127.0.0.1:55434/vxpipe_test mix test
```

## Checkpoint 7: published inbound telephony routes

Definition persistence previously created only opaque browser participant routes. An inbound phone
webhook therefore had no durable, provider-neutral way to select a published definition and entry
participant after its configured service had been authenticated.

The Calls domain now derives a `TelephonyRoute` for each non-web human connection with
`receive`/`start_call` intent. It binds tenant, configured service ref, literal E.164 destination,
participant ref, and immutable definition revision without storing carrier credentials or a
provider leg. Web routes remain a separate type because their opaque join key and lookup contract
are different.

Publication activates web and telephony routes together and disables both kinds from the previous
revision. Tenant-scoped lookup can select only that tenant. Application-scoped lookup requires
exactly one published match across tenants; an ambiguous number/service pair fails closed rather
than guessing. A new Ecto table and migration preserve the same behavior in PostgreSQL.

Red evidence:

```text
cd apps/vxpipe_calls
mix test test/vxpipe/calls/definitions_test.exs
# failed because DefinitionRevision had no telephony_routes and the resolver did not exist

cd apps/vxpipe_persistence
VXPIPE_TEST_DATABASE_URL=postgres://postgres:postgres@127.0.0.1:55434/vxpipe_test \
  mix test test/vxpipe/persistence/definition_store_test.exs
# compilation failed because the Ecto adapter could not construct the strengthened revision
```

Focused green evidence:

```text
cd apps/vxpipe_calls
mix test test/vxpipe/calls/definitions_test.exs
# 6 tests, 0 failures

cd apps/vxpipe_persistence
VXPIPE_TEST_DATABASE_URL=postgres://postgres:postgres@127.0.0.1:55434/vxpipe_test \
  mix test test/vxpipe/persistence/definition_store_test.exs
# 3 tests, 0 failures
```

The first Ecto green attempt exposed a duplicate `select` while adding the tenant scope to the base
query. Removing the redundant projection left the base query's bounded two-row ambiguity check
intact. This checkpoint still does not create or start a call from the route, and it does not own a
provider leg; those remain the next checkpoint.

The root format, warnings-as-errors compile, strict Credo, unused-dependency, and database-backed
umbrella test gates all passed against the same isolated PostgreSQL 17 instance.

## Checkpoint 8: atomic incoming provider-leg claim

A verified and normalized incoming event can now select its published telephony route and prepare
the pinned definition without starting a room. `PreparedCallFactory` owns the common web/telephony
plan construction so browser admission and carrier admission do not duplicate definition parsing,
identity generation, compilation, or plan digests. The telephony workflow additionally verifies
that the routed participant is the entry caller.

The call repository now has one provider-neutral atomic claim operation. The Ecto adapter stores
the new call in `admitting` state and its initial `telephony_legs` row in one transaction. The row
retains the configured service plus bounded provider event, connection, control, leg, and session
identifiers for later live correlation; it contains no credentials or raw provider payload. Both
provider/service/event ID and provider/service/leg ID are unique. An exact retry returns the
existing pinned claim without creating another call. Reusing an event ID for a different leg fails
closed, and the attempted new call is rolled back. Call preparation leaves `started_at` empty;
room startup owns that timestamp in a later checkpoint.

The persistence refactor kept responsibilities bounded: `PreparedCallRecord` maps between the
domain call and Ecto record, `TelephonyCallStore` owns the leg-claim transaction and deduplication,
and the existing `CallStore` delegates instead of absorbing another callback family.

Red evidence:

```text
cd apps/vxpipe_calls
mix test test/vxpipe/calls/telephony_admissions_test.exs \
  test/vxpipe/calls/admissions_test.exs
# compilation failed because TelephonyAdmissionClaim did not exist

cd apps/vxpipe_persistence
VXPIPE_TEST_DATABASE_URL=ecto://postgres:postgres@127.0.0.1:55434/vxpipe_test \
  mix test test/vxpipe/persistence/telephony_call_store_test.exs \
  test/vxpipe/persistence/call_store_test.exs
# two focused tests failed because CallStore did not implement the claim callback
```

Focused green evidence after implementation and the SRP extraction:

```text
cd apps/vxpipe_calls
mix test test/vxpipe/calls/telephony_admissions_test.exs \
  test/vxpipe/calls/admissions_test.exs
# 14 tests, 0 failures

cd apps/vxpipe_persistence
VXPIPE_TEST_DATABASE_URL=ecto://postgres:postgres@127.0.0.1:55434/vxpipe_test \
  mix test test/vxpipe/persistence/telephony_call_store_test.exs \
  test/vxpipe/persistence/call_store_test.exs
# 18 tests, 0 failures
```

The first persistence implementation used non-UUID deterministic call and room fixture values,
which the database correctly rejected as `call_insert_failed`; replacing them with valid UUIDs
made the fixtures match the public-ID contract. Gateway dispatch into this workflow, room startup,
and live in-memory incarnation ownership remain the next checkpoint.

The root format, warnings-as-errors compile, strict Credo, unused-dependency, and database-backed
umbrella test gates passed. The umbrella run covered 682 tests with zero failures and excluded only
the existing explicitly tagged integration lanes.

## Checkpoint 9: telephony planned-room startup

The persisted claim could compile a telephony plan, but `PlanStartup` still rejected every
transport except `web` and every entry caller except a web receive/start connection. Call Engine
now accepts the closed `telephony` transport and a compiled non-web receive/start entry caller. It
uses the ordinary planned-room supervision and lifecycle path; no carrier schema, command, or raw
media enters room control.

The focused test compiles a `20260911.03` incoming-phone definition, starts the call, observes the
entry caller already joined under the returned room incarnation, and ends it through the pinned
maximum-duration lifecycle timer. The first run failed with `unsupported_call_plan` at
`transport.type`, which was the expected red boundary.

Focused green evidence:

```text
cd apps/vxpipe_call_engine
mix test test/vxpipe/call_engine/telephony_call_startup_test.exs
# 1 test, 0 failures

mix test test/vxpipe/call_engine/telephony_call_startup_test.exs \
  test/vxpipe/call_engine/definition_driven_call_test.exs \
  test/vxpipe/call_engine/human_only_call_test.exs
# 25 tests, 0 failures
```

Gateway still has to bind the claimed provider leg to the returned room incarnation and project
the durable start. That remains the next checkpoint.

The root format, warnings-as-errors compile, strict Credo, unused-dependency, and database-backed
umbrella test gates passed with 683 tests and zero failures. An initial umbrella run exposed one
failure in the unrelated room-authority termination test; that exact file passed immediately on a
focused rerun, and the subsequent complete umbrella run passed. No implementation change was made
for that transient result.

## Checkpoint 10: provider-leg lifecycle projection

Calls now exposes lifecycle operations specific to an incoming telephony claim. A successful room
startup atomically changes the call from `admitting` to `running`, sets its actual `started_at` and
incarnation, and changes the exact stored leg from `admitting` to `active` with the same
incarnation. An exact repeat is idempotent. A pre-live startup failure instead changes the call to
`failed` and the leg to `ended`, preserves an empty `started_at`, and records the safe terminal
reason and failure time.

The PostgreSQL adapter locks and rechecks the stored provider event, connection, control, leg, and
session identifiers plus tenant, call, and participant identity before either transition. Call and
leg changes share one transaction, so neither half can commit independently. The general
`CallStore` delegates these operations to the cohesive `TelephonyCallStore` boundary.

Red evidence:

```text
cd apps/vxpipe_calls
mix test test/vxpipe/calls/telephony_admissions_test.exs
# 5 tests, 2 failures because both lifecycle facade operations were absent

cd apps/vxpipe_persistence
VXPIPE_TEST_DATABASE_URL=ecto://postgres:postgres@127.0.0.1:55434/vxpipe_test \
  mix test test/vxpipe/persistence/telephony_call_store_test.exs
# 4 tests, 2 failures because the Ecto repository callbacks were absent
```

Focused green evidence:

```text
cd apps/vxpipe_calls
mix test test/vxpipe/calls/telephony_admissions_test.exs
# 5 tests, 0 failures

cd apps/vxpipe_persistence
VXPIPE_TEST_DATABASE_URL=ecto://postgres:postgres@127.0.0.1:55434/vxpipe_test \
  mix test test/vxpipe/persistence/telephony_call_store_test.exs
# 4 tests, 0 failures
```

The gateway still has to invoke claim, startup, and projection as one ingress workflow and retain
the live provider-leg correlation in memory.

The root format, warnings-as-errors compile, strict Credo, unused-dependency, and database-backed
umbrella test gates passed with 687 tests and zero failures.

## Checkpoint 11: serialized gateway leg ownership

Gateway now supplies `CallIngress` as the default handler for authenticated Telnyx events. An
incoming event starts one temporary `Leg` process under a dedicated dynamic supervisor and unique
registry. The process is keyed by provider, configured service, and provider leg ID, and it owns
the Calls claim, ordinary room startup, and lifecycle projection in sequence.

The first green design claimed in the HTTP process and registered the leg owner afterward. Review
found a real race: a concurrent retry could see the committed claim before the owner existed and
misclassify the call as abandoned. Moving the claim into the already-registered leg process closes
that gap. Concurrent/retried initiation awaits the same process and does not claim or start again.
After a process/VM loss, an `admitting` duplicate is marked `startup_unknown` and never restarted;
running and failed duplicates are acknowledged without repeating the call.

The leg owner retains the pinned claim in memory. Later events resolve it without another Calls or
PostgreSQL operation, then require exact provider connection, control, leg, and session identity
before reaching the live backend. Mismatches fail closed. The child uses `restart: :temporary`, so
its initialization data cannot automatically repeat a call after an internal process crash.
Startup failure is projected once and acknowledged rather than treated as permission to redial.
The current production backend explicitly rejects post-initiation events until their call-control
and media checkpoints implement them.

Red evidence:

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/telephony/call_ingress_test.exs
# 3 tests, 3 failures because CallIngress and LegSupervisor did not exist
```

Focused green evidence:

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/telephony/call_ingress_test.exs
# 3 tests, 0 failures

mix test test/vxpipe/gateway/telephony/call_ingress_test.exs \
  test/vxpipe/gateway/http/telnyx_events_test.exs \
  test/vxpipe/gateway/http/endpoint_test.exs
# 25 tests, 0 failures
```

The remaining milestone work begins with provider command submission and media transport attached
to this owner; it does not require moving carrier state into Room Authority.

The root format, warnings-as-errors compile, strict Credo, unused-dependency, and database-backed
umbrella test gates passed with 690 tests and zero failures. The first umbrella run had one
unrelated call-lifecycle readiness test fail; its seven-test file passed on an immediate focused
rerun, followed by the complete clean umbrella result. No timing implementation was changed.

## Checkpoint 12: bounded Telnyx Voice API commands

The Telnyx adapter now maps the provider-neutral dial, answer, and exact-leg end commands onto the
current Voice API endpoints. Dial and answer request one bidirectional Opus stream, with
inbound audio selected for room ingestion and outbound mixer audio addressed back to the same leg.
Dial also sends the configured Voice API connection, callback URL, an opaque Vxpipe leg correlation
value, and `detect` only when AMD was enabled by the compiled intent. Hangup uses the already
correlated provider call-control ID and never looks up or guesses a destination.

The HTTP boundary turns 2xx into an accepted submission and exposes only the status of a known 4xx
rejection. Transport errors, redirects, 5xx responses, and malformed success bodies are bounded;
ambiguous outcomes are represented as `unknown`. Req retries and redirects are disabled after
merging injectable test transport options, so a caller cannot accidentally override the no-retry
rule. Neither provider response bodies nor credentials enter the returned error value.

The test was written first and failed because the provider adapter did not exist. After the three
cohesive modules were added, the focused result was:

```text
cd apps/vxpipe_gateway
MIX_ENV=test mix test test/vxpipe/gateway/telephony/telnyx/adapter_test.exs
# 6 tests, 0 failures
```

The command adapter is not wired into the live leg owner yet, and the media WebSocket remains an
explicit unattached result. Those are separate checkpoints so HTTP command semantics, socket
ownership, and Membrane audio normalization do not accumulate in one module.

The root format, warnings-as-errors compile, strict Credo, unused-dependency, and database-backed
umbrella test gates passed with 696 tests and zero failures. The first umbrella run had one failure
in the unrelated MCP mixed-DNS wire-security test. Its exact test passed immediately, followed by
the complete clean umbrella result; no MCP implementation was changed.

## Checkpoint 13: exact-leg Telnyx media decoding

The command media settings now request Telnyx's supported Opus mode rather than L16. This lets the
next Membrane pipeline decode directly to the room's existing 48 kHz PCM without an FFmpeg process,
`libswresample`, or a custom sample-rate converter. The configured Telnyx voice bandwidth remains
16 kHz while the Opus decoder owns conversion to the room format.

The media decoder accepts a bounded JSON message only after its `start` message matches the
in-memory call-control ID, session ID, opaque Vxpipe leg state, optional expected stream ID, and the
requested Opus/16 kHz/mono format. Media messages must name the admitted stream and inbound track;
their base64 payload, global sequence, media chunk, and millisecond timestamp are parsed without
turning provider strings into atoms. Media chunk is used as the audio ordering sequence, while the
provider sequence remains part of a stable event identity. Socket DTMF receives the exact known
leg/session identity and provider occurrence time before common event validation. Another call,
stream, direction, malformed base64 payload, or incompatible format fails closed.

The tests were written first. The combined provider adapter/media suite initially had seven
expected failures because media decoding was unattached and command requests still selected L16.
The focused green result after implementation was:

```text
cd apps/vxpipe_gateway
MIX_ENV=test mix test test/vxpipe/gateway/telephony/telnyx/adapter_test.exs \
  test/vxpipe/gateway/telephony/telnyx/media_decoder_test.exs
# 11 tests, 0 failures
```

This checkpoint validates the provider message boundary only. A WebSocket owner, media token, and
Membrane ingress/egress pipelines remain required before media can attach to the room.

The root format, warnings-as-errors compile, strict Credo, unused-dependency, and database-backed
umbrella test gates passed with 701 tests and zero failures. The umbrella has no `ecto.setup` alias;
the disposable test database was therefore initialized with the existing `ecto.create` and
`ecto.migrate` tasks before the clean test run.

## Checkpoint 14: Membrane Telnyx ingress normalization

The room-ready PCM value, mono mixer, and PCM sink were moved from the WebRTC namespace into the
transport-neutral Gateway media namespace before adding the carrier path. The mechanical extraction
kept the existing WebRTC decode and room-ingress tests green and was committed separately.

The new Telnyx ingress test was written next and failed because `AudioIngressPipeline` did not yet
exist. The implemented pipeline accepts only the pinned tenant, room incarnation, participant,
connection, and stream identity with Opus/16 kHz/mono metadata. Media chunks must increase strictly,
and their provider timestamps cannot regress. The packet source assigns the provider millisecond
timestamp as PTS, a Telnyx-owned Membrane filter aligns the first packet to the closest preceding
20 ms room-clock point based on monotonic arrival time, and the official Membrane Opus decoder emits
48 kHz PCM. Shared mono/framing/sink elements then produce exact room-ready 20 ms frames. This path
does not launch FFmpeg and does not use a custom resampler.

Focused green evidence:

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/telephony/telnyx/audio_ingress_pipeline_test.exs \
  test/vxpipe/gateway/webrtc/audio_pipeline_test.exs \
  test/vxpipe/gateway/webrtc/room_audio_ingress_test.exs
# 10 tests, 0 failures

cd ../..
mix compile --warnings-as-errors
mix credo --strict
# clean
```

This is still an isolated normalization boundary. The provider WebSocket owner must next bind one
admitted stream to the live leg, apply room media policy, and feed these PCM frames through the
existing engine attachment. The reverse mixer-to-Telnyx Opus path also remains pending.

The root format, warnings-as-errors compile, strict Credo, unused-dependency, and database-backed
umbrella gates passed with 703 tests and zero failures. One initial umbrella invocation returned a
nonzero status after its retained output showed the final Console lane green but omitted the earlier
failure block. The Gateway lane passed all 127 tests with the same seed on immediate isolation, and
the following complete umbrella run passed every lane. No implementation was changed for that
transient result.

## Checkpoint 15: Membrane Telnyx egress encoding

The current Telnyx media documentation was rechecked before fixing the outbound contract. In RTP
bidirectional mode, client-to-provider audio is a JSON `media` event containing one base64 payload;
the example does not add a stream ID. Permitted chunks range from 20 ms to 30 seconds, but Vxpipe
retains the mixer's existing 20 ms cadence for bounded latency and consistent policy boundaries.

The shared `MixedFrame` PCM source was first moved from the WebRTC namespace into the Gateway media
namespace, keeping the existing WebRTC output test green in a separate mechanical commit. The new
Telnyx egress test then failed because `AudioEgressPipeline` did not exist. The implementation pins
tenant, room incarnation, recipient, and subscription, accepts only mix-minus/full-mix 48 kHz mono
20 ms frames, encodes with Membrane's Opus encoder, paces with `Membrane.Realtimer`, and emits the
documented base64 headerless Opus envelope to the exact socket owner. It rejects misaligned and
wrong-identity frames before encoding.

Focused green evidence:

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/telephony/telnyx/audio_egress_pipeline_test.exs
# 2 tests, 0 failures
```

The pipeline is not itself a socket or room subscriber. The next checkpoint must connect both
Membrane directions to one authenticated, single-use Telnyx WebSocket owned by the exact live leg.

The checkpoint passed `mix format --check-formatted`, compilation with warnings as errors, strict
Credo, the focused ingress/egress and WebRTC-output regression set (6 tests), the full umbrella
suite against an isolated disposable PostgreSQL 17 instance (705 tests, 0 failures), and the unused
dependency check.

## Checkpoint 16: single-use media admission

The provider media socket cannot use webhook signatures because Telnyx is opening a new WebSocket,
and a call-control identifier in a URL is not sufficient authentication. A focused test first
failed because no media admission or binding modules existed. Gateway now owns an in-memory token
issuer. Each cryptographically random token pins the exact live leg process plus tenant, call, room
incarnation, participant, configured service, ingress key, and provider identifiers. It can be
consumed once only through the configured ingress key, expires on a monotonic deadline, and is
revoked when the leg process terminates. Repeated preparation for the same exact binding returns
the existing pending token so a duplicate command path cannot leave multiple valid socket URLs.

Focused green evidence:

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/telephony/media_admission_test.exs
# 4 tests, 0 failures
```

This checkpoint deliberately does not expose an HTTP route yet. The next checkpoint consumes the
token before upgrading and passes only the resolved binding into the Telnyx WebSocket process.

The checkpoint passed formatting, compilation with warnings as errors, strict Credo, the focused
four-test contract, the full umbrella suite against an isolated disposable PostgreSQL 17 instance
(709 tests, 0 failures), and the unused dependency check.

## Checkpoint 17: bounded media WebSocket upgrade

A focused HTTP test first failed because the aggregate telephony configuration rejected media
admission settings. The router now validates the complete telephony option namespace, then gives
event and media handlers only their owned subsets. The new Telnyx media route validates the
WebSocket handshake before consuming a token, returns the same not-found response for invalid,
wrong-ingress, and reused tokens, and upgrades with only the resolved binding. An invalid handshake
therefore cannot burn a valid one-time token. Idle time and frame size are bounded, and Gateway now
declares its direct WebSock dependencies rather than relying on Console's Phoenix dependency tree.

Focused green evidence:

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/http/telnyx_media_test.exs
# 2 tests, 0 failures
```

The initial socket process monitors the exact leg and can carry outbound Telnyx envelopes, but it
still rejects inbound provider frames until the next checkpoint attaches decoding and media
pipelines.

The checkpoint passed formatting, compilation with warnings as errors, strict Credo, the unused
dependency check, the focused two-test HTTP contract, and the full umbrella suite against an
isolated disposable PostgreSQL 17 instance (711 tests, 0 failures).

## Checkpoint 18: exact socket frame dispatch

A focused socket test first failed because the media binding lacked the internal leg identifier
carried in Telnyx client state. The binding now pins that identifier separately from the provider's
call-leg ID. The socket accepts the provider connection preamble, validates the `start` frame's
call-control/session/client-state/Opus contract, pins the announced stream ID, and requires all
later media and DTMF frames to match it. Valid decoded events go through the existing exact leg
owner, preserving its serialized runtime correlation. Invalid text, every binary frame, and a
failed leg dispatch close the socket; no payload is rerouted by number or looked up in PostgreSQL.
Outbound envelopes from the Membrane sink travel back over the same socket process.

Focused green evidence:

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/telephony/telnyx/media_socket_test.exs \
  test/vxpipe/gateway/telephony/media_admission_test.exs \
  test/vxpipe/gateway/http/telnyx_media_test.exs
# 9 tests, 0 failures
```

The default live backend still rejects these newly decoded events. The next checkpoint must attach
the live room ingress/egress and agent-output boundaries before enabling media dispatch there.

The checkpoint passed formatting, compilation with warnings as errors, strict Credo, the unused
dependency check, the focused nine-test socket/admission/HTTP set, and the full umbrella suite
against an isolated disposable PostgreSQL 17 instance (714 tests, 0 failures).

## Checkpoint 19: complete configured-service boundary

A focused configured-service test first failed because the service accepted only webhook identity
and verification material. That was insufficient to answer or dial a leg after admission. An
enabled Telnyx service now pins its provider adapter, secret command options, public callback base,
and media-token lifetime alongside the prior safe identity and webhook verifier. The public base
must be HTTPS with a host and no userinfo, query, or fragment; its optional path prefix is normalized
once. Missing command credentials and ambiguous/non-TLS URLs fail during configuration parsing.
The struct's derived inspection remains limited to safe identity, so command credentials do not
appear in logs or crash inspection.

Focused green evidence:

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/telephony/configured_service_test.exs \
  test/vxpipe/gateway/http/telnyx_events_test.exs
# 9 tests, 0 failures
```

The checkpoint passed formatting, compilation with warnings as errors, strict Credo, the unused
dependency check, the focused nine-test configuration/webhook set, and the full umbrella suite
against an isolated disposable PostgreSQL 17 instance (716 tests, 0 failures).

## Checkpoint 20: incoming answer activation

Focused tests first failed because there was no incoming-leg activator and media admission could
not be explicitly revoked. The new provider-neutral orchestration boundary checks that configured
provider, service, tenant scope, and provider connection match the durable claim; generates one
internal telephony-leg ID; binds and admits the exact media socket; derives WSS from the normalized
public HTTPS base; and submits one answer command through the configured adapter. A rejected command
revokes its unconsumed token. The adapter contract continues to preserve unknown submission as an
outcome rather than retrying. The service secret remains inside adapter options and the media URL
contains only opaque ingress and admission tokens.

Focused green evidence:

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/telephony/incoming_leg_activation_test.exs \
  test/vxpipe/gateway/telephony/media_admission_test.exs
# 7 tests, 0 failures
```

This activator is intentionally tested independently before the leg lifecycle invokes it. The next
checkpoint must inject the immutable service registry into the default handler and make successful
room startup plus carrier activation one serialized leg transition.

Formatting, compilation with warnings as errors, strict Credo, and the unused dependency check
passed. The first full umbrella run reported one Call Engine failure while every other lane passed;
the retained filtered output did not contain the failed assertion. Call Engine passed all 348 tests
with the exact seed on immediate isolation, and a following complete umbrella run passed 719 tests
with zero failures against the same isolated disposable PostgreSQL 17 instance. No checkpoint code
was changed to mask the transient result.

## Checkpoint 21: serialized carrier activation and live evidence

The first focused leg-owner test failed because room startup projected the call as running before
the configured carrier answer operation had even been attempted. A separate default-backend test
also failed because the authenticated service registry and media-admission owner were not available
at the call-control boundary. Gateway now injects those immutable runtime objects into only the
standard `CallIngress`/`CallAdmission` path. Custom ingress handlers and custom call-ingress
backends remain unchanged, and secret-bearing configured-service data is not added to normalized
events.

The live leg owner now serializes durable claim, ordinary room startup, and exactly one configured
answer activation. A rejected activation is projected as `leg_activation_failed`, leaves
`started_at` empty, revokes its media token, and retires the temporary owner. Accepted and unknown
submissions both wait in `answering`; neither triggers a retry or claims that the phone leg is live.
An exact provider `answered` event supplies the durable start timestamp. If the authenticated,
single-use media socket starts first, that observation proves liveness and uses the gateway clock.
Duplicate incoming and answered events do not repeat claim, room startup, answer submission, or
start projection. When admitted media start is that first evidence, projection precedes dispatch of
the same event to the live media backend so pipeline attachment is not lost. Later exact live events
still route through the pinned in-memory claim.

The new default-adapter test exposed a valid URL edge case: an HTTPS public base with no path parses
with a nil path. Media URL construction now treats that as the empty prefix while preserving the
same WSS route.

Red evidence:

```text
cd apps/vxpipe_gateway
mix test --no-start test/vxpipe/gateway/http/telnyx_events_test.exs
# 8 tests, 1 failure: media_admission was not accepted or injected

mix test test/vxpipe/gateway/telephony/call_ingress_test.exs
# 5 tests, 2 failures: start was projected at command submission and media-start was not live evidence
```

Focused green evidence:

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/call_admission_adapter_test.exs \
  test/vxpipe/gateway/telephony/call_ingress_test.exs \
  test/vxpipe/gateway/telephony/incoming_leg_activation_test.exs \
  test/vxpipe/gateway/http/telnyx_events_test.exs
# 19 tests, 0 failures
```

This checkpoint still does not attach the Telnyx ingress/egress pipelines to the room or agent
output. Private briefing, press-1 acceptance, exact end cleanup, the deterministic complete-call
harness, and authorized real-provider verification remain pending.

The first full umbrella gate exposed one existing MediaSocket regression: the media-start event was
consumed as lifecycle evidence but not forwarded to the live backend. The Gateway lane failed one
of 147 tests for the missing dispatch while every other completed lane was green. The fix keeps the
ordering explicit—project live state, then dispatch that same exact media-start—and the owning
focused socket/leg tests were rerun before repeating the full gate.

Final verification passed formatting, compilation with warnings as errors, strict Credo, and the
unused-dependency check. The first post-fix umbrella repeat encountered the existing timing-sensitive
Call Engine room-shutdown assertion at its two-second monitor deadline (seed `468577`); all other
lanes were green. The owning Call Engine suite immediately passed all 348 tests with that exact seed,
and the following clean umbrella run passed 723 tests with zero failures against a fresh disposable
PostgreSQL 17 instance. No production change was made for that unrelated transient assertion.

## Checkpoint 22: transport-neutral room media coordinators

Before attaching Telnyx, the policy-aware room ingress and room egress coordinators were moved from
`Vxpipe.Gateway.WebRTC` to `Vxpipe.Gateway.Media`. Their responsibilities are not WebRTC-specific:
they own engine audio handles, current policy snapshots, policy-barrier pipeline replacement,
normalized PCM projection, mixer subscription, bounded draining, and transport pipeline failure.
The RTP decoder/encoder pipelines and the WebRTC child supervisor remain under the WebRTC boundary.
No behavior or public API was changed, and Git retains the files as moves with namespace updates.

Focused regression evidence:

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/media/room_audio_ingress_test.exs \
  test/vxpipe/gateway/media/room_audio_egress_test.exs \
  test/vxpipe/gateway/webrtc/audio_pipeline_test.exs \
  test/vxpipe/gateway/webrtc/connection_test.exs
# 14 tests, 0 failures
```

The next behavioral checkpoint can inject Telnyx's existing Membrane ingress/egress pipelines and
an owning telephony supervisor into these coordinators instead of cloning their room-facing logic.

The mechanical checkpoint passed formatting, compilation with warnings as errors, strict Credo,
the unused-dependency check, the focused 14-test regression set, and the complete 723-test umbrella
suite against a fresh disposable PostgreSQL 17 instance.

## Checkpoint 23: shared media pipeline signals

The Telnyx Membrane ingress and room-mix egress pipelines now publish the same ready, PCM-frame,
and delivery-acknowledgement messages consumed by the transport-neutral room media coordinators.
This removes a Telnyx-only message dialect without changing the provider wire format, codec chain,
or process registration. A focused red test first demonstrated that both pipelines still emitted
their old transport-prefixed signals; the smallest implementation change then made the four
pipeline tests pass.

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/telephony/telnyx/audio_ingress_pipeline_test.exs \
  test/vxpipe/gateway/telephony/telnyx/audio_egress_pipeline_test.exs
# 4 tests, 0 failures
```

The checkpoint also passed root formatting, compilation with warnings as errors, strict Credo,
the unused-dependency check, and all 723 umbrella tests against a fresh disposable PostgreSQL 17
instance.

## Checkpoint 24: authenticated live-event provenance

The provider-neutral live-event callback now receives the PID that synchronously submitted the
event to the exact leg owner. For Telnyx media this is the already-authenticated WebSocket process,
which gives the upcoming media session a safe egress target without embedding connection identity
in RTVI or trusting another provider field. The source remains internal runtime context; webhook
and media payload schemas are unchanged.

The focused tests first failed because the backend observer received no source, then passed after
the leg preserved its `GenServer.call/3` caller across both the initial media-start transition and
later running events:

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/telephony/call_ingress_test.exs \
  test/vxpipe/gateway/telephony/telnyx/media_socket_test.exs
# 8 tests, 0 failures
```

## Checkpoint 25: bounded direct phone playout

Direct synthesized speech could not safely reuse the WebRTC output process because that boundary
constructs RTP headers and owns a peer connection. A new transport-neutral `Media.AudioOutput`
coordinator instead owns project behavior: identity validation, 20 ms PCM framing, a bounded
500-frame queue, provider backpressure, one acknowledged frame in flight, playback callbacks, and
clean pipeline replacement on interruption. The implementation is split into state, validation,
buffering, delivery, and pipeline-lifecycle modules rather than collecting those concerns in one
large callback module.

Telnyx supplies a dedicated Membrane pipeline using the shared PCM source, Opus encoder, realtime
pacer, and socket sink. It emits only payload envelopes over the authenticated socket and does not
use FFmpeg. The PCM source was extended to accept the small transport-neutral playback frame as
well as room-mixer frames.

The coordinator test was first red because neither its module nor playback-frame contract existed;
the Telnyx pipeline test was separately red before its Membrane implementation existed. Focused
green evidence:

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/media/audio_output_test.exs \
  test/vxpipe/gateway/media/room_audio_egress_test.exs \
  test/vxpipe/gateway/webrtc/room_audio_output_pipeline_test.exs \
  test/vxpipe/gateway/telephony/telnyx/audio_egress_pipeline_test.exs \
  test/vxpipe/gateway/telephony/telnyx/audio_output_pipeline_test.exs
# 16 tests, 0 failures
```

Root formatting, compilation with warnings as errors, and strict Credo also pass. Live-leg
attachment and complete umbrella verification remain for the next checkpoint.

A pre-commit follow-up test caught two identity/clock details. `AudioOutputFrame.participant_id`
names the speaking agent rather than the human who owns the destination connection, so output
validation pins tenant, room, incarnation, and connection but permits that expected participant
difference. A natural second turn also keeps monotonically increasing Membrane timestamps on the
same realtime pipeline; only interruption resets the clock because it first replaces the entire
pipeline. The expanded six-test output/pipeline set passes after both corrections.

## Checkpoint 26: supervised live Telnyx media attachment

The live backend now responds to the first authenticated media-start event by creating one
temporary media subtree for the exact internal connection. The subtree attaches the phone
participant to the already-running room, supplies its direct output sink to the Call Engine, starts
the shared policy-aware room ingress and egress coordinators, and injects Telnyx-owned Membrane
pipelines through a small provider selection boundary. The common setup therefore contains no
Telnyx pipeline modules and is ready for a second provider to supply its own set.

Inbound Telnyx Opus enters both the enabled connection speech ingress and permitted room-audio
publication path. Direct agent PCM and permitted room-mix PCM leave through their respective
bounded coordinators and the same authenticated WebSocket owner. Overload/staleness outcomes remain
drops; fatal media failure stops the session. One significant temporary session and its dynamic
children use a `one_for_all` supervisor so no codec pipeline or coordinator is orphaned.

The first teardown test was intentionally red: stopping the attached room did not stop its media
connection within the two-second assertion window. The connection already received a room monitor
from Call Engine attachment, but the media session had not retained it in its monitored-owner set.
Adding that exact reference makes socket loss, leg-owner loss, and room loss all end the complete
connection subtree without a restart.

Red evidence:

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/telephony/media_session_test.exs
# 2 tests, 1 failure: room termination left the media connection alive
```

Focused green evidence:

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/telephony/media_session_test.exs \
  test/vxpipe/gateway/telephony/call_ingress_test.exs \
  test/vxpipe/gateway/telephony/telnyx/media_socket_test.exs
# 10 tests, 0 failures

mix test
# 155 tests, 0 failures (4 excluded)
```

Root formatting, warnings-as-errors compilation, strict Credo, and the unused-dependency check all
pass. Two initial umbrella runs each hit the existing timing-sensitive startup-readiness assertion:
the room had already exited and its newly installed monitor reported `:noproc` instead of the
expected shutdown reason. The owning lifecycle file passed all seven tests immediately, and the
complete Call Engine lane passed all 348 tests at the failing seed. A clean umbrella repeat then
passed all seven application lanes—731 tests with zero failures—against a fresh disposable
PostgreSQL 17 instance.

Outbound transfer dialing, private briefing, exact destination press-1 acceptance, AMD/failure
cleanup, and the deterministic full-call harness remain before this milestone is runnable.

## Checkpoint 27: signed outgoing-leg correlation

Telnyx dial commands already put Vxpipe's opaque internal leg ID into `client_state`, but the
webhook decoder discarded every outgoing initiation. That made a later signed event unusable for
binding an unknown immediate dial outcome to its pending transfer. A focused test first failed at
compilation because common telephony events had no internal leg field.

Common events now include a bounded `:outgoing` initiation carrying `leg_id`. The Telnyx decoder
accepts it only after the provider webhook has passed the existing signature boundary and the
payload's base64 JSON contains exactly a valid Vxpipe leg identifier. Missing, malformed, empty, or
oversized client state fails decoding rather than falling back to a phone number. A single Telnyx
`ClientState` module now owns command encoding plus webhook/media decoding, avoiding divergent
formats.

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/telephony/telnyx/webhook_decoder_test.exs \
  test/vxpipe/gateway/telephony/telnyx/media_decoder_test.exs \
  test/vxpipe/gateway/telephony/telnyx/adapter_test.exs
# 17 tests, 0 failures

cd apps/vxpipe_call_engine
mix test test/vxpipe/call_engine/telephony/adapter_test.exs
# 5 tests, 0 failures
```

This checkpoint supplies correlation only. The outbound leg owner, media-admission reservation,
dial submission, and pending-transfer control remain next.

Root formatting, warnings-as-errors compilation, strict Credo, and the unused-dependency check
pass. The umbrella test command again hit only the previously recorded startup-readiness monitor
race in Call Engine (`:noproc` after the room had already exited); the changed Gateway lane passed
all 156 tests. The complete 348-test Call Engine lane immediately passed at that failing umbrella
seed, so no unrelated lifecycle change was included in this checkpoint.

## Checkpoint 28: pending outbound media admission

A carrier dial request needs its media URL before its response supplies the exact provider call
identifiers. Issuing a fully bound token first would invent those identifiers; registering only
after the response would leave a race in which an early carrier upgrade receives a false 404.

`MediaAdmission` can now reserve one opaque token against an exact supervised leg and ingress key,
then bind the complete validated `MediaBinding`. At most one consumer waits while the reservation is
pending. A successful bind replies to that waiter and consumes the token atomically. Wrong ingress,
mismatched binding, a duplicate consumer, revocation, expiry, and owner death all retain the same
closed/non-enumerating behavior as ordinary single-use admissions.

The initial expiry test was red because an expired bind returned a mismatch and left the waiting
upgrade unresolved. The bind path now detects expiry first, drops the reservation, and releases the
waiter with `:invalid_media_token`.

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/telephony/media_admission_test.exs \
  test/vxpipe/gateway/http/telnyx_media_test.exs
# 11 tests, 0 failures
```

This is an admission primitive only. The outgoing leg owner will generate the reservation, submit
the dial without retry, and finalize it from an accepted response or the signed correlated event.

Root formatting, warnings-as-errors compilation, strict Credo, and the unused-dependency check
pass. A complete umbrella run passed all seven lanes—736 tests with zero failures—against a fresh
disposable PostgreSQL 17 instance. An earlier Gateway-only run hit an unrelated 100 ms room-output
teardown assertion; its owning six-test file immediately passed at the same seed.

## Checkpoint 29: accepted outbound provider identity

The Telnyx dial response already supplies call-control, call-leg, and call-session identifiers, but
the provider-neutral command result retained only call-control identity. That would force an
accepted outbound dial to wait for a later webhook before its reserved media URL could be bound to
the exact carrier leg.

`Telephony.Submission` now carries optional provider leg and session identifiers and validates any
supplied value as a non-empty string. Telnyx dial acceptance requires and preserves all three
identifiers returned by the Voice API. Answer and end-leg submissions remain valid without the two
new values because those operations already act on an adopted exact leg.

The focused adapter assertion was first red because the neutral struct had neither field. Green
evidence:

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/telephony/telnyx/adapter_test.exs
# 6 tests, 0 failures

cd apps/vxpipe_call_engine
mix test test/vxpipe/call_engine/telephony/adapter_test.exs
# 5 tests, 0 failures
```

This checkpoint preserves response identity only. The supervised outgoing owner will consume it to
bind the pending media reservation; signed outgoing webhook correlation remains necessary for an
unknown immediate submission.

Root formatting, warnings-as-errors compilation, strict Credo, and the unused-dependency check
pass. The first umbrella run reached the previously recorded 100 ms room-output teardown assertion
in the unchanged Gateway media test. Its owning six-test file passed immediately at the same seed;
a clean umbrella repeat then passed all seven lanes—736 tests with zero failures—against the
existing isolated PostgreSQL 17 test instance.
