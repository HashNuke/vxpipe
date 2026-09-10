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
  parity for ordinary speech, externally submitted fast and slow tools, blocking and
  non-blocking admission, interruption, and later private completion.
- Atom/module churn checks will use many unique string-backed aliases and schemas.

## Documentation checkpoint

Created the durable runtime decision and the new intermediate milestone. Updated the
ordered milestone index, forward live-MCP plan, later compaction/usage wording, and the
completed Jido-backed milestone headers so historical implementation evidence is not
mistaken for the selected forward architecture. No application code, dependencies, or
runtime behavior changed in this checkpoint.

## Implementation checkpoint 1: package contracts and lifecycle

- Created the `vxpipe_agent_runtime` umbrella child with direct `req_llm` and `jsv`
  dependencies. It has no dependency on Call Engine, MCP, persistence, gateway, console,
  or Jido.
- Added separate modules for the tool descriptor, admitted request, terminal result,
  normalized event, model-provider behavior, private executor behavior, session, and OTP
  application. The split keeps provider execution, descriptor validation, data contracts,
  and lifecycle ownership independently testable.
- Added a deterministic test-only model provider under this application's own test support.
  It accepts mock model data and can return immediately or block, so later checkpoints can
  extend it with scripted streaming/tool-call outcomes without network access.
- The first focused red run failed at compile time because `Result` and the other contracts
  did not exist. After the minimal implementation, 4 focused tests passed.
- Added a lifecycle test that monitors a blocked provider request. It failed because
  `Task.Supervisor.async_nolink/2` allowed the request to outlive session shutdown. Retaining
  the supervised task's link to the trapping session fixed the ownership contract; the
  focused suite then passed with 5 tests and 0 failures.
- Tool descriptors validate bounded names, descriptions, and JSON schemas at construction.
  Their derived inspection excludes the opaque binding and compiled validator. Requests and
  results likewise omit prompt/output payloads from inspection.

Repeated model/tool rounds, argument execution, streaming, cancellation, the production
ReqLLM adapter, and Call Engine migration are not part of this checkpoint and remain pending.

Verification after formatting:

- `cd apps/vxpipe_agent_runtime && mix test`: 5 tests, 0 failures.
- Umbrella `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix credo --strict`, and `mix deps.unlock --check-unused`: passed.
- Umbrella `mix test` did not execute because the test alias could not create the PostgreSQL
  database without a password in this shell. This package does not use the database; the
  limitation remains recorded rather than treating a later command's exit status as proof.

## Execution-model correction before checkpoint 2

An initial uncommitted checkpoint-2 prototype treated fast tools as synchronous executor
results and slow tools as submitted work. Review with the user rejected that split before it
was committed. The prototype was removed and the checkpoint-1 application suite remained
green with 5 tests and 0 failures.

The selected target now submits every platform, Call Variables, host, and MCP tool to a
separate bounded worker owned by the active agent's Call Engine subtree. A tool binding's
conversation mode is a separate concern: omission defaults to `blocking`, while
`conversation_mode: "non_blocking"` explicitly allows unrelated caller/model turns during
execution. Blocking never authorizes inline execution.

Every accepted submission produces one correlated running tool result. That committed
exchange survives later speech/model cancellation because real work has started. Completion
arrives once as a private engine-origin observation with the same invocation ID. Call Engine
owns authoritative invocation state and supplies a bounded payload-free pending projection
before every provider generation; this is ephemeral model context, not repeated polling or
another committed tool result.

The plan also fixes admission sequencing: the current post-submission acknowledgement round
may finish, a blocking invocation then prevents later caller turns from entering the model,
and deterministic hold output is used until its terminal observation has been consumed.
Non-blocking invocations retain the approved unrelated-conversation behavior. See
`docs/tool-execution-model.md` for states, races, cancellation, partial submission, multiple
calls, transfer/shutdown, ownership, and migration checks.

## Implementation checkpoint 1b: submit-only and pending-context contracts

Reopened the provisional executor contract before beginning the loop. The focused red suite
reported 11 tests with 8 expected failures: the old `execute/4` callback remained, pending
invocation/context-source modules did not exist, and Session rejected the new source options.
The replacement behavior exposes only `submit/4`, whose successful result confirms that the
host started independent work; it cannot return an inline business result.

Added a payload-free `PendingInvocation` value and `PendingContextSource.snapshot/3` host
boundary. `PendingContext` invokes the source outside the Session GenServer, passes the source
a timeout, enforces that timeout itself, and validates a bounded unique list before provider
generation. Its projection cannot carry arguments, results, bindings, endpoints, credentials,
or arbitrary maps. Source errors and malformed results are collapsed to safe runtime errors,
and the provider is not called when authoritative pending state is unavailable.

The first green implementation exposed that merely passing a timeout did not stop a stalled
source callback. A focused regression test reported 3 tests with 1 expected failure; moving the
source call into a linked temporary task with timeout shutdown made it green. Session shutdown
also terminates this nested source work through the request-worker link.

Verification:

- `cd apps/vxpipe_agent_runtime && mix test`: 12 tests, 0 failures.
- Umbrella `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix credo --strict`, and `mix deps.unlock --check-unused`: pass.
- Umbrella `mix test`: stopped before test execution because PostgreSQL authentication needs a
  password that is absent from this shell. No database is used by this package; the focused
  owning-app suite is the available runtime evidence.
- Repeated model/tool rounds, ReqLLM encoding, invocation workers, blocking admission, and
  Call Engine migration remain deliberately outside this checkpoint.

## Implementation checkpoint 2a: normalized tool-response boundary

Started checkpoint 2 with the data boundary needed by both the deterministic driver and the
future ReqLLM adapter. The red contract/registry run failed at compilation because the new
model-only tool projection did not exist. Added four single-purpose modules:

- `ToolCall` accepts only bounded complete IDs, names, argument maps, and provider metadata;
  inspection omits the arguments and metadata.
- `ModelResponse` represents final text or mixed text plus complete calls and rejects empty,
  malformed, oversized, or excessive responses; inspection omits generated text.
- `ModelTool` contains only name, permitted description, and pinned input schema.
- `ToolRegistry` pins exact names, rejects duplicates, keeps bindings private, preserves model
  projection order, and validates returned arguments with the descriptor's compiled schema.

This slice does not call the executor or run another model round yet. It deliberately lands the
validated/private boundary separately so the loop does not become responsible for schema
compilation, provider projection, or registry privacy.

Verification:

- Focused contract/registry tests: 8 tests, 0 failures.
- Complete `vxpipe_agent_runtime` suite: 15 tests, 0 failures.
- Umbrella format, warnings-as-errors, strict Credo, and unused-lock checks: pass.
- Umbrella `mix test`: again stopped before execution because the shell has no PostgreSQL
  password; no new code in this slice depends on PostgreSQL.

## Implementation checkpoint 2b: one submitted tool round

The desired Session test first reported 5 tests with 4 failures: the old provider contract
returned plain strings, provider requests did not contain conversation messages, and Session
rejected tool/loop options. Replaced that transitional path with normalized `Message` and
`ModelRequest` values, committed `Conversation` state, and a `RequestRunner` dedicated to
model/tool sequencing.

The executor callback still never runs business logic. Its accepted response now includes the
binding's already-resolved `blocking` or `non_blocking` conversation mode. For one valid call,
the request worker resolves the exact private descriptor, validates its arguments, calls
`submit/4`, and commits the assistant tool-call message plus
`{"status":"running","invocation_id":...}` through a synchronous Session acknowledgement.
Only after that barrier does it fetch current pending state and run the next provider request.
A blocking acceptance supplies no tools in that acknowledgement request. Mixed text from the
tool-call response and the acknowledgement response is returned once and in order.

Moved option/adapter validation and runner projection into `SessionConfiguration`, leaving
Session focused on request admission, task lifecycle, committed conversation, and commit
acknowledgements. `RequestRunner` owns sequencing; value, registry, context-source, and executor
modules retain their narrower boundaries.

A model response with several tool calls was still able to accept work without the required
partial-commit implementation. A new regression test failed while that request waited for a
second round. Until the ordered batch checkpoint lands, multiple calls now fail explicitly with
`multiple_tool_calls_unsupported` before invoking the executor. This is a temporary fail-closed
boundary, not the final milestone behavior.

Verification:

- Complete `vxpipe_agent_runtime` suite: 17 tests, 0 failures.
- Umbrella format, warnings-as-errors, strict Credo, and unused-lock checks: pass.
- Umbrella `mix test`: stopped before test execution because PostgreSQL authentication needs a
  password absent from this shell.
- Streaming, ordered multiple calls/partial rejection, cancellation, provider failure after
  acceptance, and production ReqLLM encoding remain pending.

## Implementation checkpoint 2c: ordered submission batches

Replaced the temporary fail-closed multiple-call guard. The red batch test expected two
provider-ordered submissions but received the earlier `multiple_tool_calls_unsupported`
failure before either was attempted.

The runner now performs two phases. It first rejects duplicate provider call IDs and resolves
every exact local name plus JSON Schema before any work begins. It then invokes only the
submit-only host callback in provider order and builds one matched result per call. An accepted
call receives the correlated `running` result. A definite host rejection receives a bounded
`{"status":"rejected","reason":...}` result. Already accepted workers remain represented when
a later submission rejects; no rollback or retry occurs.

The batch's conversation gate is the strict union of accepted modes: one blocking acceptance
withholds all tools from the next acknowledgement round, while an explicitly non-blocking
acceptance keeps the authorized tool projection. Rejected calls do not create pending state or
change the gate. Tests cover a mixed accepted/rejected batch and an explicitly non-blocking
call.

As a hygiene refactor after green, moved tool-loop scenarios into `ToolRoundTest`; Session tests
now cover only session lifecycle and pending-context integration. No production behavior moved.

Verification:

- Complete `vxpipe_agent_runtime` suite: 18 tests, 0 failures.
- Umbrella format, warnings-as-errors, strict Credo, and unused-lock checks: pass.
- Umbrella `mix test`: stopped before test execution because the shell still lacks the local
  PostgreSQL password.
- Provider failure after acceptance, conversation recovery, cancellation, stream events,
  explicit per-round limits, and production ReqLLM mapping remain pending.

## Implementation checkpoint 2d: provider-failure recovery

Added a focused recovery scenario around the commit barrier. A non-blocking tool is accepted
and its assistant-call/running-result exchange commits. The acknowledgement provider then
returns a deliberately private raw failure. The red test showed that raw atom escaping through
the public `Result`.

`RequestRunner` now owns provider-boundary normalization: valid normalized responses pass;
provider errors, exceptions, and exits become `provider_unavailable`; malformed success values
become `invalid_provider_response`. It does not expose the dependency's reason or retry.

After that failed request returns, a new request in the same Session receives the committed
original user message, assistant tool call, and single running result before its new user
message. It also receives the fresh authoritative pending projection. The test confirms that
the invocation is neither lost nor submitted again.

Verification:

- Focused recovery test: 1 test, 0 failures.
- Complete `vxpipe_agent_runtime` suite: 19 tests, 0 failures.
- Umbrella format, warnings-as-errors, strict Credo, and unused-lock checks: pass.
- Umbrella `mix test`: stopped before test execution because the local PostgreSQL password is
  absent from this shell.
- Cooperative request cancellation, remaining bounds, streaming, ReqLLM projection, and Call
  Engine adoption remain pending.
