# Shared tool bounds

## Scope and starting evidence

Continue at `fa7e2a35`, committed and pushed with a clean worktree. Shared
conversation admission is complete (8/20 tasks); all root gates passed with
5,158 tests, zero failures, plus Lean and clean Astra xhigh review. The preceding
goal turn made progress by reproducing/fixing admission defects and finishing
that checkpoint. No deployment is authorized.

This checkpoint closes C3's shared invocation bounds. Native trees still used a
hardcoded five-second timeout, sixteen workers/consumed IDs and 65,536-byte
results. LLM activations already used application settings and a transfer-aware
timeout. Reuse that projection and the existing workers/registry.

## Red evidence and implementation

Five focused cases initially failed (seed `207541`): configured short expiry,
configured concurrency, result size, a legitimate MCP operation beyond five
seconds, and transfer budget preservation. The transfer case first had an invalid
fixture model; after correcting the fixture, it reproduced a native 5,000 ms
budget instead of the required 31,000 ms. The other four failures were behavior
reproductions, not setup failures.

`Tool.InvocationConfig` extracts the existing settings projection and transfer
deadline calculation. LLM startup uses it directly; native startup stores the
same private options in its runtime and passes them through the existing allocation
tree to the registry and invocation supervisor. Standalone native allocations use
the same application defaults. No environment variables, new executor, provider
policy or compatibility path is introduced. Existing transport association/result
safety caps are separate from configurable worker execution bounds.

The former five-second expiry test now uses a configured 100 ms deadline and
proves `unknown`, worker cleanup, lease consumption and no retry. A gated MCP
fixture releases after 5.1 seconds and proves one normal completion from one
business attempt. Capacity tests recover after consumption; the existing sixteen-
worker interruption test explicitly selects that capacity. The first green run
passed four cases; the remaining failure was its test helper consuming a rejected
sibling's earlier Started event, corrected by correlating that rejection's events.

## Verification and remaining work

Startup/native/LLM regression passes: 133 tests, zero failures, seed `26644`.
Independent Astra xhigh source/test/documentation review is clean and supports
closing C3 bounds after the broader gates. Milestone remains 8/20 until those pass. Full-root evidence above
belongs to `fa7e2a35`; it is not evidence for this new checkpoint.

The read-only remaining-work audit identified reusable coverage in the registry,
LLM partial-admission tests, Console saved-MCP fixtures, and existing receptionist
tests. It also identified absent native tool-attempt usage configuration; reproduce
that separately before fixing it under C3 observability. Origin-aware stop-hold
completion remains an unmet requirement, not established by safe origin retirement.

The first quick-gate pass reached the existing PlanStartup file-size ceiling.
Binding tool settings before constructing the runtime made the projection easier
to read and removed the overflow without splitting unrelated responsibilities.
Compilation, format, strict Credo, unused dependencies and Lean now pass. Complete
Call Engine, AgentRuntime and Console suites are running; full umbrella verification
will be repeated for final integrated milestone acceptance.

Final relevant application suites pass: **3,039 tests, zero failures, 224 excluded**
(seed `628682`): Call Engine 2,380, AgentRuntime 108 and Console 551. Quick root
gates and Lean pass (seed `599571`). Independent source/test/doc review is clean. C3 bounds is
checked, bringing progress to 9/20; full milestone acceptance remains open.
