# Jido AI evaluation

Date: 2026-09-08

## Objective

Evaluate whether Jido AI, Jido Action, and Jido MCP can replace custom pieces that
Vxpipe planned to build directly around ReqLLM. The focus is the agent model/tool
loop and remote MCP integration, not room media or transport concerns.

No runtime dependency was added during this research checkpoint. A subsequent
planning update selected the Jido-based boundaries described below and updated the
durable architecture and milestone specifications; implementation is still pending.

Latest follow-up: keep Jido AI's LLM/tool loop, select ExMCP directly behind
`vxpipe_mcp`, and require a public Jido runtime-tool interface extension before live
tenant MCP tools ship. The earlier direct Jido MCP and wait-for-Connect recommendations
below are historical. See [the durable decision](../docs/jido-tool-execution.md).

## Finding

The strongest fit is a hybrid:

1. Keep Vxpipe as the authority for calls, rooms, participants, media,
   authorization, transfers, variables, persistence policy, and client event
   projection.
2. Use one supervised `Jido.AI.Agent`/AgentServer as the implementation of each
   active agent participant's ordinary LLM/tool loop. It replaces the current
   inference capability process and remains subordinate to Vxpipe's participant
   lifecycle.
3. Represent platform-owned agent tools with Jido Action while their handlers
   still call Vxpipe-owned processes and enforce Vxpipe permissions.
4. Use ExMCP directly behind the thin `vxpipe_mcp` policy boundary for remote protocol
   work. Keep the engine-side Jido model-tool bridge separate; dynamic names/schemas
   require a supported public Jido extension, not a custom LLM loop.
5. Keep long-running tool work under Vxpipe supervision. A Jido action can submit
   such work and return immediately; the remote operation must not occupy the
   ordinary ReAct loop for its full duration.

Jido AI is not an alternative model-provider client to ReqLLM. It is an
orchestration layer built on ReqLLM. Adopting it would mean using ReqLLM through
Jido for agent loops instead of maintaining the whole loop directly on ReqLLM.

## Current Vxpipe boundary

The current implementation deliberately gives the engine ownership of the
voice-facing lifecycle:

- `Vxpipe.CallEngine.Provider.ModelInference` is the provider-neutral inference
  boundary.
- `Vxpipe.CallEngine.Provider.ReqLLM` translates Vxpipe messages and tool
  definitions to ReqLLM.
- `Vxpipe.CallEngine.Capability.ModelInference` owns request serialization,
  supervised inference tasks, timeouts, interruption, streamed sentence output,
  history, repeated model/tool rounds, tool events, and tool execution.
- `Vxpipe.CallEngine.Tool.Executor` checks the project-owned tool contract and
  bounds tool results.

The room and participant process trees should continue to own those voice and
call semantics. A third-party agent runtime must fit behind that boundary or
replace one coherent layer; it must not become a second authority for the room.

## What the Jido packages provide

The stable package lines reviewed were:

- Jido AI 2.3.0, which depends on Jido 2.3, Jido Action 2.3, and ReqLLM 1.x.
- Jido Action 2.3.2, which provides action metadata, schemas, validation,
  execution, timeouts, cancellation, retries, and telemetry.
- Jido MCP 1.1.1, which provides pooled remote-client and Jido Action/Jido AI
  integration surfaces.

Vxpipe currently uses ReqLLM 1.22.0. That version is within Jido AI 2.3.0's
declared ReqLLM range, but dependency resolution and behavior still need to be
verified in the umbrella.
The later isolated probe resolved and ran these stable Jido AI/Action versions with
ReqLLM 1.22.0 and ExMCP 1.3.0; umbrella integration remains unverified.

### ReAct runtime and AgentServer

Jido AI explicitly presents its standalone ReAct runtime for applications that
already own their orchestration. It supplies:

- synchronous, streaming, and process-backed runs;
- model/tool iteration with configurable iteration limits;
- concurrent tool execution with deterministic result ordering;
- request handles, cancellation, continuation, and event collection;
- usage and tool lifecycle events;
- request transformation before each model call;
- thread/context projection and explicit context replacement;
- telemetry for requests, LLM calls, tools, durations, tokens, and retries.

This overlaps substantially with the inner loop in
`Vxpipe.CallEngine.Capability.ModelInference`. It does not overlap with WebRTC,
audio routing, STT, TTS, room supervision, or client protocol handling.

The initial recommendation was standalone ReAct. Follow-up review changed that
choice because Jido MCP's public dynamic tool-sync API targets a running
`Jido.AI.Agent`, not a standalone ReAct run. A per-activation AgentServer is a clean
fit only when it replaces the current per-agent inference process. Vxpipe's
participant supervisor owns its start, readiness and termination; Jido owns the
contained conversation/request/tool runtime. It never becomes the participant or
room authority. Standalone ReAct remains useful for isolated adapter tests.
After selecting ExMCP directly, the AgentServer remains the chosen supervised inference
boundary, but no longer for compatibility with Jido MCP's synchronization API.

### Jido Action

Jido Action is a good common descriptor and execution contract for tools that an
agent may call. It can cover platform tools such as variable operations and
transfers while the actual authority stays in Vxpipe processes.

Project policy must override several library defaults:

- The reviewed ReAct defaults allow one tool retry. Vxpipe's current decision is
  no automatic retry, so `tool_max_retries` must be set to zero.
- The reviewed ReAct defaults allow tool concurrency of four. Vxpipe must choose
  concurrency explicitly according to ordering and side-effect rules.
- Action schemas are open unless configured otherwise, so security-sensitive
  platform actions need strict input schemas.
- Jido Action's plain JSON Schema compatibility form does not perform full
  runtime validation. Remote MCP inputs still require a real JSON Schema
  validator for the server-provided schema.

The sibling Callx implementation is useful local evidence: it already expresses
several small host operations as Jido Actions while retaining a custom
voice-facing LLM adapter. It also retains a custom ReqLLM loop for dynamically
discovered room tools. The selected AgentServer-backed ReAct runtime removes more
of that custom loop, but the Vxpipe-specific authority boundaries remain necessary.

## Proposed runtime boundary

```text
Vxpipe room and participant supervision
  -> Vxpipe agent-loop adapter
       -> one Jido.AI.Agent/AgentServer per active agent participant
            -> ReqLLM provider access
            -> static Jido Actions -> Vxpipe variable and transfer APIs
            -> required public runtime-tool interface (not available yet)
                 -> Vxpipe private binding/background worker
                      -> vxpipe_mcp -> ExMCP public client
```

The Vxpipe adapter would translate between Jido events and engine events. It must
remain responsible for:

- assigning room, participant, turn, and request identities;
- projecting streamed model text into text and TTS output;
- applying interruption policy;
- authorizing every platform or remote tool invocation;
- applying client tool-event visibility policy;
- associating usage and persisted events with the correct call entities;
- rejecting stale completions after an agent or room incarnation ends.

## Fit against planned custom work

| Planned concern | Jido fit | Vxpipe ownership that remains |
| --- | --- | --- |
| Repeated LLM/tool calls | Strong: the AgentServer-backed ReAct strategy implements the loop | Model profile selection, call pinning, turn serialization, event projection |
| Streaming model output | Strong: the runtime emits a normalized event stream | Sentence/audio pacing and interruption |
| Static platform tools | Strong: Jido Action describes and executes them | Authorization and calls to room-owned processes |
| Dynamic remote MCP tools | Requires a public runtime descriptor/executor interface; current Action-module registry is insufficient | Tenant catalog, credentials, pinning, network policy and private tool binding |
| Tool timeout and cancellation | Useful primitives exist | Per-tool semantics and distinction between speech interruption and operation cancellation |
| Tool retry | Mechanism exists | Configure zero automatic retries by policy |
| Long-running background tools | Partial: a normal ReAct run waits for tool results | Submission, supervision, late completion, and continued conversation |
| Thread/context projection | Useful mechanics | Variable state, access rules, persistence, and prompt projection |
| Compaction | Supports replacing projected context with provenance | Trigger thresholds, summarizer, failure behavior, and archival history |
| Usage telemetry | Strong normalized events | Attribution to calls, participants, turns, and storage records |
| Agent process lifecycle | Useful as the replaceable inference child | Vxpipe participant supervision remains its owner |
| Room/media lifecycle | No fit | Entirely Vxpipe-owned |

## Long-running tools and continued conversation

Jido's normal ReAct runner executes a batch of tool calls and waits for their
results before making the next model request. Its tool heartbeat keeps observers
informed, but does not create a second conversational model turn while the tool
is running. Its normal concurrent request policy also does not by itself provide
the planned Vxpipe behavior of continuing the conversation around a submitted
operation.

The clean integration is to distinguish two action classes:

### Completing action

The action is expected to finish within the current turn. ReAct waits for its
result and supplies that result to the next LLM iteration. Read-only lookups and
short bounded operations fit here.

### Submitted action

The Jido Action validates and authorizes the request, asks a Vxpipe-owned
supervisor to start it, and immediately returns a result such as:

```json
{
  "status": "running",
  "operation_id": "op_..."
}
```

The agent may then continue speaking and accepting turns. Completion is later
delivered to the active agent through the Vxpipe adapter, with the original call,
participant, operation, and room-incarnation identities. Vxpipe decides whether
that completion becomes model context, a client-visible event, or only a stored
event.

Follow-up review found that Jido's `inject` and `steer` APIs are not a delivery
mechanism for this update. They reject an idle agent, and input queued during an
active request is explicitly best-effort and can be dropped if the run finishes
first. Vxpipe therefore keeps accepted completions in a bounded per-agent mailbox.
After the current request terminates, the Vxpipe coordinator starts one serialized
engine-origin continuation request. Its provenance prevents the adapter from
presenting it as caller speech or a public transcript event. A Jido busy rejection
at that point is an invariant failure to retain/report, not a reason to drop the
completion or spin in a retry loop.

This preserves prior decisions:

- interrupting generated speech does not imply cancellation of an external
  operation;
- an explicit cancellation tool can ask the Vxpipe worker to cancel;
- no automatic retry is introduced;
- a late or uncertain result cannot mutate a replacement room incarnation;
- the source system remains authoritative when a timeout leaves an outcome
  unknown.

## Earlier Jido MCP decision — superseded

Historical checkpoint: the later released-package investigation selects direct ExMCP
for the protocol layer. Preserve the observations below, not the old dependency mandate.

The released Jido MCP package is directly relevant rather than merely a generic
action wrapper. It pools remote clients, discovers remote tools, can call them
directly, and can generate Jido Action proxies for use by Jido AI.
That could replace custom connection pooling, discovery-to-tool conversion, and
some invocation plumbing in the planned MCP adapter.

Jido MCP is the selected integration surface. It does not replace the thin Vxpipe
policy boundary.

### Gaps to prove or resolve

1. **Protocol revision:** released documentation names the 2025-03-26 and
   2025-06-18 Streamable HTTP revisions. Vxpipe currently plans to pin MCP
   2025-11-25. Exact compatibility must be demonstrated, not inferred.
2. **Endpoint and tool identity:** the current public direct client accepts bounded
   string endpoint IDs, but Jido AI proxy sync requires a trusted atom endpoint ID.
   It generates an Action module whose atom name is derived from endpoint and tool
   definition data. Unsyncing can purge module code but cannot garbage-collect the
   atom. Tenant endpoint/tool/schema churn therefore remains unsafe.
3. **Tenancy:** Vxpipe needs application- and tenant-configured endpoints with
   generation-pinned credentials. A global pool entry must not accidentally
   share authorization or discovery results across tenants.
4. **Per-call pinning:** a call must keep the selected endpoint generation and
   discovered tool contract even if configuration changes during the call.
5. **Network security:** URL policy, redirects, DNS changes, private-address
   blocking, TLS, credential injection, and response/decompression bounds remain
   Vxpipe deployment policy even when a library performs the transport.
6. **Validation:** MCP tool arguments must be validated against the discovered
   JSON Schema before transmission. The Jido MCP proxy uses a JSON Schema
   validator, but its supported dialect and limits must match the pinned Vxpipe
   contract.
7. **Result limits:** Vxpipe's maximum acceptable MCP response size and projection
   policy must apply before content enters agent context or persistence.
8. **Retries and deadlines:** action execution must not silently retry a
   side-effecting MCP call. Call, connect, idle, and overall deadlines need clear
   ownership.
9. **Lifecycle cleanup:** endpoint generations and proxy artifacts need bounded
   lifetimes when tenants reconfigure integrations. The reviewed public sync path
   does not satisfy that lifetime bound for externally configured catalogs.
Jido MCP's choice of internal protocol/transport library is not one of these product
gates. Vxpipe tests the behavior of the pinned public Jido MCP surface and does not
depend directly on its transitive client runtime. `vxpipe_mcp` remains a small
policy-owning boundary while delegating protocol mechanics to Jido MCP.

The generic public `Jido.MCP.Actions.CallTool` does not solve the proxy issue for
Vxpipe's agent-visible contract. It exposes endpoint/tool selection and a generic
arguments map to the model, whereas the call plan requires fixed local aliases,
private endpoint selection, and an exact pinned input schema per enabled binding.
Using the private proxy generator is also rejected. MCP implementation is blocked
until a supported public Jido MCP/Jido AI mechanism provides those semantics without
external atom/module growth. This does not block Jido AI for platform tools.

## Alternatives considered

### Continue directly on ReqLLM

This preserves complete control and has the smallest dependency change, but it
leaves Vxpipe maintaining a generic model/tool loop, event normalization, usage
collection, tool concurrency, and context projection that Jido already provides.
The current decision is to extend the missing public tool interface while preserving
Jido's loop, not to rebuild this loop merely because MCP glue is missing.

### Adopt Jido AgentServer as the whole agent participant

Rejected. Jido must not own media, presence, transfers, Call Variables, protocol
projection, or participant identity. The selected narrower use starts one
AgentServer as the participant subtree's inference child only.

### Use standalone ReAct plus Jido Action in production

The earlier rejection relied on Jido MCP's public agent tool-sync API. That dependency
is now superseded; the retained AgentServer choice provides the per-activation supervised
request boundary. Standalone ReAct remains useful for deterministic adapter tests,
not as a second production runtime. Both share the module-backed tool limitation.

### Use a supervised Jido agent as the inference child

Selected. It replaces the existing inference loop process while Vxpipe retains the
outer participant and room lifecycles. This is the narrowest production boundary
that uses Jido's public request lifecycle and can compose with its public agent
integration surfaces.

### Use Jido MCP without a Vxpipe wrapper

This is attractive mechanically but would put tenant policy, credentials,
endpoint generations, security bounds, and call pinning too close to a general
integration package. It is not recommended. The wrapper should be thin, but it
should exist.

## Focused adoption spike

The first spike replaces the inference child inside the existing participant tree;
it does not add a second room or participant authority. Exercise one small vertical
slice:

1. Accept one text input for an active agent.
2. Stream model output through existing Vxpipe output events.
3. Execute one static Jido Action.
4. Feed its result back to the model and complete the response.
5. Preserve request, participant, turn, and usage identities.
6. Interrupt model/TTS output without implicitly cancelling a completed or
   submitted side effect.
7. Time out a tool with automatic retries configured to zero.
8. Submit one background action, accept a second user turn while it runs, and
   safely project its later completion through the Vxpipe mailbox/internal-request
   path without using best-effort Jido injection.

Then run a separate remote-MCP spike against a controlled server:

1. Configure the endpoint through the same application/tenant model planned for
   production.
2. Discover and pin its tools for one call.
3. Validate arguments and reject invalid input before network transmission.
4. Invoke a tool through Jido AI and preserve the original MCP response for
   storage while applying agent/client projections separately.
5. Enforce response size, deadline, credential, and network constraints.
6. Reconfigure the tenant endpoint and prove that the active call remains on its
   pinned generation.
7. Repeatedly add and retire generated catalogs and verify that atom/module usage
   is bounded.

## Acceptance criteria

Adopt Jido AI for the agent loop if the spike proves that:

- its stream and cancellation events map cleanly to existing Vxpipe behavior;
- Vxpipe remains the sole authority for room and participant lifecycle;
- action authorization and client visibility cannot be bypassed;
- retries, timeouts, and concurrency are explicit Vxpipe policy;
- submitted background actions can coexist with continuing conversation;
- usage and tool events retain the identities needed for persistence;
- replacing the current inner loop removes more custom machinery than the
  adapter introduces.

Use ExMCP behind the Vxpipe MCP boundary and require the separate MCP checks before
claiming that milestone complete. A failed gate is a concrete ExMCP integration
blocker to resolve; it is not permission to add a second client or custom parser.
That blocker would not prevent using Jido AI and Jido Action for the rest of the
agent loop.

## Decision status

Selected for the milestone plan after the released-package follow-up: one supervised Jido AI
AgentServer per active agent participant, Jido Action for finite static tools, and
ExMCP behind the thin Vxpipe MCP policy boundary. The milestone count and order
remain unchanged. No runtime dependency or implementation has been added yet. The
earlier focused reviews are retained as history. The live-MCP specification owns the
runtime-tool interface blocker; the protocol-only checkpoint can proceed independently.

## Jido Connect replacement investigation

Follow-up research on 2026-09-08 compared the current Jido Connect default branch
and its open replacement pull request with Vxpipe's MCP requirements.

### Released/current state

Jido Connect is not currently a usable replacement dependency:

- Default-branch revision `02cb6cbdc3e720922b7c3805e8ecdebb6e60461c`
  describes repository version `0.8.0`, but the packages are not published on Hex.
- Its separate `jido_connect_mcp` application still depends on `jido_mcp` and
  delegates MCP transport, protocol, client registration, discovery, and calls to
  it. Depending on this version would retain the dependency being evaluated for
  replacement.
- The default-branch bridge does add Connect-owned connection policy, credential
  leases, endpoint-generation fencing, schema fingerprints, normalized errors,
  and uncertain-write classification. Those are useful higher-level controls, not
  an independent MCP client implementation.

### Proposed successor state

[Jido Connect issue 69](https://github.com/agentjido/jido_connect/issues/69) and
[its bridge issue](https://github.com/agentjido/jido_connect/issues/71) define a
more precise successor:

- ExMCP owns protocol, transport, and client behavior.
- Core Jido Connect owns only `mcp.tools.list` and `mcp.tool.call` plus its
  connection, authorization, and safety contracts.
- The separate unpublished `jido_connect_mcp` application is removed.
- MCP resources, prompts, server publication, a general endpoint pool, and dynamic
  Jido AI proxy Actions deliberately do not move to Connect.

Open pull request
[75](https://github.com/agentjido/jido_connect/pull/75), inspected at head
`8880808d88918c1774ec147ff31d7fe15d244d34`, implements that proposed shape as
core `jido_connect` `0.9.0` over ExMCP `~> 1.0`. Its GitHub quality check passed.
It is nevertheless unmerged, currently conflicts with its base branch, and has no
published Hex release. Its final commit also moves Connect to a Jido Action v3 beta
pin, whereas the stable Jido AI line evaluated above uses Jido Action v2; coexistence
with the selected agent runtime has not been demonstrated.

### What Vxpipe could reuse

The proposed core bridge contains several boundaries that closely match Vxpipe:

- host-owned durable connections and storage-free, short-lived credential leases;
- tenant/actor ownership metadata, scopes, host policy callbacks, and safe
  credential inspection;
- public string endpoint IDs kept separate from supervised ExMCP client references;
- either host-supervised clients or one connection-generation-scoped client whose
  lifecycle drains and stops after rotation, revocation, expiry, or removal;
- connection revision, credential version, and monotonic generation fences;
- remote schema hashes, live schema re-checks, and rejection when the selected
  schema has changed;
- disabled retry for tool calls and explicit `sent_outcome_unknown` classification;
- normalized and sanitized result/error envelopes;
- prepare/commit mechanics, expiring secret-free snapshots, confirmation metadata,
  and host-owned one-use execution claims for sensitive mutations;
- deterministic catalog metadata, restrictive packs, stable fingerprints, and
  schema-rich `Catalog.Item` values for statically authored Connect integrations.

These could remove meaningful custom code from endpoint credential lifecycle,
authorization, schema-drift fencing, and uncertain-write handling.

### What it does not replace for Vxpipe

The proposed bridge does not solve Vxpipe's agent-visible dynamic tool contract:

- It exposes two static Connect operations. Discovered remote tools remain result
  data from `mcp.tools.list`; the bridge does not create one `Catalog.Item` or one
  Jido Action per remote tool.
- Connect explicitly rejects the generic MCP list/call operations from a reviewed
  catalog pack. Its catalog packs therefore cannot directly represent Vxpipe's
  per-agent allowlist of arbitrary tenant-discovered remote tools.
- `mcp.tool.call` still accepts model-sensitive `endpoint_id`, `tool_name`, and a
  generic `arguments` map. Exposing it directly would violate Vxpipe's local alias,
  private endpoint selection, and exact per-tool input-schema boundary.
- The generic operation classifies every remote call as an external write requiring
  AI confirmation. MCP discovery does not reliably say whether a tool is a read or
  mutation, so Vxpipe still needs its own enabled-tool policy and execution semantics.
- The reviewed code compares pinned and live schemas but does not establish
  Vxpipe's required JSON Schema 2020-12 validation of the actual outgoing arguments.
- It performs one `tools/list` call rather than Vxpipe's bounded whole-pagination
  discovery contract.
- It defaults to MCP `2025-06-18`; compatibility and conformance with Vxpipe's
  selected `2025-11-25` profile are not demonstrated.
- It has no demonstrated cumulative decoded/decompressed response-size enforcement,
  redirect/DNS-rebinding/private-address policy, or the full deadline model required
  by the MCP milestones.
- It does not own call-plan pinning, background operation supervision, result
  projection, client visibility, persistence, room-incarnation checks, or the
  application/tenant precedence rules.

The safe composition would keep every enabled remote tool as a Vxpipe data
descriptor with its local alias and exact pinned schema. `Vxpipe.Tool.Executor`
would resolve that private binding and invoke Jido Connect's static MCP bridge
internally. The model would never receive the bridge's endpoint or remote tool
selectors. This avoids externally driven atom/module creation but also means Jido
Connect is not the missing dynamic Jido AI Action surface.

### Earlier Connect recommendation — superseded by the released-package follow-up

Do not adopt the current default-branch `jido_connect_mcp`, because it still uses
Jido MCP. Do not pin Vxpipe to the unmerged replacement pull request. Re-evaluate a
published, stable core Jido Connect release after it lands, then run a focused spike
against Vxpipe's protocol revision, dynamic data-tool, argument-validation,
transport-security, response-limit, and Jido AI dependency gates.

If that release passes, use core Jido Connect for the narrow list/call and
connection-safety layer, use its ExMCP dependency only through Connect's public API,
and keep Vxpipe's data-backed model tool catalog and call-specific policy boundary.
If it fails those gates or remains unavailable when implementation begins, use
ExMCP behind `vxpipe_mcp` directly rather than adopting a maintenance-bound package.
At this historical checkpoint the milestones had not changed. The subsequent requested
investigation below selects ExMCP now and updates them coherently; a stable future
Connect release can be reconsidered without making its release a prerequisite.

## Released-package loop and tool-interface investigation

The user asked whether Jido would still own the LLM loop with a direct MCP client and
requested appropriate milestone corrections. Reused this research labnote rather than
opening a second task log.

- Installed Jido AI 2.3.0, Jido Action 2.3.2, ReqLLM 1.22.0 and ExMCP 1.3.0 together
  in an isolated `Mix.install` probe, outside the umbrella. Dependency resolution,
  compilation and application startup succeeded under Elixir 1.19.5. No repository
  dependency or lockfile changed.
- Ran five deterministic ExUnit compatibility checks: **5 tests, 0 failures**. The
  positive control scripted two successive model-requested Action calls followed by
  a final answer, proving Jido performs the repeated loop without Vxpipe orchestration
  of those rounds. Both instrumented Action executions were observed.
- Negative controls confirmed runtime descriptors and `ReqLLM.Tool` callback values
  are rejected by tool selection. A registry alias is lost in model projection, and
  two aliases of one Action raise duplicate tool names. The dependency version
  combination is usable; exact dynamic model-tool exposure is not plug-and-play.
- Inspected released `ToolAdapter`, `ToolSelection`, `Config` and `Runner`, then checked
  current-main request transformation/interception. The runner normalizes Action-module
  selection and regenerates `llm_opts[:tools]` after the transformer. The current-main
  interceptor can change arguments, not select an alternate executor, and is reached
  only after Action resolution. That newer hook is not in the tested 2.3.0 release.
- The required extension is a public runtime descriptor/projection and private execution
  binding interface inside Jido's existing loop. Prefer upstream support. No private
  monkey-patch, fork, upstream issue/PR or replacement loop was created/authorized.
- ExMCP 1.3.0 documents public client discovery/invocation and an explicit legacy-only
  `2025-11-25` transport profile. Its retry/stream-reissue policies and bundled validator
  still require verification against our no-resubmission and 2020-12 validation rules;
  a dependency resolution probe is not a transport conformance result.
- Updated the existing 21-milestone plan without renaming filenames or reordering it.
  The protocol-only MCP checkpoint no longer depends on Jido or dynamic model exposure.
  Live MCP owns the public runtime-tool interface gate. Early static-tool slices reject
  aliases differing from Action names until that interface exists; the final definition
  alias contract remains intact. Streaming/AgentServer integration is still unimplemented.
- Synchronized architecture, decision register, original call-definition labnote and
  dependency documentation links. Existing protocol, security, background-worker,
  visibility and privacy requirements remain; no implementation checkbox was checked.

The initial probe invocation from a temporary working directory could not find the
project-selected Elixir runtime. Running through the project shell activated it and
completed the five checks. Source inspection and failed workarounds are recorded in
[the focused decision](../docs/jido-tool-execution.md); no credentials or live services
were used. Repository documentation verification is recorded at completion below.

Completion verification for this follow-up:

- `git diff --check` passed.
- All 128 relative file links and 39 heading links in the 13 changed/new Markdown
  documents resolved. The index maps exactly to 21 distinct milestone files.
- Fenced examples in the architecture, decision register and original call-definition
  labnote are unchanged from the committed baseline. Research terminology checks passed.
- Reviewed the dependency-selection and prerequisite diffs: protocol/security gates and
  background/visibility contracts remain; no milestone implementation box was completed.
- The isolated compatibility probe passed five checks. No umbrella, browser, live-provider
  or MCP-conformance tests were run: this is a documentation/research checkpoint, not an
  application dependency change or a shipped integration.

## Verification evidence

### Earlier milestone-plan update

- Kept the existing 21 milestone files and ordering rather than adding a horizontal
  dependency-adoption milestone.
- Added the Jido AI AgentServer and Jido Action migration to the definition-driven
  one-agent vertical slice, with AgentServer limited to the supervised inference
  child role.
- Made Call Variables tools Jido Actions while retaining the room-owned variables
  process as their authority.
- Kept submitted long-running actions in independently supervised Vxpipe workers;
  Jido receives a running acknowledgement and remains available for conversation.
- Replaced the direct MCP-client milestone with Jido MCP integration/conformance and
  updated live remote-tool integration to use Jido MCP through `vxpipe_mcp`.
- Removed direct transitive MCP-client selection from durable architecture, milestone,
  issue, decision-register and documentation-reference surfaces. Jido MCP's internal
  dependency choice is not a Vxpipe planning concern.
- Completed focused review of the five materially changed specifications; no
  implementation checkbox was marked complete.
- Verified changed Markdown relative links, milestone index/file count, whitespace and
  prohibited-term hygiene for this labnote. No runtime dependency, test, browser run or
  conformance result is claimed by this documentation checkpoint.

Local inspection:

- inspected the current model provider behavior, ReqLLM adapter, inference
  capability, and tool executor;
- inspected the planned agent, background-tool, MCP, variables, compaction, and
  usage milestones;
- inspected the sibling Callx Jido Action and LLM adapter usage;
- confirmed the locked ReqLLM version is 1.22.0.

### Focused follow-up review

Inspected the upstream default branches at these revisions on 2026-09-08:

- Jido AI `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2`;
- Jido Action `5d25c655f49a80643f0ccbfe2be90be3bbe68f6e`;
- Jido MCP `627251e46db19387c6404f1a04e4e4207be74f98`.

Evidence observed:

- `Jido.AI.Agent` provides request handles/event streams, runtime tool registration,
  request-scoped tools/context, system-prompt updates, and a ReAct-owned task
  supervisor. Its strategy reads the model from initialized agent state and defaults
  overlapping requests to rejection.
- Jido Actions are modules with runtime input validation. Platform actions can be a
  finite application-owned set; per-call variable grants/schemas remain engine data.
- Normal ReAct waits for a completing action. `inject`/`steer` is active-run-only,
  best-effort input, so it cannot acknowledge durable-in-memory late-result delivery.
- Jido MCP's public sync action targets a running Jido AI agent. Its current proxy
  generator is private, rejects string endpoint IDs, creates modules derived from
  discovered definitions, and unsync can purge module code but not atoms.
- The generic public MCP call Action would expose model-selectable endpoint/tool
  fields and cannot present each binding's pinned schema.

Required corrections were applied to the agent, Call Variables, background-tool,
MCP integration and live-MCP specifications, their index, and durable architecture.
The review marks the specifications complete while keeping implementation checkboxes
unchecked and making the MCP compatibility blocker explicit.

Follow-up documentation verification:

- `git diff --check` passed.
- All relative links in the ten changed documentation files resolve locally.
- The index still maps exactly to 21 descriptive milestone files, with no open
  follow-up-review markers.
- The two newly added HexDocs links and the commit-pinned tool-sync/proxy source links
  returned successful HTTP responses.
- The labnote terminology check passed.
- An initial nested-shell URL check expanded its loop variable in the wrong shell and
  produced an empty-host error; the direct `curl` checks above replaced that invalid
  result.
- No runtime, browser, provider, conformance, or umbrella test was run because this
  checkpoint changes documentation only.

### Jido Connect follow-up

- Inspected default-branch Jido Connect revision
  `02cb6cbdc3e720922b7c3805e8ecdebb6e60461c`, including the core catalog,
  generated-module, authorization, credential-lease, MCP bridge, endpoint lease,
  schema compatibility, and runtime paths.
- Inspected the migration issues and open pull request 75 at
  `8880808d88918c1774ec147ff31d7fe15d244d34`, including the core ExMCP adapter,
  connection-scoped client lifecycle, bridge guide, dependency graph, tests, and
  recorded release checks.
- Confirmed through the Hex API that `jido_connect` has no published package, and
  through the GitHub API that pull request 75 remains open with a merge conflict;
  its recorded quality check succeeded.
- Compared the proposed bridge with Vxpipe's existing standalone and live MCP
  milestone gates. No dependency was added and no runtime/conformance claim was
  made.

Primary package and project references:

- [Jido AI package dependencies](https://hex.pm/packages/jido_ai/2.3.0/dependencies)
- [Jido AI overview](https://jido-ai.hexdocs.pm/Jido.AI.html)
- [Jido AI standalone ReAct runtime](https://hex.pm/packages/jido_ai/2.3.0/files/guides/user/standalone_react_runtime.md)
- [Jido AI ReAct configuration](https://hex.pm/packages/jido_ai/2.3.0/files/lib/jido_ai/reasoning/react/config.ex)
- [Jido AI ReAct runner](https://hex.pm/packages/jido_ai/2.3.0/files/lib/jido_ai/reasoning/react/runner.ex)
- [Jido AI request lifecycle](https://jido-ai.hexdocs.pm/request_lifecycle_and_concurrency.html)
- [Jido AI thread and context projection](https://hex.pm/packages/jido_ai/2.3.0/files/guides/developer/thread_context_projection_model.md)
- [Jido AI request transformer](https://hex.pm/packages/jido_ai/2.3.0/files/lib/jido_ai/reasoning/react/request_transformer.ex)
- [Jido Action 2.3.2](https://hex.pm/packages/jido_action/2.3.2)
- [Jido Action execution](https://jido-action.hexdocs.pm/Jido.Exec.html)
- [Jido Action schema validation](https://jido-action.hexdocs.pm/schemas-validation.html)
- [Jido MCP 1.1.1 dependencies](https://hex.pm/packages/jido_mcp/1.1.1/dependencies)
- [Jido MCP 1.1.1 README](https://hex.pm/packages/jido_mcp/1.1.1/files/README.md)
- [Reviewed Jido MCP tool-sync source](https://github.com/agentjido/jido_mcp/blob/627251e46db19387c6404f1a04e4e4207be74f98/lib/jido_mcp/jido_ai/actions/sync_tools_to_agent.ex)
- [Reviewed Jido MCP proxy source](https://github.com/agentjido/jido_mcp/blob/627251e46db19387c6404f1a04e4e4207be74f98/lib/jido_mcp/jido_ai/proxy_generator.ex)
- [Reviewed Jido MCP generic call Action](https://github.com/agentjido/jido_mcp/blob/627251e46db19387c6404f1a04e4e4207be74f98/lib/jido_mcp/actions/call_tool.ex)
- [Jido agent runtime](https://jido.run/docs/concepts/agent-runtime)
- [Jido Connect repository](https://github.com/agentjido/jido_connect)
- [Jido Connect migration issue](https://github.com/agentjido/jido_connect/issues/69)
- [Jido Connect ExMCP bridge issue](https://github.com/agentjido/jido_connect/issues/71)
- [Jido Connect replacement pull request](https://github.com/agentjido/jido_connect/pull/75)
- [Jido MCP maintenance issue](https://github.com/agentjido/jido_mcp/issues/52)
