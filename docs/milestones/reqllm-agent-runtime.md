# ReqLLM agent runtime

Status: implementation in progress. Package contracts, lifecycle, provider-neutral loop, and
the production ReqLLM boundary with tagged-provider interoperability are implemented. Call Engine
migration and final evidence remain pending.
Prerequisites: [Definition-driven call](definition-driven-call.md),
[Call Variables](call-variables-and-tool-visibility.md), and
[background-tool conversation](background-tool-conversation.md).
Sources: [runtime decision](../reqllm-agent-runtime.md),
[prior Jido investigation](../jido-tool-execution.md), and
[ReqLLM documentation](https://hexdocs.pm/req_llm).

## Runnable outcome

The existing sample call runs through the separate `vxpipe_agent_runtime` internal package
instead of Jido. It streams an ordinary answer, submits exact data-backed tool aliases to
external workers, remains conversational for a non-blocking binding, enforces the default
blocking binding, and consumes its later private completion. The same package can project a
second alias sharing the same executor while preserving a different pinned schema. No Jido
process or dependency is used.

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
  supervised request workers perform provider work and submit tools outside GenServer callbacks.
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
  arguments, and ask the engine-owned submit-only executor to start independently supervised
  work. Agent Runtime never executes an operation inline. Preserve call IDs, model order,
  provider metadata, and definite non-submission errors. Corrupt exchanges and exhausted
  bounds fail the current turn instead of inventing a result.
- Every accepted submission returns the existing bounded running acknowledgement
  immediately. That single correlated acknowledgement is committed as the invocation's tool
  result and remains in model conversation, so every later model request includes it while
  the work is pending. The runtime does not repeat the acknowledgement or synthesize polling
  or status messages. The work and completion mailbox remain Call Engine-owned and outlive
  later speech cancellation as already specified. Completion enters once as a private
  engine-origin observation carrying the same invocation ID; it is not a second result
  attached to the old tool exchange and does not create public caller speech.
- Tool bindings default to blocking later caller conversation and may opt into
  `non_blocking` in the call definition. Blocking is Call Engine admission policy, never
  inline execution: the current acknowledgement round may finish, then caller turns receive
  a deterministic holding response without entering the LLM until the terminal private
  continuation is consumed. Non-blocking turns retain all pending running acknowledgements.
  Follow the [tool execution model](../tool-execution-model.md).
- Before every provider generation, obtain a bounded payload-free pending-invocation snapshot
  from a Call Engine context-source contract. Supply it as trusted ephemeral model context,
  never as another committed tool result. Conversation history records what was said; Call
  Engine remains authoritative for what is currently running or awaiting consumption.
- Normalize runtime events for request start, text delta, complete tool request, executor
  outcome, usage, terminal answer, cancellation, and safe failure. Events carry opaque
  correlation supplied by Call Engine, but the runtime does not assign call/participant/turn
  authority, client visibility, transcript policy, TTS, storage, or cost interpretation.
- Apply an absolute request deadline, provider timeouts, maximum model rounds, maximum
  tool calls per round, bounded tool argument/result bytes, bounded text/response bytes,
  and bounded event handoff. Failure or cancellation cannot trigger an automatic model,
  tool, or provider retry. Provider-native routing remains a later configured concern.

## Migration checkpoints

1. [Complete 2026-09-10] Add the child application and red-test its public descriptor,
   request, result, event, submit-only executor, pending-context source, and session contracts
   with a deterministic model driver.
2. [In progress 2026-09-10] Implement the submit-only model/tool state machine: final
   response, accepted running acknowledgements, definite non-submission, multiple calls in
   model order, mixed text/tool output, commit barriers, bounded failure, and cancellation.
   Normalized response/tool-call values, the exact private registry, accepted/rejected ordered
   submission batches, blocking/non-blocking acknowledgement rounds, and accepted-work
   recovery after provider failure or cancellation are complete. Per-session tool-batch and
   accumulated-output bounds, the request deadline, and private engine-origin continuation
   admission are also implemented. Provider-neutral bounded text streaming is complete.
   Remaining submit callback bounds, production ReqLLM adapter behavior, and Call Engine lease
   integration remain pending.
3. [Complete 2026-09-10] Add the ReqLLM adapter by moving/refining the existing Call Engine
   projection. Raw JSON Schema aliases, canonical exchanges, deterministic streaming collection,
   usage, safe call metadata, cleanup, and live-provider interoperability are covered. The live
   check remains tagged and excluded from default tests. Call Engine selection belongs to the next
   checkpoint.
4. [In progress 2026-09-10] Replace the Jido AgentServer child in an activation with
   `Vxpipe.AgentRuntime`; migrate
   the coordinator/dispatcher to one worker-submission path and compile default-blocking /
   explicit-non-blocking binding policy. The schema/compiler portion is complete in
   `20260910.01`. The neutral capacity-bounded host invocation supervisor/worker is complete and
   proves that a legacy-inline operation executes out of process with one bounded terminal
   outcome. The authoritative registry now retains idempotent submissions, payload-free pending
   phases, leased terminal outcomes, explicit consumption, and bounded tombstones. Its narrow Agent
   Runtime submit and pending-context adapters are complete. Resolved host bindings now compile to
   deterministic descriptors with model-visible schema separated from the private action and
   conversation mode. Remote MCP/Variables handlers, runtime admission, and activation integration
   remain. Preserve completion and interruption behavior.
5. Run parity and churn checks, inspect the rendered sample, then remove unused Jido AI,
   Jido Action, Jido, and related lock entries. Do not remove them earlier or retain an
   unused fallback loop after migration.

## Implementation checklist

- [x] Finalize the standalone submit-only package contracts and supervised lifecycle.
- [ ] Implement deterministic submit-only rounds, exact runtime-tool resolution, canonical
  running exchanges, streaming events, cancellation/commit barriers, and all declared bounds.
- [x] Move/refine the existing ReqLLM projection behind the new package and add focused plus
  tagged-provider interoperability evidence.
- [ ] Migrate the agent activation/coordinator and all tools to supervised submission without
  changing room authority, client visibility, or archive contracts.
- [ ] Remove Jido dependencies and obsolete adapters only after behavioral parity, full
  umbrella verification, and rendered sample verification are green.
- [ ] Update architecture, package API documentation, milestone evidence, and the labnote
  in each coherent checkpoint.

## Acceptance and failure checks

- [ ] A deterministic run streams text, requests a tool, starts one external worker, commits
  its running result, performs an acknowledgement round, and later consumes its private
  completion once. Mixed text/tool output is neither dropped nor delivered twice.
- [ ] Two local aliases share one executor implementation while retaining distinct exact
  descriptions, schemas, binding identities, and attribution. Repeated unique aliases and
  schemas do not cause proportional atom/module growth.
- [ ] Unknown/duplicate tools, malformed calls, invalid arguments, excessive calls/rounds,
  oversized input/result/text, submission failure, worker failure, and provider failure
  produce the specified bounded model-error or terminal outcome with no unauthorized
  execution, public internal explanation, or retry.
- [ ] Multiple tool calls are submitted and acknowledged in provider-required model order.
  Partial submission preserves already-started work; a missing or duplicate acknowledgement
  cannot advance the model loop.
- [ ] Cancelling an active streamed request closes it, suppresses later deltas, discards only
  uncommitted exchange data, and leaves the session usable. It neither terminates an accepted
  worker nor removes its committed tool-call/running-result pair.
- [ ] Killing the runtime session terminates request workers without ending the room. Killing
  the participant activation cleans up the complete runtime subtree and stale results cannot
  attach to a replacement activation.
- [ ] A non-blocking acknowledgement, unrelated caller turn, and later engine-origin completion
  reproduce the completed milestone's ordering and visibility behavior. The single correlated
  running acknowledgement is committed once and appears in every later model request while
  pending, with no repeated polling or status message. The private completion carries the same
  invocation ID and is consumed once, with no fake public user message or competing TTS stream.
- [ ] Every provider generation receives the current bounded pending projection without tool
  arguments/results or private routing data; it is not appended repeatedly to conversation.
- [ ] Omitted binding policy blocks later caller model admission by default; an explicit
  `non_blocking` binding permits the unrelated-turn sequence. Blocking turns receive bounded
  deterministic hold output, and a completion is consumed before admission reopens.
- [ ] Process inspection, telemetry, errors, and public events contain no prompts, raw tool
  arguments/results, private bindings, credentials, or provider authorization values.
- [ ] A tagged supported-provider run accepts the exact tool schema, streams conversational
  text, performs a real multi-round tool continuation, reports observed usage, and cleans up
  after cancellation without relying on dependency-private APIs.

## Manual verification

1. Run the sample call with full debug tool visibility and confirm ordinary streamed text and
   that both a fast platform tool and a slow tool execute in external workers.
2. With a non-blocking binding, speak/type another turn while the operation runs, interrupt
   only active speech, then confirm its private completion is consumed once.
3. With the default blocking binding, send another caller turn and confirm deterministic hold
   output without model admission; confirm completion is consumed before conversation resumes.
4. Inspect diagnostics and call history for request/tool/usage correlation and confirm public
   visibility settings still hide tool events by default.
5. Repeat a controlled provider failure and mid-stream cancellation, then start another turn
   in the same session. Inspect desktop and mobile sample states in Chromium.

## Scope boundaries

No remote MCP network call, Legion integration, transfer, media
mixing, recording, storage migration, context compaction, Vxpipe-managed provider fallback,
automatic tool retry, durable runtime session, or new client protocol. This milestone builds
and adopts the model/tool-loop substrate; the next milestone connects its private executor
contract to the already implemented MCP bindings.

Context compaction remains future work, but it must preserve pending invocation state,
including the committed running acknowledgement and its invocation correlation, until the
single matching completion has been consumed.

## Completion and evidence

- [ ] Demonstrate the runnable outcome and every acceptance/failure check above.
- [ ] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [ ] Update this milestone, the index checkbox, architecture/API docs, and implementation
  labnote with actual test/browser/provider evidence in the implementation commits.

Implementation evidence:

- Checkpoint 1 foundation adds the standalone `vxpipe_agent_runtime` child with no Call Engine,
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
- The completed contract correction replaces provisional `Executor.execute/4` with
  submit-only `Executor.submit/4`. The callback can only confirm acceptance or return a
  bounded rejection category; it cannot return an inline business result.
- `PendingContextSource.snapshot/3` supplies the host state, safe correlation, and a bounded
  timeout. `PendingContext` runs the callback outside the session process, enforces that
  timeout, rejects excessive/duplicate/invalid projections, and passes only validated
  `PendingInvocation` values to the provider request. A source error, exception, exit, or
  timeout fails safely without calling the model.
- Red evidence: the expanded package suite initially reported 11 tests with 8 expected
  failures because `submit/4`, pending values/source, and session configuration did not
  exist. A separate timeout test then reported 3 tests with 1 expected failure while a
  stalled callback was still unbounded. Green focused suite: 12 tests, 0 failures.
- After the correction, umbrella `mix format --check-formatted`,
  `mix compile --warnings-as-errors`, `mix credo --strict`, and
  `mix deps.unlock --check-unused` pass. Umbrella `mix test` again stopped before executing
  tests because PostgreSQL authentication requires a password absent from this shell; the
  database-free owning application suite is green.
- Checkpoint 2a adds bounded `ToolCall` and `ModelResponse` values. Their `Inspect`
  implementations omit arguments, provider metadata, and generated text. It also adds a
  pinned `ToolRegistry` that rejects duplicate names, exposes only `ModelTool` projections,
  resolves exact strings, validates arguments against the compiled JSON Schema, and keeps the
  private binding out of inspection and provider values.
- Checkpoint 2a red evidence was a focused compile failure because `ModelTool` did not exist.
  After implementing the four cohesive value/registry modules, the focused contract/registry
  run passed 8 tests and the complete package suite passed 15 tests with 0 failures. Umbrella
  format, warnings-as-errors, strict Credo, and unused-lock checks pass. Umbrella `mix test`
  remains blocked before test execution by the same absent PostgreSQL password.
- Checkpoint 2b adds normalized messages/model requests, committed conversation state, and a
  focused `RequestRunner`. One complete validated call is submitted outside the Session
  GenServer; accepted work returns its resolved blocking mode, commits the assistant call and
  correlated `running` result through a Session acknowledgement barrier, refreshes pending
  state, and performs the next model round. A blocking acceptance withholds all tools from
  that acknowledgement round while preserving the mixed response text once.
- Session configuration validation/projection lives in `SessionConfiguration`; Session itself
  continues to own only lifecycle, admission, committed conversation, task correlation, and
  commit acknowledgement.
- Checkpoint 2b red evidence: the focused Session suite reported 5 tests with 4 failures under
  the old string-only provider path. The new single-call flow then passed, and a separate
  multiple-call test failed because the unfinished loop submitted work; the fail-closed guard
  made the complete package suite green at 17 tests, 0 failures. Umbrella format,
  warnings-as-errors, strict Credo, and unused-lock checks pass; umbrella tests remain blocked
  before execution by absent PostgreSQL authentication.
- Checkpoint 2c replaces the temporary multiple-call rejection with ordered batch handling.
  All names and schemas resolve before any submission; duplicate call IDs fail before work.
  The runner then submits in provider order and commits one matched result per call. Accepted
  calls receive `running`; definite host rejection receives a bounded `rejected` result.
  Accepted work is retained when a later call rejects, and any blocking acceptance withholds
  tools from the next round. An all-non-blocking batch keeps the authorized projection.
- The tool-round tests are separated from Session lifecycle tests. Checkpoint 2c red evidence
  showed the old temporary guard returning before the first expected submission. The complete
  package suite is green at 18 tests, 0 failures. Umbrella format, warnings-as-errors, strict
  Credo, and unused-lock checks pass; umbrella tests again stop before execution because the
  local PostgreSQL password is absent.
- Checkpoint 2d proves the submission commit barrier across provider failure. After the
  running exchange commits, a raw acknowledgement-provider error collapses to
  `provider_unavailable`. A later request in the same Session contains the original user,
  assistant call, and running result exactly once, followed by the new user input and current
  pending projection. No work is resubmitted and no raw provider reason escapes.
- Checkpoint 2d red evidence exposed the raw provider error in the public Result. The focused
  recovery test and full package suite are green at 19 tests, 0 failures. Umbrella format,
  warnings-as-errors, strict Credo, and unused-lock checks pass; umbrella tests remain blocked
  before execution by absent PostgreSQL authentication.
- Checkpoint 2e adds explicit Session cancellation without cancelling an accepted tool worker.
  Provisional provider work is terminated immediately and its staged input is discarded. A
  Session-owned submission barrier defers cancellation while the host submission is in flight;
  after acceptance/rejection, the complete matched exchange commits before the request task is
  terminated. The Session emits a bounded cancelled result/event and remains usable.
- Checkpoint 2e red evidence reported 2 focused failures because `Session.cancel/1` did not
  exist. Tests prove cancellation terminates active provider work, drops an uncommitted user
  turn, preserves an accepted running exchange across the submission race, and admits a clean
  later request. Full package suite: 21 tests, 0 failures. Umbrella format,
  warnings-as-errors, strict Credo, and unused-lock checks pass; umbrella tests stop before
  execution because the local PostgreSQL password is absent.
- Checkpoint 2f adds configurable positive limits for tool calls in one model round and for
  assistant output accumulated across all rounds of one admitted request. Call count and mixed
  response output are checked before entering the submission barrier, so an over-limit response
  starts no external worker. An over-limit terminal response is discarded without committing
  its staged input or output.
- Checkpoint 2f red evidence reported 3 focused failures because both settings were rejected as
  invalid Session configuration. The bounds tests and complete package suite are green at 24
  tests, 0 failures. Umbrella format, warnings-as-errors, strict Credo, and unused-lock checks
  pass; umbrella tests stop before execution because the local PostgreSQL password is absent.
- Checkpoint 2g adds a positive Session-owned request deadline, defaulting to 30 seconds. It
  terminates provisional provider work and discards its staged exchange when time expires. If
  expiry occurs after the submission barrier begins, Session records the terminal intent, waits
  for the complete running/rejection exchange to commit, and then terminates the model request
  without touching accepted external workers. `Session.request/4` now relies on that internal
  deadline by default instead of an earlier five-second `GenServer.call` timeout.
- Checkpoint 2g red evidence reported 2 focused failures because `request_timeout_ms` was not a
  valid Session setting. Deadline tests and the complete package suite are green at 26 tests,
  0 failures. Umbrella format, warnings-as-errors, strict Credo, and unused-lock checks pass;
  umbrella tests stop before execution because the local PostgreSQL password is absent.
- Checkpoint 2h adds `Session.continue/4` for private engine-origin input. The normalized message
  retains `origin: :engine` in runtime history while using the ordinary provider `user` role
  required by supported chat APIs. A successful continuation commits its input and answer; a
  provider failure commits neither, allowing Call Engine to retain and later re-admit its
  completion lease. Caller input retains `origin: :caller` distinctly.
- Checkpoint 2h red evidence reported 2 focused failures because the continuation API did not
  exist. Continuation tests and the complete package suite are green at 28 tests, 0 failures.
  Umbrella format, warnings-as-errors, strict Credo, and unused-lock checks pass; umbrella tests
  stop before execution because the local PostgreSQL password is absent.
- Checkpoint 2i adds an optional provider-neutral `stream/3` callback. It forwards only non-empty
  text deltas through a token-correlated Session handoff, bounds bytes and event count before
  forwarding, and treats all deltas as provisional. Only the final validated `ModelResponse`
  enters the existing output/commit loop. Delta event inspection excludes text payloads.
- Checkpoint 2i red evidence reported 4 focused failures: buffered generation was still selected
  and the event-count setting was invalid. Streaming tests and the complete package suite are
  green at 32 tests, 0 failures. Umbrella format, warnings-as-errors, strict Credo, and unused-lock
  checks pass; umbrella tests stop before execution because the local PostgreSQL password is
  absent. ReqLLM stream construction/materialization and transport cleanup remain checkpoint 3.
- Checkpoint 3a adds the production `Provider.ReqLLM` boundary split into credential-safe
  configuration, request projection, and response normalization modules. It maps caller and
  engine-origin messages to provider-compatible roles, projects exact JSON Schema tools with a
  non-executing callback, injects the bounded pending-invocation snapshot into ephemeral system
  context, and preserves canonical tool-call metadata needed for subsequent provider turns.
- Buffered responses and materialized streams normalize into the same bounded `ModelResponse`,
  including usage and ReqLLM's redacted call metadata. Every non-empty usage/metadata observation
  is handed to Session as an inspection-safe `model_usage` event before response handling. The
  deterministic stream fixture proves ordered text callbacks and explicit ReqLLM handle closure.
- Checkpoint 3a red evidence first failed to compile because normalized responses lacked usage and
  provider metadata. A subsequent focused usage-event test failed because the loop discarded
  those values. The adapter/usage tests and complete package suite are green at 37 tests,
  0 failures. Umbrella format, warnings-as-errors, strict Credo, and unused-lock checks pass;
  umbrella tests stop before execution because the local PostgreSQL password is absent.
- Checkpoint 3b adds a tagged Gemini interoperability test using the production streaming path.
  Gemini accepted the exact `vxpipe_interop_value` JSON Schema alias, returned the expected call,
  then accepted the canonical assistant-call/running-result exchange plus the current pending
  projection with tools withheld. The second provider round streamed non-empty conversational
  text. The tagged run passed 1 test with 0 failures; ReqLLM's debug URL redacted the credential.
- The default package suite now explicitly excludes integration tests and passes 37 tests with
  0 failures and 1 excluded. Umbrella format, warnings-as-errors, strict Credo, and unused-lock
  checks pass; umbrella tests stop before execution because the local PostgreSQL password is
  absent.
- Checkpoint 4e compiles a resolved host-tool map into exact name-ordered Agent Runtime
  descriptors. The model projection receives only each host definition's name, description, and
  raw JSON input schema. The opaque binding separately pins the host action and its default-blocking
  or explicit-non-blocking conversation mode; neither appears in descriptor inspection. Map-key,
  resolved-name, and host-definition-name agreement is required, so routing cannot drift silently.
- Checkpoint 4e red evidence reported 2 expected failures because the descriptor compiler did not
  exist. The focused suite then passed 2 tests and the complete Call Engine suite passed 223 tests
  with 2 integration exclusions. Both modes still compile to the one submit-only invocation path;
  this checkpoint adds no inline executor and does not yet select Agent Runtime in live calls.
- Umbrella format, warnings-as-errors compilation, strict Credo, and unused-lock checks passed for
  checkpoint 4e. Umbrella `mix test` stopped before test execution because PostgreSQL SCRAM needs a
  password absent from this shell; no credential source was inspected.

## Specification review

Locally reviewed during planning for dependency direction, SRP, supervision ownership,
tool/privacy authority, failure bounds, migration safety, and a runnable vertical outcome.
No independent review or implementation evidence is claimed.
