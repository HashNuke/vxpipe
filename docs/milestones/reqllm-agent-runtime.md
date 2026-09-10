# ReqLLM agent runtime

Status: not implemented. Specification planned on 2026-09-10; implementation review and
evidence remain pending.
Prerequisites: [Definition-driven call](definition-driven-call.md),
[Call Variables](call-variables-and-tool-visibility.md), and
[background-tool conversation](background-tool-conversation.md).
Sources: [runtime decision](../reqllm-agent-runtime.md),
[prior Jido investigation](../jido-tool-execution.md), and
[ReqLLM documentation](https://hexdocs.pm/req_llm).

## Runnable outcome

The existing sample call runs through the separate `vxpipe_agent_runtime` internal package
instead of Jido. It streams an ordinary answer, invokes an exact data-backed platform-tool
alias, submits a background tool, remains conversational while that tool runs, and consumes
its later private completion. The same package can project a second alias sharing the same
executor while preserving a different pinned schema. No Jido process or dependency is used.

## Package and dependency boundary

- Add the umbrella child `apps/vxpipe_agent_runtime`, exposed as
  `Vxpipe.AgentRuntime`. It depends directly on ReqLLM and only on small supporting
  libraries it actually uses. It does not depend on Call Engine, Calls, Persistence,
  Gateway, Console, `vxpipe_mcp`, ExMCP, Jido AI, or Jido Action.
- Move provider conversation/tool-loop primitives out of Call Engine where they are not
  call-domain concerns. Call Engine depends on the new package and implements its tool
  executor/event-owner contracts. `vxpipe_mcp` remains an independent ExMCP protocol
  package; this milestone uses controlled bindings and performs no remote MCP networking.
- Keep one top-level module per file and split descriptor validation, conversation state,
  ReqLLM projection, response collection, tool exchange, request execution, and session
  lifecycle into cohesive modules. Do not replace the current Jido concentration with one
  large runtime module.

## Runtime specification

- Represent each enabled tool as an immutable descriptor containing its exact bounded local
  string name, permitted description, pinned JSON input schema, and an opaque private binding.
  Keep the binding outside the ReqLLM tool value and every model-visible/event/inspection
  projection. Reject duplicate names, invalid schemas, unknown returned names, and invalid
  arguments before calling the executor. Never create an atom or module from external data.
  Project a package-owned static callback into ReqLLM tools and keep every actual private
  binding in the runtime registry; provider generation must never receive or execute it.
- Start one runtime session through the participant activation's owning supervisor. Its
  supervised request workers perform provider and executor work outside GenServer callbacks.
  Terminating the session subtree terminates active request workers and closes an active
  ReqLLM stream. Define explicit names for package-owned supervisors/registries and avoid
  cyclic synchronous calls.
- Accept immutable instructions, selected ReqLLM model/options, tool registry, request and
  response limits, an executor implementation, and an event destination at activation
  startup. Runtime status and `Inspect` output retain no prompt, message, tool argument,
  result, private binding, credential, or raw provider error.
- Admit one active model request per session. Call Engine continues to serialize caller
  input and engine-origin completion turns and owns the bounded pending queue. The runtime
  returns an explicit busy/closed result rather than queueing another domain turn silently.
- Build each ReqLLM request from the committed conversation plus one staged input. Stream
  provisional text events promptly, assemble the canonical response once, and classify it
  as final output or complete tool calls. Commit conversation state only for the accepted
  round. Cancellation discards staged input/output and closes provider work without deleting
  earlier committed exchanges.
- On tool calls, resolve names only in the request's pinned registry, validate complete
  arguments, call the engine-owned executor with opaque correlation context, and append the
  assistant tool-call message plus matched results through canonical ReqLLM conversation
  semantics. Preserve call IDs, model order, provider metadata, and error results, then run
  the next model round until final output or the bounded iteration/deadline limit. A rejected
  or failed tool becomes a bounded model-only error result when recovery is safe; it does not
  expose an internal failure reason to the caller. Corrupt exchanges and exhausted bounds fail
  the current turn instead of inventing a result.
- A submitted background executor returns the existing bounded running acknowledgement
  immediately. Its work and completion mailbox remain Call Engine-owned and outlive later
  speech cancellation as already specified. A later private completion enters as a new
  engine-origin request; it is not a second result attached to an old tool exchange and does
  not create public caller speech.
- Normalize runtime events for request start, text delta, complete tool request, executor
  outcome, usage, terminal answer, cancellation, and safe failure. Events carry opaque
  correlation supplied by Call Engine, but the runtime does not assign call/participant/turn
  authority, client visibility, transcript policy, TTS, storage, or cost interpretation.
- Apply an absolute request deadline, provider timeouts, maximum model rounds, maximum
  tool calls per round, bounded tool argument/result bytes, bounded text/response bytes,
  and bounded event handoff. Failure or cancellation cannot trigger an automatic model,
  tool, or provider retry. Provider-native routing remains a later configured concern.

## Migration checkpoints

1. [Complete 2026-09-10] Add the child application and red-test its public descriptor, request, result, event,
   executor, and session contracts with a deterministic model driver.
2. Implement the smallest repeated model/tool state machine: final response, one tool
   continuation, multiple calls with ordered results, mixed text/tool output, bounded
   failure, and cancellation.
3. Add the ReqLLM adapter by moving/refining the existing Call Engine projection. Prove raw
   JSON Schema aliases, canonical exchanges, streaming collection, usage, and cleanup at
   that boundary. Keep live-provider checks tagged.
4. Replace the Jido AgentServer child in an activation with `Vxpipe.AgentRuntime` and adapt
   the existing coordinator/dispatcher without moving room policy into the package. Preserve
   current background completion and interruption behavior.
5. Run parity and churn checks, inspect the rendered sample, then remove unused Jido AI,
   Jido Action, Jido, and related lock entries. Do not remove them earlier or retain an
   unused fallback loop after migration.

## Implementation checklist

- [x] Red-test and add the standalone package contracts and supervised lifecycle.
- [ ] Implement deterministic repeated rounds, exact runtime-tool resolution, canonical
  tool exchanges, streaming events, cancellation, and all declared bounds.
- [ ] Move/refine the existing ReqLLM projection behind the new package and add focused plus
  tagged-provider interoperability evidence.
- [ ] Migrate the agent activation/coordinator and all platform/background tools without
  changing room authority, client visibility, or archive contracts.
- [ ] Remove Jido dependencies and obsolete adapters only after behavioral parity, full
  umbrella verification, and rendered sample verification are green.
- [ ] Update architecture, package API documentation, milestone evidence, and the labnote
  in each coherent checkpoint.

## Acceptance and failure checks

- [ ] A deterministic run streams text, requests a tool, receives its result, performs a
  second model round, and answers once. Mixed text/tool output is neither dropped nor
  delivered twice.
- [ ] Two local aliases share one executor implementation while retaining distinct exact
  descriptions, schemas, binding identities, and attribution. Repeated unique aliases and
  schemas do not cause proportional atom/module growth.
- [ ] Unknown/duplicate tools, malformed calls, invalid arguments, excessive calls/rounds,
  oversized input/result/text, executor failure, and provider failure produce the specified
  bounded model-error or terminal outcome with no unauthorized execution, public internal
  explanation, or retry.
- [ ] Multiple tool calls are executed and returned in provider-required model order. A missing
  or duplicate result cannot advance the model loop.
- [ ] Cancelling an active streamed request closes it, suppresses later deltas, discards its
  uncommitted exchange, and leaves the session usable. It does not terminate an already
  accepted Call Engine background invocation.
- [ ] Killing the runtime session terminates request workers without ending the room. Killing
  the participant activation cleans up the complete runtime subtree and stale results cannot
  attach to a replacement activation.
- [ ] A background acknowledgement, unrelated caller turn, and later engine-origin completion
  reproduce the completed milestone's ordering and visibility behavior with no fake public
  user message or competing TTS stream.
- [ ] Process inspection, telemetry, errors, and public events contain no prompts, raw tool
  arguments/results, private bindings, credentials, or provider authorization values.
- [ ] A tagged supported-provider run accepts the exact tool schema, streams conversational
  text, performs a real multi-round tool continuation, reports observed usage, and cleans up
  after cancellation without relying on dependency-private APIs.

## Manual verification

1. Run the sample call with full debug tool visibility and confirm ordinary streamed text,
   one synchronous platform tool, and one submitted background tool.
2. Speak/type another turn while the background operation runs, interrupt only active speech,
   then confirm its private completion is consumed once.
3. Inspect diagnostics and call history for request/tool/usage correlation and confirm public
   visibility settings still hide tool events by default.
4. Repeat a controlled provider failure and mid-stream cancellation, then start another turn
   in the same session. Inspect desktop and mobile sample states in Chromium.

## Scope boundaries

No remote MCP network call, Legion integration, call-definition change, transfer, media
mixing, recording, storage migration, context compaction, Vxpipe-managed provider fallback,
automatic tool retry, durable runtime session, or new client protocol. This milestone builds
and adopts the model/tool-loop substrate; the next milestone connects its private executor
contract to the already implemented MCP bindings.

## Completion and evidence

- [ ] Demonstrate the runnable outcome and every acceptance/failure check above.
- [ ] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [ ] Update this milestone, the index checkbox, architecture/API docs, and implementation
  labnote with actual test/browser/provider evidence in the implementation commits.

Implementation evidence:

- Checkpoint 1 adds the standalone `vxpipe_agent_runtime` child with no Call Engine,
  MCP, persistence, gateway, console, or Jido dependency. It defines bounded request,
  result, safe event, model-provider, private executor, and tool-descriptor contracts.
- A deterministic test-only model provider proves provider work runs outside the session
  GenServer. A monitored blocking provider proves a supervised session shutdown terminates
  its active request worker. Focused application suite: 5 tests, 0 failures.
- The initial focused run failed because the package contracts did not exist. The lifecycle
  test then failed while the request was unlinked; changing the supervised task to retain
  session ownership made it green. Repeated rounds and production ReqLLM projection remain
  intentionally pending in checkpoints 2 and 3.
- `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`,
  and `mix deps.unlock --check-unused` pass at the umbrella root. The umbrella `mix test`
  alias could not create `vxpipe_test` because this shell has no PostgreSQL password; it
  stopped before executing tests. No database is used by this package checkpoint.

## Specification review

Locally reviewed during planning for dependency direction, SRP, supervision ownership,
tool/privacy authority, failure bounds, migration safety, and a runnable vertical outcome.
No independent review or implementation evidence is claimed.
