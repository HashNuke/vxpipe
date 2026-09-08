# Definition-driven one-agent call

Status: implementation in progress. Typed definition/compiler checkpoints completed
on 2026-09-08; runtime startup and Jido integration remain. Specification review:
approved, including the Jido integration follow-up (2026-09-08).
Prerequisites: none; start from the existing runnable umbrella.
Sources: [Canonical representation and minimal definition](../../labnotes/20260905-0405-call-definition-design.md#canonical-representation); [entry participants](../../labnotes/20260905-0405-call-definition-design.md#entry-participants-and-startup--approved-g2-decisions); [Jido evaluation](../../labnotes/20260908-1344-jido-ai-evaluation.md); [R47](../call-definition-gap-review.md).

## Runnable outcome

A trusted embedded host loads a definition with a web caller and one receiving agent,
starts a room from its pinned plan, and completes the existing text/audio exchange and a
small host-tool call through Jido AI in the sample. Editing the source definition afterward
cannot change that live call.

## Specification

- Add engine-owned typed constructors for `CallDefinition`, participant/connection/capability selections, `CallInvocation`, and `ResolvedCallPlan`; ordinary Elixir input and JSON decoding converge on the same validation. Raw JSON maps never become room state.
- Use the date-based `YYYYMMDD.NN` schema-version contract. Keep resource ID/revision distinct from schema version. Choose/document the first implemented schema release during implementation; the labnote's representative JSON is a candidate, not a released schema.
- Require different existing string refs `entry_caller` and `entry_receiver` into `participants`; participant kind is human or agent. Initially run the web-caller/agent-receiver path. Do not activate the entire catalog. Keep definition key, runtime participant ID, connection ID, and fresh activation ID distinct.
- Resolve prompts, capability defaults/overrides, and supported provider options once before live startup. Provider configuration stays separate from engine interruption/duration policy. Pin the resulting immutable plan; live orchestration must not consult mutable definitions.
- Replace the current custom ReqLLM model/tool iteration process with one
  `Jido.AI.Agent`/AgentServer per active agent-participant activation. Start it through the
  participant subtree's owning supervisor and terminate it with that activation. Jido owns
  only the agent's conversation context, serialized ReAct request lifecycle, registered
  actions, and its internal request tasks; it is not a room, participant, media, transfer,
  variables, persistence, or client-protocol authority. This replaces one coherent Vxpipe
  capability layer rather than adding a second participant lifecycle.
- Define a finite application-owned Jido agent module and configure each activation from
  the pinned plan before declaring it ready: initialize the selected model and context,
  set the resolved system prompt, register the supported action modules, and pass private
  execution context only at the request/action boundary. Use Jido's public APIs; do not
  generate modules from definition input or mutate a ready agent piecemeal.
- An engine-owned coordinator serializes external and internal turns and maps Jido request
  handles/events into Vxpipe request/turn/participant identities, output pacing,
  interruption, visibility, and usage. Configure Jido request policy to reject overlapping
  asks and configure automatic tool retries to zero; the coordinator, not Jido concurrency,
  owns the voice turn queue. Standalone ReAct may be used in isolated adapter tests, but it
  is not a separate production loop beside the per-activation AgentServer.
- Constructors return path-specific errors. Closed registries map public strings to allowed implementations; no external atom/module/function creation, executable expressions, or credentials in the public plan or public errors.
- Generate each agent's enabled tool surface from one local-key `tools` map. Express
  supported registered platform/host bindings as Jido Actions while their handlers retain
  Vxpipe authorization and process boundaries. Reserve transfer derivation for the
  agent-transfer slice and remote bindings for the remote-MCP slice. Reject alias collisions
  with reserved/compiler-generated names. Unsupported enabled tools/features fail
  explicitly, never disappear silently. Empty transfer possibilities expose no transfer tool.
- The first supported subset uses finite static Actions whose local tool keys equal their
  declared Action names. Reject differing aliases before startup until the public binding
  interface in [the decision](../jido-tool-execution.md) is available. Current Jido AI loses
  map aliases when constructing model tools; do not silently rename or generate modules.
  This temporary rollout restriction does not remove aliases from the final definition
  contract. The live-MCP slice owns the general runtime-binding interface gate.
- Invocation cannot replace the definition's entry refs or the trusted tenant identity.
- Reuse current room, gateway, model, STT, TTS, and sample components. Preserve existing runtime speech/interruption behavior. This milestone's trusted startup adapter is not the production API-key/token path built in the prepared-call admission slice.

## Implementation checklist

- [x] Write failing constructor/compiler tests for entry refs, schema version, participant identity, unsupported fields/options, secret-safe errors, and plan pinning.
- [x] Implement the minimal typed compiler and JSON/Elixir parity for the supported one-agent subset.
- [ ] Red-test the per-activation Jido AgentServer/coordinator against the existing stream,
  tool, timeout, teardown and interruption contracts; add compatible Jido AI/Jido Action
  dependencies and lockfile.
- [ ] Route ordinary agent inference and one small host action through the supervised Jido
  agent, with overlapping asks rejected, automatic tool retries disabled, and tool
  concurrency chosen explicitly.
- [ ] Route room startup through the compiled plan and resolve only needed initial participants/capabilities.
- [ ] Wire one trusted sample/embedded fixture to the new path without redesigning the responsive console.
- [ ] Specify supported-feature diagnostics for later milestone features; reject enabled unsupported privacy/connection/tool settings before starting providers.
- [ ] Refactor duplicated preset configuration only after the definition-driven sample tests pass.

## Acceptance and failure checks

- [ ] Missing/identical/unknown/non-string entry refs fail before room/provider start; unused catalog entries start no processes or dials.
- [ ] Invocation attempts to replace entry refs or tenant identity fail; authored aliases that collide with reserved/generated tools fail before startup.
- [ ] Equivalent Elixir and JSON definitions normalize identically; unknown schema versions and unsupported provider combinations fail clearly.
- [ ] One call has one participant per definition key; no cross-call shared runtime identities.
- [ ] Change a source definition/profile after start: the active room retains its original resolved configuration.
- [ ] A forced provider startup failure cleans up the attempted tree without silently switching providers.
- [ ] One host action completes through Jido Action and the ReAct continuation without
  duplicate tool/text events; invalid input fails before the action handler runs.
- [ ] A deterministic request completes two successive tool rounds and a final response
  through Jido's loop, with no engine-owned replacement model/tool loop. Tool names shown
  to the model match accepted definition keys; unsupported aliases fail before startup.
- [ ] Jido stream cancellation maps to the existing interrupted turn without ending the
  participant or granting Jido authority over room lifecycle. Configured tool retries are
  zero, and a stale event from a terminated activation cannot reach its replacement.
- [ ] Kill the Jido process: its participant supervisor applies the declared restart policy
  without restarting the room. Commit a transfer or end the participant: the Jido process
  and its request-task subtree terminate without orphaned work or speech.
- [ ] Existing text, speech recognition, streamed model/TTS output, and barge-in regression tests stay green.

## Manual verification

1. Load a synthetic caller/reception definition through the documented trusted host/sample adapter.
2. Join the existing sample console; exchange typed and spoken messages and invoke the
   synthetic host action once.
3. Change the configured prompt for a subsequent call and confirm the existing room keeps its original plan while a new room uses the new input.
4. Try an invalid entry ref and an unsupported provider option; inspect safe errors and confirm no orphan room/provider remains.

## Scope boundaries

No Ecto, public production admission, remote MCP, multi-party mixing, transfers, recording,
or new provider integration. This slice does not implement submitted background actions;
those remain in their own milestone. Reject rather than
pretend to support enabled runtime features. Tenant identity here is supplied by the trusted
host; client-supplied tenant strings do not establish authority.

## Completion and evidence

- [ ] Demonstrate the runnable outcome and every acceptance/failure check above.
- [ ] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [ ] Update this milestone, the index checkbox, relevant architecture/user docs, and
  implementation labnote with actual test/browser/integration evidence in the implementation commit.

Implementation evidence, checkpoint 1 (2026-09-08): released the first engine-owned
schema identifier, `20260906.02`, and added typed definition, participant, connection,
capability selection, invocation and resolved-plan structures. The pure compiler accepts
equivalent fixed-key Elixir/JSON maps, keeps definition ID/revision and tenant/actor
identity outside caller-controlled input, resolves profiles/tools only through closed
trusted registries, assigns fresh runtime identities, and returns path-specific errors
without rejected values. That first checkpoint accepted an empty variables object and
empty transfer lists.

Red: `mix test test/vxpipe/call_engine/call_definition/compiler_test.exs` from the
call-engine child failed while compiling the test because the first typed struct did not
exist. Green: the same focused command passed 7 tests. Full umbrella gate evidence is
recorded in the implementation labnote and commit. Do not mark this slice complete.

Implementation evidence, checkpoint 2 (2026-09-08): added typed Call Variables section
schemas, agent read/read+write grants, validated partial invocation values, and immutable
initial section state to the resolved plan. The released schema uses a closed JSON
Schema-shaped subset compiled by JSV 0.22 with casting and external references unavailable.
Variable defaults, unsupported schema keywords, malformed grants, unknown sections or
variables, and datatype violations fail with value-free paths before room startup.
Authored `required` lists remain in definition metadata but are removed only from the
runtime validator, including nested schema nodes, so iterative population does not invent
or require missing values. Explicit empty sections remain distinct from omitted sections.

Red: the focused Call Variables compiler test first failed to compile because
`CallDefinition.VariableSection` did not exist. A review-added malformed-`required` case
then failed because the initial validator relaxation accepted it; the closed schema compiler
fixed that defect. Green: the focused file passed 7 tests, and the original compiler file
passed 7 tests. Full umbrella evidence is recorded in the implementation labnote. Runtime
Call Variables ownership and tools remain milestone 4 work; milestone 1 remains incomplete.

## Specification review

Reviewed independently by milestone_review_a on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Added reserved/generated tool alias collision checks and invocation entry/tenant non-override. Re-review approved; first position correct.
The 2026-09-08 Jido follow-up found that public Jido MCP tool synchronization targets a
running `Jido.AI.Agent`, while standalone ReAct has no equivalent public synchronization
surface. The specification now uses one supervised AgentServer as the replaceable
per-agent inference layer, with explicit readiness, request serialization and teardown
boundaries. Focused source review approved this corrected mechanism. The later released-
package probe verified two ReAct rounds and exposed the static Action alias limitation;
the supported first-slice subset and runtime-binding gate now state that limitation.
AgentServer remains the lifecycle choice, no longer a dependency on Jido MCP synchronization.
This is specification evidence only; implementation and runtime verification remain unchecked.
