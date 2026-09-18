# Jido loop and runtime tool bindings

Date: 2026-09-08. Status: superseded on 2026-09-10 for forward implementation.

The Jido-backed implementation and investigation below remain factual evidence for completed
milestones. Vxpipe will not maintain a Jido fork or wait on its missing runtime data-tool
interface. The selected forward path is the separate
[ReqLLM agent runtime](reqllm-agent-runtime.md), implemented before live MCP tools. That
milestone must preserve the completed behavior before Jido dependencies are removed.

## Superseded decision

Keep **Jido AI for the model/tool loop** and Jido Action for finite, application-owned
tools. Use **ExMCP directly behind `vxpipe_mcp`** for remote discovery/invocation.
Neither direct `jido_mcp` nor unreleased Jido Connect is a prerequisite. Choosing a
protocol client does not require Vxpipe to implement another LLM loop.

One supervised Jido AgentServer remains the inference child of each Vxpipe agent
activation. Vxpipe owns call authority, tool grants, private bindings, background
workers and voice-turn coordination. Jido owns successive model/tool rounds through
ReqLLM. The AgentServer choice now rests on this lifecycle boundary, not on the
discarded Jido MCP synchronization API. Standalone ReAct is an isolated test surface.

There is a separate, real compatibility gap: current Jido AI does not provide the
runtime data-tool registration/projection/execution surface our dynamic catalogs need.
Direct ExMCP fixes neither that gap nor arbitrary local aliases for static Actions.
The live-MCP milestone must obtain and verify a supported public Jido AI extension
before it can ship. Do not describe a small existing adapter as sufficient.

## Verified behavior

Reviewed published Jido AI 2.3.0, Jido Action 2.3.2, ExMCP 1.3.0 and Vxpipe's
ReqLLM 1.22.0 together in an isolated `Mix.install` probe. All four resolved, compiled
and started together under Elixir 1.19.5. This is dependency compatibility evidence,
not umbrella integration or remote MCP conformance.

Five deterministic ExUnit checks passed:

| Check | Observed result |
| --- | --- |
| Script two successive model-requested Action calls, then a final answer | ReAct executes both and continues to the answer; no Vxpipe loop is needed |
| Supply a runtime descriptor map as a request tool | Rejected as `:invalid_tools` |
| Supply a `ReqLLM.Tool` with a callback as a request tool | Rejected as `:invalid_tools` |
| Register `local_lookup` against an Action named `static_lookup` | Executor registry retains the alias, but model projection uses `static_lookup` |
| Register two aliases of the same Action | Model projection raises duplicate tool names |

The probe used `Jido.AI.Test.expect_react`, `react_llm_opts` and `ReAct.run`, with
two instrumented Action executions, `tool_max_retries: 0` and concurrency one. The
negative checks used `ToolSelection.normalize_input`, `ReAct.build_config` and
`Config.reqllm_tools`. They characterize upstream compatibility, not project-owned
runtime tests to copy into the umbrella. Implementation tests should exercise our
adapter boundary. No live model, MCP endpoint or credentials were used.

Release source and current default branch
`fc5bc1434ddb69493fe8a68443f03bc6a198c5a2` explain the result:

- `ToolAdapter` builds model definitions from Action modules. Its generated ReqLLM
  callback is not the ReAct execution hook.
- `Config.reqllm_tools` projects module values, losing registry aliases.
- `ToolSelection` permits Action-module tools, not runtime descriptor/callback values.
- The request transformer can change tool selection, but the runner normalizes it
  afterward and regenerates `llm_opts[:tools]` from those modules. Supplying arbitrary
  schemas through request options is therefore not an escape hatch.
- On the reviewed default branch, the runner resolves an Action before invoking
  `before_tool_call`; that hook can
  change arguments, not tool identity or executor, and is required to return quickly.
  `after_tool_call` projects a result after execution, not an alternate dispatcher.

Sources: [Tool adapter](https://hex.pm/packages/jido_ai/2.3.0/files/lib/jido_ai/tool_adapter.ex),
[configuration](https://hex.pm/packages/jido_ai/2.3.0/files/lib/jido_ai/reasoning/react/config.ex),
[tool selection](https://hex.pm/packages/jido_ai/2.3.0/files/lib/jido_ai/reasoning/react/tool_selection.ex),
[request transformer](https://hex.pm/packages/jido_ai/2.3.0/files/lib/jido_ai/reasoning/react/request_transformer.ex),
[runner](https://hex.pm/packages/jido_ai/2.3.0/files/lib/jido_ai/reasoning/react/runner.ex),
[default-branch interceptor](https://github.com/agentjido/jido_ai/blob/fc5bc1434ddb69493fe8a68443f03bc6a198c5a2/lib/jido_ai/tool_interceptor.ex).

The boundary was revalidated on 2026-09-10. The official Hex registry still lists 2.3.0 as
the latest `jido_ai` release. The current upstream `main` commit
[`e3d0f767`](https://github.com/agentjido/jido_ai/tree/e3d0f7671fe1349c00d7f6918eaee95a17c4c33c)
still types and validates ReAct tool inputs as Action modules, derives ReqLLM definitions from
those modules, and dispatches by the resolved Action module. No public runtime descriptor/executor
contract matching the requirements below was found. [Issue 282](https://github.com/agentjido/jido_ai/issues/282)
also remains open; its proposed bounded `search_actions`/`run_action` facade deliberately differs
from exposing each call-spec-selected local alias with its exact pinned schema. Neither the latest
release nor current upstream therefore lifts this blocker.

## Required Jido interface

This is a required upstream/public extension contract, **not an API available today**:

1. Accept per-request/per-activation tool descriptors as data: local string name,
   permitted description and pinned JSON input schema. Keep private execution binding
   separate from the model-visible descriptor.
2. Resolve model tool names only against the current authorized binding map. Two local
   aliases may share one static handler or remote operation but retain distinct schemas,
   grants and binding identities. No externally driven atom/module generation.
3. Dispatch through a public executor hook that accepts the resolved binding, validated
   arguments and invocation context, then returns the normal tool result to Jido's loop.
   Static Actions and runtime tools must coexist in the same run.
4. Preserve Jido iteration, streaming, timeout/cancellation and event behavior. Preserve
   Vxpipe's no-retry policy, private execution context and call/turn/invocation identity.
   A background executor returns the existing running acknowledgement; its independently
   supervised worker later uses the existing completion mailbox/continuation path.

At implementation, prefer an upstream public extension and pin the version that proves
these contracts. A fork/private patch requires an explicit maintenance decision; this
research does not authorize one or publish an upstream issue/PR. Related
[Jido AI issue 282](https://github.com/agentjido/jido_ai/issues/282) proposes lazy Action
catalog discovery, not this exact per-tool schema/executor contract; it is not evidence
that the gap is already solved or committed upstream.

## ExMCP boundary and remaining gates

ExMCP's public `ExMCP.Client` handles protocol lifecycle, discovery and invocation;
remote names and schemas remain data. `vxpipe_mcp` configures/supervises that client
and enforces Vxpipe's security and result contracts. It does not depend on Jido AI,
Jido Action or domain applications. The engine-side tool bridge owns model exposure,
grants and background submission, not the standalone protocol library.

ExMCP 1.3.0 is the evaluated release candidate, not a conformance claim. Its documented
HTTP options include `protocol_mode: :legacy_only` and
`protocol_version: "2025-11-25"`; explicitly pin and verify our approved profile rather
than inherit broader negotiation defaults. Generic retries and modern response-stream
reissue are separate policies: disabling `retry_policy` alone is not proof that an
uncertain call cannot be resubmitted. Configure and test the actual selected path;
do not change wire profiles or weaken no-resubmission to obtain a conformance pass.
Its bundled validator dependency also does not prove our JSON Schema 2020-12 requirement.

The standalone milestone retains initialization with/without sessions, bounded paginated
discovery, outgoing argument validation, production HTTPS/DNS/redirect defenses,
cumulative decoded response budgets, absolute deadlines, credential isolation and the
pinned official client-conformance matrix. Missing effective hooks remain explicit
compatibility blockers; no custom MCP parser or silent alternate client path.
Sources: [ExMCP 1.3.0](https://hex.pm/packages/ex_mcp/1.3.0),
[client source and retry options](https://hex.pm/packages/ex_mcp/1.3.0/files/lib/ex_mcp/client.ex),
[HTTP profiles](https://hex.pm/packages/ex_mcp/1.3.0/files/lib/ex_mcp/transport/http.ex).

## Alternatives and milestone consequences

- **Direct Jido MCP:** superseded. Its dynamic proxy approach creates atoms/modules from
  tenant-controlled catalog churn. Wrapping its generic call Action does not solve exact
  local names/schemas. See the [research log](../labnotes/20260908-1344-jido-ai-evaluation.md).
- **Jido Connect now:** not selected. The reviewed ExMCP-backed core replacement is an
  unpublished open migration, and its generic list/call bridge does not itself add runtime
  per-tool schemas to Jido AI. Re-evaluate a stable release if it removes meaningful work;
  its future backend choice need not affect our public call-spec contract.
  [Migration](https://github.com/agentjido/jido_connect/pull/75).
- **Generic model-visible `call_mcp(endpoint, tool, args)`:** rejected; loses exact local
  schemas and exposes selectors that belong in private authorized bindings.
- **Generated per-tenant Action modules:** rejected; deleting code does not reclaim atoms.
- **Reimplement the ReqLLM loop:** unnecessary; Jido demonstrably provides the loop. Extend
  the tool interface, not the orchestration engine. Do not force long-running work into
  request-transformer/interceptor hooks.

The Jido decision retained the then-existing milestone order. The current index has **23
milestones** after two later observability slices were added:

- The call-spec-driven slice proves Jido streaming and repeated host-tool rounds with
  finite static Actions. Until the public binding extension exists, its explicitly limited
  subset accepts a local tool key only when it equals the Action's name; unsupported aliases
  fail before startup rather than being renamed silently. This is a rollout restriction,
  not a change to the final call-spec alias contract.
- Variables/background slices reuse those finite Actions and retain their approved
  authority/lifetime contracts. They do not need remote catalog generation.
- The standalone MCP slice verifies ExMCP independently; it does not require a Jido agent
  or prove model exposure. It can run before the Jido tool-interface gap is resolved.
- The live-MCP slice owns the required public runtime-binding extension proof: exact schemas,
  two aliases of one handler, mixed static/remote tools, repeated rounds and background
  completion, with no external atom growth or private selector leakage. It remains blocked
  on that interface even after protocol conformance passes.

The original investigation itself implemented no milestone. Its isolated five-test probe is not
AgentServer/media integration, transport-security verification or an official conformance run.
