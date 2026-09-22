# STS tool boundary

## Scope and inspection

Continue the open public-identity/tool lifecycle milestone tasks directly, per
the user's later instruction. Worktree started clean at `c171a7c8`.
Before editing tests or runtime, expanded the milestone into public identity,
ordered retirement, supervised execution and binding authorization tasks.

Observed defects in `RoomAuthority.SpeechToSpeech.Tools`: public IDs contain
`inspect(call_ref)` and tool-only correlation IDs contain the provider turn;
active duplicate calls overwrite pending work; the agent argument is not checked
against the current allocation; unknown cancellation creates a fabricated event;
completion may forward to the provider even after source loss. Capability owner
messages drop acknowledged channel order. Pending associations have no bound.

Separate execution defects remain explicit tasks: raw unowned tasks survive
cancellation/timeouts, their timers are not retained, and non-host bindings have
no executor/deadline. Shared `Tool.InvocationSupervisor`/`Invocation` already own
bounded worker execution and should be reused in the execution checkpoint.
Schema/variable/MCP permission adoption is not proven by an allowlist lookup.

## Design/dependency review

The room owns public IDs and exact-source authorization; the capability must
preserve acknowledged channel order, never publish room events. The ordered
envelope remains the next checkpoint. Use bounded active associations
and an owner-envelope sequence watermark rather than an unbounded tombstone set.
Provider adapters remain responsible for deduplicating upstream messages before
assigning fresh semantic event sequences. Do not claim worker lifetime is bounded
merely because the pending map is bounded. Keep identity and execution evidence
separate, with both required before closing the parent milestone task.

## Implementation and red/green evidence

The first room-boundary suite failed **16 tests out of 16**, including both
binary/reference privacy, shared IDs for simultaneous tool-only calls, private
key type collisions, duplicate admission, wrong-agent calls/cancellations,
unknown cancellations, replaced/missing source result delivery, epoch change,
capability replacement, and the seventeenth pending call. Reproduce from the
Call Engine child:

```shell
mix test test/vxpipe/call_engine/room_authority/sts_tool_identity_test.exs --seed 0
```

The repair uses `Id.generate(:tool_attempt)`, room-owned command/turn IDs, raw
private map keys and a saved exact allocation/source binding. Tool completions,
failures and cancellations reuse the started IDs. Lost/replaced sources cannot
receive a result; their pending associations still retire. Duplicate active
calls cannot overwrite or execute twice. The room's 16-entry association budget
rejects the next call with a safe provider failure without evicting admitted work.
Capability replacement clears old room tool associations.

Three follow-up source tests failed (**19 tests, three failures**): a tool could
reuse the old source's public audio-turn IDs after rebinding, admission accepted
a held/closed input epoch, and completion forwarded a held source's result. The
repair rechecks the current source and open epoch at admission and settlement,
including held membership; an audio turn must have that exact owner before its
public IDs can be shared. The complete room/output identity group then passed
44 tests. Timeout and invalid-result terminal identity checks were added to the
same suite, preserving the original timeout and result-size behavior.

The older room tool fixtures used a generic Agent which crashed on
`send_tool_result`; publication still passed because the runtime caught its
exit. Replaced those fixtures with an acknowledged result receiver and asserted
actual result delivery. The live Morse STS room test additionally submits an
explicit tool-only input through the real allocation, executes a compiled host
binding, compares action-context IDs with public start/completion IDs, and
checks both room and capability associations are empty. No invented audio turn
is published. This is a local embedded room tool call, not hosted/native tool
interoperability or a full schema/permissions acceptance test.

## Verification and next checkpoint

The broader focused STS suite passes **168 tests, zero failures**, seed 0. It
covers all 21 STS selection/example/startup, speech contract/output/tool/turn,
allocation concurrency, ingress, capability, room and transcript-mode files.
The new identity suite has 21 cases; the seven-case real-room matrix includes
the new tool round trip. Reproduce those boundaries together with:

```shell
mix test test/vxpipe/call_engine/room_authority/sts_tool_identity_test.exs test/vxpipe/call_engine/room_authority/sts_output_identity_test.exs test/vxpipe/call_engine/room_authority/speech_to_speech_test.exs test/vxpipe/call_engine/room_authority/sts_transcript_modes_test.exs --seed 0
```

The previous caller checkpoint's original umbrella process completed all five
gates successfully: **2,221 tests, zero failures, 42 excluded**, seed 0. It was
polled to successful exit rather than restarted on empty output. That evidence
belongs to `c171a7c8`, not this checkpoint. Commit this focused runtime/test/docs
checkpoint before its own umbrella gates, per the user's instruction.

Still required: ordered tool owner envelopes and post-terminal retirement,
capability pending bounds, supervised invocation adoption with actual worker/
timer cancellation, schema/permission and all supported binding execution,
and submitted-result retention. No change to timeout values, provider manifest,
hosted authorization, history replay or production Google availability. The
provider contract, author guide and unchecked milestone/index record the limits.

Pre-commit review: `git diff --check` passes, and 165 local Markdown links/anchors
resolve across the changed documentation. Reviewed exact staged paths and diffs;
no unrelated worktree changes were present.
