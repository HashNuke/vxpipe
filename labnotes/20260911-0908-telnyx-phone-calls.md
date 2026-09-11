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
