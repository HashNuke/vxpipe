# Shared tool dispatch

## Scope and current checkpoint

Implement the shared participant tool milestone in small reviewed checkpoints.
The starting worktree was clean at `f2fd0f78`; all 20 milestone tasks were open.
No earlier runtime implementation was present in this checkout. The previous
planning turn made progress by committing the specification; this checkpoint
starts its implementation. `bin/setup` completed successfully.

The first change preserves the compiled native tool registry separately from the
provider's schema projection. `SpeechToSpeechActivation.resolve/3` now returns
the schema-only activation and the existing AgentRuntime `ToolRegistry` separately;
PlanStartup stores the registry on the private `SpeechToSpeechRuntime`. Provider
construction still receives only the existing activation projection. No adapter
implementation, tool dispatcher or conversation policy changes in this checkpoint.

This reuses the text path's `ToolDescriptors` and `ToolRegistry` validation,
including injected Call Variables tools. It does not add a second registry type
or expose handlers, compiled validators, variable permissions or owner references
to provider configuration. MCP startup still requires C2's owned remote handler.

## Red/green evidence

- Added a native/text registry contract test with a host tool and read-only Call
  Variables binding. The test compares resolved executable bindings and rejection
  of invalid arguments/unselected update tools. It also serializes the generic
  provider configuration to check that private bindings/sections/validators are
  absent, independently of Inspect redaction.
- Extended the actual compiled PlanStartup test to verify the private registry
  survives startup construction and resolves the selected host action.
- Both tests failed before implementation for the expected missing registry:
  **2 tests, 2 failures**, seed `151879`.
- Focused startup configuration, activation, existing Google session and descriptor
  tests pass after implementation: **101 tests, 0 failures**, seed `63750`.
  The provider-test change only adapts the private resolver's return tuple.

## Review, gates and notifications

Sent pushnotify at task start and after the focused tests passed. GPT-6 Astra
xhigh independently approved the code/test diff without actionable findings.
All five root checks pass: formatting, warnings-as-errors compilation, strict
Credo, unused-dependency validation, and **5,095 tests, 0 failures, 371 excluded**
(seed `293285`). The complete run includes 2,313 Call Engine and 876 Gateway tests.
The review agent separately approved the documentation/progress accounting with
no actionable findings. No valid bug report required a reproduction/fix cycle for
this checkpoint; the initial missing-registry tests supplied red/green evidence.
No speech/source-cutover state transition changed, so this checkpoint does not
require a new Lean run.

The first milestone task is checked from the focused contract/startup evidence;
all dispatch, MCP ownership, conversation policy and final acceptance tasks remain
open. This leaves the milestone at 1/20 tasks and 0/4 complete checkpoints.

## Next dispatch checkpoint

An independent read-only design review confirmed the next change should resolve
the exact runtime's compiled descriptor before publishing/submitting work, then
send its binding directly to the shared invocation registry. Keep participant and
activation checks. Preserve pending-source/policy checks before applying hangup;
the existing end-call authorizer alone does not verify the input epoch or owner.
Preserve the already-committed transfer teardown path.

The identity unit tests currently fabricate an ownerless MCP binding to exploit
silent deferral. Replace that fixture with an actual shared tool registry and
supervised invocation registry/worker, keeping result publication under the test's
control. Deterministically lease/acknowledge its completions instead of inflating
capacity for the 50-call watermark case. Compiled-room tests continue to prove
actual tree ownership. Reproduce duplicate settled-reference behavior before
claiming full duplicate protection; a fresh sequence can currently generate a new
invocation ID. These are next-step test/design requirements, not implemented fixes.

## Shared dispatch and scoped platform effects

Native admission now resolves the exact runtime's compiled registry before
publishing or executing work. Participant and activation must match the runtime,
recorder and current capability. Selected host, platform, variable and transfer
bindings go directly to the existing InvocationRegistry; the parallel host/transfer
switch and silent deferral are removed. Invalid schemas and unselected names
produce bounded failures without pending work or a worker.

Platform results expose only their public result. Native hangup queues a private
source/policy scope; the room checks that scope again before applying the existing
EndCall authorization. This closes the interval between completion publication
and processing the queued effect. Transfer keeps its existing post-commit teardown
path because the source has already changed at commit.

Verification so far:

- Three compiled-room tests reproduced pending current-time/hangup and invalid
  host arguments reaching the worker: 3 failures, seed `822818`.
- Six scoped platform-effect tests failed before public-result normalization and
  effect application. They now cover current hangup and queued source, epoch,
  hold, denied-policy and regranted-policy changes.
- An additional activation test reproduced admission with a stale capability
  activation even though the runtime/recorder matched: 1 failure. Matching all
  three activation identities fixes it.
- Compiled native variable read/update, denied-section and read-only tool-selection
  cases pass using the same dispatch. The suspected variable startup failure did
  not reproduce, so no variable startup workaround was added.
- Initial focused lifecycle/identity/platform/transfer lane: 61 tests, 0 failures,
  seed `523389`. Expanded native/LLM/transfer lane: 110 tests, 0 failures, seed `539620`. See the final verification below for the superseding deletion checkpoint.

Independent GPT-6 Astra xhigh review found older tests relying on ownerless MCP
bindings or silent deferral. Reproduced three plan-only unit failures and a duplex
mute timeout before migrating those fixtures. Stopped that failing run after
recording concrete failures instead of waiting through repeated timeouts. Unit
fixtures now use real compiled registries; compiled duplex mute/overlap tests use
the existing controlled host worker and complete it rather than injecting a room
result. Original lifecycle and speech assertions are retained. The second review
approved the code with no actionable findings.

No provider adapter or speech/source-cutover state-machine transition changes in
this checkpoint. Duplicate settled-reference handling, completion consumption,
conversation-mode policy, configured execution bounds and owned native MCP startup
remain subsequent milestone work. Dispatching non-blocking tools is not evidence
that C3's conversation behavior is complete.

The EndCall extraction keeps RoomAuthority below its existing 800-line strict
Credo limit; the first gate run caught that limit before the full test suite.
Independent review approved the extraction and corrected task accounting: C1
has 3/5 tasks complete (3/20 overall). Silent deferral and basic schema/name
rejection are fixed, but task 3 remains open for its revoked/unsupported-operation
rejection contract. Source/policy fencing alone is not evidence of that contract.
The user clarified that no legacy compatibility is required before launch;
superseded paths must be removed as the shared implementation lands.

The follow-up audit found no production senders for direct native execution/timeout
messages. Two real-room tests reproduced premature settlement through those paths
(2 failures), then passed after deleting the handlers, unused result/timeout
wrappers and delegates. The room ignores unknown messages generally; it has no
special compatibility handling for removed events. Current semantic settlement
still comes from InvocationRegistry completions or immediate admission failure.
Tests call that helper directly where they own synthetic room state.

Final focused regression result: **112 tests, 0 failures**, seed `286573`, covering
native identity/lifecycle, ordinary and duplex mute/overlap, native and LLM
platform/transfer scenarios. A generated-test constant comparison emitted a type
warning; extracting the two message shapes into test helpers removed it, and the
two affected tests were rerun. Formatting, warnings-as-errors compilation, strict
Credo and unused-dependency checks pass. The full umbrella run was deliberately
interrupted when the user's no-legacy-path direction added this deletion; it is
not passing evidence for this checkpoint. The full suite remains required at the
milestone integration gate. Focused suites accompany small coherent checkpoints
to avoid repeating the approximately twelve-minute umbrella run for each one.
Independent GPT-6 Astra xhigh review approved the removal with no code findings;
its requested progress correction is reflected in the milestone and index.
