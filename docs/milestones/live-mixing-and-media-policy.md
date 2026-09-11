# Live mixing and presence-driven media policy

Status: partially implemented. Specification review: approved (2026-09-08).
Prerequisites: [Asynchronous history](asynchronous-call-history.md); [Call lifecycle](opening-audio-and-call-lifecycle.md); [Agent transfers](agent-transfers.md).
Sources: [Media policy](../../labnotes/20260905-0405-call-definition-design.md#participant-presence-constrains-the-capability-topology); [live mixing](../../labnotes/20260905-0405-call-definition-design.md#mix-live-record-participant-tracks-and-the-live-mix); [commit barrier](../../labnotes/20260905-0405-call-definition-design.md#retained-transfer-and-media-enforcement-invariants).

## Runnable outcome

Two admitted humans exchange live audio without an agent, and a separately authorized silent monitor hears only permitted sources. Admitting a restrictive participant changes live routes/transcript delivery and storage permission before any newly forbidden data flows.

## Specification

- Add an engine-owned RoomMixer pipeline for normalized timestamped frames, aligned bounded buffers, per-participant mix-minus, authorized full mix and optional authorized individual-track taps. Gateway owns external monitor transport/auth only; monitoring never reads S3 or publishes audio by implication.
- Use Membrane elements for codec, RTP, framing, mixing arithmetic, encoding and pacing wherever
  their contracts fit. Keep only Vxpipe-specific identity, media-policy, mix-minus routing,
  revision-barrier and bounded-delivery adapters; do not introduce FFmpeg when the negotiated
  format already matches the room sample rate.
- Support human-only entry/continued rooms with active agent nil and one runtime participant per catalog key. Keep call duration/lifecycle independent of agent presence.
- Compile normal media_policy and admitted participant while_present maps: audio_routes and transcript_routes map definition source keys to recipient arrays. Explicit maps are complete allowlists; an omitted policy field adds no restriction, but an omitted source inside an explicit route map is denied. An empty map permits none, with no implicit source/self/monitor grant. Intersect all active restrictions plus host ceiling; never deep-merge to restore omitted routes.
- record_audio/save_transcripts are independent room-wide interval permissions; false wins. Leaving removes only that contribution; raw transport loss does not clear authoritative presence. Permission never enables unconfigured STT/recording. Stop STT flows if neither permitted live nor storage consumer needs them.
- Commit policy before main bridge/activation, including queued/late output and reactivation. Route enforcement, transcript projection and private archive gates use source-interval provenance. Denied intervals never reach storage queues/debug logs/exports or retrospectively replay after relaxation. Previously allowed history stays until retention.
- Reserve a separately authorized private-preparation lane for the next transfer slice; it cannot become full-room audio. No per-packet SQL or RoomAuthority mixing. Bounded overload is explicit, and storage failure cannot block live media.

## Implementation checklist

- [x] Red-test synthetic tagged PCM sources, timestamp alignment/mix-minus, monitor authorization, and human-only lifecycle.
- [x] Implement mixer/pipeline supervision and bounded sinks independently of RoomAuthority and storage adapters.
- [x] Compile/intersect presence policies and apply an authoritative media commit barrier.
- [ ] Connect transcript, STT-demand, archive and future recorder taps to the same interval permissions.
- [ ] Expose existing transport/harness paths for multiple authorized participants and silent monitoring without redesigning the sample console.

## Acceptance and failure checks

- [x] Mix-minus excludes own source; monitor hears only authorized sources, contributes none, and cross-tenant/unauthorized subscriptions fail.
- [x] Explicit omitted publisher/recipient, empty maps, multiple simultaneous restrictions, leave and transport-loss cases behave differently as specified.
- [ ] Admit a restrictive participant: no forbidden in-flight audio/transcript crosses the commit barrier; queued output and later relaxation cannot replay that interval.
- [ ] Live transcript sharing can continue with save_transcripts false; no-save is not no-processing. Stop STT when no permitted consumer remains.
- [x] Human-only calls still route/end correctly; slow monitors/storage and process failure do not put mixing into authority or database work.
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

The authority now also owns a bounded revision-acknowledgement barrier for media enforcers.
Registration succeeds only after an enforcer installs the current snapshot. Admission and leave
compute the candidate revision but do not publish it as committed until every registered enforcer
acknowledges it. Rejection, timeout, malformed acknowledgement, or later enforcer process loss
terminates the significant policy authority so its room fails closed; a partially applied policy
can therefore never leave the room running. Focused red/green tests cover initial installation,
blocked admission until the final acknowledgement, rejection, process loss, duplicate
registration, and invalid timeout configuration. The complete Call Engine suite passes 302 tests
with one tagged integration exclusion. A fresh database-backed umbrella run also passes across all
seven child applications. No mixer, transcript projector, or archive gate is registered yet, so
the implementation checklist remains open until those concrete consumers apply and enforce the
revisions.

A significant room-scoped `RoomMixer` is now the first concrete barrier enforcer in every planned
room. It accepts only fixed-format normalized s16le PCM frames carrying the currently installed
policy revision, aligns sources by room-clock timestamp in a bounded buffer, saturating-mixes them,
and produces policy-filtered mix-minus, full-mix, or individual-track frames. Participant presence
and exact tenant/room/incarnation identity are checked at the mixer boundary. Full-mix and track
subscriptions are output-only and conflict with speaking subscriptions for the same participant.
Every subscription has a bounded mixer-owned queue and a coalesced availability notice; consumers
pull through an opaque token, so a slow sink neither blocks the mixer nor accumulates audio in its
mailbox. A policy revision clears aligned inputs and pending outputs before acknowledging the
barrier, and stale-revision frames cannot be reclassified under a later relaxed policy. Absent
recipients receive nothing even if their connection subscription has not been removed yet.
Focused tests were written first and cover timestamp alignment, mix-minus/full/track output,
16-bit saturation, route restrictions, stale revisions, no replay after relaxation, bounded input
and output overload, monitor non-publication, identity/participant authorization, recipient leave,
and malformed/non-monotonic policy. Planned-room tests prove startup reaches policy revision two
and mixer loss ends the room. The complete Call Engine suite passes 310 tests with one tagged
integration exclusion. A fresh database-backed umbrella run also passes across all seven child
applications. Gateway normalization/encoding, live connection subscription, transcript and
archive enforcement, and human-only startup remain open.

A significant room-scoped `TranscriptRouter` is now the second concrete barrier enforcer. It
installs the same immutable policy revisions as the mixer, retains a bounded 128-revision default
history for storage provenance, filters current transcript recipients by authoritative presence and
`transcript_routes`, and never delivers a stale-revision projection after later restriction or
relaxation. Participant transcription and generated agent text now cross this boundary before
client delivery. Transcript-bearing input/output facts receive the router's
`media_policy_revision` and `save_transcripts` decision before archive handoff; denied text is
removed before it can enter the bounded queue, and the delayed Calls sink still repeats the source
policy check. A live planned-room regression first demonstrated that a restrictive participant's
empty agent-output route still leaked text to the caller; the same scenario now delivers no text
and archives only non-content metadata under revision three. Unit tests also cover explicit routes,
storage independence, stale interval non-replay, bounded-history eviction,
wrong-room/unknown-revision rejection, and room teardown when the router is lost. The Call Engine
suite passes 317 tests with one tagged integration exclusion. STT provider-session revision
pinning, demand/restart on policy changes, future recording taps, transport-to-mixer wiring, and
human-only startup remain open, so the
broader transcript/archive checklist and in-flight-transition acceptance checks are not yet marked
complete.

Human-only planned startup is now executable. Schema `20260911.01` accepts a human
`entry_receiver`; compilation gives both human entries stable runtime participant identities and
no activation ID. Startup admits exactly those two definitions through the existing policy
barrier, selects STT independently per human identity, and permits attachment without fabricating
an agent/text capability. The dedicated vertical test sends normalized PCM from both humans
through the room's revision-two mixer, proves each mix-minus output contains only the other
speaker, confirms text remains unavailable, and fires the pinned maximum-duration timer to end the
room. Legacy ad-hoc attachment still requires an agent. The schema and room tests were written
first and failed at the old agent-only receiver constraint. The complete Call Engine suite passes
319 tests with one tagged integration exclusion, and the complete database-backed umbrella suite
passes across all seven child applications. Gateway media normalization and live transport
subscriptions are still required before this path is browser-runnable.

The Gateway transport-normalization checkpoint now provides a per-track Membrane pipeline.
Membrane owns jitter buffering, RTP timestamp rollover, Opus depayloading/parsing/decoding, and
exact 20 ms rechunking. A focused room-timestamp element aligns the first emitted packet to the
shared VM-relative 20 ms clock, while a channel element passes mono through or averages stereo to
the mixer's fixed 48 kHz mono s16le format. No FFmpeg dependency is used because Opus decoding is
already requested at 48 kHz. The pipeline pins and checks tenant, room-incarnation, participant,
connection, and first-track identity before accepting input. The engine's saturating sample
addition now uses Membrane's audio-mixer adder; Vxpipe continues to own policy-aware mix-minus,
full-mix and individual-track routing and bounded subscriptions. Tests were written first and
failed because the pipeline boundary was absent; four focused pipeline checks now cover 20 ms
output, two-packet accumulation, stereo normalization, and identity/track rejection. This
checkpoint is not yet wired into `Connection`, so the transport checklist remains open until live
ingress, policy-transition purge/restart, bounded subscription drain, and WebRTC egress are
verified together. The Gateway suite passes 71 tests with four tagged integration exclusions, and
a fresh database-backed umbrella run passes across all seven child applications.

The next transport checkpoint wires that normalizer into planned-room WebRTC ingress. Call Engine
attachments now expose an opaque room-audio handle plus the mixer's shared clock configuration;
legacy attachments expose no handle and retain the existing STT-only route. A separately
supervised Gateway `RoomAudioIngress` registers as a media-policy enforcer, owns a stable source
sequence, and sends only current-generation decoded PCM through the handle into `RoomMixer`.
Every later policy revision synchronously terminates and replaces the Membrane jitter/decode/frame
pipeline before acknowledgement. Late output from the prior generation and packets received
through that boundary are dropped rather than relabeled under a relaxed policy. Raw Opus still
fans out independently to configured STT, while a human-only planned connection can operate with
STT disabled. Focused red/green checks cover planned versus legacy attachment configuration,
engine-owned push/enforcer registration, supervised ingress startup, revision tagging, sequence
continuity, pipeline replacement, stale-generation output, and stale-interval packet rejection.
The Gateway suite passes 75 tests with four tagged integration exclusions; the Call Engine suite
passes 319 tests with one tagged integration exclusion. A fresh PostgreSQL-backed umbrella run
passes across all seven child applications. Formatting, warnings-as-errors compilation, strict
Credo, and the unused-dependency check pass, and the disposable PostgreSQL container was removed.
The next checkpoint makes planned-room flushing clock-driven. A configurable 300 ms playout delay
covers the default 200 ms Gateway jitter window plus 100 ms of cross-connection arrival skew. Each
frame-duration tick derives an aligned sample cutoff from the shared monotonic room clock and
flushes through it whether or not a new packet arrived, preventing silence or a stopped publisher
from stranding another source's final frames. A focused fake-clock/fake-scheduler test proves that
frames remain buffered before the delay, become available at the cutoff, and keep the timer armed.
The Call Engine suite passes 320 tests with one tagged integration exclusion, and a fresh
PostgreSQL-backed umbrella run passes across all seven child applications. Formatting,
warnings-as-errors compilation, strict Credo, and the unused-dependency check pass.
Bounded mix-minus subscription drain and WebRTC Opus egress remain open, so the transport/harness
checklist and browser-runnable outcome are not yet claimed.

The output attachment checkpoint distinguishes mixer output from direct agent TTS explicitly.
Human-entry rooms with no active agent advertise one `:mix_minus` subscription through an opaque
Call Engine operation. Legacy and active-agent attachments keep mixer output disabled, so the
Gateway cannot accidentally infer output ownership from optional STT or start a second RTP
producer for the same track. The human-only vertical test now obtains both subscriptions only
through that public boundary and still proves reciprocal mix-minus output. Dynamic output-mode
switching belongs to the later human-transfer milestone; Gateway draining and Opus egress remain
open here. The Call Engine suite remains green at 320 tests with one tagged integration exclusion,
and the fresh PostgreSQL-backed umbrella run and all quality gates pass.

The first output-media checkpoint now turns one fixed-format mixer frame stream into WebRTC-ready
Opus/RTP. A dedicated Membrane pipeline owns PCM ingestion, voice-tuned Opus encoding, Opus RTP
payloading, randomized RTP stream identity/header sequencing, presentation-timestamp-based
real-time pacing, and delivery to the negotiated WebRTC audio track. The boundary accepts only
20 ms, 48 kHz, mono s16le `:mix_minus` frames whose tenant, room incarnation, subscription, and
recipient match its pinned attachment. Readiness is announced only after every child in the media
chain reaches `:playing`; this prevents a caller from pushing into a pipeline whose children are
still linking. Focused tests verify two encoded packets as one coherent RTP stream, their 960-sample
timestamp progression, decodable Opus output, delivery acknowledgements, and identity/format
rejection. The pipeline contains no FFmpeg element or process. Bounded subscription draining,
policy-revision pipeline replacement, and live connection startup remain the next checkpoint, so
the transport checklist and browser-runnable outcome remain open.

A separate connection-scoped output coordinator now owns bounded delivery between the mixer and
that Membrane pipeline. It subscribes only when Call Engine explicitly advertises `:mix_minus`,
pulls at most one frame, and does not pull another until the WebRTC sink acknowledges the first.
Availability messages received while output is not ready or a frame is in flight coalesce into one
later drain. The coordinator is also a media-policy barrier enforcer: every later revision stops
the old pipeline, discards its in-flight identity, starts an empty generation, and only then
acknowledges the revision; stale acknowledgements cannot unlock the replacement. Output failure is
reported to the owning connection and ends the coordinator. Call Engine now exposes bounded pulls
through its façade rather than requiring Gateway to invoke mixer internals. Focused tests cover the
disabled path, one-frame backpressure, clean policy replacement, stale acknowledgement rejection,
and failure propagation. `Connection` startup and a two-client WebRTC verification remain open.
If mixer subscription fails after pipeline launch, activation immediately terminates that pipeline
instead of leaving a sibling process behind for later connection cleanup.

The live-connection checkpoint now starts that coordinator from the real WebRTC `Connection` only
when the Call Engine attachment advertises mixer output. A focused HTTP/WebRTC test negotiates two
independent ExWebRTC clients through the RTVI offer endpoint, sends encoded Opus from each human,
decodes the other human's received output, and verifies mix-minus does not echo the caller's own
frame. The red run also exposed that Membrane pipeline children return supervisor and pipeline
process identities from `start_link/1`; the owning dynamic-supervisor boundary now normalizes that
result to the supervised child identity used for monitoring and termination. Existing active-agent
connections retain the direct TTS owner and do not start a second RTP producer. The Gateway suite
passes 83 tests with four tagged integration exclusions; a fresh PostgreSQL-backed umbrella run
and every common quality gate pass. An authorized monitor connection,
restrictive live-policy transition, and sample-console/manual verification remain open.

The first composed transition check now covers the live audio half of that remaining barrier
acceptance. Three negotiated WebRTC clients establish an initially permitted caller-to-receiver
route; the caller then queues another encoded frame immediately before a restrictive specialist is
admitted. Once admission returns, the receiver gets neither that old interval nor later frames,
while newly encoded caller/specialist audio crosses only their allowlisted route in both directions.
This required no production change: the existing authority commit, ingress generation restart,
mixer purge, and egress generation replacement compose correctly. The Gateway suite passes 84
tests with four tagged integration exclusions. STT provider-session provenance must still prove
the transcript half before the broader acceptance item can be marked complete.

## Specification review

Reviewed independently by milestone_review_a on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Distinguished omitted policy fields from denied omitted route sources and added fail-closed policy-apply admission/bridge checks; re-review approved.
This is specification evidence only; implementation and runtime verification remain unchecked.
