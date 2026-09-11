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
