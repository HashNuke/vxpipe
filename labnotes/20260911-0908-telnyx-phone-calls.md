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

## Next checkpoint

Define and exercise the common adapter command/event contract with a deterministic fake before
adding Telnyx webhook, command, or media code. Then connect verified ingress and provider-leg
correlation through Calls and Gateway.
