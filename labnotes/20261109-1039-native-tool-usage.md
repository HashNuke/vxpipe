# Native tool usage observations

Start from pushed a22243b4 (13/20). C3's remaining task includes safe attempt
observations and terminal ordering. Native invocations use the shared executor
but omitted its usage configuration and target.

Four compiled ordinary/duplex success/unknown tests initially failed to receive
usage. The first archive fixture was incomplete: missing explicit subscriber
bounds disabled archival. Corrected that fixture and reran with native usage
still disabled: four failures, seed661588, while ordinary tool facts were present.
This confirms the missing observation rather than a disabled recorder. Reenabled
native usage and all four passed.

Reuse InvocationUsage/ToolAttempt unchanged. A separate optional usage_target in
the existing registry defaults to the text path's lifecycle target. Native usage
routes through its existing completion bridge, preserving registry-to-bridge-to-
room ordering ahead of terminal results. Authorize only the bridge belonging to
the current native capability; normal tenant/call/participant/activation checks
remain. Do not enable text lifecycle publication for native invocations merely
to obtain usage. No new recorder, store, process or queue.

Independent Astra design review agrees with separating the usage target and
requires success/unknown, rejected/replayed requests, stale-source denial and
terminal hangup/transfer evidence. Implementation review and final verification
remain pending.

Verification: four success/unknown cases pass after wiring. Native lifecycle/MCP
transfer/shared registry regression passed 72 tests (741106). Expanded regression,
including final archive replay assertions, shared usage, LLM coordinator/conversation
and native identity/lifecycle/MCP cases: 183 tests, zero failures (47746). Quick
root formatting, compile, strict Credo and unused-dependency checks pass. No
speech/source-cutover state machine changed in this checkpoint; the previous
checkpoint's Lean result is recorded separately, not claimed as a new run.

Independent GPT-6 Astra xhigh review found no actionable implementation issues
and approved closing C3 after the passing regression: 14/20 tasks, C3 5/5 and
2/4 checkpoints. C1 shared compiled-room partial admission and C4 remain open.
No deployment or live vendor run. Final full umbrella acceptance still belongs
to the remaining conformance checkpoint.
