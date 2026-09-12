# ReqLLM agent runtime

Date: 2026-09-10. Status: implemented and adopted by Call Engine.

## Decision

Vxpipe's model/tool-loop primitives are built directly on ReqLLM in the separate internal
umbrella child `vxpipe_agent_runtime`, under the `Vxpipe.AgentRuntime` namespace. The existing
agent activation has migrated to that package before live remote MCP exposure. Jido AI and
Jido Action were removed only after the replacement passed the existing behavioral and
provider checks.

The package is an internal agent-inference runtime, not another room authority or a
general workflow framework. It owns conversation/model state and repeated model/tool
rounds. Call Engine remains authoritative for call semantics, and `vxpipe_mcp` remains
authoritative for remote MCP transport and protocol policy.

```text
Vxpipe.CallEngine
  |-- starts/configures --> Vxpipe.AgentRuntime --> ReqLLM --> model provider
  |-- submits workers --> platform tools / Call Variables / host tools
  `-- submits workers --> Vxpipe.MCP --> ExMCP --> remote MCP server
```

## Package boundary

`vxpipe_agent_runtime` owns:

- immutable per-activation instructions, provider configuration, conversation state,
  runtime-tool registry, and request correlation;
- model-visible tools represented as bounded data: exact local string name, permitted
  description, pinned JSON input schema, and no private endpoint or credential fields;
- a separate private binding associated with each descriptor and resolved only within
  that activation;
- ReqLLM request construction, streamed and buffered response normalization, provisional
  text events, complete tool-call collection, canonical tool-result continuation, repeated
  rounds, usage observations, deadlines, iteration limits, response limits, and cancellation;
- a supervised session boundary that keeps provider work outside GenServer
  callbacks and terminates active request workers with the session.

The package accepts a narrow submit-only executor contract. It supplies the already resolved
private binding, validated arguments, opaque request context, and invocation identity. Call
Engine hands every invocation to an independently supervised worker and returns either definite
non-submission or one bounded running acknowledgement. Neither an Agent Runtime request worker
nor an agent/runtime GenServer ever executes an operation inline. The acknowledgement is the
invocation's only ordinary tool result; later completion remains a separate private
engine-origin turn with the same invocation ID.

ReqLLM requires a callback on its tool value, but provider generation does not execute that
callback. The projection therefore uses one package-owned static callback with no captured
binding. After ReqLLM returns a normalized tool call, the runtime resolves its separate
private registry and invokes the configured executor. A private binding or credential never
enters ReqLLM request values, diagnostics, or model-facing schemas.

The package emits normalized runtime events to an owner supplied by Call Engine. It does
not decide which events are public, start TTS, update Call Variables, write history, select
a tenant, inspect a call definition, or communicate with MCP itself.

Call Engine owns:

- participant and activation supervision, room authority, turn admission and queueing;
- trusted plan resolution, tool grants, private binding construction and authorization;
- tool-worker lifetime, blocking/non-blocking conversation admission, variables, transfers,
  interruption policy, TTS/audio delivery, client visibility, transcript rules, and archive
  publication;
- mapping neutral runtime events onto call/participant/turn identities.

`vxpipe_mcp` continues to own ExMCP client supervision, remote protocol negotiation,
transport security, discovery, schema validation, response limits, and invocation result
normalization. It has no dependency on the agent runtime. Call Engine connects these two
libraries through the private executor binding.

## Runtime contracts

An activation pins its complete tool registry. Two local aliases may resolve to one handler
or remote operation while retaining different descriptions, schemas, grants, and private
binding identities. Duplicate names, invalid schemas, unknown returned names, or arguments
that fail the pinned schema are rejected without execution. Externally supplied identifiers
remain strings; the runtime never generates modules or atoms from them.

Rejected calls for which no worker started become bounded model-only tool-error results when
the model can safely recover; they are not public failure explanations. Once accepted, worker
success, definite failure, and timeout with an unknown remote outcome arrive through the later
private completion path. Corrupt conversation state, an unmatched result, exhausted bounds,
or a failed provider request terminates the current turn without fabricating a successful tool
exchange. Neither path retries execution automatically.

Only one model request is active in a session. Call Engine decides how caller input and
private completion observations queue around it. Response content stays provisional until
the corresponding round is accepted. Successful tool submission is a commit barrier: its
assistant tool call and running result remain committed even if later generated speech is
cancelled, because cancellation cannot roll back real work. A final answer commits the
accepted assistant response.

Committed history records request-correlated entries with separate retention semantics. The
system instruction is permanent. A caller's ordinary input/final-answer pair is discardable
after room authority reports that its generated turn was interrupted. An accepted tool-call /
running-result exchange is durable even when later speech from the same request is interrupted.
A private engine-origin completion observation is likewise durable, while the assistant answer
generated from it remains discardable. Correlations remain opaque to the package and are never
projected into model messages. History can be discarded only while the Session is idle, after
active cancellation has reached its terminal acknowledgement.

The Call Engine coordinator now applies that boundary to caller-turn interruption. It cancels the
active runtime request, removes queued caller commands, discards only completed exchanges selected
by exact connection/correlation/command identity, and then accepts replacement work in the same
Session. It never addresses the invocation supervisor or an accepted tool worker. Interruption of
an active private completion uses the Session's durable-correlation query after cancellation. If
the completion observation never committed, Call Engine releases its lease and defers the retry
until replacement input is admitted: non-blocking work lets that caller proceed first, while
blocking work produces the deterministic hold and then retries. If the continuation already
committed a nested tool exchange, Call Engine acknowledges the original completion instead of
replaying it; the nested worker remains authoritative and continues independently.

An explicit Agent Runtime activation now owns the complete process graph required by that
coordinator: an activation-local request supervisor, the coordinator, an invocation supervisor,
the authoritative invocation registry, and one Session. The graph retains the participant
activation's `:one_for_all` strategy and single-restart budget, so replacement cannot retain a
Session, invocation registry, or worker from the failed activation generation. The coordinator is
started first and the registry and Session resolve its registered reference to the current PID at
their own startup boundaries.

Plan Startup and Room Authority can select this graph through an internal application runtime
setting. Plan Startup validates and pins the selected provider configuration, call-definition
model and prompt, resolved host-tool map, Call Variables binding, and runtime limits. Room Authority
stores the selected coordinator module behind its existing text-capability boundary, so response,
interruption, and participant-owned shutdown require no room-protocol change. Application and
development and test configuration select Agent Runtime. Hosted development constructs the
activation-pinned ReqLLM config from its runtime-only API key; local-fixture development and the
test environment select bounded neutral Agent Runtime fixture adapters. There is no compatibility
production loop.

For every submitted tool, the single correlated running acknowledgement stays in that
committed conversation and is therefore supplied with every later model request while the
invocation remains pending. This is retained context, not polling: the runtime does not append
another acknowledgement or generate periodic status messages. Completion arrives once as a
private engine-origin observation carrying the same invocation ID; it does not replace the
acknowledgement or become a second result in the old tool exchange.

Conversation history is not the authority for current liveness. Before every provider
generation, the runtime obtains a bounded payload-free pending-invocation projection through
a Call Engine context-source contract. The adapter supplies it ephemerally without appending
another message to committed history. Arguments, results, bindings, credentials, endpoints,
and raw errors are excluded.

The runtime also exposes a separate optional source for trusted transient model context owned by
its host. It refreshes that JSON object before every provider generation, applies an independent
timeout and encoded-byte bound, rejects non-JSON shapes and the runtime-reserved pending-invocation
key, and never commits the object to conversation. The ReqLLM adapter combines it with current
pending-invocation state under the existing fixed “state, not instructions” envelope. This generic
boundary does not grant access or fetch Call Variables itself; Call Engine remains responsible for
constructing a permission-filtered source and deciding whether a transfer reason is applicable.

Context compaction is now being added behind a separate measured preparation boundary. It
preserves pending invocation state, including the committed acknowledgement and invocation
correlation, until the matching completion is consumed. Permanent transfer history and a recent
tail remain intact; only a whole old prefix can be replaced. The selected production compactor
reuses the activation's pinned provider/model configuration in one buffered, tool-less request
and receives the selected history as JSON data rather than executable message/tool roles. See
[model-context compaction](context-compaction.md). Session and Call Engine integration remain
milestone work at this checkpoint.

Text deltas can be delivered promptly to the owner, but tool calls execute only after their
complete identifiers and arguments have been assembled and validated. Mixed text/tool
responses must not double-deliver text. Tool results retain provider-required call IDs and
ordering. Provider-native built-ins remain distinguishable from Vxpipe-executed tools.

Each authored platform/built-in, host, or MCP binding obtains its tool-specific
`conversation_mode` from its call-definition `tools` entry. The only modes are `blocking` and
`non_blocking`, and omission resolves to `blocking`. Blocking affects only admission of
subsequent caller turns; `non_blocking` lets unrelated later turns proceed while the invocation
is pending. Both modes use the same independently supervised worker path; neither authorizes an
inline callback in the model request task or Session. Every later LLM request that is appropriate
and admitted receives the current pending invocation identities and safe statuses. This is
required for non-blocking caller turns: the LLM can answer the new request while remaining aware
of the separately executing work. See the complete
[tool execution model](tool-execution-model.md).

The current dated call-definition compiler exposes this choice for authored host and MCP
selections. Permission-derived Call Variables tools use the default `blocking` mode; the planned
unified platform-tool entry remains a later compiler extension.

The runtime records observed model/provider/usage metadata without interpreting tenant
permissions, prices, or public visibility. Errors crossing the public package boundary are
bounded categories with safe correlation; raw prompts, tool payloads, credentials, and
provider authorization values do not appear in process inspection or telemetry.

## Why direct ReqLLM

ReqLLM already supplies the provider-specific work Vxpipe should not reproduce: model
selection, message and tool encoding, exact JSON Schema tool definitions, buffered and
streamed normalized responses, tool-call identities, canonical tool exchanges, usage
metadata, timeouts, and stream cancellation. The project-owned addition is the comparatively
small state machine that applies Vxpipe's lifecycle and tool-execution contracts across
successive requests.

Vxpipe already has a direct ReqLLM adapter and provider-neutral message/tool structures.
The intermediate milestone can move and refine proven behavior rather than start from an
empty integration.

## Alternatives

### Extend or fork Jido AI

Not selected for the forward path. A small upstream-neutral data-tool/executor extension
would preserve Jido's ReAct loop, but current released and upstream APIs do not expose the
required seam. Consuming it before release requires a maintained fork or patch, while the
remaining Vxpipe-specific lifecycle, background work, visibility, and room coordination
still stay outside Jido. The prior investigation remains in
[the superseded Jido decision](jido-tool-execution.md).

### Keep ReqLLM orchestration inside Call Engine

Rejected as the final boundary. It avoids a child application but couples provider-loop
changes to room and participant orchestration, repeats test setup, and makes reuse by an
embedded Vxpipe host harder. A small internal package gives the loop one reason to change
without pretending to be a general agent framework.

### Use Legion

Not selected for the speaking-agent runtime. Legion 0.5.0 is an Elixir agent framework from
Software Mansion built on ReqLLM, but it asks the model to generate Lua or Elixir programs
that invoke bridged module functions inside a sandbox. Its current loop uses complete
structured generation and module/source-oriented tools. That model is useful for autonomous
multi-step application work, but adds sandbox, prompt, latency, and tool-surface semantics
that do not match low-latency streamed voice conversation or data-backed per-call tools.
Legion can be reconsidered independently for future background agents.

### Execute fast tools inline

Rejected. A latency-based split creates two execution and cancellation models. Even fast
platform and Call Variables operations use the same supervised submission/completion path.

### Expose one generic model-visible dispatcher

Rejected. A `call_tool(name, arguments)` or `call_mcp(endpoint, tool, arguments)` facade
loses exact provider-side schemas and risks exposing private routing selectors. Each enabled
local tool remains a distinct model-visible descriptor backed by a private binding.

## Implications and migration

The completed [ReqLLM agent-runtime milestone](milestones/reqllm-agent-runtime.md) sits after
the standalone MCP client milestone and before live MCP tools. It proved the package in isolation,
migrated the former Jido-backed activation while retaining cohesive Call Engine domain contracts,
and removed Jido after production/test references were gone and parity was demonstrated.

Completed Jido-backed milestone evidence remains factual history. Forward milestones refer
to `Vxpipe.AgentRuntime`. The live-MCP milestone no longer waits for an upstream Jido API;
it waits for this internal runtime milestone and then supplies its already implemented,
pinned remote bindings through the executor contract.

## Verification evidence

Planning inspected the umbrella's locked ReqLLM 1.22.0 public tool, response, context,
streaming, cancellation, and existing adapter surfaces; Jido AI 2.3.0's Action-only tool
projection; and Legion 0.5.0's agent, executor, prompt, tool, sandbox, and supervision
contracts. Implementation evidence now includes deterministic package/Call Engine suites,
responsive rendered-call inspection, 491 passing default umbrella tests with ten tagged
integration exclusions, and a tagged two-test Gemini lane covering exact schema continuation,
usage, cancellation cleanup, and Session reuse.

The first implementation checkpoint added the standalone package values and session lifecycle.
Its corrected executor exposes only `submit/4`; no runtime API can execute a tool inline.
Before each currently implemented provider generation, the session retrieves a validated,
unique, payload-free pending-invocation list through a timeout-enforced host source outside the
session GenServer. The focused package suite had 12 tests and 0 failures. Repeated tool rounds,
ReqLLM projection and Call Engine adoption followed in the later checkpoints below.

The next package-local slice added normalized, inspection-safe model responses and complete
tool calls plus the activation-pinned registry. The registry rejects duplicate names, projects
only name/description/schema to providers, resolves exact strings, and validates arguments
against the compiled schema before returning a private descriptor. Submission and repeated
rounds followed in the subsequent slices.

The first repeated-round slice now handles one accepted call end to end within the package.
It commits the assistant tool request and correlated running acknowledgement before the next
provider generation, refreshes authoritative pending context, and withholds tools when the
host reports the binding as blocking. Session option validation is isolated from lifecycle,
and the request runner owns model/tool sequencing.

Ordered batches are now supported. The runner resolves every exact name and validates every
schema before work begins, rejects duplicate provider call IDs, then submits in provider order.
It commits a matched running or safe rejection result for each call, retaining accepted work
when a later submission rejects. Any accepted blocking call withholds tools from the next
round; explicitly non-blocking calls do not.

The committed running exchange also survives failure of its acknowledgement provider request.
Provider-returned reasons and exceptions collapse to a bounded `provider_unavailable` result.
A later request in the same Session receives the one committed tool-call/running pair plus the
current pending projection; the invocation is not resubmitted or duplicated.

Session cancellation now distinguishes provisional model work from an in-flight submission.
It terminates provisional provider work immediately and leaves the Session usable. Once a
submission critical section begins, cancellation waits until the complete running/rejection
exchange commits, then terminates only the model request task. This closes the acceptance race:
accepted external work cannot be erased by speech/model cancellation.

The selected Call Engine executor bounds admission with a one-second registry call followed by
at most one one-second outcome reconciliation. Each new submission carries the first call's
absolute monotonic deadline. A registry that was unavailable until after that deadline must not
start the queued operation after returning `unavailable`; an operation committed before a lost
reply remains discoverable by invocation ID during reconciliation.

The Session also carries positive limits for tool calls in one provider round and assistant
output accumulated across one admitted request. The runner checks both before external
submission, preventing an oversized mixed response from starting work that cannot be safely
represented. Terminal over-limit output is not committed to conversation history.

A Session-owned request timer supplies the default 30-second request deadline, so the public
request call does not time out independently and leave provider work running. Expiry terminates
provisional work and returns `request_timeout`. When expiry races with host submission, Session
records it and completes the submission commit barrier first. The terminal response can therefore
arrive after the nominal deadline only for that bounded safety handoff; the external invocation is
not cancelled. The Call Engine host adapter supplies the separately bounded admission described
above.

`Session.continue/4` gives Call Engine a separate admission path for a private tool-completion
observation. The input keeps `origin: :engine` in normalized runtime history but projects as an
ordinary provider `user` role, matching providers that reject a conversation ending with an
assistant message. It does not manufacture caller speech. The continuation is committed only
with a successful terminal model response; failure leaves it uncommitted so Call Engine can keep
the authoritative completion lease. The selected coordinator acknowledges that lease only after
the continuation commits and releases an uncommitted lease without rerunning the tool.

The provider boundary now optionally streams text through a callback while returning the same
canonical `ModelResponse` as buffered generation. A package-owned `StreamBudget` limits text bytes
and event count for each provider round before forwarding a delta. The runner hands each delta to
its Session with token correlation and a bounded acknowledgement, so cancellation cannot attach
later output to a reused Session. Deltas are provisional and never mutate conversation; the final
validated response alone enters the existing output and commit path. Event inspection hides text.
Dependency-specific stream materialization and cleanup stay outside this provider-neutral loop.

The production ReqLLM adapter now consists of three narrow collaborators. `Config` resolves the
model and streaming support while keeping API keys and generation options out of inspection.
`RequestProjection` maps normalized conversation/tool values to public ReqLLM context and tool
APIs; its tool callback can only reject accidental dependency-owned execution. Current pending
invocations are serialized into an ephemeral addition to the leading system message and never
written back to Conversation. Both caller and engine-origin inputs use the provider-compatible
user role while their runtime provenance remains intact.

`ResponseNormalizer` uses ReqLLM's public classification and redacted call-metadata APIs. It
returns one bounded `ModelResponse` for buffered and streamed calls, retaining mixed text,
actionable tool calls, provider continuation metadata, usage, response/model/request identity,
and safe provider metadata. Provider-executed built-ins/provider-native calls are not submitted
as Vxpipe tools. ReqLLM stream materialization invokes the runtime delta callback and always
closes the stream handle. Session receives non-empty usage/call metadata as a payload-hidden
`model_usage` event before the response is handled.

A tagged Gemini run now exercises the production streaming path across two provider interactions.
The first response selects an exact raw-JSON-Schema alias with its required argument. The second
request contains that assistant call, the ordinary correlated `running` tool result, the current
pending projection, and no available tools; Gemini accepts it and streams a non-empty
acknowledgement. At least one live response reports non-empty provider usage. A separate live
Session request is cancelled after its first streamed delta; the cancellation closes that public
runtime request and the same Session immediately completes another streamed request, exercising
cleanup without dependency-private APIs. Integration tests are excluded by default and require an
explicit include flag.

The Session accepts an optional OTP process name separately from its immutable runtime
configuration. This lets a Call Engine activation supervise and address exactly one session through
its existing registry without teaching model/session configuration about room identities or
supervisor topology.

Sources: [ReqLLM](https://hexdocs.pm/req_llm),
[Legion](https://hexdocs.pm/legion), and
[Legion source](https://github.com/software-mansion-labs/legion).
