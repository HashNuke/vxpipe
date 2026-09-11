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
