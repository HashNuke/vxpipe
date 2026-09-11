# Streaming recordings

## 2026-09-11: artifact writer boundary

Started milestone 19 on branch `milestone/streaming-recordings`. Milestone 18 still has one
explicitly recorded external manual verification item, but its production and deterministic test
work is complete enough that it does not block the storage boundary.

The first checkpoint establishes `vxpipe_artifacts` rather than putting object-store behavior in
the call engine. The new application has one unique Registry, one Task Supervisor for blocking
object operations, and one Dynamic Supervisor for temporary call-scoped writers. The artifact
application depends on no other umbrella child, which preserves the intended dependency direction.

The test was written before the writer modules. Its initial run failed with
`UndefinedFunctionError` for `Vxpipe.Artifacts.Writers.start_writer/1`, which was the expected red
boundary. The implementation was split into cohesive modules for immutable artifact identity, PCM
chunks, bounded handoff, object-store behavior, manifest, result, writer state, writer callbacks,
and the supervised start API.

The fake store deliberately holds a write in a task. While it is held, the caller can offer a
second chunk and gets `{:error, :full}` for a third; no store call executes in the writer or source
process. After the source exits normally, the writer closes its handoff, refuses new chunks, drains
the two accepted chunks, and completes a manifest with 1,920 stored samples, one rejected chunk,
and `:incomplete` status. The first green attempt exposed that a terminal GenServer tuple was being
passed back through the ordinary state continuation; a dedicated stop-or-continue branch corrected
that callback lifecycle.

Evidence:

```text
cd apps/vxpipe_artifacts
mix compile --warnings-as-errors
# success

mix test test/vxpipe/artifacts/writer_test.exs --max-cases 1
# 1 test, 0 failures
```

Running `mix credo` from the child does not work because Credo is intentionally a root-only umbrella
dependency. From the root, formatting, compilation with warnings as errors, strict Credo over 612
source files, all 803 umbrella tests, and the unused-dependency check pass. No S3 request, database
row, room mixer subscription, or recording configuration exists yet.

## 2026-09-11: internal recording subscription

The next red test specified the policy boundary before starting any recorder process. It attempted
to create a full-mix recording subscription using a fresh room-local reference, rejected another
reference, and expected frames only in policy revisions whose effective `record_audio` value was
true. The initial run failed at the intended missing `RoomMixer.subscribe_recording/2` API.

The mixer now stores an optional unforgeable recording token. `SubscriptionCatalog` constructs a
separate `:recording` subscription with no participant recipient, while the existing path explicitly
marks every ordinary subscription as `:participant`. This prevents recording from borrowing monitor
or participant identity. Full-mix and individual-track modes are accepted; mix-minus is not.

Recording fanout deliberately does not use participant recipient routes. The route map answers who
may hear a source, while the independent effective `record_audio` boolean answers whether main-room
audio may be stored. Private transfer preparation never enters the main mixer. On a denial revision,
the existing policy barrier clears pending timestamp buckets and subscription queues before it
acknowledges the revision; the installed recording subscription simply receives nothing until a
later permitted revision supplies new frames.

Focused evidence:

```text
cd apps/vxpipe_call_engine
mix test test/vxpipe/call_engine/room_mixer_test.exs \
  test/vxpipe/call_engine/media_policy_room_test.exs \
  test/vxpipe/call_engine/silent_monitor_call_test.exs --max-cases 1
# 10 tests, 0 failures
```

No dependency on `vxpipe_artifacts` or network/storage work was added to the mixer. The next step is
the room-scoped capability that owns these subscriptions and projects their frames into bounded
artifact chunks.

Root formatting, compilation with warnings as errors, strict Credo over 612 source files, all 804
umbrella tests, and the unused-dependency check pass.

## 2026-09-11: room recording coordinator

The next test specified the storage-neutral engine boundary. Its red run failed because
`Vxpipe.CallEngine.RoomRecording` did not exist. The implementation adds that temporary
room-scoped process plus cohesive stream, chunk, writer-port, and process-state modules. The call
engine does not depend on the artifacts application.

At startup, the coordinator validates pinned tenant/call/room/incarnation identity, reads the
mixer's established PCM format, uses the room-local recording reference to subscribe, and opens an
injected writer. The writer contract is deliberately non-blocking: callback implementations may
start supervised workers or allocate a bounded handoff, but external I/O belongs outside the
engine process.

Each mixer availability message causes one bounded pull. Frames become typed chunks carrying a
per-stream sequence, room-clock offset, sample count, policy revision, contributing participant
IDs, and PCM payload. Sequence advances even for a rejected offer while the clock offset remains
authoritative, allowing downstream manifests to expose loss rather than close over it. Writer
errors increment a local rejection count instead of reaching the mixer.

The focused green test observed the exact two-source full mix at offset zero, no chunk while the
next policy revision denied recording, and only newly admitted audio at offset four after policy
relaxation. Adjacent mixer, media-policy, and silent-monitor tests also stayed green:

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

Formatting and compilation with warnings as errors pass. Root strict Credo checks 619 source files
without findings; all 805 umbrella tests and the unused-dependency check pass. The concrete
artifacts adapter, capacity rejection/lifecycle proof, connection-qualified individual tracks,
metadata, S3 integration, and playback remain pending.

## 2026-09-11: artifact recording adapter

The next test established the one-way integration boundary and initially failed because
`Vxpipe.Artifacts.RecordingWriter` did not exist. The artifacts application now has a
compile-time-only dependency on the engine's recording contract. The engine remains independent of
artifacts, and starting artifacts does not start the engine application.

The adapter turns the pinned recording stream into an artifact specification, generates a short
opaque artifact ID, encodes each external identity before building the object-key path, starts a
writer through the artifacts-owned dynamic supervisor, and returns its bounded handoff. It does not
perform external object operations. A small handle retains the writer PID, handoff, and channel
count; the latter is needed to validate PCM chunks without changing room-clock sample semantics.

The prior artifact chunk validation assumed mono. Chunks now state their channel count and validate
`sample_count * channels * 2` payload bytes. The new stereo test offers two per-channel frames/four
scalar samples, lets the writer drain after its source exits, and verifies that the manifest ends at
offset two rather than incorrectly treating the stream as four frames long. The existing bounded
writer lifecycle remains green:

```text
cd apps/vxpipe_artifacts
mix test test/vxpipe/artifacts/recording_writer_test.exs \
  test/vxpipe/artifacts/writer_test.exs --max-cases 1
# 2 tests, 0 failures
```

No concrete S3-compatible request, room-supervisor wiring, recording selection, individual-track
identity, relational metadata, or playback was added in this checkpoint.

Root formatting, compilation with warnings as errors, strict Credo over 622 source files, all 806
umbrella tests, and the unused-dependency check pass.

## 2026-09-11: multipart S3-compatible object store

The next red test described incremental multipart behavior and failed because
`Vxpipe.Artifacts.S3ObjectStore` did not exist. Two sub-part-size PCM chunks had to form one valid
five-MiB part; a later short interval had to remain buffered until completion, become the allowed
final short part, and precede an ordered ETag completion request.

The implementation delegates S3 signing, credential discovery, endpoint behavior, operation
construction, and response parsing to ExAws 2.7.0 and ExAws S3 2.5.9, using the official Req HTTP
adapter with Req 0.7.4. SweetXml 0.7.5 supplies the S3 XML parsers. The selection and minimum-part
behavior were checked against the [ExAws S3 multipart documentation](https://ex-aws-s3.hexdocs.pm/ExAws.S3.html#upload/4)
and the [ExAws Req adapter documentation](https://ex-aws.hexdocs.pm/ExAws.Request.Req.html).

`S3ObjectStore` initiates one upload per artifact and keeps a reversed iodata buffer. It allocates a
contiguous binary only when uploading a part, and its configured threshold cannot be smaller than
five MiB. Each request still executes inside the artifacts-owned task supervisor established by the
writer checkpoint. On terminal upload or completion failure it attempts to abort the multipart
upload and returns the original failure. No temporary file, media conversion, or separate OS
process is involved.

Trusted adapter options carry bucket and ExAws request/initiation settings. They are not accepted
from call definitions or client payloads, and the session's inspection output excludes both client
options and buffered PCM. The focused fake-client test observes exact part bytes and ETag order
without credentials or a network request:

```text
cd apps/vxpipe_artifacts
mix test --max-cases 1
# 3 tests, 0 failures
```

A fresh compile of dependency source emits one type-analysis warning inside SweetXml 0.7.5 under
Elixir 1.19; project warnings-as-errors compilation succeeds, and there is no project-owned warning.
A tagged live S3-compatible lane, runtime configuration/wiring, individual tracks, metadata, and
playback remain pending.

The first root suite attempt exited with one retained failure target under the persistence app, but
the captured tail did not include its assertion. `mix test --failed` reran that exact single target
successfully, and a subsequent complete suite passed. No implementation change was made in response;
this is recorded as a transient test observation rather than a diagnosed project failure.

Root formatting, compilation with warnings as errors, strict Credo over 626 source files, all 807
umbrella tests, and the unused-dependency check pass.

## 2026-09-11: supervised recording startup

The next call-engine test passed recording settings to `start_call/2` and expected the writer to
open a full-mix stream carrying the pinned tenant, call, room, and incarnation identity. It failed
at the expected boundary because room startup discarded those settings and never created a
recorder.

The room-incarnation supervisor now delegates recording-child construction to a cohesive helper.
When explicitly enabled, the helper creates a fresh reference, puts it into the room mixer's trusted
options, and gives the same reference to a temporary recorder. The recorder is ordered after the
significant room authority because authority initialization registers the mixer with the initial
media policy. Starting it earlier returned a policy-unavailable subscription and would have made
the supervision order incorrect. Disabled settings add no token and no child.

`RoomMixer.ref/1` exposes only its internal registered server reference. Recording configuration
resolves that reference to the actual mixer process before monitoring or subscribing, retaining
the existing direct-PID test boundary. The engine continues to accept an injected writer and has no
dependency on the concrete artifacts application.

The gateway's previously private option assembly was extracted into one adapter responsible for
mapping trusted call-admission settings into call-engine settings. Its test was separately red while
that adapter did not exist, then green after it preserved recording for both web and telephony call
startup paths.

Focused evidence:

```text
cd apps/vxpipe_call_engine
mix test test/vxpipe/call_engine/human_only_call_test.exs --max-cases 1
# 2 tests, 0 failures

cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/call_admission/call_engine_options_test.exs \
  test/vxpipe/gateway/call_admission_adapter_test.exs --max-cases 1
# 5 tests, 0 failures
```

Root formatting, compilation with warnings as errors, strict Credo over 628 source files, all 809
umbrella tests, and the unused-dependency check pass. Concrete runtime selection, qualified
individual tracks, metadata publication, integration storage, and playback remain pending.

## 2026-09-11: preserving recording source identity

The decoded gateway PCM contract already carried participant, connection, and track identity, but
normalization omitted the connection. Mixer buckets and source sequences then used only the
participant ID. This meant two simultaneous tracks belonging to one participant collided at the
same timestamp and could not later produce honestly identified separate artifacts.

Two tests captured the boundary first. The gateway test could not compile its expected normalized
connection because the struct lacked that field. The mixer test then required two connection/track
pairs for one participant at the same timestamp to be admitted and mixed instead of treating the
second as a duplicate.

`NormalizedFrame` now retains the connection ID. The timestamp buffer exposes one source-key
function for the participant/connection/track triple, and both buffering and sequence admission use
it. Connection and track identifiers are validated at mixer admission. Routers continue to apply
presence and audio routes by participant; a full mix deduplicates its contributing participant list
when multiple qualified tracks belong to that participant.

Focused evidence:

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

The next step is dynamic, policy-gated individual stream creation from this identity. No separate
artifact, metadata row, runtime storage selection, or playback endpoint was added here.

Root formatting, compilation with warnings as errors, strict Credo over 628 source files, all 810
umbrella tests, and the unused-dependency check pass.

## 2026-09-11: selected individual recording streams

The next test changed a recorder target from full mix only to full mix plus one selected participant.
Its red run stopped with `:invalid_recording_targets`, proving that no individual stream path existed.
The desired behavior required no individual writer at room creation, one writer after the selected
source's first qualified frame, exact unmixed PCM at the same room offset as the full mix, and no
writer for an unselected source.

Room startup accepts stable participant definition references in trusted recording settings and
resolves them against the pinned plan. It also supports selecting every plan participant. The
private mixer target holds resolved participant IDs, and its fanout creates one concrete individual
mode for each participant/connection/track source rather than mixing selected sources together.

The recorder now separates subscription state from concrete output state. Full mix opens at startup;
individual outputs open lazily because connection and track identity becomes available only with
media. Each output owns its own writer handle and sequence counter. Writer rejection remains outside
the mixer path, and the frame's authoritative room-clock offset still exposes loss or denied gaps.

The recording stream carries optional source identity only for concrete individual modes. Its opaque
stream ID is deterministically derived from that qualified identity. The artifacts locator maps the
stream to a participant-track specification with the exact participant, connection, and track IDs.
To preserve the required test sequence, the old full-mix-only locator was restored first; the new
adapter test failed on `:full_mix` versus `:participant_track`, then passed after the mapping was
applied.

Focused evidence:

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

This checkpoint does not yet select the S3 adapter in the Console runtime, persist artifact
metadata, prove terminal failure manifests, attribute accepted agent egress, run a tagged storage
integration, or expose playback.

The first two root-suite runs exposed existing timing sensitivity in unrelated asynchronous tests:
one lifecycle assertion installed its explicit monitor late, and one model-provider timeout allowed
only 25 ms for the request task to become observable under umbrella load. The lifecycle monitor now
starts immediately after room startup. The model test uses a still-bounded 250 ms provider deadline
and a one-second outcome assertion. Its focused 11-test module and the recording-focused tests pass.

Root formatting, compilation with warnings as errors, strict Credo over 630 source files, all 811
umbrella tests, and the unused-dependency check pass.

## 2026-09-11: asynchronous artifact metadata publisher

The artifact writer previously sent its terminal result only to an optional observer and then
exited. Calling a database adapter from that process would couple terminal object handling to SQL
latency, while routing the result through the room archive subscriber would lose results that finish
after the room and its archive drain.

A new artifacts-owned metadata port and temporary publisher separate this lifecycle. The artifact
writer starts a publisher with its immutable result and exits. The publisher invokes the configured
adapter in a dedicated task, bounds each attempt by time, and bounds total attempts. A maximum child
count on the publisher supervisor prevents an extended sink outage from retaining unlimited retry
processes. Observer outcomes distinguish success, explicit discard, invalid adapter response,
timeout, retry exhaustion, and inability to start a publisher.

The initial test failed after object completion because no metadata write message existed. The
green case proves the writer has stopped before the fake metadata adapter returns, then makes the
adapter request a retry and observes the identical result succeed on attempt two:

```text
cd apps/vxpipe_artifacts
mix test test/vxpipe/artifacts/writer_test.exs --max-cases 1
# 2 tests, 0 failures

mix test --max-cases 1
# 5 tests, 0 failures
```

No relational record, Calls workflow, runtime adapter selection, object-store integration, or
playback route is part of this checkpoint.

The first umbrella run also exposed a test-only two-second deadline in the existing native media
pipeline coverage while the suite was under concurrent load. That test now permits five seconds;
its focused two-test suite passes and no production deadline changed. The complete root rerun passes
formatting, compilation with warnings as errors, strict Credo over 635 source files, all 812 umbrella
tests, and the unused-dependency check.

## 2026-09-11: durable artifact metadata projection

The metadata publisher needed a database-neutral destination contract before runtime wiring. Calls
now has a dedicated artifact repository and workflows rather than adding unrelated callbacks to its
existing transcript/tool/variable archive repository. `CallArtifact` validates terminal identity,
PCM clock progress, source identity, gaps, status, and the stored-object reference. Tenant-bound
reads require the `calls` scope.

Persistence adds a ninth migration and a focused artifact store. It inserts or deduplicates one row
per call/artifact ID in a transaction, checks the established incarnation, rejects conflicting
redelivery, and returns the domain contract on reads. Rows contain manifests and storage references,
never PCM. A complete result must have an object reference; an incomplete result may have none.

The `EctoStorage` metadata adapter projects the artifacts terminal result into that Calls workflow.
It keeps the object key and optional ETag while dropping the provider-returned location, which is
not an authorization mechanism. Known invalid/conflicting results are terminal discards; repository
availability errors are retries for the publisher.

The Calls test first failed on the missing contract and APIs. After that boundary was green, the
persistence test failed with `:unsupported_archive_fact`, then passed through the real Ecto adapter
and transaction. Focused evidence:

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

The full nine-migration chain succeeded on a new empty temporary database, which was then removed.
Root formatting, compilation with warnings as errors, strict Credo over 641 source files, all 814
umbrella tests, and the unused-dependency check pass. Runtime recording configuration, terminal
failed-upload integration, agent-egress provenance, tagged storage integration, and playback remain.

## 2026-09-11: trusted runtime recording composition

The next checkpoint moved concrete adapter selection to the executable Console host. The focused
test was written before the configuration module and failed with the expected undefined
`Vxpipe.Console.RecordingConfiguration.build/1`. The implementation keeps recording disabled unless
the host explicitly enables it, and rejects enabled settings without both persistence and a bucket.

The enabled development profile injects the artifacts recording writer, multipart S3 object store,
and asynchronous Ecto metadata writer into the existing Gateway call-admission backend. Its targets
are the permitted full mix plus all permitted individual tracks. A coordinator pass pulls at most 16
room frames, writer capacity is 100 chunks (about two seconds with the configured 20 ms frames), and
post-source drain is bounded at 30 seconds. Those are application-owned limits, not client input.

Optional region and root HTTP(S) endpoint values become ExAws request overrides. A configured
endpoint uses path-style S3 requests. ExAws continues to discover credentials through its provider
chain; neither the configuration object nor the call definition receives credential values. Console
now has runtime dependencies on the artifacts and persistence applications because it is the
repository composition host. The engine and reusable Gateway retain their existing dependency
direction and ports.

Focused evidence:

```text
cd apps/vxpipe_console
mix test test/vxpipe/console/recording_configuration_test.exs --max-cases 1
# 4 tests, 0 failures

mix test --max-cases 1
# 63 tests, 0 failures
```

A development `mix run --no-start` probe supplied non-secret database, bucket, region, and local
endpoint values, evaluated `config/runtime.exs`, and matched the trusted writer/object-store
selection. It printed `trusted recording runtime configuration valid`; it intentionally made no
network request. Failed-upload projection, agent-egress provenance, tagged S3-compatible integration,
and authenticated playback remain pending.

The first complete umbrella run exposed the inbound Membrane child-readiness race recorded in the
separate `20260911-1942-audio-pipeline-readiness.md` labnote. After that ancillary fix, root
formatting, compilation with warnings as errors, strict Credo over 642 source files, all 818 umbrella
tests, and the unused-dependency check pass.

## 2026-09-11: terminal object-completion failure evidence

The next red test sent one accepted PCM chunk through a supervised artifact writer and configured
the fake object store to fail completion. It failed initially because the fake ignored that option
and returned a successful object reference. Test support now returns its configured completion
outcome after reporting the attempted manifest.

The production writer required no change. On failure it retained one accepted chunk and 960 samples,
changed the terminal status to incomplete with `completion_failed`, omitted the object reference,
exited normally, and passed the exact immutable result to the independently supervised metadata
publisher. The metadata adapter was allowed to acknowledge only after the artifact writer's `DOWN`,
demonstrating that metadata latency is not part of writer lifetime.

Focused evidence:

```text
cd apps/vxpipe_artifacts
mix test test/vxpipe/artifacts/writer_test.exs --max-cases 1
# 3 tests, 0 failures

mix test --max-cases 1
# 6 tests, 0 failures
```

The persistence checkpoint already covers storage of an incomplete result without an object
reference. This test intentionally does not claim survival when both object storage and metadata
storage are unavailable. Live agent-egress provenance, room/writer crash cases, tagged object-store
integration, and playback remain pending.

Root formatting, compilation with warnings as errors, strict Credo over 642 source files, all 819
umbrella tests, and the unused-dependency check pass.

## 2026-09-11: transport-accepted direct output

Tracing the implemented speech path showed that direct output did not enter the room mixer. Feeding
generated audio into recording would have been incorrect because interruption can discard queued
frames. Feeding it back into ordinary mixer fanout would also have duplicated live audio. The
chosen boundary therefore keeps live delivery unchanged and adds a distinct recording-only input.

The first engine test failed at the missing accepted-egress frame and handoff modules. The engine
now creates one connection-qualified handoff only for an enabled recording and binds it to a direct
output before connection startup can emit speech. The handoff reserves fixed capacity through
atomics, performs only a non-suspending send, and aligns each frame to the existing room clock. Its
recording gate carries the current policy revision. A denial prevents offers immediately, while the
mixer repeats revision and presence checks to fail closed across a transition race.

The mixer holds accepted direct output in a recording-only timestamp buffer. Recording subscribers
combine it with ordinary room input at the same timestamp; participant and monitor output ignore
that buffer. This preserves one live delivery while making the recorded full mix contain the audio
the transport actually accepted. Individual output identifies the source participant, destination
connection, and `agent-egress` track.

Gateway tests then failed at the absent recording-bind output contract. WebRTC now keeps the source
PCM beside each encoded packet and offers it only after RTP submission succeeds. The shared phone
output offers the exact in-flight PCM only after its Membrane pipeline acknowledges sending it.
Frames waiting in either bounded output queue are discarded by interruption without a recording
offer. This is deliberately called egress acceptance; nothing in this path proves remote playback.

Focused evidence:

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

The complete Call Engine suite passes 357 tests. The first root suite run retained one failed Call
Engine target after exiting nonzero; rerunning that exact retained target passed, and a subsequent
complete run passed all 823 umbrella tests. Root formatting, compilation with warnings as errors,
strict Credo over 647 source files, and the unused-dependency check also pass.

Pending milestone work remains room/writer crash behavior, tagged object-store integration,
authorized operator playback, and final cross-slice manual verification.

## 2026-09-11: recording failure isolation evidence

The room recorder is already a temporary, non-significant sibling of Room Authority, while each
artifact writer is independently supervised and monitors the recorder as its source. Focused
coverage now terminates the recorder after it has produced audio, observes its `DOWN`, and then
successfully reads the live room snapshot before ending the room through its normal lifecycle.
Recording failure therefore does not become call failure.

A separate artifact test accepts one chunk, kills the unlinked object-store task processing the
next chunk, and accepts a later chunk. The writer continues after the task failure. When its source
then exits abnormally, the writer drains and completes an incomplete manifest with two surviving
chunks, one rejected chunk, and the exact 960-sample gap between them. The source exit reason is
retained as terminal evidence. This depends on object completion remaining available; a total
object and metadata outage still cannot guarantee a durable manifest.

No production change was needed because the intended temporary-child, monitor, and unlinked-task
boundaries were already present. The first room test run failed only because the assertion expected
an `{:ok, snapshot}` tuple from an existing API that returns the snapshot directly; correcting the
test to the public contract produced the intended failure-isolation evidence.

```text
cd apps/vxpipe_call_engine
mix test test/vxpipe/call_engine/human_only_call_test.exs --max-cases 1
# 2 tests, 0 failures

cd apps/vxpipe_artifacts
mix test test/vxpipe/artifacts/writer_test.exs --max-cases 1
# 4 tests, 0 failures
```

The remaining milestone work is tagged object-store integration, authorized operator playback,
and final cross-slice manual verification.

Root formatting, compilation with warnings as errors, strict Credo over 647 source files, all 824
umbrella tests, and the unused-dependency check pass.

## 2026-09-11: S3-compatible multipart integration

The artifacts test helper now excludes `:integration` by default, matching the other networked
lanes. A new `:s3_live` test requires an explicitly enabled endpoint and bucket, uses the production
multipart adapter, uploads an exact five-MiB part plus a short final part, completes the object,
reads it back, and compares the entire PCM payload. Cleanup targets only the random object key made
by the test. Credentials remain in the standard ExAws provider chain and are not printed.

The default child suite remained green with the network test excluded:

```text
cd apps/vxpipe_artifacts
mix test --max-cases 1
# 7 tests, 0 failures (1 excluded)
```

The tagged lane was then run against a disposable MinIO server. The current container image was
pulled, the production code created the absent authorized test bucket, the multipart round trip
passed, and the test removed its unique object. The disposable container and its ephemeral storage
were removed by the command's exit trap:

```text
VXPIPE_S3_LIVE=1 \
VXPIPE_S3_INTEGRATION_ENDPOINT=<authorized-root-origin> \
VXPIPE_S3_INTEGRATION_BUCKET=<authorized-test-bucket> \
VXPIPE_S3_INTEGRATION_REGION=<region> \
mix test test/integration/s3_compatible_object_store_test.exs \
  --include integration --max-cases 1
# 1 test, 0 failures
```

The tagged network boundary is now covered. Authorized operator playback and final cross-slice
manual verification remain.

Root formatting, compilation with warnings as errors, strict Credo over 647 source files, all 824
default umbrella tests, and the unused-dependency check pass. The tagged object-store test is
excluded from that total and passed separately above.

## 2026-09-11: exact artifact access boundary

The private playback path needs one terminal artifact, but the existing Calls workflow returned
every artifact for a tenant-visible call. Filtering that list in Console would be authorized but
would make the presentation host retrieve and handle unrelated storage references. The new Calls
operation instead resolves one artifact through the repository using the authenticated tenant key,
call public ID, and artifact public ID.

The focused test was written first and failed with an undefined
`Vxpipe.Calls.fetch_call_artifact/4`. The workflow now rejects principals without the `calls` scope,
and the repository test adapter records the exact lookup without exposing object storage details.
The Ecto adapter first resolves the tenant-visible call and then queries the artifact by its public
ID within that call. Another tenant therefore receives `call_not_found`; a nonexistent artifact in
a visible call receives `call_artifact_not_found`.

```text
cd apps/vxpipe_calls
mix test test/vxpipe/calls/artifacts_test.exs --max-cases 1
# 1 test, 0 failures

cd apps/vxpipe_persistence
VXPIPE_TEST_DATABASE_URL=postgres://postgres:postgres@127.0.0.1:55433/vxpipe_test \
  mix test test/vxpipe/persistence/call_store_test.exs --max-cases 1
# 17 tests, 0 failures
```

No HTTP route or object reader exists in this checkpoint. The next change can build those pieces
without letting a browser choose a bucket or object key.

Root formatting, compilation with warnings as errors, strict Credo over 647 source files, all 824
default umbrella tests, and the unused-dependency check pass.
