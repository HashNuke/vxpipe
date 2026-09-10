# ReqLLM agent runtime

## Objective

Plan an intermediate milestone that replaces the forward dependency on a missing
Jido AI runtime-tool extension with a small internal package built directly on
ReqLLM. The package must preserve the existing voice-call behavior and expose exact,
data-backed runtime tools without taking ownership of rooms, MCP transport, storage,
or client protocols.

## Investigation

- The umbrella currently locks ReqLLM 1.22.0 and already contains a direct adapter
  that projects Vxpipe messages and data-backed tool definitions into ReqLLM. The
  existing implementation therefore supplies reusable provider-boundary work; this
  is not a new provider integration.
- ReqLLM accepts tools with string names, descriptions, raw JSON Schema maps, and a
  callback. It normalizes buffered and streamed tool calls, exposes canonical tool
  exchange helpers, retains usage/provider metadata, and supplies explicit streaming
  cancellation. It deliberately does not own repeated model/tool rounds.
- Jido AI 2.3.0 owns repeated rounds but only projects Action modules. Its public
  request transformer and interceptor surfaces cannot preserve arbitrary local aliases,
  pinned runtime schemas, and private data bindings. Maintaining an upstream-neutral
  extension is possible, but still creates a fork/patch dependency until released.
- Legion 0.5.0 from Software Mansion was reviewed as the other candidate. Legion asks
  the model to generate Lua or Elixir code, evaluates it in a sandbox, and bridges
  module functions into that code. Its current executor uses complete structured
  generation rather than streaming conversational output, and its tool contract is a
  list of modules described to the generated program. That is a different execution
  and latency model from Vxpipe's real-time voice loop. It may be useful for future
  autonomous background work but is not selected for the speaking-agent runtime.

## Decision

- Add `apps/vxpipe_agent_runtime`, exposed under `Vxpipe.AgentRuntime`.
- The child depends directly on ReqLLM. It has no dependency on Call Engine,
  `vxpipe_mcp`, ExMCP, Calls, Persistence, Gateway, or Console.
- It owns one supervised agent session's conversation state, exact runtime-tool
  projection, repeated model/tool rounds, streaming/cancellation, bounded request
  execution, provider-normalized results, and neutral lifecycle events.
- Call Engine supplies immutable activation configuration, a private tool executor,
  and an event destination. It retains authorization, participant/room lifecycle,
  background invocation ownership, interruption policy, variables, transfer policy,
  TTS/client projection, and archive events.
- `vxpipe_mcp` remains the ExMCP-backed protocol library. A private Call Engine binding
  passed to the executor connects an agent-runtime tool request to the pinned MCP
  operation; endpoint and credentials never enter the model-visible descriptor.
- Keep the completed Jido-backed milestones as factual history. The new milestone must
  demonstrate behavioral parity and remove Jido dependencies only after the replacement
  is green. Live MCP then depends on the new runtime instead of a Jido extension.

## Planned verification

- Deterministic model-driver tests will prove repeated rounds, mixed text/tool output,
  exact aliases and schemas, ordered results, cancellation, limits, and private binding
  isolation without testing ReqLLM's own provider codecs.
- A focused ReqLLM boundary test will prove the exact data projected to ReqLLM and the
  canonical response/tool-exchange mapping.
- A tagged provider lane will prove streamed text and a multi-round tool continuation
  through the production adapter.
- Existing Call Engine behavior tests and the rendered sample call will prove migration
  parity for ordinary speech, a synchronous platform tool, a submitted background tool,
  interruption, and later private completion.
- Atom/module churn checks will use many unique string-backed aliases and schemas.

## Documentation checkpoint

Created the durable runtime decision and the new intermediate milestone. Updated the
ordered milestone index, forward live-MCP plan, later compaction/usage wording, and the
completed Jido-backed milestone headers so historical implementation evidence is not
mistaken for the selected forward architecture. No application code, dependencies, or
runtime behavior changed in this checkpoint.
