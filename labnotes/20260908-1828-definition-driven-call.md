# Definition-driven call implementation

## Goal

Implement milestone 1, `definition-driven-call`, as sequential red-green
checkpoints. Keep the existing room, gateway, speech and interruption behavior
green while replacing preset startup with a pinned typed definition and a
supervised Jido agent activation.

## Baseline

- Milestone status is not implemented and has no prerequisites.
- The current engine accepts `CreateRoom.agent` presets and directly starts the
  custom `ModelInference` capability from application settings.
- `vxpipe_call_engine` currently depends on ReqLLM and WebSockex; Jido AI and
  Jido Action are not installed.
- The existing gateway creates rooms through the preset path. The first compiler
  checkpoint must therefore be additive and must not break that runnable path.
- Worktree was clean at the start of the goal. Commit `702b4bb` is the preceding
  documentation checkpoint.

## Checkpoint 1: typed definition boundary

Selected schema release: `20260906.02`, matching the approved candidate in the
call-definition design. Resource ID and revision are trusted constructor metadata,
not keys in the schema document. Trusted tenant and actor identities are constructor
options for `CallInvocation`, not invocation-body values.

The initial supported compiler subset is deliberately closed:

- human web caller using receive/start-call connection intent;
- one agent receiver with inline prompt and first-message mode;
- capability profile refs resolved from a trusted registry;
- exact-name static host-tool bindings;
- bounded call duration; and
- empty transfers only until the transfer milestone.

Unsupported fields and enabled later-milestone behavior fail with path-specific,
secret-safe errors. Raw JSON maps and ordinary Elixir maps must converge on the
same structs. A resolved plan gets fresh call/room/participant/activation identities
and copies resolved data so later source/catalog changes cannot affect it.

### Red evidence

Added focused compiler tests covering JSON/Elixir parity, entry refs, schema and
field rejection, trusted invocation identity, closed profile/tool resolution,
pinning, and fresh runtime identities.

The first focused run failed during test compilation at the first expected
typed structure: `Vxpipe.CallEngine.CallDefinition.ConnectionIntent` was
undefined. No test executed, confirming that the new boundary was absent rather
than failing because of existing runtime behavior.

### Green implementation and review

- Added one top-level module per file for definition, participant, connection,
  capability refs/selections, tool selection, invocation, resolved plan and its
  participant/capability/tool data, plus pure validation and compilation.
- Extended only the engine's protocol-neutral error-code union and ID generator.
- Fixed-key normalization accepts the atom-key form used by trusted Elixir hosts
  and string keys produced by `JSON.decode/1`; it never converts input to atoms.
- Definition resource identity and invocation tenant/actor identity are supplied
  as trusted constructor options. Unknown invocation keys therefore reject entry
  or tenant override attempts.
- Closed capability-profile and host-tool maps are the only resolution path.
  Capability options containing credential-like keys cannot enter the pinned plan.
- The first green run passed `7 tests, 0 failures`. It initially exposed an alias
  collision between definition and resolved participant structs; fixing the
  explicit struct match resolved that implementation defect. Warnings for unused
  clause arguments were also removed.
- No room, provider, gateway, Jido or sample behavior changed in this checkpoint.

### Checkpoint 1 verification

From the umbrella root:

- `mix format --check-formatted` passed.
- `mix compile --warnings-as-errors` passed for call engine and gateway.
- `mix test` passed: call engine `73 tests, 0 failures (1 excluded)` and gateway
  `37 tests, 0 failures (3 excluded)`. Expected failure-path tests emitted
  supervised provider/transport termination logs without test failures.
- `mix deps.unlock --check-unused` passed with no output.

### Remaining milestone work

Runtime plan startup, supervised Jido integration, host-action execution through
Jido, provider failure cleanup, the trusted sample fixture, browser verification
and all milestone-level acceptance checks remain pending. Existing preset startup
stays available until the replacement path is proven.

## Checkpoint 2: typed initial Call Variables

This compiler checkpoint uses the already locked JSV 0.22 dependency for
Draft 2020-12 validation. The call-engine application declares it directly because
the engine owns schema compilation. JSV is configured without application-provided
resolvers and without atom casting. Definition validation rejects external `$ref`
usage rather than allowing network schema resolution.

### Red evidence

Focused tests cover typed section schemas, read/read+write agent permissions,
recursive default rejection, invalid schemas, partial initial values despite
`required`, explicit empty sections, unknown sections/properties, wrong datatypes,
JSON/Elixir parity, and unfilled sections remaining absent rather than becoming
empty or null values. The initial run failed while compiling the test because
`Vxpipe.CallEngine.CallDefinition.VariableSection` did not exist.

Review of the first green implementation found that removing `required` before
building the validator also allowed a malformed string-valued `required` keyword.
A new focused case reproduced that defect before the schema compiler was tightened;
an unsupported `allOf` case also establishes the dated schema's closed boundary.

### Green implementation and review

- Added typed Call Variables declaration, variable-section, permission, resolved
  section and resolved collection structures, one top-level module per file.
- Agent grants accept only `read` or the unique pair `read` and `write`, and must
  name a declared section. Human participants cannot declare agent grants.
- A schema compiler validates JSON-only data and a closed initial keyword/type
  subset, rejects defaults and references by treating all unsupported keywords
  uniformly, then compiles through JSV without casts or reference resolvers.
- `required` is validated as authored metadata, then removed contextually from
  schema nodes in the compiled runtime validator. It is not removed from enum data
  or the authored definition. Partial values therefore remain type checked at any
  populated depth without demanding missing values.
- Initial values validate before participant resolution/provider startup. Unknown
  sections, non-object roots, undeclared direct variables and datatype violations
  return only a path and generic reason. Omitted sections use `nil` with revision
  zero; explicitly supplied empty objects remain `%{}` with revision zero.
- Focused Call Variables tests passed `7 tests, 0 failures`; the original compiler
  tests passed `7 tests, 0 failures`.
- The first complete engine run had one unrelated 100 ms STT monitor assertion
  miss while its expected termination appeared in logs. That test passed alone,
  and the complete engine rerun passed `80 tests, 0 failures (1 excluded)`.

### Checkpoint 2 verification

From the umbrella root after the test-only termination-wait checkpoint `c1547f9`:

- `mix format --check-formatted` passed.
- `mix compile --warnings-as-errors` passed.
- `mix test` passed: call engine `80 tests, 0 failures (1 excluded)` and gateway
  `37 tests, 0 failures (3 excluded)`. Expected failure-path tests emitted
  supervised provider/transport termination logs without test failures.
- `mix deps.unlock --check-unused` passed with no output.

The milestone records the constructor/compiler test and minimal compiler checklist
items as complete. The ordered milestone index remains unchecked because the
runnable definition-driven call has not been delivered. Runtime variable ownership
and tools remain milestone 4 rather than being claimed by this compiler checkpoint.
The checkpoint was committed and pushed as `6568bf4`.

## Checkpoint 3a: Jido agent and static Action foundation

The engine now directly depends on Jido AI 2.3.0 and Jido Action 2.3.2. It starts
an application-owned `Vxpipe.CallEngine.Jido` instance so delegated ReAct workers
have the registry, agent supervisor, task supervisor, and runtime store required by
Jido's public AgentServer path.

The finite `Vxpipe.CallEngine.Agent` has no compile-time tool catalog. An
`AgentFactory` validates exact-name modules, then synchronously sets the resolved
system prompt and registers only selected static Actions on the running AgentServer.
This happens before the future activation owner reports readiness. The Agent uses
the reject-overlap policy and zero automatic Action retries.

Static Action handlers enter the existing Vxpipe `Tool.Executor` through a
per-activation `Tool.Dispatcher` GenServer. Jido 2.3.0's Agent option builder does
not propagate `tool_concurrency` into the delegated ReAct runtime, whose default is
four. The dispatcher therefore makes the application-owned handler boundary serial
without modifying dependency internals. `get_current_time` now implements both the
existing Vxpipe Tool contract and Jido Action while retaining its strict argument
check and bounded-result execution path.

### Red and integration evidence

The new focused test initially failed to compile because `Jido.AI.Test` was absent.
After adding dependencies, the real AgentServer failed its delegated request because
no Jido instance supervisor was running. Starting the application-owned instance
advanced the request and exposed another concrete boundary: direct mutation of a
prebuilt agent's strategy config is overwritten when AgentServer initializes it.
Moving prompt/tool setup to Jido's synchronous public AgentServer calls fixed that
readiness race.

The first two-round script intentionally called the same argument-free clock Action
twice. Jido's duplicate-tool-call guard correctly prevented that fixture, so the test
now uses a strict deterministic test Action with different arguments in successive
rounds. This tests the loop rather than disabling the dependency's safety guard.

Focused green evidence:

- `mix test test/vxpipe/call_engine/agent_test.exs`
- Result: `2 tests, 0 failures`.

Relevant regression evidence:

- `mix test test/vxpipe/call_engine/agent_test.exs test/vxpipe/call_engine/tool/executor_test.exs test/vxpipe/call_engine/call_definition/compiler_test.exs`
- Result: `12 tests, 0 failures`.

Umbrella gates after formatting:

- `mix format --check-formatted` passed.
- `mix compile --warnings-as-errors` passed for both umbrella children.
- `mix test` passed: call engine `82 tests, 0 failures (1 excluded)` and gateway
  `37 tests, 0 failures (3 excluded)`. Expected failure-path and shutdown logs did
  not produce test failures.
- `mix deps.unlock --check-unused` passed with no output.

This checkpoint does not route room turns through Jido and does not yet prove stream
projection, request timeout, interruption, participant-owned restart, or teardown.
Those remain the next red-green checkpoint before either Jido implementation task is
marked complete.

## Checkpoint 3b: Jido request coordinator

The engine now has a narrow `AgentRuntime` behavior, a production Jido adapter, and an
`AgentCoordinator` GenServer. The coordinator remains Vxpipe's authority for one-active-
turn admission, the bounded pending queue, response byte limits, sentence pacing, Vxpipe
identity correlation, timeout, interruption, and capability-facing tool/text events.
Jido remains the only ReAct loop and retains its own conversation context.

Each request receives a fresh `areq_` identity and private refs for the Vxpipe command and
request. The coordinator adds the trusted `Tool.Context` and per-activation dispatcher at
the request boundary. Jido runtime events are accepted only for the currently active
request; late events after timeout or interruption are ignored. Completed Vxpipe turn
identities are retained in a bounded correlation list. On interruption, selected request
IDs are retained as exclusions for every later model projection. A physical cleanup request
also uses Jido's public context-modification signal, but its acceptance is not treated as an
immediate cleanup guarantee because Jido may defer application behind worker lifecycle work.

### Red, green, and refactor evidence

The initial focused command was:

- `mix test test/vxpipe/call_engine/agent_coordinator_test.exs`

It ran three tests and failed all three because `Vxpipe.CallEngine.AgentCoordinator` did
not exist. After the minimal coordinator and runtime boundary were added, configuration
validation initially rejected the unloaded test adapter; explicitly ensuring the adapter
module is loaded fixed that boundary. The timeout test then demonstrated that queued turns
receive their own deadline, so its deliberately short fixture deadline was widened without
adding sleeps.

Refactoring changed cancellation to return the cancelled command explicitly and added a
regression case for an oversized final result. That case proves failing one response cannot
accidentally complete the next queued request. Invalid tool envelopes also cancel/fail the
correlated request and advance the queue instead of wedging it. The production cancellation
adapter uses a synchronous AgentServer signal so a replacement request cannot overtake the
cancel command in the agent mailbox.

Focused result at that stage: `5 tests, 0 failures`. The suite includes a real AgentServer and scripted
Jido provider round that calls the host Action once, projects its lifecycle, returns final
text, and requests cleanup of that completed exchange from Jido context. The remainder use a
controllable runtime adapter to prove exact timeout, queue, stale-event and interruption
races. The Jido-containing coordinator test module runs synchronously with other ExUnit
modules because parallel Jido script runs produced an incomplete two-round event stream in
the pre-existing Agent test during a full-suite run; isolation restored deterministic
coverage.

The complete call-engine rerun passed `87 tests, 0 failures (1 excluded)`. One prior run
hit an existing 100 ms TTS shutdown assertion even though the transport-close event had
arrived; that exact focused test passed immediately and the complete rerun was green without
changing production or unrelated test code.

Umbrella gate evidence:

- `mix format --check-formatted` passed.
- `mix compile --warnings-as-errors` passed.
- `mix test` passed: call engine `87 tests, 0 failures (1 excluded)` and gateway
  `37 tests, 0 failures (3 excluded)`.
- `mix deps.unlock --check-unused` passed with no output.

This checkpoint still does not place the AgentServer/coordinator/dispatcher under a single
participant activation supervisor, replace room use of the old inference capability, or
start a room from a resolved plan. Those lifecycle and routing steps remain next.

## Checkpoint 3c: supervised activation lifecycle

`AgentActivationSupervisor` now groups the per-activation dispatcher, Jido AgentServer,
and coordinator with explicit registry names. The child order lets coordinator `init/1`
synchronously configure the already-running AgentServer with the pinned prompt and finite
Action list. Supervisor startup is therefore the readiness acknowledgement; there is no
separate timing guess or piecemeal post-start mutation.

The supervisor uses one-for-all with one restart allowed in five seconds. A first abnormal
AgentServer failure ends and replaces all three children, including another synchronous
configuration barrier. A second failure in that interval ends the temporary activation
supervisor. Normal shutdown by its future participant owner will not be restarted by the
room's dynamic supervisor. The test monitors every child, confirms each replacement PID and
the reapplied prompt/tool surface, then confirms the exhausted activation leaves no live
child. The separate failed-startup case confirms its partially started children leave no
registered names.

### Red and green evidence

- Red command: `mix test test/vxpipe/call_engine/agent_activation_supervisor_test.exs`.
- Red result: `2 tests, 2 failures`; the requested supervisor module and APIs did not exist.
- The first implementation run retained one failure because the coordinator accepted only
  a dispatcher PID while the supervisor correctly supplied an explicitly named `via`
  reference. Resolving and validating both registered servers fixed startup without
  weakening readiness.
- Focused result: `2 tests, 0 failures`.
- Relevant runtime result: `mix test test/vxpipe/call_engine/agent_activation_supervisor_test.exs test/vxpipe/call_engine/agent_coordinator_test.exs test/vxpipe/call_engine/agent_test.exs`
  initially passed `9 tests, 0 failures`.

### Runtime-order follow-up

A 20-run repeat check of the coordinator uncovered two dependency-order boundaries that a
single green run did not show. A Jido `tool_completed` event can reach the stream sink before
its lower-sequence `tool_started` event. Strict immediate projection incorrectly failed the
turn. The coordinator now deduplicates event IDs, buffers an early result by tool-call ID,
emits start before completion when the start arrives, and delays terminal completion while
an observed tool lifecycle is unsettled. A focused out-of-order test was red before this
change and green afterward.

The same repeat check showed that acceptance of Jido's public context-modification signal
does not guarantee the operation has already survived all worker-lifecycle updates. A
bounded retry still sometimes returned unavailable and was the wrong abstraction. A new
engine-owned Jido request transformer now removes entries carrying interrupted request refs
from each actual LLM projection. Its focused test first failed because the module was absent,
then passed. Physical context replacement remains a cleanup request; projection filtering
owns correctness.

Post-correction evidence:

- `mix test test/vxpipe/call_engine/agent_coordinator_test.exs --repeat-until-failure 20 --max-failures 1`
  completed all 20 runs: `6 tests, 0 failures` per run.
- `mix test test/vxpipe/call_engine/agent_activation_supervisor_test.exs test/vxpipe/call_engine/agent_request_transformer_test.exs test/vxpipe/call_engine/agent_coordinator_test.exs test/vxpipe/call_engine/agent_test.exs`
  passed `11 tests, 0 failures`.

Checkpoint 3c umbrella gates:

- `mix format --check-formatted` passed.
- `mix compile --warnings-as-errors` passed.
- `mix test` passed: call engine `91 tests, 0 failures (1 excluded)` and gateway
  `37 tests, 0 failures (3 excluded)`.
- `mix deps.unlock --check-unused` passed with no output.

This checkpoint completes the milestone's stream/tool/timeout/interruption/teardown
red-test task across checkpoints 3a-3c. It does not yet make the activation a child of a
participant, route room turns through its coordinator, or compile its options from a plan.

## Checkpoint 3d: participant-owned activation

The room participant dynamic supervisor previously started a bare `ParticipantAuthority`.
That left no participant-scoped supervisor able to own an agent activation. A new
`ParticipantSupervisor` now owns the authority and, for an agent participant, its
`AgentActivationSupervisor`. Both are temporary significant children: explicit participant
termination tears down both, while activation death after its internal retry budget ends
the participant subtree. The room-level participant supervisor remains running and can
admit another participant, so this failure does not restart the room.

The room authority now monitors the participant supervisor rather than the bare authority.
The existing authority registry identity and snapshot API remain unchanged, preserving
connection authorization and existing participant lookup behavior.

### Red and green evidence

- Red command: `mix test test/vxpipe/call_engine/participant_supervisor_test.exs`.
- Red result: `1 test, 1 failure`; the activation-aware start and participant-stop APIs did
  not exist.
- Green command: `mix test test/vxpipe/call_engine/participant_supervisor_test.exs`.
- Green result: `2 tests, 0 failures`; explicit teardown stops the authority and activation,
  and two rapid AgentServer failures exhaust the activation budget and end only that
  participant subtree.

The first umbrella run exposed a pre-existing teardown-test race: after monitored room
authority and incarnation termination had both been proven, the test additionally assumed
the independent Registry process had consumed its own monitor signal immediately. The
extra nested participant ownership made that scheduling window visible. The redundant
Registry timing assertion was removed; the two process monitors remain the authoritative
room teardown contract.

This checkpoint establishes lifecycle ownership only. It does not yet route room turns
through the coordinator or derive activation options from a resolved plan.

Post-correction evidence:

- `mix test test/vxpipe/call_engine/create_room_test.exs test/vxpipe/call_engine/participant_supervisor_test.exs --repeat-until-failure 20 --max-failures 1`
  completed all 20 runs: `5 tests, 0 failures` per run.
- `mix format --check-formatted` passed.
- `mix compile --warnings-as-errors` passed.
- `mix test` passed: call engine `93 tests, 0 failures (1 excluded)` and gateway
  `37 tests, 0 failures (3 excluded)`.
- `mix deps.unlock --check-unused` passed with no output.

## Checkpoint 4: plan-driven Jido room routing

The engine now exposes a trusted `start_call/2` path that accepts only a compiled
`ResolvedCallPlan`. A pure typed `PlanStartup` step chooses the entry caller and receiver,
builds their participant commands, resolves the initial supported `:req_llm` model option,
sorts the receiver's finite static Action surface, and combines it with application-owned
queue/output/tool-result/request bounds. Only those two participants are started; an unused
agent in the same compiled catalog has neither an authority nor activation.

The room keeps the coordinator's stable Registry reference as its logical text capability.
Each request reaches the currently registered coordinator, and inbound capability events
are accepted only when their sender resolves as that current child. After the activation's
one allowed one-for-all restart, the room therefore routes the next turn through the new
coordinator rather than retaining a stale PID. Exhausting that budget still ends the
participant as established in checkpoint 3d.

### Red, green, and verification evidence

- The first red attempt stopped in fixture validation because explicit `nil` capability
  keys are invalid authored values; omitting those unset keys corrected the fixture before
  behavior work began.
- Corrected red command:
  `mix test test/vxpipe/call_engine/definition_driven_call_test.exs`.
- Corrected red result: `1 test, 1 failure`; `Vxpipe.CallEngine.start_call/2` did not exist.
- Green focused result: `2 tests, 0 failures`.
- `mix test test/vxpipe/call_engine/definition_driven_call_test.exs --repeat-until-failure 10 --max-failures 1`
  completed all ten runs with `2 tests, 0 failures` per run.
- The definition-driven, legacy model-inference, text-turn and spoken-barge-in files passed
  together: `12 tests, 0 failures`.
- `mix format --check-formatted` and `mix compile --warnings-as-errors` passed.
- `mix test` passed: call engine `95 tests, 0 failures (1 excluded)` and gateway
  `37 tests, 0 failures (3 excluded)`.
- `mix deps.unlock --check-unused` passed with no output.

This checkpoint supports definition-driven text and one static host Action through Jido.
It does not yet start plan-selected speech capabilities, reject all later-slice settings,
or connect the trusted sample.

## Checkpoint 5: plan-selected speech startup

The definition-driven room now resolves the entry caller's STT selection and entry receiver's
TTS selection before participant admission. Resolution combines public provider options from
the immutable plan with application-owned credentials and runtime adapters. Typed runtime
records retain the constructed provider configuration, transport selection, ingress limits
and output queue bound for the room; these private/runtime values do not enter the public plan
or snapshot.

The selected TTS runtime starts with the receiving agent. When the entry caller attaches, the
room returns that participant's pinned STT runtime to the connection startup path rather than
rereading a mutable global provider selection. The legacy `CreateRoom` path explicitly retains
its prior application-default STT/TTS behavior.

### Red, green, and verification evidence

- Red command: `mix test test/vxpipe/call_engine/definition_driven_call_test.exs`.
- Red result: `3 tests, 1 failure`; no TTS transport-start event arrived because plan speech
  selections were not connected to room startup.
- Green focused result: `3 tests, 0 failures`. The case uses deliberately different plan and
  application model values and proves the transports receive plan-selected STT/TTS models plus
  the application-owned credential.
- Ten repeated focused runs completed with `3 tests, 0 failures` per run.
- The first complete engine run exposed the documented Jido test isolation issue: the direct
  Agent test still declared `async: true` and lost the second scripted tool event while another
  Jido test was active. Marking that module synchronous aligned the code with checkpoint 3b's
  already recorded test-lane decision. The subsequent complete suite passed.
- Umbrella gates passed: `mix format --check-formatted`,
  `mix compile --warnings-as-errors`, call engine `96 tests, 0 failures (1 excluded)`, gateway
  `37 tests, 0 failures (3 excluded)`, and `mix deps.unlock --check-unused`.

Room startup now activates only the entry participants and their selected model/STT/TTS
capabilities. The trusted sample still needs a complete spoken turn through this path, and
unsupported enabled later-slice settings need precise pre-provider diagnostics.

## Checkpoint 6: trusted development sample

The development gateway now owns a narrow `TrustedCall` adapter. Endpoint initialization
validates one configured definition and closed capability/tool registries. Each creation
request supplies only a browser-generated room ID; the gateway adds the configured principal,
constructs the invocation, compiles a fresh plan, and calls the engine's trusted plan-start API.
It then reads the plan's already-started entry caller through a public engine snapshot function
and issues that exact participant's single-use Small WebRTC session.

This path returns `room`, `participant`, and `session` from `POST /api/rooms`. It does not call
the legacy join route or create a second human participant. The React creation page accepts the
atomic response and retains its existing fallback for older configured create-then-join hosts.
No visual structure or responsive styling changed.

### Red, green, and verification evidence

- Gateway red: `mix test test/vxpipe/gateway/http/endpoint_test.exs` passed the HTTP status but
  failed its response match because only the legacy room was returned.
- A review-added trusted request without `room_id` was red with a `FunctionClauseError` because
  the adapter guard rejected the raw value before typed validation. Removing that guard lets
  `CallInvocation` return `invalid_call_invocation`, which the development HTTP boundary maps
  to 400.
- Gateway green: the focused file passed `10 tests, 0 failures`.
- Frontend red: `npm test -- --run src/App.test.tsx` failed to find the console because the page
  attempted a second fetch after the atomic response.
- Frontend green: `npm test` passed `2 tests`; `npm run build` completed TypeScript checking and
  the Vite production build.
- `MIX_ENV=dev mix run --no-start` with explicit dummy credential fixtures successfully
  initialized the configured gateway endpoint and validated the trusted definition. The first
  probe without those fixtures stopped at the existing required-secret guard before definition
  initialization, as expected.
- A live `bin/dev --http` process loaded the ignored development credentials. A filtered local
  creation request returned the configured tenant, a human `part_` entry identity, a `sess_`
  identity and `smallwebrtc` transport. No credential value was printed.
- Rendered Chromium checks at 1440x900 and 390x844 confirmed the owned creation page remained
  intact. Axe reported zero WCAG A/AA violations there. A mocked atomic response caused exactly
  one room request and displayed the responsive Pipecat console. The dependency-rendered console
  still reports four unnamed mobile tab buttons and two low-contrast states; those upstream
  component findings remain standing rather than being hidden by generated-package patches.
- The first complete umbrella run hit the existing 100 ms TTS provider-failure monitor
  assertion after the expected unavailability event had already arrived. This was a bounded test
  scheduling window, not a runtime failure. The monitor assertion now allows one second, matching
  the suite's lifecycle-testing convention, and the focused file passed 20 consecutive randomized
  runs.
- Final checkpoint gates passed `mix format --check-formatted`,
  `mix compile --warnings-as-errors`, `mix deps.unlock --check-unused`, call engine `96 tests,
  0 failures (1 excluded)`, gateway `39 tests, 0 failures (3 excluded)`, sample `2 tests`, and
  the production sample build.

### Manual spoken/tool verification

1. Put valid development provider keys in the ignored repository `.env` and run `bin/dev`.
2. Open the HTTPS sample URL printed by the process and choose **Create room**.
3. Confirm the Pipecat console appears, then choose **Connect** and wait for `botReady`.
4. Type a short message and confirm one assistant text response and one spoken response.
5. Speak a short message and confirm one final caller transcript plus one text/spoken response.
6. Ask for the current UTC time and confirm one `get_current_time` tool lifecycle followed by
   the final answer.

The remaining milestone implementation is explicit unsupported-feature/startup diagnostics,
then removal of duplicated preset-only development configuration once those sample checks are
complete.

## Checkpoint 7: startup support diagnostics

The definition types intentionally carry some contract fields for later slices. Before this
checkpoint, a generated/fixed `first_message` could pass construction and compilation but was
ignored by room startup. Non-empty Call Variables were likewise pinned without an authoritative
runtime, while an unsupported selected model provider collapsed into generic retryable
`room_start_failed` after a room child had been attempted.

The public `CallEngine.start_call/2` boundary now asks `PlanStartup` to preflight the active plan
against the application-owned runtime before calling the room `DynamicSupervisor`. It builds no
room, participant, Jido, transport, or provider process. Failure returns the secret-safe
`unsupported_call_plan` code with a definition path and fixed reason. The active subset requires:

- web transport and the web receive/start-call entry caller;
- a receiving agent in `wait_for_input` mode;
- no Call Variables sections or participant transfers yet;
- resolved local host Actions only;
- the Jido/ReqLLM model path and speech selections compatible with configured runtimes.

Privacy/media policy keys (`media_policy` and `while_present`), alternate connection values,
remote tool types, tool aliases, and non-empty transfers are still rejected earlier by closed
constructors. This preflight covers supported schema shapes whose runtime is deferred; it does
not widen the released schema.

### Red, green, and evidence

- Red: a compiled generated greeting returned `{:ok, room}` while doing nothing with the
  greeting. A compiled model selection using an unsupported provider returned only
  `room_start_failed`.
- Green: both return path-specific `unsupported_call_plan`; a non-empty variables section does
  the same. Every case verifies the tenant/room registry has no entry after rejection, proving
  the dynamic room/provider tree was not started.
- Existing constructor cases now explicitly cover call/participant media policy keys and an MCP
  tool selection alongside the already-covered non-web connection and transfer cases.
- Focused compiler plus definition-driven integration files pass `13 tests, 0 failures`.
  Duplicate room identity is still checked before preflight, preserving the prior
  `room_already_exists` precedence while keeping validation before dynamic child creation.
- Final gates passed `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix deps.unlock --check-unused`, call engine `99 tests, 0 failures (1 excluded)`, and gateway
  `39 tests, 0 failures (3 excluded)`.

## Checkpoint 8: remove development preset duplication

Once the trusted sample and its definition-driven tests were green, the old development
model-inference preset was redundant. It repeated the prompt, Gemini model, host tool, and
execution limits alongside the definition/profile registry. The application STT/TTS settings
also repeated the profile-owned model, encoding, and sample rate.

`config/dev.exs` now leaves legacy model inference at the reusable base default (`enabled:
false`). The trusted definition/profile registry is the single development owner of prompt,
model, tools, voice, STT model, and public media options. Application settings retain the
Deepgram provider modules, private provider options populated at runtime, transport modules,
media-ingress bounds, TTS request bound, and the separate shared agent-runtime bounds.

This is configuration-only and therefore did not require an initial red test. A `MIX_ENV=dev`
probe with explicit fixture environment values verified all of the following without printing a
credential:

- legacy model inference remained disabled;
- the runtime injected the Deepgram fixture only into private STT/TTS provider options;
- the configured trusted definition and registries initialized successfully.

The development runtime continues to require the Gemini environment value for the Jido/ReqLLM
sample and the Deepgram value for speech. Embedded users retain the legacy `CreateRoom` contract
and can explicitly supply its complete application configuration; repository development no
longer configures that duplicate path by default.

Final gates passed `mix format --check-formatted`, `mix compile --warnings-as-errors`,
`mix deps.unlock --check-unused`, call engine `99 tests, 0 failures (1 excluded)`, and gateway
`39 tests, 0 failures (3 excluded)`.

## Checkpoint 9: acceptance hardening and milestone completion

The final acceptance pass added direct evidence for two contracts that earlier implementation
tests reached only indirectly. A running room now proves its resolved prompt and model remain
pinned after the source definition and profile registry are replaced. A forced selected-TTS
transport failure proves the single attempted provider start is cleaned up with no registered
room, participant, activation, or silent fallback.

Live acceptance exposed two integration defects that the deterministic runtime had not made
visible. First, Jido ignores a top-level `model` request option; the coordinator now carries the
plan-selected model in private runtime context and the request transformer returns it as the
public per-request override Jido applies. Second, the provider-failure branch piped state into a
helper whose argument order was reversed, crashing the coordinator. Focused red tests reproduced
both failures. The corrected coordinator reports the normalized provider failure, remains ready
for the next request, and continues to preserve the selected model.

Development runtime configuration now supplies `GEMINI_API_KEY` to ReqLLM's Google provider
configuration. The former legacy model-inference injection had become ineffective when that
duplicate preset was disabled in checkpoint 8. A fixture-only runtime probe confirmed the
credential is configured without printing its value.

The HTTPS sample also revealed that `crypto.randomUUID` is unavailable on some non-secure HTTP
origins used during local diagnosis. A frontend red test captured that browser boundary. Room ID
creation now feature-detects `randomUUID`, falls back to a standards-shaped UUID generated with
`crypto.getRandomValues`, and retains a last-resort non-cryptographic ID only when the Web Crypto
API is entirely unavailable. The room creation and console layout were otherwise unchanged.

### Red, green, and acceptance evidence

- The focused plan-pinning/provider-cleanup additions initially failed because the active Jido
  server retained its default model and the failing TTS transport left startup behavior
  unproved. They now pass with explicit source-registry mutation, one failed start attempt, and
  complete registry cleanup.
- The coordinator model-propagation test initially found no per-request model in private runtime
  context; the request-transformer test then found no Jido model override. Both are green after
  routing the immutable plan selection through the transformer.
- The coordinator provider-failure test initially crashed with `:provider_unavailable` treated
  as state. It now receives one normalized failure and successfully accepts a replacement turn.
- The frontend fallback test initially raised because `randomUUID` was absent. It now produces
  the deterministic standards-shaped fallback and makes exactly one room-creation request.
- Focused engine command passed `23 tests, 0 failures` across the compiler,
  definition-driven-call, coordinator, and request-transformer files.
- In the rendered HTTPS sample, one typed request displayed the `get_current_time` lifecycle and
  completed with one text/spoken answer. A provider-watch speech fixture then produced one final
  caller transcript and an agent answer whose streamed TTS sentences reached `spoken: completed`.
- Chromium inspection at desktop and 390x844 mobile showed the existing responsive console
  intact. Browser error output was empty. The hardening pass used feature detection and graceful
  degradation without changing the established visual hierarchy or layout.
- Final repository gates passed: `mix format --check-formatted`,
  `mix compile --warnings-as-errors`, `mix deps.unlock --check-unused`, call engine
  `102 tests, 0 failures (1 excluded)`, gateway `39 tests, 0 failures (3 excluded)`, sample
  `3 tests, 0 failures`, and the production sample build. The Vite build retained its existing
  advisory for a bundle larger than 500 kB; it is not a build failure.

Every milestone acceptance/failure item now has direct test or live-browser evidence. Milestone
1 is complete; the next implementation slice is the observable sample call.
