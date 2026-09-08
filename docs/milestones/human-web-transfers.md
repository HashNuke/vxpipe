# Private briefing and human web acceptance

Status: not implemented. Specification review: approved (2026-09-08).
Prerequisites: [Prepared admission](prepared-call-admission.md); [Agent transfers](agent-transfers.md); [Live mixing/media policy](live-mixing-and-media-policy.md).
Sources: [Human transfer acceptance/briefing](../../labnotes/20260905-0405-call-definition-design.md#transfer-success-and-failure--approved-g8-baseline); [commit barrier](../../labnotes/20260905-0405-call-definition-design.md#retained-transfer-and-media-enforcement-invariants).

## Runnable outcome

Reception prepares a human web destination. That person privately hears permitted caller/purpose information and an optional configured notice, explicitly accepts, and then joins the caller. The AI subtree ends while the human-human call and Call Variables remain live.

## Specification

- The destination is a catalog participant, not a free-form address or new participant instance. Use the same tenant/call/participant-scoped first-admission token path; preparation/connection alone grants no main-room audio or transcript access.
- Isolate private briefing/configured notice in the authorized preparation lane. Caller cannot hear it; destination receives only minimum permitted variables/history, not full room media. Use the applicable permitted source voice without inventing a new voice hierarchy.
- Human readiness requires usable media and explicit acceptance. Client owns acceptance presentation; gateway receives an authenticated control message bound to destination participant, connection and current pending attempt. Specify and test a Vxpipe adapter extension/sideband control, not an invented RTVI-core event.
- Source/model/caller cannot accept for destination. Duplicate/stale/late acceptance cannot commit twice or another attempt. Keep one total 30-second transfer deadline including private preparation; preserve source until commit/failure.
- At commit apply destination while_present privacy restrictions before main bridge, then change control and terminate source agent subtree. active agent nil is valid; variables, allowed live transcripts, duration and authorized monitoring continue independently.
- Failure/timeout cleans only the pending destination, source handles typed outcome with approved single recovery limit. Detailed restoration cause remains internal, including full sample visibility.

## Implementation checklist

- [ ] Red-test private lane isolation and destination-bound acceptance with two authenticated web clients.
- [ ] Implement human preparation/readiness on common room transfer state machine and token/session mapping.
- [ ] Specify narrow authenticated web acceptance wire contract and client fixture without changing RTVI-core semantics.
- [ ] Connect minimum-necessary briefing/notice output, privacy commit barrier and human-only continuation.
- [ ] Add an isolated sample/test client entry point for destination acceptance only if needed; keep developer console uncluttered.

## Acceptance and failure checks

- [ ] Before acceptance destination cannot hear caller/main room; caller cannot hear private briefing.
- [ ] Forged source/caller/other-connection, stale and duplicate acceptance reject; timeout/late readiness cannot bridge.
- [ ] Consent/acceptance alone does not bypass policy application; failed privacy barrier leaves source responsible with no leaked media.
- [ ] After commit source capabilities/workers end, two humans converse and variables survive; original start/duration clocks remain.
- [ ] Busy/failing/dropped destination cleans exact attempt and does not terminate a still-valid caller/source conversation.
- [ ] Pre-commit isolation blocks destination microphone publishing as well as main-room
  listening/transcripts; no unrestricted variables/history snapshot reaches that destination.
- [ ] Early acceptance cannot bypass usable media and private briefing/configured-notice
  sequencing. Define exact early-accept handling; enqueued audio is not completed playback.

## Manual verification

1. Start a caller/reception/support definition with a permitted briefing and restrictive support while_present policy.
2. Open a separate authenticated destination client; listen privately and verify the caller hears none of the briefing.
3. Accept through the client control, then converse human-to-human and inspect absence of the agent subtree.
4. Repeat with decline/no acceptance, stale acceptance, and privacy-apply failure using controlled fixtures.

## Scope boundaries

No platform-mandated acceptance button/UI design, phone provider yet, blanket regulatory-compliance claim, general concurrent-agent consultation, or implicit full transcript/variable access for a human destination.

## Completion and evidence

- [ ] Demonstrate the runnable outcome and every acceptance/failure check above.
- [ ] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [ ] Update this milestone, the index checkbox, relevant architecture/user docs, and
  implementation labnote with actual test/browser/integration evidence in the implementation commit.

Implementation evidence: none yet. Do not mark this slice complete because its specification
has been reviewed.

## Specification review

Reviewed independently by milestone_review_b on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Added bidirectional private-lane isolation, transcript/snapshot restrictions and early-acceptance sequencing tests; re-review approved.
This is specification evidence only; implementation and runtime verification remain unchecked.
