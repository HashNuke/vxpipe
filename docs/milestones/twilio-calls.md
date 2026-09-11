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

## Specification review

Reviewed independently by milestone_review_a on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Approved initial draft; shared contract order and separate vendor verification, media/acceptance/failure parity sufficient.
This is specification evidence only; implementation and runtime verification remain unchecked.
