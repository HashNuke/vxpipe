# STS tool lifecycle

Isolated branch from `49213160`; only this worktree is writable for this task.
Native Codex only; no teammate/OpenCode. Dependency/build snapshots are copied
into this worktree so compilation cannot write another checkout. Two schedulers
and focused Call Engine tests only; parent owns integration/root acceptance.

## Inspection and pre-implementation design review

The current room executor uses raw Task.start and an independent five-second
timer; interruption removes the only room association. Existing Invocation
already owns a linked action task and reports timeout as unknown. Registry owns
bounded records and lease/commit delivery. Reuse these APIs unchanged.

The milestone task breakdown and labnotes/milestones/sts-tool-lifecycle.md were added before
tests or runtime edits. Proposed shared seam was reported to the parent in the
coordination update: private completion submission plus exact commit receipt,
running acknowledgement and conversation-mode admission. Shared provider and
capability APIs are excluded from this checkpoint. Retaining the old active-call
final-result path is explicitly incomplete, not substitute acceptance.

No Codex subagent tool is exposed in this session. Independent parent review is
still required; do not label local self-review as Astra independent review.

## Red/green execution evidence

All commands below ran from the owning `apps/vxpipe_call_engine` directory in
the isolated checkout, with local copied `_build` and `deps`. No root/native/
load/hosted/billable commands ran. Build/dependency symlink inspection found no
absolute link back into another checkout.

Initial red command (execution session 2234, terminal exit 2):

```sh
ERL_FLAGS='+S 2:2' mix test test/vxpipe/call_engine/room_authority/sts_tool_lifecycle_test.exs --seed 0
```

Seven tests, seven failures: no registry/tree APIs; actual worker survives its
deadline while the room publishes timeout; worker also survives capability,
explicit activation-tree stop and room owner loss. These are project-owned
integration failures, not tests of OTP guarantees.

First implementation run (42360, exit 2): seven tests, two fixture failures.
The fixture expected interrupt to return `:ok`; the existing contract returns
`{:ok, 0}`. Corrected that assertion without changing runtime behavior. Same
command then passed seven tests (14926, exit 0).

Initial regression selection (32205, exit 0): 79 tests, zero failures. Added
ownership-fault and simultaneous-running saturation checks within the already
recorded ownership/bounds scope. Final selection (77793, exit 0): 83 tests,
zero failures, including 11 new lifecycle tests:

```sh
ERL_FLAGS='+S 2:2' mix test test/vxpipe/call_engine/room_authority/sts_tool_lifecycle_test.exs test/vxpipe/call_engine/room_authority/sts_tool_identity_test.exs test/vxpipe/call_engine/room_authority/sts_transcript_modes_test.exs test/vxpipe/call_engine/capability/speech_to_speech_test.exs --seed 0
```

Exact edited Elixir files were formatted with owning-child `mix format` and
`git diff --check` passed. Only temporary significant invocation children were
added to Tree. RoomAuthority gained one dispatch tag; no parent-owned provider,
shared speech contract, capability controller or Socket changed.

## Review findings and remaining gates

Local diff review confirms no raw Task.start or independent execution timer
remains in STS Tools. Registry and worker APIs are reused unchanged; the registry
owns authoritative outcome and capacity. Bridge leases remain unconsumed even
after existing active-call delivery. No fake private acceptance is emitted.
Retired associations neither stop execution nor receive a late ordinary result.
The exact source/epoch/policy checks and public IDs are retained.

Supervisor-kill fault injection exposed generic Invocation's missing status/log
redaction: its crash report includes context and arguments. Only empty synthetic
arguments were used in that run, with no credentials. Proposed parent scope:
Invocation.format_status/1 and a focused STS crash/status regression. This actual
finding is not repaired by bridge redaction and remains OPEN pending coordination.

Running acknowledgements, private continuation commit/release and blocking/
nonblocking model admission remain OPEN, as do complete schema/binding adoption,
actual transfer acceptance and parent integration/root gates. The current host
execution selection remains blocking-only. The active-call final-result path is
preserved as an incremental boundary, not declared compliant with the final
conversation protocol. No checkpoint-wide or milestone-wide completion claim.
