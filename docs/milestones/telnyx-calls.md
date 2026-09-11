# Telnyx calls and phone transfers

Status: not implemented. Specification review: approved (2026-09-08).
Prerequisites: [Human web transfers](human-web-transfers.md), including admission, private preparation, mixer and media policy.
Sources: [Common telephony intent](../../labnotes/20260905-0405-call-definition-design.md#keep-telephony-provider-neutral-and-pin-the-resolved-definition-in-the-room); [protected destinations](../../labnotes/20260905-0405-call-definition-design.md#protected-dynamic-dial-destinations--approved-r13-decision); [machine detection](../../labnotes/20260905-0405-call-definition-design.md#provider-answering-machine-detection--resolved-r32).

## Runnable outcome

A verified incoming phone leg starts the pinned definition and speaks to reception; reception can dial a configured support participant, privately brief them, accept press-1, and bridge the two humans through the existing room mixer.

## Specification

- Implement Telnyx as an adapter to common receive/originate/adopt-leg/media/readiness/acceptance/end operations. Keep provider-specific webhook schemas, authentication, call-control commands and media transport handling outside room state/definition JSON. Verify current vendor API/SDK behavior in implementation before claiming interoperability.
- A human participant references configured service, receive/dial mode, and literal number or protected number_from_variable(section,variable), mutually exclusive. Receive start_call routes resolve an enabled deployment; receiving into an existing call requires explicit call/participant/provider-leg correlation, never number-only guessing.
- Trusted backend initial routing variables are declared string-compatible values, and no agent may write their section. Tool selects allowed participant ref only; validate any dynamic number before dialing. Missing/null/invalid destination fails without an outgoing request, not automatic lookup. Caller number is not verified identity.
- Persist/claim admission before activating initial legs; hold pinned plan in memory. Verify incoming webhook/media identity, map provider call/leg IDs to tenant/call/participant/incarnation/attempt, handle duplicate/out-of-order events, and never adopt another tenant's leg.
- Outbound transfer uses the existing total deadline/private lane/source-retention contract. Usable phone media plus deterministic press-1 on the exact pending destination leg accepts; caller/source/LLM utterances cannot accept. Apply privacy before bridge.
- Optional provider answering-machine detection reporting machine disconnects only the attempted outbound destination. Unknown/disabled detection still awaits explicit transfer acceptance within the original deadline. Initial outbound-only machine detection ends that attempted call without voicemail speech.
- Command failure/unknown submission outcomes do not cause speculative redial. Clean only known exact legs, preserve generic public vs internal detail, and never repeat a crashed call. Normalize codecs/clocks through existing media boundaries, not raw provider packets in RoomAuthority.

number_from_variable is dial-only, not an inbound-route selector. Transfer-created callbacks
must correlate to the existing pending call/participant/leg; they cannot re-enter the
number-to-definition start path even if the number matches a published inbound route.
Live leg/DTMF/media/transfer handling uses the in-memory pinned mappings, not synchronous
PostgreSQL lookups or writes. Real vendor integration requires configured provider-reachable
webhook/media ingress; the development tailnet URL is not assumed publicly reachable.

## Implementation checklist

- [x] Define/test the common telephony adapter contract with fake receive/dial/answer/media/DTMF/AMD/end events before vendor code.
- [ ] Add Telnyx configured service resolution, verified ingress and provider-leg correlation through Calls/Gateway adapter boundaries.
- [ ] Implement permitted outbound dialing, media normalization and private briefing/press-1 acceptance.
- [ ] Integrate optional AMD and exact-leg failure/cleanup without changing transfer or definition semantics.
- [ ] Add fixtures for vendor webhook/media authentication and a separate tagged real-provider lane using authorized test endpoints.

## Acceptance and failure checks

- [ ] Receive routes select only published matching definitions; spoofed/tampered/cross-tenant callbacks/media fail before adoption.
- [ ] Duplicate/out-of-order events cannot duplicate rooms/dials/acceptance; uncertain command response never triggers speculative second dial.
- [ ] Literal/protected variable destinations work; invalid/missing/mutated-by-agent source fails before dialing; model cannot supply numbers.
- [ ] Private briefing is isolated; only destination-leg press-1 accepts, then privacy barrier precedes human bridge.
- [ ] Machine/no-answer/busy/timeout cleans destination and retains valid source/caller; unknown AMD does not reset deadline. Delayed events target only known current legs.
- [ ] Stop PostgreSQL after admission: known current-leg callbacks/DTMF/media still work with
  honest archive lag. An outbound callback matching an inbound number does not create a call.

## Manual verification

1. First use a deterministic telephony harness to run inbound, outgoing, busy/no-answer and press-1 flows without calling real people.
2. In the tagged authorized vendor lane, call a configured inbound test number and speak to reception.
3. Transfer only to an authorized test destination, listen to private briefing, press 1 and verify human-human audio/privacy.
4. Exercise provider-supported AMD and disconnect cases; inspect internal leg correlation and permitted history without exposing credentials.

## Scope boundaries

No arbitrary model-supplied numbers, generic outbound routing-policy matrix, automatic redial/retry, voicemail-message delivery, local machine classifier, or provider-owned bridge bypassing the room's approved routing/recording controls.

## Completion and evidence

- [ ] Demonstrate the runnable outcome and every acceptance/failure check above.
- [ ] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [ ] Update this milestone, the index checkbox, relevant architecture/user docs, and
  implementation labnote with actual test/browser/integration evidence in the implementation commit.

Implementation evidence: the provider-neutral adapter contract, Telnyx raw-webhook verifier,
bounded Voice API v2 event normalization, configured service registry, and raw-body HTTP ingress
are implemented with deterministic focused tests. Published inbound telephony routes now pin a
configured service ref plus literal number to one immutable definition revision and participant;
tenant lookups remain scoped and ambiguous application-wide matches fail closed. Calls now claims a
normalized incoming event against that route, compiles the pinned revision for telephony transport,
and atomically persists the call in `admitting` state with its provider leg. Exact event/leg retries
return the original claim, while a reused event ID naming another leg fails closed and rolls back
the attempted call. `started_at` remains empty until live room startup succeeds. The gateway
resolves opaque ingress keys to
application- or tenant-scoped services, authenticates before decoding, bounds request size, rejects
provider-connection mismatches, and dispatches only safe service identity plus common events.
Gateway-to-Calls dispatch, live room/incarnation ownership, commands, media, and the runnable vendor
outcome remain incomplete; do not mark this slice complete or check the second implementation item
yet.

## Specification review

Reviewed independently by milestone_review_c on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Added dial-only dynamic source, no inbound re-admission for transfer callbacks, PG-outage runtime correlation and provider-reachable ingress checks; re-review approved.
This is specification evidence only; implementation and runtime verification remain unchecked.
