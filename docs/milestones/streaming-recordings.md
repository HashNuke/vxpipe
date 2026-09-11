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
- [x] Add artifacts application/ports and scoped writer supervision; keep dependency direction and engine database-free.
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

Implementation is in progress. The first checkpoint evidence follows; do not mark the whole slice
complete until every acceptance check is demonstrated.

## Checkpoint 1: bounded artifact-writer ownership

The umbrella now contains a database- and engine-independent `vxpipe_artifacts` application. Its
application supervisor owns a unique writer registry, a writer task supervisor, and one dynamic
supervisor for call-scoped artifact writers. `Vxpipe.Artifacts.Writers` is the only public start
path; writer identity is pinned by tenant, call, and artifact rather than an unscoped process name.

The initial object-store port separates opening an upload, writing one bounded PCM chunk, and
completing it with a terminal manifest. A writer monitors its recording source but is not linked to
that source. It can therefore drain already-accepted chunks after the source exits. Store calls run
under the artifacts-owned task supervisor, leaving both the writer mailbox and future mixer caller
free while object I/O is slow.

The handoff reserves a fixed atomics-backed capacity before using a non-suspending process send.
Capacity includes the active store write and queued chunks; a full handoff rejects the newest chunk
without blocking. Closing rejects later input. The terminal manifest distinguishes successfully
written samples from rejected chunks and marks the artifact incomplete when bounded loss occurred.
This is honest bounded handoff, not a lossless or durable-queue claim.

The focused test was first red because the supervised writer API did not exist. Its green path
holds the first fake object-store write, fills the two-chunk capacity, observes an immediate third
rejection, ends the source, drains both accepted chunks, and completes an incomplete manifest:

```text
cd apps/vxpipe_artifacts
mix test test/vxpipe/artifacts/writer_test.exs --max-cases 1
# 1 test, 0 failures
```

No engine mixer tap, S3 adapter, relational metadata, recording configuration, or operator playback
is introduced by this checkpoint. Those remain later parts of this milestone.

Root formatting, compilation with warnings as errors, strict Credo over 612 source files, all 803
umbrella tests, and the unused-dependency check pass.

## Checkpoint 2: policy-gated mixer recording subscriptions

`RoomMixer` now exposes a separate internal recording subscription instead of pretending that a
recorder is a silent human participant. `RoomIncarnationSupervisor` will supply a fresh reference to
the mixer and the future `RoomRecording` sibling; callers without that exact token cannot create a
recording subscription. Existing participant mix-minus and monitor subscriptions retain their
presence, route, and conflict rules.

A recording subscription may select the full main-room mix or one named participant track. It sees
only normalized frames admitted under the current room identity and policy revision. Recording is
independent of participant recipient routes: when enabled, it captures the selected main-room
source even if that source has a narrow audience. It never captures private preparation audio,
which is not an input to the main mixer. The effective `record_audio` boolean remains the storage
authority.

Fanout skips all recording subscriptions while `record_audio` is false. A policy transition clears
the timestamp buffer and every subscriber queue before acknowledging the new revision, so audio
queued in a permitted interval cannot be pulled after denial and denied frames cannot be replayed
after permission returns. The recording subscription may remain installed and resumes only with
new frames tagged for the later permitted revision.

The new test was red with an undefined `RoomMixer.subscribe_recording/2`. The green case proves a
forged token is rejected, route-independent full-mix capture succeeds while recording is permitted,
the denied middle interval emits nothing, and a later permitted revision records only new audio.
Existing mixer, policy-room, and silent-monitor behavior remains green:

```text
cd apps/vxpipe_call_engine
mix test test/vxpipe/call_engine/room_mixer_test.exs \
  test/vxpipe/call_engine/media_policy_room_test.exs \
  test/vxpipe/call_engine/silent_monitor_call_test.exs --max-cases 1
# 10 tests, 0 failures
```

This checkpoint supplies only the authorized mixer tap. It does not start a recorder, hand chunks
to an artifact writer, or enable recording in a call definition.

Root formatting, compilation with warnings as errors, strict Credo over 612 source files, all 804
umbrella tests, and the unused-dependency check pass.

## Checkpoint 3: storage-neutral room recording coordinator

The call engine now owns a temporary `RoomRecording` coordinator and a small recording writer port.
The port accepts a typed immutable stream identity at open time and typed clock-aligned chunks
afterward. Its contract permits only supervised-worker setup and bounded in-memory handoff in the
callbacks; concrete implementations must perform no network, disk, or database work inline. This
keeps the live-media contract in the engine without adding a dependency on the artifacts app.

The coordinator reads the mixer's established PCM format, creates an authorized full-mix recording
subscription using the room-local token, and opens the injected writer. An audio-available
notification pulls no more than the configured frame limit. Each resulting chunk preserves
room-clock offset, policy revision, contributing participant IDs, per-channel sample count, and PCM
bytes. Its sequence number advances even when a writer rejects an offer, so a later accepted
interval and its offset retain honest gap evidence. Writer rejection is counted locally and cannot
enter the mixer call path. Individual-track configuration remains deliberately unavailable until
it can carry the required participant, connection, and track identity.

The focused test was first red because `RoomRecording` did not exist. Its green path mixes two
participants, observes the exact permitted full-mix bytes, denies recording for the middle
interval, then resumes at a later clock offset without replaying the denied audio:

```text
cd apps/vxpipe_call_engine
mix test test/vxpipe/call_engine/room_recording_test.exs --max-cases 1
# 1 test, 0 failures

mix test test/vxpipe/call_engine/room_recording_test.exs \
  test/vxpipe/call_engine/room_mixer_test.exs \
  test/vxpipe/call_engine/media_policy_room_test.exs \
  test/vxpipe/call_engine/silent_monitor_call_test.exs --max-cases 1
# 11 tests, 0 failures
```

This checkpoint does not yet wire a concrete artifact writer, select recordings from a call
definition, capture connection-qualified individual tracks, publish metadata, or add operator
playback. Those remain required before the milestone checklist can advance.

Root formatting, compilation with warnings as errors, strict Credo over 619 source files, all 805
umbrella tests, and the unused-dependency check pass.

## Checkpoint 4: bounded artifact adapter

`Vxpipe.Artifacts.RecordingWriter` now implements the call engine's writer port as an outer adapter.
The artifacts application has a compile-time-only dependency on the engine contract; the engine
retains no dependency on artifacts, and starting artifacts does not start the engine supervision
tree. The adapter translates an engine stream to an artifact specification, creates an opaque
artifact ID and encoded object-key path, starts the artifact-owned writer, and returns its bounded
handoff. It performs no object-store request itself.

Artifact chunks now carry channel count. Their `sample_count` is the number of per-channel clock
frames, and validation requires exactly `sample_count * channels * 2` bytes for signed 16-bit PCM.
Writer progress and manifest offsets therefore preserve room-clock duration for both mono and
multichannel audio.

The focused test was first red because the adapter did not exist. Its green path opens a stereo
full-mix stream, hands off two clock frames/four scalar samples, drains after the source exits, and
completes a manifest whose duration is exactly two sample frames:

```text
cd apps/vxpipe_artifacts
mix test test/vxpipe/artifacts/recording_writer_test.exs \
  test/vxpipe/artifacts/writer_test.exs --max-cases 1
# 2 tests, 0 failures
```

This checkpoint uses the existing fake object-store boundary. A concrete S3-compatible adapter,
room-supervision wiring, recording selection, individual connection tracks, relational metadata,
and operator playback remain pending.

Root formatting, compilation with warnings as errors, strict Credo over 622 source files, all 806
umbrella tests, and the unused-dependency check pass.

## Checkpoint 5: S3-compatible multipart object store

The artifacts application now has a concrete `S3ObjectStore`. It delegates operation construction,
request signing, credential providers, endpoint configuration, and response parsing to current
ExAws/ExAws S3, using their Req HTTP adapter. The implementation does not stage a file or introduce
an audio/video conversion dependency.

One multipart session buffers PCM as reversed iodata until it reaches the configured part size,
which cannot be below S3's five MiB minimum. Full parts upload sequentially in the artifact writer's
existing object-I/O task boundary. Completion uploads the permitted final short part, preserves
ordered part ETags, and completes the object; terminal part/completion failure attempts an abort.
The live side remains bounded independently, while object-store memory is bounded to one multipart
part plus one already-bounded input chunk. Client request options are excluded from session
inspection because they may contain credential-provider data.

The test was first red because `S3ObjectStore` did not exist. Its green path buffers two smaller PCM
chunks into an exact five-MiB first part, holds a final short interval, uploads that as part two on
completion, and supplies both ETags in order:

```text
cd apps/vxpipe_artifacts
mix test --max-cases 1
# 3 tests, 0 failures
```

ExAws 2.7.0, ExAws S3 2.5.9, Req 0.7.4, and SweetXml 0.7.5 are locked with the dependency change.
The design follows the official ExAws multipart and Req adapter contracts. The concrete adapter is
not yet selected by a supervised room, and the tagged S3-compatible integration lane remains
pending with recording configuration, track capture, metadata, and playback.

Root formatting, compilation with warnings as errors, strict Credo over 626 source files, all 807
umbrella tests, and the unused-dependency check pass.

## Specification review

Reviewed independently by milestone_review_b on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Corrected provable egress vs remote-playout boundary, room manifest identity and terminal-manifest outage guarantees; re-review approved.
This is specification evidence only; implementation and runtime verification remain unchecked.
