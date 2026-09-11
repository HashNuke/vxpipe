# Live mixing and presence-driven media policy

Status: partially implemented. Specification review: approved (2026-09-08).
Prerequisites: [Asynchronous history](asynchronous-call-history.md); [Call lifecycle](opening-audio-and-call-lifecycle.md); [Agent transfers](agent-transfers.md).
Sources: [Media policy](../../labnotes/20260905-0405-call-definition-design.md#participant-presence-constrains-the-capability-topology); [live mixing](../../labnotes/20260905-0405-call-definition-design.md#mix-live-record-participant-tracks-and-the-live-mix); [commit barrier](../../labnotes/20260905-0405-call-definition-design.md#retained-transfer-and-media-enforcement-invariants).

## Runnable outcome

Two admitted humans exchange live audio without an agent, and a separately authorized silent monitor hears only permitted sources. Admitting a restrictive participant changes live routes/transcript delivery and storage permission before any newly forbidden data flows.

## Specification

- Add an engine-owned RoomMixer pipeline for normalized timestamped frames, aligned bounded buffers, per-participant mix-minus, authorized full mix and optional authorized individual-track taps. Gateway owns external monitor transport/auth only; monitoring never reads S3 or publishes audio by implication.
- Support human-only entry/continued rooms with active agent nil and one runtime participant per catalog key. Keep call duration/lifecycle independent of agent presence.
- Compile normal media_policy and admitted participant while_present maps: audio_routes and transcript_routes map definition source keys to recipient arrays. Explicit maps are complete allowlists; an omitted policy field adds no restriction, but an omitted source inside an explicit route map is denied. An empty map permits none, with no implicit source/self/monitor grant. Intersect all active restrictions plus host ceiling; never deep-merge to restore omitted routes.
- record_audio/save_transcripts are independent room-wide interval permissions; false wins. Leaving removes only that contribution; raw transport loss does not clear authoritative presence. Permission never enables unconfigured STT/recording. Stop STT flows if neither permitted live nor storage consumer needs them.
- Commit policy before main bridge/activation, including queued/late output and reactivation. Route enforcement, transcript projection and private archive gates use source-interval provenance. Denied intervals never reach storage queues/debug logs/exports or retrospectively replay after relaxation. Previously allowed history stays until retention.
- Reserve a separately authorized private-preparation lane for the next transfer slice; it cannot become full-room audio. No per-packet SQL or RoomAuthority mixing. Bounded overload is explicit, and storage failure cannot block live media.

## Implementation checklist

- [ ] Red-test synthetic tagged PCM sources, timestamp alignment/mix-minus, monitor authorization, and human-only lifecycle.
- [ ] Implement mixer/pipeline supervision and bounded sinks independently of RoomAuthority and storage adapters.
- [ ] Compile/intersect presence policies and apply an authoritative media commit barrier.
- [ ] Connect transcript, STT-demand, archive and future recorder taps to the same interval permissions.
- [ ] Expose existing transport/harness paths for multiple authorized participants and silent monitoring without redesigning the sample console.

## Acceptance and failure checks

- [ ] Mix-minus excludes own source; monitor hears only authorized sources, contributes none, and cross-tenant/unauthorized subscriptions fail.
- [ ] Explicit omitted publisher/recipient, empty maps, multiple simultaneous restrictions, leave and transport-loss cases behave differently as specified.
- [ ] Admit a restrictive participant: no forbidden in-flight audio/transcript crosses the commit barrier; queued output and later relaxation cannot replay that interval.
- [ ] Live transcript sharing can continue with save_transcripts false; no-save is not no-processing. Stop STT when no permitted consumer remains.
- [ ] Human-only calls still route/end correctly; slow monitors/storage and process failure do not put mixing into authority or database work.
- [ ] Fail mixer/transcript/archive policy application during admission/transfer: the bridge
  fails closed without destination media or queued old output crossing under stale policy.

## Manual verification

1. Join two distinct human definitions using authorized test clients; exchange simultaneous audio and inspect mix-minus.
2. Join an explicitly authorized silent monitor and verify it cannot transmit or hear unauthorized sources.
3. Admit a restrictive participant that permits only caller/specialist routes and denies recording/transcript storage.
4. Inspect live recipients and private archive sink; remove the participant and confirm only its restrictions lift, with no historical replay.

## Scope boundaries

No implicit full-room monitor privilege, capability-denial selectors, participant-type wildcard policy, offline-only mixer, or generic redaction/compliance claim. Recording bytes and transfer-acceptance UI are later slices; this provides their enforceable media foundation.

## Completion and evidence

- [ ] Demonstrate the runnable outcome and every acceptance/failure check above.
- [ ] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [ ] Update this milestone, the index checkbox, relevant architecture/user docs, and
  implementation labnote with actual test/browser/integration evidence in the implementation commit.

Implementation evidence (2026-09-11): schema `20260911.01` introduces the normal call-wide
`media_policy` and participant-local `while_present` shapes. Omitted fields compile as `:inherit`,
while explicit empty route maps/recipient lists and false storage permissions remain distinct.
Route sources and recipients accept only declared participant definition keys, reject duplicates,
and fail malformed values at exact paths. The compiler translates those keys once to immutable
runtime participant IDs and `MapSet` recipient allowlists in the resolved plan. The focused test was
written first and failed because both typed policy modules were absent; after implementation it
passes four tests, including JSON/Elixir parity, omission versus empty, the full approved
specialist restriction, invalid-reference paths, and compiler rejection of a forged typed policy.
The complete Call Engine suite passes 286
tests with one tagged integration exclusion. The complete database-backed umbrella suite also
passes after correcting the independently observed stale transfer-registration race. Runtime
intersection, authoritative presence, the
commit barrier, mixer, transcript/archive enforcement, and human-only routing remain open.

The next checkpoint adds the pure effective-policy composer. It intersects the resolved host
ceiling, normal policy, and a participant-ID-keyed map of authoritative presence contributions.
All-inherited routes become unrestricted; otherwise explicit maps remain complete allowlists and
their sources/recipient sets intersect. False wins for the two storage permissions, and removing
one owner before recomposition removes only that contribution. Resolved-policy representation
validation rejects malformed trusted inputs so the later commit barrier can fail closed. Five
focused composer tests pass; authoritative presence state and media enforcement remain open.
The expanded Call Engine suite passes 291 tests with one tagged integration exclusion, and the
database-backed umbrella suite passes across every child application.

A room-scoped media-policy authority now owns the pinned participant-policy catalog, active
contribution map, monotonic revision, and effective snapshot outside Room Authority. Planned-room
startup supervises it as a temporary significant child: policy-state loss ends the room rather than
restarting unrestricted. Participant commit applies the pinned contribution before Room Authority
records membership. Connection detach leaves that contribution active, while authoritative
participant exit removes it. Focused process and room tests cover invalid startup, unknown/duplicate
admission, owner-scoped leave, both entry participants, disconnect versus leave, and fail-closed
authority loss. A rejected unplanned participant is also discarded after preparation, leaving no
stray supervisor or policy revision. Mixer/transcript/archive consumers and their revision
acknowledgement barrier remain open. The expanded Call Engine suite passes 297 tests with one
tagged integration exclusion, and the database-backed umbrella suite passes across every child
application.

## Specification review

Reviewed independently by milestone_review_a on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Distinguished omitted policy fields from denied omitted route sources and added fail-closed policy-apply admission/bridge checks; re-review approved.
This is specification evidence only; implementation and runtime verification remain unchecked.
