# Context compaction and fallback

## Scope

Implement milestone 22: bounded model-context compaction plus only the
provider-native routing/fallback configuration supported through ReqLLM. This
work must not introduce a Vxpipe-managed provider chain or give summarized text
tool, policy, variable, or permission authority.

## 2026-09-12 — budget boundary checkpoint

- Confirmed the active runtime already represents every input class in one
  normalized `ModelRequest`: committed/staged messages, tool definitions,
  unresolved invocation state, transient authorized call-variable projection,
  and request correlation. The token counter therefore receives this complete
  request rather than a partial history list.
- Added a focused `ContextBudget` value. Output capacity is reserved before
  calculating the usable input budget. The compaction trigger is the ceiling of
  75% of usable input; the strict below-50% target is
  `div(usable_input_tokens - 1, 2)`.
- Kept counting behind the separate `InputTokenCounter` contract and bounded it
  through `RequestBudget`. This avoids claiming that a generic character
  estimate is exact for every provider/model and keeps counting work outside
  the session process.
- Invalid/unavailable counters produce the typed
  `:input_token_count_unavailable` outcome. They never authorize a provider
  request with an unmeasured context.

Red evidence:

```text
cd apps/vxpipe_agent_runtime
mix test test/vxpipe/agent_runtime/context_budget_test.exs
# 5 tests, 5 failures: ContextBudget and RequestBudget were absent
```

Green evidence:

```text
cd apps/vxpipe_agent_runtime
mix test test/vxpipe/agent_runtime/context_budget_test.exs
# 5 tests, 0 failures
```

The first milestone checklist item remains open until a fake compactor consumes
the decision and proves replacement against realistic protected conversation
entries.

## 2026-09-12 — protected conversation checkpoint

- Added snapshot selection over committed `Conversation.Entry` values. Permanent
  system/transfer entries and a configurable recent tail are protected.
- Entries containing a tool call or result whose invocation ID is currently
  pending are protected as one relationship. Selection is a contiguous old
  prefix and therefore never reorders a summary around protected work.
- Replacement verifies the complete snapshotted prefix against current state.
  Entries appended after the snapshot are retained; a changed prefix returns
  `:stale_compaction_snapshot` without attaching the summary.
- A derived summary is structurally an assistant message with no tool calls or
  tool-result identity. Its fixed envelope identifies it as untrusted historical
  data with no instruction, policy, tool, variable, or permission authority.
- Compacted durable entries carry their prior correlations in the derived entry,
  preserving the existing interruption/recovery query without retaining their
  full model-facing text.

Red evidence:

```text
cd apps/vxpipe_agent_runtime
mix test test/vxpipe/agent_runtime/conversation_compaction_test.exs
# 5 tests, 5 failures: ConversationCompaction was absent
```

Green evidence:

```text
cd apps/vxpipe_agent_runtime
mix test test/vxpipe/agent_runtime/conversation_compaction_test.exs
# 5 tests, 0 failures
mix test
# 69 tests, 0 failures (2 excluded)
```

The selection/replacement primitive does not call a summarizer. The first
milestone checklist item remains open until one bounded fake-compactor attempt
is orchestrated and the final request is remeasured.

## 2026-09-12 — fake compactor orchestration checkpoint

- Added `ContextPreparation`, which measures the full normalized request and
  makes no compactor call below the threshold.
- A triggered attempt snapshots only eligible conversation entries, measures the
  protected request, and refuses to compact when protected/current content fills
  the usable input window.
- The `CompactionRequest` contains only selected authorized messages, their
  source correlations, the request correlation, and a maximum summary-token
  allowance. It has no tool definitions, pending invocation projection, Call
  Variables projection, executor, or other execution authority.
- The `ContextCompactor` callback runs once behind a bounded runner. Its result
  carries separately bounded summary text, observed usage, and safe provider
  metadata.
- After replacement, the entire model request is rebuilt with the unchanged
  tools, pending invocation state, transient variables, current work, and recent
  messages, then measured again. If an achievable below-half target is missed,
  the result is rejected as `:compacted_context_too_large`.
- Failures return the original immutable conversation to the caller; no partial
  compacted state is committed.

Red evidence:

```text
cd apps/vxpipe_agent_runtime
mix test test/vxpipe/agent_runtime/context_preparation_test.exs
# 5 tests, 5 failures: ContextPreparation and CompactionResult were absent
```

Green evidence:

```text
cd apps/vxpipe_agent_runtime
mix test test/vxpipe/agent_runtime/context_preparation_test.exs
# 5 tests, 0 failures
mix test
# 74 tests, 0 failures (2 excluded)
```

The first implementation checklist item is now complete. The production
summarizer/model selection, conservative token accounting, and runtime-session
integration remain open.

## 2026-09-12 — production selection and accounting checkpoint

- Inspected the locked ReqLLM 1.22 and LLMDB surfaces. ReqLLM exposes model
  context/output limits and provider option validation, but no exact local input
  tokenizer covering every provider.
- Selected the active activation's same pinned provider, model, credential, and
  native routing configuration for summary work. The compactor cannot silently
  select another configured model or recipient.
- Added conservative input accounting over messages/tool relationships, exact
  tool schemas, pending invocation state, and transient model context. It charges
  encoded UTF-8 bytes plus fixed base/message/tool envelope margins; request
  correlation is correctly excluded because it is not model input.
- The production `ModelContextCompactor` projects selected history into JSON data
  under fixed summary-only instructions and calls the pinned provider with no
  tools, pending state, or model context. Any returned tool call is rejected.
- Added a per-request maximum-output token field so the summary allowance reaches
  the ordinary ReqLLM adapter without changing the pinned provider configuration.
- ReqLLM configuration now forces unsupported-option validation to error. A
  supported Zenmux provider-routing fallback is retained; the same provider
  option on Google is rejected before I/O.
- Recorded the complete decision, limits, rejected alternatives, and remaining
  verification in `docs/context-compaction.md`.

Red evidence:

```text
cd apps/vxpipe_agent_runtime
mix test test/vxpipe/agent_runtime/conservative_input_token_counter_test.exs \
  test/vxpipe/agent_runtime/model_context_compactor_test.exs \
  test/vxpipe/agent_runtime/provider/req_llm_test.exs
# 9 tests, 7 failures: counter/compactor/output projection and validated metadata absent
```

Green evidence:

```text
cd apps/vxpipe_agent_runtime
mix test test/vxpipe/agent_runtime/conservative_input_token_counter_test.exs \
  test/vxpipe/agent_runtime/model_context_compactor_test.exs \
  test/vxpipe/agent_runtime/provider/req_llm_test.exs
# 9 tests, 0 failures
mix test
# 79 tests, 0 failures (2 excluded)
```

The second implementation checklist item is complete. Runtime configuration,
Session/RequestRunner preparation, compaction lifecycle events, and privacy-safe
usage projection remain open.

## 2026-09-12 — Agent Runtime session checkpoint

- Added a cohesive `CompactionConfiguration` boundary instead of expanding
  `SessionConfiguration` with provider-specific logic. It resolves explicit
  trusted overrides or optional provider-reported context/output limits, validates
  counter/compactor callbacks, and applies the decided 4-entry/1-second/15-second
  defaults.
- Added optional provider limit callbacks. The ReqLLM adapter exposes only its
  already validated config metadata; other providers must supply explicit trusted
  limits or remain unable to enable compaction.
- `RequestRunner` now prepares context before every conversational inference and
  tool-continuation round. A successful compaction is committed to the owning
  Session before the ordinary provider request; a failed later inference therefore
  cannot restore the oversized history.
- The existing active-token commit callback remains the attachment boundary. An
  old task cannot commit into another request/session generation.
- Confirmed that stopping the Session while its fake compactor is blocked also
  terminates that linked compaction task. No stale summary worker survives its
  activation.

Red evidence:

```text
cd apps/vxpipe_agent_runtime
mix test test/vxpipe/agent_runtime/session_compaction_test.exs
# 2 tests, 2 failures: context_compaction was rejected by Session configuration
```

Green evidence:

```text
cd apps/vxpipe_agent_runtime
mix test test/vxpipe/agent_runtime/session_compaction_test.exs
# 2 tests, 0 failures
```

The third checklist item remains open until Call Engine passes the application
settings into each activation and a queued user/tool completion is proven to
survive the compaction interval.

## 2026-09-12 — Call Engine activation checkpoint

- Passed the application-level `context_compaction` setting through plan startup
  and the activation runtime graph into each Agent Runtime Session. The base
  setting is disabled; development enables it with provider-derived limits for
  ReqLLM and explicit conservative limits for the deterministic fixture.
- Added a room-level test with a controllable token counter and buffered summary
  response. Two completed exchanges establish history, the third turn triggers
  compaction, and a fourth caller turn is explicitly queued while the summary is
  blocked.
- The queued turn runs only after the compacted conversation has been committed.
  Both the triggering request and queued request contain the derived summary.
- The first red attempt accidentally used `SendText`'s default
  `run_immediately: true`; that correctly interrupted and killed the active
  compaction request. Setting `run_immediately: false` exercised the intended
  existing queue contract without changing interruption semantics.

Red evidence:

```text
cd apps/vxpipe_call_engine
mix test test/vxpipe/call_engine/agent_runtime/context_compaction_room_test.exs
# 1 test, 1 failure: Call Engine did not pass context_compaction into the Session
```

Green evidence:

```text
cd apps/vxpipe_call_engine
mix test test/vxpipe/call_engine/agent_runtime/context_compaction_room_test.exs --trace
# 1 test, 0 failures
mix test
# 398 tests, 0 failures (1 excluded)
```

The third milestone checklist item is complete. Summary usage events and
runtime-only summary privacy are the next checkpoint.

## 2026-09-12 — Private summary and usage checkpoint

- Kept derived summaries entirely inside the owning Agent Runtime Session and
  subsequent model requests. No summary text or selected source message is sent
  through runtime events, client projection, or archive handoff; the original
  permitted transcript facts remain untouched.
- Added a bounded `context_compaction_usage` runtime event containing only
  usage, safe provider metadata, and outcome. Call Engine projects it as a
  separate model attempt attributed to the triggering real turn with
  `context_compaction_input_tokens`, `context_compaction_output_tokens`,
  `context_compaction_total_tokens`, or an unmeasured
  `context_compaction_operation`.
- Added the focused `CompactionUsage` coordinator module rather than mixing a
  second attempt lifecycle into conversational `ModelUsage` tracking.
- A valid accepted summary reports a successful attempt. A tool-calling,
  malformed, or still-oversized response reports a failed attempt and preserves
  known incurred usage/provider identifiers. A compactor attempt that returns no
  measurement reports a failed operation; budget failures before any model call
  create no observation.
- Extended the room/archive test to acknowledge its initial Variables baseline,
  retain the original first caller and agent transcript facts, observe the
  separately named compaction usage, and prove a unique summary sentinel appears
  in no archived payload.

Red evidence:

```text
cd apps/vxpipe_agent_runtime
mix test test/vxpipe/agent_runtime/session_compaction_test.exs
# 1 failure: no context_compaction_usage event

cd apps/vxpipe_call_engine
mix test test/vxpipe/call_engine/usage/model_projection_test.exs \
  test/vxpipe/call_engine/agent_runtime/coordinator_test.exs
# 2 failures: compaction purpose/event projection was unsupported

cd apps/vxpipe_agent_runtime
mix test test/vxpipe/agent_runtime/session_compaction_test.exs \
  test/vxpipe/agent_runtime/context_preparation_test.exs \
  test/vxpipe/agent_runtime/model_context_compactor_test.exs
# compilation failed because CompactionObservation did not exist

mix test test/vxpipe/agent_runtime/context_preparation_test.exs
# 5 tests, 1 failure: an attempted compactor failure had no observation
```

Focused green evidence:

```text
cd apps/vxpipe_agent_runtime
mix test test/vxpipe/agent_runtime/session_compaction_test.exs \
  test/vxpipe/agent_runtime/context_preparation_test.exs \
  test/vxpipe/agent_runtime/model_context_compactor_test.exs
# 10 tests, 0 failures

cd apps/vxpipe_call_engine
mix test test/vxpipe/call_engine/agent_runtime/coordinator_test.exs \
  test/vxpipe/call_engine/usage/model_projection_test.exs \
  test/vxpipe/call_engine/agent_runtime/context_compaction_room_test.exs
# 27 tests, 0 failures

mix test
# 401 tests, 0 failures (1 excluded)

cd ../..
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
# all pass; Credo checked 801 source files with no issues
mix deps.unlock --check-unused
# exit 0
```

The fourth milestone checklist item is complete. Provider-native fallback
controlled and tagged coverage is the remaining implementation checkpoint.

## 2026-09-12 — controlled native-routing checkpoint

- Added a controlled ReqLLM/Zenmux adapter test using `Req.Test`. The single
  observed HTTP request contains the configured provider-native routing/fallback
  object and exact tool JSON Schema while omitting private executor correlation.
- The controlled provider response names a routed model different from the
  requested primary; normalization retains that actual model and reported token
  usage rather than substituting the configured model.
- Added a Session-level partial-stream failure characterization. After one text
  delta, an upstream failure produces `:provider_unavailable` without a second
  stream request, buffered generation, or tool submission.
- Added a separately tagged live Zenmux interoperability test. It requires
  `ZENMUX_API_KEY`, optionally reads `VXPIPE_ZENMUX_MODEL`, sends native routing
  plus an exact tool schema, and checks non-empty model/usage observations. It is
  excluded from the default suite.
- `Req.Test` needs Plug at runtime, so `vxpipe_agent_runtime` now declares Plug
  as a test-only direct dependency. The lockfile is unchanged because the
  umbrella already locked the dependency.
- The first controlled attempt failed before reaching the stub because Plug was
  only a transitive dependency of another umbrella child. After adding the
  direct test dependency, it reached the adapter and exposed the authoritative
  Zenmux path as `/api/v1/chat/completions`, which the test now verifies.

Green evidence:

```text
cd apps/vxpipe_agent_runtime
mix test test/vxpipe/agent_runtime/streaming_test.exs \
  test/vxpipe/agent_runtime/provider/req_llm_native_routing_test.exs --trace
# 6 tests, 0 failures

mix test
# 84 tests, 0 failures (3 excluded)

mix test test/integration/req_llm_native_routing_test.exs
# 0 tests, 0 failures (1 excluded)
```

`ZENMUX_API_KEY` is unset in this workspace, so the live provider request was
not run. Configured call-profile pass-through remains before the final milestone
checklist item can be marked complete.

## 2026-09-12 — configured model-profile checkpoint

- Confirmed the remaining exposure gap: application-wide Agent Runtime options
  could configure native routing, but a pinned model capability profile could
  carry only its model. Direct adapter coverage alone did not make per-profile
  routing usable by a compiled call plan.
- Added the cohesive `PlanStartup.AgentModelProfile` boundary. It accepts only
  the closed profile keys `model` and `generation_options`, merges profile
  generation values over application defaults, and calls the configured model
  provider constructor before room startup.
- Credentials, streaming mode, controlled test transport, and other provider
  constructor settings remain application-owned. The model profile contributes
  only recursively data-valued generation settings, with no executable hook,
  module tuple, process, or credential selector.
- A real ReqLLM configuration test proves a Zenmux profile retains an
  application timeout, overrides an application temperature, and carries the
  native routing/fallback object. A Google profile with the same unsupported
  provider option rejects the call plan.
- A regression run exposed that always injecting `generation_options: []`
  changed the constructor contract for profiles and test providers that did not
  configure generation options. The merger now omits that key unless the
  application or selected profile actually supplied it.

Red evidence:

```text
cd apps/vxpipe_call_engine
mix test test/vxpipe/call_engine/plan_startup/agent_model_profile_test.exs --trace
# 2 tests, 1 failure: the existing model-only profile restriction rejected routing options

mix test test/vxpipe/call_engine/definition_driven_call_test.exs --max-failures 1
# 1 test, 1 failure: synthetic empty generation options broke the existing test provider

mix test test/vxpipe/call_engine/plan_startup/agent_model_profile_test.exs --trace
# 3 tests, 1 failure: ReqLLM accepted an executable output-repair callback from the profile
```

Green evidence:

```text
cd apps/vxpipe_call_engine
mix test test/vxpipe/call_engine/plan_startup/agent_model_profile_test.exs \
  test/vxpipe/call_engine/definition_driven_call_test.exs
# 28 tests, 0 failures

mix test
# 404 tests, 0 failures (1 excluded)
```

The fifth implementation checklist item is complete. The milestone acceptance
matrix, root gates, and runnable cross-slice evidence remain to audit before
claiming milestone completion. The tagged Zenmux request remains unrun because
its credential is unavailable.

## 2026-09-12 — acceptance hardening checkpoint

- Audited the milestone acceptance sentences against focused tests rather than
  treating implementation checkboxes as completion evidence.
- Generic compactor-error coverage did not directly prove the timeout and
  malformed-return cases. Added both: a timed-out compactor worker is killed,
  and both outcomes return an unmeasured failed observation with the original
  conversation unchanged.
- Existing snapshot coverage retained appended user/assistant work but did not
  explicitly carry a late tool relationship. Added a snapshot-application test
  that retains both the appended assistant tool call and its matching tool
  result ID.
- Together with pending-tool protection, Call Engine's queued-caller
  remeasurement, and termination of the Session-owned compactor, these tests
  close the current-work/stale-activation and summary-failure acceptance rows.

Verification:

```text
cd apps/vxpipe_agent_runtime
mix test test/vxpipe/agent_runtime/context_preparation_test.exs \
  test/vxpipe/agent_runtime/conversation_compaction_test.exs --trace
# 13 tests, 0 failures

mix test
# 87 tests, 0 failures (3 excluded)
```

No production change was required; the existing bounded runner and atomic
snapshot replacement already satisfied the newly explicit cases.

## 2026-09-12 — rendered acceptance transfer regression

- During milestone acceptance, the first ordinary typed RTVI turn completed over the live HTTPS
  WebRTC sample, but requests for human support produced no assistant row. Subsequent ordinary
  typed turns still completed, disproving the initial suspicion that caller-idle handling or the
  data channel had become stuck.
- Captured the browser's actual outbound data-channel frame. It contained one valid RTVI
  `send-text` request with the expected content and open `chat` channel. Browser protocol logs then
  showed the matching correlated `error-response`; a fresh call reproduced the same result before
  any idle notification.
- Isolated the distinguishing contract to the development sample's mixed transfer schema: billing
  accepts only `destination`, while human support also requires `reason`. Separate historical
  provider checks had covered ordinary and reason-required schemas, but not their combined
  top-level `oneOf`.
- Added the exact mixed schema to the tagged Agent Runtime provider lane. The red run returned a
  `transfer` call with empty arguments, proving the provider projection—not room admission or
  transport state—caused the visible failure.
- Replaced the model-visible combinator with one flat object containing a closed destination enum
  and a reason property that identifies its applicable destinations. The property is schema-required
  only when every allowed target needs a reason. The private Call Engine request remains the
  authority boundary and still enforces the exact per-destination argument shape.
- Replayed a fresh room through the HTTPS/WebRTC sample after the dev reloader applied the fix. The
  same request now showed `Function call (transfer)`, followed by the source agent's spoken hold
  response; no correlated error was emitted.

Red evidence:

```text
cd apps/vxpipe_agent_runtime
mix test --include integration test/integration/req_llm_provider_test.exs:82 --trace
# 1 test, 1 failure: provider returned transfer arguments %{}

cd ../vxpipe_call_engine
mix test test/vxpipe/call_engine/call_definition/agent_transfer_compiler_test.exs:276 --trace
# 1 test, 1 failure: generated schema still used top-level oneOf
```

Green evidence:

```text
cd apps/vxpipe_call_engine
mix test test/vxpipe/call_engine/call_definition/agent_transfer_compiler_test.exs --trace
# 13 tests, 0 failures

cd ../vxpipe_agent_runtime
mix test --include integration test/integration/req_llm_provider_test.exs:82 --trace
# 1 test, 0 failures: populated human-support destination and non-empty reason
```

## 2026-09-12 — final acceptance and review hold

- Audited every milestone acceptance sentence against focused tests. The
  accepted summary cannot carry tools, tool results, execution hooks, Variables,
  or permission authority; the original permitted archive stays intact and the
  summary sentinel remains runtime-private.
- The controlled native-routing request preserves its exact tool schema and
  private-executor boundary, retains the actual routed model and reported usage,
  and never retries a partial stream. The separately tagged live Zenmux lane is
  still excluded because `ZENMUX_API_KEY` is not configured.
- Exercised an unmodified RTVI 1.13.0 client over the default HTTPS/WebRTC stack.
  It reached READY, completed an ordinary typed text/audio turn, and exposed the
  exact mixed-transfer schema regression described above. After the schema fix,
  a fresh call projected the transfer function call and the source agent's
  hold/recovery responses without a correlated protocol error.
- Rechecked the connected conversation at 390 x 844. The Voice UI Kit switches
  to its mobile tabs cleanly, the complete tool and recovery exchange remains
  readable, and document/body width stays 390 pixels with no horizontal
  overflow.
- The rendered audit still reports inaccessible third-party icon/tab controls,
  third-party contrast failures, and the Vxpipe playground shell's missing
  level-one heading. Preserved that debt in
  `docs/issues/sample-voice-ui-accessibility.md`; no unrelated UI was changed
  during this runtime milestone.
- The separate transfer desk could not connect in this run because the
  development BEAM had no database URL and therefore did not enable durable
  sample calls. This run claims the model/tool/protocol path only; the owning
  human-transfer milestone already contains database-backed destination proof.

Final verification:

```text
cd apps/vxpipe_agent_runtime
mix test test/vxpipe/agent_runtime/context_budget_test.exs \
  test/vxpipe/agent_runtime/context_preparation_test.exs \
  test/vxpipe/agent_runtime/conversation_compaction_test.exs \
  test/vxpipe/agent_runtime/model_context_compactor_test.exs \
  test/vxpipe/agent_runtime/session_compaction_test.exs \
  test/vxpipe/agent_runtime/provider/req_llm_test.exs \
  test/vxpipe/agent_runtime/provider/req_llm_native_routing_test.exs \
  test/vxpipe/agent_runtime/streaming_test.exs --trace
# 34 tests, 0 failures

cd ../vxpipe_call_engine
mix test test/vxpipe/call_engine/agent_runtime/context_compaction_room_test.exs \
  test/vxpipe/call_engine/plan_startup/agent_model_profile_test.exs \
  test/vxpipe/call_engine/agent_transfer_room_test.exs \
  test/vxpipe/call_engine/usage/model_projection_test.exs --trace
# 19 tests, 0 failures

cd ../..
mix assets.build
# TypeScript check and esbuild production asset build pass
mix assets.test
# 3 files, 7 tests, 0 failures
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
# 802 source files, no issues
mix deps.unlock --check-unused
VXPIPE_TEST_DATABASE_URL=postgres://postgres:postgres@127.0.0.1:55433/vxpipe_test mix test
# exit 0; all default umbrella child suites pass
```

Milestone 22 is complete. The ordered index now pauses at the requested
pre-delivery platform review before container delivery or retention work.
