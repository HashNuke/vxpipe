# Vxpipe protocol and runtime architecture

Status: Living architecture; room creation, one-participant RTVI connection,
text-turn, Gemini model-inference, Deepgram Flux audio-input, and Deepgram Flux
text-to-speech, typed interruption, and provider-driven spoken barge-in slices
are implemented, along with bounded asynchronous private call history

## Decision

Vxpipe will provide a protocol-neutral, OTP-native voice runtime. Client and
provider protocols will be adapters at the gateway boundary rather than types
embedded in the call engine.

The first client adapter will support unmodified current RTVI 2.x clients and
the RTVI 2.1 feature set. RTVI is one supported access mechanism, not Vxpipe's
internal protocol or permanent public object model. A future custom protocol or
another client standard must be able to drive the same engine commands and
consume the same domain events without changing the engine.

This document refines the initial ideas in
[`labnotes/20260903-0323-vxpipe-thoughts.md`](../labnotes/20260903-0323-vxpipe-thoughts.md)
using the Callx findings in
[`labnotes/20260902-1743-investigate-callx-architecture.md`](../labnotes/20260902-1743-investigate-callx-architecture.md)
and the current [RTVI standard](https://docs.pipecat.ai/client/rtvi-standard.md),
[RTVI server reference](https://docs.pipecat.ai/api-reference/server/rtvi/introduction.md),
and [RTVIProcessor reference](https://docs.pipecat.ai/api-reference/server/rtvi/rtvi-processor.md).

The document primarily describes the intended Vxpipe contract. The implemented
vertical slices are called out below; later sections and checkpoints remain
proposed unless stated otherwise.

## Why support RTVI

RTVI supplies a useful client-facing vocabulary and existing client SDKs. Its
standard messages cover readiness, speaking state, user transcription, bot
output, LLM and TTS activity, client-side function calls, text input, DTMF,
metrics, custom requests, and UI interaction. Pipecat clients already handle
media devices, transports, session state, and these messages across web and
mobile environments.

Supporting RTVI at the gateway provides:

- unmodified Pipecat client compatibility;
- a faster path to browser and mobile clients;
- a familiar readiness and conversation event model;
- transport-independent application messages above WebRTC or WebSocket;
- existing APIs for custom fire-and-forget messages and correlated requests;
- client-side tool handlers, DTMF, text input, and media-device controls; and
- a stable baseline against which a richer Vxpipe client can be introduced.

RTVI does not define everything Vxpipe needs. Authentication and transport
credential issuance occur outside the RTVI envelope. Its user-and-bot vocabulary
does not provide a complete multi-participant room, connection, track, telephony
leg, transfer, durable event, replay, authorization, cluster-placement, or
supervision model. Reconnection starts a new client connection rather than
defining durable room resumption.

RTVI must therefore remain a client projection over the engine rather than the
engine's source of truth.

## RTVI and Callx serve different boundaries

The existing Callx work is stronger than RTVI as a description of an internal
voice runtime. It models rooms, participants, transport connections,
capabilities, topic authorization, transfers, DTMF collection, tool invocations,
and room lifecycle. Its room process serializes authoritative state changes,
while OTP supervisors and monitors isolate runtime workers.

Callx is not a suitable public wire protocol in its current form. Its API and
events contain Elixir structs, atoms, modules, functions, PIDs, and private
adapter state. It has no wire schema or protocol version, committed events lack
durable event IDs and room sequence numbers, event history retains raw audio
without a bound, and synchronous hooks or subscribers can delay the room
mailbox. A room-authority crash can also restart that authority beside surviving
workers.

Vxpipe will retain the useful Callx domain distinctions while replacing its
in-process event surface with explicit protocol-neutral contracts.

| Concern | RTVI | Current Callx | Vxpipe choice |
| --- | --- | --- | --- |
| Existing clients | Cross-platform SDKs | No public clients | RTVI gateway adapter |
| Readiness and conversation UI | Standard client events | Internal topic events | Project engine events into RTVI |
| Rooms and participants | Primarily client/user and bot | Rich room model | Call-engine domain resources |
| Telephony legs and transfers | Not a complete model | Explicit state machines | Call-engine resources and events |
| Internal scheduling | Outside the protocol | OTP processes | Redesigned OTP runtime |
| Wire contract | JSON messages | BEAM terms | Versioned gateway codecs |
| Durability and replay | Not defined | Unbounded in-memory history | Bounded journal and snapshots |
| Authentication | Outside RTVI | Host-specific | Gateway session and operation scopes |

## Domain terminology

Vxpipe uses **capability** for behavior available to a participant. Capability
kinds include speech-to-text, model inference, text-to-speech, input and output
guardrails, recording, and other composable voice-runtime functions.

The related terms have distinct meanings:

- A **participant** has zero or more configured capability instances.
- A **capability kind** defines the provider-neutral contract and the events it
  consumes and publishes.
- A **capability instance** is one participant's resolved runtime attachment,
  including its provider selection, options, lifecycle, and routing policy.
- A **provider** supplies an underlying external function, such as hosted
  speech recognition, model inference, or speech synthesis.
- An **adapter** implements a capability contract for a provider and translates
  between provider-native data and Vxpipe commands, frames, and events.
- A **service** is an external system or an independently deployed application,
  not the generic name for a participant's runtime behavior.

For example, a human participant may have a `speech_to_text` capability instance
implemented by a provider adapter. An AI participant may have model-inference,
text-to-speech, and guardrail capability instances. Whether an adapter uses a
remote API or in-process code does not change the participant-facing capability
contract.

Vxpipe will not initially define a standalone voice-activity-detection
capability or run local speech/model inference such as Whisper. Selected hosted
STT providers are responsible for their supported speech-activity, endpointing,
and transcription behavior. When a provider emits speech-activity or endpointing
evidence, its adapter normalizes that evidence into Vxpipe turn events; the call
engine does not run a separate detector.

### Call variables, conversation history, and model context

The approved call-definition design uses **Call Variables** for typed, shared
values grouped into sections. For example, `booking` is a section and `status`
is a variable within it. Use "variable", not "field", for these named values.
Object-valued variables may contain nested data without adding a path language.

**Conversation history** contains messages and tool calls/results. A spoken
transcript is a view of what participants said. **Model context** means everything
supplied to the LLM: instructions, selected history, and permitted call variables.
Neither history nor model context is the mutable variable store.

The selected target places one `Vxpipe.AgentRuntime` session under each active agent
participant's Vxpipe-owned supervision subtree. The separate `vxpipe_agent_runtime`
umbrella child owns ReqLLM conversation state, exact data-backed tool projection, repeated
model/tool rounds, streamed response normalization, cancellation and neutral runtime events.
It does not own room/participant authority, tool authorization or worker execution,
conversation admission, MCP transport, variables, transfers, TTS, client visibility, or
persistence. Those remain Call Engine concerns. See the
[runtime decision](reqllm-agent-runtime.md), [tool execution model](tool-execution-model.md),
and [intermediate milestone](milestones/reqllm-agent-runtime.md).

The package implements the submit-only executor behavior and the bounded, timeout-enforced
pending-invocation context-source boundary. Its package-local loop resolves and validates complete
ordered batches, submits each call, commits a matched running or safe rejection result, refreshes
pending state, and performs the correctly gated acknowledgement round outside the Session
GenServer. Streaming, cancellation, bounded failure, ReqLLM projection, and Call Engine adoption
are implemented; Jido is no longer a runtime or dependency.

Agent Runtime now has a second, host-supplied transient model-context boundary for trusted JSON
state that is not conversation history. It fetches the object outside the Session before every
provider generation, bounds source time and encoded bytes, rejects non-JSON or reserved runtime
keys, and keeps it out of committed messages. ReqLLM combines it with the independently validated
pending-invocation projection in one fixed state envelope. The reusable runtime assigns no room or
variable semantics to this object; Call Engine must supply only the active agent's authorized view.

Within the package loop, an accepted running exchange is durable for the Session lifetime
even if the following provider generation fails. Later turns retain that exchange once and
combine it with the current engine-owned pending projection; a provider failure cannot trigger
resubmission or erase accepted work. Definition-driven live calls use this path.

Session cancellation respects that barrier. It may terminate provisional provider work
immediately, but cancellation arriving during host submission is deferred until the complete
running/rejection exchange commits. The request task is then terminated without touching the
Call Engine-owned invocation worker.

Agent Runtime enforces its configured per-round tool-call count and per-request accumulated
assistant-output size before host submission. These bounds keep one model response from
creating an unbounded worker batch or committing output that the request cannot return.

Each runtime Session also owns its model-request deadline. Expiry closes provisional provider
work and discards uncommitted messages. If a host submission is already in its commit barrier,
the timeout becomes pending until that exchange commits; the runtime then stops only its request
task. A host submission must therefore remain a short, bounded admission operation rather than
performing the business action itself.

Agent Runtime has distinct caller and private engine-origin admission APIs. Both may require a
provider `user` wire role, but normalized messages retain their origin so an external tool
completion is never mistaken for caller speech. A successful private continuation commits the
observation and answer together; a failed one commits neither. Call Engine remains responsible
for retaining the completion lease until that successful result and for suppressing public
caller/transcript projection.

The package's model-provider boundary supports buffered generation and optional text streaming.
Each streamed delta is size/count checked before a token-correlated, timeout-bounded handoff
through the owning Session. Deltas remain provisional output; only the assembled normalized model
response can commit conversation. Request cancellation terminates the streaming request worker and
the Session ignores stale-token messages. ReqLLM-specific stream lifecycle/cleanup belongs to the
production provider adapter rather than this provider-neutral loop.

The production ReqLLM adapter is now package-owned and split by responsibility: secret-safe model
configuration, normalized request projection, and bounded response normalization. It uses public
ReqLLM context/tool/response/stream APIs, injects the current pending-invocation projection only
into the outgoing request, and attaches no engine binding to a ReqLLM tool. Buffered and streamed
responses yield the same runtime value. Usage plus ReqLLM-redacted provider call identity crosses
the token-correlated Session event boundary; prompts, private bindings, raw provider failures, and
authorization values do not. Call Engine selects this adapter for hosted-model live activations.
Session startup also separates its optional OTP process name from immutable runtime configuration,
allowing the activation supervisor to use a stable registry reference without making topology part
of model state.

Call Engine now also has a narrow Agent Runtime coordinator for the migration path. It owns the
bounded caller-turn queue and calls the synchronous `Session.request/4` API from a separately
supervised task, so provider work and streamed-event handling never run in the coordinator
GenServer callback. A dedicated output buffer projects complete sentence segments through the
existing capability-message contract without replaying the final response after streamed deltas.
If streamed output violates the engine bound, the coordinator cancels that runtime request before
admitting queued caller work. The activation supervisor selects this coordinator, and room
interruption routes through its correlation-safe cancellation path.

Before it admits a caller command, the migration coordinator now asks a separate conversation-
admission boundary to inspect the authoritative invocation-registry snapshot. Any unconsumed
`blocking` record—whether running, terminal-queued, or already leased—returns one bounded platform
holding response and never sends that caller text to the model. A snapshot containing only
`non_blocking` records remains admissible, and Agent Runtime independently includes those records
in the request's payload-free pending projection. Registry unavailability fails admission closed.
This gate never executes, waits for, or cancels the tool worker.

Terminal invocation delivery now follows the registry's lease boundary. The coordinator checks for
a terminal completion before caller work, converts the bounded outcome into a `ContinueAgent`
command, and submits it through `Session.continue/4` as private engine-origin input. The continuation
retains the source call/participant/connection identity and whether its output should use TTS; the
tool result remains explicitly marked as untrusted data. Caller input arriving during a leased
non-blocking completion is queued, while a blocking completion still produces the holding response.
The registry record is acknowledged only after Agent Runtime reports the continuation committed.
Failure or cancellation before commit releases the lease and fails the coordinator closed without
rerunning the tool. A terminal completion discovered by a racing caller is leased first even if its
notification has not yet reached the coordinator mailbox.

To keep this migration boundary cohesive, the coordinator delegates one active request's task,
correlation, buffering, and cancellation to `Coordinator.ActiveRequest`; terminal projection and
lease commit/release decisions belong to `Coordinator.RequestOutcome`; completion command/lease
construction belongs to `CompletionContinuation`. The coordinator retains only serialization,
admission, and scheduling.

Tagged production evidence confirms Gemini accepts this adapter's exact tool schema and a
subsequent canonical running-acknowledgement round with ephemeral pending state and tools withheld.
It also reports usage and verifies public Session cancellation cleanup plus immediate Session reuse.
The deterministic room and rendered sample checks separately prove the selected Call Engine path.

The implemented `AgentActivationSupervisor` groups the request supervisor, coordinator,
invocation supervisor, invocation registry, and Agent Runtime Session under a one-for-all
policy. Each child resolves only the registered references it needs, and the graph is ready
only after all components have started successfully.
One abnormal child failure restarts the whole configured set once; another within the
restart window terminates the activation and its children. The activation supervisor is
temporary to its participant owner, so deliberate participant shutdown does not
resurrect the agent. The implemented `ParticipantSupervisor` is that owner: it groups the
participant authority with the optional activation, treats either as significant, and ends
the whole participant subtree when one terminates. The room-level dynamic supervisor owns
these participant supervisors rather than bare authorities, so an exhausted agent retry
budget removes the participant without restarting the room. Routing room turns through the
owned coordinator is implemented through a stable Registry reference instead of a child
PID. Requests therefore reach a replacement coordinator after the allowed restart, while
events from a stale child cannot pass the room's current-capability check.

Submitted actions return a correlated running acknowledgement and continue under the
activation-owned invocation supervisor. Their later results enter a bounded Vxpipe mailbox.
When Agent Runtime is idle, the coordinator supplies the result through a private engine-origin
continuation that is never projected as caller speech. A chat provider may still require this
non-model input to use its ordinary user wire role; provider role is not Vxpipe participant
attribution. Room Authority creates no participant or caller-transcript event for this request.

The released definition uses `call_variables.sections`, invocation values use
`initial_variables`, and per-agent section grants use `variable_permissions`.
The tools are `read_variables(sections)`, `update_variables(section_name, data)`,
and `update_variable(section_name, variable_name, value)`. Sections are read-only
or read+write for an agent; omitted grants give no access. A dedicated
`CallVariables` GenServer per room incarnation owns the values, revisions,
compiled variable schemas, and per-agent grants. It handles tool reads/updates
directly, without routing through `RoomAuthority` or consulting it for each
authorization. Datatype and value-size checks remain, with incremental population
and no required-variable completeness or additional schema-complexity caps now.
The variables process authorizes, type-checks, and serializes updates, adopts
the new in-memory values/revisions, and returns success after local acceptance
and asynchronous archival handoff. Reads use that memory. It does not wait for
PostgreSQL; the earlier database-commit-before-success rule is superseded by R41.
Local acceptance is not durable persistence. `RoomAuthority` is not on this path;
the storage adapter owns SQL and Ecto, not the call engine.

The variables process lives under the room supervisor, outside agent execution
subtrees, and survives transfers and human-only periods. A committed transfer
terminates the source agent's whole execution subtree, including its capabilities
and model/tool workers. Requests already sent to the variables process may still commit after
source shutdown under normal identity, permission, deadline, size, datatype, and
revision checks; there is no current-activation check for variable access.
This never resumes the old agent or its speech. Room shutdown also ends the
variables process, so completion is not guaranteed if that owner itself stops.
The current shared model/tool task supervisor must be addressed when implementing
agent-wide shutdown; this lifecycle is not yet guaranteed by today's runtime.

For a remote MCP booking, the agent receives the tool result and separately calls
our variable-update tool. The remote MCP does not need Vxpipe-specific knowledge,
and no automatic result-mapping layer is required. These are approved design
contracts, not newly implemented runtime features; see the
[call-definition design](../labnotes/20260905-0405-call-definition-design.md#call-variables-are-typed-sectioned-and-permissioned).

Personalization belongs in agent instructions. Agents use their existing
permitted `read_variables` tools to obtain known values and handle missing
information conversationally; no new interpolation, template, or variable-binding
engine is required. Locale, timezone, and business-time interpretation belong to
the integrating application and its agent instructions. Provide date/current-time
tooling through the usual enabled-tool boundary when an agent needs a fresh
observation. This does not introduce call-level locale/timezone fields, a default
hierarchy, or a frozen new tool name/schema. It changes neither authoritative
call timestamps nor the trusted destination-resolution boundary described below.

The selected remote MCP client is [ExMCP](https://hexdocs.pm/ex_mcp/ExMCP.Client.html),
used directly behind `vxpipe_mcp`. This supersedes direct Jido MCP selection; neither
`jido_mcp` nor Jido Connect is required. The separate `vxpipe_agent_runtime` package owns
the model/tool loop, independently of MCP transport. See the
[runtime/tool-binding decision](reqllm-agent-runtime.md).
Target MCP `2025-11-25` Streamable HTTP with JSON and SSE responses.
Initialization uses `initialize` followed by `notifications/initialized`; subsequent
requests carry the negotiated `MCP-Protocol-Version`. Handle optional
`MCP-Session-Id` values only within their resolved integration/credential boundary.
This replaces the earlier 2026 profile, not a compatibility claim for other versions
or legacy HTTP+SSE. [Lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle),
[transport](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports).

Keep `vxpipe_mcp` as a thin internal Mix library/umbrella-child policy wrapper around
ExMCP, not a custom JSON-RPC/HTTP/SSE client or parser. Use ExMCP's public client
discovery/invocation APIs. The wrapper owns configured supervision, scoped client reuse
and Vxpipe-facing policy/result mapping, with no Jido AI/Action, Calls/Repo/gateway/room
or tenant-selection dependency. The engine-side tool bridge owns model exposure.
The domain owner supplies resolved endpoint, private credentials, authorized network
policy and deadlines, retaining agent grants, bindings and call history. Missing
required ExMCP hooks are a compatibility blocker to report, not permission to add
a second client path or replacement protocol support. No public MCP
server is in scope. Dependency selection does not prove security, response limits,
timeouts or conformance: test the effective public ExMCP path before enabling it.

Call Engine keeps configured infrastructure distinct from a discovered integration
snapshot. `RemoteMCP.ConfiguredIntegration` validates one application- or tenant-scoped
credential generation, allowed-operation set, private client settings, and bounded
discovery/invocation policy; its inspection omits the private settings. The separate
`RemoteMCP.CatalogLoader` opens the exact scoped reusable `vxpipe_mcp` connection and
publishes an integration snapshot only after complete bounded `tools/list` discovery and
allowed-operation validation. It does not compile a call or expose model tools. Definition
compilation then resolves from those snapshots and copies only the selected public schema
and generation identity into the immutable plan. Catalog TTL/refresh orchestration and the
configuration source remain outside the loader rather than becoming another concern of an
agent activation.

`RemoteMCP.CatalogStore` owns only the current immutable application/tenant catalog
snapshot. A configuration owner loads and validates every replacement before one atomic
publication; network discovery never runs in the store's GenServer callback and cannot
delay readers. New definition compilation sees the published replacement. An activation
already started from an earlier snapshot retains its own exact runtime binding, schema and
connection until that activation ends or its credential generation is revoked. Publication
does not mutate a running activation or silently switch its remote operation. The initial
store does not schedule TTL refreshes or decide how application/tenant configuration is
retrieved.

The public Call Engine compilation facade acquires that current snapshot and injects it only
for the duration of pure definition compilation. `vxpipe_calls` centralizes definition-save
and call-preparation compilation through its small `CallPlanCompiler` boundary: it supplies
ordinary provider/tool registries and, when embedding requires it, an opaque catalog-store
server reference. It never receives an integration snapshot, endpoint, header or credential.
Only the resulting safe immutable call plan crosses back into Calls and later Gateway paths.
An unavailable store fails definition resolution instead of accepting a definition against a
stale caller-supplied MCP registry. Live room startup must obtain exact private bindings again
inside Call Engine; it must not route a private catalog through a prepared-call or gateway
record.

`RemoteMCP.CatalogRefresh` is the one-shot refresh operation used by a future configuration
owner. It accepts only validated configured integrations, rejects duplicate scope/integration
identities before discovery, and loads them with explicitly bounded concurrency. It constructs
and atomically publishes one complete application/tenant snapshot only when every load succeeds;
otherwise the last published snapshot remains unchanged. The operation does not fetch source
configuration, schedule itself, own TTL expiry, or perform protocol work outside
`CatalogLoader`. Configuration removal/revocation and stale-snapshot expiry therefore remain
required before this becomes an automatic production refresh loop.

`RemoteMCP.ConfigurationSource` is the narrow boundary that supplies one complete validated set
of configured integrations to that future refresh owner. The first adapter,
`RemoteMCP.ApplicationConfiguration`, reads raw keyword records from the
`:vxpipe_call_engine, :remote_mcp_integrations` OTP application setting and converts them at
runtime into redacted `ConfiguredIntegration` values. Runtime conversion is intentional: Mix
configuration must not need project modules to be compiled before it can declare infrastructure.
A missing setting means no configured integrations, while one invalid record rejects the entire
source rather than silently publishing a partial authorization catalog. Private connection
settings remain inside the redacted engine-owned values. A later tenant/vault-backed adapter can
implement the same whole-source contract without changing discovery or publication. Periodic
scheduling and stale-catalog expiry remain separate responsibilities.

Remote client authentication is a closed configuration value: omit it or use `:none`, use
`[type: :bearer, token: ...]`, or use
`[type: :custom_headers, headers: [{name, value}, ...]]`. Raw transport `:headers` are rejected.
Custom header names and values are bounded and validated before client startup, names are
normalized case-insensitively, and duplicates are rejected. Authentication may own an
`authorization` header, but cannot override transport-owned fields such as `host`, `accept`,
`content-type`, `content-length`, `mcp-protocol-version`, or `mcp-session-id`. The OTP source
validates the complete production HTTPS/client profile before accepting any integration record;
one malformed endpoint or authentication value rejects the complete source without opening a
network connection. Secret values remain only in the inspection-redacted private configuration.

`RemoteMCP.CatalogRefresher` owns those timing responsibilities when remote MCP is enabled in
`Vxpipe.CallEngine.Application` settings. It starts configuration retrieval plus discovery
immediately and repeats it after the configured refresh interval. Each cycle runs under the
explicitly named `CatalogRefreshTaskSupervisor`, outside both the refresher and catalog-store
callbacks, and has a separate wall-clock timeout. A transient source/discovery failure retains the
last good snapshot. If no complete refresh succeeds within `stale_after_ms`, the refresher
atomically publishes an empty catalog so new definition compilation fails closed; a later complete
success restores service. A successful empty configuration is an intentional removal and is
published immediately rather than waiting for staleness. The stale interval must be longer than
the refresh interval. Timing state retains only normalized outcomes, while fetched private
configuration exists only within the supervised refresh task. Catalog replacement or removal does
not mutate a binding already pinned into an active agent; explicit credential-generation
revocation remains the mechanism for ending active authorization.

Reusable protocol connections are keyed by application/tenant scope, integration ID,
and credential generation. An agent activation acquires a monitored, non-secret lease
for every exact generation used by its resolved bindings; the lease grants access to the
connection handle without copying endpoint headers or credentials into the call plan or
lease registry. Ending the activation releases those leases while leaving a connection
available to other authorized activations. Explicitly revoking a generation first
tombstones it, then retires its cached connection and notifies every current lease holder;
new leases and connection opens for that exact generation fail closed. The activation's
one-for-all supervision then ends the stale binding rather than falling back to another
tenant or application credential. Runtime tombstones complement the configured credential
source: after an application restart, that source must be rehydrated without revoked
generations rather than treating in-memory lease state as durable credential storage.

Stream/session recovery must never silently resubmit `tools/call` or bypass invocation
deadlines. The same invocation retains one absolute deadline and cumulative decoded/
decompressed response budget across stream resumption, progress and reconnects;
neither resets for a new HTTP response. Verify initialization with and without a
server-issued session ID. The pinned `vxpipe_mcp` adapter owns those wire semantics;
Call Engine reaches it through the same scoped connection and protocol boundaries for
catalog discovery and activation-local invocation.

All remotely supplied integration, tenant, endpoint, generation, operation, alias, and schema
identities remain binaries throughout configuration, discovery, plan resolution, exact activation
checkout, argument validation, and invocation. None selects a BEAM module. Repeated infrastructure
churn must therefore remain data churn: it may replace catalog values and supervised clients but
must not create atoms or modules. Private endpoint selectors remain behind the integration boundary
and are absent from resolved plans and inspectable activation state.

A controlled loopback acceptance fixture exercises the engine's `CatalogLoader` and
`IntegrationOwner` through the real `vxpipe_mcp`/ExMCP client. It verifies authenticated discovery,
exact pinned invocation, schema rejection before submission, one-shot timeout/oversize ambiguity,
redirect refusal without credential forwarding, and mixed DNS-answer rejection at the effective
network client. Plaintext transport is available only through the explicit test connection provider;
production integration configuration still requires HTTPS and cannot select that escape hatch.

Direct ExMCP intentionally does not expose model tools. Before live-MCP integration ships,
the intermediate `vxpipe_agent_runtime` milestone must provide the shared runtime-tool
projection/executor interface: exact local string names, permitted descriptions, pinned
schemas and separate private bindings without externally driven atom/module creation.
Platform and remote tools share that one runtime loop. Call Engine resolves and executes
the bindings; the model never receives endpoint, credential, remote-operation or tenant
selectors. Do not add another loop inside Call Engine or MCP, or use a generic model-visible
endpoint/tool selector. The standalone ExMCP conformance milestone remains independent.

The [official specification](https://modelcontextprotocol.io/specification/2025-11-25)
is authoritative. Validate the client using pinned compatible versions of the
[official conformance suite](https://github.com/modelcontextprotocol/conformance)
and its [client integration harness](https://github.com/modelcontextprotocol/conformance/blob/main/SDK_INTEGRATION.md),
which starts scenario servers and passes their URL to the test client. Record
applicable passes, failures and unsupported/skipped cases, not blanket certification.
The [Everything reference server](https://github.com/modelcontextprotocol/servers/tree/main/src/everything)
adds client interoperability examples, not complete conformance proof; verify its
actual revision and remote transport match. Any loopback-HTTP allowance belongs
only to an isolated test runner, never production endpoint policy. See the
[client-library milestone](milestones/mcp-client-library.md).

MCP routing uses only trusted application/tenant integration endpoints, never a
model-supplied URL. Require verified HTTPS; a configured private CA is acceptable,
but insecure TLS or an implicit loopback-HTTP exception is not. Default outbound
address checks reject non-public targets, including link-local/cloud metadata,
CGNAT, multicast, and unspecified addresses, and recheck the actual address at
connection time against DNS rebinding. A private destination requires explicit
host-application network authorization that a tenant cannot bypass; this is a
controlled exception, not disabling address protections globally. No automatic
redirects initially: configure the intended endpoint and never forward credentials
across redirects. Vxpipe adopts the SDK's published safeguards at its own outbound
boundary; the cited defaults concern OAuth discovery helpers, not all MCP traffic.
No Go dependency, artifact fetcher, per-call credentials, or inbound/CORS change.
[SDK security guidance](https://go.sdk.modelcontextprotocol.io/protocol/#server-side-request-forgery).

Validate actual outgoing tool arguments against the selected/discovered pinned
`inputSchema` before remote submission using a proper JSON Schema validator,
baseline 2020-12. Enforce required/type/enum/nested constraints, unlike incremental
Call Variables. Unsupported dialect/features or model representation reject the
enabled binding before exposure; no weakened constraints, unvalidated calls, or
automatic external `$ref` fetching. No JSON Schema validator library, extra caps,
or complete output schema design is selected. [MCP schema rules](https://modelcontextprotocol.io/specification/2025-11-25/basic#json-schema-usage).

Store received MCP responses, including structured content and attachment/resource
descriptors, preserving reported success/error and unknown outcomes. The agent
chooses further steps through its authorized tools; saving a descriptor does not
download or inspect its target. No automatic file fetch/playback or arbitrary
media reader is added. Detailed projection/inspection is
[deferred](issues/mcp-result-and-document-inspection.md).
Server-requested sampling, elicitation, and related interactions are separately
[deferred](issues/mcp-server-requested-interactions.md): do not advertise
unimplemented capabilities or acquire authority from their requests. Under the
selected profile these are server-initiated requests, not the superseded profile's
input-required continuation flow. Report missing capability clearly without
invoking models or participants; resubmission is not an approved retry exception.
These are design contracts, not implemented adapters.

The approved MCP lifecycle also distinguishes speech interruption from tool
cancellation: an already-submitted read or action continues to its result or
existing timeout while the agent remains running. Interrupting speech is not
evidence of intent to cancel the tool. Keep its result tied to the invocation
for subsequent reasoning without reviving cancelled model output or speech,
automatically updating variables, or starting additional unsent old-turn tools.
Transfer and room shutdown still end local agent execution; this does not undo
remote side effects. A submitted MCP request that times out without a definitive
remote result reports outcome `unknown`; a local timeout does not establish
remote failure or rollback. Preserve any already-known definitive result.
The initial tool/MCP executor does not automatically retry any failed invocation,
including known non-submission failures, not just ambiguous timeouts. Return its
known error or unknown outcome to the agent. A later agent-requested tool call is
a separate invocation, not an internal retry or an exactly-once guarantee. Do not
add a trusted read-only/idempotent-write/side-effect classification layer now.
Automatic retries and business-idempotency exceptions are
[deferred for later review](issues/automatic-tool-retries-and-idempotency.md).
Tool retries are separate from call-creation idempotency (not offered initially)
and admission bookkeeping recovery (never repeat a crashed call). Ordinary
database transaction handling is unchanged. Explicit per-invocation cancellation is
[deferred for later review](issues/explicit-tool-call-cancellation.md), not
required for the current slice; its opt-in policy is not approved.
This is planned behavior, not the current model-task cancellation behavior
described in the implemented slices below.

All tools use application-level asynchronous orchestration for every model provider;
native async-tool support does not select a separate workflow. Vxpipe accepts and
starts an independently supervised invocation within the agent's execution
subtree, then returns a correlated running acknowledgement as the model's only
ordinary tool response. Agent Runtime never executes even a fast platform or Call
Variables operation inline. The acknowledgement is not a successful business result.

The agent's local call-definition binding defaults to blocking later caller
conversation and may explicitly select `non_blocking`. A non-blocking invocation
allows unrelated model turns while pending, each retaining the committed running
acknowledgement. A blocking invocation allows its current acknowledgement response
to finish, then Call Engine answers later caller turns with deterministic hold output
without admitting them to the LLM. Admission reopens only after the terminal private
continuation is consumed. See the [tool execution model](tool-execution-model.md).

Committed running results record what the model was told, but Call Engine remains
authoritative for current invocation liveness. Before every provider generation it supplies
Agent Runtime a bounded ephemeral projection of pending and terminal-unconsumed invocation
IDs, tool names, source-turn identities, modes, and safe states. It excludes arguments,
results, bindings, endpoints, credentials, and raw errors and is not repeatedly appended to
conversation history.

Completion becomes a separate invocation-linked update to the latest conversation,
not a second ordinary result for the acknowledged call or a replay of its old
model turn. The agent coordinates subsequent speech with the current conversation.
Adapters must preserve accompanying text and tool calls and encode these updates
for their provider; result data remains untrusted tool output. One application
contract avoids provider-specific lifecycle branches. Agent Runtime and Call Engine
implement this contract; each added provider still requires interoperability checks
because context encoding alone does not guarantee it. Explicit cancellation is deferred
as noted above. Existing interruption,
timeout, transfer/shutdown, and variable-update rules still apply, without a
durable operation worker or post-shutdown recovery requirement.

The first Call Engine migration checkpoint implements the neutral host-tool worker substrate:
`Tool.InvocationSupervisor` owns capacity-bounded temporary children, while each
`Tool.Invocation` owns one execution attempt and deadline. It deliberately ignores the legacy
Action definition's `inline`/`background` distinction. An operation whose old definition says
`inline` therefore still runs outside the submitting process and reports one correlated terminal
outcome. `Tool.InvocationRegistry` now owns bounded capacity from accepted startup through consumed
completion, idempotent submission reconciliation, worker identity, terminal races, payload-free
ordered snapshots, completion lease/release, explicit acknowledgement, and bounded consumed-ID
tombstones. A worker is prepared dormant, monitored, recorded, and only then explicitly begun, so
a fast completion cannot overtake its authoritative running record. Only acknowledgement frees
capacity. Thin Call Engine adapters now implement Agent Runtime's submit and pending-context
contracts: submission can only delegate to this registry, and pending projection maps only safe
status values after verifying the request correlation belongs to the same registry. Host, Call
Variables, and remote MCP handlers plus definition-driven activation wiring select this substrate
in live calls.

For each resolved host-tool map, Call Engine compiles a deterministic name-ordered Agent Runtime
descriptor list. Each descriptor copies only the host definition's exact name, description, and
JSON input schema into the model-visible projection. Its opaque invocation binding privately pins
the host action and the call definition's conversation mode. A map key that differs from the
resolved binding or host definition name is rejected rather than silently changing routing. This
compilation does not create an inline path: both conversation modes submit through the same
invocation registry and supervised worker boundary.

Schema `20260910.03` adds explicitly selected `platform` bindings to that unified tools map.
Their canonical names resolve through a closed Call Engine catalog; definition input supplies
neither a module nor executable routing data. The initial catalog exposes current UTC time and
immediate hangup, while preserving a participant-local model-visible alias and the same pinned
conversation mode. Platform tools use the ordinary activation-owned invocation worker. Hangup
returns a typed effect to the registry rather than calling Room Authority from its worker task;
the registry delivers ordered start/completion facts before Room Authority validates the live
agent/source connection and terminates the room. There is no inline agent-side hangup path.

Permission-derived Call Variables tools compile through the same descriptor boundary. Because
these platform tools are generated rather than explicitly selected in the participant's `tools`
map, the current schema gives each one the default `blocking` conversation mode. Their opaque
binding contains only the scoped room-variables handle and authorization identity. Invocation
workers call that binding by its exact generated name; Agent Runtime never receives the handle or
calls the room-scoped variables process itself.

For a plan containing remote MCP tools, `CallEngine.start_call/2` reads one complete current
integration-catalog snapshot from the configured catalog store and does not accept an injected
catalog as an authority. Plan startup verifies every pinned remote generation against that snapshot
before creating the room. It then passes the snapshot privately through room startup to the agent
activation. The activation conditionally starts one `RemoteMCP.IntegrationOwner` in the same
one-for-all generation as the Session, coordinator, invocation registry, and invocation supervisor.
Each model descriptor carries only its local alias, public description, and pinned schema; its
opaque handler points to that owner. The common invocation worker calls the owner, which resolves
the exact pinned remote operation and scoped connection. A catalog change before activation can
therefore reject the stale plan; an owner that has started retains its checked-out generation until
activation shutdown or explicit credential revocation.

Remote execution does not introduce a separate conversation path. An explicitly non-blocking MCP
binding can remain pending while the acknowledgement is synthesized and delivered through the
agent's ordinary TTS capability; the remote operation still runs only in its supervised invocation
worker. Its terminal event carries the local alias and bounded result into the ordinary private
archive and one engine-origin continuation. That continuation may ask for a separately authorized
Call Variables tool. The variables process—not the MCP client or model runtime—enforces the
participant's section grant and publishes the resulting snapshot. Client tool visibility remains
the call's generic hidden/metadata/full policy and therefore does not depend on whether the private
handler is a host action, Call Variables binding, or remote MCP operation.

Late business confirmations are an external-event concern deferred beyond this
MCP slice. A future gateway webhook or other external event could inform the
relevant room/agent if the room is still active—for example, a booking success
notification arriving after a timeout. No event endpoint, late-result delivery,
polling, reconciliation worker, or operation ledger is required now for that
scenario. Authentication, correlation, inactive-room behavior, and agent handling
of those events belong to the future design; no such runtime support is added here.

Generic platform-level confirmation before MCP tool execution is out of scope
for now. Agent instructions can ask for conversational confirmation, while any
enforceable business authorization belongs to the integrating application/MCP.
Prompt instructions are not a security guarantee. Vxpipe still enforces tool
access, trusted identity, and argument checks; no confirmation token, approval
endpoint, or generic confirmation state machine is introduced.

R47 keeps provider-supported settings in reusable configured services/profiles;
conversation, interruption, and call-duration policy remain engine-owned. Reject
known unsupported options/combinations during definition validation rather than
silently dropping them. Failures discoverable only from the provider use normal
startup/runtime failure handling. No new configuration layer, arbitrary provider
payload, or executable policy is introduced.

R48 checks the total accumulated input before each inference, including fixed
instructions, tool definitions, and current conversation/tool history. Compare
that input with the usable input budget after reserving output capacity. The
defaults compact older completed conversation at 75% of that budget, targeting
below 50%. Preserve instructions, tool definitions, recent/current messages,
unresolved tool interactions, and valid tool-call/result pairing. These are design
targets, not a promise that protected content fits: do not silently remove it or
exceed the model limit when compaction cannot make room.

Compaction consumes only that agent's authorized live conversation, never an
unrestricted room archive. A summary is derived data, not system authority, a tool
result, or permission to execute tools. It does not modify `CallVariables`, grants,
or the full permitted archive. Source-interval restrictions also apply to derived
transcript summaries; denied transcript storage cannot be bypassed by saving a
summary. If work uses a snapshot, preserve intervening messages and unresolved
invocations when incorporating its result. The summarizer model/execution choice
and configuration encoding are not selected; no new model recipient is authorized.
This resolves the budget/conditions policy, not an implemented compaction engine.

R49 requires a configurable hard maximum acceptable MCP response size, default
1 MiB (1,048,576 bytes) of decoded/decompressed response data. Enforce it
incrementally while receiving, including cumulative streaming equivalents, not
per chunk with unlimited total acceptance or after buffering the full body.
On excess, stop receiving/processing and report bounded observed too-large/outcome
details without declaring an external side effect failed or automatically retrying.
A body rejected before full receipt cannot be described as fully archived.

This ingestion cap is separate from the token/model-context projection budget.
Fully accepted permitted responses belong in the asynchronous archive. If one
cannot fit the model budget, return an explicit model-projection-too-large outcome
without replacing the archive with chopped JSON, repeating the remote action,
or adding automatic result summarization/inspection. Archival handoff is not
durable confirmation. Concrete parser/transport and configuration hierarchy are
implementation details; the deferred general result/document-inspection design
is unchanged.

R50 permits explicitly configured LLM provider-native/router fallback only where
the selected agent-runtime/ReqLLM provider surface supports the provider options. It does not add a Vxpipe fallback schema,
direct-provider chain/coordinator, or STT/TTS fallback feature. Keep tool,
permission, privacy, and usage constraints, recording actual observed provider/
model attribution without inventing hidden upstream attempts or IDs. This does
not authorize MCP retries or promise replay of already-emitted speech/tool actions
after a stream failure. Unsupported fallback settings follow R47 validation.
The numbered R01–R50 review is complete; deferred issues and engineering choices
remain separate from runtime implementation.

### First messages and transfer responsibility

Optional call-level `opening_audio` plays to `entry_caller` before
`entry_receiver` begins the normal conversation. Schema `20260910.02` represents its source
as the closed tagged object documented in [the opening-audio contract](opening-audio-contract.md):
fixed text or an HTTPS file URL. For text, render and cache
audio using the initial receiving agent's resolved TTS service and voice,
including configured defaults. Do not generate its text through an LLM, choose
an arbitrary first participant, or start a later transfer agent to supply a voice.
Without an initial agent/usable TTS profile, startup fails before registering a room rather
than silently inventing one.

Room and participant capabilities may start and warm up while opening audio
plays. The gate controls media delivery, not process startup: do not route user
or other participant audio into capabilities or normal conversational media paths
until playback completes. Receiving a packet at the transport is not permission
to forward it to STT, a recorder, or another consumer. Opening-asset rendering
and playback remain allowed, while the receiver's ordinary greeting and
conversation still wait until completion. This approves neither text barge-in
nor capture/retrospective replay of the blocked interval; no buffer/replay
mechanism is introduced. Downloading, rendering, caching, or enqueueing audio is
not completed playback. Omission means normal startup with no announcement
delay; failed/incomplete configured playback cannot silently open the media gate.

Cache reusable generated audio by exact text, resolved TTS provider/model/voice,
and output-affecting settings, scoped to the tenant/configured binding. Changed
text or voice must not reuse stale audio; secrets belong in neither cache keys
nor logs. The configured reusable asset is not a per-call recording/export, and
does not acquire per-call retention. The application owns one bounded in-memory LRU for file and
generated-text assets. File keys hash tenant, exact URL, and a media profile. Text keys hash tenant,
exact text, provider/model/voice, output-affecting settings, and a render profile. A supervised
forwarding sink collects only bounded complete provider PCM on a text miss; a hit uses the ordinary
temporary asset player without a new TTS request. Asset preparation itself starts no call tree
and does not set `started_at`.

The fixed-text runtime starts cache lookup and, on a miss, synthesis when the entry caller's output
sink attaches. HTTPS-file
sources instead start a temporary worker under the room capability supervisor, independent of TTS.
That worker performs the bounded tenant-scoped load and supplies PCM chunks of at most 20
milliseconds through the existing output backpressure boundary. Both forms keep text and STT
ingress closed and release
them only on that sink's actual completion acknowledgement. Provider, asset, worker, or playback
failure stops the room. File retrieval never runs in Room Authority.

This is an initial-call barrier, separate from each agent's greeting and from
transfer behavior. Notices for later joiners are not selected here. Record `started_at` at actual live-call start, not at notice
completion or receiver activation; the notice does not reset the clock. This is
playback ordering, not mandatory disclosure or a promise of consent/compliance.

Each agent participant chooses its first-message behavior: wait for input, speak
fixed greeting text, or generate a greeting. For the initial receiver, the runtime
starts that behavior only after the entry caller has attached and configured opening
playout has actually completed. Wait mode emits nothing. Fixed mode records the exact
configured text as assistant history and sends it through normal authorized text/TTS
output. Generated mode submits a private engine-origin model request, then routes its
answer through that same output path. Startup is marked once before asynchronous output
can complete, preventing duplicate attachment or completion signals from replaying it.

Apply the same choice on an agent's first activation in a call. Reconnect and later
reactivation of the same participant do not replay its startup greeting; transfer/re-entry
integration remains pending. A new call has its own first activation. Greetings use normal
authorized output and do not bypass current privacy permissions. The approved
startup/idle/duration boundaries follow below.

Required provider/connection startup readiness has a configurable 30-second
deadline, starting with the actual post-join admission/startup attempt, not
prepared-record creation or token issuance. A definitive terminal failure fails
early; expiry aborts startup, releases resources, and reports a clear failure.
Deliberate `opening_audio` playback is not itself a readiness failure or subject
to a new 30-second truncation rule. Preserve its media-input gate and actual
`started_at` semantics; a failed pre-live startup never fabricates a start time.

The planned-room runtime starts one significant `CallLifecycle` process before Room Authority
inside the room-incarnation supervisor. That process owns the readiness and whole-call timer
handles; Room Authority owns neither clock and mirrors only whether startup input is ready. A
deadline that fires before authority binding is retained and delivered after binding rather than
lost. Because the lifecycle child is temporary and significant, its failure shuts down the room
incarnation instead of restarting it with fresh deadlines. Legacy ad-hoc rooms do not receive
this definition-driven lifecycle child.

For the current web caller, attachment marks readiness when the plan selects no STT runtime. If
STT is selected, its capability and ingress must start and bind before readiness is marked. The
readiness timer is then cancelled once, and the initial receiver's greeting remains gated behind
both readiness and completed opening playout. Readiness expiry and maximum duration notify
attached connections with safe reasons and terminate the room. Early shutdown on a definitive
selected-STT startup/binding failure follows the same lifecycle path: it cancels readiness and
ends the attempted planned room immediately while returning a bounded attachment error. Legacy
ad-hoc rooms preserve their detach-only behavior. Deeper provider-specific ready handshakes remain
to be implemented where a transport's successful start does not already establish readiness.

Planned startup accepts either a human or an agent as `entry_receiver`. A human receiver is
admitted through the same participant and media-policy commit barrier as the human caller but gets
no activation ID, agent subtree, text capability, greeting, or TTS capability. Speech-to-text
runtimes are selected by participant identity for both human entries rather than being a
caller-only singleton. Both humans may attach without a fabricated agent; text input still fails
with `agent_not_ready`. The room mixer then routes policy-permitted PCM between the two identities,
and the ordinary readiness and maximum-duration lifecycle continues to own room termination.
Legacy ad-hoc rooms still require their configured agent path before attachment.

When an agent genuinely waits for caller input, a configurable 15-second idle
notification lets its instructions decide whether to nudge, wait, or use a
permitted end-call tool. No automatic silence hangup or repeated-announcement
cadence is added. Opening playback, agent output, holding, dialing, and tool-wait
are not caller silence. Use actual conversation/media evidence without new local
VAD/models; human-only calls must not depend on a nonexistent agent.

The current planned-room lifecycle implements this as an explicit arm/suspend/activity state
machine rather than elapsed wall time inferred by Room Authority. It arms only after readiness,
an attached entry caller, an open opening-audio gate, completed first-message admission, no active
caller speech or agent turn, and no pending tool invocation. Text acceptance and STT speech-start
signals are real caller activity and cancel/reset the interval. Opening/output/tool work merely
suspends the clock; it does not fabricate caller activity.

Idle expiry carries a one-use timer token. Room Authority claims it before asking the active agent
runtime to process a private engine-origin notification, so a cancelled/stale timer cannot become
a caller-visible message or a competing model request. The notification explains only that no new
caller input arrived and asks the agent to follow its instructions; it invents neither a caller
utterance nor a disconnection. Once delivered, the lifecycle does not arm another idle interval
until actual caller activity occurs. The agent can remain silent, speak through its ordinary
output path, or invoke a tool it already has permission to use. Later dialing/transfer work must
explicitly suspend the same lifecycle state before waiting on a destination.

Long tools do not cause automatic periodic progress speech. Agent instructions
control kickoff/results through the same agent and one coordinated voice while
the approved background-tool conversation can continue. Possible music during
startup or tool waiting is [deferred](issues/wait-music.md); no playback option is
introduced.

The whole live call defaults to a 30-minute limit (`1800000` ms). Resolve
`limits.max_duration_ms` from an explicit call-definition value, otherwise tenant
settings, otherwise application settings, otherwise that platform default. Pin
the effective limit in the resolved call plan; unlike retention, later settings
changes do not change an active call's limit. Measure from actual `started_at`,
excluding prepared wait and never resetting on transfer/recovery. It also applies
to human-only portions. At the limit, the engine ends with a clear duration-limit
reason. No creation-time override, unlimited mode, warning/grace policy, or closing-
speech guarantee is added. The current runtime starts its maximum-duration timer with the live
planned-room subtree, uses only the value already pinned in `ResolvedCallPlan`, and never accepts
a per-start duration override. The definition parser preserves omission rather than inserting a
default. Before a prepared call is stored, `vxpipe_calls` resolves the tenant and application
settings and supplies them to the pure Call Engine compiler; that compiler applies the complete
precedence and pins the result.

The current OTP setting is `:call_duration` under `:vxpipe_calls, Vxpipe.Calls`. Its
`max_duration_ms` is the application value and its `tenants` map may hold a
`[max_duration_ms: value]` override keyed by public tenant key. Values at every configured or
authored scope use the same closed range of 1,000 through 86,400,000 milliseconds. Malformed
trusted settings fail compilation rather than silently selecting another value. Changing this
setting after call preparation does not mutate the stored plan or its live lifecycle timer.

Closing wording and the decision to invoke the existing hangup tool belong to
agent instructions (R31). No platform speak-then-end/closing-message API,
mandatory playback-drain deadline, or pending-hangup cancellation on speech
interruption is introduced. Normal/immediate hangup and the hard duration limit
remain unchanged. Instructions alone do not guarantee that audio finished playing;
this does not add playout-aware hangup.

Use provider-supplied answering-machine/voicemail detection when supported and
configured for use; detection is not mandatory on every call.
Preserve its provenance and unknown outcomes, not a local beep classifier or
LLM-inferred proof of a human. Both [Telnyx](https://developers.telnyx.com/docs/voice/programmable-voice/answering-machine-detection)
and [Twilio](https://www.twilio.com/docs/voice/answering-machine-detection) document
provider detection. When that detection reports a machine, disconnect the
attempted outbound destination leg. For a transfer, return its typed failure to
the source and preserve the original caller/source conversation under normal
permissions; do not end the entire room. For an initial outbound call whose only
remote human is that destination, terminate the attempted leg/call rather than
inventing voicemail speech.

Unknown, disabled, or unavailable detection is neither machine nor human proof.
An unknown transfer keeps waiting for explicit recipient acceptance within the
existing total 30-second attempt deadline, without extending it. Classification
is not an accuracy guarantee or a substitute for acceptance. No local classifier,
beep inference, provider tuning, or automatic message delivery is added. Leaving
voicemail is [deferred for later review](issues/voicemail-message-delivery.md),
without reintroducing a platform closing-speech workflow.

Until a transfer successfully commits, the source agent retains conversational
responsibility. `RoomAuthority` still owns the room and the transfer transition;
the agent does not take over room supervision. Prepare the destination and verify
readiness before committing the handoff. A failed attempt, such as busy or no
answer, returns a typed tool error to the source agent, which can explain the
failure and choose its next permitted action. Do not terminate it just because
transfer was requested. A successful handoff terminates its execution subtree,
including capabilities and model/tool workers, under the existing lifecycle.
Failure handling respects current permissions; it is not permission to resume
forbidden processing. After a failed transfer, allow exactly one bounded attempt
to restore the source's permitted capabilities. Supervisor/application retries
must not reset this one-attempt budget. If it fails and no usable conversation
remains, terminate the call; an already working, permitted human conversation can
continue. Preserve the detailed failure reason internally, not in agent speech,
client events, or tool-debug UI. Agent/public outcomes may be generic failures or
ends without provider/cause details, even when samples select full tool visibility.
Existing privacy constraints and whole-call duration still apply.
This restores capabilities within a still-live call, not a crashed call runtime.

The initial transfer scope includes a private destination briefing: caller and
intake agent converse, then an outbound human support recipient privately hears
who is calling and the purpose, plus an optional recording notice, before press-1
acceptance and bridging. The caller must not hear that briefing. The web equivalent
uses client-owned interaction and authenticated acceptance. Share only permitted,
minimum-necessary variables/history, not an implicit full transcript. Use the
agent voice for source TTS when applicable and permitted, without choosing a new
voice/configuration format. Source responsibility continues until commit, and
acceptance alone does not expose full room media. This approves the bounded
briefing flow, not general simultaneous-agent consultation or a compliance claim;
its routing and commit policy follow R38 below.

Shared transfer defaults live in call-level `transfer_policy`; source participants
keep `transfers: [allowed participant refs]`, and destination-specific connection/
acceptance requirements stay with the destination. No named transfers, graph,
source-level default machinery, or per-pair overrides initially. Other policy
fields/enums are not frozen by naming this configuration boundary.

An agent destination must be ready for conversation with its required capabilities.
A human destination needs usable media and explicit acceptance: deterministic
press-1 DTMF from its pending phone leg, or an authenticated transfer-accepted
message from its web connection. The web client owns presentation/user interaction;
the platform does not prescribe an acceptance button. The gateway/adapter binds
acceptance to the destination participant/connection and current pending transfer
attempt, rejecting source/caller/model assertions, stale messages, and duplicate
commit attempts. This is an internal/adapter control contract, not an RTVI core
field. Transport connection alone admits no full conversational media or private
disclosure; source responsibility and target-presence capability rules hold until
the room commits the transfer.

`transfer_policy` has a configurable 30-second total attempt deadline, starting
when the preparation request is accepted and covering preparation, dialing, and
acceptance together, not restarting per phase. Busy/no-answer or another definite
failure ends it earlier. On failure/timeout, stop the destination attempt, return
a typed outcome, and let the source continue when permitted. Late answer/acceptance
cannot commit an expired attempt; clean up its exact mapped leg without automatic
redial. This is separate from startup readiness and whole-call duration and adds
no remote-outcome certainty or durable recovery framework.

Schema `20260910.04` implements the authoring and compilation half of this boundary for
agent-to-agent destinations. Each non-empty, unique `transfers` list must resolve to other agent
participants in the same definition. Compilation adds one private participant-transfer binding
under the reserved `transfer` name, captures the source participant/activation and destination
participant identities outside the model projection, and exposes only destination refs plus their
safe descriptions in a closed input schema. The generated binding uses the ordinary tool-visibility
policy and defaults to blocking later caller conversation. It still executes through the same
activation-owned supervised worker path; blocking does not mean inline execution.

Schema `20260910.05` adds the closed call-level `transfer_policy.attempt_timeout_ms`, with a
30-second default and a bounded 1–120-second range, and pins it into the resolved plan. The
activation-owned outer invocation timeout encloses the selected attempt budget rather than imposing
the ordinary 30-second tool limit on a longer configured transfer. One room-owned preparation task
materializes the destination participant/runtime and selected TTS; `RoomAuthority` owns the single
pending attempt, its caller reply, monotonic deadline, final reauthorization, and commit. This keeps
the room control loop available while provider or child startup is pending. Failure or expiry
terminates the task and exact destination resources while leaving source responsibility unchanged.
Clearing the pending attempt before replying makes late task results non-authoritative.

Schema `20260910.06` puts the inbound history policy on the destination agent as
`transfer_history`, leaving each source's `transfers` value as the approved simple participant-ref
list. Omission resolves to the privacy-safe `fresh` mode. The closed alternatives are
`all_spoken`, `last_n_spoken` with a required positive `turns` value, and `selected`; no other mode
or mode-specific field is silently accepted. This placement prevents a source model from choosing
how much prior conversation another participant may receive. The compiler pins the policy into the
destination participant in the immutable call plan.

Schema `20260911.02` opens the previously agent-only destination allowlist to a web human whose
connection intent is exactly `receive`/`transfer`. Entry admissions and transfer admissions remain
distinct: a human with `start_call` admission cannot be selected by the transfer tool. The human
destination may carry one optional fixed `transfer_notice`. A transfer to a human always requires
a non-empty bounded `reason`, which is the private caller/purpose briefing supplied to that
destination; it is not a free-form address, public client event, or full variable/history snapshot.
The resolved plan pins the connection intent and notice. This checkpoint defines the authoring and
compilation boundary.

Schema `20260911.03` generalizes the human connection intent for configured telephony services
without turning provider names into atoms or admitting credentials/provider commands into the call
definition. A receive intent carries a literal E.164 number and an explicit admission. A dial intent
uses exactly one literal E.164 number or one direct `number_from_variable` section/variable
reference and normalizes to transfer admission. The referenced variable must be declared with a
string-compatible schema, and every agent is forbidden write access to its routing section. The
compiler accepts that participant only through an existing source `transfers` allowlist; the model
still receives a participant ref rather than a telephone number or provider selector. This schema
checkpoint defines pinned intent, not a live provider leg. Calls metadata preserves the same safe
intent and creates browser join routes only for web participants.

The provider-neutral telephony runtime contract lives in Call Engine so embedded hosts, Gateway,
Calls, and later carrier adapters share one dependency direction. Carrier modules implement dial,
answer, outbound-media, exact-leg end, authenticated-webhook decode, and media-message decode
callbacks. Dial/answer/end submissions report either `accepted` or `unknown`; an unknown immediate
outcome is deliberately not a retry instruction. Raw webhook bytes and normalized headers remain
intact until the adapter verifies them, and the common wrapper will not decode an unverified body.
Adapters emit only the closed normalized lifecycle vocabulary: incoming, answered, media started,
media packet, DTMF, answering-machine result, and ended. Sparse or malformed adapter results fail at
this boundary before room control sees them. An authenticated provider event outside that consumed
vocabulary returns an explicit `ignore` outcome so the gateway can acknowledge it without treating it
as an actionable event or asking the carrier to retry it. Provider media remains a packet with its
authenticated codec/clock/sequence metadata until a Membrane gateway pipeline converts it into the
existing room PCM clock; raw carrier packets do not enter Room Authority.

Common provider identity preserves the identifiers a carrier actually supplies. Configured provider
connection, addressable call-control, and exact call-leg identifiers are mandatory. A separate
provider call-session identifier is optional: Telnyx supplies and pins it, while Twilio has no
distinct equivalent and retains `nil` instead of duplicating its Call SID into a fictitious session.
Matching includes the optional value, so adapters cannot discard a real session identifier merely
because another carrier lacks one.

Configured telephony services share service ID, ingress key, application/tenant scope, optional
outbound number, public TLS base, media-token lifetime, and closed machine-detection policy. A
provider profile owns the rest. Telnyx retains its Voice API connection ID, Ed25519 public key and
API key; Twilio retains its Account SID and Auth Token. The Twilio Account SID becomes the safe
configured-provider identity, while the Auth Token remains private in adapter and verifier options.
Mixed provider credentials fail configuration instead of being ignored, and service inspection
projects identity only.

The Twilio adapter authenticates form-encoded webhooks according to Twilio's current official
[request-validation contract](https://www.twilio.com/docs/usage/security): HMAC-SHA1 covers the
configured exact public URL followed by form fields in case-sensitive key order, and the expected
base64 value is compared to `X-Twilio-Signature` in constant time. Form parsing rejects duplicate,
oversized, or malformed fields. Only after verification does the adapter normalize an incoming
[Voice webhook](https://www.twilio.com/docs/voice/twiml) into the common event. Account SID is
rechecked against the configured service; Call SID becomes the addressable control/leg identity;
the stable incoming event key derives from that Call SID. Gateway receipt time is used where the
initial TwiML request supplies no provider event timestamp.

Gateway exposes the synchronous Voice ingress at
`POST /api/telephony/twilio/:ingress_key/voice`. The route preserves the untouched form body for
signature verification and resolves the configured public URL rather than trusting proxy/request
headers. After authenticated normalization, the common ingress workflow claims the prepared call,
starts its pinned room, and activates the incoming leg. Activation returns a typed result containing
the common media binding and its one-time provider media URL. The HTTP boundary then answers with
Twilio [`<Connect><Stream>`](https://www.twilio.com/docs/voice/twiml/stream) TwiML pointing to that
WSS URL; there is no fictitious second answer API command. Telnyx consumes the same typed activation
result but continues to acknowledge its asynchronous event with an ordinary success response.

The corresponding `GET /api/telephony/twilio/:ingress_key/media/:token` WebSocket boundary checks
the upgrade shape, resolves the configured Twilio service, and validates `X-Twilio-Signature`
against the exact configured WSS URL before consuming the one-time media token. A rejected signature
therefore cannot burn a legitimate admission token. The resulting socket pins the configured
Account SID, exact Call SID, one Stream SID, and live leg owner. It accepts only Twilio's declared
mono 8 kHz `audio/x-mulaw` start format, bounds and decodes PCMU media, timestamps DTMF at gateway
observation, and dispatches normalized events through the provider-neutral leg boundary. Cross-call
or cross-stream frames close the socket rather than entering the room.

The Twilio media-session selection reuses the same direct-output, room-ingress, and room-egress
contracts as Telnyx. Provider-owned Membrane pipelines decode PCMU to mono signed 16-bit PCM,
linearly interpolate the fixed 8-to-48 kHz ingress ratio, and frame it on the room's 20 ms clock.
The reverse path applies a bounded six-sample averaging filter, converts 48-to-8 kHz, encodes PCMU,
and uses `Membrane.Realtimer` before producing the exact Twilio media envelope with its pinned
Stream SID. No FFmpeg runtime or external codec process participates. Codec/rate math remains in
small deterministic modules beneath the Membrane elements rather than in the socket or room
authority. When interruption or a policy revision replaces an output pipeline, the shared output
lifecycle first terminates the old local producer, then invokes its configured playback clearer,
and only then launches the replacement. Twilio's clearer emits the exact `clear` command for the
pinned Stream SID, so already-buffered provider audio cannot continue after barge-in or a privacy
barrier. Transports without a remote playback-clear operation use the explicit no-op implementation
of that contract. Complete transfer parity and live-provider verification remain pending
checkpoints.

Outbound Twilio control uses the current official
[Calls resource](https://www.twilio.com/docs/voice/api/call-resource). Gateway posts one
form-encoded create request with HTTP Basic authentication, the configured E.164 `From`, the
already-authorized destination, inline `<Connect><Stream>` TwiML, and the exact signed callback URL
for the opaque internal leg. The requested progress callbacks are `initiated`, `ringing`,
`answered`, and `completed`. A configured detection mode additionally enables asynchronous
[answering-machine detection](https://www.twilio.com/docs/voice/answering-machine-detection) and
points its result at that same callback boundary. Gateway never retries this create request: a
network or 5xx outcome remains unknown, while a 4xx response is a bounded provider rejection. To
end a known attempt, it updates only that exact Account SID/Call SID resource to `completed`.

Gateway receives those callbacks at
`POST /api/telephony/twilio/:ingress_key/events/:leg_id`. The configured URL, including the exact
opaque leg path, participates in signature verification before the body is decoded. Account SID,
Call SID, direction, bounded sequence, configured origin, authorized destination, and internal leg
ID are retained for correlation. Status values normalize to outgoing, answered, or ended events;
async AMD normalizes to human, machine, or unknown. Authenticated statuses outside that consumed
vocabulary are acknowledged without dispatch. Because Twilio says callbacks may arrive out of
order, any fully correlated progress callback—not only the initial one—may bind a pending leg after
an unknown create outcome. It can only locate the already-running owner by its opaque leg ID, must
pass the owner's complete identity checks, and cannot submit another dial. Once bound, later
callbacks route by the exact Call SID.

The Telnyx gateway boundary authenticates the untouched request body before any event decoding.
It verifies the base64 Ed25519 signature over `timestamp <> "|" <> raw_body` with the configured
base64 public key and rejects signed timestamps more than five minutes before or after gateway
receipt. Invalid verifier configuration is kept distinct from an unauthenticated request internally,
while malformed headers, stale/future timestamps, signature decoding failures, and body tampering
share one bounded authentication failure. Event decoding and admission cannot run until this check
succeeds.

After authentication, the Telnyx webhook decoder accepts the Voice API v2 `data` envelope and emits
bounded common events. It retains the provider event ID, Voice API `connection_id`, call-control ID,
leg ID, session ID, and parsed occurrence time for service/leg correlation and delayed-event
handling. Incoming initiation additionally retains the caller and called addresses. Answered, DTMF,
standard/premium machine detection, and hangup events map to the closed common vocabulary;
documented premium human variants become `human`, premium machine/silence/fax outcomes become
`machine`, and `not_sure` becomes `unknown`. Known timeout/busy/no-answer hangups retain that
meaning, while unrecognized provider hangup causes become generic failure. An outgoing initiation
is consumed only when its signed payload includes the bounded opaque Vxpipe leg ID previously
encoded into provider `client_state`; this provides the correlation seam for an accepted or unknown
dial submission without selecting by phone number. The remaining authenticated but unconsumed
Voice API events are acknowledged through `ignore`.

Gateway exposes this boundary at
`POST /api/telephony/telnyx/:ingress_key/events`. The deployment configuration resolves the opaque
ingress key to one enabled application- or tenant-scoped service, its expected Voice API connection
ID, and its webhook verifier. The same configured service pins the provider command adapter and
secret options, an optional E.164 outbound origination number, a provider-reachable HTTPS public
base URL, the short media-token lifetime, and a closed answering-machine setting that defaults to
`disabled` and may be set to `detect`. The resolved room request chooses the configured service and
destination but cannot override that provider-profile setting. Outbound lookup first selects an exact
tenant-scoped service ID and otherwise falls back to the application-scoped service with that ID; it
never uses another tenant's configuration. The origination number is deployment configuration rather
than a call-definition value or a model-selected destination.
Plain HTTP, missing-host, userinfo-bearing, query-bearing, fragment-bearing, and missing-secret
configurations fail during startup. Credentials and verifier material remain inside that
configured service and are never passed to the ingress handler or included in its derived
inspection; the handler receives only a safe service identity and a common event. The route is
backend-only for CORS, limits the untouched request body to 128 KiB, authenticates before JSON
decoding, and rejects an otherwise valid event whose
`connection_id` does not match the selected service. Authenticated events outside the consumed
vocabulary are acknowledged without dispatch. This is only the provider ingress seam: durable
admission, event deduplication, and exact call/participant/leg correlation are owned by Calls and
are not implied by authentication or decoding alone.

Incoming leg activation derives one internal telephony-leg ID, constructs the exact media binding,
issues its short-lived token, and submits one provider-neutral answer command through the pinned
service adapter. The public HTTPS base becomes WSS while preserving its deployment path prefix.
If command submission is rejected or the binding does not match the configured provider/service/
tenant/connection, activation revokes the unconsumed media admission. An unknown carrier submission
outcome remains a submitted outcome and is resolved only by later exact-leg events; it is not retried.

Saving a definition now derives a separate durable inbound telephony route for each human
`receive`/`start_call` connection whose service is not `web`. The route binds the immutable
definition revision and participant ref to the configured service ref plus literal E.164 number;
it stores no carrier credentials. Publication activates these routes in the same transaction that
switches the definition's web routes, and publishing a later revision deactivates the earlier
revision's routes. A tenant-scoped service lookup is constrained to that tenant. An
application-scoped lookup may cross tenants only when service and number identify exactly one
published route; zero or multiple matches fail closed. This gives authenticated ingress a durable
definition-selection boundary without using caller identity or a provider leg ID as the route.

Calls claims each normalized incoming event against that published route before a room can start.
The claim reconstructs and compiles the immutable definition revision with telephony transport,
generates call/room/participant identities, verifies that the route names the entry caller, and
persists the call in `admitting` state together with the initial provider leg in one transaction.
`started_at` remains empty: provider ingress and durable admission do not claim that a live room
has started. The provider/service/event identity and provider/service/leg identity are independently
unique. An exact webhook retry returns the existing pinned claim without creating another call;
reusing an event identifier for a different leg fails closed. The persisted leg retains only safe
correlation identifiers and never carrier credentials or raw webhook contents. Live ownership and
room-incarnation correlation are established by the subsequent startup boundary rather than by a
database lookup for every provider event.

The ordinary planned-room startup accepts `telephony` as a transport only after compilation has
resolved the entry caller to a configured non-web `receive`/`start_call` connection intent. It then
creates the same supervised room, participant, lifecycle, mixer, policy, transcript, variables, and
agent activation tree used for web calls. This is not a provider adapter inside Room Authority:
carrier media and control still attach at the gateway boundary using the room incarnation returned
by startup.

Once startup returns, the same live leg owner activates the carrier through the configured service
before it accepts later callbacks. An accepted or unknown answer submission leaves the owner in an
`answering` state; command submission alone is not evidence that the call started. The first exact
provider `answered` event projects its provider occurrence time as `started_at`. If the admitted
media socket starts first, that exact media observation is also proof that the call is live and the
gateway's observation time is used. Calls then projects the claim and returned incarnation in one
transaction: the call becomes `running` and the initial leg becomes `active` with the same
incarnation. A pre-live room or carrier-activation failure instead makes the call `failed` and the
leg `ended`, leaving `started_at` empty. Projection rechecks every stored provider correlation and
call, tenant, and participant identity from the claim under a database lock. Repeating the same
terminal transition is idempotent; a different incarnation or mismatched claim is unavailable
rather than silently reassigned.

Gateway's default telephony ingress handler starts one temporary OTP leg owner keyed by configured
service plus provider and provider leg ID. The HTTP boundary supplies that default owner with the
same immutable configured-service registry and media-admission process used to authenticate the
webhook and admit its media socket; custom ingress/backends remain untouched. The owner performs
the durable claim itself, then serializes room startup, carrier answer submission, exact live
evidence, and lifecycle projection before it accepts ordinary later callbacks. Registering before
the claim closes the retry window between transaction commit and live ownership: concurrent copies
await the same result and cannot start another room or submit another answer. A persisted
`admitting` claim found after its live owner has disappeared is marked `startup_unknown` and is not
restarted; persisted `running` or `failed` claims are acknowledged without repeating the call.
Startup or carrier-activation failure is also projected once and acknowledged rather than becoming
an automatic redial signal.

After admission, the leg owner verifies provider connection, call-control, leg, and session IDs on
every normalized callback and dispatches it through the pinned in-memory claim. These later events
do not select a definition or query PostgreSQL. Unknown or mismatched legs fail before the live
backend. The owner is deliberately temporary under a dedicated dynamic supervisor, so an internal
failure cannot restart a call from stale initialization data. Carrier-specific handling for the
post-initiation event types is added with the media and call-control checkpoints; unsupported live
events currently return an explicit processing error rather than being silently discarded.

Telnyx command submission is isolated behind the common adapter and a small Voice API client. Dial
creates one authorized provider leg with the configured Voice API connection, exact callback URL,
opaque Vxpipe leg correlation, optional `detect` AMD, and one bidirectional Opus media stream.
Answer adopts an exact known provider control ID into the same media contract; hangup also targets
only that exact ID. The HTTP client disables redirects and automatic retries for all three
side-effecting commands. A 2xx response is accepted, a bounded 4xx status is a known rejection, and
a transport, 3xx, or 5xx result is an unknown outcome. Unknown never means permission to submit the
command again; later correlated provider events determine what actually happened. Provider bodies
and API credentials are not included in returned errors.

The carrier requests Opus at its supported 16 kHz voice bandwidth rather than L16. Telnyx media
messages carry headerless RTP payloads plus string sequence, chunk, and millisecond timestamp
fields. The adapter admits a socket `start` only when its call-control ID, session ID, opaque leg
state, stream identity, and declared Opus/16 kHz/mono format match the in-memory leg. Subsequent
inbound media is base64-decoded into a provider-neutral packet ordered by media chunk; DTMF is
given the same exact leg identity and its provider occurrence time. Another call, session, stream,
direction, codec, or malformed payload fails before entering a pipeline. The Membrane Opus path
decodes the headerless payload directly to the existing 48 kHz room PCM contract, avoiding FFmpeg
and a separate raw-PCM resampler. Its first accepted provider timestamp is aligned to the nearest
20 ms room-clock boundary using the packet's monotonic arrival time; later packets retain their
provider timing. Exact pinned call identity and strictly increasing media chunks are checked before
Membrane receives a packet. Stale chunks and regressing timestamps are rejected rather than replayed
into the room. The decoded PCM frame, mono mixer, and PCM sink are transport-neutral Gateway media
components shared with WebRTC, while RTP handling and Telnyx clock alignment remain in their owning
transport adapters. In the reverse direction, authorized 20 ms room PCM frames use the shared PCM
source, Membrane's Opus encoder, and Membrane's realtime pacing before the Telnyx sink emits the
provider's exact client-to-server `media.payload` JSON envelope. That envelope contains base64
headerless Opus and no invented stream identifier; the socket itself already names the exact leg.
The policy-aware room-ingress and room-egress coordinators are also Gateway media components rather
than WebRTC components. They own engine attachment handles, media-policy revision barriers, mixer
subscription/backpressure, and transport-pipeline replacement. WebRTC and telephony supply their
own supervised pipeline lifecycle and codec-specific options; neither transport reimplements those
room-facing semantics.
Direct synthesized speech uses a separate transport-neutral playout coordinator. It bounds and
reframes streamed 48 kHz mono PCM, admits only one acknowledged 20 ms transport frame at a time,
and derives started/progress/completed or interrupted duration from transport acknowledgements.
The Telnyx implementation supplies a Membrane Opus encoder, realtime pacer, and WebSocket sink; it
does not invoke FFmpeg. Direct playout and mixer egress remain distinct sources because only direct
playout owns turn callbacks, while the provider socket remains their common serialized wire sink.
The output frame names the agent that produced the speech, which need not be the human participant
owning the target connection. Natural turn boundaries preserve the pipeline's monotonic media
clock; an interruption replaces the pipeline before resetting that clock and admitting new speech.
Before a provider receives a media URL, Gateway issues an opaque, expiring admission token bound to
the exact live leg process and its tenant, call, incarnation, participant, configured service, and
provider identifiers. The token is single-use, is valid only under that service's opaque ingress
key, and is revoked when the leg terminates. Repeated command preparation reuses the still-pending
token instead of creating multiple valid media admissions.
Outbound dialing may reserve that token against the exact supervised leg and ingress key before the
provider has returned its call identifiers. At most one upgrade may wait on the reservation. Binding
the complete validated media identity releases that waiter and consumes the token atomically;
expiry, revocation, or owner death releases it with the same invalid-token outcome. A mismatched bind
does not consume the reservation. This closes the media-before-command-response race without
weakening the exact final binding or exposing whether a token is merely pending.
Each outbound attempt has one temporary OTP leg owner registered by its opaque Vxpipe leg ID. Its
startup validates the already-resolved room destination against the configured service and
origination number, reserves one media URL, and submits one dial command from that process. A
duplicate concurrent start joins the same child and observes the same result rather than submitting
another dial. An accepted command binds the response's complete carrier identity to the exact
tenant, call, room incarnation, participant, and owner before media admission succeeds. An
inbound-only service or mismatched request fails before carrier submission; a failed owner is not
restarted by its supervisor.
When the immediate dial result is unknown, the reservation and the same owner remain pending. A
signed, fully correlated progress event uses only the opaque internal leg ID to locate that existing
owner; it cannot start a leg. The owner rechecks provider, configured connection, origination
number, and authorized destination before adopting the event's complete carrier identity. This
allows an answered or terminal event to settle the attempt even if carrier callbacks arrive out of
order. A mismatch leaves the pending attempt unchanged. On success, the owner registers the provider
leg before binding media, so an early waiting media socket cannot race ahead of subsequent exact-leg
event routing. Accepted responses use that same registration-before-bind operation.
Call Engine initiates a dial transfer only through a narrow host-supplied outbound-leg connector.
The engine resolves the participant's literal number or direct protected creation-time Call
Variable from the immutable plan, builds one request containing the exact tenant, actor, call,
room incarnation, participant, service, and destination, and gives the connector only the remaining
shared transfer deadline. The configured service—not the room request—owns the provider detection
mode. The model continues to select only a participant ref.
Provider configuration and submission stay behind the embedding transport implementation. A
successful connector call yields an opaque cleanup handle retained by the pending human
preparation; expiry or failed preparation disconnects that handle, while successful transfer
leaves the live transport leg under its transport owner. This boundary lets Gateway implement
Telnyx today without introducing a Gateway dependency into Call Engine or making Room Authority
perform network I/O.
The handle also identifies only its provider-neutral owner process for monitoring. Room Authority
monitors that owner while the transfer is pending, fails the attempt if it exits, and removes the
monitor on commit or cleanup. It never reads the connector's opaque carrier reference. This lets a
busy, no-answer, machine, hangup, or local transport failure promptly retain the source through the
ordinary failed-transfer path instead of waiting for the total deadline or coupling engine state to
a provider event schema.
Gateway's default connector resolves the requested service through the tenant-first configured
registry, generates one opaque internal leg ID, starts the existing temporary outbound owner, and
waits only within the engine-supplied remaining deadline for its accepted-or-unknown no-retry dial
result. Both prepared web calls and incoming phone calls receive this connector when the reusable
Gateway HTTP mount uses its default admission backend; custom admission backends remain untouched.
The returned reference identifies the exact owner and supervisor for later cleanup without
exposing carrier credentials or provider command data to Call Engine.
When the outbound media socket supplies a valid start event, that same leg owner creates the
ordinary supervised telephony media subtree using the actor and destination identity already
pinned in the outbound request. The connection first attaches with `transfer_preparation`
admission: its direct-output Membrane pipeline can play the private briefing, but no room ingress
or room-mix egress exists yet. The attached media-session process reports readiness and press-1
acceptance because it is the exact process Room Authority recorded as the connection owner; the
dial owner, webhook process, caller, source agent, and any other socket cannot substitute for it.
Duplicate control from the same session is idempotent for that attempt.

Authenticated lifecycle events are accepted only when their full carrier identity matches that
outbound owner's binding. With configured detection, a machine result submits one provider-neutral
end command for the exact known call-control ID and then retires the temporary owner. Human and
unknown results keep the original acceptance deadline unchanged; a detection event is non-operative
when detection is disabled. Busy, no-answer, timeout, failed and ordinary carrier-ended events retire
the local owner without sending a redundant hangup. Room Authority observes owner loss and uses its
existing generic failed-transfer path, retaining the source and hiding provider detail. Explicit
engine cleanup of an accepted pending leg submits one exact end command before retiring it; an
unknown/unbound attempt can only be cleaned up locally. None of these paths redials.

After the private briefing has completed and the destination has accepted, the room applies the
privacy barrier, commits the human transfer, and sends the promoted attachment to that same media
session. Only then does the session start the provider-specific Membrane room-ingress and
room-egress pipelines with the promoted policy-bearing attachment. Thus private preparation cannot
publish destination audio or hear the room mix, and the carrier-specific leg never bypasses the
room mixer or its policy enforcement during promotion.
Gateway consumes that token only after validating an RFC-compliant WebSocket upgrade at
`GET /api/telephony/telnyx/:ingress_key/media/:token`. A wrong ingress key, expired/reused token,
or malformed token receives the same not-found response. An invalid upgrade does not consume a
valid token. Only the resolved binding—not the token or request data—crosses into the socket
process, whose frame and idle limits are bounded independently of webhook request limits.
The socket first accepts Telnyx's connection preamble without changing room state, then requires a
`start` frame whose call-control ID, call-session ID, client state, and negotiated Opus format match
the binding. That frame pins the provider stream ID for every later media and DTMF frame. Decoded
events are dispatched synchronously to the already-running exact leg owner; a mismatched frame,
binary frame, or unavailable leg closes the socket instead of being guessed or rerouted.

Provider-wire compatibility is kept testable without making ordinary tests place phone calls.
Versioned provider-shaped fixtures are signed over their exact raw body and pass through the real
webhook, media-upgrade, socket, admission, room, and transfer boundaries. A separate opt-in tagged
lane exercises the same adapter against the live Voice API only when an operator explicitly supplies
authorized numbers and provider-reachable webhook/media URLs. The fixture profile is checked against
Telnyx's current official [Voice API webhooks](https://developers.telnyx.com/docs/voice/programmable-voice/voice-api-webhooks),
[dial command](https://developers.telnyx.com/api-reference/call-commands/dial), and
[media-streaming](https://developers.telnyx.com/docs/voice/programmable-voice/media-streaming)
contracts; passing deterministic fixtures alone is not represented as a successful external call.

The first valid media-start event creates one temporary supervised media subtree for that exact
connection. A provider selector supplies only the carrier-specific direct-output, room-ingress, and
room-egress Membrane pipelines; the session setup itself owns the common engine attachment and
coordinator lifecycle. The attached connection makes the transport-neutral direct-output
coordinator available to the active agent, sends each accepted inbound frame to the connection's
speech ingress when enabled and to the room mixer when permitted, and subscribes the phone leg to
its permitted room mix. Droppable overload/staleness results do not tear down a healthy call, while
a fatal media result does.

The connection supervisor owns the media session, its three coordinators, and their Membrane
pipelines as one `one_for_all` subtree. The session monitors the authenticated media socket, exact
provider leg owner, and room-authority monitor returned by attachment. Loss of any of those owners
ends the whole media subtree without restarting it or reconstructing the call. Duplicate media-start
delivery reuses the registered connection subtree, and later media must still originate from the
same authenticated socket and carry the pinned stream ID. This live path uses the pinned in-memory
claim and attachment; it does not add a PostgreSQL lookup to individual media delivery.

The Call Engine runtime now represents a web-human transfer as a generated attempt ID and a
destination connection with `transfer_preparation` admission. That attachment has no speech input,
room-audio publication, room-audio subscription, participant snapshot, transcript projection, or
Call Variables projection. A dedicated TTS capability uses the retained source-agent voice to send
the bounded reason and optional fixed notice only to the destination output sink. It does not reuse
the source connection or publish the private briefing as ordinary room transcript history.

The protocol-neutral `ParticipantTransferControl` command accepts only `media_ready` or `accept`
from the exact attached destination process, actor, participant, connection, room incarnation, and
attempt. Early acceptance is remembered but cannot commit before usable media and completed output
playback; stale, forged, and duplicate controls reject. The room applies participant admission and
its media-policy transition before promoting the connection to ordinary mix-minus media, then
clears agent text ownership and arranges source-subtree teardown through the existing transfer-tool
completion effect. Call Variables and the room lifecycle remain unchanged. A dropped private
destination cleans its attempt and reports a generic tool failure while the source remains active.

For a running call, the gateway recognizes this destination's pinned transfer admission and issues
a provisional session bound to the existing room incarnation; it does not invoke ordinary
participant joining. The WebRTC connection retains the normal `chat` data channel for unmodified
RTVI and adds a separate `vxpipe` data channel for the narrow transfer control. That channel
exposes only bounded preparation, destination acceptance, activation, and generic failure. It does
not expose the private briefing, Call Variables, history, internal rejection reason, PIDs, or room
authority. Acceptance and media-ready commands are reconstructed from the authenticated session
and the actual connection process before the engine reauthorizes the exact current attempt.

The destination connection starts main room ingress and mix-minus egress only after the briefing
playback and policy commit. Both Membrane pipelines must report usable readiness, and the source
participant must have exited, before the gateway announces the transfer as active. This prevents
an acknowledgement from racing the final presence-driven policy replacement. Dropping or failing
the provisional connection still leaves the source responsible.

Agent Runtime accepts an internal initial-conversation seed for activation construction. That
boundary retains the destination's independently configured system prompt and accepts only plain
caller-origin user messages and tool-free assistant messages. It rejects system messages, engine
messages, tool messages, tool calls, and tool correlation metadata rather than trusting a caller to
pre-filter them. These messages are committed history, not a client-facing session-initialization
input. Call Engine remains responsible for deriving the list from confirmed room delivery facts and
the pinned destination policy before it can use this boundary.

Call Engine now maintains that private room projection independently of Agent Runtime conversation
and asynchronous archive delivery. Caller text enters it only after the room accepts the input for
agent processing; final STT input follows the same accepted-command boundary. Assistant text enters
it only when the audio sink reports playback completion, so generated, queued, interrupted, or
otherwise unplayed text cannot cross the transfer. Its inspection representation exposes only the
entry count. At accepted transfer preparation, the room takes one immutable policy projection:
`all_spoken` supplies all entries, `last_n_spoken` supplies the configured trailing utterance count,
and `fresh`/`selected` supply no prior messages. Destination startup receives this vetted list
through the Agent Runtime seed boundary. Later speech during preparation cannot mutate the already
prepared destination's history. Selected-mode transient context is described below; re-entry
remains a separate follow-up.

For a `selected` destination, the generated transfer schema requires the source agent to provide a
non-empty transfer reason of at most 1,024 characters. This requirement is destination-specific: a
single transfer tool can still target ordinary-history destinations without accepting a reason for
those variants. Call Engine validates the selected variant again while constructing its private
transfer request and keeps the reason out of `Inspect` and client events. Plan Startup constructs a
redacted Call Engine model-context source from the destination's immutable variable binding and
that reason. Before every destination generation, the source reads through
`CallVariables.Binding`, so the variables owner independently enforces the pinned participant and
readable sections. The transient JSON contains `call_variables` and, for selected transfers only,
`transfer.reason`; it is neither copied into conversation history nor exposed as a client event.
The application defaults bound this local source call to one second and its complete encoded model
context to 256 KiB, both configurable through the Call Engine Agent Runtime settings.

The first runtime checkpoint makes this a runnable fresh-history agent-to-agent transfer. The
activation-owned tool worker constructs a private request and calls Room Authority; Room Authority
reauthorizes the room/incarnation, caller connection, current source participant and activation,
immutable source allowlist, and pinned destination identity before starting anything. It prepares
the destination participant, agent runtime, and selected TTS capability without changing the active
text capability. Only successful preparation commits the new text/TTS routing, preserves the room
and Call Variables process, emits one safe completion through the existing tool-event contract, and
then terminates the source participant subtree. A stale source is rejected before destination
startup. Runtime configuration retained for later participant materialization has a redacted
inspection surface.

This checkpoint supports fresh, all-spoken, and bounded-last-spoken destination history and
implements preparation failure, total-deadline cleanup, duplicate-attempt rejection, and late-result
exclusion. Selected transfers now require and privately deliver a bounded reason alongside only
the destination-readable variables. Variable projections refresh before every generation, and the
variable-tool continuation observes its newly accepted revision. Re-entry keeps the participant
identity, creates a fresh activation, and does not replay its first greeting.

The current agent-only transfer path retains the active source's resolved TTS runtime separately
from its temporary capability process. If source TTS disappears during destination preparation and
that preparation fails, one room-supervised task may rebuild source TTS within a fixed 750 ms
budget. That bound fits inside the transfer tool's existing one-second allowance beyond the
authored attempt deadline, rather than resetting the main attempt budget. Room Authority coordinates
only the task result; it does not start the capability inline.
The transfer returns its generic failure after restoration settles, while private history records
whether restoration was unnecessary, completed, failed, or timed out. The replacement is not
restarted again if it later fails. Successful transfer commit replaces the retained runtime with
the destination's pinned selection. The runtime's inspection representation excludes its provider
and transport values so retaining it does not add credentials to Room Authority crash reports.
Deadline cleanup is also scheduled beneath the room transfer task supervisor. A provider transport
that is still completing its own bounded startup therefore cannot make Room Authority wait on a
capability-supervisor cleanup call. The transfer task pool has a fixed per-room child limit; late
startup is stopped without acquiring room authority, and saturation fails later preparation rather
than accumulating unbounded work.
Prepared membership is still provisional when its startup task reports success. At commit,
Participant Lifecycle verifies that the exact participant supervisor remains registered under the
pinned tenant, room, and participant identity before adding it to authoritative room state. A
destination that exited in the preparation-to-commit gap is discarded, receives no routing
authority, and produces a generic transfer failure; the private transfer fact retains the closed
`destination_commit_unavailable` cause.

### Presence-driven media and transcript policy — approved R38

Normal call-wide permissions live in `media_policy`. Each participant's optional
`while_present` contributes room-wide restrictions while that participant is
authoritatively admitted. Both use `audio_routes`, `transcript_routes`,
`record_audio`, and `save_transcripts`. These replace public STT/TTS capability
denials; earlier `presence_policy`/`capability_denials` examples are superseded.
See the [approved definition example](../labnotes/20260905-0405-call-definition-design.md#participant-presence-constrains-the-capability-topology).

`audio_routes` maps publisher participant-definition keys to recipient-key arrays,
including humans and agents. An explicit map is the complete allowlist: only
listed sources may publish room audio, only to their listed recipients. An empty
recipient list permits no other participant to hear that source. There is no
implicit self-loop, full-room monitor access, wildcard, role selector, or expression.
`transcript_routes` separately maps the speech-source participant to recipients
of its live derived transcript; include self explicitly if wanted.

Omission adds no restriction and inherits the normal policy. An explicit empty
route map permits no routes. Do not deep-merge a presence map while preserving
unlisted routes. Intersect publisher permissions and recipient routes from all
present policies and the normal policy; host/application authorization remains a
ceiling. Storage false wins over true/omission. Leaving removes only that owner's
contribution, not surviving restrictions. Mere transport loss does not remove
authoritative presence or reset work.

`record_audio` and `save_transcripts` are independent room-wide booleans initially,
not per-source capture overrides. False restricts the current interval: no tracks,
full mixes, or derivatives through Vxpipe-owned recording paths when audio is
forbidden; no automatically stored transcripts or copies in archive/log/export
paths when transcript storage is forbidden. Previously permitted intake history
is not deleted retroactively; whole-call retention cleanup is unchanged. These
booleans choose permitted capture/storage, not a new `call_retention` duration.
Automatic model-debug archives must not copy denied transcripts. Automatic paths honor
source-interval privacy even when processed later. This is not generic taint
tracking/redaction of arbitrary externally copied text or control over provider/
client copies, nor a compliance guarantee. Complete observed tool history still
follows its privacy and credential/header exclusions.

Policies permit flows; they do not enable unconfigured recording/STT or activate
every catalog participant. Live transcription sends audio to a provider: no storage
does not mean no processing. If no permitted live transcript recipient or storage
consumer needs recognition, stop those STT flows. Configured capabilities remain
internal implementation details. Call Variables and their local acceptance/
permission rules are unchanged.

During private transfer preparation, the destination receives only the authorized
briefing/configured notice through its isolated lane, which the caller cannot
hear; it is not yet admitted to the main conversation. Acceptance stays bound to
the pending attempt. At commit, apply `while_present` restrictions before connecting
main media, then hand off and terminate the source. This is the existing transfer
phase, not another workflow graph or general concurrent-agent consultation.

`RoomAuthority` authorizes the pinned resolved policy/topology; mixing, media routes,
transcript projections, recording, and archive boundaries enforce it without
frontend-only muting or database lookups per packet. Fail closed if the privacy
barrier cannot apply before commit. New delivery, queued/late old output, later
reactivation, and retrospective replay must not bypass a restricted interval.
Source responsibility, total transfer deadline, and restoration rules remain.

The implemented media-policy runtime has one significant policy authority, one significant
`RoomMixer`, and one significant `TranscriptRouter` per planned room. The authority composes
immutable effective snapshots and commits a new revision only after every registered enforcer
installs it. Rejection, timeout, malformed acknowledgement, or enforcer loss ends the room. Both
consumers are registered before entry participants are admitted, so startup revisions and later
presence transitions pass through the same barrier.

`RoomMixer` accepts normalized, timestamped s16le PCM frames tagged with the installed policy
revision. It rejects wrong-room, absent/output-only source, stale revision, stale sequence, stale
timestamp, duplicate, wrong-format, and over-capacity input. Fixed-size timestamp buckets align
sources; saturating PCM addition produces mix-minus, full-mix, and individual-track outputs after
`audio_routes` filtering. Output subscriptions belong to present participant identities. Full-mix
and track subscribers are silent monitors at this boundary and cannot also publish or take a
mix-minus subscription. Per-subscription output queues are bounded inside the mixer and expose
only coalesced availability notices plus opaque-token pulls, keeping slow consumers out of the
mixing path. Installing any new policy revision clears pending input and output frames before the
acknowledgement, and every output retains source IDs, timestamp, and policy revision. Transport
input normalization begins in the Gateway with a per-track Membrane pipeline. Official Membrane
elements own RTP jitter buffering and rollover-aware timestamps, Opus depayloading/parsing and
decoding, and exact 20 ms PCM rechunking. The Opus decoder already emits 48 kHz s16le, so Vxpipe
uses a small Membrane filter only for mono passthrough or stereo-to-mono averaging; FFmpeg is not
part of this path. A room-timestamp filter supplies the Vxpipe-specific shared-clock offset, and
the sink restores the pinned tenant, room-incarnation, participant, connection, and track
identity. The engine's PCM addition delegates to Membrane's audio-mixer adder. Vxpipe retains the
policy-aware timestamp buckets, mix-minus/full/individual routing, revision barrier, and bounded
subscriber queues because a generic one-output mixer does not express those room contracts.
Connection-scoped output orchestration and Membrane-backed WebRTC mix encoding/pacing consume these
opaque subscriptions without exposing mixer ownership to the Gateway. Recording taps remain a
subsequent boundary; they cannot omit revision provenance or bypass this barrier.

The connection-to-mixer ingress boundary is now implemented without exposing mixer or policy
processes as transport APIs. A planned-room `ConnectionAttachment` carries an opaque room-audio
handle and the mixer's one VM-relative clock origin; legacy ad-hoc attachments explicitly report
that room audio is disabled. Each writable planned WebRTC connection supervises a separate
`RoomAudioIngress` coordinator and Membrane normalizer. The coordinator registers with the same
media-policy authority as the mixer and transcript router. Before acknowledging any later policy
revision, it terminates and replaces the entire jitter/decode/framing pipeline, discards late
output from the old pipeline generation, and rejects transport frames received through the
replacement boundary. Only current-generation PCM is assigned the installed revision and a
connection-stable monotonic source sequence before crossing the engine's opaque handle into the
mixer. Raw Opus continues independently to configured STT, so human-only planned calls can use
the mixer without fabricating an STT capability while legacy rooms retain their STT-only route.
The default WebRTC jitter latency for this path is 200 ms.

Planned rooms enable the mixer's room-clock scheduler with a 300 ms playout delay. Every PCM frame
keeps a sample timestamp relative to the mixer's monotonic clock origin. On each frame-duration
tick, the mixer converts elapsed monotonic time minus that delay into an aligned sample timestamp
and finalizes every bucket through that point. Packet arrival does not advance or pause the room
clock, so a stopped or silent publisher cannot strand another participant's final frames. The
delay covers the Gateway's default 200 ms RTP jitter window and leaves 100 ms for cross-connection
arrival skew. Directly constructed mixers omit scheduling unless `playout_delay_ms` is supplied,
which preserves deterministic manual flushing for focused tests and embedding-specific control.
The Gateway drains these subscriptions through Membrane-backed Opus egress. The rendered
multi-browser sample remains subsequent work.

The attachment also makes output authority explicit. Every ordinary human connection in a planned
room receives policy-authorized mix-minus output, including while an agent owns the room's direct
TTS path; monitor connections receive full mix and cannot publish. The transport creates each
subscription only through the opaque Call Engine handle. Agent TTS remains a direct output source,
while authorized human callers can hear other admitted room sources before and after agent
handoff. This avoids deriving media ownership from whether STT happens to be configured and lets a
human-only continuation reuse the same room/mixer path rather than switch to a second bridge.

Silent-monitor authority is carried by the engine-issued connection attachment rather than by a
client-supplied mixer option. An admitted monitor receives `:full_mix`, has no STT or room-audio
ingress, and any RTP it sends is discarded without terminating its receive-only connection. The
Gateway starts no normalizer for that attachment and cannot downgrade or broaden the output mode:
the engine replaces the requested subscription mode with the granted one. The same `audio_routes`
snapshot filters full-mix sources, so monitor admission alone grants neither publication nor
unrestricted listening.

`TranscriptRouter` keeps a bounded installed-revision history for source-interval decisions (128
revisions by default). A current transcript projection reaches only connected, present
participant identities permitted by `transcript_routes`; a projection tagged with an older
revision is never delivered later, even
after policy relaxation. Its source revision independently supplies `save_transcripts` provenance.
Room-generated participant transcriptions and agent text output pass through this router, while
typed input and generated/delivered transcript-bearing archive facts receive the same current
source policy before entering the bounded archive handoff. A denied payload is stripped at the
engine boundary and the delayed Calls projection repeats that check. Policy-router failure denies
delivery/storage while the significant-child failure tears down the room. Provider-session
revision pinning and STT demand/restart at policy boundaries remain required before claiming that
late provider results spanning a presence transition are completely source-interval accurate.
If a delayed projection outlives the retained history, it fails closed instead of inferring policy.

Admission is also fail-closed when a concrete mixer or transcript router cannot install the next
revision. The policy authority terminates the room rather than retaining a partially updated
bridge, and the public participant-join boundary converts the concurrent room teardown into a
retryable protocol-neutral error. If transcript policy lookup itself is unavailable, delivery has
no recipients and archive provenance explicitly denies transcript storage; no content is handed to
the asynchronous archive queue under an inferred policy.

Dial destinations may be literal participant `connection.number` values or come
from a declared creation-time variable, using the candidate alternative
`number_from_variable: {"section": "routing", "variable": "support_number"}`.
The two sources are mutually exclusive. Section/variable names are direct keys,
not expressions or a nested path language. The trusted integrating backend must
choose an authorized destination and supply it through `initial_variables`, not
blindly forward a caller-provided phone number.

Reject a definition if any agent has write permission to a section referenced
for dialing this way. Agent read permission is optional and unnecessary for
trusted engine resolution; no per-variable permission type is introduced.
Resolve the pinned connection reference against that protected initialized data.
Missing, null, or invalid numbers fail the transfer before dialing, through the
existing typed failure/source-agent responsibility contract, without a default.

The model still requests only a permitted destination participant ref. It cannot
provide a number, provider, URL, or variable ref as transfer arguments; the
executor rechecks the source's compiler-derived allowlist. It may choose when to
request transfer and among explicitly allowed roles, not an arbitrary dial
destination. If the business needs timing restrictions, enforce them outside the
LLM. This adds no generic outbound allowlist/region policy or runtime mutation API,
and the candidate field is documented design, not implemented schema/runtime.

## Architectural boundaries

```text
Pipecat clients ──> RTVI 2.x adapter ─┐
Future clients  ──> Custom adapter    ├──> Protocol-neutral commands
Telephony       ──> SIP adapter       ┘              │
                                                     ▼
                                          OTP-native Call Engine
                                                     │
                                      Domain events / media / metrics
                                                     ▼
                                  Protocol-specific event projections
```

Four contracts remain separate:

1. **Media transport:** WebRTC tracks, SIP/RTP, or WebSocket audio and video.
2. **Client protocol:** RTVI or another adapter's readiness, commands, and event
   projection.
3. **Call-engine protocol:** typed commands, signals, media frames, and domain
   events exchanged between supervised Vxpipe processes.
4. **Management and delivery:** authenticated REST/control operations, durable
   event subscriptions, webhooks, artifacts, and configuration.

The `vxpipe_gateway` application owns external protocol and transport adapters.
The `vxpipe_call_engine` application owns room state, participant and capability
lifecycle, routing, turn semantics, tools, transfers, and protocol-neutral
events. The dependency direction is from gateway to the public call-engine
contract. The call engine must not depend on RTVI message names, JSON shapes,
client SDKs, or transport credentials.

The planned `vxpipe_agent_runtime` application owns only the reusable, supervised
ReqLLM conversation/tool-loop boundary for one agent activation. Call Engine depends on
its public data-tool, executor and event contracts; the runtime must not depend back on
Call Engine. `vxpipe_mcp` independently owns ExMCP protocol mechanics. Call Engine is the
only component that connects an authorized private MCP binding to an agent-runtime tool
request, preserving an acyclic dependency graph.

### Reusable gateway and console

The approved [gateway/console split](gateway-console-boundary.md) adds a separate
Phoenix application, `vxpipe_console`, using the `Vxpipe.Console` namespace.
It includes the existing `vxpipe_gateway` as a dependency; it does not rename,
regenerate or convert that application. The console owns browser presentation,
samples assets and dashboard pages. Gateway owns the reusable API/protocol and
connection runtime, without a dependency on Phoenix or our console.

Both the console and another embedding host should be able to mount the gateway
HTTP interface into their endpoint and start its required supervised processes.
Our console deployment has one Phoenix HTTP listener: gateway is a Plug in that
endpoint, its standalone listener is disabled, and no internal HTTP hop is needed.
Other hosts may instead enable the standalone gateway listener without console.
Mounted paths, transport upgrades and runtime configuration require explicit
integration verification; this is an approved target, not an assertion that
every embedding mode already works.

The console uses public gateway/Calls interfaces. Ecto Repo, schemas and migrations
remain in `vxpipe_persistence`; `vxpipe_calls` owns database-neutral workflows and
repository interfaces. This split changes neither the engine's independent
embedding contract nor the asynchronous live-storage design.

The managed repository-development sample follows the same boundary. Console
supervises a small trusted backend process that bootstraps a private development
tenant/API key and publishes the configured definition through Calls. It retains
the plaintext key and configured initial variables only in redacted process state.
Its same-origin endpoint returns a public call locator plus join token; the browser
then uses the reusable gateway's ordinary participant-session admission. Console
does not query Repo or implement token verification. If persistence is disabled,
the sample process is absent and the browser retains the database-free trusted
gateway fallback.

The implemented control-plane baseline follows this boundary. `vxpipe_calls`
defines credential and definition/deployment repository ports, while
`vxpipe_persistence` supplies the optional PostgreSQL adapter. Its tenant/API-key,
immutable definition-revision, and participant-route tables use private SQL keys;
public tenant keys, API-key IDs, definition IDs, and route UUIDs remain separate.
Draft routes resolve only after explicit publication. See
[tenant control-plane operations](tenant-control-plane.md) for migration and
trusted bootstrap commands.

## Gateway protocol adapter contract

Every client protocol adapter must implement the same responsibilities:

- negotiate the supported protocol version and optional features;
- bind an authenticated gateway session to a tenant, actor, room, participant,
  connection, and transport;
- decode external messages into validated engine commands;
- authorize each command before it reaches the room authority;
- project only authorized engine events into the external protocol;
- correlate requests and responses with bounded deadlines;
- apply connection-level rate and queue limits;
- redact private engine and provider state; and
- detach or terminate the participant according to the room's disconnect
  policy.

The common adapter state includes:

- protocol name and negotiated version;
- advertised optional capabilities;
- tenant, actor, roles, and scopes;
- stable interaction and room IDs;
- room incarnation ID;
- participant and connection IDs;
- transport identity and credential audience;
- last acknowledged durable event cursor; and
- connection-specific limits and deadlines.

The adapter must never expose PIDs or use a distributed PID as public identity.

## RTVI 2.x compatibility

The first adapter accepts RTVI major version 2 and implements the current 2.1
feature set. Deprecated major version 1 is not part of the initial contract.
Unsupported major versions receive a protocol error and cannot activate a
session.

This needs explicit conformance testing because the standalone standard page
labels itself version 1.0 while including later 1.2 additions, and the current
RTVIProcessor advertises 2.1.0. The documentation also contains details that
should not be treated as a generated schema, such as an inconsistent
`server-response` type label and metric values without a reliable unit field.
Actual current client behavior and versioned fixtures are the compatibility
authority.

### Session startup

RTVI does not authenticate a user or create transport credentials. Before the
RTVI handshake, Vxpipe uses one client admission workflow: authenticated call
creation/preparation returns a scoped join token, then the client joins with that
token. A backend client uses the same flow as a browser client; there is no
separate API-key-authenticated direct WebSocket start path. Across preparation
and token-based admission the gateway must:

1. authenticate the caller;
2. authorize creation of or admission to a room;
3. resolve the room, participant role, agent version, and transport;
4. create a gateway session with a bounded lifetime;
5. issue narrowly scoped transport credentials; and
6. return connection parameters understood by the chosen client transport.

After the media transport connects, `client-ready` negotiates RTVI version and
attaches the gateway session. Vxpipe sends `bot-ready` only after room admission,
the requested participant, and the required agent pipeline are ready. A
connected transport is not sufficient evidence that the bot can process input.
When a startup notice is configured, the caller transport can be established for
playback and room/participant capabilities may warm up concurrently. Participant
audio delivery and normal conversation remain gated until playback completes;
provider readiness alone does not release that gate.

### Standard message mapping

| RTVI input | Engine operation |
| --- | --- |
| `client-ready` | Negotiate protocol and attach the participant connection |
| `disconnect-bot` | Detach or end according to session policy |
| `send-text` | Submit text; interrupt older room-agent work when `run_immediately` is true, otherwise retain FIFO order |
| `dtmf` | Publish ordered DTMF input to the selected connection/input collector |
| `llm-function-call-result` | Complete the matching client-owned tool invocation |
| `client-message` | Dispatch a validated optional Vxpipe request or notification |
| UI messages | Dispatch authorized UI state, event, and cancellation operations |

Engine events project to standard speaking, transcription, bot-output,
LLM/TTS, tool, error, metric, server-message, and UI messages. A client that
does not opt into any Vxpipe-specific capability must still be able to complete
a normal text or audio conversation.

### Optional Vxpipe messages

Vxpipe-specific features use RTVI's standard custom-message mechanisms rather
than incompatible top-level message types. Clients advertise or discover them
through `bot-ready.data.about.vxpipe.extensions`.

Client notifications use `client-message.data.t`. Correlated queries and
mutations use the SDK's `sendClientRequest` facility. Server notifications use
`server-message` with a versioned envelope:

```json
{
  "t": "vxpipe.event",
  "v": 1,
  "d": {
    "event_id": "evt_01...",
    "room_id": "room_01...",
    "room_sequence": 42,
    "kind": "participant.joined",
    "occurred_at": "2026-09-03T05:00:00Z",
    "correlation_id": "cmd_01...",
    "data": {}
  }
}
```

Agent interruption uses `t: "vxpipe.turn"`, `v: 1`, and
`d.kind: "interrupted"`. Its data names the interrupted agent participant,
originating participant and turn, confirmed played milliseconds, and the
authenticated participant, connection, command, and correlation that caused the
interruption. The trigger may be immediate typed input or an authenticated
provider speech-start signal. The parallel standard `bot-interrupted` event
remains unmodified.

All mutations carry a stable `command_id`. Domain-level responses have a typed
result envelope:

```json
{
  "ok": false,
  "error": {
    "code": "participant_not_authorized",
    "message": "The participant cannot perform this operation.",
    "retryable": false,
    "details": {}
  }
}
```

RTVI protocol errors remain reserved for malformed, unsupported, or
uncorrelatable wire messages.

One deliberately separate transport mechanism exists for a provisional human-transfer
destination. Its WebRTC connection may negotiate a `vxpipe` data channel alongside RTVI's `chat`
channel. The server sends `transfer.preparation`, the authenticated destination sends
`transfer.accept`, and the server sends `transfer.active` only after engine commit and usable main
media. Controls carry bounded public attempt/participant identifiers, never briefing content or
internal authorization detail. This is not an RTVI message family and does not alter behavior for
an unmodified RTVI 2.x client. Future adapters may expose the same protocol-neutral engine command
through another authenticated mechanism.

Initial optional message families are:

- `vxpipe.capabilities`: negotiated protocol, transport, and engine features;
- `vxpipe.room`: snapshot, roster, subscriptions, lifecycle, and replay cursor;
- `vxpipe.participant`: roles, state, mute, hold, and connection state;
- `vxpipe.turn`: speech, transcript, endpointing, interruption, and commit state;
- `vxpipe.playout`: queued, first-audio, spoken ranges, truncation, and completion;
- `vxpipe.agent`: active-agent state and agent handoff;
- `vxpipe.call`: telephony legs, DTMF, voicemail, IVR, and transfer lifecycle;
- `vxpipe.tool`: invocation, progress, approval, result, and cancellation;
- `vxpipe.debug`: authorized live timeline, metrics, and bounded replay; and
- `vxpipe.session`: connection replacement and room resumption metadata.

These names describe external schemas only. Future protocol adapters may expose
the same engine capabilities with different wire messages.

## Call-engine protocol

The engine contract separates messages by lifecycle and delivery requirements.

### Commands


Commands request acknowledged state changes. Every command contains:

- command ID and schema version;
- tenant and authenticated actor identity;
- required scopes;
- room and incarnation IDs;
- optional participant, connection, capability, or tool target;
- absolute deadline;
- idempotency policy; and
- typed payload.

Examples include room admission, adding or removing a participant, changing
routing, sending text, beginning an input collection, completing a client tool,
initiating a transfer, changing an active agent, and ending a session.

Commands that alter authoritative room state receive a typed success or failure.
Calls are bounded. The engine must not make cyclic synchronous calls between
room, participant, connection, and capability processes.

### Signals

Signals cover interruption, cancellation, disconnect, nonterminal stop, process
failure, and shutdown. They are not ordinary commands because timely delivery
can invalidate queued work.

An interruption cancels speculative model work, interruptible tool work, queued
speech, and unsent audio for the affected turn while leaving the conversation
active. Graceful end drains accepted work. Immediate cancellation abandons it.
A nonterminal stop drains a pipeline stage while retaining the process for later
work. These transitions must remain distinct.

### Media frames

Media frames are ephemeral and contain:

- room, incarnation, participant, connection, and track IDs;
- format, codec, sample rate, channels, and direction;
- capture/presentation timestamp and sequence;
- turn or utterance correlation when known;
- provider-native metadata in a bounded, redacted namespace; and
- the binary payload.

Raw media is never appended to room event history. Recorders and stream sinks
subscribe through explicit bounded media paths with retention, encryption, and
failure policy.

### Domain events

Committed domain events contain:

- globally unique event ID;
- schema version;
- tenant, interaction, room, and incarnation IDs;
- monotonic sequence within the room incarnation;
- participant, connection, capability, agent-version, and transport IDs when
  applicable;
- occurrence timestamp;
- causation and correlation IDs;
- visibility and data-classification metadata;
- normalized payload; and
- optional redacted provider payload.

Events are immutable after commitment. Ephemeral processor messages and media
frames do not become durable merely because they describe lifecycle activity.
Only the room authority assigns room sequence numbers.

### Snapshots and replay

A snapshot is a public, authorized projection, never a serialization of internal
GenServer state. It includes the resolved room version, current lifecycle,
participants, connections, capabilities, active agent, current transfers/tools,
and the last durable room sequence.

Snapshot/event-cursor synchronization is separate from permission to resume a
call. Media is not replayed through the event journal. Same-call caller
reconnection is deferred for the initial slice; after a logical call ends,
connecting again starts a new call. Any future same-call reconnect would require
fresh transport identity and explicit admission authorization, not just a cursor
or a new token.

## Conversation semantics

### Human input and transcription

The initial thought that a human publishes transcription only after a completed
turn is too coarse. Vxpipe distinguishes:

1. provider speech-activity start or stop, when available;
2. semantic user-speaking start or stop;
3. partial transcript;
4. provider-final transcript segment;
5. committed conversational turn;
6. corrected or replaced transcript; and
7. cancelled or discarded turn.

Partial and segment-final transcripts remain observable to authorized clients
and monitors. The LLM consumes only the configured committed-turn event unless
the agent explicitly enables speculative generation. Provider `final` must not
be assumed to mean conversational end of turn.

RTVI `user-transcription.final` projects partial versus provider-final state for
compatibility. The optional `vxpipe.turn` messages carry the richer turn ID,
phase, evidence, timestamps, endpointing reason, and commit state.

Microphone media remains active while agent output plays. A normalized provider
`StartOfTurn` is an immediate interruption signal from the participant and
connection to which that STT capability is bound. It stops older work before the
new participant-turn event is committed. The provider's later `EndOfTurn`
commits input but does not repeat cancellation. This uses hosted provider turn
detection; the call engine does not run a local VAD.

### Agent output and actual playout

Generated LLM text, text submitted to TTS, synthesized audio, scheduled audio,
and audio actually played are different facts. Conversation history and durable
transcripts must not claim that interrupted or dropped text was heard.

Each agent utterance receives an ID. The output path reports queued text,
synthesized ranges, first audio, played word or character ranges, interruption,
truncation, and completion. The final assistant transcript is derived from
confirmed playout where the transport supplies sufficient evidence; otherwise
it carries an explicit confidence/source marker.

RTVI `bot-output` remains the compatible best-effort projection. The
`vxpipe.playout` family exposes precise Vxpipe semantics.

## OTP runtime topology

```text
Vxpipe.CallEngine.Application
├── Registry / cluster room directory
├── DynamicSupervisor RoomSupervisor
│   └── RoomIncarnationSupervisor
│       ├── RoomAuthority
│       ├── ParticipantSupervisor
│       ├── ConnectionSupervisor
│       ├── CapabilitySupervisor
│       └── PipelineSupervisor
├── Task.Supervisor for bounded external work
└── Event/metric exporter supervisors
```

Each room incarnation is an isolation boundary with its own process tree and
per-process heaps. Individual runtime workers are started through their owning
dynamic supervisor and monitored by the room authority.

The room authority must never restart alone beside surviving workers. An
authority or static room-infrastructure failure terminates the complete room
incarnation. R40 permits bookkeeping recovery about an existing room/leg, not
automatically creating a fresh call incarnation, redialing, or resuming a crashed
call. Commands carrying an old incarnation ID are rejected.

Recoverable provider or participant failures do not automatically destroy the
room. Isolated worker restart requires adapter-declared safety and the applicable
approved failure policy/budget; it cannot repeat an uncertain external operation
or reset R36's single restoration attempt. Otherwise report failure through normal
handling. R50 allows supported provider-native LLM fallback, not a generic engine
fallback chain or restart of a terminated call.

### Scheduling and backpressure

The room authority owns state transitions, not audio processing. Media,
provider I/O, model work, serialization, persistence, webhooks, recordings, and
metrics export execute outside its mailbox.

Every streaming edge declares:

- maximum queued frames/bytes and age;
- whether it blocks, drops newest, drops oldest, coalesces, or terminates;
- cancellation behavior;
- downstream deadline;
- overload metric and event; and
- whether loss is acceptable for that frame class.

BEAM mailboxes are not a backpressure mechanism. Queue length, process memory,
reductions, scheduler utilization, and dropped/coalesced work are monitored.

OTP 28 priority aliases may be evaluated for sparse interrupt or cancellation
signals, but not for media or normal events. Erlang's
[priority-message documentation](https://www.erlang.org/doc/system/ref_man_processes.html#priority-messages)
warns that the feature is intended for narrow cases and not large priority
queues. The baseline design uses an explicit control path and bounded stage
queues; priority aliases are adopted only if focused benchmarks show a material
benefit.

### Cluster ownership

The cluster directory maps each active room to `{node, incarnation}`. A gateway
resolves the current owner and forwards protocol-neutral commands rather than
exposing remote PIDs. Ownership registration is conditional on the incarnation
so delayed messages from a prior owner cannot reclaim or mutate the room.

Node loss, network partition, and owner migration have explicit admission and
recovery policies. Vxpipe does not assume BEAM distribution itself supplies
public authentication, durable state, or split-brain resolution.

## Security and observability

The gateway authorizes every room and participant operation. Admission to a
transport does not imply permission to observe all room events or control other
participants.

API-key administration starts through trusted OTP/CLI operations, including
creating the first key without an existing API key. Keys are bound to one tenant
and use `admin` and `calls` permission scopes. This approves the tenant boundary
and scope split, not per-definition allowlists, arbitrary per-operation grants,
an admin HTTP API, or an implicit relationship between the two scopes. Each
tenant may have multiple independently revocable keys, allowing separate
integrations and overlap while replacing a key. Show a generated key once and
persist only its one-way digest and metadata, never a recoverable copy.

Revoking an API key rejects further authentication with that key. It does not
invalidate previously issued join tokens or end established connections. Join
tokens are not coupled to their issuing API key for revocation; admission checks
the token's own expiry, single-use status, tenant/call/participant scope, and
current lifecycle eligibility. An otherwise eligible unused token remains valid
after the requesting API key is revoked. Obtaining another token still requires
valid API-key authentication.

All API clients prepare/create the call with an authenticated request containing
initial variables, receive a scoped token, and use token-based joining. The
backend may hand the token to a browser or use it itself. Joining does not accept
replacement initial variables or an API key as a direct-start alternative.
Existing-call token issuance still serves eligible unstarted records and first
admission of eligible participants into live calls. The browser WebRTC path stays
supported; a future WebSocket adapter needs its token-delivery encoding, not a
separate initialization flow. Proposed deadlines/byte limits for the removed
direct-WebSocket setup message are not adopted or transferred to another route.

Call creation already accepts any declared initial variables from the authorized
creator, integrating backend, or trusted ingress adapter. Telephony ingress uses
that same contract for values it can supply; no additional customer-lookup or
admission-resolver feature is required. Unknown values remain unfilled and can
be populated later by the usual permitted variable tools. Caller number alone
must not silently become verified customer identity.

Call creation does not offer an `Idempotency-Key` header, duplicate-suppression
key, or cached deduplication response. Repeated authorized creation requests may
create separate prepared records. The integrating application/user may later
delete unwanted records through an authorized mechanism; no deletion endpoint or
UI is implemented here. This is distinct from single-use token claims, same-call
admission exclusion, and telephony webhook/leg deduplication, which still prevent
starting the same admitted call twice.

Join tokens expire five minutes after issuance by default. The authenticated
backend requesting a token may request a longer lifetime, including when
requesting one for an existing call. No additional maximum is approved here.
The browser cannot extend an issued token by changing its join request. Token
expiry prevents later admission with that token; it neither deletes the prepared
call record nor ends an established call. Gateway authentication and persistence
ports own credentials and token handling; the engine receives neither secret.

An authorized backend may replace an expired token for an eligible unstarted
call record, preserving its pinned definition and initial variables without
starting a room at issuance. Another token does not supersede earlier unused
tokens: each keeps its own expiry and single-use status. Admission still enforces
tenant/call/participant eligibility so distinct tokens cannot create duplicate
callers or take over active connections. Same-call caller reconnection is deferred:
a fresh token is not proof that the same person is returning. Once the logical call ends,
the next call has a new record and identity. This does not prevent first admission
of an eligible transfer destination or other not-yet-admitted participant into
an existing live call. Accepted tokens stay consumed; pending admission must be
reconciled before any new attempt, and active connections cannot be taken over.
A temporary transport interruption is not automatically a logical call end;
the precise failure/end trigger remains unspecified. No rule here ends a
multiparty call merely because any one participant disconnects.

Admission uses a short database claim, never a transaction spanning OTP/provider
startup. If the original room/leg still exists, identify that existing work and
finish its bookkeeping without starting another. If the actual call runtime
crashes or terminates, do not automatically restart the call, redial, or reconnect
the caller. An uncertain provider dial is recorded as failed/unknown as appropriate;
clean up known resources without a speculative second dial or remote rollback
promise. Recovery here means records about existing work, not repeating the call
or adding a general durable recovery/exactly-once framework.

The tenant/API-key CLI bootstrap, prepared-call creation, existing-record token
issuance, and token-authenticated browser session routes now implement this baseline.
General HTTP administration and the broader endpoint/scope matrix remain outside
this checkpoint.

Public projections exclude:

- provider credentials and authorization headers;
- secret-bearing callback or signed URLs;
- private adapter state and authenticated request objects;
- PIDs, references, functions, module names, and stack internals;
- unapproved provider-native payloads; and
- transcript, tool, or media data outside the actor's visibility scope.

Client tool-event visibility is a call-level policy declared in the call
definition or explicitly selected by the authorized backend/OTP host when
creating the call. A creation-time selection overrides the definition's value;
resolve and pin the effective policy with the call record/resolved plan before
joining. The gateway applies it to that call's authorized client connections.
The policy can hide tool events entirely, expose lifecycle metadata only, or
include arguments/results. When neither source specifies visibility, hide all
tool events. Both metadata and full payload visibility require explicit selection.
Per-tool overrides select one of the same detail levels and take precedence over
the call-wide default. Target each override by the participant definition key
plus its local key in that participant's `tools` map, not by a remote MCP operation
name alone. The same local tool name on two agents is two independent targets;
tools without an override inherit the call-wide default. Resolve each invocation's
target from its server-owned participant/tool binding, not client-supplied labels.
Pin these selections with the rest of the call policy. Use `tool_visibility`
for the call-wide `hidden`, `metadata`, or `full` default, and optional
`tool_visibility_overrides` for participant-key → local-tool-key → level:

```json
{
  "tool_visibility": "hidden",
  "tool_visibility_overrides": {
    "reception": {
      "lookup_order": "metadata",
      "create_booking": "full"
    }
  }
}
```

Omitting both means hidden with no overrides. An authorized creation-time
selection replaces this effective policy pair from the definition; omitting
the creation policy inherits the definition. This is not a deep-merge/patch API.
Within the selected pair, a binding override still wins over the default.

Calls created for the Console playground explicitly select full tool
visibility using effective `{"tool_visibility":"full"}` with no overrides.
An inherited restrictive binding override would still win, so the trusted sample
creation replaces the policy pair rather than changing only its default. This
is the same call policy available to other integrations, not
a frontend-specific exception or an additional debug-session grant. A frontend
flag, UI route, or rendering choice cannot change a prepared call's visibility;
filter events before sending them to the browser. Keep private execution payloads
separate from these projections. Visibility does not grant tool execution,
additional agent variable permissions, or access to another call. Existing
credential/header exclusions still apply even to full tool visibility.
The detailed failed-transfer restoration reason is also internal-only: full
visibility, including samples, cannot expose it through debug tool payloads.

Room-authoritative transfer history is a separate private archive projection. After current-source
authorization, the engine records `participant_transfer_started` and exactly one terminal
`participant_transfer_completed` or `participant_transfer_failed` fact with source participant and
activation, caller, invocation, and pinned destination identity. Failed facts use a closed internal
cause taxonomy; they are not RTVI events. The ordinary client/model tool lifecycle remains the
interoperability surface, and every failed `transfer` projection is generic even under full tool
visibility. This separation preserves operational evidence without granting a browser access to
internal preparation or restoration causes.

The gateway now implements this boundary for the trusted definition-driven call
path. Schema `20260910.01` validates the definition policy and resolves participant
definition keys to runtime participant IDs in the immutable call plan. Trusted
creation may replace the complete policy pair; the result is carried privately in
the one-time transport session and is absent from its public response. The RTVI
projection drops hidden events before transport, omits arguments/results at
metadata level, and includes them only at full level. Preset/ad-hoc room joins
without a pinned definition policy remain hidden. The Console development call
selects full visibility in trusted server configuration, not in browser input.

Tool-history storage is independent of client visibility. Always retain all
observed invocation data with the call: invocation and participant/tool identity,
metadata, timing/outcomes, arguments/request payloads, and responses/results/errors.
There is no tool-history enable switch, metadata-only storage mode, per-tool
payload selection, or arguments/results opt-in. Hidden client events do not
suppress storage; metadata/full client selections do not change what is saved.
The storage consumer receives its own engine-event projection, not the browser-
filtered stream. Integration credentials and authorization headers remain excluded
before persistence; this is not raw wire credential capture or a new general
redaction feature. Store observed outcomes only: an unknown timeout stays unknown,
without fabricating a remote response. Storing data does not grant client access.
R41 selects asynchronous storage subscribers for live-call facts, including tool
history. Storage failures do not fail/stop the room or undo accepted variables.

Always save permitted available transcripts, turn details, and observed usage/
model/cost information with the call, alongside the complete tool history and
locally accepted variable snapshots. R38 qualifies the earlier no-separate-storage-
toggle-per-category rule: transcript/audio retention is distinct from live sharing.
The approved room-wide booleans govern automatic persistence paths; do not disable
recognition merely because transcript storage is forbidden. This is not a new set
of usage/tool/variable storage toggles.
Preserve
typed-text provenance and provider-final speech facts, and distinguish generated
agent text from confirmed delivered/spoken text, including interruptions. Do not
start STT or any prohibited processing just to produce an archive; absent or
prohibited transcription yields no invented transcript. Missing usage or prices
remain unavailable, never fabricated or recorded as zero. Usage attribution and
observation settlement follow R44/R45 below. R46 retains provider-reported
estimate/final costs when available; otherwise price remains unknown alongside
observed usage and IDs, without a local pricing catalog. Archival guarantees
remain separate.

Store available call audio only when recording is integrated, explicitly enabled,
and permitted by the effective `record_audio` policy. Recording
remains a room capability subject to privacy policy and the `opening_audio`
media-input gate, not an automatically enabled archival feature or another
storage-toggle matrix. Available ordinary turn/tool/usage history follows R41's
asynchronous subscriber design below, superseding the synchronous-first checkpoint.
Credential/header exclusions and visibility/agent grants remain unchanged.

R41 keeps required setup/admission writes in PostgreSQL, creating the call record
whose ID anchors runtime events. Once admitted, live room activity does not depend
on synchronous PostgreSQL writes. Engine-owned room storage services/capabilities
supervise subscriber/writer lifecycles; persistence and object-store adapters stay
in their owning umbrella applications, not `RoomAuthority` or the live mixer.
`EctoStorage` asynchronously consumes permitted call-start/lifecycle, transcript,
turn, tool, usage/cost, and full variable-snapshot facts for PostgreSQL.
`S3Storage` subscribes to permitted recording audio streams and streams bytes to S3;
PostgreSQL holds history and artifact metadata/references, not duplicate audio bytes.
Existing call-details publication remains a separate post-call workflow.

The first implemented artifacts boundary lives in the independent `vxpipe_artifacts` application.
Its application tree owns a unique writer registry, an object-I/O task supervisor, and a dynamic
writer supervisor. Call-scoped writers are keyed by tenant, call, and artifact; they monitor their
recording source and may drain after that source exits. A small object-store port owns upload open,
bounded PCM-chunk writes, and manifest completion. These core artifact modules do not depend on the
call engine, Calls, Ecto, or Gateway.

The writer handoff reserves a fixed shared capacity before a non-suspending send, so an active slow
write plus queued chunks cannot grow an unbounded mailbox or push object latency into live media.
Overflow rejects the newest chunk and increments terminal incompleteness evidence. Closing the
handoff rejects later audio while already-accepted chunks drain. Object-store operations run in the
artifacts-owned task supervisor. This boundary does not yet enable recording or implement S3: the
engine-owned `RoomRecording` capability remains responsible for policy-filtered mixer subscriptions
and for constructing exact interval/chunk metadata before it calls an injected writer handoff.

The mixer now has a distinct internal recording-subscription path guarded by a fresh room-local
reference shared only with its sibling recording capability. A recorder is therefore not modeled
as a fake participant and cannot acquire participant output privileges. Recording subscriptions
select either the full main-room mix or one participant track. They ignore recipient route maps,
because `record_audio` independently governs storage, but receive no frames while that effective
permission is false. Private preparation media remains outside the main mixer and therefore outside
these taps. Policy installation clears mixer input and subscription queues before acknowledgement;
denied or formerly queued intervals cannot arrive after the barrier or be replayed when permission
later returns.

`RoomRecording` is a temporary room-scoped coordinator, not an object-store client. Its first
checkpoint reads the mixer's established PCM format, opens the configured full-mix subscription,
and assigns it a stable identity under the pinned tenant, call, room, and incarnation. A bounded
availability notification causes it to pull at most the configured number of mixer frames and
project them into typed chunks containing the room-clock offset, per-stream sequence, sample count,
policy revision, contributing participant IDs, and PCM payload. The writer port's `open` and
`offer` callbacks are explicitly non-blocking: implementations may start supervised workers and
allocate bounded handoffs there, but network, disk, and database work belongs beyond that handoff.

Rejected writer offers increment room-local recording evidence and do not fail or block the mixer.
Sequences advance for every pulled interval, including a rejected one, while room-clock offsets
make policy-denied or capacity-lost gaps independently observable. If the mixer disappears, the
temporary recording source exits; an independently supervised artifact writer can detect that
source termination, drain already accepted chunks, and finalize honestly. The call engine owns
these live-media semantics without depending on `vxpipe_artifacts` or any concrete storage adapter.

The outer artifacts application supplies `Vxpipe.Artifacts.RecordingWriter` as an implementation of
the engine-owned writer port. This one-way, compile-time-only dependency lets the adapter translate
an engine stream into an artifact specification, start the artifact-owned supervised writer, and
return its bounded handoff. Starting the artifacts application does not start the engine
supervision tree. The adapter creates an opaque artifact ID and an object key from encoded tenant,
call, and incarnation segments; raw identifiers cannot introduce object-key path segments. PCM
chunks carry channel count as well as per-channel sample count, so offsets, durations, and manifest
gaps retain the shared room-clock meaning for mono and multichannel audio. This adapter still does
not choose or implement an object store.

`Vxpipe.Artifacts.S3ObjectStore` is the first concrete object-store implementation. It uses ExAws
for S3 operation construction, signing, credential providers, endpoints, and response parsing, with
ExAws's Req HTTP adapter; Vxpipe does not implement those protocols. The store initiates one
multipart upload per artifact and retains incoming PCM as reversed iodata until it reaches the
configured part size, whose minimum is S3's five MiB rule. Full parts upload sequentially in the
existing artifact task boundary. Completion uploads one permitted final short part and then closes
the multipart upload with ordered ETags. A terminal part/completion error makes a best-effort abort
and reports failure to the artifact writer. The in-memory upload buffer is bounded to one part plus
one already-bounded mixer chunk, and no temporary file or transcoding process is involved.

S3 bucket, endpoint, region, credential-provider overrides, encryption headers, and request options
are trusted application/tenant configuration supplied to the adapter, never call-definition or
client payload data. The adapter state excludes those client options and buffered PCM from
inspection. A completed object remains raw signed little-endian 16-bit PCM described by its
artifact manifest; authenticated playback packaging belongs to the later operator boundary.

Recording is disabled unless trusted call-start options set `recording: [enabled: true, ...]` and
provide a writer implementation, bounded pull size, and targets. Gateway call admission preserves
that host configuration for both web and telephony starts. The room-incarnation supervisor creates
a fresh reference for each enabled recording and supplies it only to that room's mixer and recorder.
It starts `RoomRecording` after `RoomAuthority`, so the authority has already registered the mixer
with the initial media-policy snapshot before the recorder requests its tap. The recorder remains a
temporary sibling: its startup failure prevents an enabled recording call from pretending to have
recording, while a later recorder or storage failure does not terminate the significant room
authority. Disabled calls create neither a recording token nor a recorder.

That failure isolation has two explicit drain paths. If the temporary `RoomRecording` coordinator
terminates after opening streams, the independently supervised artifact writers observe their
source monitor, close admission, drain already accepted chunks, and finalize with the coordinator's
exit reason. If an object-store operation task crashes, its artifact writer counts the in-flight
chunk as failed, continues with later accepted chunks, and publishes an incomplete manifest with
the resulting aligned gap after its source ends. Neither event restarts or terminates the live room.
An outage that also prevents object completion or metadata publication still cannot promise durable
terminal evidence.

Normalized room audio retains its authenticated `connection_id` as well as participant and track
identity. Mixer timestamp buckets and monotonic source sequences are keyed by that complete triple,
so simultaneous connections or tracks owned by one participant do not overwrite or reject one
another. Live participant routing still evaluates the participant identity, while the full mix
reports unique contributing participant IDs. This source identity is the prerequisite for opening
separate recording artifacts whose manifests can name the exact participant, connection, and track.

Trusted recording targets may request the full mix, all individual tracks, or individual tracks for
specific participant definition keys. Room startup resolves those stable definition keys against
the pinned plan; no caller supplies runtime participant IDs. The mixer uses one authorized wildcard
recording subscription to emit a separate unmixed frame for every selected qualified source. The
recorder opens each individual writer lazily on its first frame, because connection and track IDs do
not exist at room creation, and keeps an independent sequence per artifact. Its stream contract and
the artifacts adapter preserve all three source identifiers; full-mix and individual objects remain
different artifact kinds under the same room clock.

Terminal artifact metadata has a separate asynchronous lifecycle from both room recording and
object upload. After an artifact writer completes or exhausts its upload path, it hands the exact
manifest plus any stored-object reference to an artifacts-owned metadata publisher. The publisher
runs the configured metadata adapter in its own bounded-time task, may retry only up to its trusted
attempt limit, and can outlive the artifact writer. A bounded dynamic-supervisor ceiling prevents a
database outage from accumulating unlimited publisher processes. Exhaustion, invalid adapter
responses, and publisher-capacity failures are reported as unavailable/discarded evidence; they do
not revise the artifact manifest or stop a call. The artifacts application defines this port but
does not depend on Calls or Ecto. A later adapter checkpoint projects the result into PostgreSQL.

Calls owns a distinct `ArtifactRepository` port and tenant/scopes-authorized artifact workflows;
artifact metadata is not folded into transcript/tool fact storage. Persistence supplies the Ecto
adapter and one `call_artifacts` row per terminal artifact. The row stores the complete/incomplete
manifest, aligned gap intervals, exact source identity, and a minimal object reference containing
only the object key and optional ETag. Provider-returned locations are not persisted or exposed as
playback authorization. Duplicate identical publication is idempotent, while conflicting reuse of
an artifact ID and a wrong call incarnation fail. Incomplete metadata may survive without an object
reference, which reports an attempted/failed artifact rather than inventing playable audio.
Calls also exposes an exact artifact lookup keyed by authenticated tenant, call public ID, and
artifact public ID. Persistence binds all three in its query; browser paths never select an object
by accepting a storage key or provider-returned location from the client.

The repository development host composes those existing ports in `vxpipe_console`; it does not add
S3 or Ecto knowledge to Call Engine or Gateway. Recording is off by default. When the trusted
runtime switch is enabled, Console requires its configured persistence application and S3 bucket,
then injects `Vxpipe.Artifacts.RecordingWriter` with `S3ObjectStore` and the asynchronous
`Vxpipe.Persistence.EctoStorage` metadata adapter into Gateway call admission. The default targets
are the live full mix and all individual tracks that remain permitted by the room's effective media
policy. A bounded pull handles at most 16 mixer frames at once, and the writer accepts at most 100
pending chunks—about two seconds at the repository's 20 ms room frame—before rejecting later chunks
and reporting incomplete evidence. Writer drain is independently bounded at 30 seconds.

Direct agent output remains a connection egress path rather than being replayed through the
participant mixer. For an enabled recording, Room Authority binds an engine-owned recording handoff
to that direct output before connection startup can generate speech. WebRTC retains original PCM
beside each queued encoded packet and offers it only after the peer connection accepts the RTP
packet. The shared telephony output offers the PCM only when its provider-specific Membrane pipeline
acknowledges the in-flight socket send. Generated, encoded, queued, interrupted, or transport-failed
audio is therefore absent. This boundary proves egress acceptance, not remote playout or hearing.

That handoff has atomics-backed fixed capacity and never suspends live output. It shares the
mixer's room clock and an atomic projection of the effective recording policy, then sends accepted
frames to a separate mixer buffer used only by recording subscriptions. Full-mix recordings combine
those frames with concurrent room inputs, and selected agent tracks retain the source participant,
destination connection, and stable direct-egress track identity. Ordinary participant/monitor
subscriptions never receive the recording-only input, avoiding duplicate live audio. Policy
revision validation is repeated at mixer admission, so a transition race fails closed and denied
audio cannot be replayed after relaxation. Private transfer-preparation output never receives the
main-room handoff.

Development runtime settings use `VXPIPE_RECORDING_ENABLED`, `VXPIPE_RECORDING_S3_BUCKET`, and
optional `VXPIPE_RECORDING_S3_REGION` / `VXPIPE_RECORDING_S3_ENDPOINT`. The endpoint parser accepts
only root HTTP(S) origins and forces S3 path-style requests for compatible local stores. Credentials
remain in ExAws's standard provider chain; Console does not copy them into a call definition,
prepared-call record, client response, or inspectable recording state. An embedding host can supply
the same engine recording options directly without including Console.

The artifacts application keeps real object-store interoperability in an opt-in `:integration` /
`:s3_live` lane. It requires an explicitly authorized endpoint and bucket, obtains credentials only
from ExAws's standard environment/provider chain, performs a real multipart upload, reads the
finished raw PCM object byte-for-byte, and deletes that unique test object. The default suite makes
no network request and never prints credential values or signed requests.

Playback reads use a separate artifacts-owned S3 read port rather than extending the upload
session or letting Console issue provider operations. Every request is an inclusive byte range of
at most one MiB. The persisted ETag, when present, becomes an `If-Match` condition, and a short or
otherwise malformed response fails instead of fabricating missing audio. ExAws still owns
credential discovery, request signing, endpoint configuration, and S3 response handling. Higher
layers may stream a recording through repeated bounded reads without loading the object into a
room process or a single application buffer.

Console projects the stored signed-16 PCM into a virtual RIFF/WAVE file for ordinary browser
playback; it performs no transcoding and starts no external media process. The 44-byte header is
generated from the artifact format. Manifest gaps become zero-valued PCM intervals in the virtual
data so a damaged recording retains its known timeline instead of silently compressing time.
Individual tracks begin at their recorded start offset, which remains visible as alignment
metadata. A single-range HTTP parser supports complete, bounded, open-ended, and suffix reads;
multiple or unsatisfiable ranges fail closed. Both header and silence are generated in bounded
chunks, while recorded bytes continue through the artifacts-owned range port.

The Console playback route remains behind the signed, calls-scoped operator session. Its public
path carries only a call public ID and artifact public ID. A Console backend resolves that pair
through the exact tenant-authorized Calls operation, binds the resulting private object reference
to host-owned object-storage settings, and constructs the virtual WAVE source. Bucket, object key,
ETag, endpoint, credentials, and provider-returned locations are never accepted from the browser or
returned as playback authorization. Capture enablement controls new recording production; it does
not prevent an authorized operator from reading an existing artifact when trusted playback storage
settings remain configured.

The response layer advertises single byte ranges and streams with a declared length through
repeated reads capped at one MiB; it never buffers the whole recording. Satisfiable ranges receive
the exact virtual-file interval, malformed or multiple ranges receive `416`, and an object failure
before response streaming begins receives a generic storage error. Cross-tenant and nonexistent
call/artifact lookups share a generic not-found response. Responses are private and non-cacheable,
and ordinary room, mixer, monitor, and call-control processes are absent from this playback path.

Call inspection obtains recording rows through a separate list operation on the same
tenant-authorized Calls boundary. Console projects each artifact into a safe summary containing
only its public identity, source identity, format, room-clock alignment, terminal state, and gap /
rejection evidence. Object keys, object references, endpoints, credentials, and provider locations
do not enter the LiveView assigns or rendered markup. Summary construction may validate that a
virtual WAVE layout and trusted reader binding can be built, but it performs no object read.

The operator workbench renders the full mix before connection-qualified participant tracks and
keeps each native audio control on the private call/artifact route. An incomplete artifact remains
visible with its known duration, start offset, gaps, rejected chunks, and terminal reason; it is
playable only when the stored manifest and trusted playback configuration form a valid source.
Empty recording history and temporary recording-repository failure are distinct, bounded states.
This presentation is owned by a dedicated recording component rather than adding storage or media
logic to the general call-detail component.

The final recording acceptance composition holds an artifact object-write task while the room
mixer continues serving an ordinary monitor. A denied recording interval and a later bounded-queue
rejection stay audible to that permitted live monitor but absent from the stored PCM. When storage
resumes, later accepted audio keeps its original room-clock offset; the terminal manifest exposes
separate gaps for policy omission and capacity loss. This validates the intended dependency
direction in operation: the live mixer offers bounded evidence outward, while object latency and
failure cannot synchronously enter participant or monitor delivery.

The first archive implementation checkpoint establishes the database side of exact Call
Variables history without putting it on the live path yet. Calls owns an
`ArchiveRepository` port, immutable baseline/update snapshot contract, and tenant-scoped
calls-authorized read workflow. Persistence stores each full snapshot and conditionally
advances `calls.latest_variables_snapshot_id` in one transaction. An identical delivery is
idempotent; a different snapshot claiming the same call/incarnation/global revision fails;
older valid history and a late revision-zero baseline persist without moving the pointer
backward. Call, room, and established incarnation checks prevent cross-call linkage. That
database checkpoint deliberately leaves room processes unwired; the following checkpoint
adds the bounded source handoff, while the broader event archive remains subsequent work.

The second archive checkpoint supplies that live boundary for Call Variables. An
engine-owned global archive supervisor starts one temporary subscriber for each durable room;
the subscriber is not a child of the room incarnation, monitors that incarnation, and may
drain after it exits. Producers reserve capacity through shared atomics and use a non-suspending
message offer. Capacity includes the active writer plus queued facts. At capacity, the newest
fact is rejected at the source and the local variable update remains accepted; no unbounded
subscriber mailbox is used. A writer task performs injected adapter work sequentially outside
the room and retries a retained fact without reserving it twice.

The initial database-backed admission configuration uses 256 pending facts, a 250 ms retry
delay, and a five-second post-room drain window. Expiry terminates the outstanding writer,
abandons retained facts, and increments discard/incomplete evidence. Overflow, unavailable
offers, retries, pending work, and terminal/expiry discards remain distinct counters. A crashed
subscriber is temporary and is not silently restarted behind an already-issued handoff; later
offers report unavailable.

`CallVariables` emits an exact revision-zero baseline before it handles commands, with stable
call/room/incarnation identity and no invented participant, turn, or tool attribution. Each
accepted update similarly hands off the exact post-update snapshot with its originating
command/participant/activation/correlation/tool IDs. `EctoStorage` maps those engine facts to
the Calls-owned archive workflow. Runtime archival is enabled only for the durable,
database-backed admission path; the legacy trusted room sample does not create archive work
for a call record that does not exist.

The private-fact checkpoint reuses that handoff for protocol-neutral room,
participant, connection, turn, final-transcription, generated/delivered/interrupted
output, and tool facts. `RoomAuthority` remains one serializer but delegates
participant, connection, input, output, tool, turn and archive behavior to cohesive
modules. It does not construct Ecto schemas or persistence envelopes.

Calls owns the immutable private-fact contract and authorized history projection;
persistence owns the append-only `call_facts` schema, ordered/idempotent queries and
transactions. Calls exposes the underlying ordered ledger, a permitted transcript,
complete observed tool history, and exact variable snapshots/latest state as separate
views. The delayed Calls sink repeats credential filtering and source-policy enforcement
after JSON canonicalization.

Once every retained ordinary item drains, the subscriber attempts an
`archive_stream_closed` fact with source-exit and overflow/unavailable/discard/retry
evidence. A terminal loss-free marker plus a contiguous private sequence reports
`complete`; a marker with known loss or gaps reports `incomplete`; no durable marker
reports `unconfirmed`. The marker remains subject to the same finite drain deadline,
so a database failure cannot become a false completion claim. Diagnostic missing-
sequence samples are bounded while the total missing count remains exact.

Subscribers may persist directly or publish to a future queue, such as SQS;
no queue dependency is selected. Database/storage failures must not themselves
fail/stop the room, undo accepted variables, or backpressure media/`RoomAuthority`.
All handoffs and buffers must be bounded and report loss/incompleteness honestly.
An in-memory handoff is not durable: process/host failure before durable storage
can lose history or accepted variables. Retries/queues only help for facts still
retained; no unbounded mailbox, durable spool, exact overflow policy, or exactly-once/
no-loss guarantee is added. Post-call draining/finalization can outlive the room.

Enforce R38 at the source/subscription boundary and again at storage sinks, retaining
source-interval permission/provenance for delayed writes. Never enqueue forbidden
audio/transcript payloads first and filter them later; logs, exports, and storage
buffers cannot retain them. Live transcript routes remain independent from
`save_transcripts`. Permission applies to the source interval, not just policy at
write time. Every copy still follows retention and cannot recreate purged data.

Oban and SQS are possible later choices, not selected dependencies. Oban stores
jobs in its configured SQL database; with PostgreSQL backing, enqueueing still
needs PostgreSQL. Deferring a job does not remove that outage dependency.
[Oban documentation](https://oban.hexdocs.pm/Oban.html).

Post-incident S3-to-PostgreSQL import and PostgreSQL-to-S3 export repair are
deferred operational work, not an automatic reconciliation/recovery API or full
database-backup guarantee. Only surviving persisted data is recoverable. An S3
audio subscriber is not an independent in-call JSON/history copy; a final export
dependent on PostgreSQL cannot recover facts that never reached it, and metadata
cannot recreate missing audio. Neither repair nor publication may reconstruct
prohibited or purged data. No Ecto, Oban, SQS, or storage implementation is added
by this decision.

Usage belongs to the call, with participant/activation/service-interval links
when known and a turn link only when attribution is honest. Participant attribution
does not require a turn: STT/TTS may span several service-active intervals and
turns for one participant. Preserve observed service starts/stops rather than
assuming one continuous membership interval or inventing billable duration. LLM
requests can link to their agent/turn; a TTS turn link depends on provider evidence.
Shared/unattributable work remains call-scoped, without equal allocation across
turns. One canonical billable fact may carry these references; they do not create
separate call, participant, and turn charges.

Keep tokens, duration, characters, and other provider units separately from price.
Usage can be known while monetary cost is unavailable. Preserve actual provider
request/operation/session IDs when supplied, namespaced by provider, configured
integration, and tenant. A missing provider ID stays absent; local correlation
is not a provider request ID.

R46's initial pricing policy uses available provider-reported estimate/final cost,
otherwise unknown price plus observed usage and IDs; no local pricing catalog or
invented fallback rate. For TTS, retain input-text character count and
generated-audio duration when observed. For STT, retain audio duration and
recognized-text character count when observed and permitted. Preserve exact units and provenance;
measured character counts are not automatically provider-billable characters.
Do not sum repeated interim/cumulative recognition text as new usage. Providers
need not supply every ID or measurement; absent evidence stays absent. Character
counts do not require retaining forbidden transcript text or starting prohibited
STT, and source-interval privacy still applies. A precise character-counting
standard or new configuration surface is not selected by this decision.

Retain usage observations and derive one effective amount per provider-operation
attempt/component. Distinguish incremental deltas from cumulative totals separately
from estimate/final/correction status. Deltas 100 + 60 mean 160; cumulative reports
100 then 160 mean 160, not 260. Cumulative 1000, 1600, then final 1700 mean 1700,
not 4300. Final evidence supersedes estimates, and a stale estimate cannot override
a known final. Explicit corrections may lower or raise the amount; neither arrival
order nor `max()` decides settlement. Finality does not turn a delta into a total.
Deduplicate only when observation/sequence/delivery identity proves repetition;
equal numeric values alone are not duplicates. Keep distinct units, currencies,
components, and provenance, count each effective operation attempt once, and avoid
adding a total to its included subcategories. Do not coalesce separate billable
attempts. Failed/interrupted work still contributes observed usage; missing usage
is unknown, not zero. This does not authorize automatic MCP retries.

The implemented neutral contract is owned by Call Engine under `Usage`, before any provider or
storage adapter. An immutable observation identifies its tenant, call, local operation attempt,
capability, provider namespace, outcome, time, and one measured component. Attribution is a
separate optional value containing only dimensions backed by evidence: room incarnation,
participant activation, service interval, telephony leg, turn, utterance, or tool call. Provider
context keeps provider/configured-integration selectors and genuine model, voice, request,
operation, or session identifiers; the external identifiers are available explicitly but omitted
from ordinary struct inspection.

Canonical scalar units are tokens, characters, milliseconds, and requests. Monetary measurements
pair an uppercase three-letter currency with a non-negative exact `Decimal`; floating-point money
is invalid. Measurement provenance is one of provider-reported, locally measured, library
estimate, or billing lookup. Settlement retains provenance-specific effective amounts and refuses
to produce an unqualified total spanning multiple provenances, preventing a reported price and an
estimate from being silently added together. Equal quantities remain distinct. Replay suppression
requires matching immutable semantics plus a shared observation ID, delivery ID, or source
sequence; contradictory reuse of one of those identities is an error. Cumulative reports without
enough explicit source sequencing to choose between otherwise-equivalent-status reports are
ambiguous rather than settled by arrival order.

The first runtime capture path translates each completed model round into this neutral contract.
The agent-runtime coordinator keeps a bounded request/round tracker until the runtime's terminal
event, independently of whether its task result has already advanced the conversation. This
prevents cross-sender mailbox ordering from dropping a late usage event. Each tool-intermediate and
final round receives a distinct local attempt ID; that ID is never presented as a provider ID.
The translation currently accepts only non-negative integer input, output, and total token fields.
Input/output are declared as included components only when a reported total exists. Arbitrary usage
and provider metadata are discarded, and cost fields whose reported-versus-catalog provenance is
not established are deliberately left unknown.

Model usage is handed only to the owning `RoomAuthority`, which authenticates the current or
committed-transfer teardown capability against its pinned participant activation and call
incarnation. It projects each accepted observation as a private `usage_observed` archive/live-
inspection fact through the existing bounded asynchronous port; no client protocol event is
created. Genuine response/request/session IDs remain in that private fact. An operation may carry
provider identity with no measurement, so lack of token or price evidence does not erase the
operation and is not rewritten as zero.

Agent Runtime emits `model_attempt_started` only after pending invocation/context lookup succeeds
and immediately before calling the provider. It emits `model_usage` for every valid completed
provider response, including an empty usage/metadata pair. The Call Engine round tracker therefore
creates an attempt ID only for work that reached the provider boundary, closes it on the matching
usage event, and records a measurement-free `failed` or `cancelled` observation if the runtime ends
while that attempt is still open. Setup failures before provider invocation create no provider
attempt. Each restarted request gets fresh attempt IDs, even if it reuses a command/correlation.
Usage already handed off remains independent of stale text suppression, and cancelling an in-flight
provider request retains the operation with unknown measurements rather than pretending its cost
was zero. If a streaming provider returns a valid final response after a local text/event budget has
already rejected its output, Agent Runtime hands off the response's usage before returning the local
failure; rejected conversational output therefore cannot erase known incurred usage. Hosted speech,
tool, and carrier capture were not part of that model checkpoint.

The second runtime capture path covers definition-selected text-to-speech attempts. The resolved
runtime pins the call, participant activation, configured profile, and provider-owned safe identity;
credentials remain in the existing provider/transport configuration. An attempt begins only after
the transport accepts `Speak`. Text that remains queued, or a `Speak` command rejected locally,
therefore creates no observation. If `Speak` is accepted and `Flush` fails, the accepted input is
retained as a failed attempt without an invented provider identifier or audio duration.

Each attempt records the input's Unicode grapheme count as locally measured characters. It counts
decoded PCM emitted by the provider, including audio discarded after an interruption, and converts
complete PCM frames to milliseconds with `Membrane.RawAudio`; playout progress is not substituted
for generated duration. Provider request and speech identifiers cross only from validated provider
signals and remain distinct from the local `tatt_` attempt identity. Provider completion records
`succeeded` before downstream playout drains, an acknowledged interruption records `cancelled`, and
provider/transport failure records `failed`. Output rejection after provider completion cannot
rewrite or duplicate already-incurred synthesis usage.

The TTS GenServer delegates tracking/projection to focused attempt and adapter modules. Its owning
`RoomAuthority` accepts observations only from the exact active synthesis capability or the exact
prepared private-briefing capability, matching the pinned participant and optional activation. The
same private asynchronous archive path used for model observations stores the facts; no client
event or raw synthesis text is added. Definition-selected hosted and deterministic tone providers
publish a safe provider identity. The legacy room command path lacks a pinned call/profile identity
and remains unobserved rather than fabricating one.

The third runtime capture path covers definition-selected speech-to-text sessions. The resolved
runtime pins call, participant/optional activation, configured profile, and a safe provider/model
identity without copying credentials. Each concrete provider transport receives a fresh local
`satt_` attempt and `sint_` service-interval identity. A transport-accepted audio submission or
normalized provider activity proves the attempt exists. A measurement-free `in_progress`
observation marks its first observed boundary; a provider connection event may be buffered until
later bound activity or termination so early connection setup cannot bypass room source authority.
Policy-driven transport replacement closes the old interval as `cancelled`, while provider or
transport failure closes it as `failed`. A new transport never reuses the prior attempt or interval.

Only a provider's final turn can emit speech measurements. The hosted Flux adapter validates its
final audio window and normalizes the window difference to the nearest integer millisecond. That
becomes a provider-reported `recognized_audio_duration` delta. A final transcript may also produce a
locally measured Unicode-grapheme `recognized_text_characters` delta, but only when the pinned media
policy permits transcript storage for that interval. Interim, eager, resumed, or repeated final
turn state never adds character or duration deltas. The tracker retains no transcript text; a
provider without final-window evidence leaves duration unknown. The local deterministic recognizer,
for example, can report final recognized characters but does not invent an audio duration.

STT lifecycle tracking and observation projection are separate modules from the capability
GenServer. The owning `RoomAuthority` accepts their facts only from the exact STT process currently
bound to a participant connection and rechecks tenant, call, room, incarnation, participant, and
optional activation. Observations include the service interval but omit a Vxpipe turn when the STT
boundary has no authoritative domain-turn identity. The facts use the same private archive/live-
inspection path as model and synthesis usage and add no client event, transcript payload, audio, or
fabricated provider identifier.

The fourth runtime capture path covers every tool invocation accepted by an agent activation's
supervised invocation registry. Acceptance occurs only after the worker has started and creates a
fresh local `tlatt_` attempt plus one final, locally measured `invocations` request delta. That
measurement counts an accepted Vxpipe tool invocation; it is not represented as a remote-provider
billable request. Reconciliation of the same invocation identity and fingerprint reuses the
existing work and emits no second start or measurement.

A separate terminal observation records succeeded, failed, or unknown according to the actual
worker outcome. The existing bounded timeout stays unknown and does not authorize a retry.
Conversational interruption does not cancel the independently supervised tool, so its later real
outcome remains observable even when stale conversational output is suppressed. Explicit tool
cancellation remains deferred and is not inferred from speech interruption or a client-facing
cancelled-output event.

Tool provider context is deliberately narrow. Host actions use the `host_application` namespace;
engine-owned platform, transfer, and Call Variables actions use `vxpipe`; remote operations use
`remote_mcp` plus their pinned configured integration ID. The local tool-call ID remains an
attribution dimension and is never copied into a provider request/operation/session field. Because
the remote tool protocol defines no common billing envelope here, arbitrary result metadata is not
treated as usage or cost and missing provider identifiers remain absent.

The invocation registry delegates usage construction and publication to focused modules and keeps
only the optional attempt state attached to its ordinary invocation record. Arguments and results
remain in the existing private tool-history facts; neither is copied into usage observations or
ordinary struct inspection. `RoomAuthority` accepts the observations only from the exact active
agent capability or its committed-transfer teardown source, rechecks the call and activation, and
uses the same private asynchronous archive/live-inspection path without a client usage event.

The fifth runtime capture path covers incoming and outgoing carrier legs at Gateway's shared
provider-neutral telephony boundary. A locally generated telephony-leg ID is both the usage attempt
identity and the optional leg attribution; it is never presented as an external provider ID. After
request/service validation and media admission, and immediately before the adapter's answer or dial
call, Gateway records one final locally measured `carrier_legs` request delta. Earlier validation or
admission failure creates no carrier observation because no carrier operation was attempted.

An accepted submission or authenticated event adds the real provider leg ID as `operation_id` and
the real provider session ID when one exists. The first valid answered or media-started event marks
the connected boundary. A later valid ended event records `connection_duration` only when its time
does not precede the connected boundary. Two provider-envelope timestamps produce
provider-reported duration; a locally observed receipt/media time produces locally measured
duration. Event timestamp provenance is explicit: Telnyx webhook envelope time is
provider-reported, while Twilio's HTTP receipt clock is locally measured. A later provider answer
may improve an earlier local media-start boundary without creating a second connected observation.

Rejected answer/dial attempts retain failed terminal observations without invented duration or
provider identity. Local cancellation and an ambiguous submission retain cancelled/unknown terminal
state without claiming the carrier has ended, so no duration is derived from the local end-command
request. Duplicate lifecycle evidence changes neither boundaries nor totals. Binding validation runs
before accounting; a mismatched provider/service/leg event cannot connect or settle another leg.

`Vxpipe.Gateway.Telephony.LegUsage` coordinates lifecycle-to-usage state and delegates event-evidence
translation and failure-isolated reporting to separate modules. Call Engine separately owns attempt
state transitions and immutable observation projection. The reporter routes exact
tenant/call/room/incarnation/participant/leg facts to `RoomAuthority`, which revalidates that scope
and writes through the existing private asynchronous archive/live-inspection port. Both carrier
adapters use these same incoming/outgoing leg owners. No client usage event, synchronous SQL write,
price, or provider-billable-duration claim is introduced by this capture path.

The existing bounded `EctoStorage` subscriber now maintains a database projection of those private
usage facts without adding PostgreSQL to the room, media, model, or carrier hot paths. It first
archives the immutable `usage_observed` call fact, then strictly restores the typed observation and
stores it in `usage_observations`. The raw fact remains the authoritative timeline evidence; the
structured row is a rebuildable query projection and also permits a later billing observation to be
appended after room shutdown. Replayed observation IDs are idempotent only when every typed value
matches. Conflicting reuse is rejected rather than silently replacing history.

Within a call-locked transaction, `Vxpipe.Persistence.UsageStore` derives the current effective
amounts from all accepted observations and atomically replaces that call's `usage_amounts`
projection. Scalar and monetary quantities use exact PostgreSQL numeric storage; typed decoding
restores integer scalar units and `Decimal` currency values without floating-point conversion.
Amounts keep provider context, every evidence-backed attribution dimension, component, inclusion,
mode, status, provenance, and contributing observation IDs. Included child components may arrive
before their aggregate: they remain inspectable and excluded from totals until the aggregate
arrives, rather than causing the asynchronous subscriber to discard or indefinitely retry a valid
partial stream.

Calls owns the `UsageRepository` port and the `fetch_usage_report/3` workflow. Reads require a
tenant principal with `calls` scope, and the persistence query joins through that tenant before
returning any amount. The report derives non-overlapping root totals at the most-specific supported
provider, participant, activation, service-interval, leg, turn, utterance, tool, unit/currency, and
provenance dimensions. Genuine provider request, operation, and session IDs remain available on
the private individual amounts but do not fragment configured-provider totals. Operator
presentation consumes this public Calls workflow; Console does not query the Repo directly.

The existing Console call-detail workbench reads the usage report independently from persisted
history, live inspection, and recording artifacts. A usage-store failure therefore renders a
generic usage-unavailable state while preserving the other evidence. The compact ledger exposes
non-overlapping totals first and keeps individual effective operations in an explicit disclosure,
including genuine external references when present. Empty, incomplete-aggregate, and unavailable
states are distinct. Wide evidence tables scroll within named keyboard-focusable regions at narrow
viewports rather than widening the page. This remains an operator-only projection under the
existing signed `calls`-scoped session; no ordinary caller/client usage event or route is added.

A provider integration may optionally resolve delayed billing from persisted provider IDs through
the Calls-owned `BillingLookup` port. `Calls.enrich_usage_billing/3` requires a tenant principal
with `calls` scope, reads that tenant's immutable observations through `UsageRepository`, and
coalesces multiple components from the same local provider attempt into one candidate. An attempt
without a genuine request, operation, or session ID is counted as missing evidence. Conflicting
external IDs make only that candidate unavailable; they are not guessed or sent to a provider.

The configured port is a tenant-aware dispatcher. Its context owns application/tenant integration
resolution and credentials; its request contains only tenant/call scope, configured provider
identity, evidence-backed attribution, outcome, and genuine external IDs. It contains no
transcript, media, tool argument, or tool result. Calls invokes candidates through a bounded
`Task.async_stream/3` pass (default concurrency four and five-second per-lookup timeout), entirely
outside the media hot path and `RoomAuthority`. A missing port/provider implementation is reported
as unsupported, not-yet-settled provider data as pending, and transport, credential, timeout, crash,
or invalid-result cases as unavailable. One bad provider result does not become a zero cost.

A successful adapter result supplies a stable provider delivery/revision identity, source sequence
when one exists, source timestamp, exact non-negative amount, currency, component, and settlement
status. Calls turns it into an immutable cumulative observation with `billing_lookup` provenance,
the original attempt/provider/attribution/outcome, and a deterministic local observation ID. This
makes exact repeated retrieval idempotent while a conflicting reuse of provider delivery evidence
still fails settlement. The adapter must explicitly normalize provider-specific sign conventions;
the common measurement never accepts a negative charge.

The existing `UsageStore` call-locked transaction remains the acknowledgement boundary. A fetched
amount is not reported as stored until the observation and rebuilt projection commit. The workflow
can be started by a later background subscriber/job and can finish after room and call end; it does
not alter `ended_at` or retention. Its tenant-joined fetch and ordinary usage-store insert both fail
for a purged call, so enrichment cannot recreate it. Actual network adapters remain optional and
must be added only with provider-specific API evidence and tests. R46's initial pricing policy and
R41's asynchronous storage contract are resolved. Locally accepted variable snapshots and all
existing media/privacy and whole-call retention boundaries still apply.

Post-call finalization runs outside the call room with a configurable 60-second
waiting window from call end. Publish earlier when all expected work is settled;
otherwise, at the deadline publish the available permitted data with explicit
pending, failed, or missing components. Unknown cost is not zero. Media deliberately
prohibited, unconfigured, or not produced is not accidental loss or incomplete
capture; distinguish it from expected work that has not succeeded.

This is a reporting wait, not an extension of the call or a deadline that cancels
uploads, provider work, or permitted asynchronous billing lookup. Background work
may outlive the room; `ended_at` and retention do not change. A database/object-store
outage may prevent publication: retain/retry appropriate publication state without
falsely marking it published or complete. R41 requires bounded, honest asynchronous
storage without a lossless guarantee; the reporting deadline adds no such guarantee.

Later facts can trigger refreshed publication or a new revision. R42 uses an
immutable publication revision record with its own identity and persisted UTC
timestamp. Under the call-owned object prefix, format its filename as
`details-YYYYMMDDHHMMSSmmm.json`, including three millisecond digits: a record
timestamp of `2026-09-08T12:34:56.789Z` gives `details-20260908123456789.json`.
This is the publication record's timestamp, not call `created_at` or retry time.
Retrying that same snapshot reuses its persisted identity, contents, and filename;
changed contents require a new publication record/timestamp and object, not an
overwrite. Value changes alone do not change `schema_version`.

Maintain a latest-publication pointer without replacing earlier revision objects.
Millisecond timestamps do not prove uniqueness or globally monotonic ordering:
creation must detect/handle filename collisions within the call-owned prefix so
distinct publications cannot clobber each other. Keep internal revision identity/
correlation; timestamp alone is not a deduplication key. The collision-handling
mechanism is an implementation detail, not permission to invent a record timestamp.
All publication revisions are call-owned and deleted with the call. Known call-owned
jobs and references must respect retention deletion and source-interval privacy:
late work cannot recreate purged data or capture/copy a denied interval. These
R42/R43 decisions add no runtime implementation or new configuration key/hierarchy.

For every locally accepted variable update, `CallVariables` emits its exact full
post-update snapshot with call/incarnation, original turn/tool, source participant,
revisions, and local acceptance timestamp. Do not read a later live state and
mislabel it as an earlier update. Reuse tool history and its arguments, without a
separate changeset. Validation failures still reject without local mutation.
Tool success means local acceptance and asynchronous archival handoff, not a
PostgreSQL commit; reads immediately use the new in-memory values/revisions.

`EctoStorage` projects snapshots asynchronously. Its PostgreSQL transaction inserts
the history snapshot and conditionally advances `calls.latest_variables_snapshot_id`
atomically. Deduplicate deliveries and handle out-of-order revisions/incarnations
so the pointer never regresses or references another call. An older valid history
snapshot may be archived without becoming latest. A transaction failure rolls back
that storage attempt, not the already accepted live update; it cannot turn prior
tool success into failure. No synchronous commit-status lookup is needed.
An indexed lookup/simple join retrieves the latest persisted snapshot, which may
lag the in-memory owner. Full snapshots stay private, not client events or broader
agent tool results. Storage failure/loss is reported honestly without blocking
the live call, and accepted-but-unpersisted values may be lost with the process/host.
Retained initial values form a baseline snapshot with no invented turn/tool call,
so the pointer also works before the first update.
These are approved designs, not newly implemented persistence. This explicitly
supersedes database-commit-before-variable-success and synchronous-first history.
Admission still requires its configured database writes; asynchronous runtime
archival is not removal of that dependency or a durable database-free fallback.
General sensitive-input redaction remains deferred; R47–R50's approved profile,
model-context, and provider-native fallback contracts are above.

General redaction of sensitive spoken audio or input passing through STT/the LLM
is deferred, not a prerequisite for this slice. A deterministic collection path
such as DTMF can collect account numbers without asking an LLM to interpret the
digits. Its input integration and raw-digit routing still need their own design;
DTMF alone does not guarantee exclusion from recordings, logs, or tool payloads.
Do not claim automatic masking of spoken or model-visible sensitive input.
Existing credential/header exclusions, permissions, and client visibility remain
mandatory; hiding a tool event is not transcript or audio redaction.

Stored call-data retention periods are application configuration with tenant
overrides. The application default is retain forever. An explicit tenant setting
wins; otherwise inherit the application setting, including its forever default.
The setting is `call_retention`: use the JSON string `"forever"` or a finite
duration object such as `{"seconds":2592000}` (30 days). Omitted application
configuration defaults to `"forever"`; omitted tenant configuration inherits it,
while explicit tenant `"forever"` overrides a finite application period. This is
not a call-definition, creation, or participant option. No human-readable duration
parser, null sentinel, or per-call policy copy is introduced.
Forever means no age-based expiration by Vxpipe, not permission to start STT or
recording, retain excluded credentials, or claim a backup/recovery guarantee.
Capability permissions, credential exclusions, and client visibility remain
separate from storage duration. Periods are not agent-defined
or client-selected. For a completed call with finite retention, the expiry
threshold is `ended_at + retention_period`, not record creation or a later storage
write. Do not expire retained data while the call is active. Retain forever has
no expiry threshold; an unset `ended_at` must not fall back to `created_at`.
Use the current application/tenant period for all calls, past and future. Resolve
the current tenant override or application fallback when evaluating expiry; do
not pin a retention period, policy version, or fixed expiry on each call. A
shorter period can make older completed calls immediately eligible for cleanup.
A longer period or forever changes eligibility for data still present, but cannot
restore deleted data. Application changes do not override an explicit tenant
setting.

Retention expiry deletes the entire call and all Vxpipe-managed data belonging
to it: the call record, transcript, events, tool history, variable snapshots
(including the latest), participant/leg records, usage/cost records, recordings,
and exported artifacts. This is not a soft delete or a payload-only purge that
keeps a call summary. Shared call definitions and application/tenant configuration
remain; call-specific copies and references do not. Database rows and stored
objects are both in scope, not one cross-store database transaction. Pending or
late archive/publication work must not recreate deleted call data.

Periodic background sweeps select eligible completed calls using the current
tenant/application setting and `ended_at`; crossing the threshold does not trigger
instant deletion or a per-call timer. The sweep interval/default remains deployment
configuration to choose, not an approved hourly frequency or exact deletion SLA.
Delete all managed call-owned external objects/copies first, then the call-owned
database data and call record. Definitive object-key-not-found counts as already
absent, but database cleanup waits until every relevant external object is absent.
An object-store timeout, permission/authentication error, or other unknown/failure
is not not-found: keep the database record and artifact references for a later sweep.

After a crash or partial failure, repeat deletion from those retained records;
already-missing objects succeed and database cleanup follows when all are absent.
A database failure also leaves work for a later sweep. No per-object progress
journal or permanent tombstone is required; successful cleanup leaves no call
record, summary, or snapshot. Cleanup and archive/publisher owners must coordinate
so late writes cannot recreate purged data; external-first ordering alone does
not solve that race, and no elaborate coordination mechanism is selected here.
These background cleanup retries are not MCP/tool executor retries.
Unstarted-record housekeeping remains separate; no job is implemented
by this documentation decision.

Silent live monitoring uses an authenticated monitor participant with explicit
scopes, topic grants, retention, and rate limits. It consumes projected events and
sampled media/metrics outside the room hot path. Debugging alone does not change
storage retention or remove bounded live-buffer limits.

Telemetry includes:

- speech start/stop and transcription delay;
- turn-commit and interruption delay;
- LLM time to first token;
- TTS time to first audio;
- transport playback delay and end-to-end response latency;
- tool and transfer lifecycles, and observed supported provider-native LLM fallback;
- remote MCP connection lifecycle plus discovery/invocation latency and outcomes;
- provider availability and error categories;
- tokens, characters, audio duration, and cost attribution;
- per-room mailbox and bounded-queue pressure; and
- scheduler, reductions, memory, and process restart information.

Every metric defines its unit, aggregation and observed source/model/provider.
Relevant room/turn/utterance correlation belongs in restricted event context or
per-call history, not unbounded metric labels. General metrics exclude conversational
payloads and credentials. RTVI metric messages are a compatibility projection and
are not the canonical telemetry schema.

The implemented framework-independent event contract currently includes:

| Event | Measurements | Bounded metadata | Boundary |
| --- | --- | --- | --- |
| `[:vxpipe, :gateway, :http, :request, :stop]` | `duration` in Erlang `:native` units | `operation`, `outcome`, and integer `status` or `nil` after an exception | Entire reusable gateway Plug call, including CORS and parsing; exceptions are emitted as `:exception` before being reraised |
| `[:vxpipe, :call_engine, :model, :first_token]` | `duration` in Erlang `:native` units | `provider` | Request dispatch to first non-empty model output observed by the agent coordinator; emitted once per request and absent when no output arrives |
| `[:vxpipe, :call_engine, :model, :request, :stop]` | `duration` in Erlang `:native` units | `provider`, `outcome`, and `first_output` | Request dispatch to terminal completion, cancellation, timeout, or failure; `first_output` is `:observed` or `:missing` |
| `[:vxpipe, :call_engine, :tts, :first_audio]` | `duration` in Erlang `:native` units | `provider` | TTS request dispatch to the first decoded provider audio frame, before output-sink acceptance or remote playout; emitted once and absent without audio |
| `[:vxpipe, :call_engine, :opening_audio, :stop]` | `count` equal to `1` and `duration` in Erlang `:native` units | `source` and `outcome` | Configured opening-audio attempt through correlated destination playout completion or terminal failure; emitted once and absent when opening audio is omitted |
| `[:vxpipe, :call_engine, :provider, :failure]` | `count` equal to `1` | `capability`, `provider`, and `category` | Safe failure projection at the owning model, STT, or TTS boundary; no raw provider reason or response is included |
| `[:vxpipe, :call_engine, :background_tool, :admission]` | `count` plus `reserved` and configured `limit` gauges observed at that admission | `outcome` | Engine submission boundary after validation and capacity checks; accepted work is counted only after worker startup |
| `[:vxpipe, :call_engine, :background_tool, :stop]` | `count` and local-worker `duration` in Erlang `:native` units | `outcome` | One terminal observation for a successful, failed, unknown-timeout, or activation-terminated local worker |
| `[:vxpipe, :call_engine, :background_tool, :handoff]` | `count` plus completion `depth` and configured `limit` gauges observed at that handoff | `outcome` | Bounded coordinator-mailbox queue, duplicate, overflow, or consumption boundary |
| `[:vxpipe, :call_engine, :runtime, :sample]` | `active_rooms`, `memory_bytes`, and `run_queue` as non-negative gauges | none | Periodic engine-owned sample outside room callbacks; active rooms come from the room DynamicSupervisor and VM values from the local BEAM |
| `[:vxpipe, :mcp, :connection, :stop]` | `count`, `duration` in Erlang `:native` units, and current `active_connections` | `operation`, `outcome`, and optional local client PID | Terminal standalone MCP client open/reuse/failure or close/absence observation; the PID permits same-VM restricted correlation without exposing integration identity |
| `[:vxpipe, :mcp, :request, :stop]` | `count` and `duration` in Erlang `:native` units | `operation`, `outcome`, and optional local client PID | Terminal complete-catalog discovery or prevalidated invocation boundary |

Gateway operations are closed categories (`:cors_preflight`, `:health_check`,
`:room_create`, `:session_create`, `:rtvi_offer`, `:rtvi_candidates`, or `:unknown`).
Outcomes are `:ok`, `:client_error`, `:server_error`, `:exception`, or `:unknown`.
The event does not carry the request path, query, headers, body, or correlation IDs.
Engine provider labels are normalized to the closed `:req_llm`, `:deepgram`,
`:local_fixture`, `:morse`, or `:other` set. Model outcomes are `:ok`, `:unavailable`, `:timeout`,
`:invalid_response`, or `:cancelled`; failure categories are `:unavailable`, `:timeout`,
`:invalid_response`, `:output_failure`, or `:unknown`. Background admission outcomes are
`:accepted`, `:saturated`, `:start_failed`, `:unavailable`, or `:invalid_tool`; worker outcomes
are `:ok`, `:failed`, `:unknown`, or `:terminated`; handoff outcomes are `:queued`,
`:duplicate`, `:overflow`, or `:consumed`. MCP connection operations are `:open` or `:close`;
their outcomes are `:opened`, `:reused`, `:failed`, `:closed`, or `:absent`. Opening-audio
sources are `:text` or `:file_url` and outcomes are `:completed` or `:failed`. MCP request
operations are `:discovery` or `:invocation`; their outcomes are bounded to `:ok`, `:failed`,
`:timeout`, `:rejected`, `:too_large`, `:not_submitted`, `:remote_error`, or `:unknown`.
Console diagnostics projects opening-audio stops into bounded source/outcome duration aggregates;
it does not retain call identity, configured text, asset URLs, or provider payloads.
None of these events carries input/output text, audio, raw provider errors, model names,
endpoint/tool identity, request arguments/results, credentials, tenant IDs, or integration
IDs. Only the MCP events may include an ephemeral local client PID; the Console removes it
before queueing or retaining an observation.
`active_rooms` is the current DynamicSupervisor child count rather than a lifecycle-event
estimate. The runtime sampler is an explicitly named call-engine child and its interval comes
from the call-engine application setting `telemetry: [sample_interval_ms: ...]`.

### Observability delivery

Two planned vertical slices make these goals runnable:

- [Observable sample call](milestones/observable-sample-call.md) follows the
  definition-driven call. A developer runs the existing sample and sees live timing,
  safe provider failures and VM health on a separate dashboard, without waiting for
  persistence or expanding the voice console.
- [Call inspection and debugging](milestones/call-inspection-and-debugging.md) follows
  asynchronous history. An authorized operator inspects a live or ended call's
  participant/turn/tool timeline, permitted variable snapshots and observed timings,
  distinguishing live state from archive lag, unavailable facts and known gaps.

The owning engine/gateway boundaries emit framework-independent Telemetry events.
Project-owned handlers perform bounded local work because Telemetry invokes handlers
in the emitting process; downstream reporting/inspection must not introduce SQL,
network waits or unbounded queues into media/model callbacks. Embedded hosts can
attach to the complete list returned by `Vxpipe.CallEngine.Telemetry.events/0` without a
gateway, Console, Phoenix, or database dependency. Standalone MCP hosts likewise use
`Vxpipe.MCP.Telemetry.events/0`; the MCP library has no Console dependency. A stable handler identifier,
detach-before-attach startup, orderly detach and a bounded receiving collector keep that
integration safe; the engine README contains a minimal host example. Measurement boundaries
must distinguish provider output, gateway egress and actual remote playback; missing data is
not zero.
[Telemetry execution](https://hexdocs.pm/telemetry/telemetry.html#attach/4).

The Console's `Vxpipe.Console.TelemetryReporter` is one optional consumer. Its event
handler performs only atomic admission and a local message send. The configured
`max_pending_events` is a hard bound: events beyond it are dropped and counted rather
than growing the reporter mailbox or delaying the emitting process. The reporter keeps
only finite counts, duration aggregates and the latest runtime sample; it never retains
raw event history. Duration aggregates convert native monotonic durations to
microseconds and retain count, total, minimum, maximum and latest values. Provider,
operation, outcome and failure keys are normalized to the closed categories above,
including fallbacks for unexpected metadata. Snapshot ages expose stale collection,
and the dropped count exposes saturation. One stable Telemetry handler identifier is
detached before attachment and during normal shutdown, so a replacement also removes a
handler left behind by an abrupt reporter exit. A separate MCP projection owns MCP event
sanitation and aggregation; it drops the local client PID and all unexpected fields in the
emitting process before the reporter message is sent. The standalone MCP operations are
synchronous and own no admission queue, so the diagnostic panel reports queue pressure as
not applicable rather than inventing a gauge.

An optional engine-owned local model fixture makes the early dashboard failure path
deterministic. It is disabled in base application configuration and may be enabled only
through trusted application/runtime settings; no call definition, invocation, browser
room-creation body, or RTVI command can select a fixture result. The supervised fixture
atomically supplies one fixed success, delayed success, provider failure, or invalid empty
result to the next Agent Runtime request, then resets to its configured default. Deliberate delay runs
in the model worker, not the room authority. The coordinator therefore emits the normal
payload-free model timing/outcome events under the bounded `:local_fixture` provider label,
and successful text continues through the ordinary optional TTS and gateway paths. Console
controls appear only when the fixture process is configured.

The gateway exposes authorized projections and the console presents them through
public gateway/Calls APIs, not direct Repo queries or unrestricted room state.
Tenant call inspection is separate from platform-wide VM introspection;
caller tokens and public call IDs grant neither operator access nor extra visibility.
Existing source-interval privacy and credential exclusions apply, and debugging never
starts STT, recording or audio monitoring implicitly. Silent listening remains in the
live-mixing milestone. Later slices extend these views with their implemented facts.

The Console implements that inspection boundary at `/operator/sign-in`, `/calls`, and
`/calls/:call_id`. It exchanges an existing tenant key plus `:calls`-scoped API key for a
non-secret signed browser session, filters the submitted secret from request logs, and
keeps sample and platform-diagnostics routes outside this tenant guard. Calls supplies
cursor-bounded persisted pages; the engine supplies only its bounded live projection.
URL-backed event selection is local to the loaded evidence, while connected running-call
pages refresh only the live projection. Ended calls require no room process. Console and
Gateway gain neither Repo access nor unrestricted process inspection through this flow.

Phoenix is approved for the separate `vxpipe_console` application, not a gateway
migration. Preserve the existing gateway protocol handlers, React sample,
application-option ownership and engine/persistence dependency direction.
Phoenix LiveDashboard is selected for platform VM/runtime inspection; a separate
Vxpipe diagnostics page owns bounded call-path measurements. Diagnostics are disabled
by default and explicitly enabled through Console application settings. When enabled,
this slice adds no page authentication; deployment exposure is an application concern.
API keys authenticate call-management endpoints and caller join tokens authorize call
admission. Tenant call inspection additionally permits an existing `:calls`-scoped API
key to establish a Console-only, signed browser session. Authentication consumes the key
server-side over TLS; the session stores only the tenant/API-key identifiers, closed scopes,
and a bounded expiry, never the key secret. That session authorizes only call-inspection
routes and is not a caller token, sample credential, diagnostics login, or LiveDashboard
login. Repository development serves the diagnostics namespace from the shared Console
endpoint. The Console
shell and LiveDashboard route are
implemented. The Vxpipe LiveView measurement page reads the bounded reporter with a short
timeout and presents only its latest aggregate snapshot. It distinguishes current, stale,
missing, dropped and unavailable observations without creating a second history buffer.
Its locally packaged, content-hashed client connects through the existing diagnostics
socket. The diagnostics enablement decision is shared by the HTTP pipeline and socket
connect callback: disabled HTTP requests return 404 and disabled socket connections are
refused. No hosted browser asset or additional Console or LiveDashboard authentication is
introduced.

## Configuration and container boundary

OTP application settings are the canonical configuration entry point for
runnable Vxpipe applications. Each application reads its namespaced setting once
at its application boundary, validates and normalizes it, and passes explicit
options down its supervision tree. Reusable supervisors also accept those
options directly so an embedding host is not forced to mutate global
application state.

Vxpipe's own `config/<env>.exs` files configure only the Vxpipe root project.
Mix does not evaluate a dependency's configuration files in a consuming
project; the consuming release owns its application settings. Runtime modules
must not branch on `Mix.env()`. Deployment environment variables are read only
from `config/runtime.exs` and translated into application settings before the
applications start.

The Docker runner accepts one versioned JSON configuration through an explicit
`--config` path. The same schema permits pinned resource references or complete
inline definitions for a standalone process.

The JSON loader is an adapter into the same validated application options. It
must not create an independent configuration path or allow raw string-keyed JSON
to flow through runtime processes.

External strings resolve through closed registries. JSON never selects an
arbitrary BEAM module and never uses `String.to_atom/1`. Provider credentials are
runtime secret references to environment variables, mounted files, or an
external secret store. Resolved plans and validation errors are redacted.

A resolved room plan pins:

- configuration and schema version;
- agent and workflow versions;
- provider adapters and capability snapshots;
- transport, codec, and media policies;
- turn, interruption, and tool policies, plus supported configured LLM routing options;
- artifact capture and event policies; and
- secret reference generations without storing secret values.

Stored-data retention periods are not pinned in the room plan; the current
application/tenant setting applies to existing and future calls.

The container exposes readiness only after required engine and gateway services
can accept work. Termination drains admitted sessions according to policy,
rejects new admission, and exits with deterministic status. Logs are structured,
secret-safe, and exportable without a local interactive login.

### Development ingress

The repository development stack uses the Console Phoenix endpoint as its single tailnet
HTTPS listener. Phoenix/Bandit binds to the discovered Tailscale address on port 4000,
serves the Console-owned React assets, and invokes the gateway Plug in-process. This
supplies one stable secure browser origin without a reverse-proxy hop or second web server.

The Console Phoenix endpoint supervises Phoenix's esbuild wrapper as a development
asset watcher and uses Phoenix LiveReload for browser refreshes. Goreman
does not model the playground as a separate application; it starts the shared BEAM
runtime and reload helper. React remains the sample UI and is
not replaced by LiveView. There is no separate frontend HTTP listener: esbuild writes
the watched bundle into Console `priv/static`, and Phoenix serves it on the same endpoint
as API, health and diagnostics routes.

`bin/dev` resolves the tailnet hostname and address, asks Tailscale for the current
`.ts.net` certificate in the ignored runtime directory, and passes the certificate,
key, address and public URL into Phoenix runtime configuration. The development stack
runs as the invoking user and does not require a root process, `TS_PERMIT_CERT_UID`,
or manually preserved TLS environment variables.

Phoenix terminates HTTP and WebSocket TLS. WebRTC media and RTVI data channels still
establish their own ICE-selected path and are not carried through the HTTP listener.
Production ingress remains deployment-specific.

## Deterministic testing facilities

Vxpipe includes opt-in in-process Morse/tone STT and TTS adapters in the call-engine
library. They implement the ordinary speech capability and local transport boundaries;
they do not bypass room turns, participant attribution, output acknowledgements,
interruption, or playout completion. A compiled provider profile must resolve through
the application's closed provider registry. No call/client input can choose a transport
module directly.

The codec handles a documented International Morse ASCII subset as bounded, mono,
little-endian linear16 PCM. Encoding is resumable and TTS retains at most one
unacknowledged 20 ms frame. Decoding retains partial windows and split samples across
arbitrary chunks, with explicit final-flush, malformed-signal, duration, text, and audio
bounds. Provider failures use the existing speech failure lifecycle rather than fabricated
text or silence. Exact alphabet, timing, safety defaults and verification commands are in
the [call-engine README](../apps/vxpipe_call_engine/README.md#local-morse-audio-providers) and
[Morse audio milestone](milestones/morse-code-audio-providers.md).

These encode/decode controlled tones, not ordinary speech, VAD, or a local speech model.
Direct PCM verification is distinct from browser microphone processing: the current
WebRTC ingress supplies Opus and is not claimed as Morse STT input. The opt-in Console
profile therefore uses typed input with 48 kHz Morse TTS; the complete local STT/model/TTS
round trip runs at the engine's direct-PCM boundary without speech credentials or network
access.

The adapters support:

- protocol conformance tests;
- multi-participant routing tests;
- turn and barge-in timing tests;
- event replay and snapshot tests;
- failure and supervision tests;
- container smoke tests; and
- concurrency and scheduler regression benchmarks.

## Implementation checkpoints

Each behavior checkpoint begins with the smallest failing externally observable
test and leaves the umbrella usable.

### Implemented create-room slice

The first deliberately narrow vertical slice crosses the browser, gateway, and
call-engine boundaries without claiming completion of checkpoints 1 through 3:

1. The samples browser sends `POST /api/rooms` to its same-origin gateway.
2. The gateway injects a configured development principal with a tenant, actor,
   and `rooms:create` scope. The browser cannot assert those identities.
3. The browser supplies a non-secret, randomly generated room ID. The gateway
   validates it and constructs the protocol-neutral `CreateRoom` command with a
   generated command ID and absolute deadline.
4. The call engine starts a temporary room-incarnation supervisor through its
   named dynamic room supervisor.
5. A significant, temporary room-authority child owns the initial `open` state.
   If that authority terminates, the whole incarnation terminates and is not
   automatically recreated under stale identity.
6. The engine returns a public snapshot, which the gateway serializes. That
   confirmation replaces the creation screen with the responsive Pipecat
   console; the console receives the whole viewport without Vxpipe overlays.

The development route is disabled in base configuration and enabled only by the
repository development overlay. The configured principal is not authentication;
it is a replaceable seam where a future authenticated gateway session supplies
the same protocol-neutral identity. At this checkpoint the slice did not yet
implement generic command/event contracts, participants, media, RTVI signaling,
persistence, or room recovery.

### Implemented participant connection slice

The next slice admits one human participant and proves a real unmodified Pipecat
client can cross the browser, HTTP, WebRTC, RTVI, and OTP boundaries:

1. `POST /api/rooms/:room_id/sessions` requires the configured `rooms:join`
   scope and asks the call engine to admit a protocol-neutral human participant.
2. The room authority starts that participant only through the dynamic
   participant supervisor owned by the room incarnation. It monitors the
   participant and releases its identity if the participant terminates.
3. The gateway issues an opaque, single-use session bound to the tenant, actor,
   room incarnation, and participant. The default development lifetime is five
   minutes; expiry is enforced with monotonic time.
4. The Console playground passes that session in the current Pipecat client's
   `webrtcRequestParams.requestData` and uses the same-origin
   `/api/rtvi/offer` endpoint.
5. The gateway implements Pipecat Small WebRTC's `POST` offer/answer and `PATCH`
   trickle-ICE requests with ExWebRTC. It accepts the ordered `chat` data channel
   and ignores transport signalling and keepalive messages that are not RTVI
   application messages.
6. A current RTVI 2.x `client-ready` receives a correlated `bot-ready` for
   server protocol 2.1.0. Unsupported or malformed version strings receive a
   correlated protocol error without crashing the transport process.
7. Closing the data channel tears down the complete temporary connection
   incarnation, including the peer connection, while the participant and room
   incarnation remain alive.

The gateway owns the session, WebRTC, and RTVI processes and their dependencies.
The call engine sees only participant admission and contains no ExWebRTC,
Pipecat, JSON, or RTVI types. The detailed decision, supervision topology,
failure behavior, and verification evidence are recorded in
[`rtvi-participant-connection.md`](rtvi-participant-connection.md).

At that checkpoint this was transport and protocol readiness, not a voice
conversation pipeline. Incoming RTP terminated at a diagnostic sink, and there
was not yet an agent participant or text-turn path.

### Implemented deterministic text-turn slice

The third slice adds a provider-free conversational round trip without changing
the browser UI or introducing RTVI types into the call engine:

1. Development room creation resolves a deterministic text agent. The room
   authority admits its agent participant and starts the responder through the
   room incarnation's dynamic capability supervisor.
2. A WebRTC connection must attach to its exact room incarnation and admitted
   human participant before it can complete negotiation and report
   `bot-ready`. A room without a ready agent path rejects attachment.
3. The engine and gateway monitor each other across that attachment. Browser
   disconnect removes the room subscription; loss of the room, human
   participant, or agent capability tears down the transport connection.
4. The gateway decodes RTVI `send-text` into a validated, protocol-neutral
   `SendText` command using identity from the bound session rather than the
   client message.
5. The room authority verifies that the caller owns the attached connection and
   emits consecutive `ParticipantTurnStarted` and `ParticipantTurnCompleted`
   events for the complete typed input before dispatching work outside its
   mailbox to the deterministic capability.
6. The capability produces `Echo: <input>`. The room authority assigns IDs and
   consecutive room-incarnation sequences to protocol-neutral `TextOutput` and
   `AgentTurnCompleted` events and sends them only to the originating
   connection. Completion is separate because one turn may eventually contain
   multiple output segments.
7. The gateway projects participant boundaries as RTVI user start/stop messages
   and agent output as an unspoken `bot-output` followed by
   `bot-stopped-speaking`. Pipecat's protocol 2.x client uses these lifecycle
   events to keep successive typed turns in separate messages, including turns
   submitted inside its speech-pause grace period. The unmodified Pipecat
   conversation view displays both the locally injected user message and the
   engine-produced assistant response.

This establishes the first bidirectional command/event path and the first
runtime capability instance. It does not add transcription, model inference,
speech synthesis, outbound audio, provider credentials, reconnection,
production authentication, TURN policy, persistence, or room recovery. The
detailed decision and verification evidence are in
[`deterministic-text-turn.md`](deterministic-text-turn.md).

### Implemented Deepgram Flux audio-turn slice

The fourth slice routes the browser's existing microphone track through a
provider-neutral engine boundary while preserving RTVI as a gateway projection:

1. The gateway resolves the negotiated codec for each remote audio track and
   maps an ExRTP Opus packet to a protocol-neutral `AudioFrame`. No ExWebRTC or
   ExRTP type crosses into `vxpipe_call_engine`.
2. Attaching a human connection starts one temporary speech-to-text capability
   and one bounded media ingress through the room incarnation's dynamic
   capability supervisor. The returned `ConnectionAttachment` is an internal
   runtime handle and is never a public snapshot or wire value.
3. Media ingress validates room-incarnation and connection identity, binds the
   stream to its first accepted track, and enforces maximum frame age, queue
   length, and total queued bytes. It allows only one provider send in flight,
   preserves accepted order, tolerates isolated overflow as RTP loss, and
   terminates the stream after sustained overflow.
4. The Deepgram adapter owns Flux `/v2/listen` query construction, authorization,
   bounded JSON decoding, and fixed provider-event mapping. The supervised socket
   owns WebSocket lifecycle and sends raw 48 kHz Opus payloads without exposing
   its credential or provider payloads to the room.
5. The room authority receives only normalized low-rate signals. `StartOfTurn`
   creates an audio turn, `Update` replaces the current partial transcript, and
   `EndOfTurn` emits a provider-final transcription followed by a distinct
   participant-turn completion. Eager end predictions never invoke the agent.
6. Only the complete, non-empty `EndOfTurn` transcript is dispatched once to the
   deterministic agent. All resulting events retain one engine turn correlation
   while receiving consecutive room-incarnation sequence numbers.
7. The gateway projects those events as RTVI `user-started-speaking`,
   `user-transcription` with the correct `final` flag, and
   `user-stopped-speaking`, followed by the existing deterministic bot output.
8. Closing or losing the provider before `EndOfTurn` does not fabricate a final
   transcript or committed turn. Provider and media failure tears down the
   affected WebRTC connection; automatic mid-turn reconnect is deferred.

The repository development overlay enables this capability with
`flux-general-en` and requires `DEEPGRAM_API_KEY` at runtime. Base configuration
leaves speech-to-text disabled, so an embedding application's environment is not
implicitly coupled to the repository's development provider. Default tests use
a fake transport; separately tagged live tests prove both individual 20 ms Opus
packet compatibility and the complete WebRTC-to-Flux-to-RTVI-to-agent path.
Detailed planning, provider research, implementation choices, and verification
evidence are recorded in
[`20260904-1212-stt-capability.md`](../labnotes/20260904-1212-stt-capability.md).

### Implemented Deepgram Flux text-to-speech slice

The fifth slice completes audible deterministic-agent output without placing
provider or WebRTC details in the room authority:

1. A configured agent owns one temporary text-to-speech capability under the
   room incarnation's dynamic capability supervisor. The capability keeps one
   persistent `/v2/speak` session so Flux prosody can persist across turns.
2. `TextOutput.will_be_spoken` is true only when the command requested audio,
   the room has a live TTS capability, and its originating connection supplied
   an output sink. Text-only and TTS-disabled paths still complete immediately.
3. The provider-neutral capability serializes one active synthesis request and
   a bounded pending FIFO. It sends separate Flux `Speak` and `Flush` controls,
   validates provider lifecycle messages, and synchronously hands bounded raw
   audio frames to the connection sink. The socket cannot accumulate unbounded
   audio in the capability mailbox. If the paced sink fills, the current binary
   frame and, when necessary, final-frame padding wait behind bounded calls while
   pace ticks drain capacity; provider bursts therefore apply TCP/WebSocket
   backpressure rather than terminating the room.
4. Flux streaming emits raw signed little-endian linear16 rather than Opus. The
   gateway's per-connection egress preserves provider-frame remainders, makes
   exact 20 ms 48 kHz mono frames, and encodes them through libopus. It queues a
   bounded number of packets and paces RTP at 20 ms with sequence numbers and
   timestamps advanced independently of provider chunk boundaries. The default
   500-packet queue covers ten seconds of ordinary output; longer turns remain
   supported through backpressure instead of requiring an unbounded buffer.
5. The gateway creates the outbound WebRTC audio track before answering the SDP
   offer. The output sink is an opaque process handle passed only through the
   internal attachment path; no PID enters a public command, snapshot, event,
   JSON value, or RTVI message.
6. Provider `SpeechMetadata` means no more synthesis audio. It causes egress to
   zero-pad at most one final incomplete PCM frame. Once the total packet count
   is known, egress reports elapsed scheduled playout every 100 ms for internal
   transport progress. The room does not emit agent completion until the last
   paced packet's duration has elapsed.
7. A spoken `TextOutput` is projected as an RTVI 2.x `bot-output` segment with
   `spoken_status: new`. Sending the first RTP packet produces a
   protocol-neutral `AgentSpeechStarted`; draining the final packet produces
   `AgentTurnCompleted`. The gateway projects those boundaries as
   `bot-started-speaking` plus an `in-progress` output whose entire text remains
   pending, then a `completed` output followed by `bot-stopped-speaking`. Flux
   supplies total audio duration but no per-word timing stream, so the RTVI
   adapter does not fabricate intermediate word progress from scheduled audio.
   Progressive highlighting is reserved for a future provider-alignment event;
   without one, the whole output changes from pending to completed at the paced
   gateway boundary. This gives an unmodified RTVI 2.x client one persistent
   assistant message without presenting estimated word positions as observed
   speech. The completion boundary does not claim a browser output-device
   acknowledgement.
8. This first audible slice initially gated microphone RTP and projected server
   mute boundaries during spoken output. The later spoken-barge-in checkpoint
   supersedes that input behavior: microphone RTP now continues to STT and no
   synthetic mute events are emitted. Output announcements remain serialized:
   the next segment is not exposed until the active paced turn completes, even
   though the engine may already have produced its text. At this checkpoint
   typed input during playback was queued output; the typed-interruption
   checkpoint below supersedes that behavior when `run_immediately` is true.
9. Fatal provider, transport, codec, sink, or sustained queue failures never
   fabricate successful completion. At this checkpoint local playback
   cancellation and Flux playback-offset reconciliation remained deferred; the
   typed-interruption checkpoint below implements them for immediate text.

Base configuration leaves text-to-speech disabled. The repository development
overlay enables `flux-haley-en`, requests 48 kHz linear16, and resolves the same
runtime `DEEPGRAM_API_KEY` used by Flux STT. Focused tests cover provider parsing,
bounded capability behavior, PCM framing, Opus encoding, RTP pacing, and room
sequencing. Separately tagged live tests prove both provider PCM output and a
complete RTVI text-to-Flux-to-Opus-to-WebRTC path. Research, Callx comparison,
the rejected PCMU path, and detailed evidence are in
[`20260904-1602-tts-capability.md`](../labnotes/20260904-1602-tts-capability.md).

### Implemented Gemini model-inference slice

The sixth slice replaces the repository development agent's deterministic echo
with room-scoped conversational generation while preserving the established
input and output boundaries:

1. `CreateRoom` accepts the provider-neutral `:model_inference` agent preset.
   The reusable base configuration leaves it disabled; the development overlay
   selects the ReqLLM adapter and `google:gemini-3.5-flash-lite`.
2. The room authority admits the normal agent participant and starts one
   temporary model-inference capability under the room incarnation's dynamic
   capability supervisor. Provider selection is application configuration, not
   part of the client protocol or room HTTP payload.
3. Typed RTVI input and committed Deepgram transcripts still converge on
   `SendText`. The capability accepts each turn quickly, while an explicitly
   named application `Task.Supervisor` owns blocking provider requests outside
   the room-authority mailbox.
4. Each capability runs one request at a time, bounds its pending FIFO, and
   retains a configured number of complete successful user/assistant pairs.
   The configured system prompt is placed first on every request and is not
   replaceable by client input.
5. The ReqLLM adapter translates neutral message roles, passes the runtime
   Gemini credential explicitly, and returns only normalized text chunks or an
   error. Streaming models feed a bounded sentence accumulator so each complete
   sentence can enter the existing `TextOutput`, optional TTS, and paced playout
   path before generation finishes. Models without streaming support return one
   buffered terminal segment through the same engine lifecycle.
6. A provider failure, invalid response, task exit, or timeout fails that turn,
   omits it from history, and advances queued work without ending the room. A
   protocol-neutral `AgentTurnFailed` becomes a correlated generic RTVI error
   response. A full pending queue rejects new work as retryable `agent_busy`
   before participant input events are committed.
7. Development reads `GEMINI_API_KEY` only from runtime configuration when the hosted
   model path is enabled. The optional local diagnostics fixture needs no model credential.
   Credentials never enter commands, events, public snapshots, JSON payloads, browser
   configuration, or logs.

The engine does not expose provider token boundaries. It emits sentence-sized
segments and closes the logical assistant turn only after model generation and
all scheduled speech playout complete. Conversation history is volatile and
bounded by completed turn count, not tokens. Tools, token-aware compaction, durable history,
prompt-profile resolution, and verification of supported provider-native LLM
fallback remain later checkpoints. R47–R50 approve design contracts above, not
these runtime features or a Vxpipe fallback coordinator.
Provider-driven spoken barge-in is implemented by the later checkpoint below.
The detailed decision and verification evidence are in
[`model-inference-turn.md`](model-inference-turn.md).

### Superseded model tool-invocation slice

This historical slice executed tools inside the old model request task. It has been superseded:
definition-driven agents now use Agent Runtime and independently supervised invocation workers.
The optional legacy `CreateRoom` model-inference preset remains text-only, advertises no tools,
and rejects unsolicited provider tool calls without execution or public tool lifecycle events.
The numbered behavior below records the removed slice and is not current runtime behavior.

The next slice closes the first model/action/model loop without moving tool
execution into RTVI or a provider adapter:

1. Trusted call-engine configuration supplies modules implementing the neutral
   tool behavior. Each exposes a name, description, JSON parameter schema, and
   callback. The browser cannot submit executable modules or tool schemas.
2. The model capability gives neutral definitions to its provider adapter. A
   response may contain final text or normalized tool calls; both streaming and
   buffered providers use the same classification.
3. Calls execute sequentially inside the original supervised model request task.
   Results must be JSON-compatible and byte-bounded, and the complete loop has a
   configured maximum number of rounds plus the original turn timeout.
4. Tool results return to the provider as neutral assistant-call and tool-result
   messages. Provider-specific continuation metadata remains opaque adapter state
   and never enters public events.
5. Room authority publishes sequenced tool start, completion, failure, and
   cancellation events attributed to the agent, originating participant,
   connection, command, and correlation. Immediate typed or spoken interruption
   kills tool work and settles active calls before the turn interruption.
6. The RTVI gateway maps this lifecycle to
   `llm-function-call-in-progress` and `llm-function-call-stopped`. Other client
   protocols may project the same engine events differently.
7. Development enables an argument-free `get_current_time` tool returning UTC,
   allowing the unmodified samples console to demonstrate the entire loop.

The first tool runs within the model request task. Separate per-tool supervision,
parallel calls, approval gates, durable results, idempotency, and external action
providers remain later checkpoints. Detailed decisions and verification evidence
are in [`model-tool-invocation.md`](model-tool-invocation.md).

### Implemented typed turn-interruption slice

The next slice makes RTVI `send-text` urgency observable across the complete
model, synthesis, playout, and protocol path:

1. The room authority derives interrupter identity from the already attached
   connection. A client cannot override its participant ID in the message.
2. `run_immediately: true` cancels all older active and queued work in the room's
   current single logical agent-output lane before dispatching replacement work.
   `run_immediately: false` retains FIFO behavior.
3. `AgentTurnInterrupted` explicitly names the interrupted agent, originating
   participant and turn, target connection, interrupting participant and
   connection, both commands and correlations, and confirmed played time. This
   remains unambiguous with several human participants and does not assume agent
   identity from a process ID.
4. Audio egress immediately clears unsent RTP and PCM. The persistent Flux TTS
   capability keeps its one in-flight sink write in a supervised task so RTP
   backpressure cannot block cancellation. The persistent Flux TTS session
   receives an `Interrupt` with cumulative confirmed playback when audio has
   played, discards late provider audio, and starts replacement synthesis only
   after the old provider turn closes.
5. In-flight and queued model requests are canceled. A completed interrupted
   user/assistant pair is removed from volatile history when exact heard text is
   unavailable, preventing later prompts from treating the complete response as
   heard.
6. The gateway emits standard `bot-interrupted` without private fields. It also
   emits a versioned `vxpipe.turn` `server-message` carrying full attribution for
   Vxpipe-aware clients and never marks the interrupted output as completely
   spoken.
7. RTVI exposes one logical bot through each connection. The engine event names
   its agent participant so future agent composition remains protocol-neutral;
   independently addressable multi-agent clients require an optional Vxpipe
   message or another adapter.

This checkpoint covered typed interruption and initially left microphone RTP
gated during bot playout. The subsequent spoken-barge-in checkpoint supersedes
that transport behavior. The decision, rejected alternatives, implications,
and test evidence are recorded in
[`typed-turn-interruption.md`](typed-turn-interruption.md).

### Implemented provider-driven spoken-barge-in slice

The next slice uses the hosted STT provider's turn-start evidence to activate
the existing room-wide interruption path:

1. The WebRTC connection forwards valid inbound RTP through its bounded media
   ingress regardless of whether agent output is queued or playing. It no longer
   projects synthetic `user-mute-started` or `user-mute-stopped` messages around
   output.
2. A normalized provider `StartOfTurn` is accepted only from the STT capability
   bound to that tenant, room incarnation, participant, and connection. Neither
   the provider payload nor the client supplies the participant identity.
3. Before emitting the participant start, the room allocates the audio turn's
   command and correlation IDs and uses them in a protocol-neutral interruption
   context. The existing cancellation path stops model work, synthesis, and
   local playout. If no agent work exists, no interruption event is fabricated.
4. `AgentTurnInterrupted` precedes `ParticipantTurnStarted` in room sequence and
   attributes the cancellation to the authenticated STT connection. Repeated
   provider updates do not cancel twice.
5. The same audio turn continues through partial transcription. `EndOfTurn`
   commits a non-immediate internal text command because the interruption was
   already evaluated at speech start, then drives normal model inference and
   spoken output.
6. Standard clients receive `bot-interrupted`, user speaking/transcription
   events, and the replacement bot output. The optional `vxpipe.turn` projection
   carries the complete agent, source-turn, and interrupter identities.
7. The slice does not add local VAD or server-side acoustic echo cancellation.
   Capture endpoints should use their available echo control. Provider false
   starts can cancel agent work, and continuous microphone streaming continues
   to consume STT capacity during output.

The implementation and verification evidence are detailed in
[`spoken-barge-in.md`](spoken-barge-in.md).

### Current definition-driven call runtime

The initial definition checkpoints released engine-owned schema `20260906.02`; the
current schema is `20260910.01`. It adds per-tool conversation admission: omission resolves
to `blocking`, while only explicit `"non_blocking"` opts into later caller turns during
pending work. Both modes always use the same independently supervised Call Engine worker
path. Resource ID/revision and trusted
tenant/actor identity are constructor metadata rather than fields accepted from
definition or invocation documents. Fixed known keys are normalized without
creating atoms from input; equivalent JSON and Elixir maps produce the same typed
definition.

The currently implemented subset validates one human web caller, one agent
receiver, inline prompt/first-message policy, capability-profile refs, exact-name
host-tool selections, typed Call Variables declarations and permissions, partial
initial values, and a bounded call duration. A closed JSON Schema-shaped subset
is compiled with JSV 0.22 without casting or reference resolution. Defaults,
unsupported keywords, malformed grants, unknown sections/variables and invalid
populated values fail before room startup. `required` declarations are retained
as authored metadata but do not demand completeness at any nesting depth.

Closed trusted registries resolve selected profiles and handlers into an immutable
`ResolvedCallPlan`. The plan receives fresh call, room, participant and
agent-activation identities, plus declared section schemas, grants, initial values
and zero revisions. Omitted sections stay unpopulated while explicit empty objects
stay populated. Neither rejected values nor private capability options enter public
errors. Later-milestone transfers remain rejected instead of being silently ignored.

The first runtime checkpoint added Jido AI 2.3 and Jido Action 2.3 as direct engine
dependencies, an application-owned Jido supervision instance, and the finite
`Vxpipe.CallEngine.Agent` module. A synchronous readiness configuration boundary
sets the resolved prompt and exact supported Action modules on a running AgentServer;
automatic Action retries are zero. Static host Actions enter the existing bounded
Vxpipe executor through a per-activation `Tool.Dispatcher` GenServer, which serializes
actual handler execution even though the released Jido runtime does not expose its
parallel-tool limit through the Agent macro. A deterministic test proves two successive
Action rounds and a final answer through Jido's delegated ReAct worker.

The next checkpoint added `AgentCoordinator` and a narrow `AgentRuntime` adapter. It
correlates Vxpipe command identities with Jido request IDs, streams complete sentence
segments through the existing capability messages, projects Action lifecycle events,
bounds the pending queue and response bytes, cancels timed-out/interrupted requests, and
rejects stale terminal events. Tool completion that overtakes its start event is buffered
until the call identity/arguments arrive, and terminal completion waits for observed tool
lifecycles to settle. Explicitly selected completed Vxpipe turns are excluded from every
later model projection; physical Jido-context replacement is also requested but may be
deferred by Jido. A deterministic runtime double proves queue/failure/order races, while a
real Jido AgentServer test proves one host Action and final response use Jido's delegated
ReAct loop.

The trusted `start_call/2` path now starts a room from a compiled immutable plan. A typed
`PlanStartup` value selects only the entry caller and receiver and combines the receiver's
pinned prompt, `:req_llm` model and static host Actions with application-owned runtime
bounds. It starts both participant subtrees and installs the receiver's stable coordinator
reference as the room text capability. An unused catalog agent starts no participant or
activation process. Plan startup also combines the caller's selected STT and receiver's
selected TTS public options with application-owned credentials, transports and queue/ingress
policy before participant admission. Each speech setting retains its top-level implementation as
the application default and may expose a closed `:providers` map for additional implementations.
The compiled provider module must match that default or an exact registered module key; call input
cannot construct a module or select an unregistered transport. This permits different pinned call
profiles, including in-process Morse providers, without changing legacy room defaults. It retains
those typed provider runtimes for the room,
starts TTS with the receiver and starts the pinned STT when the caller connection attaches.
Existing preset startup remains intact. A resolved-plan room now starts its dedicated
CallVariables owner alongside, rather than inside, RoomAuthority and binds only its active
agent's permitted generated Actions. The temporary gateway adapter may supply trusted,
server-configured initial variables to the invocation; the browser room-creation body cannot
replace them, and adapter inspection excludes the private values. Exact evidence is tracked
in the milestone and its implementation labnote.

The public plan-start boundary now preflights the complete active startup selection before it
creates the room supervisor child. This check resolves application-owned provider configuration
without starting provider processes and returns a path-specific `unsupported_call_plan` error.
The initial runnable subset accepts only a web receive/start-call caller, a
`wait_for_input` receiver, supported local host tools, the Jido/ReqLLM model path, and compatible
configured speech profiles. Typed Call Variables are active for non-empty section sets through
the room-owned process and generated tools described above. Generated/fixed greetings remain
rejected until the opening-audio/lifecycle slice implements them. Privacy/media policy,
remote-tool, transfer, and other connection modes remain closed-schema constructor errors rather
than ignored settings.

The repository development gateway is the first trusted host for this path. Its startup
configuration validates one definition plus closed capability/tool registries. For each
browser request, it creates a trusted invocation, compiles a fresh plan, starts the plan,
reads the already-started entry caller through the engine API, and issues a gateway session
bound to that participant. `POST /api/rooms` returns the room, participant, and session
together; the browser neither supplies the definition/profiles nor admits a second human.
The creation page accepts that atomic response and enters the unchanged responsive Pipecat
console. The older preset create-then-join routes remain available as a development/embedding
compatibility path and are not the production admission design.

The repository's development configuration no longer duplicates the trusted definition as a
legacy model-inference preset. The definition/profile registry owns the system prompt, model,
voice, STT model, tool surface, and public provider media options. Call-engine application
settings own only runtime/provider integration concerns needed by this slice: private
credentials, transport modules, ingress/queue bounds, and agent execution bounds. The default
sample still checks required development credentials at runtime, while the reusable base keeps
legacy preset model inference disabled unless an embedding host configures it explicitly.

### Implemented prepared-call admission slice

The durable development path supersedes direct trusted room creation when PostgreSQL is
configured, while preserving it as a database-free fallback:

1. Console starts a trusted sample process before its endpoint. That process uses only
   public Calls workflows to bootstrap a fresh development tenant/API key and publish the
   configured sample definition. Its inspect projection excludes the plaintext key and
   initial variables.
2. `POST /sample/calls` authenticates with that server-held key, prepares a durable call,
   and returns only the public tenant/call/participant locator and opaque join token.
3. The browser posts an empty body and that bearer token to the tenant-scoped participant
   session route. The gateway claims the token in one short repository transaction, then
   starts the exact serialized plan pinned at preparation; browser data cannot replace
   variables or tool visibility.
4. First admission starts the room and entry participants. A later eligible participant
   claim joins the already-running room using its persisted incarnation without restarting
   the room or resetting `started_at`.
5. Start-time projection runs as supervised bookkeeping after runtime success. Its failure
   cannot tear down a live room; known pre-live failure records a bounded terminal reason,
   and accepted tokens are never restored for speculative retries.

The authenticated management routes grant no CORS access. Configured CORS applies only to
browser token admission and signaling and remains independent of credential validation.
API keys, initial variables, token digests, and consumed join tokens do not enter engine
state or live-session responses.

1. **Protocol-neutral types:** implement command, signal, media-frame, event,
   snapshot, error, identity, and incarnation contracts with serialization-safe
   public projections.
2. **Room failure boundary:** implement the room incarnation supervision tree,
   authority, registries, bounded retention, and whole-incarnation failure
   behavior using deterministic adapters.
3. **Gateway adapter boundary:** define the protocol-adapter behaviour and prove
   it with an in-memory fake protocol before adding a concrete client protocol.
4. **RTVI 2.x codec:** implement handshake, standard message mappings,
   correlation, readiness, errors, and current-client conformance fixtures.
5. **Turn and playout semantics:** implement partial/segment/commit events,
   interruption, graceful end versus cancellation, and actual-playout tracking.
6. **Optional message schemas:** add capability negotiation, room/participant,
   tool, telephony, debug, replay, and session messages through RTVI custom
   messaging.
7. **Transport paths:** add WebSocket/browser media first, then SIP/PSTN while
   preserving the same participant and conversation contracts.
8. **Durability and operations:** add snapshots, replay, exporters, cluster
   ownership, admission control, health, tracing, and retention.
9. **JSON release and image:** compile mounted JSON into a redacted resolved
   plan, start the release, and verify readiness, drain, and deterministic exit.
10. **Second-adapter proof:** implement a minimal test-only second protocol
    adapter to ensure RTVI concepts have not leaked into `vxpipe_call_engine`.

## Acceptance criteria

- A current unmodified RTVI 2.x client completes text and audio conversations.
- A standard-only RTVI client works without consuming optional Vxpipe messages.
- Unsupported versions and malformed messages fail without activating or
  crashing a room.
- A second protocol adapter drives the same commands and domain events without
  modifying `vxpipe_call_engine`.
- Partial, provider-final, turn-committed, interrupted, and cancelled input are
  observably distinct.
- Generated, synthesized, scheduled, played, truncated, and interrupted agent
  output are observably distinct.
- Slow clients, exporters, recorders, or providers cannot block the room
  authority or unrelated sessions.
- Authority failure cannot leave stale room workers alive under a fresh room
  state.
- Retries and reconnects cannot duplicate acknowledged mutations.
- Snapshot plus cursor replay reconstructs the public room state without raw
  audio history.
- Authorization is enforced per operation and event projection.
- Credentials and private runtime terms never appear in public snapshots,
  events, errors, logs, or protocol messages.
- Deterministic adapters cover the same lifecycle used by network providers.

## Deferred compatibility

The first release does not promise RTVI major-version 1 compatibility, seamless
media resumption across reconnect, automatic room recovery after an
authoritative crash, or a particular production concurrency figure. These can
be added through explicit versioned policies without changing the
protocol-neutral engine contract.
