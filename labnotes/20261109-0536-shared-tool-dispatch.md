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
