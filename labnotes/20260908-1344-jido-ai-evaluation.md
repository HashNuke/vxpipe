# Jido AI evaluation

Date: 2026-09-08

## Objective

Evaluate whether Jido AI, Jido Action, and Jido MCP can replace custom pieces that
Vxpipe planned to build directly around ReqLLM. The focus is the agent model/tool
loop and remote MCP integration, not room media or transport concerns.

No dependency or architecture change was made during this research checkpoint.

## Finding

The strongest fit is a hybrid:

1. Keep Vxpipe as the authority for calls, rooms, participants, media,
   authorization, transfers, variables, persistence policy, and client event
   projection.
2. Evaluate Jido AI's standalone ReAct runtime as the implementation of an agent's
   ordinary LLM/tool loop.
3. Represent platform-owned agent tools with Jido Action while their handlers
   still call Vxpipe-owned processes and enforce Vxpipe permissions.
4. Evaluate the released Jido MCP package as the remote MCP adapter because it
   already builds on Anubis MCP, but do not adopt it until the protocol, tenancy,
   identity, and resource-lifetime gaps below pass a focused spike.
5. Keep long-running tool work under Vxpipe supervision. A Jido action can submit
   such work and return immediately; the remote operation must not occupy the
   ordinary ReAct loop for its full duration.

Jido AI is not an alternative model-provider client to ReqLLM. It is an
orchestration layer built on ReqLLM. Adopting it would mean using ReqLLM through
Jido for agent loops instead of maintaining the whole loop directly on ReqLLM.

## Current Vxpipe boundary

The current implementation deliberately gives the engine ownership of the
voice-facing lifecycle:

- `Vxpipe.CallEngine.Provider.ModelInference` is the provider-neutral inference
  boundary.
- `Vxpipe.CallEngine.Provider.ReqLLM` translates Vxpipe messages and tool
  definitions to ReqLLM.
- `Vxpipe.CallEngine.Capability.ModelInference` owns request serialization,
  supervised inference tasks, timeouts, interruption, streamed sentence output,
  history, repeated model/tool rounds, tool events, and tool execution.
- `Vxpipe.CallEngine.Tool.Executor` checks the project-owned tool contract and
  bounds tool results.

The room and participant process trees should continue to own those voice and
call semantics. A third-party agent runtime must fit behind that boundary or
replace one coherent layer; it must not become a second authority for the room.

## What the Jido packages provide

The stable package lines reviewed were:

- Jido AI 2.3.0, which depends on Jido 2.3, Jido Action 2.3, and ReqLLM 1.x.
- Jido Action 2.3.2, which provides action metadata, schemas, validation,
  execution, timeouts, cancellation, retries, and telemetry.
- Jido MCP 1.1.1, whose released version depends on Anubis MCP 1.10.

Vxpipe currently uses ReqLLM 1.22.0. That version is within Jido AI 2.3.0's
declared ReqLLM range, but dependency resolution and behavior still need to be
verified in the umbrella.

### Standalone ReAct runtime

Jido AI explicitly presents its standalone ReAct runtime for applications that
already own their orchestration. It supplies:

- synchronous, streaming, and process-backed runs;
- model/tool iteration with configurable iteration limits;
- concurrent tool execution with deterministic result ordering;
- request handles, cancellation, continuation, and event collection;
- usage and tool lifecycle events;
- request transformation before each model call;
- thread/context projection and explicit context replacement;
- telemetry for requests, LLM calls, tools, durations, tokens, and retries.

This overlaps substantially with the inner loop in
`Vxpipe.CallEngine.Capability.ModelInference`. It does not overlap with WebRTC,
audio routing, STT, TTS, room supervision, or client protocol handling.

Jido's full AgentServer is not the first integration target. It owns an agent
process lifecycle, signal routing, command tasks, directives, queues, and state.
Nesting it inside Vxpipe's existing room and participant supervision would create
two lifecycle models. It may be worth considering later only if it cleanly
replaces the current per-agent inference process instead of wrapping it.

### Jido Action

Jido Action is a good common descriptor and execution contract for tools that an
agent may call. It can cover platform tools such as variable operations and
transfers while the actual authority stays in Vxpipe processes.

Project policy must override several library defaults:

- The reviewed ReAct defaults allow one tool retry. Vxpipe's current decision is
  no automatic retry, so `tool_max_retries` must be set to zero.
- The reviewed ReAct defaults allow tool concurrency of four. Vxpipe must choose
  concurrency explicitly according to ordering and side-effect rules.
- Action schemas are open unless configured otherwise, so security-sensitive
  platform actions need strict input schemas.
- Jido Action's plain JSON Schema compatibility form does not perform full
  runtime validation. Remote MCP inputs still require a real JSON Schema
  validator for the server-provided schema.

The sibling Callx implementation is useful local evidence: it already expresses
several small host operations as Jido Actions while retaining a custom
voice-facing LLM adapter. It also retains a custom ReqLLM loop for dynamically
discovered room tools. The newer standalone ReAct and Jido MCP packages may now
remove more of that custom loop, but the Vxpipe-specific authority boundaries
remain necessary.

## Proposed runtime boundary

```text
Vxpipe room and participant supervision
  -> Vxpipe agent-loop adapter
       -> Jido AI standalone ReAct runtime
            -> ReqLLM provider access
            -> Jido Actions
                 -> Vxpipe variable and transfer APIs
                 -> Vxpipe remote-MCP boundary
                      -> Jido MCP if its spike passes
                      -> Anubis MCP directly otherwise
```

The Vxpipe adapter would translate between Jido events and engine events. It must
remain responsible for:

- assigning room, participant, turn, and request identities;
- projecting streamed model text into text and TTS output;
- applying interruption policy;
- authorizing every platform or remote tool invocation;
- applying client tool-event visibility policy;
- associating usage and persisted events with the correct call entities;
- rejecting stale completions after an agent or room incarnation ends.

## Fit against planned custom work

| Planned concern | Jido fit | Vxpipe ownership that remains |
| --- | --- | --- |
| Repeated LLM/tool calls | Strong: standalone ReAct already implements the loop | Model profile selection, call pinning, event projection |
| Streaming model output | Strong: the runtime emits a normalized event stream | Sentence/audio pacing and interruption |
| Static platform tools | Strong: Jido Action describes and executes them | Authorization and calls to room-owned processes |
| Dynamic remote MCP tools | Promising through Jido MCP proxies | Tenant catalog, credentials, pinning, network policy |
| Tool timeout and cancellation | Useful primitives exist | Per-tool semantics and distinction between speech interruption and operation cancellation |
| Tool retry | Mechanism exists | Configure zero automatic retries by policy |
| Long-running background tools | Partial: a normal ReAct run waits for tool results | Submission, supervision, late completion, and continued conversation |
| Thread/context projection | Useful mechanics | Variable state, access rules, persistence, and prompt projection |
| Compaction | Supports replacing projected context with provenance | Trigger thresholds, summarizer, failure behavior, and archival history |
| Usage telemetry | Strong normalized events | Attribution to calls, participants, turns, and storage records |
| Agent process lifecycle | Available in AgentServer | Avoid initially because Vxpipe already owns it |
| Room/media lifecycle | No fit | Entirely Vxpipe-owned |

## Long-running tools and continued conversation

Jido's normal ReAct runner executes a batch of tool calls and waits for their
results before making the next model request. Its tool heartbeat keeps observers
informed, but does not create a second conversational model turn while the tool
is running. Its normal concurrent request policy also does not by itself provide
the planned Vxpipe behavior of continuing the conversation around a submitted
operation.

The clean integration is to distinguish two action classes:

### Completing action

The action is expected to finish within the current turn. ReAct waits for its
result and supplies that result to the next LLM iteration. Read-only lookups and
short bounded operations fit here.

### Submitted action

The Jido Action validates and authorizes the request, asks a Vxpipe-owned
supervisor to start it, and immediately returns a result such as:

```json
{
  "status": "running",
  "operation_id": "op_..."
}
```

The agent may then continue speaking and accepting turns. Completion is later
delivered to the active agent through the Vxpipe adapter, with the original call,
participant, operation, and room-incarnation identities. Vxpipe decides whether
that completion becomes model context, a client-visible event, or only a stored
event.

This preserves prior decisions:

- interrupting generated speech does not imply cancellation of an external
  operation;
- an explicit cancellation tool can ask the Vxpipe worker to cancel;
- no automatic retry is introduced;
- a late or uncertain result cannot mutate a replacement room incarnation;
- the source system remains authoritative when a timeout leaves an outcome
  unknown.

## Jido MCP assessment

The released Jido MCP package is directly relevant rather than merely a generic
action wrapper. It uses Anubis MCP, pools remote clients, discovers remote tools,
can call them directly, and can generate Jido Action proxies for use by Jido AI.
That could replace custom connection pooling, discovery-to-tool conversion, and
some invocation plumbing in the planned MCP adapter.

It is not yet safe to assume that it replaces the full Vxpipe MCP boundary.

### Gaps to prove or resolve

1. **Protocol revision:** released documentation names the 2025-03-26 and
   2025-06-18 Streamable HTTP revisions. Vxpipe currently plans to pin MCP
   2025-11-25. Exact compatibility must be demonstrated, not inferred.
2. **Endpoint identity:** the released action path converts an endpoint identifier
   to an atom, and proxy modules are dynamically generated. Tenant-supplied or
   otherwise unbounded names must never create atoms or modules indefinitely.
3. **Tenancy:** Vxpipe needs application- and tenant-configured endpoints with
   generation-pinned credentials. A global pool entry must not accidentally
   share authorization or discovery results across tenants.
4. **Per-call pinning:** a call must keep the selected endpoint generation and
   discovered tool contract even if configuration changes during the call.
5. **Network security:** URL policy, redirects, DNS changes, private-address
   blocking, TLS, credential injection, and response/decompression bounds remain
   Vxpipe deployment policy even when a library performs the transport.
6. **Validation:** MCP tool arguments must be validated against the discovered
   JSON Schema before transmission. The Jido MCP proxy uses a JSON Schema
   validator, but its supported dialect and limits must match the pinned Vxpipe
   contract.
7. **Result limits:** Vxpipe's maximum acceptable MCP response size and projection
   policy must apply before content enters agent context or persistence.
8. **Retries and deadlines:** action execution must not silently retry a
   side-effecting MCP call. Call, connect, idle, and overall deadlines need clear
   ownership.
9. **Lifecycle cleanup:** endpoint generations and proxy artifacts need bounded
   lifetimes when tenants reconfigure integrations.
10. **Upstream direction:** the current source branch has moved its transport
    integration away from Anubis while the stable release still uses Anubis.
    Vxpipe should evaluate a pinned release, not assume unreleased source behavior
    or a frictionless upgrade path.

Until these checks pass, `vxpipe_mcp` should remain a small policy-owning boundary
even if its implementation delegates most protocol mechanics to Jido MCP.

## Alternatives considered

### Continue directly on ReqLLM

This preserves complete control and has the smallest dependency change, but it
leaves Vxpipe maintaining a generic model/tool loop, event normalization, usage
collection, tool concurrency, and context projection that Jido already provides.
It remains the fallback if Jido cannot preserve voice interruption and per-call
tool semantics.

### Adopt Jido AgentServer as the whole agent participant

This offers the most Jido functionality, but initially duplicates Vxpipe's OTP
lifecycle, state, queueing, and supervision decisions. It also makes failures and
ownership harder to reason about. This is not recommended for the first
integration.

### Use standalone ReAct plus Jido Action

This uses the reusable inner-loop machinery while keeping the established Vxpipe
process boundaries. It is the recommended first experiment.

### Use Jido MCP without a Vxpipe wrapper

This is attractive mechanically but would put tenant policy, credentials,
endpoint generations, security bounds, and call pinning too close to a general
integration package. It is not recommended. The wrapper should be thin, but it
should exist.

## Focused adoption spike

The first spike should not change the room tree. Add a second implementation of
the agent-loop boundary and exercise one small vertical slice:

1. Accept one text input for an active agent.
2. Stream model output through existing Vxpipe output events.
3. Execute one static Jido Action.
4. Feed its result back to the model and complete the response.
5. Preserve request, participant, turn, and usage identities.
6. Interrupt model/TTS output without implicitly cancelling a completed or
   submitted side effect.
7. Time out a tool with automatic retries configured to zero.
8. Submit one background action, accept a second user turn while it runs, and
   safely project its later completion.

Then run a separate remote-MCP spike against a controlled server:

1. Configure the endpoint through the same application/tenant model planned for
   production.
2. Discover and pin its tools for one call.
3. Validate arguments and reject invalid input before network transmission.
4. Invoke a tool through Jido AI and preserve the original MCP response for
   storage while applying agent/client projections separately.
5. Enforce response size, deadline, credential, and network constraints.
6. Reconfigure the tenant endpoint and prove that the active call remains on its
   pinned generation.
7. Repeatedly add and retire generated catalogs and verify that atom/module usage
   is bounded.

## Acceptance criteria

Adopt Jido AI for the agent loop if the spike proves that:

- its stream and cancellation events map cleanly to existing Vxpipe behavior;
- Vxpipe remains the sole authority for room and participant lifecycle;
- action authorization and client visibility cannot be bypassed;
- retries, timeouts, and concurrency are explicit Vxpipe policy;
- submitted background actions can coexist with continuing conversation;
- usage and tool events retain the identities needed for persistence;
- replacing the current inner loop removes more custom machinery than the
  adapter introduces.

Adopt Jido MCP behind the Vxpipe MCP boundary only if the separate MCP checks pass.
Failure of the MCP spike does not block adoption of Jido AI and Jido Action for
the rest of the agent loop.

## Decision status

Recommended for a focused implementation spike, not yet selected as an
architecture dependency. No milestone ordering or durable architecture document
was changed by this research alone.

## Verification evidence

Local inspection:

- inspected the current model provider behavior, ReqLLM adapter, inference
  capability, and tool executor;
- inspected the planned agent, background-tool, MCP, variables, compaction, and
  usage milestones;
- inspected the sibling Callx Jido Action and LLM adapter usage;
- confirmed the locked ReqLLM version is 1.22.0.

Primary package and project references:

- [Jido AI package dependencies](https://hex.pm/packages/jido_ai/2.3.0/dependencies)
- [Jido AI overview](https://jido-ai.hexdocs.pm/Jido.AI.html)
- [Jido AI standalone ReAct runtime](https://hex.pm/packages/jido_ai/2.3.0/files/guides/user/standalone_react_runtime.md)
- [Jido AI ReAct configuration](https://hex.pm/packages/jido_ai/2.3.0/files/lib/jido_ai/reasoning/react/config.ex)
- [Jido AI ReAct runner](https://hex.pm/packages/jido_ai/2.3.0/files/lib/jido_ai/reasoning/react/runner.ex)
- [Jido AI request lifecycle](https://jido-ai.hexdocs.pm/request_lifecycle_and_concurrency.html)
- [Jido AI thread and context projection](https://hex.pm/packages/jido_ai/2.3.0/files/guides/developer/thread_context_projection_model.md)
- [Jido AI request transformer](https://hex.pm/packages/jido_ai/2.3.0/files/lib/jido_ai/reasoning/react/request_transformer.ex)
- [Jido Action 2.3.2](https://hex.pm/packages/jido_action/2.3.2)
- [Jido Action execution](https://jido-action.hexdocs.pm/Jido.Exec.html)
- [Jido Action schema validation](https://jido-action.hexdocs.pm/schemas-validation.html)
- [Jido MCP 1.1.1 dependencies](https://hex.pm/packages/jido_mcp/1.1.1/dependencies)
- [Jido MCP 1.1.1 README](https://hex.pm/packages/jido_mcp/1.1.1/files/README.md)
- [Jido agent runtime](https://jido.run/docs/concepts/agent-runtime)
