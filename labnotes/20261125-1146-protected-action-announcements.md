# Protected action announcements

The initial room tests failed because the two tool schemas lacked the announcement. Both passed after routing the optional text through the active caller-facing TTS capability. The tests use a real room with a controlled provider and a sink which withholds its drain acknowledgement.

Review exposed two playback boundary cases. Renderer loss after local completion must preserve the pending carrier drain. Delivered audio belongs in the archive and spoken history before the transfer projects history for its destination. Both regressions were reproduced and the five focused cases passed after the fixes. A further test checks that announced hangup cannot start a model continuation while the carrier drains.

A delayed-drain test reproduced an extra model round for both tools. The host now reports that the accepted invocation owns the current response. Hangup waits for the room before settling its tool result. A second red test suspended registry settlement, replaced the caller output generation and reproduced hangup of the replacement. Settlement now checks the caller binding again, distinguishes announced effects from immediate hangup and ignores late effects.

Astra reviewed the renderer/drain race, transfer history and model scheduling. Opus 5.5 reviewed the room/tool boundaries. Source inspection confirmed that the registry call catches exits and the TTS capability itself sends both synthesis acknowledgement and playback completion in order. The gateway can close a connection on an agent-unavailable notification, so the room demonitoring a failed renderer deliberately leaves its admitted action in control of the original sink. The room call now also converts exits into tool failures.

The API hangup test verifies administrative preemption. Other focused checks exercise a delayed sink acknowledgement, duplicate evidence, deadline fallback, renderer loss before and after local playback, archive delivery, caller text and speech onset, native tool projection and a competing tool completion. The tests use local provider and sink fixtures.

Two multi-tool tests reproduced a sibling completion starting an extra model round. The registry now defers model continuations while an announced action owns playback, rejects a competing hangup and releases the hold after a failed transfer. The test completes the recovery cue before expecting the failure observation. All 11 announcement tests passed together. The five shared-prompt tests also passed, including the instruction to use only supplied instructions or authorized knowledge tools for business facts.

An intermediate umbrella run saw an idle-acknowledgement ordering assertion fail. The isolated test passed 11 consecutive executions. The primary verification below uses the full final run.

## Reproduce the reviewed failures

From the umbrella root, run the following focused checks. The announcement tests exercise the room or its input and schema boundaries. The prompt tests inspect the packaged instructions. Live model behavior requires a separate call.

```sh
mix test --only protected_announcement apps/vxpipe_call_engine/test/vxpipe/call_engine
mix test apps/vxpipe_agent_runtime/test/vxpipe/agent_runtime/prompt_test.exs
mix test apps/vxpipe_call_engine/test/vxpipe/call_engine/call_variables_test.exs apps/vxpipe_call_engine/test/vxpipe/call_engine/room_authority/sts_tool_lifecycle_test.exs
```

| Regression case | Failure observed before the fix | Check on the fixed path |
| --- | --- | --- |
| Form permissions and grounding | The shared instructions lacked the intake rule, the empty writable form had no schema projection and native discovery with no arguments failed. The grounding assertion also failed before the explicit knowledge rule. | The prompt, Call Variables and native tool lifecycle tests cover these contracts. |
| Both tools with a delayed drain | The tool schemas lacked the argument. After wiring playback, the model still started a follow-up while the carrier was draining. | Both action tests hold the drain, attempt caller input and verify silence until release. |
| Renderer dies during synthesis | Accepted hangup remained pending after renderer death. | The room terminates with agent hangup before the speech deadline. |
| Renderer dies after local playback | The reservation ended before carrier drain. | The room remains in the draining phase until the original sink acknowledges. |
| Delivery history | The archive had no delivered-output event after confirmed playout. | Each action produces the delivered sentence after the sink acknowledges. |
| Destination history on handoff | Two isolated mutation replays removed confirmed history or recorded expired playback. The destination received an empty history in the first case and an unheard sentence in the second. | The `all_spoken` agent-to-agent tests inspect the actual destination model request for both outcomes. |
| Caller output changes during settlement | Replacing the output generation after drain caused the replacement call to receive the old hangup. | The original effect expires, the room survives and the sibling tool's model continuation resumes. |
| Sibling completion | A second tool in the same response started a model request during protected playback. | A completed sibling stays queued through hangup. Failure of an announced transfer releases it after the recovery cue drains. |
| Accepted hangup worker loss | Killing the invocation worker while the carrier was draining immediately started another provider request. | The room retains ownership until hangup even if the invoking worker exits. |
| Room loss during submission | Removing the room-exit handler in an isolated process turned a valid hangup into a GenServer exit when the room was gone. | The public hangup tool returns unavailable for the missing room and invalid arguments for blank text. |
| Large authorized form | A compiled plan granting 33 sections failed no-argument discovery with the 32-item explicit-selection limit. | The 33-section test checks implicit discovery and model context, explicit oversize rejection, and exclusion of ungranted sections. |

GPT-6.2 Astra at xhigh reviewed the complete working-tree changes, including the earlier form scope, tool permissions and prompt changes. Its final focused runs passed 237 tests across the call engine and agent runtime. Astra checked all 52 changed paths and verified 212 local documentation links. Some fixes already existed when their reproduction assertions were added. The history and missing-room rows above used process-local mutations of the fixed source to demonstrate the failure without changing the worktree.

Final umbrella verification passed 6,612 tests across ten applications with zero failures and 436 exclusions (seed 664789). The targeted announcement command passed 15 tests. Formatting, compilation with warnings as errors, strict Credo, unused-dependency checks and Lean verification all passed. Testing used local providers and sinks. Deployment and handset playback were outside this implementation checkpoint.
