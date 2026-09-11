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
