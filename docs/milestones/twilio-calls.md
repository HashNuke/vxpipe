# Twilio through the common telephony contract

Status: not implemented. Specification review: approved (2026-09-08).
Prerequisites: [Telnyx/common telephony slice](telnyx-calls.md), including its tested provider-neutral adapter contract.
Sources: [Common telephony boundary](../../labnotes/20260905-0405-call-definition-design.md#keep-telephony-provider-neutral-and-pin-the-resolved-definition-in-the-room); [transfer and machine behavior](../../labnotes/20260905-0405-call-definition-design.md#transfer-success-and-failure--approved-g8-baseline); [R32](../call-definition-gap-review.md).

## Runnable outcome

Switch a configured telephony service to Twilio and run the same inbound-agent and outgoing-human-transfer scenarios without changing the participant/transfer/media policy schema or room orchestration.

## Specification

- Implement a second adapter for the same receive/dial/adopt/media/accept/end contracts. Resolve vendor details from application/tenant service configuration; do not embed Twilio command payloads or credentials in participants.
- Verify current vendor webhook/control-response/media APIs during implementation; adapt their real flow rather than assuming the first provider's webhook/API sequence. Prove bidirectional media and usable caller/destination audio through Vxpipe mixing before declaring support.
- Gateway adapter authenticates vendor ingress and normalizes provider/session/leg IDs. Calls selects/pins initial definitions and shared admission; active transfers resolve their existing in-memory participant target, never reselect deployment from a phone number.
- Preserve protected initial-variable dialing, explicit destination-leg press-1 acceptance, isolated briefing/optional notice, privacy-before-bridge, total deadline, one bounded permitted source restoration and internal-only technical reasons.
- Use optional provider AMD where configured; machine disconnects attempted leg, unknown waits acceptance without resetting deadline. Duplicate/out-of-order/late callbacks cannot redial, re-admit or complete another transfer. Unknown submission is not remote failure or permission to retry.
- Normalize provenance for media clocks and future usage/request IDs without inventing equivalence across carriers. Shared models/interfaces change only if a genuine common requirement is discovered and covered for both adapters.

## Implementation checklist

- [ ] Reuse common telephony contract tests with Twilio fakes; add red cases for vendor-specific verification and callback/media correlation.
- [ ] Implement configured Twilio authentication/control/media adapter in proper gateway/provider boundaries.
- [ ] Run inbound and outgoing private-transfer acceptance through the existing room mixer and policy barrier.
- [ ] Exercise AMD/DTMF/timeout/cleanup and parity with the first adapter.
- [ ] Add tagged real-provider tests and document supported transport/control combinations without untested compatibility claims.

## Acceptance and failure checks

- [ ] Same portable participant definition works by resolving another configured service; no provider-specific room logic is required.
- [ ] Tampered/cross-tenant media or callbacks reject; duplicates/out-of-order events keep one mapped attempt and no speculative retries.
- [ ] Protected-number violations reject before dial; only destination press-1 accepts and briefing remains private.
- [ ] Machine/unknown/busy/no-answer/timeout outcomes preserve the common source/cleanup rules and privacy restrictions.
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

## Specification review

Reviewed independently by milestone_review_a on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Approved initial draft; shared contract order and separate vendor verification, media/acceptance/failure parity sufficient.
This is specification evidence only; implementation and runtime verification remain unchecked.
