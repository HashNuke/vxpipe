# Vxpipe protocol and runtime architecture

Status: Living architecture; room creation, one-participant RTVI connection,
text-turn, Gemini model-inference, Deepgram Flux audio-input, and Deepgram Flux
text-to-speech, typed interruption, and provider-driven spoken barge-in slices
are implemented

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

The planned definition uses `call_variables.sections`, invocation values use
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

The initial remote MCP adapter targets revision `2026-07-28` Streamable HTTP,
including `application/json` and request-scoped SSE responses with that revision's
request metadata/lifecycle, not legacy initialization/session assumptions.
Other revisions and legacy HTTP+SSE require explicit tested compatibility;
incompatible endpoints fail clearly. [MCP transport](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http).

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
automatic external `$ref` fetching. No library, extra caps, or complete output
schema design is selected. [MCP schema rules](https://modelcontextprotocol.io/specification/2026-07-28/basic#json-schema-usage).

Store received MCP responses, including structured content and attachment/resource
descriptors, preserving reported success/error and unknown outcomes. The agent
chooses further steps through its authorized tools; saving a descriptor does not
download or inspect its target. No automatic file fetch/playback or arbitrary
media reader is added. Detailed projection/inspection is
[deferred](issues/mcp-result-and-document-inspection.md).
Server-requested sampling, elicitation, and related interactions are separately
[deferred](issues/mcp-server-requested-interactions.md): do not advertise
unimplemented capabilities or acquire authority from their requests. Report
missing capability clearly; continuation/resubmission is not an approved retry
exception. These are design contracts, not implemented adapters.

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

Background tools use application-level orchestration for every model provider;
native async-tool support does not select a separate workflow. Vxpipe accepts and
starts an independently supervised invocation within the agent's execution
subtree, then returns a correlated running acknowledgement as the model's tool
response. The same agent can continue conversation and feed TTS while that work
runs. The acknowledgement is not a successful business result.

Completion becomes a separate invocation-linked update to the latest conversation,
not a second ordinary result for the acknowledged call or a replay of its old
model turn. The agent coordinates subsequent speech with the current conversation.
Adapters must preserve accompanying text and tool calls and encode these updates
for their provider; result data remains untrusted tool output. One application
contract avoids provider-specific lifecycle branches. This requires implementation
and per-provider interoperability checks; it is not guaranteed by context encoding
alone. Explicit cancellation is deferred as noted above. Existing interruption,
timeout, transfer/shutdown, and variable-update rules still apply, without a
durable operation worker or post-shutdown recovery requirement.

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
ReqLLM supports the provider options. It does not add a Vxpipe fallback schema,
direct-provider chain/coordinator, or STT/TTS fallback feature. Keep tool,
permission, privacy, and usage constraints, recording actual observed provider/
model attribution without inventing hidden upstream attempts or IDs. This does
not authorize MCP retries or promise replay of already-emitted speech/tool actions
after a stream failure. Unsupported fallback settings follow R47 validation.
The numbered R01–R50 review is complete; deferred issues and engineering choices
remain separate from runtime implementation.

### First messages and transfer responsibility

Optional call-level `opening_audio` plays to `entry_caller` before
`entry_receiver` begins the normal conversation. Its source may be an audio-file
URL (WAV or another supported format) or fixed configured text. For text, render and cache
audio using the initial receiving agent's resolved TTS service and voice,
including configured defaults. Do not generate its text through an LLM, choose
an arbitrary first participant, or start a later transfer agent to supply a voice.
Without an initial agent/usable TTS profile, text-source applicability remains
open rather than silently inventing one.

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
does not acquire per-call retention. Render timing, cache storage/eviction, and
source fetching are not selected. Asset preparation itself starts no call tree
and does not set `started_at`.

This is an initial-call barrier, separate from each agent's greeting and from
transfer behavior. Required transport-specific completion evidence, failure
handling, source configuration/formats, and notices for later joiners are not
selected here. Record `started_at` at actual live-call start, not at notice
completion or receiver activation; the notice does not reset the clock. This is
playback ordering, not mandatory disclosure or a promise of consent/compliance.

Each agent participant chooses its first-message behavior: wait for input, speak
fixed greeting text, or generate a greeting. Apply that choice on its first
activation in a call, after any configured startup notice and once required
connections/capabilities are ready. Reconnect
and later reactivation of the same participant do not replay its startup greeting.
A new call has its own first activation. Greetings use normal authorized output;
this does not bypass current privacy permissions. Exact encoding remains an
implementation detail; the approved startup/idle/duration boundaries follow below.

Required provider/connection startup readiness has a configurable 30-second
deadline, starting with the actual post-join admission/startup attempt, not
prepared-record creation or token issuance. A definitive terminal failure fails
early; expiry aborts startup, releases resources, and reports a clear failure.
Deliberate `opening_audio` playback is not itself a readiness failure or subject
to a new 30-second truncation rule. Preserve its media-input gate and actual
`started_at` semantics; a failed pre-live startup never fabricates a start time.

When an agent genuinely waits for caller input, a configurable 15-second idle
notification lets its instructions decide whether to nudge, wait, or use a
permitted end-call tool. No automatic silence hangup or repeated-announcement
cadence is added. Opening playback, agent output, holding, dialing, and tool-wait
are not caller silence. Use actual conversation/media evidence without new local
VAD/models; human-only calls must not depend on a nonexistent agent.

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
speech guarantee is added. These are design contracts,
not runtime changes.

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
its routing and commit policy follow R38 below. These are designs, not runtime changes.

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

These are approved contracts, not implemented authentication endpoints or CLI
commands. Exact request encoding and the admin endpoint/scope matrix are not
specified by this checkpoint.

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

Calls created for the `samples/` playground explicitly select full tool
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

This is an approved visibility contract, not current gateway behavior. The
current tool-event path still sends arguments/results without this audience
distinction.

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

A provider integration may optionally include asynchronous billing lookup alongside
its streaming service, using persisted provider IDs where a billing API supports
them. It runs outside the media hot path and `RoomAuthority` and can outlive the
room; it neither blocks the live call nor resets `ended_at` or retention. Not every
provider offers request-level billing, and eventual cost resolution is not promised.
Use existing tenant integration authentication/isolation, not per-call credentials.
No billing API/schema/dependency/provider implementation is chosen. R46's initial
pricing policy and R41's asynchronous storage contract are resolved.
Usage-history writes and optional provider billing lookup run outside the room.
Locally accepted variable snapshots and all existing media/privacy and whole-call
retention boundaries still apply.

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
- provider availability and error categories;
- tokens, characters, audio duration, and cost attribution;
- per-room mailbox and bounded-queue pressure; and
- scheduler, reductions, memory, and process restart information.

Every metric carries a unit, aggregation, source, model/provider, and relevant
room/turn/utterance correlation. RTVI metric messages are a compatibility
projection and are not the canonical telemetry schema.

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

The repository development stack uses Caddy as its single tailnet HTTPS ingress.
Caddy binds to the discovered Tailscale address, routes `/api/*` to the gateway
over loopback, exposes the gateway health check at `/healthz`, and routes
remaining paths to the Vite samples application over loopback. This supplies one
stable secure browser origin and leaves room for additional development
applications without making Caddy part of the product protocol model.

`bin/dev` resolves the tailnet hostname and address, renders a complete Caddy
JSON configuration as the invoking user, and then asks Goreman to run only the
Caddy process through sudo. The root process does not inherit application
secrets or depend on manually preserved environment variables. This lets Caddy
retrieve `.ts.net` certificates from tailscaled without configuring
`TS_PERMIT_CERT_UID`; Mix and Vite remain unprivileged.

Caddy terminates only HTTP and WebSocket traffic. WebRTC media and RTVI data
channels still establish their own ICE-selected path and are not proxied through
Caddy. Production ingress remains deployment-specific.

## Deterministic testing facilities

Vxpipe includes deterministic Morse/tone STT and TTS adapters in the library.
They provide reproducible audio without external providers and support exact
assertions for routing, transcription phases, interruption, playout, tool calls,
and teardown.

These adapters are used for:

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
4. The samples app passes that session in the current Pipecat client's
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
7. Development reads `GEMINI_API_KEY` only from runtime configuration when the
   capability is enabled. The credential never enters commands, events, public
   snapshots, JSON payloads, browser configuration, or logs.

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

### Implemented model tool-invocation slice

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
