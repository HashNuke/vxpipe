# Private briefing and human web acceptance

Status: partially implemented. The protocol-neutral private room lane, exact destination control,
briefing playback barrier, authenticated gateway sideband/session routing, human-only commit, and
dropped-destination cleanup and rendered two-browser sample path are implemented. The remaining
failure checks remain. Specification review: approved (2026-09-08).
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

- [x] Red-test private lane isolation and destination-bound acceptance with two authenticated web clients.
- [x] Implement human preparation/readiness on common room transfer state machine and token/session mapping.
- [x] Specify narrow authenticated web acceptance wire contract and client fixture without changing RTVI-core semantics.
- [x] Connect minimum-necessary briefing/notice output, privacy commit barrier and human-only continuation.
- [x] Add an isolated sample/test client entry point for destination acceptance only if needed; keep developer console uncluttered.

## Acceptance and failure checks

- [x] Before acceptance destination cannot hear caller/main room; caller cannot hear private briefing.
- [ ] Forged source/caller/other-connection, stale and duplicate acceptance reject; timeout/late readiness cannot bridge.
- [ ] Consent/acceptance alone does not bypass policy application; failed privacy barrier leaves source responsible with no leaked media.
- [ ] After commit source capabilities/workers end, two humans converse and variables survive; original start/duration clocks remain.
- [ ] Busy/failing/dropped destination cleans exact attempt and does not terminate a still-valid caller/source conversation.
- [x] Pre-commit isolation blocks destination microphone publishing as well as main-room
  listening/transcripts; no unrestricted variables/history snapshot reaches that destination.
- [x] Early acceptance cannot bypass usable media and private briefing/configured-notice
  sequencing. Define exact early-accept handling; enqueued audio is not completed playback.

## Manual verification

1. Configure and migrate `VXPIPE_DATABASE_URL`, provide valid Gemini and Deepgram development
   keys, then start `bin/dev`.
2. Open `/`, create a room, connect the Pipecat caller console, and ask to be transferred to human
   support with a concise purpose.
3. Open `/transfer` in a second browser/device and connect within the 30-second attempt deadline.
   Verify only the destination hears the private briefing and configured notice; neither web human
   can exchange main-room audio before acceptance.
4. Accept on the destination page. Verify it reports `Main room active`, the source agent exits,
   and the two humans exchange audio in both directions. The detailed browser steps and expected
   data boundaries are in the [Console asset README](../../apps/vxpipe_console/assets/README.md#manual-human-transfer-test).
5. Repeat with decline/no acceptance, stale acceptance, and privacy-apply failure using controlled
   fixtures.

## Scope boundaries

No platform-mandated acceptance button/UI design, phone provider yet, blanket regulatory-compliance claim, general concurrent-agent consultation, or implicit full transcript/variable access for a human destination.

## Completion and evidence

- [ ] Demonstrate the runnable outcome and every acceptance/failure check above.
- [ ] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [ ] Update this milestone, the index checkbox, relevant architecture/user docs, and
  implementation labnote with actual test/browser/integration evidence in the implementation commit.

Partial implementation evidence (2026-09-11): the Call Engine focused room test starts a genuine
agent transfer tool invocation, attaches the catalog web human with disabled pre-commit media,
rejects stale/forged/foreign-process/duplicate control, delivers private briefing audio only to the
destination sink, waits for completed playback, commits media policy before mix-minus promotion,
tears down the source agent, and preserves Call Variables. A separate test drops the pending
destination process and observes a generic failed transfer with the source still active. The three
focused tests and all 336 Call Engine tests pass (one integration test excluded).

The Gateway checkpoint adds a transfer-only session for an already running call and keeps that
session provisional rather than joining the participant. A separate `vxpipe` WebRTC data channel
carries only bounded preparation, acceptance, active, and generic-error controls; the standard
RTVI `chat` channel remains unchanged. A full Gateway test drives the caller's transfer request
through RTVI and two real ExWebRTC peer connections. It proves destination input/output isolation,
exact-attempt acceptance, private briefing delivery, source teardown, Membrane pipeline readiness,
and bidirectional Opus room audio after activation. All 94 Gateway tests pass (four excluded).
This does not mark the milestone complete: timeout/late-control coverage, explicit
failed-policy-barrier coverage, and the remaining combined lifecycle assertions above remain.

The Console sample checkpoint adds a dedicated `/transfer` destination page beside the unchanged
Pipecat caller console. It obtains only a public locator plus expiring participant token, claims the
provisional gateway session, negotiates browser audio directly, and uses the bounded `vxpipe`
sideband for exact-attempt acceptance. Component and browser-transport tests cover the admission,
offer, trickle ICE, projected controls, acceptance envelope, remote audio, and cleanup. The React
suite passes 7 tests across 3 files; TypeScript checking passes. Rendered Chrome inspection at
1440x1000 and 390x844 confirms the responsive empty and error states; axe reports zero WCAG A/AA
violations or incomplete checks. The full two-human runtime remains covered by the real ExWebRTC
gateway integration test above, while the README now gives the manual two-browser verification
flow.

## Specification review

Reviewed independently by milestone_review_b on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Added bidirectional private-lane isolation, transcript/snapshot restrictions and early-acceptance sequencing tests; re-review approved.
This is specification evidence only; implementation and runtime verification remain unchecked.
