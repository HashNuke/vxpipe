# Private briefing and human web acceptance

Status: implemented (2026-09-11). The protocol-neutral private room lane, exact destination
control, briefing playback barrier, authenticated gateway sideband/session routing, human-only
commit, bounded timeout cleanup, fail-closed policy barrier, and rendered two-browser sample path
are complete. Specification review: approved (2026-09-08).
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
- Resolve the human destination's configured STT during preparation and activate it only after
  main admission. Provider startup runs outside room authority and the policy barrier. Activation
  is restricted to the owning connection/actor and reuses an already bound recognizer. Permitted
  transcripts retain source participant identity when delivered to another web connection.
- Recoverable destination failure or timeout cleans only the pending destination; the source
  handles a typed outcome under the approved single recovery limit. If a media-policy enforcer
  cannot apply the commit barrier consistently, the destination is never bridged, the source is
  never handed off, and the room closes fail-closed. Detailed causes remain internal, including
  when the development sample exposes all permitted tool events.

## Implementation checklist

- [x] Red-test private lane isolation and destination-bound acceptance with two authenticated web clients.
- [x] Implement human preparation/readiness on common room transfer state machine and token/session mapping.
- [x] Specify narrow authenticated web acceptance wire contract and client fixture without changing RTVI-core semantics.
- [x] Connect minimum-necessary briefing/notice output, privacy commit barrier and human-only continuation.
- [x] Add an isolated sample/test client entry point for destination acceptance only if needed; keep developer console uncluttered.

## Acceptance and failure checks

- [x] Before acceptance destination cannot hear caller/main room; caller cannot hear private briefing.
- [x] Forged source/caller/other-connection, stale and duplicate acceptance reject; timeout/late readiness cannot bridge.
- [x] Consent/acceptance alone does not bypass policy application; a failed privacy barrier emits
  no main-media promotion or successful handoff and closes the room fail-closed.
- [x] After commit source capabilities/workers end, two humans converse and variables survive; original start/duration clocks remain.
- [x] Configured destination STT remains absent during private preparation, starts after promotion,
  and delivers partial/final transcripts to the authorized caller without restarting existing STT.
- [x] Busy/recoverably failing/dropped destination affects only the exact attempt and does not
  terminate a still-valid caller/source conversation.
- [x] Pre-commit isolation blocks destination microphone publishing as well as main-room
  listening/transcripts; no unrestricted variables/history snapshot reaches that destination.
- [x] Early acceptance cannot bypass usable media and private briefing/configured-notice
  sequencing. Define exact early-accept handling; enqueued audio is not completed playback.

## Manual verification

1. Configure and migrate `VXPIPE_DB_URL`, provision tenant Google/Deepgram credentials using
   [credential setup](../provider-credential-storage.md), set `VXPIPE_DEV_TENANT`, then start `bin/dev`.
2. Open `/pipecat-console`, create a room, connect the Pipecat caller console, and ask to be
   transferred to human support with a concise purpose.
3. Open `/transfer` in a second browser/device and connect within the 30-second attempt deadline.
   Verify only the destination hears the private briefing and configured notice; neither web human
   can exchange main-room audio before acceptance.
4. Accept on the destination page. Verify it reports `Main room active`, the source agent exits,
   and the two humans exchange audio in both directions. Speak from the destination and verify
   its transcription appears in the caller conversation. The detailed browser steps and expected
   data boundaries are in the [Console asset README](../../apps/vxpipe_console/assets/README.md#manual-human-transfer-test).
5. Repeat with decline/no acceptance, stale acceptance, and privacy-apply failure using controlled
   fixtures.

## Scope boundaries

No platform-mandated acceptance button/UI design, phone provider yet, blanket regulatory-compliance claim, general concurrent-agent consultation, or implicit full transcript/variable access for a human destination.

## Completion and evidence

- [x] Demonstrate the runnable outcome and every acceptance/failure check above.
- [x] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [x] Update this milestone, the index checkbox, relevant architecture/user docs, and
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
The final Call Engine checkpoint adds the remaining timeout, late-control, media-policy failure,
and lifecycle assertions. Its first timeout run exposed that successful private preparation
cancelled the total-attempt timer; the coordinator now settles only the completed preparation task
and retains the original timer through acceptance, readiness, and briefing. The exact destination
is discarded when that timer fires, late readiness rejects, and the source agent stays available.
The controlled policy-barrier failure proves acceptance and completed briefing still cannot
promote main media: the room closes under the existing significant-child fail-closed contract
before source handoff. The success path also proves the same Call Variables and Call Lifecycle
processes survive human promotion, so no transfer resets the pinned duration clock.

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

Final completion verification passes the five focused human-transfer room tests, formatting,
warnings-as-errors compilation, strict Credo across 4,660 modules/functions, unused dependency
checks, and the full umbrella suite against a fresh disposable PostgreSQL database (MCP 37/3
excluded, Agent Runtime 58/2, Call Engine 338/1, Calls 37, Persistence 25, Gateway 95/4, Console
59). The final checkpoint changed no UI; its rendered-browser evidence is the immediately
preceding sample checkpoint.

Pre-delivery regression correction (2026-09-12): a durable two-tab browser review found that the
Gateway returned HTTP 201 and consumed the destination token but omitted the pinned `room_id` and
`incarnation_id` from the provisional participant projection. The sample client therefore rejected
the otherwise valid session before opening its transfer connection. A red Gateway HTTP contract
test reproduced the response defect before the projection was corrected, and a red client guard
test now requires the declared room identity. The full Gateway suite passes 227 tests with 6
integration tests excluded; the Console suite passes 88 tests; all 8 asset tests and TypeScript
checking pass. Repeating the real HTTPS flow with
Gemini and local Morse audio reaches `Private briefing line open`, enables acceptance, and records
destination admission, media connection, private briefing, and acceptance without the former
invalid-session error. The deterministic Morse briefing exceeds the unchanged total-attempt timer,
so completed main-room promotion continues to be evidenced by the real two-peer Gateway integration
test rather than this regression run. Formatting, warnings-as-errors compilation, strict Credo,
unused dependency checking, and the correctly configured PostgreSQL-backed umbrella suite also
pass.

Pre-delivery acceptance correction (2026-09-13): real Deepgram reconnection during the
human admission barrier exceeded its one-second budget and closed the caller's room.
Provider session rotation now runs in a supervised connector after the capability has
installed the new policy and stopped admitting old-session audio/signals. A newer policy
cancels unfinished connection work; provider sessions remain pinned to one revision.
The regression was observed red before implementation, and all 15 focused transfer/STT
checks and the two-peer Gateway audio check pass. A real Gemini/Deepgram Chrome handoff
now reaches `Main room active` and retains the caller connection after acceptance.
The full umbrella completion checks pass (997 tests, 15 integration cases excluded).
See the [failure investigation](../../labnotes/20260913-1906-human-transfer-failure.md).

Pre-delivery incremental-policy correction (2026-09-13): the user requested applying
only the service changes implied by the new permissions. The
[incremental policy decision](../incremental-media-policy.md) supersedes the
revision-wide reset behavior described in the historical checkpoints above.

- [x] Review permission scopes, stale-data rejection, admission ordering, and bounded
  provenance retention; preserve unchanged speech sessions and STT ingress queues.
- [x] Preserve unaffected audio pipelines, mixer queues, and recording intervals.
- [x] Verify the combined change with all root gates (1,006 tests, zero failures,
  15 integration cases excluded) and a live Gemini/Deepgram handoff. The caller's
  STT transport and ingress/egress pipeline identities remain unchanged from room
  revision 2 through revision 4; both peers exchange RTP after acceptance. See the
  [audio evidence](../../labnotes/20260913-2001-incremental-audio-policy.md).

Pre-delivery human-transcription correction (2026-09-13): human promotion previously activated
mixing but omitted the destination's configured STT. The engine now retains that runtime and the
web/phone transport starts it after main admission through the existing supervised startup and
policy binding path. Gateway now forwards room-authorized transcripts from other participants
instead of filtering them to its own source connection. The focused checks cover private-lane
exclusion, connection ownership, repeated activation, real two-peer RTP ingestion, and partial/final
RTVI delivery with the destination participant ID. Rendered Chrome with live Gemini/Deepgram and
a synthesized microphone stream displays support speech in the caller conversation while the
destination remains active. All root gates pass; the full suite reports 1,007 tests, zero failures,
and 15 integration exclusions with four concurrent test modules. See the
[transcription evidence](../../labnotes/20260913-2019-human-transfer-transcription.md).

## Specification review

Reviewed independently by milestone_review_b on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Added bidirectional private-lane isolation, transcript/snapshot restrictions and early-acceptance sequencing tests; re-review approved.
The implementation and runtime evidence above complete the subsequently executed milestone.
The 2026-09-13 transcription correction was reviewed against private-lane admission, capability
ownership, policy-authorized routing, and independent human-only continuation; it adds no new
milestone prerequisite or blanket capability restart.
