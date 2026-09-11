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
