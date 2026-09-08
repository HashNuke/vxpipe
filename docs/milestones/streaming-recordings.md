# Permitted live recordings streamed to S3

Status: not implemented. Specification review: approved (2026-09-08).
Prerequisites: [Live mixing/media policy](live-mixing-and-media-policy.md); [Asynchronous history](asynchronous-call-history.md).
Sources: [Live recording split](../../labnotes/20260905-0405-call-definition-design.md#mix-live-record-participant-tracks-and-the-live-mix); [R38/R41](../call-definition-gap-review.md).

## Runnable outcome

During a multi-party call, enabled permitted individual tracks and the already-live full mix stream to S3-compatible storage. After the call, an authorized operator plays the combined recording and can inspect its aligned tracks, gaps and completeness.

## Specification

- RoomRecording is a room-scoped capability with bounded taps on mixer inputs/outputs. S3Storage/ArtifactWriter lives in the separate artifacts ownership boundary and streams bounded chunks/segments or multipart parts; neither RoomAuthority nor mixer performs network/disk/SQL work.
- Record the actual live mix, not a required post-call remix. Keep authorized live monitor on the mixer, never S3 readback. Individual participant/connection tracks share the room clock with the combined recording.
- Manifests identify tenant/call/room/incarnation, participant/connection/track, codec/sample format, monotonic start offsets, sample counts/duration, gaps and terminal status. Correlate agent audio with utterances/egress-accepted portion; generated-but-discarded TTS is not delivered recording. Egress acceptance is not confirmation that a remote listener played/heard it.
- Capture only when configured/enabled and permitted. record_audio false covers tracks/mix/derivatives for that interval, including buffering/late writes; opening gate still applies. Previously permitted segments remain. Recording permission never implies STT, transcript storage or new monitor access.
- EctoStorage asynchronously stores artifact metadata/references, not audio bytes. Object errors/queue saturation cannot stop room/media or undo variables; surface incomplete/gap evidence honestly. Artifact workers can outlive room and finalize or mark incomplete after owner failure.
- Call-owned objects/manifests are identifiable for later whole-call retention and publication. Establish writer lifecycle/ownership/late-write coordination boundaries now; do not promise dual audio copies, lossless in-memory buffering, or automatic incident repair.

## Implementation checklist

- [ ] Red-test recording lifecycle with tagged audio and fake object writer, exact permitted intervals, gaps, and room/worker failure.
- [ ] Add artifacts application/ports and scoped writer supervision; keep dependency direction and engine database-free.
- [ ] Implement bounded stream-to-S3 recording plus asynchronous metadata/manifests.
- [ ] Capture live full mix and selected individual tracks with shared clocks and honest egress provenance.
- [ ] Add private operator playback/access mechanism and tagged S3-compatible integration tests without logging signed URLs/secrets.

## Acceptance and failure checks

- [ ] Reconstruct duration/alignment from manifests; combined object matches live mix and excludes generated-but-discarded/not-egress-accepted TTS. Test interrupted/discarded output without equating egress acceptance with remote playout.
- [ ] Deny recording mid-call: no tracks/mix/derivatives from that interval enter tap/queue/object; relaxation cannot replay it.
- [ ] Slow/failing object store and saturated writer queue leave live calls/monitor responsive; gaps/incomplete state are explicit.
- [ ] Room/writer crash preserves surviving evidence and records final/incomplete manifests when storage succeeds; a total outage cannot guarantee persisted manifests or successful finalization. Post-call draining is independent of reporting wait.
- [ ] Cross-tenant reads and ungranted recording/monitor taps fail; metadata alone is not claimed to restore lost audio.

## Manual verification

1. Enable permitted recording for a two-human or transferred call and also listen through a live monitor.
2. End the call, play its combined object, and inspect separate aligned tracks/manifests.
3. Repeat with a restrictive participant joining mid-call and compare omitted intervals.
4. Slow/fail the test object store and inspect responsive live audio plus honest recording gaps.

## Scope boundaries

No mandatory offline remix, PG audio-byte duplication, automatic repair/import, unconditional recording, or new per-category history toggle. Optional offline derivatives can remain deferred; ordinary playback uses the recorded live mix.

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
Corrected provable egress vs remote-playout boundary, room manifest identity and terminal-manifest outage guarantees; re-review approved.
This is specification evidence only; implementation and runtime verification remain unchecked.
