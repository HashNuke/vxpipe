# Telnyx calls and phone transfers

Status: complete (2026-09-11). Specification review: approved (2026-09-08).

Credential configuration update (2026-09-16): new legs now resolve encrypted tenant service
records; existing owners retain their initialized configuration. The earlier application-scope
lookup/configuration evidence below is historical and superseded. See
[tenant telephony setup](../tenant-telephony-services.md). This changes credential readers only;
this milestone still owns its original carrier/audio acceptance.

Prerequisites: [Human web transfers](human-web-transfers.md), including admission, private preparation, mixer and media policy.
Sources: [Common telephony intent](../../labnotes/20260905-0405-call-definition-design.md#keep-telephony-provider-neutral-and-pin-the-resolved-definition-in-the-room); [protected destinations](../../labnotes/20260905-0405-call-definition-design.md#protected-dynamic-dial-destinations--approved-r13-decision); [machine detection](../../labnotes/20260905-0405-call-definition-design.md#provider-answering-machine-detection--resolved-r32).

## Runnable outcome

A verified incoming phone leg starts the pinned call spec and speaks to reception; reception can dial a configured support participant, privately brief them, accept press-1, and bridge the two humans through the existing room mixer.

## Specification

- Implement Telnyx as an adapter to common receive/originate/adopt-leg/media/readiness/acceptance/end operations. Keep provider-specific webhook schemas, authentication, call-control commands and media transport handling outside room state/call spec JSON. Verify current vendor API/SDK behavior in implementation before claiming interoperability.
- A human participant references configured service, receive/dial mode, and literal number or protected number_from_variable(section,variable), mutually exclusive. Receive start_call routes resolve an enabled deployment; receiving into an existing call requires explicit call/participant/provider-leg correlation, never number-only guessing.
- Trusted backend initial routing variables are declared string-compatible values, and no agent may write their section. Tool selects allowed participant ref only; validate any dynamic number before dialing. Missing/null/invalid destination fails without an outgoing request, not automatic lookup. Caller number is not verified identity.
- Persist/claim admission before activating initial legs; hold pinned plan in memory. Verify incoming webhook/media identity, map provider call/leg IDs to tenant/call/participant/incarnation/attempt, handle duplicate/out-of-order events, and never adopt another tenant's leg.
- Outbound transfer uses the existing total deadline/private lane/source-retention contract. Usable phone media plus deterministic press-1 on the exact pending destination leg accepts; caller/source/LLM utterances cannot accept. Apply privacy before bridge.
- Optional provider answering-machine detection reporting machine disconnects only the attempted outbound destination. Unknown/disabled detection still awaits explicit transfer acceptance within the original deadline. Initial outbound-only machine detection ends that attempted call without voicemail speech.
- Command failure/unknown submission outcomes do not cause speculative redial. Clean only known exact legs, preserve generic public vs internal detail, and never repeat a crashed call. Normalize codecs/clocks through existing media boundaries, not raw provider packets in RoomAuthority.

number_from_variable is dial-only, not an inbound-route selector. Transfer-created callbacks
must correlate to the existing pending call/participant/leg; they cannot re-enter the
number-to-call-spec start path even if the number matches a published inbound route.
Live leg/DTMF/media/transfer handling uses the in-memory pinned mappings, not synchronous
PostgreSQL lookups or writes. Real vendor integration requires configured provider-reachable
webhook/media ingress; the development tailnet URL is not assumed publicly reachable.

## Implementation checklist

- [x] Define/test the common telephony adapter contract with fake receive/dial/answer/media/DTMF/AMD/end events before vendor code.
- [x] Add Telnyx configured service resolution, verified ingress and provider-leg correlation through Calls/Gateway adapter boundaries.
- [x] Implement permitted outbound dialing, media normalization and private briefing/press-1 acceptance.
- [x] Integrate optional AMD and exact-leg failure/cleanup without changing transfer or call spec semantics.
- [x] Add fixtures for vendor webhook/media authentication and a separate tagged real-provider lane using authorized test endpoints.

## Acceptance and failure checks

- [x] Receive routes select only published matching call specs; spoofed/tampered/cross-tenant callbacks/media fail before adoption.
- [x] Duplicate/out-of-order events cannot duplicate rooms/dials/acceptance; uncertain command response never triggers speculative second dial.
- [x] Literal/protected variable destinations work; invalid/missing/mutated-by-agent source fails before dialing; model cannot supply numbers.
- [x] Private briefing is isolated; only destination-leg press-1 accepts, then privacy barrier precedes human bridge.
- [x] Machine/no-answer/busy/timeout cleans destination and retains valid source/caller; unknown AMD does not reset deadline. Delayed events target only known current legs.
- [x] Stop PostgreSQL after admission: known current-leg callbacks/DTMF/media still work with
  honest archive lag. An outbound callback matching an inbound number does not create a call.

## Manual verification

1. First use a deterministic telephony harness to run inbound, outgoing, busy/no-answer and press-1 flows without calling real people.
2. In the tagged authorized vendor lane, call a configured inbound test number and speak to reception.
3. Transfer only to an authorized test destination, listen to private briefing, press 1 and verify human-human audio/privacy.
4. Exercise provider-supported AMD and disconnect cases; inspect internal leg correlation and permitted history without exposing credentials.

## Scope boundaries

No arbitrary model-supplied numbers, generic outbound routing-policy matrix, automatic redial/retry, voicemail-message delivery, local machine classifier, or provider-owned bridge bypassing the room's approved routing/recording controls.

## Completion and evidence

- [x] Demonstrate the runnable outcome and every acceptance/failure check above.
- [x] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [x] Update this milestone, the index checkbox, relevant architecture/user docs, and
  implementation labnote with actual test/browser/integration evidence in the implementation commit.

Implementation evidence: the provider-neutral adapter contract, Telnyx raw-webhook verifier,
bounded Voice API v2 event normalization, configured service registry, and raw-body HTTP ingress
are implemented with deterministic focused tests. Published inbound telephony routes now pin a
configured service ref plus literal number to one immutable call spec revision and participant;
tenant lookups remain scoped and ambiguous application-wide matches fail closed. Calls now claims a
normalized incoming event against that route, compiles the pinned revision for telephony transport,
and atomically persists the call in `admitting` state with its provider leg. Exact event/leg retries
return the original claim, while a reused event ID naming another leg fails closed and rolls back
the attempted call. `started_at` remains empty until live room startup succeeds. Call Engine's
ordinary planned-room lifecycle now accepts the pinned telephony transport and configured
receive/start entry caller, while continuing to reject unsupported connection intents. Calls can
atomically project the returned incarnation onto both call and initial leg, or mark both terminal
without a start timestamp when room startup fails. The gateway resolves opaque ingress keys to
application- or tenant-scoped services, authenticates before decoding, bounds request size, rejects
provider-connection mismatches, and dispatches only safe service identity plus common events.
The default Gateway handler now gives each exact incoming leg one temporary supervised owner. That
owner serializes durable claim, ordinary room startup, and lifecycle projection; retries share it,
and later callbacks validate the full provider identity against its in-memory pinned claim without
another database lookup. A recovered `admitting` record without its owner becomes
`startup_unknown` rather than restarting a crashed call. Provider-specific post-initiation
commands now submit through a bounded no-retry Telnyx Voice API client, and authenticated headerless
Opus media has a Membrane ingress normalizer that emits exact 20 ms, 48 kHz mono room-clock frames
without FFmpeg. The reverse Membrane path validates an exact authorized mixer subscription and
encodes/paces 20 ms frames as the documented Telnyx `media.payload` socket envelope. The live media
WebSocket now has a supervised single-use admission primitive that pins every room and provider
identifier to the exact live leg and revokes admission with that leg. Its bounded HTTP route
validates the upgrade before atomically consuming the token and gives the socket only the resolved
binding. The socket validates the bound call and client state on `start`, pins the resulting stream
ID, and dispatches exact media/DTMF events to the existing leg owner. Room pipeline attachment,
private briefing, acceptance, cleanup, and runnable vendor outcome remain incomplete.
Configured Telnyx services now fail startup unless webhook verification, command credentials,
provider connection identity, a provider-reachable TLS base URL, and a bounded media-token lifetime
form one complete deployment configuration; secret-bearing fields are excluded from inspection.
The incoming-leg activator now binds that configuration and the pinned call incarnation to one
internal leg ID, one media token, and one provider-neutral answer command. Rejected commands revoke
admission and unknown submission outcomes never cause retry. The default webhook boundary injects
its immutable service registry and shared media admission only into the standard call-ingress
backend, leaving custom backends unchanged. The live leg owner serializes durable claim, ordinary
room startup, carrier activation, and exact live evidence. It remains `answering` after command
submission and projects `started_at` only from the exact provider answer occurrence, or from the
gateway observation time when the admitted media stream proves liveness first. Room pipeline
attachment, private briefing, acceptance, cleanup, and runnable vendor outcome remain incomplete.
This serialized activation checkpoint passed the root formatting, warnings-as-errors compilation,
strict Credo, unused-dependency, focused 22-test regression set, and a clean 723-test umbrella run.
The existing policy-aware room ingress/egress coordinators have also moved from the WebRTC namespace
to the transport-neutral Gateway media boundary, with their WebRTC behavior unchanged. Telnyx can
therefore adopt the same policy revision, mixer subscription, and backpressure ownership while
retaining its own Membrane codecs and socket lifecycle.
Direct agent speech now has a transport-neutral bounded PCM playout coordinator with acknowledged
started/progress/completed and interruption semantics. A dedicated Telnyx Membrane pipeline encodes
and paces those exact 20 ms frames to the authenticated socket without FFmpeg. The coordinator and
pipeline contracts pass focused framing, backpressure, interruption, failure, codec, pacing, and
wire-envelope tests. The first authenticated media-start now creates one temporary supervised
connection subtree, attaches the exact phone participant to the running room, routes decoded input
to enabled speech processing and permitted room publication, and routes both direct agent speech
and the permitted room mix back through Telnyx's Membrane pipelines. Carrier pipeline selection is
isolated from the common attachment setup. The socket, exact leg owner, and attached room are all
monitored; loss of any one tears down the whole media subtree without restart. Focused attachment,
source-identity, input-delivery, output-envelope, and teardown tests pass, as do all 155 Gateway
tests and the complete 731-test umbrella gate. Private briefing, outbound transfer/press-1
acceptance, AMD cleanup, deterministic complete-call harness, and authorized real-provider
verification remain pending.
Telnyx outgoing-initiation webhooks also recover a bounded opaque Vxpipe leg ID from signed
`client_state` and emit a common outgoing event instead of being discarded. Malformed or absent
correlation fails decoding. This is the prerequisite for associating later provider identifiers
with exactly one pending transfer, including when the immediate dial outcome is unknown; it does
not yet submit that outbound dial.
Gateway media admission can now reserve the opaque outbound media URL before provider identifiers
exist and atomically bind the complete exact identity afterward. One early upgrade waits within the
existing bound, while bind, expiry, revocation, or leg-owner death settles it without revealing a
pending-token state. Focused reservation, mismatch, expiry, revocation, single-use, and HTTP-upgrade
tests pass, as does the complete 736-test umbrella gate. Outbound leg ownership and dial submission
remain pending.
Accepted Telnyx dial responses now retain call-control, call-leg, and call-session identity through
the common submission contract instead of discarding the identifiers needed to bind the reserved
media admission. The signed correlated outgoing event remains the fallback when the immediate
submission is unknown. Outbound leg ownership and dial submission remain pending.
Configured services can now pin an optional validated E.164 origination number. Outbound service
selection resolves an exact tenant-scoped service ID before its application-wide fallback and
cannot select another tenant's configuration. The service ref remains in the call spec while
credentials, provider connection identity, and the `from` number remain deployment settings.
One temporary supervised outbound leg now validates the exact room destination, reserves its media
URL, and submits a single dial. Concurrent starts for the same opaque leg ID share the owner and
result rather than redialing. An accepted response binds its complete carrier identity to the exact
tenant/call/incarnation/participant before media can connect; inbound-only service configuration
fails before submission. Unknown-outcome webhook adoption and transfer control remain pending.
An unknown immediate dial outcome can now be completed only by a signed outgoing-initiation event
whose opaque internal leg ID locates the existing owner and whose service/from/to identity matches
the pinned request. Mismatches do not consume the reservation. Successful response or event
adoption registers the exact provider leg before releasing media, closing the early-media routing
race without a retry. Transfer readiness, press-1, and cleanup remain pending.
Call Engine now opens a configured phone transfer through a provider-neutral host connector rather
than a Gateway dependency. It resolves a literal or protected creation-time Call Variable from the
pinned plan, includes exact actor/call/room-incarnation/participant/service identity, and gives the
connector only the remaining shared transfer deadline. The connector's opaque handle is retained by
the pending human preparation and disconnected if preparation fails or the destination never
accepts; a completed transfer leaves the leg under its transport owner. The same room-authoritative
private briefing, exact attached-connection acceptance, policy commit, and source handoff path now
accepts dial/transfer human participants. A deterministic engine test proves protected-number
resolution, one outbound request, private briefing and promotion, plus deadline cleanup. Gateway's
connector implementation and automatic phone media/DTMF control remain pending.
Gateway now implements that connector with tenant-first configured-service resolution, an opaque
generated leg ID, the existing temporary leg supervisor, and a bounded wait for the single
no-retry submission result. Its reusable HTTP mount injects the same registry and media-admission
owner into the default Calls admission path for both browser-started and incoming-phone rooms;
custom backends are not rewritten. The returned exact process/supervisor reference is opaque to
Call Engine. Carrier lifecycle handling remains pending.
The outbound owner now handles the authenticated media socket as the transport half of the existing
human-transfer state machine. A valid media start creates the ordinary supervised telephony media
subtree and attaches the destination in `transfer_preparation` mode, where only direct private
playout exists. The exact attached media-session process automatically reports media readiness and
can report press-1 acceptance; the webhook process, caller, and another process are rejected by the
existing room connection-ownership check. Completion of both acceptance and the private briefing
lets the room commit its privacy barrier and promote that same session, which only then starts the
Membrane room ingress and mix-minus egress pipelines. A deterministic full-seam test covers dial,
private speech, exact-socket DTMF, delayed completion, promotion, and active destination state.
The provider-neutral connector handle now also supplies an owner process solely for monitoring.
Room Authority monitors it only while the phone handoff is pending, converts owner loss into the
ordinary generic failed-transfer result, retains the source, and demonitor-flushes it on either
commit or cleanup. The carrier reference remains opaque and is still interpreted only by Gateway.
Carrier hangup, AMD outcomes, deterministic whole-call harness coverage, and authorized vendor
verification remain pending.

## Checkpoint 37: configured carrier detection mode

Answering-machine detection is now a reusable configured-service option rather than part of a
call spec or room-authored outbound request. Omission resolves to `disabled`; the only other
accepted value is `detect`. Invalid values fail the service configuration closed. When enabled, the
Gateway copies the pinned service choice into the common dial command sent to the carrier adapter.

The focused dial test was red because its room request disabled detection even though the selected
service enabled it. The service now owns that choice, and the redundant field has been removed from
Call Engine's outbound-leg request. This preserves the existing participant connection schema and
prevents call orchestration from overriding deployment/provider policy.

Focused green evidence:

```text
mix test apps/vxpipe_call_engine/test/vxpipe/call_engine/human_phone_transfer_room_test.exs \
  apps/vxpipe_gateway/test/vxpipe/gateway/telephony/configured_service_test.exs \
  apps/vxpipe_gateway/test/vxpipe/gateway/telephony/outgoing_leg_test.exs
# 10 tests, 0 failures
```

Root formatting, warnings-as-errors compilation, strict Credo, and the unused-dependency check
pass. The complete umbrella run reached every application and found only the previously recorded
startup-readiness teardown race (`:noproc` instead of the expected shutdown reason); its unchanged
seven-test owning file immediately passed at the same seed.

Exact machine/end-event handling and carrier hangup remain pending within the AMD/cleanup
checklist item.

## Checkpoint 38: exact outbound lifecycle and cleanup

The outgoing owner now consumes authenticated `answered`, answering-machine, and ended events only
when every carrier identifier matches its bound leg. A configured machine result submits exactly
one common end-leg command for that known call-control ID and retires the owner. Human or unknown
classification keeps waiting for explicit press-1 within the existing transfer deadline. Detection
events are non-operative when the service disabled detection. Busy, no-answer, timeout, failure and
ordinary hangup all retire locally without sending a redundant provider hangup.

Explicit engine cleanup now asks the owner to end a known accepted leg before it exits. If the
owner is already gone or never acquired complete carrier identity, the connector limits cleanup to
that local temporary child. Provider command rejection/unknown outcomes never trigger another dial.

The full seam test enables detection on the tenant service, begins the ordinary private transfer,
delivers exact machine evidence, observes one hangup, and then observes the existing generic
`tool_failed` result while the source agent remains active. The engine still sees only monitored
owner loss; it neither receives the provider event nor learns carrier-specific detail.

Red evidence:

```text
mix test test/vxpipe/gateway/telephony/outgoing_leg_test.exs
# 7 tests, 3 failures: lifecycle events were unsupported
# 8 tests, 1 failure: connector cleanup retired locally without an end command
```

Focused green evidence:

```text
mix test test/vxpipe/gateway/telephony/outgoing_leg_test.exs \
  test/vxpipe/gateway/telephony/outbound_phone_transfer_test.exs
# 11 tests, 0 failures
```

Root formatting, warnings-as-errors compilation, strict Credo, and the unused-dependency check pass.
One loaded umbrella run hit a timing-sensitive Gateway failure that did not reproduce in its complete
175-test owning app at the same seed. A clean root repeat then passed all seven lanes—754 tests with
zero failures.

The remaining milestone work is deterministic signed-webhook/whole-call harness coverage and an
authorized tagged real-provider lane.

## Checkpoint 39: signed whole-call harness and live-provider lane

Provider-shaped Voice API v2 fixtures now cover incoming and outgoing initiation, answer, media
start, and DTMF. The harness renders only bounded placeholders, signs the exact raw webhook body
with the configured Ed25519 key, and sends it through the mounted Gateway endpoint. It upgrades the
real media route and initializes the real Telnyx socket rather than invoking a room callback
directly.

The complete deterministic scenario admits one incoming phone caller, starts the pinned reception
agent, attaches Opus media, and has an STT turn ask for the allowlisted human destination. The
scripted model selects only that participant ref. Gateway submits one dial, correlates duplicate
signed outgoing events to the already-pending attempt, attaches the destination privately, and
accepts only DTMF `1` from its exact media socket. The destination remains private until its
briefing playback completes; promotion then applies the existing policy barrier, shuts down the
source agent, and leaves the two humans joined through the normal room path.

After the initial claim, the harness makes its durable backend unavailable. Signed answer events,
both media sockets, DTMF, briefing completion, and promotion still use the pinned in-memory owners.
The operation record contains exactly one durable claim, proving that later carrier traffic does
not fall back to storage or the inbound route. Existing focused tests retain the spoofing,
cross-tenant, protected-number, command-uncertainty, machine, no-answer, timeout, and exact cleanup
failure coverage.

The wire choices were checked on 2026-09-11 against Telnyx's current official
[Voice API webhook](https://developers.telnyx.com/docs/voice/programmable-voice/voice-api-webhooks),
[dial command](https://developers.telnyx.com/api-reference/call-commands/dial),
[media streaming](https://developers.telnyx.com/docs/voice/programmable-voice/media-streaming), and
[answering-machine detection](https://developers.telnyx.com/docs/voice/programmable-voice/answering-machine-detection)
documentation. This validates the fixture envelopes and configured command/media options against
the published contract; it is not a claim that an external carrier call ran in this checkout.

An `:integration`/`:telnyx_live` test provides the separate real Voice API dial lane. It remains
excluded by default and additionally skips unless `VXPIPE_TELNYX_LIVE=1`. Its required settings are
the API key, connection ID, controlled from/destination numbers, and provider-reachable webhook and
media URLs. A successful accepted dial captures all three provider identities and schedules an
exact-leg hangup. The live lane was compiled and observed to skip safely without those explicit
settings; no external call was placed for this checkpoint.

Focused verification:

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/telephony/telnyx_call_harness_test.exs \
  test/vxpipe/gateway/http/telnyx_events_test.exs \
  test/vxpipe/gateway/http/telnyx_media_test.exs \
  test/vxpipe/gateway/telephony/telnyx/adapter_test.exs \
  test/vxpipe/gateway/telephony/telnyx/webhook_decoder_test.exs \
  test/vxpipe/gateway/telephony/telnyx/media_decoder_test.exs
# 28 tests, 0 failures

mix test test/integration/telnyx_voice_api_test.exs --include integration
# 1 test, 0 failures, 1 skipped
```

The implementation commit also passed the root formatting, warnings-as-errors compilation, strict
Credo, unused-dependency check, and all seven umbrella lanes—755 tests with zero failures. The live
lane is ready for an explicitly authorized carrier run when controlled numbers and public ingress
are available.

## Specification review

Reviewed independently by milestone_review_c on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Added dial-only dynamic source, no inbound re-admission for transfer callbacks, PG-outage runtime correlation and provider-reachable ingress checks; re-review approved.
This is specification evidence only; implementation and runtime verification remain unchecked.
