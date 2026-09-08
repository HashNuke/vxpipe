# Definition-driven one-agent call

Status: implementation in progress. Typed definition/compiler, participant-owned Jido
routing, plan-selected speech startup, and trusted sample wiring checkpoints completed on
2026-09-08. All implementation checklist checkpoints are complete; acceptance and final
spoken-sample evidence remain.
Specification review: approved,
including the Jido integration follow-up (2026-09-08).
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
- [x] Red-test the per-activation Jido AgentServer/coordinator against the existing stream,
  tool, timeout, teardown and interruption contracts; add compatible Jido AI/Jido Action
  dependencies and lockfile.
- [x] Route ordinary agent inference and one small host action through the supervised Jido
  agent, with overlapping asks rejected, automatic tool retries disabled, and tool
  concurrency chosen explicitly.
- [x] Route room startup through the compiled plan and resolve only needed initial participants/capabilities.
- [x] Wire one trusted sample/embedded fixture to the new path without redesigning the responsive console.
- [x] Specify supported-feature diagnostics for later milestone features; reject enabled unsupported privacy/connection/tool settings before starting providers.
- [x] Refactor duplicated preset configuration only after the definition-driven sample tests pass.

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

Implementation evidence, checkpoint 3a (2026-09-08): added compatible direct
`jido_ai` 2.3 and `jido_action` 2.3 dependencies, an application-owned Jido instance,
the finite Vxpipe Agent module, and a synchronous AgentServer configuration barrier.
Resolved prompts and supported static Actions are set through public Jido APIs before
the activation can be declared ready. Automatic Action retries are zero. Static Actions
delegate actual host execution to a per-activation Vxpipe dispatcher GenServer, making
handler execution serial even though the current Jido Agent configuration surface does
not propagate a tool-concurrency option.

Red: `mix test test/vxpipe/call_engine/agent_test.exs` first failed to compile because
`Jido.AI.Test` was unavailable. The first runtime attempt then exposed a missing
application-owned Jido supervisor, and the next exposed that struct-level tool setup is
reinitialized at AgentServer startup. Starting the Jido instance and moving setup to
synchronous public AgentServer calls resolved those integration boundaries. Green: the
focused file passed 2 tests, including two successive host-Action rounds and one final
answer through Jido's real delegated ReAct worker. Coordinator stream, timeout,
interruption, and activation teardown contracts remain unchecked, so neither runtime
implementation task nor the milestone is complete.

Implementation evidence, checkpoint 3b (2026-09-08): added the engine-owned
`AgentCoordinator` and a narrow `AgentRuntime` boundary. The coordinator accepts one active
request, bounds pending turns and response bytes, attaches private Vxpipe command/request
refs and authorized tool context, translates Jido sentence/tool/terminal events onto the
existing capability messages, and ignores stale events after cancellation. Timeout and
interruption cancel the correlated Jido request. Interrupted completed request IDs are
excluded from every later model projection by an engine-owned request transformer; the
adapter additionally requests physical context replacement without relying on its possibly
deferred application. The production adapter uses Jido AgentServer request, cancel and
context APIs rather than implementing an engine-side provider/tool loop.

Red: the focused coordinator suite failed all three initial cases because
`Vxpipe.CallEngine.AgentCoordinator` did not exist. Green/refactor: the suite now passes
five tests, including bounded timeout/queue behavior, an oversized terminal-response race,
interruption/context discard, stream/tool projection, and one real Jido host-Action round.
The complete engine suite passes 87 tests with one network integration test excluded.
Umbrella gates pass: formatting, warnings-as-errors, call engine `87 tests, 0 failures
(1 excluded)`, gateway `37 tests, 0 failures (3 excluded)`, and no unused dependencies.
Participant-owned startup/teardown and room routing remain unchecked, so the corresponding
runtime checklist items and the milestone stay incomplete.

Implementation evidence, checkpoint 3c (2026-09-08): added a named, temporary
`AgentActivationSupervisor` that starts the serialized host dispatcher, Jido AgentServer,
and coordinator under a one-for-all policy. Coordinator initialization is the synchronous
prompt/Action configuration barrier, so successful supervisor startup means the activation
is ready. One abnormal child failure restarts and reconfigures the entire set; a second
failure within the five-second window terminates the activation and all children. Failed
initial configuration also cleans up previously started siblings and their registrations.

Red: the focused activation suite failed both initial cases because the supervisor did not
exist. The first implementation then failed readiness because coordinator validation only
accepted a dispatcher PID, not the named `GenServer.server()` reference used by supervision;
validating the resolved registered processes fixed that boundary. Green: the focused suite
passes two lifecycle cases. A repeated coordinator run then exposed out-of-order Jido tool
events and deferred context modification. The coordinator now buffers early tool results,
waits for observed tool lifecycles before terminal completion, deduplicates event IDs, and
uses a separately red-tested projection filter for interrupted request IDs. Twenty repeated
coordinator runs passed after that correction; the combined Agent/Coordinator/Activation/
Transformer tests pass eleven tests. This completes the runtime-contract red-test checklist
item. The subtree is not yet owned by a participant or used by room traffic, so runtime
routing and milestone completion remain unchecked.

Checkpoint 3c umbrella gates pass: formatting, warnings-as-errors, call engine `91 tests,
0 failures (1 excluded)`, gateway `37 tests, 0 failures (3 excluded)`, and no unused
dependencies.

Implementation evidence, checkpoint 3d (2026-09-08): introduced a participant-level
supervisor between the room's participant dynamic supervisor and each participant
authority. An agent participant owns its configured activation as a sibling of its
authority; both children are temporary and significant. Deliberately ending the participant
therefore tears down its authority and complete activation, while exhausting the
activation's internal one-restart budget ends that participant subtree without ending or
restarting the room-level participant supervisor. Human participants use the same ownership
boundary without an activation child. Room turn routing and plan-driven startup remain
unchecked.

Red: the focused ownership test failed because the room participant supervisor had no
activation-aware start contract or participant stop operation. Green: the focused file
passes two tests covering explicit teardown and exhausted activation retries, and the
combined room-teardown/participant-ownership files passed twenty repeated runs. Umbrella
gates pass: formatting, warnings-as-errors, call engine `93 tests, 0 failures (1 excluded)`,
gateway `37 tests, 0 failures (3 excluded)`, and no unused dependencies.

Implementation evidence, checkpoint 4 (2026-09-08): added a trusted `start_call/2` engine
path for a compiled plan and a typed `PlanStartup` boundary. It selects only the entry
caller and receiver, creates their fixed runtime commands, builds the receiver activation
from its pinned prompt/model/static Actions plus bounded application policy, and starts both
under their participant supervisors. The room routes normal turns through the activation's
coordinator reference, projects the existing participant/tool/text/terminal events, and
accepts events only from the currently registered coordinator. A first AgentServer failure
therefore restarts the activation without leaving the room bound to a stale child PID.

Red: after correcting an initially invalid test fixture, the vertical test failed because
`Vxpipe.CallEngine.start_call/2` did not exist. Green: two real Jido cases now prove a host
Action round from an attached entry caller, non-activation of an unused catalog agent, and
successful room routing after the activation's allowed restart. Ten repeated focused runs
passed, and the legacy deterministic/model/speech turn files remained green. Together with
the earlier request-policy, zero-retry, serial-dispatch and multi-round tests, this completes
the ordinary Jido routing checklist item. The broader room-startup item remains unchecked:
plan-selected speech capability behavior and explicit unsupported-feature diagnostics are
not implemented yet.

Checkpoint 4 umbrella gates pass: formatting, warnings-as-errors, call engine `95 tests,
0 failures (1 excluded)`, gateway `37 tests, 0 failures (3 excluded)`, and no unused
dependencies.

Implementation evidence, checkpoint 5 (2026-09-08): plan startup now resolves the entry
caller's selected STT and entry receiver's selected TTS against application-owned runtime
configuration before admitting either participant. The immutable room runtime contains the
constructed provider configuration and selected public model/media options, while credentials,
transport adapters, ingress limits and output queue bounds remain outside the public plan.
TTS starts with the receiver; STT starts for the caller's connection using the runtime pinned
when the room began. The legacy `CreateRoom` path retains its application-default behavior.

Red: the new definition-driven speech case timed out waiting for the TTS transport because
compiled speech selections were ignored. Green: the test proves the plan-selected TTS and
STT models override different application defaults while both transports receive the
application-owned credential. Ten repeated focused runs passed. A broader run exposed the
previously documented scripted-Jido concurrency failure because `AgentTest` was still marked
async; aligning that module with the existing synchronous Jido test lane made the complete
gate deterministic without changing runtime behavior.

Checkpoint 5 umbrella gates pass: formatting, warnings-as-errors, call engine `96 tests,
0 failures (1 excluded)`, gateway `37 tests, 0 failures (3 excluded)`, and no unused
dependencies. This completes the compiled-plan room-startup checklist item. End-to-end audio
turn completion through the trusted definition sample and explicit startup diagnostics remain
for the next checkpoints.

Implementation evidence, checkpoint 6 (2026-09-08): the development gateway now validates
one trusted call definition and closed capability/tool registries during endpoint setup. Each
creation request builds a trusted invocation, compiles a fresh immutable plan, starts its entry
caller/receiver, and issues a single-use gateway session for the already-started caller. The
room, participant and session return atomically to the sample, so the browser does not supply
definition/profile identity or create an extra participant. Legacy configured preset and
create-then-join behavior remains available outside this selected development path.

Red: the gateway endpoint case received only a legacy room response, and the revised frontend
case failed because it attempted a second session request after receiving the new atomic
fixture response. A review-added missing-room case then reproduced a function-clause crash;
the trusted adapter now delegates arbitrary input to the typed invocation validator and maps
that error to HTTP 400. Green: the focused gateway file passes 10 tests, the sample passes 2
tests, and its production TypeScript/Vite build succeeds. A development-config probe validated the
trusted definition with dummy secret fixtures; a live `bin/dev --http` request using the local
ignored development environment returned the expected room, human entry participant and
Small WebRTC session without exposing credentials.

Rendered browser verification used Chromium at 1440x900 and 390x844. The owned creation page
retained its layout, had zero WCAG A/AA axe violations, and one mocked `POST /api/rooms`
transitioned directly to the responsive console with no second session request. Upstream Voice
UI Kit output still reports unnamed mobile tabs and two low-contrast component states; no
generated dependency code was patched in this checkpoint.

The first complete umbrella run exposed a pre-existing 100 ms monitor-delivery race in the TTS
provider-failure test after the expected unavailability event had already arrived. The assertion
remains bounded but now allows one second for the linked process's `:DOWN` message. The focused
file then passed 20 consecutive randomized runs. Final checkpoint gates pass: formatting,
warnings-as-errors, dependency-use validation, call engine `96 tests, 0 failures (1 excluded)`,
gateway `39 tests, 0 failures (3 excluded)`, sample `2 tests`, and the production sample build.

Implementation evidence, checkpoint 7 (2026-09-08): the plan-start boundary now runs a
process-free startup preflight before asking the room `DynamicSupervisor` to create a child.
Valid schema fields whose behavior belongs to later slices no longer disappear silently:
non-empty Call Variables sections and generated/fixed first messages return
`unsupported_call_plan` with their definition path. A selected model profile whose provider is
not supported by the current Jido/ReqLLM runtime returns the same safe error at the receiver's
model capability path. The existing closed constructors continue to reject `media_policy` and
participant `while_present`, non-web connection service/mode/admission values, remote tool
types, aliases, and non-empty transfers before compilation.

Red: generated greeting input started a room while ignoring the greeting, and an unsupported
model provider collapsed to retryable `room_start_failed`. Green: both now fail before a room
registry entry exists; focused compiler and end-to-end definition tests pass `13 tests,
0 failures`. Duplicate room identity is still checked first, preserving the existing conflict
contract without weakening the process-start boundary. The error contains only a stable code,
message, path, and fixed reason rather than definition values or private provider configuration.
Final checkpoint gates pass formatting, warnings-as-errors, dependency-use validation, call
engine `99 tests, 0 failures (1 excluded)`, and gateway `39 tests, 0 failures (3 excluded)`.

Implementation evidence, checkpoint 8 (2026-09-08): after the definition-driven gateway and
sample tests were green, repository development configuration stopped duplicating the old
model-inference preset. The trusted definition/profile registry is now the only development
owner of the prompt, model, host-tool selection, STT model/media format, and TTS voice/media
format. Application configuration retains private Deepgram credentials, transport modules,
media/queue bounds, and agent-runtime bounds. The reusable legacy model-inference setting falls
back to its disabled base value; embedded hosts can still configure and use the legacy
`CreateRoom` path explicitly.

This was a configuration-only refactor, so no red behavior test was required. A `MIX_ENV=dev`
probe with explicit non-secret fixture values verified that legacy inference remains disabled,
both speech runtimes receive only the runtime credential before plan merging, and the trusted
gateway definition initializes. The existing runtime guard still requires both development
provider environment variables without printing or persisting them.
Final checkpoint gates pass formatting, warnings-as-errors, dependency-use validation, call
engine `99 tests, 0 failures (1 excluded)`, and gateway `39 tests, 0 failures (3 excluded)`.

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
