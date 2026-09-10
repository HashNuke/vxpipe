# ReqLLM agent runtime

Status: implementation in progress. Package contracts, lifecycle, provider-neutral loop, and
the production ReqLLM boundary with tagged-provider interoperability are implemented. Call Engine
uses the activation-owned Agent Runtime graph and no longer depends on Jido. The rendered sample
now demonstrates the non-blocking flow; the final acceptance audit remains pending.
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
  arguments, and ask the engine-owned submit-only executor to hand every invocation to an
  independently supervised worker. Neither the Agent Runtime request worker nor an agent/
  runtime GenServer ever executes an operation inline. Preserve call IDs, model order,
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
- Each authored platform/built-in, host, or MCP tool binding takes its tool-specific
  `conversation_mode` from its call-definition `tools` entry. The only values are `blocking`
  and `non_blocking`; omission resolves to `blocking`. Blocking is Call Engine admission
  policy only: the current acknowledgement round may finish, then subsequent caller turns
  receive a deterministic holding response without entering the LLM until the terminal
  private continuation is consumed. `non_blocking` lets unrelated later turns proceed. Both
  modes always hand execution to the same independently supervised worker path; this setting
  never selects inline execution.
  The current compiler supports this field on authored host and MCP selections; generated
  Call Variables tools take the default until a later policy override is explicitly designed.
  Follow the [tool execution model](../tool-execution-model.md).
- Before every provider generation in either conversation mode, obtain a bounded payload-free
  pending-invocation snapshot from a Call Engine context-source contract. Supply it as trusted
  ephemeral model context, never as another committed tool result. Conversation history records
  what was said; Call Engine remains authoritative for what is currently running or awaiting
  consumption.
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
   conversation mode. Permission-derived Call Variables tools now compile as default-blocking
   private bindings and execute through the same worker. Remote MCP handling belongs to the next
   milestone; activation integration remains. Agent Runtime sessions now accept an OTP process name
   outside their immutable model configuration, enabling the activation graph. The migration
   coordinator now projects ordinary streamed Session output through the existing capability
   contract from a separately supervised request task, bounds its queue/output, avoids replaying
   final text, and cancels a rejected stream before advancing queued work. It is not
   activation-selected yet;
   its registry-backed admission gate now holds caller turns for any unconsumed blocking invocation
   and admits turns when every pending invocation is explicitly non-blocking. Completion leasing and
   private continuation consumption are now integrated with completion priority and a commit-time
   acknowledgement. Agent Runtime history now distinguishes discardable final conversation from
   durable accepted-tool and private-completion facts, and exposes idle-only correlation-based
   discard for the room interruption path. The migration coordinator now cancels active caller
   generation, drops queued caller commands, reconciles exact completed turns, and leaves accepted
   tool workers running. It also settles interrupted private completions from durable Session state:
   uncommitted observations are released and deferred across replacement admission, while a
   completion that committed a nested tool is acknowledged without replay. An explicit
   `:agent_runtime` activation now owns one request supervisor, coordinator, invocation supervisor,
   invocation registry, and Session under the existing one-for-all restart budget. Its deterministic
   activation test reaches the new provider boundary and proves complete graph replacement after a
   Session failure. Plan startup and room authority can now select that graph through the internal
   application runtime setting while preserving the existing capability contract. Application,
   development, and test configuration now select Agent Runtime by default. Full room tests now
   prove that an omitted tool policy blocks later caller
   model admission, an explicit `non_blocking` policy admits it, and both modes use the same
   activation-owned invocation worker/lifecycle path. Preserve completion and interruption behavior.
5. [In progress 2026-09-10] Run parity and churn checks, inspect the rendered sample, and remove
   unused Jido AI, Jido Action, Jido, and related lock entries. Dependency and fallback-loop
   removal and rendered sample inspection are complete; the final acceptance audit remains.

## Implementation checklist

- [x] Finalize the standalone submit-only package contracts and supervised lifecycle.
- [ ] Implement deterministic submit-only rounds, exact runtime-tool resolution, canonical
  running exchanges, streaming events, cancellation/commit barriers, and all declared bounds.
- [x] Move/refine the existing ReqLLM projection behind the new package and add focused plus
  tagged-provider interoperability evidence.
- [x] Migrate the agent activation/coordinator and all tools to supervised submission without
  changing room authority, client visibility, or archive contracts.
- [ ] Remove Jido dependencies and obsolete adapters only after behavioral parity, full
  umbrella verification, and rendered sample verification are green.
- [ ] Update architecture, package API documentation, milestone evidence, and the labnote
  in each coherent checkpoint.

## Acceptance and failure checks

- [x] A deterministic run streams text, requests a tool, starts one external worker, commits
  its running result, performs an acknowledgement round, and later consumes its private
  completion once. Mixed text/tool output is neither dropped nor delivered twice.
- [x] Two local aliases share one executor implementation while retaining distinct exact
  descriptions, schemas, binding identities, and attribution. Repeated unique aliases and
  schemas do not cause proportional atom/module growth.
- [x] Unknown/duplicate tools, malformed calls, invalid arguments, excessive calls/rounds,
  oversized input/result/text, submission failure, worker failure, and provider failure
  produce the specified bounded model-error or terminal outcome with no unauthorized
  execution, public internal explanation, or retry.
- [x] Multiple tool calls are submitted and acknowledged in provider-required model order.
  Partial submission preserves already-started work; a missing or duplicate acknowledgement
  cannot advance the model loop.
- [x] Cancelling an active streamed request closes it, suppresses later deltas, discards only
  uncommitted exchange data, and leaves the session usable. It neither terminates an accepted
  worker nor removes its committed tool-call/running-result pair.
- [x] Killing the runtime session terminates request workers without ending the room. Killing
  the participant activation cleans up the complete runtime subtree and stale results cannot
  attach to a replacement activation.
- [x] A non-blocking acknowledgement, unrelated caller turn, and later engine-origin completion
  reproduce the completed milestone's ordering and visibility behavior. The single correlated
  running acknowledgement is committed once and appears in every later model request while
  pending. Each admitted request also receives the authoritative pending identity and safe
  status, with no repeated polling or status message. The private completion carries the same
  invocation ID and is consumed once, with no fake public user message or competing TTS stream.
- [x] Every provider generation receives the current bounded pending projection without tool
  arguments/results or private routing data; it is not appended repeatedly to conversation.
- [x] Omitted binding policy blocks later caller model admission by default; an explicit
  `non_blocking` binding permits the unrelated-turn sequence. Blocking turns receive bounded
  deterministic hold output, and a completion is consumed before admission reopens.
- [x] Process inspection, telemetry, errors, and public events contain no prompts, raw tool
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
- Checkpoint 4f adds Call Variables as a second private invocation-binding kind. It derives the
  finite read/update descriptor set from the already-compiled participant grants, assigns the
  default `blocking` conversation mode, and dispatches the exact generated name from the neutral
  invocation worker to the scoped room-variables binding. The model projection cannot inspect the
  variables process, grants, or identity.
- Checkpoint 4f red evidence reported the expected 2 failures because descriptor compilation and
  invocation binding had no Call Variables entry points. The focused descriptor/worker suites then
  passed 7 tests, and the complete Call Engine suite passed 225 tests with 2 integration exclusions.
- Umbrella format, warnings-as-errors compilation, strict Credo, and unused-lock checks passed for
  checkpoint 4f. Umbrella `mix test` again stopped before test execution because PostgreSQL SCRAM
  needs a password absent from this shell; no credential source was inspected.
- Checkpoint 4g separates an optional Session OTP name from validated model/runtime options. Its
  focused red test failed because the name was treated as unknown runtime configuration; after the
  change, the named Session is registered and addressable while the complete Agent Runtime suite
  passes 38 tests with 1 integration exclusion. This is the minimal package prerequisite for the
  activation-owned child graph and adds no Call Engine or room dependency.
- Umbrella format, warnings-as-errors compilation, strict Credo, and unused-lock checks passed for
  checkpoint 4g. Umbrella `mix test` stopped before test execution at the unchanged missing
  PostgreSQL SCRAM password; no credential source was inspected.
- Checkpoint 4h adds a narrow Call Engine coordinator for ordinary Agent Runtime requests. Its
  Session call runs under a supplied `Task.Supervisor`, while the coordinator remains available to
  project streamed sentence segments through the existing capability contract and bound later
  caller input. The final canonical result contributes only a suffix that was not already streamed.
- Checkpoint 4h red evidence first failed because the coordinator module did not exist. A second
  focused failure exposed that rejecting an oversized stream advanced the queue while the Session
  was still busy; the coordinator now cancels that runtime request before advancing. The focused
  suite passes 2 tests and the complete Call Engine suite passes 227 tests with 2 integration
  exclusions. This checkpoint does not select the coordinator in a live activation and does not
  claim tool admission/completion behavior.
- Umbrella format, warnings-as-errors compilation, strict Credo, and unused-lock checks passed for
  checkpoint 4h. Umbrella `mix test` stopped before test execution because PostgreSQL SCRAM
  authentication needs a password absent from this shell; no credential source was inspected.
- Checkpoint 4i adds the Call Engine conversation-admission boundary. It derives `admit` or `hold`
  only from the authoritative registry snapshot and treats every unconsumed blocking phase as a
  hold. The coordinator emits one fixed bounded hold response and completion through the existing
  capability contract without model admission; a snapshot containing only non-blocking work admits
  the caller and reaches Agent Runtime with that safe pending context.
- Checkpoint 4i red evidence showed the blocking caller reaching the deterministic model provider.
  After the gate was connected, the focused coordinator suite passes 4 tests and the complete Call
  Engine suite passes 229 tests with 2 integration exclusions. Completion leasing, interruption,
  activation selection, and live-path parity remain pending.
- Umbrella format, warnings-as-errors compilation, strict Credo, and unused-lock checks passed for
  checkpoint 4i. Umbrella `mix test` stopped before test execution because PostgreSQL SCRAM
  authentication needs a password absent from this shell; no credential source was inspected.
- Checkpoint 4j leases terminal invocation outcomes before queued or racing caller work, constructs
  a source-correlated `ContinueAgent` command, and admits it through `Session.continue/4`. The
  registry record is acknowledged only after the private engine-origin turn commits. A provider
  failure releases the uncommitted lease and stops the coordinator closed, retaining the terminal
  record without rerunning the worker.
- The completion test was added before implementation and initially observed a queued blocking hold
  instead of a continuation. A second race test initially sent the caller to the provider because
  the completion notification had not reached the coordinator. Both paths now lease first. Focused
  coordinator verification passes 8 tests, including completion priority, the notification race,
  blocking holds during the active acknowledgement, and failure release.
- The coordinator refactor keeps request task/buffer/correlation mechanics in `ActiveRequest`,
  terminal output and lease decisions in `RequestOutcome`, and private command/lease construction in
  `CompletionContinuation`. Activation selection, interruption, and live-path parity remain pending.
- The complete Call Engine suite passes 233 tests with 2 integration exclusions. Umbrella format,
  warnings-as-errors compilation, strict Credo, and unused-lock checks pass. Umbrella `mix test`
  stops before test execution because PostgreSQL SCRAM authentication needs a password absent from
  this shell; no credential source was inspected.
- Checkpoint 4k adds request-correlated conversation entries and an idle-only `Session.discard/3`
  boundary for conservative interruption reconciliation. Ordinary caller input/final-answer pairs
  are discardable. Accepted tool-call/running-result exchanges remain durable, and a private
  engine-origin completion observation remains durable while its generated assistant answer is
  discardable. Correlations stay opaque and are not projected to the provider.
- Checkpoint 4k red evidence reported three missing-function failures before `Session.discard/2`
  existed. Its focused tests prove ordinary removal, accepted-tool preservation, and private
  completion preservation; the complete Agent Runtime suite passes 41 tests with 1 integration
  exclusion. Umbrella format, warnings-as-errors compilation, strict Credo, and unused-lock checks
  pass. Umbrella `mix test` stops before test execution because PostgreSQL SCRAM authentication
  needs a password absent from this shell; no credential source was inspected. Coordinator
  interruption and activation selection remain pending.
- Checkpoint 4l adds caller-turn interruption to the migration coordinator. It cancels the active
  Session request, clears queued caller commands, selects completed history by exact
  connection/correlation/command identity, and invokes the idle-only discard boundary before
  accepting replacement work. It does not address the invocation registry or supervisor, so an
  accepted tool worker remains running.
- Checkpoint 4l red evidence reported two missing-function failures because
  `Coordinator.interrupt/2` did not exist. The focused suite then passed 10 tests. An initial full
  Call Engine run exposed completion ordering: `text_complete` could reach room authority before
  the terminal invocation acknowledgement. The acknowledgement now commits first. A second run hit
  an unrelated incarnation-monitor timing assertion (`:noproc` instead of `:shutdown`); that test
  passed immediately in isolation, and the unchanged full suite then passed 235 tests with 2
  integration exclusions. Umbrella format, warnings-as-errors compilation, strict Credo, and
  unused-lock checks pass. Umbrella `mix test` stops before test execution because PostgreSQL SCRAM
  authentication needs a password absent from this shell; no credential source was inspected.
  Active private-completion interruption and activation selection remain.
- Checkpoint 4m completes migration-coordinator interruption semantics for a private completion.
  After cancelling the Session request, Call Engine queries whether that opaque correlation has a
  durable entry. An uncommitted observation releases its lease and defers completion scheduling
  across the replacement command: a non-blocking invocation admits the caller first; a blocking
  invocation holds the caller and immediately retries the completion. A durable observation caused
  by a nested accepted tool acknowledges the original completion, retains the nested running
  record, and never replays the original tool outcome.
- Checkpoint 4m package red evidence reported three missing `Session.durable?/2` calls. Coordinator
  red evidence reported unavailable interruption for both completion modes, while the nested-tool
  scenario exposed inherited `tool_call_id` context that rejected the new invocation. Private
  continuations now reset that per-invocation field. The complete Agent Runtime suite passes 41
  tests with 1 integration exclusion, and the complete Call Engine suite passes 238 tests with 2
  integration exclusions. Umbrella format, warnings-as-errors compilation, strict Credo, and
  unused-lock checks pass. Umbrella `mix test` stops before test execution because PostgreSQL SCRAM
  authentication needs a password absent from this shell; no credential source was inspected.
  Activation selection remains pending.
- Checkpoint 4n adds the activation-owned Agent Runtime process graph without changing plan startup
  or room contracts. A new activation test was written first and failed in the old Jido-only graph
  at its missing `request_options`. The explicit `:agent_runtime` graph then projected the selected
  prompt and host descriptor through the new Session/provider path and emitted output through the
  existing capability contract.
- The graph contains one activation-local request `Task.Supervisor`, coordinator, invocation
  `DynamicSupervisor`, authoritative invocation registry, and Agent Runtime Session. The coordinator
  starts before the registry and Session; those children resolve its registered reference to the
  current PID during startup. Killing the Session replaces the complete graph once, and a second
  Session failure exhausts the unchanged activation restart budget. `AgentActivationSupervisor`
  now selects topology only; legacy Jido child construction and new runtime child construction live
  in separate graph modules.
- Focused activation verification passes 4 tests. The complete Agent Runtime suite passes 41 tests
  with 1 integration exclusion, and the complete Call Engine suite passes 239 tests with 2
  integration exclusions. Umbrella format, warnings-as-errors compilation, strict Credo, and
  unused-lock checks pass. Umbrella `mix test` stops before test execution because PostgreSQL SCRAM
  authentication needs a password absent from this shell; no credential source was inspected. Plan
  startup and room authority do not select this graph by default yet.
- Checkpoint 4o connects the explicit application-selected Agent Runtime graph to the full room
  path. Its test was written first and observed an old Jido `agent_server`, proving that Plan Startup
  ignored the selection. After implementation, Plan Startup builds and validates the selected model
  provider config, retains the resolved host-tool map for neutral descriptor compilation, and pins
  the existing call-definition prompt and model in the activation options.
- Room Authority records the selected coordinator module behind its existing text-capability map.
  Normal response, interruption, and participant-owned shutdown therefore use the same room
  contracts for both migration graphs. A focused room test starts a planned call, proves that the
  activation has a Session and no Jido AgentServer, reaches the deterministic provider, and observes
  the ordinary participant-turn and agent-text completion events.
- Agent activation option construction moved out of the 464-line `PlanStartup` module into the
  cohesive `PlanStartup.AgentActivation` module; `PlanStartup` is now 306 lines and remains focused
  on validating and assembling the rest of room startup. The complete Call Engine suite passes 240
  tests with 2 integration exclusions. Umbrella format, warnings-as-errors compilation, strict
  Credo, and unused-lock checks pass. Umbrella `mix test` stops before test execution because the
  local PostgreSQL SCRAM password is absent; no credential source was inspected. Default selection
  and remaining scripted tool parity still need migration before the Jido graph can be removed.
- Checkpoint 4p makes Agent Runtime the application and development default. Hosted development
  constructs the activation-pinned production ReqLLM provider with the runtime-only API key, while
  local-fixture development selects a dedicated neutral model-provider adapter. No-start runtime
  configuration checks verified both selections without printing provider options or credentials.
- The fixture adapter was red-tested before implementation. It resolves the configured fixture
  process once, retains only its model in inspection, streams successful fixture output through the
  Agent Runtime provider contract, and maps fixture failure or missing content to bounded provider
  errors without fabricating an answer. Its focused suite passes 2 tests.
- The test environment explicitly retains the Jido graph for the remaining legacy `expect_react`
  scenarios; the earlier definition-driven Agent Runtime room test continues to override that seam
  and exercise the new path. The complete Call Engine suite passes 242 tests with 2 integration
  exclusions. Umbrella format, warnings-as-errors compilation, strict Credo, and unused-lock checks
  pass. Umbrella `mix test` stops before execution because the local PostgreSQL SCRAM password is
  absent; no credential source was inspected. This is temporary test migration scaffolding, not a
  supported production fallback.
- Checkpoint 4q adds focused room-level acceptance for the two conversation modes. Both scenarios
  compile the same deliberately blocked host operation from the participant's call-definition
  `tools` map and observe execution in a process distinct from the model request. Omission resolves
  to blocking: the acknowledgement round receives no tool surface, later caller input receives the
  deterministic hold without model admission, and admission reopens only after the private terminal
  continuation is consumed. An explicit `conversation_mode: "non_blocking"` retains the tool
  surface, admits unrelated caller input, and supplies its one correlated running acknowledgement
  plus current pending projection to that model request.
- The new invocation path now projects accepted and settled work through the existing room-owned
  `ToolCallStarted`/`ToolCallCompleted` boundary. `InvocationLifecycle` owns that translation, while
  the registry remains authoritative for start, terminal state, and completion availability. A
  trusted invocation context is authorized against the current incarnation, activation, source
  connection, and agent participant before Room Authority records it as pending. This preserves
  client visibility and archive routing without treating external work as part of the original
  turn's process lifetime.
- Checkpoint 4q red evidence was two room tests timing out on the absent `ToolCallStarted` event even
  though both independent workers had started. The focused two-scenario suite passes, the complete
  definition-driven suite passes 18 tests, and the complete Call Engine suite passes 244 tests with
  2 integration exclusions. Umbrella format, warnings-as-errors compilation, strict Credo, and
  unused-lock checks pass. Umbrella `mix test` stops before test execution because PostgreSQL SCRAM
  authentication needs a password absent from this shell; no credential source was inspected.
- Checkpoint 4r migrates the entry-participant/tool-ordering scenario and the private archive
  scenario from Jido's scripted ReAct helper to the neutral Agent Runtime test provider. Both now
  express the two real phases explicitly: a default-blocking submission produces a safe
  acknowledgement turn, then its already-executed result enters a distinct private engine-origin
  continuation. Exact room sequence assertions now cover tool start/completion, acknowledgement
  output/completion, and final result output/completion. The archive assertion similarly retains
  both agent turns plus complete private input and tool facts.
- This is test-parity migration only; no runtime behavior changed after checkpoint 4q. The complete
  Call Engine suite remains green at 244 tests with 2 integration exclusions. Remaining speech,
  failure/restart, Call Variables, unit, and tagged-provider Jido fixtures still prevent removal of
  the compatibility graph and dependencies. Umbrella format, warnings-as-errors compilation,
  strict Credo, and unused-lock checks pass. Umbrella `mix test` again stops before test execution
  because PostgreSQL SCRAM authentication needs a password absent from this shell; no credential
  source was inspected.
- Checkpoint 4s migrates four ordinary room scenarios to Agent Runtime: final speech input through
  archived TTS delivery, activation restart, selected speech-provider pinning, and immutable
  prompt/profile behavior after source maps change. The tests now drive the neutral provider at the
  model boundary and, for restart, kill the Agent Runtime Session so the existing one-for-all graph
  replacement is exercised. No production behavior changed.
- The four focused scenarios pass. Two random-seed complete runs exposed the remaining legacy Jido
  successive-tool test intermittently observing only one of two completion events; that unchanged
  test passed in isolation, and the complete Call Engine suite passed at seed `365486` with 244 tests
  and 2 integration exclusions. Removing that obsolete compatibility surface remains part of this
  milestone rather than masking it in the new runtime tests.
- Checkpoint 4t removes the final Jido test API usage from the 18-scenario definition-driven room
  suite. The archive-outage scenario now proves that Agent Runtime tool execution, live inspection,
  Call Variables, and buffered archive recovery remain independent. The Call Variables scenario
  drives a default-blocking read worker, consumes its private result, starts a separate
  default-blocking update worker, and consumes that result before the final response. Both retain
  the existing room events and archive snapshot attribution.
- The two focused scenarios, the complete definition-driven suite, and the complete Call Engine
  suite pass; the latter reports 244 tests with 2 integration exclusions at seed `365486`. The
  definition-driven module no longer imports or references Jido. Legacy unit and tagged integration
  tests plus the temporary test configuration still remain before dependency removal. Umbrella
  format, warnings-as-errors compilation, strict Credo, and unused-lock checks pass. Umbrella
  `mix test` stops before test execution because PostgreSQL SCRAM authentication needs a password
  absent from this shell; no credential source was inspected.
- Checkpoint 4u removes five Jido-only compatibility tests after mapping their contracts to neutral
  replacements. Activation-owned instruction/tool pinning and one-for-all lifecycle are covered by
  the Agent Runtime activation test; exact variable schemas and private bindings are covered by the
  descriptor compiler; ordered multiple-call submission and acknowledgement are covered by the
  standalone runtime; and room tests cover independent workers plus accepted/completed projection.
  No production behavior changed and no coverage unique to the selected runtime was removed.
- The focused migration set passes 54 tests and the complete Call Engine suite passes 239 tests with
  2 integration exclusions at seed `365486`. Jido references remain in the compatibility activation,
  coordinator event fixture, request transformer, and tagged provider test, so dependencies are not
  removed yet. Umbrella format, warnings-as-errors compilation, strict Credo, and unused-lock checks
  pass. Umbrella `mix test` stops before test execution at the unchanged absent PostgreSQL SCRAM
  password; no credential source was inspected.
- Checkpoint 4v migrates participant-owned activation lifecycle tests to the Agent Runtime graph and
  removes the duplicate Jido activation restart scenario. The participant boundary now proves that
  its `:session` child is owned, stopped with the participant, replaced once as part of the complete
  one-for-all graph, and ends only that participant subtree when the restart budget is exhausted.
  Invalid readiness also checks only the new coordinator/session/invocation roles.
- The focused activation/participant suite passes 5 tests and the complete Call Engine suite passes
  238 tests with 2 integration exclusions at seed `365486`. The activation's isolated remote-MCP
  ownership scenario remains on the compatibility graph pending its next-milestone runtime adapter.
  Umbrella format, warnings-as-errors compilation, strict Credo, and unused-lock checks pass.
  Umbrella `mix test` stops before test execution at the unchanged absent PostgreSQL SCRAM password;
  no credential source was inspected.
- Checkpoint 4w moves both the deterministic room fixture and the Morse end-to-end speech fixture
  from Jido request options to `Diagnostics.AgentRuntimeModelProvider`. `PlanStartup` now receives the
  same provider configuration shape used by the development sample, and the fixture-turn test retains
  success, unavailable, and malformed-output evidence through the complete room path.
- The migration exposed one classification mismatch: Agent Runtime flattened the provider's bounded
  `invalid_provider_response` into `provider_unavailable`. The package now preserves that one safe
  known category while still hiding every arbitrary provider reason. Red evidence was the room test
  receiving `provider_unavailable`; a new owning-boundary test and the room test now receive the
  intended invalid-response result. Agent Runtime passes 42 tests with 1 exclusion, and Call Engine
  passes 238 tests with 2 exclusions at seed `365486`. Umbrella format, warnings-as-errors
  compilation, strict Credo, and unused-lock checks pass. Umbrella `mix test` stops before test
  execution at the unchanged absent PostgreSQL SCRAM password; no credential source was inspected.
- Checkpoint 4x switches the test environment's application-selected implementation from Jido to
  Agent Runtime. Its named diagnostic fixture is supervised by the Call Engine application and is
  supplied through the neutral provider configuration, so non-inference room tests can start a
  valid activation while tests that exercise inference still select an explicit observer/fixture.
  The complete Call Engine suite passes 238 tests with 2 integration exclusions at seed `365486`.
  Only explicitly constructed compatibility tests can now start Jido. Umbrella format,
  warnings-as-errors compilation, strict Credo, and unused-lock checks pass. Umbrella `mix test`
  stops before test execution at the unchanged absent PostgreSQL SCRAM password; no credential
  source was inspected.
- Checkpoint 4y restores the coordinator's caller-interruption observability before retiring the
  compatibility coordinator. Cancelling active caller generation now emits the existing bounded
  `interrupted` capability failure and one model-stop telemetry event classified as `cancelled`;
  it emits no provider-failure event and still does not cancel independently supervised tools.
  Focused red evidence observed no capability failure or telemetry before the interruption boundary
  was updated.
- Runtime-neutral coordinator tests now also retain payload-free first-output/success telemetry and
  arbitrary-provider-failure normalization. The focused coordinator suite passes 16 tests, and the
  complete Call Engine suite passes 241 tests with 2 integration exclusions at seed `365486`.
  Umbrella format, warnings-as-errors compilation, strict Credo, and unused-lock checks pass.
  Umbrella `mix test` stops before test execution at the unchanged absent PostgreSQL SCRAM password;
  no credential source was inspected.
- Checkpoint 4z moves the bounded caller-queue/deadline contract to the neutral coordinator. With
  one queued slot, a third turn is rejected as `queue_full`; expiry terminates the active provider
  task, reports `provider_timeout`, and admits the queued turn without a stale result. The existing
  implementation passed the new owning-boundary test without production changes. The focused
  coordinator suite passes 17 tests and the complete Call Engine suite passes 242 tests with 2
  integration exclusions at seed `365486`. Umbrella format, warnings-as-errors compilation, strict
  Credo, and unused-lock checks pass. Umbrella `mix test` stops before test execution at the
  unchanged absent PostgreSQL SCRAM password; no credential source was inspected.
- Checkpoint 4aa proves two independently supervised non-blocking invocations may complete out of
  order and are serialized back into the agent exactly once with their original IDs. While the
  second completion is active, the first remains queued; after the second commits, the first is the
  next private continuation and both registry records are consumed.
- With streaming, failure recovery, deadlines, interruption, completion leasing, tool-worker
  survival, and out-of-order completion parity now owned by neutral tests, the legacy
  `AgentCoordinatorTest` compatibility suite is removed. The focused neutral coordinator suite
  passes 18 tests and the complete Call Engine suite passes 230 tests with 2 integration exclusions
  at seed `365486`; production compatibility modules remain until their final explicit consumers are
  removed. Umbrella format, warnings-as-errors compilation, strict Credo, and unused-lock checks
  pass. Umbrella `mix test` stops before test execution at the unchanged absent PostgreSQL SCRAM
  password; no credential source was inspected.
- Checkpoint 4ab removes the last test that explicitly starts the Jido activation graph. The deleted
  scenario coupled the old agent graph to a remote-MCP `IntegrationOwner`; live MCP exposure is the
  next milestone and remains rejected by current `PlanStartup`. MCP catalog, credential-lease,
  connection, result-bound, failure, and wire contracts remain covered in their owning suites. The
  Agent Runtime activation suite passes 2 tests and the complete Call Engine suite passes 229 tests
  with 2 integration exclusions at seed `365486`. Umbrella format, warnings-as-errors compilation,
  strict Credo, and unused-lock checks pass. Umbrella `mix test` stops before test execution at the
  unchanged absent PostgreSQL SCRAM password; no credential source was inspected.
- Checkpoint 4ac removes `Jido.Action` macros and dispatcher callbacks from every production host /
  Call Variables tool and from the corresponding test fixtures. They now implement only the
  project-owned `Tool.definition/0` and `Tool.execute/2` contract. Agent Runtime resolves their exact
  descriptors and every execution reaches `InvocationExecution` only inside an independently
  supervised worker; conversation blocking remains binding metadata rather than an execution path.
  The complete Call Engine suite passes 229 tests with 2 integration exclusions at seed `365486`.
  Umbrella format, warnings-as-errors compilation, strict Credo, and unused-lock checks pass;
  umbrella tests stop before execution at the unchanged absent PostgreSQL SCRAM password.
- Checkpoint 4ad removes Jido from the selected Call Engine supervision and startup path. A red
  application-boundary test first observed the global Jido child; it is no longer supervised.
  `PlanStartup.AgentActivation` now accepts only `:agent_runtime`, the activation supervisor can
  build only `RuntimeGraph`, and room authority routes start, stop, and interruption through the
  neutral coordinator without a runtime branch. Explicit `implementation: :jido` plan startup is
  rejected as unsupported. The focused startup/activation tests pass 6 tests, and the complete
  Call Engine suite passes 231 tests with 2 integration exclusions at seed `487487`. Umbrella
  format, warnings-as-errors compilation, strict Credo, and unused-lock checks pass. Umbrella
  `mix test` stops before execution at the unchanged absent PostgreSQL SCRAM password; no
  credential source was inspected. The now-unreachable Jido modules, legacy dispatcher, tests,
  dependencies, and lock entries remain for the following removal checkpoints.
- Checkpoint 4ae deletes the unreachable Jido agent, factory, request transformer, global runtime,
  runtime adapter, activation graph, and 799-line compatibility coordinator. It also removes the
  transformer's unit suite and the old tagged provider test; each retained selected-runtime
  behavior already has neutral Agent Runtime coverage recorded above. The complete Call Engine
  suite passes 226 tests with 1 integration exclusion at seed `410833`. One preceding run observed
  the existing Morse TTS interruption race as `audio_output_busy`; its focused rerun and the full
  rerun passed without changes. Umbrella format, warnings-as-errors compilation, strict Credo,
  and unused-lock checks pass. Umbrella `mix test` stops before execution at the unchanged absent
  PostgreSQL SCRAM password; no credential source was inspected. Legacy tool dispatcher modules and
  Jido dependency/lock entries remain for their own cleanup checkpoint.
- Checkpoint 4af deletes the unreachable dispatcher, dispatcher state, background supervisor,
  background invocation/completion protocol, and their compatibility suite. `ContinueAgent` now
  has one constructor for the authoritative `InvocationCompletion` protocol; the earlier
  background-completion shape cannot enter room authority. The current `Tool.Executor` is retained
  temporarily because the optional legacy text-only/model-inference preset still calls it; that
  remaining inline tool surface must be retired before claiming one universal worker path. The
  complete Call Engine suite passes 221 tests with 1 integration exclusion at seed `787975`.
  Umbrella format, warnings-as-errors compilation, strict Credo, and unused-lock checks pass.
  Umbrella `mix test` stops before execution at the unchanged absent PostgreSQL SCRAM password;
  no credential source was inspected.
- Checkpoint 4ag removes the last inline model-tool execution path. A red compatibility-capability
  test first observed an unsolicited tool request emitting `tool_started`; the retained legacy
  `CreateRoom` model-inference preset is now text-only, always advertises an empty tool list, and
  classifies buffered or streamed tool responses as invalid without executing or publishing a tool
  lifecycle. The orphaned generic `Tool.Executor` and its tests are deleted. Current tool-enabled
  definition-driven calls therefore have one execution path: Agent Runtime submits every accepted
  invocation to an independently supervised Call Engine worker. Focused legacy capability/room
  coverage passes 16 tests; the complete Call Engine suite passes 215 tests with 1 integration
  exclusion at seed `678417`. The Call Engine README, architecture history, and tool-execution
  decision now distinguish the selected runtime from the text-only compatibility preset. Umbrella
  format, warnings-as-errors compilation, strict Credo, and unused-lock checks pass. Umbrella
  `mix test` stops before execution at the unchanged absent PostgreSQL SCRAM password; no credential
  source was inspected.
- Checkpoint 4ah removes direct `jido_ai` and `jido_action` dependencies from Call Engine and prunes
  Jido plus eleven other now-unreachable lock entries. Dependency resolution retains ReqLLM in
  the standalone Agent Runtime and the legacy text-only provider adapter without reintroducing Jido.
  Agent Runtime passes 42 tests with 1 integration exclusion. After one 25 ms compatibility timeout
  observation raced the test process, its focused rerun and the complete Call Engine rerun passed;
  the latter reports 215 tests with 1 integration exclusion at seed `981844`. Umbrella format,
  warnings-as-errors compilation, strict Credo, and unused-lock checks pass. Umbrella `mix test`
  stops before execution at the unchanged absent PostgreSQL SCRAM password; no credential source
  was inspected. Rendered sample and final acceptance evidence remain before milestone completion.

## Specification review

Locally reviewed during planning for dependency direction, SRP, supervision ownership,
tool/privacy authority, failure bounds, migration safety, and a runnable vertical outcome.
No independent review or implementation evidence is claimed.
