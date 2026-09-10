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

The selected target now hands every platform/built-in, Call Variables, host, and MCP tool
invocation to a separate bounded worker owned by the active agent's Call Engine subtree.
Neither the Agent Runtime request worker nor an agent/runtime GenServer executes it inline.
For authored platform/built-in, host, and MCP bindings, the tool-specific
`conversation_mode` comes from the call-definition `tools` entry and is `blocking` or
`non_blocking`. Omission defaults to `blocking`; `non_blocking` explicitly allows unrelated
caller/model turns during execution. The mode changes later-turn admission only, never
execution placement.

Every accepted submission produces one correlated running tool result. That committed
exchange survives later speech/model cancellation because real work has started. Completion
arrives once as a private engine-origin observation with the same invocation ID. Call Engine
owns authoritative invocation state and supplies a bounded payload-free pending projection
before every provider generation in either mode; every appropriate later LLM request therefore
sees current pending state. This is ephemeral model context, not repeated polling or another
committed tool result.

The plan also fixes admission sequencing: the current post-submission acknowledgement round
may finish, a blocking invocation then prevents later caller turns from entering the model,
and deterministic hold output is used until its terminal observation has been consumed.
Non-blocking invocations retain the approved unrelated-conversation behavior. See
`docs/tool-execution-model.md` for states, races, cancellation, partial submission, multiple
calls, transfer/shutdown, ownership, and migration checks.

This clarification changes documentation precision only. The current dated compiler already
supports the choice for authored host and MCP entries. Permission-derived Call Variables tools
remain default-blocking, and the approved authored platform-tool shape is not claimed as
implemented by this documentation checkpoint.

## Implementation checkpoint 4a: call-definition conversation policy

Started the Call Engine migration at its stable configuration boundary. Schema
`20260910.01` adds `conversation_mode` to each participant-local host or MCP tool binding.
Omission compiles to `:blocking`; only the exact external value `"non_blocking"` compiles to
`:non_blocking`, and unsupported values fail at the precise tool path. Both values describe
later caller-turn admission only. They do not select an execution path: every operation will
be handed to the same independently supervised Call Engine worker boundary.

Focused compiler coverage exercises the blocking default, explicit non-blocking host tool,
explicit non-blocking remote MCP binding, and invalid value. The resolved plan carries the
policy privately for runtime admission; model-visible tool descriptions and client tool-event
visibility remain separate projections.

Red verification failed at compilation because neither typed struct exposed
`conversation_mode`. After implementation, the focused compiler suite passed 12 tests. The
complete Call Engine suite passed 216 tests with 2 integration exclusions. Its first run had
one pre-existing 100 ms MCP-owner shutdown assertion miss; that test passed immediately in
isolation and the unchanged complete suite then passed.

Umbrella format, warnings-as-errors compilation, Credo strict, and unused-lock checks passed.
Umbrella `mix test` again stopped before tests because local PostgreSQL SCRAM authentication
requires a password unavailable in this shell; no credential source was inspected.

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

## Implementation checkpoint 2e: cancellation commit barrier

Added two cancellation scenarios first; both failed because Session exposed no cancellation
operation. The first requires cancellation to terminate provisional provider work, return a
cancelled result to the admitted request, discard that uncommitted user turn, and leave the
same Session usable.

The second targets the submission race. The test executor announces entry and deliberately
blocks before returning acceptance. Session cancellation must remain pending during that
interval. `RequestRunner` now enters a Session-owned submission critical section only after all
call IDs, names, and arguments validate and before invoking the host. When the host finishes,
the runner builds the complete ordered results and asks Session to commit them. If cancellation
is waiting, Session stores that conversation first and then terminates the request task without
starting the acknowledgement provider round.

This is not inline tool execution: the guarded operation is only the host's submit/admission
callback. Accepted business work is already in a separate host-owned worker. Cancellation kills
the Agent Runtime request/provider work, not that worker. A later request in the test sees the
single committed running exchange, proving the race cannot create accepted-but-forgotten work.

Added `Result.cancelled/1`, a payload-safe `request_cancelled` event, and an idle cancellation
error. Cancellation callers are replied only after the barrier is safe. Session shutdown still
owns hard teardown of its request subtree separately.

Verification:

- Focused cancellation suite: 2 tests, 0 failures after the expected 2-test red run.
- Complete `vxpipe_agent_runtime` suite: 21 tests, 0 failures.
- Umbrella format, warnings-as-errors, strict Credo, and unused-lock checks: pass.
- Umbrella `mix test`: stopped before test execution because the shell has no local PostgreSQL
  password.
- Remaining request/response/round deadlines and sizes, streaming, production ReqLLM mapping,
  Call Engine worker/admission migration, and private completion consumption remain pending.

## Implementation checkpoint 2f: request loop bounds

Added focused tests before implementation for two runtime-owned limits. A model response with
two valid calls must fail before any executor submission when the Session permits one call per
round. Assistant text accumulated across model/tool rounds must remain within a configured byte
limit; an oversized mixed response must fail before tool submission, while an oversized final
response must fail without committing its staged exchange.

The initial three-test run failed at Session startup because
`maximum_tool_calls_per_round` and `maximum_output_bytes` were not accepted configuration. The
Session configuration now validates positive values and projects them to `RequestRunner`.
`RequestRunner` checks batch size and accumulated output before entering the submission critical
section. The existing hard `ModelResponse` and `ToolCall` ceilings remain the absolute normalized
value bounds; these new settings constrain an individual Session/request further.

Verification:

- Focused bounds suite: 3 tests, 0 failures after the expected 3-test red run.
- Complete `vxpipe_agent_runtime` suite: 24 tests, 0 failures.
- Umbrella format, warnings-as-errors, strict Credo, and unused-lock checks: pass.
- Umbrella `mix test`: stopped before test execution because the shell has no local PostgreSQL
  password.
- Request deadlines, bounded submit callback failure, streaming, production ReqLLM mapping,
  Call Engine adoption, and private completion consumption remain pending.

## Implementation checkpoint 2g: Session request deadline

Added deadline tests before implementation. The first blocks provider work and requires the
Session to terminate that process, return a bounded `request_timeout`, discard staged input, and
become idle. The second blocks the executor's submit/admission callback after the submission
barrier has begun. It requires deadline expiry to remain pending until release, commit the one
running exchange, terminate only the request task, and expose the committed exchange to the next
request.

Both tests initially failed because `request_timeout_ms` was rejected as invalid Session
configuration. Session now schedules a token-correlated timer for each admitted request and
cancels it during every terminal cleanup path. An expiry outside submission terminates the
request task immediately. An expiry inside submission records `request_timeout`; the existing
commit handler stores the complete exchange before applying that terminal outcome. External
cancellation and deadline expiry use the same commit-safety mechanism while retaining distinct
public results and events.

The public `Session.request/4` call now defaults to `:infinity` because the Session owns the
30-second default deadline. This prevents an unrelated five-second caller timeout from abandoning
a still-running model request. A caller can still provide an explicit call timeout, but the normal
host path should configure the runtime deadline instead.

Verification:

- Focused deadline suite: 2 tests, 0 failures after the expected 2-test red run.
- Complete `vxpipe_agent_runtime` suite: 26 tests, 0 failures.
- Umbrella format, warnings-as-errors, strict Credo, and unused-lock checks: pass.
- Umbrella `mix test`: stopped before test execution because the shell has no local PostgreSQL
  password.
- The submit/admission callback still needs its own bounded host contract. Streaming, production
  ReqLLM mapping, Call Engine adoption, and private completion consumption remain pending.

## Implementation checkpoint 2h: private engine continuation

Added two tests before implementation for the completion half of an asynchronous invocation.
The first admits a framed tool-completion observation, requires the provider request to carry an
ordinary `user` role with retained engine provenance, commits the answer, and proves the next
caller request sees that history with caller and engine inputs still distinguishable. The second
forces a provider failure and requires the completion observation to be absent from the next
request, preserving the host's ability to retain and retry its delivery lease.

The red run failed twice because Session had no continuation API. Added `Session.continue/4` and
an `origin` field constrained to `caller` or `engine` on normalized requests/user messages. Both
paths share the same single-request admission, deadline, loop, cancellation, and commit behavior;
the distinction is provenance, not a second provider loop. Provider projection will map both to
the compatible user wire role in the ReqLLM adapter checkpoint.

The runtime accepts already framed private content rather than interpreting Call Engine tool
outcomes. Call Engine remains authoritative for invocation IDs, result-size validation, untrusted
payload framing, completion queueing, and lease acknowledgement. The future adapter must
acknowledge that lease only after `Session.continue/4` completes successfully.

Verification:

- Focused continuation suite: 2 tests, 0 failures after the expected 2-test red run.
- Complete `vxpipe_agent_runtime` suite: 28 tests, 0 failures.
- Umbrella format, warnings-as-errors, strict Credo, and unused-lock checks: pass.
- Umbrella `mix test`: stopped before test execution because the shell has no local PostgreSQL
  password.
- Submit admission reconciliation, streaming, production ReqLLM mapping, and Call Engine lease
  integration remain pending.

## Implementation checkpoint 2i: bounded provider-neutral streaming

Added a deterministic streaming provider and four tests before implementation. They require
ordered provisional delta delivery followed by one canonical terminal response, no delta after
request cancellation, rejection before forwarding a delta that exceeds the remaining output-byte
budget, and rejection before forwarding beyond the configured per-round event count. The first
run failed all four tests because RequestRunner selected buffered generation and Session rejected
the new event-count setting.

Added optional `ModelProvider.stream/3` without importing ReqLLM values into the loop contract.
The callback receives a runtime emitter and must return the same normalized `ModelResponse` used by
buffered providers. `StreamBudget` owns mutable byte/event counters through an isolated atomics
reference, normalizes malformed callbacks/handoff failures, and prevents the offending delta from
being emitted. It is recreated for each model round using the request's remaining output budget.

Session supplies a token-correlated delta callback with a configurable bounded acknowledgement.
It forwards active deltas as `text_delta` events and ignores stale messages after cancellation or
request replacement. These events carry the required output text but their `Inspect` projection
shows only kind and correlation. Deltas never update Conversation; `RequestRunner` still validates
and commits only the final normalized response.

Verification:

- Focused streaming suite: 4 tests, 0 failures after the expected 4-test red run.
- Complete `vxpipe_agent_runtime` suite: 32 tests, 0 failures.
- Umbrella format, warnings-as-errors, strict Credo, and unused-lock checks: pass.
- Umbrella `mix test`: stopped before test execution because the shell has no local PostgreSQL
  password.
- Production ReqLLM stream creation/materialization, usage projection, transport cleanup,
  submit-admission reconciliation, and Call Engine integration remain pending.

## Implementation checkpoint 3a: production ReqLLM boundary

Started with four deterministic adapter tests. They require configuration to resolve a real
ReqLLM model without exposing or accepting API-key overrides; projection of normalized messages,
tool schemas, tool-call continuation metadata, engine-origin input, and pending invocation state;
normalization of a mixed ReqLLM response with usage and redacted call metadata; and materializing a
ReqLLM `StreamResponse` while emitting ordered text and invoking its cancellation/close handle.
The initial run failed at compile time because `ModelResponse` did not retain usage or provider
metadata.

Extended `ModelResponse` with separately bounded usage and provider-metadata maps, both excluded
from inspection. Added `Provider.ReqLLM.Config`, `RequestProjection`, and `ResponseNormalizer` so
credential validation, wire projection, and dependency output classification have separate
reasons to change. The top-level provider owns only buffered/stream calls, normalization dispatch,
and best-effort stream closure. The deterministic adapter suite then passed.

Added a separate runtime usage-event test before implementing event delivery. It failed because a
valid normalized response completed without publishing its metadata. Generalized the Session's
token-correlated stream event handshake into a bounded request-event handoff and added
`model_usage`. `RequestRunner` emits one observation for every provider round with non-empty usage
or safe call metadata before processing its text/tool response. Event inspection excludes the
payload. ReqLLM's `Response.call_metadata/1` redaction was verified against an authorization value.

Pending invocation context is rendered from the already validated payload-free values and added
only to the projected leading system message. Engine-origin and caller-origin messages both map to
ReqLLM user messages, matching the provider compatibility already observed in the existing Call
Engine implementation. ReqLLM tools contain only name, description, schema, and a callback that
returns `runtime_owned_tool`; execution bindings remain exclusively in Agent Runtime's registry.

Verification:

- Focused ReqLLM adapter plus usage-event tests: 5 tests, 0 failures after the expected compile
  failure and 1-test event red run.
- Complete `vxpipe_agent_runtime` suite: 37 tests, 0 failures.
- Umbrella format, warnings-as-errors, strict Credo, and unused-lock checks: pass.
- Umbrella `mix test`: stopped before test execution because the shell has no local PostgreSQL
  password.
- No network/provider interoperability is claimed. Tagged provider validation, Call Engine
  selection, submit-admission reconciliation, and end-to-end sample verification remain pending.

## Implementation checkpoint 3b: tagged Gemini interoperability

The shell exposed `GEMINI_API_KEY`; only presence was checked, never its value. Added an explicitly
tagged integration test for the production `Provider.ReqLLM` streaming path. The first live model
request supplies one exact `vxpipe_interop_value` tool with a raw JSON Schema constrained to the
fixture value. Gemini returned that exact call and argument. The second request supplies the
assistant call, its correlated ordinary `running` result, the matching bounded pending projection,
and no tools because this fixture binding is blocking. Gemini accepted the exchange and streamed a
non-empty acknowledgement.

The live command passed 1 test with 0 failures. ReqLLM debug logging rendered the request URL with
the API key as `[REDACTED]`. The new package's test helper initially did not exclude integration
tests, so the ordinary child suite reran the network check. Aligned it with the other umbrella apps
using `exclude: [:integration]`; the default suite now remains offline.

Verification:

- Tagged Gemini provider run: 1 test, 0 failures.
- Default `vxpipe_agent_runtime` suite: 37 tests, 0 failures, 1 excluded.
- Umbrella format, warnings-as-errors, strict Credo, and unused-lock checks: pass.
- Umbrella `mix test`: stopped before test execution because the shell has no local PostgreSQL
  password.
- Call Engine selection/admission reconciliation and end-to-end sample verification remain
  pending. The tagged test does not claim browser or live-room integration.

## Implementation checkpoint 4b: neutral supervised host invocation

Added the Call Engine worker substrate alongside the still-live Jido path. The focused red test
failed because `InvocationBinding`, `InvocationCompletion`, and `InvocationSupervisor` did not
exist. The implementation keeps responsibilities separate:

- `InvocationBinding` converts an immutable resolved host binding into an inspection-safe runtime
  target while preserving its conversation mode.
- `InvocationSupervisor` owns capacity-bounded temporary children.
- `Invocation` owns one attempt, its linked execution task, deadline, cleanup, and exactly one
  correlated completion.
- `InvocationExecution` owns exception containment, JSON result validation, and the configured
  result-size bound.

The test uses a host tool whose legacy definition retains the default `execution: :inline`. Starting
it returns a supervised invocation worker while the actual operation is still waiting in another
process, proving that the old label no longer chooses execution placement in this path. A second
worker is rejected at supervisor capacity. Release produces one correlated result and normal worker
termination; a separate explicit-non-blocking invocation reaches its deadline, kills its execution,
and reports `unknown` once. The focused suite passed 2 tests.

This checkpoint supports resolved host bindings only and is not wired into an activation. Remote
MCP and Call Variables handlers, registry lifecycle/leases/pending projection, Agent Runtime
adapters, and coordinator admission remain explicit follow-up work.

Verification:

- Focused invocation supervisor suite: 2 tests, 0 failures after the expected missing-module red
  compile.
- Complete Call Engine suite: 218 tests, 0 failures, 2 integration exclusions.
- Two consecutive earlier full-suite runs exposed different MCP-owner monitor assertions using
  ExUnit's implicit 100 ms receive timeout. Both passed focused. Test-hygiene commit `ac33562`
  published explicit one-second bounds before the clean complete run.
- Umbrella format, warnings-as-errors compilation, Credo strict, and unused-lock checks passed.
- Umbrella `mix test` stopped before tests because local PostgreSQL SCRAM authentication requires a
  password unavailable in this shell; no credential source was inspected.

## Implementation checkpoint 4c: authoritative invocation registry

Added the registry lifecycle test first. Its red compile failed because `InvocationRegistry`,
`InvocationStatus`, and `CompletionLease` did not exist. The green path adds separate submission,
record, registry-state, safe-status, and lease values around the process boundary instead of
putting execution state into `AgentCoordinator` or enlarging the legacy `Tool.Dispatcher`.

The registry accepts a validated runtime binding only after its DynamicSupervisor starts the
worker. It retains a private fingerprint so an identical delivery of the same invocation ID is
acknowledged without starting a second worker, while a conflicting reuse is rejected. Capacity is
reserved through `running`, `terminal_queued`, and `completion_admitted`; a terminal result does not
free capacity merely because a worker exited.

Completion notification carries only registry identity and invocation ID. The consumer leases the
private completion, acknowledges it only after its later Agent Runtime continuation commits, or
releases it after failure/cancellation so it can be leased again without rerunning the operation.
Acknowledgement removes the live record and adds its ID to a bounded tombstone set. Ordered
snapshots contain only invocation ID, local tool name, conversation mode, source turn ID, and safe
phase—never arguments, result, handler, or credentials.

A review before commit found a fast-completion race between `start_child/2` returning and the
registry installing its record/monitor. A new red test required a prepared worker to remain dormant.
`InvocationSupervisor` now separates prepare from begin; the registry prepares the child, installs
its monitor and local record, then explicitly begins it before returning accepted. A fast
completion is consequently handled only after the GenServer commits the running record.

Verification:

- Focused invocation worker/registry suites: 4 tests, 0 failures after the expected missing-module
  red compile and the expected missing prepare/begin red failure.
- Complete Call Engine suite: 220 tests, 0 failures, 2 integration exclusions.
- Umbrella format, warnings-as-errors compilation, Credo strict, and unused-lock checks passed.
- Umbrella `mix test` stopped before tests because local PostgreSQL SCRAM authentication requires a
  password unavailable in this shell; no credential source was inspected.

The registry currently accepts host invocation bindings and a PID completion target. Remote MCP
and Call Variables runtime bindings, the Agent Runtime submit/pending adapters, activation
supervision, coordinator admission, and submit-timeout reconciliation fault injection remain.

## Implementation checkpoint 4d: Call Engine package adapters

Added a focused test through `Vxpipe.AgentRuntime.Executor.submit/5` and
`Vxpipe.AgentRuntime.PendingContext.fetch/3` before adding the umbrella dependency. It failed at
compile time because Call Engine did not depend on `vxpipe_agent_runtime` and none of its bridge
values existed.

Call Engine now depends directly on the lower-level standalone package. An inspection-safe
`AgentRuntime.Correlation` carries the private invocation registry and trusted `Tool.Context` for
one request while exposing only command/turn correlation in inspection. `InvocationExecutor`
implements the package's submit-only callback by delegating directly to `InvocationRegistry`; it
has no execution fallback. `PendingContextSource` verifies that the correlation names the same
activation registry, obtains a bounded snapshot with the package-provided timeout, and converts
each safe status to a validated `Vxpipe.AgentRuntime.PendingInvocation`.

The focused test submits an explicitly non-blocking legacy-inline host binding, observes execution
in the external worker, and sees `running` followed by `terminal_queued` through the public pending
context contract without exposing its private result through inspection.

Verification:

- Focused package-adapter suite: 1 test, 0 failures after the expected missing-dependency/module red
  compile.
- Complete Call Engine suite: 221 tests, 0 failures, 2 integration exclusions.
- Umbrella format, warnings-as-errors compilation, Credo strict, and unused-lock checks passed.
- Umbrella `mix test` stopped before tests because local PostgreSQL SCRAM authentication requires a
  password unavailable in this shell; no credential source was inspected.

Remote MCP and Call Variables handlers, descriptor compilation, activation-owned Session startup,
coordinator admission/completion leasing, and submit-timeout reconciliation fault injection remain.

## Implementation checkpoint 4e: resolved host descriptors

Added a focused compiler boundary between resolved call-plan host bindings and the standalone Agent
Runtime. Its initial two-test run failed for the expected reason: the
`AgentRuntime.ToolDescriptors` module and `compile/1` entry point did not exist.

The compiler now orders the resolved tool map by exact local name, reads the already-registered host
definition, creates the model-visible name/description/raw JSON Schema descriptor, and stores the
host action plus `blocking` or `non_blocking` conversation mode only in the opaque
`InvocationBinding`. Descriptor inspection does not expose that binding. The map key, resolved
binding name, and host definition name must agree or the entire compilation fails with a bounded
error.

This checkpoint preserves the execution/admission distinction. A descriptor's conversation mode
controls later caller-turn admission only. It does not choose execution placement: every compiled
host descriptor points at the same invocation registry and independently supervised worker path.

Verification:

- Focused descriptor compiler suite: 2 tests, 0 failures after the expected missing-module red run.
- Complete Call Engine suite: 223 tests, 0 failures, 2 integration exclusions.
- Umbrella format, warnings-as-errors compilation, strict Credo, and unused-lock checks passed.
- Umbrella `mix test` stopped before test execution because PostgreSQL SCRAM authentication needs a
password absent from this shell; no credential source was inspected.

- Remote MCP and Call Variables descriptors, activation-owned Session startup, coordinator
  admission/completion leasing, and submit-timeout reconciliation fault injection remain pending.

## Implementation checkpoint 4f: supervised Call Variables tools

Extended the focused descriptor and invocation-worker tests before implementation. The seven-test
run had the expected two failures: `ToolDescriptors.compile/2` and
`InvocationBinding.from_call_variables/2` did not exist.

Call Variables bindings now expose their finite permitted Action set from the already-pinned read
and write sections. The descriptor compiler combines those generated tools with resolved host tools
in exact name order. Each generated descriptor is default-blocking because these tools are derived
from permissions rather than explicit participant `tools` entries. Its opaque binding contains the
scoped `CallVariables.Binding`; the descriptor's model and inspection projections do not.

`InvocationExecution` now handles that private binding by calling its existing authorization and
command boundary using the invocation's exact tool name. The test supplies a controlled
room-variables process and observes that its `GenServer.call` originates from the independently
supervised invocation execution process, not the test/agent caller. Existing Call Variables tests
continue to own authorization, update, revision, schema, and archival behavior.

Verification so far:

- Focused descriptor and invocation-worker suites: 7 tests, 0 failures after the expected two-test
  red result.
- Complete Call Engine suite: 225 tests, 0 failures, 2 integration exclusions.
- Umbrella format, warnings-as-errors compilation, strict Credo, and unused-lock checks passed.
- Umbrella `mix test` again stopped before test execution because PostgreSQL SCRAM authentication
  needs a password absent from this shell; no credential source was inspected.
- Remote MCP execution remains outside this milestone. Activation-owned Session startup,
  coordinator admission/completion leasing, and submit-timeout reconciliation fault injection
  remain pending here.

## Implementation checkpoint 4g: named Agent Runtime Session

Added a focused Agent Runtime test requiring `Session` to start under an explicit OTP name while
keeping that registration option outside immutable runtime configuration. The initial five-test run
failed with `:invalid_configuration` because `name` reached `SessionConfiguration`.

`Session.start_link/1` now separates the standard GenServer `name` option before initializing the
session. A Call Engine activation can consequently refer to its single session through the existing
activation registry without adding room identity or supervisor topology to package-owned model
state. The focused Session suite passed 5 tests and the complete Agent Runtime suite passed 38 tests
with 1 integration exclusion.

Umbrella format, warnings-as-errors compilation, strict Credo, and unused-lock checks passed.
Umbrella `mix test` stopped before test execution at the unchanged missing PostgreSQL SCRAM
password; no credential source was inspected. Call Engine activation wiring and its own
completion/admission coordinator remain pending.

## Implementation checkpoint 4h: ordinary runtime coordination

Added the smallest Call Engine coordinator boundary for an ordinary streamed Agent Runtime turn.
The first focused test failed because no coordinator module existed. The implemented coordinator
owns a bounded queue and calls the synchronous `Session.request/4` API under a supplied
`Task.Supervisor`, leaving its GenServer callback free to receive streamed runtime events. A
separate output buffer turns deltas into complete sentence messages under the existing capability
contract and appends only an unstreamed suffix from the canonical final response.

Review identified a cancellation race at the engine output bound: advancing the queue immediately
after rejecting an oversized delta could find the named Session still busy. The added regression
test failed with the queued request reported unavailable. The coordinator now cancels the rejected
runtime request and terminates its caller task before advancing; the queued clean request then
completes normally.

Verification so far:

- Focused coordinator suite: 2 tests, 0 failures after the expected missing-module and cancellation
  race red results.
- Complete Call Engine suite: 227 tests, 0 failures, 2 integration exclusions.
- Umbrella format, warnings-as-errors compilation, strict Credo, and unused-lock checks passed.
- Umbrella `mix test` stopped before test execution because PostgreSQL SCRAM authentication needs a
  password absent from this shell; no credential source was inspected.
- This checkpoint does not wire the coordinator into an activation and does not claim tool
  admission, blocking/non-blocking gate, completion leasing, or interruption behavior.

## Implementation checkpoint 4i: registry-backed conversation admission

Added coordinator tests for both tool conversation modes before implementation. The red run had one
failure: a caller turn entered the deterministic model provider while a blocking invocation was
running. The new `AgentRuntime.ConversationAdmission` module reads only the authoritative
invocation-registry snapshot. Any blocking record holds admission across running,
terminal-unconsumed, and leased phases; a list containing only non-blocking records admits the turn.
Invalid or unavailable state fails closed.

The coordinator now sends one fixed bounded holding sentence plus the normal text-complete message
without putting held caller content in Agent Runtime conversation. In the non-blocking case the
ordinary request proceeds and its provider request contains the existing payload-free pending
invocation projection. The gate is independent of worker execution: it neither runs a tool inline
nor waits for or cancels the worker.

Focused coordinator verification passes 4 tests. The test keeps a blocking record through worker
completion and proves the terminal-unconsumed record still holds a later caller turn. Completion
leasing/consumption, interruption, activation selection, and live-path parity remain pending.

The complete Call Engine suite passes 229 tests with 2 integration exclusions. Umbrella format,
warnings-as-errors compilation, strict Credo, and unused-lock checks pass. Umbrella `mix test`
stops before test execution because PostgreSQL SCRAM authentication needs a password absent from
this shell; no credential source was inspected.

## Implementation checkpoint 4j: completion lease and private continuation

Added a completion-priority coordinator test before implementation. It completed a controlled
non-blocking invocation while an ordinary model request and a later caller command were pending. The
red run produced a holding response for the queued command and never admitted the tool completion.
The implemented scheduler now leases terminal registry work before examining caller input, creates a
source-correlated `ContinueAgent`, and calls `Session.continue/4` from the separately supervised
request task. The continuation is announced through the existing capability contract before its
text can be projected.

A second red test covered the cross-sender notification race: the registry was already terminal,
but a caller `GenServer.call` reached the idle coordinator before the notification. The coordinator
now attempts a lease synchronously before admitting an idle caller. For non-blocking work that caller
is queued behind the private continuation. A blocking completion still holds and discards the caller
turn while the private continuation proceeds.

The registry record is acknowledged only after the Session returns a completed, committed private
turn. Provider failure or cancellation releases the uncommitted lease, retains the terminal record,
and stops the coordinator closed rather than rerunning the tool or letting caller work overtake lost
state. A focused failure test monitors that coordinator exit and verifies the record returned to
`terminal_queued`.

Completion construction retains the invocation's source identifiers and its original
`audio_response` choice in tool context. The completion payload is still bounded untrusted data.
The coordinator was refactored before commit: `Coordinator.ActiveRequest` owns one request's task,
correlation, output buffer, and cancellation; `Coordinator.RequestOutcome` owns terminal output and
lease decisions; `CompletionContinuation` owns lease-to-command construction. The coordinator is
now the serializer/admission scheduler instead of absorbing those separate reasons to change.

Focused coordinator verification passes 8 tests. The complete Call Engine suite passes 233 tests
with 2 integration exclusions. Umbrella format, warnings-as-errors compilation, strict Credo, and
unused-lock checks pass. Umbrella `mix test` stops before test execution because PostgreSQL SCRAM
authentication needs a password absent from this shell; no credential source was inspected.

## Implementation checkpoint 4k: interruption-safe conversation history

Added three Agent Runtime tests before implementation. The red run failed because
`Session.discard/2` did not exist. The covered cases select an ordinary completed exchange for
removal, retain an accepted tool-call/running-result exchange while removing its later answer, and
retain a private engine completion observation while removing the assistant speech generated from
it.

Conversation now owns explicit entries rather than inferring retention from a flat list. The
system instruction is permanent; accepted tool exchanges are durable; ordinary final conversation
is discardable by its opaque request correlation. Engine-origin input is durable because it can
carry the one consumed terminal tool outcome, while its assistant answer remains discardable. The
public provider projection remains the same flattened message sequence and never receives the
correlation or retention metadata.

`Session.discard/3` accepts only a list of correlation maps and operates only while the Session is
idle. The Call Engine interruption path must first cancel and receive the request's terminal result,
then reconcile any completed turns. This checkpoint changes no worker lifecycle: an accepted tool
continues in its independently supervised process.

Focused and complete Agent Runtime verification passes 41 tests with 1 integration exclusion.
Umbrella format, warnings-as-errors compilation, strict Credo, and unused-lock checks pass.
Umbrella `mix test` stops before test execution because PostgreSQL SCRAM authentication needs a
password absent from this shell; no credential source was inspected. Coordinator interruption and
activation selection remain pending.

## Implementation checkpoint 4l: caller interruption coordinator

Added two Call Engine coordinator tests before implementation. The red run failed twice because
`Coordinator.interrupt/2` did not exist. One test completes an older turn, starts another, queues a
third, interrupts the latter two while selecting the completed identity for history removal, and
then proves a replacement provider request contains only the system instruction and replacement
input. The other keeps a controlled invocation worker running across model interruption and verifies
its registry phase remains `running`.

The new `Coordinator.Interruption` collaborator owns the cancellation/reconciliation operation.
It cancels the current caller request through the Session, clears queued caller commands, selects
completed correlations through the bounded `Coordinator.History`, and calls the idle-only history
discard boundary. It never calls the invocation registry or supervisor. An active private
completion currently returns unavailable and fails the temporary migration coordinator closed;
that lease/commit distinction remains the next interruption checkpoint before activation selection.

`RequestOutcome` now records only successfully completed requests in the bounded history. During
the first complete Call Engine run, an existing completion test exposed a real ordering race: the
coordinator sent `text_complete` before acknowledging the terminal invocation record, so an
immediate registry snapshot could still see `completion_admitted`. Completion acknowledgement now
commits before the externally visible completion signal. Configuration parsing and state assembly
were moved to `Coordinator.Configuration`, leaving the coordinator focused on serialization,
admission, and scheduling.

Focused verification passes 10 coordinator tests. The first full suite after that correction hit
an unrelated room-incarnation monitor race (`:noproc` instead of `:shutdown`); the specific test
passed immediately in isolation. The unchanged complete Call Engine suite then passed 235 tests
with 2 integration exclusions. Umbrella format, warnings-as-errors compilation, strict Credo, and
unused-lock checks pass. Umbrella `mix test` stops before test execution because PostgreSQL SCRAM
authentication needs a password absent from this shell; no credential source was inspected.

## Implementation checkpoint 4m: private-completion interruption

Added durable-correlation assertions to the three Agent Runtime history tests before
implementation. The red run reported three undefined `Session.durable?/2` calls. `Conversation`
now answers whether an opaque request correlation owns any durable entry, and Session exposes that
query only while idle. Ordinary caller conversation reports false; an accepted tool exchange and a
committed private engine observation report true. The complete Agent Runtime suite passes 41 tests
with 1 integration exclusion.

Added three coordinator tests before implementing private-completion interruption. The two
conversation-mode cases initially returned unavailable because completion interruption was
deliberately fail-closed. An uncommitted non-blocking completion now releases its lease, suppresses
the registry notification while replacement input is pending, admits that caller, and retries the
same terminal observation afterward. The blocking form emits the deterministic hold without model
admission and then retries immediately. No tool worker is rerun in either case.

The third test makes a completion continuation request another tool, interrupts its acknowledgement
round after the nested submission commits, and verifies the original completion is consumed while
only the nested invocation remains running. Its first attempt exposed that
`CompletionContinuation` inherited the old completed invocation's `tool_call_id`; the submission
boundary correctly rejected the new call as mismatched. A private continuation is a new agent
request, so its tool context now resets that field to `nil`. After the durable nested exchange,
interruption acknowledges the original lease rather than replaying the completion; the nested
worker continues and its own completion is consumed normally.

Focused coordinator verification passes 13 tests. The complete Call Engine suite passes 238 tests
with 2 integration exclusions. Umbrella format, warnings-as-errors compilation, strict Credo, and
unused-lock checks pass. Umbrella `mix test` stops before test execution because PostgreSQL SCRAM
authentication needs a password absent from this shell; no credential source was inspected.
Activation selection is the next migration step.

## Implementation checkpoint 4n: activation-owned runtime graph

Added an activation-boundary test before implementation. It requested the Agent Runtime topology,
submitted a normal caller command to its coordinator, checked the pinned system instruction and
host tool projected to the deterministic provider, and exercised the existing capability text
contract. The red run failed in the old Jido-only graph because it tried to fetch the absent legacy
`request_options` value.

The explicit `:agent_runtime` topology now starts an activation-local request `Task.Supervisor`,
the migration coordinator, an invocation `DynamicSupervisor`, the authoritative invocation
registry, and one `Vxpipe.AgentRuntime.Session`. The registry and Session resolve the already-started
coordinator's registered reference to its current PID during their startup; the coordinator refers
to its later children by registered name. This breaks the startup dependency cycle without a
synchronous process cycle at runtime.

The activation keeps its existing `:one_for_all` policy and one-restart budget. The test kills the
Session and observes every graph child stop and be replaced; killing the replacement Session then
terminates the activation. No tool can survive as stale state from an earlier graph generation.
`AgentActivationSupervisor` now selects a graph and owns naming/restart policy only. The legacy Jido
and new Agent Runtime child specifications are isolated in separate modules rather than enlarging
the supervisor.

Focused activation verification passes 4 tests. The complete Agent Runtime suite passes 41 tests
with 1 integration exclusion, and the complete Call Engine suite passes 239 tests with 2 integration
exclusions. Umbrella format, warnings-as-errors compilation, strict Credo, and unused-lock checks
pass. Umbrella `mix test` stops before test execution because PostgreSQL SCRAM authentication needs
a password absent from this shell; no credential source was inspected. Plan startup is deliberately
unchanged in this checkpoint, so live rooms still select the compatibility graph; that selection
and room-level parity are next.

## Implementation checkpoint 4o: application-selected room path

Added a definition-driven room test before implementation. It configured the application runtime
to select Agent Runtime, started a planned room, and expected a Session instead of a Jido
AgentServer. The red run found the old AgentServer, proving that Plan Startup ignored the requested
runtime and that the earlier graph was reachable only through its direct supervisor test.

Plan Startup now turns an explicit `:agent_runtime` application selection into activation options.
It calls the application-configured model provider constructor with the call-definition-pinned model,
passes the resolved host-tool map for neutral descriptor compilation, and retains the prompt,
Call Variables binding, provider label, and existing bounds. Invalid provider construction becomes
the same bounded unsupported-plan error as other invalid model runtime configuration.

Room Authority now records either the migration coordinator or the legacy coordinator behind its
existing text-capability module/PID pair. Response already dispatches through that pair;
interruption and participant-owned shutdown gained the matching migration-coordinator clauses. The
room test attaches the caller, submits text, inspects the pinned system instruction and host alias
at the deterministic Agent Runtime provider, and receives the unchanged participant-turn,
`TextOutput`, and agent-turn-completed events.

The activation-option translation was separated into `PlanStartup.AgentActivation` after the test
went green. This reduced `PlanStartup` from 464 to 306 lines and keeps provider/activation migration
logic out of speech and participant startup translation. The complete Call Engine suite passes 240
tests with 2 integration exclusions. The first full run hit an existing 100 ms model-inference test
timing assertion; the unchanged suite passed on immediate rerun. The application default remains
the compatibility graph until its scripted tool and failure parity tests are migrated to the neutral
provider; this setting is a migration seam, not two intended production loops. Umbrella format,
warnings-as-errors compilation, strict Credo, and unused-lock checks pass. Umbrella `mix test` stops
before test execution because the local PostgreSQL SCRAM password is absent; no credential source
was inspected.

## Implementation checkpoint 4p: application default and local fixture adapter

Added focused tests for an Agent Runtime adapter around the existing local model fixture before
implementation. The red run reported the missing adapter module. The implemented provider resolves
the fixture server during configuration, keeps only the selected model in `Inspect`, obtains the
latest caller/engine input from the neutral model request, and streams one successful fixture
answer. Fixture failure returns `provider_unavailable`; intentionally missing output returns
`invalid_provider_response`. Neither case invents assistant text. The focused suite passes 2 tests.

Base application configuration now selects `Vxpipe.AgentRuntime.Provider.ReqLLM` and the Agent
Runtime activation graph. Development runtime injects the already-required Gemini key directly into
that activation-pinned provider config. When the local fixture is enabled, it instead selects the
new fixture adapter and its supervised fixture process. No-start development configuration checks
verified both selections; the output contained only implementation, provider module, and provider
label, not provider options or credentials.

The test environment temporarily overrides only the activation implementation to Jido and repeats
the existing runtime limits. This keeps the remaining legacy `expect_react` scenarios green while
they are migrated to neutral scripted provider data; the explicit Agent Runtime room-path test still
selects and proves the new graph. The complete Call Engine suite passes 242 tests with 2 integration
exclusions. Umbrella format, warnings-as-errors compilation, strict Credo, and unused-lock checks
pass. Umbrella `mix test` stops before execution because the local PostgreSQL SCRAM password is
absent; no credential source was inspected. This compatibility setting is test migration scaffolding
and must disappear with the Jido graph and dependencies before the milestone completes.
