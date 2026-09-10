# ReqLLM agent runtime

Date: 2026-09-10. Status: selected for an intermediate implementation milestone.

## Decision

Build Vxpipe's model/tool-loop primitives directly on ReqLLM in a separate internal
umbrella child named `vxpipe_agent_runtime`, under the `Vxpipe.AgentRuntime` namespace.
Migrate the existing agent activation to that package before exposing live remote MCP
tools. Remove Jido AI and Jido Action only after the replacement passes the existing
behavioral and provider checks.

The package is an internal agent-inference runtime, not another room authority or a
general workflow framework. It owns conversation/model state and repeated model/tool
rounds. Call Engine remains authoritative for call semantics, and `vxpipe_mcp` remains
authoritative for remote MCP transport and protocol policy.

```text
Vxpipe.CallEngine
  |-- starts/configures --> Vxpipe.AgentRuntime --> ReqLLM --> model provider
  |-- submits workers --> platform tools / Call Variables / host tools
  `-- submits workers --> Vxpipe.MCP --> ExMCP --> remote MCP server
```

## Package boundary

`vxpipe_agent_runtime` owns:

- immutable per-activation instructions, provider configuration, conversation state,
  runtime-tool registry, and request correlation;
- model-visible tools represented as bounded data: exact local string name, permitted
  description, pinned JSON input schema, and no private endpoint or credential fields;
- a separate private binding associated with each descriptor and resolved only within
  that activation;
- ReqLLM request construction, streamed and buffered response normalization, provisional
  text events, complete tool-call collection, canonical tool-result continuation, repeated
  rounds, usage observations, deadlines, iteration limits, response limits, and cancellation;
- a supervised session boundary that keeps provider work outside GenServer
  callbacks and terminates active request workers with the session.

The package accepts a narrow submit-only executor contract. It supplies the already resolved
private binding, validated arguments, opaque request context, and invocation identity. Call
Engine starts every tool in an independently supervised worker and returns either definite
non-submission or one bounded running acknowledgement. Agent Runtime never executes an
operation inline. The acknowledgement is the invocation's only ordinary tool result; later
completion remains a separate private engine-origin turn with the same invocation ID.

ReqLLM requires a callback on its tool value, but provider generation does not execute that
callback. The projection therefore uses one package-owned static callback with no captured
binding. After ReqLLM returns a normalized tool call, the runtime resolves its separate
private registry and invokes the configured executor. A private binding or credential never
enters ReqLLM request values, diagnostics, or model-facing schemas.

The package emits normalized runtime events to an owner supplied by Call Engine. It does
not decide which events are public, start TTS, update Call Variables, write history, select
a tenant, inspect a call definition, or communicate with MCP itself.

Call Engine owns:

- participant and activation supervision, room authority, turn admission and queueing;
- trusted plan resolution, tool grants, private binding construction and authorization;
- tool-worker lifetime, blocking/non-blocking conversation admission, variables, transfers,
  interruption policy, TTS/audio delivery, client visibility, transcript rules, and archive
  publication;
- mapping neutral runtime events onto call/participant/turn identities.

`vxpipe_mcp` continues to own ExMCP client supervision, remote protocol negotiation,
transport security, discovery, schema validation, response limits, and invocation result
normalization. It has no dependency on the agent runtime. Call Engine connects these two
libraries through the private executor binding.

## Runtime contracts

An activation pins its complete tool registry. Two local aliases may resolve to one handler
or remote operation while retaining different descriptions, schemas, grants, and private
binding identities. Duplicate names, invalid schemas, unknown returned names, or arguments
that fail the pinned schema are rejected without execution. Externally supplied identifiers
remain strings; the runtime never generates modules or atoms from them.

Rejected calls for which no worker started become bounded model-only tool-error results when
the model can safely recover; they are not public failure explanations. Once accepted, worker
success, definite failure, and timeout with an unknown remote outcome arrive through the later
private completion path. Corrupt conversation state, an unmatched result, exhausted bounds,
or a failed provider request terminates the current turn without fabricating a successful tool
exchange. Neither path retries execution automatically.

Only one model request is active in a session. Call Engine decides how caller input and
private completion observations queue around it. Response content stays provisional until
the corresponding round is accepted. Successful tool submission is a commit barrier: its
assistant tool call and running result remain committed even if later generated speech is
cancelled, because cancellation cannot roll back real work. A final answer commits the
accepted assistant response.

For every submitted tool, the single correlated running acknowledgement stays in that
committed conversation and is therefore supplied with every later model request while the
invocation remains pending. This is retained context, not polling: the runtime does not append
another acknowledgement or generate periodic status messages. Completion arrives once as a
private engine-origin observation carrying the same invocation ID; it does not replace the
acknowledgement or become a second result in the old tool exchange.

Conversation history is not the authority for current liveness. Before every provider
generation, the runtime obtains a bounded payload-free pending-invocation projection through
a Call Engine context-source contract. The adapter supplies it ephemerally without appending
another message to committed history. Arguments, results, bindings, credentials, endpoints,
and raw errors are excluded.

Context compaction is future work. Any compactor must preserve pending invocation state,
including the committed acknowledgement and invocation correlation, until the matching
completion is consumed; it must not make pending work disappear or cause completion to be
delivered twice.

Text deltas can be delivered promptly to the owner, but tool calls execute only after their
complete identifiers and arguments have been assembled and validated. Mixed text/tool
responses must not double-deliver text. Tool results retain provider-required call IDs and
ordering. Provider-native built-ins remain distinguishable from Vxpipe-executed tools.

Each pinned binding defaults to blocking later caller conversation and may explicitly select
non-blocking behavior in the call definition. This policy never changes worker placement.
See the complete [tool execution model](tool-execution-model.md).

The runtime records observed model/provider/usage metadata without interpreting tenant
permissions, prices, or public visibility. Errors crossing the public package boundary are
bounded categories with safe correlation; raw prompts, tool payloads, credentials, and
provider authorization values do not appear in process inspection or telemetry.

## Why direct ReqLLM

ReqLLM already supplies the provider-specific work Vxpipe should not reproduce: model
selection, message and tool encoding, exact JSON Schema tool definitions, buffered and
streamed normalized responses, tool-call identities, canonical tool exchanges, usage
metadata, timeouts, and stream cancellation. The project-owned addition is the comparatively
small state machine that applies Vxpipe's lifecycle and tool-execution contracts across
successive requests.

Vxpipe already has a direct ReqLLM adapter and provider-neutral message/tool structures.
The intermediate milestone can move and refine proven behavior rather than start from an
empty integration.

## Alternatives

### Extend or fork Jido AI

Not selected for the forward path. A small upstream-neutral data-tool/executor extension
would preserve Jido's ReAct loop, but current released and upstream APIs do not expose the
required seam. Consuming it before release requires a maintained fork or patch, while the
remaining Vxpipe-specific lifecycle, background work, visibility, and room coordination
still stay outside Jido. The prior investigation remains in
[the superseded Jido decision](jido-tool-execution.md).

### Keep ReqLLM orchestration inside Call Engine

Rejected as the final boundary. It avoids a child application but couples provider-loop
changes to room and participant orchestration, repeats test setup, and makes reuse by an
embedded Vxpipe host harder. A small internal package gives the loop one reason to change
without pretending to be a general agent framework.

### Use Legion

Not selected for the speaking-agent runtime. Legion 0.5.0 is an Elixir agent framework from
Software Mansion built on ReqLLM, but it asks the model to generate Lua or Elixir programs
that invoke bridged module functions inside a sandbox. Its current loop uses complete
structured generation and module/source-oriented tools. That model is useful for autonomous
multi-step application work, but adds sandbox, prompt, latency, and tool-surface semantics
that do not match low-latency streamed voice conversation or data-backed per-call tools.
Legion can be reconsidered independently for future background agents.

### Execute fast tools inline

Rejected. A latency-based split creates two execution and cancellation models. Even fast
platform and Call Variables operations use the same supervised submission/completion path.

### Expose one generic model-visible dispatcher

Rejected. A `call_tool(name, arguments)` or `call_mcp(endpoint, tool, arguments)` facade
loses exact provider-side schemas and risks exposing private routing selectors. Each enabled
local tool remains a distinct model-visible descriptor backed by a private binding.

## Implications and migration

The [ReqLLM agent-runtime milestone](milestones/reqllm-agent-runtime.md) is inserted after
the standalone MCP client milestone and before live MCP tools. It first proves the package
in isolation, then migrates the existing Jido-backed activation while retaining the current
Call Engine coordinator and domain contracts where they remain cohesive. Jido dependencies
are removed only when no production or test references remain and parity is demonstrated.

Completed Jido-backed milestone evidence remains factual history. Forward milestones refer
to `Vxpipe.AgentRuntime`. The live-MCP milestone no longer waits for an upstream Jido API;
it waits for this internal runtime milestone and then supplies its already implemented,
pinned remote bindings through the executor contract.

## Verification evidence

Planning inspected the umbrella's locked ReqLLM 1.22.0 public tool, response, context,
streaming, cancellation, and existing adapter surfaces; Jido AI 2.3.0's Action-only tool
projection; and Legion 0.5.0's agent, executor, prompt, tool, sandbox, and supervision
contracts. This establishes API shape, not implementation correctness. The milestone's
deterministic, tagged-provider, umbrella, and rendered-call gates remain unchecked.

Sources: [ReqLLM](https://hexdocs.pm/req_llm),
[Legion](https://hexdocs.pm/legion), and
[Legion source](https://github.com/software-mansion-labs/legion).
