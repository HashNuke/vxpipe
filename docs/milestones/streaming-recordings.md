# Permitted live recordings streamed to S3

Status: implementation in progress. Specification review: approved (2026-09-08).
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
- [x] Implement bounded stream-to-S3 recording plus asynchronous metadata/manifests.
- [x] Capture live full mix and selected individual tracks with shared clocks and honest egress provenance.
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

## Checkpoint 6: room-supervised recording startup

Trusted call-start options can now explicitly enable recording and supply its target list, bounded
pull size, and writer adapter. Recording remains disabled by default. Gateway admission forwards
the same application/tenant-owned settings for web and telephony starts; client payloads and call
definitions do not gain storage credentials or adapter options.

The room-incarnation supervisor creates one fresh reference per enabled room and injects it into
only the room mixer and its temporary `RoomRecording` sibling. It starts the recorder after the
significant room authority has registered the mixer with the initial media-policy snapshot. An
enabled recorder therefore cannot open a policy-less tap, and an invalid enabled setup fails room
startup instead of silently claiming recording. The engine still knows only its recording-writer
port; the host may inject the artifacts adapter without reversing that dependency.

The call-engine test was first red because `start_call/2` discarded the recording option. Its green
path starts a complete two-human planned room, observes an opened full-mix stream with the pinned
tenant/call/room/incarnation identity, and ends the room through its lifecycle. A second gateway
boundary test was red until its extracted call-engine option adapter preserved the trusted recording
configuration:

```text
cd apps/vxpipe_call_engine
mix test test/vxpipe/call_engine/human_only_call_test.exs --max-cases 1
# 2 tests, 0 failures

cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/call_admission/call_engine_options_test.exs \
  test/vxpipe/gateway/call_admission_adapter_test.exs --max-cases 1
# 5 tests, 0 failures
```

This checkpoint does not add a call-definition recording shape, select the concrete S3 adapter in
the Console runtime, capture connection-qualified individual tracks, publish artifact metadata, or
serve operator playback. Those remain later parts of this milestone.

Root formatting, compilation with warnings as errors, strict Credo over 628 source files, all 809
umbrella tests, and the unused-dependency check pass.

## Checkpoint 7: connection-qualified mixer sources

The gateway's normalized PCM frame now preserves the authenticated connection ID already present
on decoded media. The engine validates connection and track identifiers, and the mixer keys each
timestamp bucket and monotonic sequence by participant, connection, and track together. Two active
tracks owned by one participant therefore remain separate sources instead of the later frame being
rejected as a duplicate of the participant.

Participant-level route and presence policy is intentionally unchanged: all tracks still inherit
their authenticated participant's live policy. Full-mix provenance reports unique contributing
participant IDs even when that participant supplied multiple tracks. The complete source identity
remains on normalized frames for the next checkpoint to open distinct individual recording streams.

The call-engine test first failed because `NormalizedFrame` had no connection field. After that
field was introduced, the new same-participant case exposed the former participant-only duplicate
key; its green path admits two connection/track pairs at one room timestamp and produces their
combined samples. The gateway test separately proves that normalization retains both identifiers:

```text
cd apps/vxpipe_call_engine
mix test test/vxpipe/call_engine/room_mixer_test.exs \
  test/vxpipe/call_engine/room_recording_test.exs \
  test/vxpipe/call_engine/human_only_call_test.exs \
  test/vxpipe/call_engine/silent_monitor_call_test.exs --max-cases 1
# 14 tests, 0 failures

cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/media/room_audio_ingress_test.exs --max-cases 1
# 4 tests, 0 failures
```

This checkpoint does not yet create one artifact per source or add selection, metadata persistence,
playback, or a concrete runtime S3 configuration.

Root formatting, compilation with warnings as errors, strict Credo over 628 source files, all 810
umbrella tests, and the unused-dependency check pass.

## Checkpoint 8: selected individual track artifacts

Trusted recording targets can now combine `:full_mix` with all individual tracks or with individual
tracks selected by stable participant definition keys. Room startup resolves selected keys against
the pinned call plan and passes only the resulting participant IDs into the private mixer
subscription. Unknown or malformed selections fail an explicitly enabled recording setup rather
than silently widening capture.

The mixer emits one unmixed frame per selected participant/connection/track source. `RoomRecording`
keeps one subscription state separate from its concrete output states and opens an individual writer
only when the source's first frame reveals its connection and track IDs. Every artifact has its own
sequence while retaining the shared room-clock offset and policy revision. An unselected source is
not delivered to the recorder and cannot open a writer.

The recording stream and artifacts adapter carry the exact participant, connection, and track
identity into a `:participant_track` object specification. Its opaque stream ID is derived from the
qualified identity; storage keys still use the independently generated artifact ID. No audio
conversion or external process is introduced.

The engine test was first red because only full-mix targets were valid. It now proves a selected
source opens lazily, preserves exact identity and PCM, shares offset zero with the full mix, remains
absent for an unselected source, and obeys the same deny/resume policy intervals. The planned-room
test separately proves stable definition-key resolution. The artifacts test was run red against the
old full-mix locator before adding the individual mapping:

```text
cd apps/vxpipe_call_engine
mix test test/vxpipe/call_engine/human_only_call_test.exs \
  test/vxpipe/call_engine/room_recording_test.exs \
  test/vxpipe/call_engine/room_mixer_test.exs --max-cases 1
# 13 tests, 0 failures

cd apps/vxpipe_artifacts
mix test test/vxpipe/artifacts/recording_writer_test.exs --max-cases 1
# 2 tests, 0 failures
```

Concrete Console/S3 configuration, metadata persistence, writer-failure completeness evidence,
agent-egress provenance, tagged storage integration, and operator playback remain pending.

Root formatting, compilation with warnings as errors, strict Credo over 630 source files, all 811
umbrella tests, and the unused-dependency check pass.

## Checkpoint 9: asynchronous terminal metadata publication

An artifact writer now treats terminal metadata as a separate lifecycle after object completion.
When configured, it starts a temporary artifacts-owned metadata publisher with the exact terminal
manifest and stored-object reference, then exits normally. The publisher performs adapter work in a
dedicated task supervisor, applies a bounded write timeout, and retries only up to its trusted
attempt limit. Neither a slow metadata sink nor its retries keep the artifact writer or room alive.

The publisher tree has a fixed maximum child count. Capacity exhaustion, invalid writer replies,
write timeout, retry exhaustion, and explicit discard are observable terminal outcomes instead of
unbounded retained processes or invented persistence. Metadata publication remains disabled when no
adapter is configured. The port and publisher stay in `vxpipe_artifacts`; they introduce no Calls,
Ecto, or call-engine dependency.

The test was first red because the completed artifact produced only the existing observer result.
Its green path completes an object, proves the artifact writer has already stopped, returns a
retryable database-style failure from a fake metadata adapter, and then observes the same immutable
result published successfully on the second attempt:

```text
cd apps/vxpipe_artifacts
mix test test/vxpipe/artifacts/writer_test.exs --max-cases 1
# 2 tests, 0 failures

mix test --max-cases 1
# 5 tests, 0 failures
```

This checkpoint does not yet add PostgreSQL artifact records, select runtime adapters, prove
terminal upload-failure projection, run tagged object-store integration, or expose operator
playback.

Root formatting, compilation with warnings as errors, strict Credo over 635 source files, all 812
umbrella tests, and the unused-dependency check pass.

## Checkpoint 10: durable call-artifact records

Calls now owns a focused `ArtifactRepository` port and artifact workflows separate from transcript,
tool, and variable archives. Its immutable `CallArtifact` contract validates room/call identity,
full-mix versus participant-track identity, PCM format, aligned progress and gaps, terminal status,
and the optional stored-object reference. Reads require the caller's `calls` scope and bind the
tenant at the repository query.

Persistence adds a `call_artifacts` table and `ArtifactStore`. One terminal row belongs to one call,
is deleted with that call, and contains no audio bytes. Identical delivery is idempotent;
conflicting reuse of an artifact ID, a mismatched call incarnation, an unstarted call, or a
cross-tenant lookup fails. A complete row requires an object reference, while an incomplete row may
honestly retain manifest evidence when object completion failed.

`EctoStorage` also implements the artifacts metadata port. Its projection keeps only the object key
and optional ETag from the storage result; a provider-returned location is neither persisted nor
treated as access authorization. Terminal validation/conflict failures are discarded, while
transient repository failures remain retryable by the artifacts-owned publisher from checkpoint 9.
The dependency from Persistence to Artifacts is compile-time only, preserving application startup
ownership.

The Calls test was first red at the absent artifact contract/workflow. The persistence test was then
red because `EctoStorage` classified the terminal result as unsupported. Green evidence covers the
separate Calls boundary, real Ecto transaction/deduplication, exact gap and object-reference
round-trip, conflict rejection, and all persistence tests:

```text
cd apps/vxpipe_calls
mix test test/vxpipe/calls/artifacts_test.exs \
  test/vxpipe/calls/archives_test.exs --max-cases 1
# 10 tests, 0 failures

cd apps/vxpipe_persistence
VXPIPE_TEST_DATABASE_URL=postgres://postgres:postgres@127.0.0.1:55433/vxpipe_test \
  mix test --max-cases 1
# 32 tests, 0 failures
```

The complete nine-migration chain also succeeds against a newly created empty database, which was
removed after verification. Runtime recording/S3 selection, failed-upload end-to-end publication,
tagged storage integration, agent-egress provenance, and operator playback remain pending.

Root formatting, compilation with warnings as errors, strict Credo over 641 source files, all 814
umbrella tests, and the unused-dependency check pass.

## Checkpoint 11: trusted Console recording composition

The repository development host can now select the concrete recording path without changing a call
definition or client contract. Recording remains disabled by default. An explicit runtime switch
requires both PostgreSQL-backed persistence and an S3 bucket, then Console injects the existing
artifacts recording writer, multipart S3 object store, and asynchronous Ecto metadata adapter into
the Gateway's ordinary web/telephony call-admission backend.

The host records the permitted live full mix and all permitted individual tracks. Its fixed bounds
pull at most 16 mixer frames per coordinator pass, admit at most 100 pending writer chunks (about two
seconds with the current 20 ms room frame), and allow a terminating writer up to 30 seconds to drain.
ExAws retains credential discovery and request signing. Optional trusted region and root HTTP(S)
endpoint settings support AWS and path-style S3-compatible stores without putting secrets, storage
options, or adapter modules in client payloads or call definitions.

`vxpipe_console` now declares the artifacts and persistence applications as runtime dependencies
because it is the executable composition host. Call Engine remains storage-neutral, Gateway remains
reusable without Phoenix, and an embedding host may continue to inject another writer through the
same engine-owned port.

The focused test was first red because `RecordingConfiguration.build/1` did not exist. Its green
cases cover the disabled default, exact enabled composition, ExAws defaults, missing persistence or
bucket, malformed endpoint, and malformed enablement:

```text
cd apps/vxpipe_console
mix test test/vxpipe/console/recording_configuration_test.exs --max-cases 1
# 4 tests, 0 failures

mix test --max-cases 1
# 63 tests, 0 failures
```

A `mix run --no-start` probe with non-secret development values also evaluated
`config/runtime.exs`, rebuilt the trusted recording options, and verified the concrete writer and
object-store selection. No network request or object upload was claimed by that probe.

The first umbrella run exposed an existing inbound Membrane readiness race and failed one gateway
test before recording tests ran. That separately documented fix now waits for every pipeline child
to be playing before accepting input. The rerun passes root formatting, compilation with warnings
as errors, strict Credo over 642 source files, all 818 umbrella tests, and the unused-dependency
check.

Terminal failed-upload evidence, agent-egress provenance, tagged S3-compatible integration, and
authorized operator playback remain pending. The milestone is not complete.

## Checkpoint 12: object-completion failure evidence

The artifact-writer test boundary now exercises a successful bounded PCM handoff followed by a
terminal object-completion failure. The writer preserves the accepted sample/chunk counts, changes
the attempted complete manifest to `incomplete` with a closed `completion_failed` reason, publishes
no object reference, and hands that exact result to the separately supervised metadata publisher.
The writer exits normally before the metadata adapter acknowledges success.

The test was first red because the fake object store still returned its unconditional success and
the writer correctly produced an object reference. Its configurable completion outcome then made
the existing production failure path observable without adding a network dependency:

```text
cd apps/vxpipe_artifacts
mix test test/vxpipe/artifacts/writer_test.exs --max-cases 1
# 3 tests, 0 failures

mix test --max-cases 1
# 6 tests, 0 failures
```

Checkpoint 10 independently proves that this no-object, incomplete result is accepted by the real
Ecto metadata projection for a started call. This checkpoint does not claim that metadata survives
a simultaneous object-store and database outage. Agent-egress provenance, tagged S3-compatible
integration, room/writer crash coverage, and operator playback remain pending.

Root formatting, compilation with warnings as errors, strict Credo over 642 source files, all 819
umbrella tests, and the unused-dependency check pass.

## Checkpoint 13: transport-accepted agent egress

Direct agent and opening audio continues to use the existing connection output path, but recording
no longer assumes that generated or queued TTS reached that path. When recording is enabled, Room
Authority obtains a connection-qualified bounded handoff from the mixer and binds it to the direct
output before connection startup can emit audio. Disabled recording adds no binding. Private
transfer-preparation output is not bound, so its briefing cannot enter the main-room recording.

WebRTC retains each original 20 ms PCM frame beside its encoded Opus payload only until
`send_rtp/3` accepts that packet. The shared telephony output retains the same PCM in its existing
in-flight frame until the provider-specific Membrane pipeline reports the socket send. Only at
those boundaries does Gateway offer a typed `EgressAcceptedFrame`; encoding, generation, bounded
queue admission, and the later pacing callback do not count. A successful offer means transport
egress acceptance, never proof that the browser or phone played or heard the audio.

The engine handoff uses atomics-backed fixed capacity and a non-suspending send, so mixer or
recording pressure cannot block live output. It stamps accepted PCM against the shared room clock
and the effective recording-policy revision. The mixer keeps those frames in a separate
recording-only timestamp buffer: recording subscriptions combine them with ordinary room inputs,
while participant and monitor playback subscriptions never receive the direct audio a second time.
Policy denial closes the atomic gate; a frame racing a transition is also rejected by revision at
the mixer, and permission relaxation cannot replay it. Qualified agent tracks use the destination
connection plus the stable `agent-egress` track identifier.

The first call-engine test was red because the accepted-egress contract and mixer API did not
exist. Its green path combines accepted agent PCM with a human input in the recorded full mix,
proves the ordinary listener receives only the human input, and proves policy denial ignores later
egress. Separate Gateway tests were red at the absent output binding API. Their green paths prove
that WebRTC records only a successfully submitted RTP packet and telephony only a
Membrane-acknowledged in-flight frame, while queued frames discarded by interruption produce no
recording offer:

```text
cd apps/vxpipe_call_engine
mix test test/vxpipe/call_engine/human_only_call_test.exs \
  test/vxpipe/call_engine/room_mixer_test.exs \
  test/vxpipe/call_engine/room_recording_test.exs --max-cases 1
# 15 tests, 0 failures

cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/webrtc/audio_egress_test.exs \
  test/vxpipe/gateway/media/audio_output_test.exs --max-cases 1
# 11 tests, 0 failures

mix test --max-cases 1
# 224 tests, 0 failures (6 excluded)
```

This closes generated-versus-egress-accepted provenance for the implemented WebRTC, Telnyx, and
Twilio direct-output paths without changing live participant routing. It does not claim remote
playout confirmation. Room/writer crash coverage, tagged S3-compatible integration, authorized
operator playback, and final cross-slice manual verification remain pending.

The complete Call Engine suite passes 357 tests, and the root gates pass formatting, compilation
with warnings as errors, strict Credo over 647 source files, all 823 umbrella tests, and the
unused-dependency check.

## Specification review

Reviewed independently by milestone_review_b on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Corrected provable egress vs remote-playout boundary, room manifest identity and terminal-manifest outage guarantees; re-review approved.
This is specification evidence only; implementation and runtime verification remain unchecked.
