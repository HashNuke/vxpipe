# Call definition design

Research date: 2026-09-05 UTC
Last updated: 2026-09-07 UTC

## Goal

Define the smallest useful call-definition contract for Vxpipe: one reusable,
versionable, participant-first description that can start a single-agent call
today and grow into multi-agent calls, scoped variables, transfers between agent
and human participants, tools, and telephony without forcing ordinary calls
into a general-purpose workflow language. Participant-control transfers are
engine-owned tools; neither the public definition nor the private resolved plan
needs a node-and-edge model.

This is a research checkpoint. It does not commit a public schema or change
runtime behavior.

The [design gap review](#design-gap-review--pending-approval) records questions
and possible solutions. G1's unified agent `tools` map and G2's tenant-scoped web
admission routes, direct initial variables, API-key authentication with one-way
hash storage, single-use tokens with existing-call recovery and no automatic
call-record expiry, prepared token-join or direct-backend connection, explicit
entry participants/startup, and one participant per definition key per call are
approved and documented below. Record creation and actual live-call start also
have distinct timestamps; preparation is not call duration.
R01–R05 approve OTP/CLI first-key creation, tenant-bound `admin`/`calls` scopes,
multiple independently revocable keys, and key revocation that does not affect
previously issued join tokens or established connections. Join tokens default
to five minutes from issuance; the authenticated requester may request longer.
G3's initialization rule is also approved: call variables have no default values and are
prefilled only from supplied call-setup data. Its interruption rule lets an
already-submitted variable update finish under the existing authorization and
revision checks; a correction uses another tool call, not cancellation or
rollback. Reads containing a forbidden section now explicitly fail as a whole
with a permission error. Object-level and single-variable update tools are requested;
`update_variables` deep-merges supplied objects into the existing section and
preserves omitted variables, including nested variables. Authors should prefer simple,
shallow sections. Explicit `null` clears a variable while retaining its key, only
when its schema permits null; omission preserves the existing value. Physical
variable deletion is deferred. Variables root keys are section names; direct keys
inside a section are variable names. The variable tool uses literal names, with nested
updates expressed through the object tool. Naming is approved: Call Variables,
grouped into sections, with each direct named value called a variable. Tools are
`read_variables`, `update_variables`, and `update_variable`.
An authorized read of unpopulated variables returns one `null` at the requested
value level, without constructing nested nulls or storing a default. The first
update populates the section, and later updates add data iteratively. Datatype
and supplied-value checks remain; required-variable completeness is not enforced
at setup or on updates.
Agent section access is read-only or read+write; write-only access is not
supported. Every writer can read that section, and omitted grants provide no
access. The write-only projection and error-handling proposals are withdrawn.
MCP result handling is also settled: the agent receives the remote tool result
and then updates Vxpipe's call variables through our tools. No MCP knowledge of
Vxpipe internals or automatic result-to-variable mapping is required.
G3's ownership and lifecycle are now settled: a dedicated room-scoped
`CallVariables` GenServer owns values, revisions, schemas, and section grants.
Variable tools call it directly, without routing through `RoomAuthority` or
checking whether the source agent is still active. Transfer shuts down the
source agent's entire execution subtree; already-submitted variable requests
may still finish under the normal permission, datatype, size, and revision checks.
Additional schema-depth/property-count limits are not adopted now; retain the
existing datatype and value-size limits without required-variable completeness.
G3 is resolved in documentation. G4's conversational-interruption rule is now
approved: interrupting speech does not express intent to cancel a submitted MCP
tool call, so let that call finish within its existing timeout without reviving
the interrupted output. Background tool execution uses the same application-level
acknowledgement and later-result approach for every model provider, rather than
selecting a provider-native async-tool workflow. A submitted MCP request that
times out without a definitive remote result is reported as outcome `unknown`,
not confirmed failure.
The tool executor must not automatically retry any failed invocation, including
known non-submission failures. For an ambiguous timeout, return the unknown
outcome to the agent. A later agent-requested call is a separate invocation,
not an internal retry or a guarantee against duplicate external actions.
Explicit per-invocation cancellation is deferred to
[a separate issue](../docs/issues/explicit-tool-call-cancellation.md) for later
review, not required for this slice. Its opt-in and generated-tool policy has
not been approved.
Late booking confirmations and similar notifications are external events for a
future gateway-to-active-room/agent communication mechanism, not a current MCP
timeout-reconciliation requirement. That scenario is deferred.
Generic platform-level confirmation is also out of scope for now. Agent
instructions handle conversational confirmation; any enforceable business
authorization belongs to the integrating application/MCP. Prompt instructions
are not a security guarantee, and Vxpipe still enforces tool access.
G5's call-level client tool visibility and explicitly full-visibility sample
calls are approved, with all tool events hidden when visibility is unspecified.
Per-tool overrides are approved, scoped to the participant definition key plus
its local configured tool key, with the call-wide default as fallback. Tool-history
storage always saves observed metadata, arguments/request payloads, and
responses/results/errors independently of visibility, excluding credentials/headers.
Variable history uses full post-update snapshots linked to the originating turn
and tool invocation, reusing saved tool arguments without a separate changeset.
The call record points to the latest persisted snapshot; the GenServer remains
the runtime owner. Database-backed updates return success only after the snapshot
and latest-pointer transaction commits. Retention periods use tenant overrides
over application settings, with retain forever as the application default.
Normal transaction errors return variable-save failure; no extra database-commit
reconciliation is required for this slice. Finite retention for completed calls
starts at `ended_at`; active calls are not expired and forever has no threshold.
Current application/tenant periods apply to all calls, past and future, without
per-call retention settings. Expiry deletes the entire call and all associated
Vxpipe-managed data, including the call record itself.
General voice/LLM-input redaction is deferred; deterministic collection such as
DTMF need not involve the LLM. First-message modes and first-activation-only
greetings are approved, as is source-agent responsibility until committed
handoff and failure return to that agent. R01–R05 from the latest review batch
are resolved. Same-call caller reconnection (R07) is deferred; replacement tokens
for eligible unstarted records remain supported. The focused gap review now lists
8 individual decisions still awaiting review, rather than counting its
background groups. R06 is resolved: another token does not supersede unused ones.
R08 now uses one prepare/token/join flow for all API clients; removing direct
WebSocket initialization supersedes R09's setup-limit question. Optional
call-level `opening_audio` allows capability warmup but gates participant audio
delivery and normal conversation until playback completes. R10 is already
covered by initial variables at call creation. R11/R12 leave personalization and
business-time context to application/agent instructions with permitted variable
reads and date/current-time tooling. R14 disallows all automatic executor retries,
R15 skips classification, and R16 defers retry/idempotency enhancements. R13 now
allows protected backend-initialized dial variables while model transfers remain
restricted to participant refs.
R20/R21 now use periodic cleanup sweeps: external call-owned objects first, then
database data, with definitive missing objects accepted and failed work retried
from retained records/references. The exact sweep interval is not selected.
R19 chooses application/tenant `call_retention` as `"forever"` or an explicit
seconds-duration object, without changing retention behavior or adding per-call policy.
R18 always stores complete observed tool history and permitted available transcripts, turn
details, usage/model/cost data, and committed variables. R38 qualifies media
retention independently from live sharing, without introducing usage/tool/variable
storage toggles. Audio requires explicitly enabled and permitted recording;
archival needs do not start STT or bypass capability permissions.
R17 defines `tool_visibility` and participant/local-tool `tool_visibility_overrides`,
including trusted full-visibility sample policy replacement with no overrides.
R22 selects `2026-07-28` Streamable HTTP; R23 requires validated outgoing MCP
arguments. R24 result/document inspection and R25 server-requested interactions
are deferred to separate issues while observed response storage remains mandatory.
R26 adopts SDK-aligned endpoint security at Vxpipe's outbound boundary. R27/R28
set configurable 30-second readiness and 15-second idle-notification defaults;
R29 leaves tool speech to instructions and defers wait music. R30 pins a 30-minute
default live-call limit with definition, tenant, then application precedence.
R31 leaves closing speech/hangup timing with agent instructions. R33–R35 define
call-level transfer defaults, destination acceptance, and a total attempt deadline.
R32 disconnects the attempted destination on configured provider machine detection;
unknown still requires explicit transfer acceptance within the existing deadline.
Leaving voicemail is deferred, not automatic speech or an entire-room hangup.
R36 allows exactly one bounded source-restoration attempt after failed transfer,
with detailed failure causes internal-only. R37 includes isolated pre-acceptance
human-destination briefing. R38 supersedes capability denial as primary privacy
control with presence-driven media publishing/subscription, live transcript sharing,
and separate transcript/audio retention, using approved `media_policy` and
participant `while_present` maps with intersected routes and false-wins storage.
R39 offers no API creation-idempotency feature; separate requests may create
separate records. R40 only recovers bookkeeping for existing work, never repeats
a crashed call or speculatively redials an uncertain one.
R44 retains usage observations and derives effective amounts without double
counting deltas, cumulative reports, estimates, finals, or corrections. R45 permits
call/participant/service-interval/turn attribution where honest and optional later
billing lookup by actual provider IDs. Pricing policy remains R46.
Approval of documentation does not authorize runtime implementation.

## Constraints

- Preserve the protocol-neutral call engine and keep client/provider protocols
  in adapters.
- Support both embedded Elixir use and a container controlled through a
  serialization-safe API.
- Start with typed data and a small set of runtime primitives.
- Do not allow a public definition to select arbitrary modules, functions, PIDs,
  or atoms.
- Keep definitions and invocations secret-free. Resolve credentials from a
  tenant-scoped store with an application-wide fallback into a private
  credential lease, and keep the value absent from resolved-plan equality,
  public snapshots, events, errors, and logs.
- Keep remote MCP integrations application-wide or tenant-scoped so endpoints,
  credentials, discovery, health, and limits are reusable across calls. Keep
  selected MCP and built-in tool bindings in each agent's unified `tools` map so
  a configured integration does not automatically affect every call or expose
  every operation to every agent. No separate agent integration-enablement map
  is required.
- Keep model decisions separate from authoritative room mutations.
- Defer an embedded scripting language until declarative primitives prove
  insufficient.

## Worktree baseline

The worktree already contained unrelated spoken-barge-in documentation changes.
They were left untouched. This file is the only path created for this research
checkpoint.

## Research method

Reviewed the existing local platform-research corpus and rechecked current
first-party documentation for two managed voice-agent control planes and two
programmable realtime-agent frameworks. The review focused on reusable agent
configuration, graph/flow configuration, multi-agent composition, handoffs,
tasks, context transfer, version selection, runtime overrides, and the boundary
between declarative builders and code-first frameworks.

The source products are intentionally not named in this labnote. Their product
models are treated as evidence, not as schemas to copy.

The remote-MCP follow-up also reviewed the official MCP `2026-07-28` tool,
Streamable HTTP, and schema specifications. That revision is stateless at the
HTTP protocol layer, permits the tool list to vary with request authorization,
and returns structured or unstructured content from `tools/call`. Those details
drive the profile binding, credential precedence, and discovery decisions below;
detailed result projection/inspection is now deferred as described in R24.

## Findings

### There is no single industry call-definition object

The reviewed systems expose overlapping but differently scoped resources:

- A reusable agent definition combines instructions, speech/model providers,
  tools, turn behavior, first-message behavior, limits, monitoring, and artifact
  policy. It may be stored by ID or supplied inline for one call.
- A multi-agent definition is commonly a set of agent members with one entry
  member and an allowlisted set of handoff destinations. Handoffs are usually
  model-selected tools, not unconditional graph edges.
- A conversation-flow definition is a graph of dialogue, deterministic action,
  branching, transfer, and terminal nodes joined by model-evaluated or
  deterministic conditions.
- Code-first frameworks separate the transport/session orchestrator from
  long-lived agents, short-lived typed tasks, side-effecting tools, and agent
  handoffs. Their visual/declarative builders cover only a portable subset and
  hand advanced behavior back to code.
- One pipeline-oriented framework has both a small flow layer and a separate
  multi-agent worker layer. Flow nodes manage task messages, functions,
  entry/exit actions, context strategy, and state. Workers own independent
  models, tools, context, activation, handoff, background jobs, and distribution.

The closest analogues to Vxpipe's desired object are therefore a multi-agent
manifest, a conversation graph, or executable session code. None cleanly unifies
portable call topology, multi-agent control, transport participants, telephony
legs, context policy, and artifact policy in one provider-neutral contract.

### The useful common primitives are smaller than a workflow language

Across the reviewed systems, the stable concepts are:

1. a session with an explicit lifecycle;
2. one currently active conversational agent per conversation lane;
3. agents with distinct instructions, models, voices, tools, and permissions;
4. typed, side-effecting tools;
5. typed session data separate from LLM chat history;
6. explicit activation or handoff to another agent;
7. a context-transfer decision at each handoff;
8. short-lived conversational tasks that return typed results;
9. deterministic lifecycle actions such as speak, collect, transfer, and end;
10. immutable published versions or pinned runtime snapshots; and
11. a runtime invocation carrying per-call variables and endpoint identities.

These identify the behaviors a useful call definition must compose. They do not
require arbitrary code, arbitrary expressions, parallel branches, or a large
node taxonomy in the initial authoring contract.

### Use a participant-first public authoring model

The common path across the reviewed systems is not a graph. It is one reusable
agent, or a named set of focused agents with one initial handler and explicit,
allowlisted participant handoffs. Graphs appear as a separate structured-flow
product or a code-level orchestration mechanism when deterministic sequencing
is actually needed.

The public `CallDefinition` should therefore be participant-first without
assuming an agent must own the room for its entire lifetime:

- `entry_caller` and `entry_receiver` string refs naming definition-local
  participants;
- shared capability-profile defaults;
- a map of every participant the room is allowed to materialize;
- agent participants with prompts, first-message behavior, capability overrides,
  selected tools, and direct transfer allowlists;
- human participants with any participant-specific, non-secret connection
  intent;
- typed call-variable schemas and matching per-call initial values; and
- bounded call policies and references to artifact/event policies.

The agent name in the definition is a stable logical role, not a PID, runtime
participant ID, or activation ID. Entering an agent creates a fresh activation
that owns conversational control. Re-entering the same agent may reuse its
private history according to policy, but stale work from an earlier activation
must still be rejected.

Both entry refs resolve within the same `participants` map, including the caller.
Each referenced definition determines the participant's kind and connection
intent. This permits an initially human-only call and a definition with no agent
participants. Neither entry field contains an inline participant definition.

### Entry participants and startup — approved G2 decisions

Replace the earlier single `entrypoint` field with two required string refs:

- `entry_caller` names the initial calling participant.
- `entry_receiver` names the initial receiving participant, human or agent.
- Both must name existing, different keys in `participants`. The caller remains
  in that catalog alongside receivers and possible transfer destinations.
- These refs describe the initial conversational roles, not the actor sending
  an HTTP request or the server issuing a carrier dial command. Connection
  configuration still determines whether to receive a connection or dial out.
- Transfers change live control/routing, not the pinned initial entry refs.
  There is no mutable "current receiver" hidden inside `entry_receiver`.

For the representative support definition, `entry_caller: "caller"` and
`entry_receiver: "reception"` select the two initial participants. Billing and
human support remain catalog entries available for later admission or transfer:

1. At live startup, establish the caller according to its connection intent.
   If call-level `opening_audio` is configured, play it through the minimal
   caller transport/file-playback path. Room/participant capabilities may start
   and warm up concurrently, but receive no user/participant audio until playback
   completes; normal conversation also waits. Otherwise prepare/admit the receiver
   normally according to its connection intent. Merely storing a prepared call and issuing a join
   token starts neither room nor participants. An agent receiver starts
   interacting only after any opening audio and required capability readiness.
2. Do not start every listed agent's providers or dial every listed human at
   room creation. The catalog defines possibilities, not current room membership.
3. An authorized transfer prepares its destination before committing control.
   A dial-out human destination is dialed when needed, and dialing alone does
   not establish that the person has joined.
4. A human receiver does not cause an implicit AI receiver to be created. If
   both initial participants are human, the call can begin without an AI agent.

Definition validation resolves and checks the two refs when parsing/saving the
definition. Admission pins the selected revision and resolved participant refs
in the call plan. Runtime orchestration uses that in-memory plan; it does not
scan participant definitions or re-query a mutable definition to discover the
caller. Explicit roles remove ambiguity even though avoiding a repeated loop
is not the main reason for this shape.

This resolves initial role identification and catalog-versus-startup behavior.
The subsequent cardinality decision below fixes one participant per definition
key per call. No runtime startup behavior or schema release was implemented by
these documentation decisions.

### Optional opening audio before entry reception — approved startup decision

`opening_audio` is an optional call-level setting, separate from participant
`first_message`. Its source may be a prerecorded audio-file URL (WAV or another
supported format) or fixed configured text rendered and cached as audio. Play it
to `entry_caller` before `entry_receiver` begins normal conversation. For example,
a fixed recording announcement can precede the receiving agent's greeting. It need not
be a recording notice: the option is not mandatory disclosure or a consent/
compliance guarantee. The option name and source choices are selected, not a
nested source schema, file-fetch mechanism, or audio-format matrix.

For fixed text, use the initial receiving agent's resolved TTS service and voice,
including its configured defaults, to create and cache the audio. Do not ask the
LLM to generate the opening text. Do not select the first map entry or activate
a later transfer agent merely to supply a voice. If no initial agent/usable TTS
exists, text-source applicability remains open; no implicit agent or fallback
voice is approved. This does not change human-only entry into an AI call.

The reusable cache identity includes exact configured text, resolved TTS provider,
model and voice, and relevant output-affecting settings, scoped to the tenant and
configured binding. Changing these inputs must not return stale audio. Keep
credentials out of keys/logs. Cache persistence, TTL/eviction, URL fetching, and
whether rendering happens during definition preparation or later are not chosen
here. Rendering prepares an asset without starting a call process tree or setting
`started_at`; it need not activate normal live providers. Shared reusable opening
assets are configuration assets, not call recordings/exports subject to deleting
that one call. No per-call cache retention policy is introduced.

Establish the caller connection and transport/file playback needed to deliver
the file. Room and participant capabilities may all initialize and warm up while
it plays. Gate audio delivery, not process startup: do not route audio from the
user or any other participant into those capabilities or normal conversational
media paths until playback completes. Transport receipt of packets is not
authorization to deliver them to STT, recording, or another consumer. Providers
being ready does not release this gate. Opening-text rendering and asset playback
are allowed; the agent's ordinary greeting/model conversation still wait until
completion under the existing first-message rule.

This decision does not authorize recording or retrospective replay of the blocked
participant-audio interval; no buffer/replay feature is introduced. Exact
buffering policy and text barge-in during opening playback are not selected here.
Downloading, rendering, caching, or merely enqueueing audio is not completed
playback, and failed/incomplete configured playback cannot silently open the
media-input gate.

If `opening_audio` is omitted, proceed with normal startup with no announcement
delay. After configured playback completes, admit normal audio delivery according
to the usual capability permissions and readiness rules, and apply the receiver's
first-message policy. Already-warmed capabilities need not be restarted.
This is initial call startup, not every agent activation or transfer. Notices
for later-joining participants, exact transport-specific completion evidence,
and playback failure behavior need separate design; no new mechanisms are
approved for them here. R11 separately leaves personalization to agent instructions
and permitted variable reads; fixed opening text introduces no interpolation engine.

Keep `started_at` tied to actual live-call start. Do not delay or reset it to
opening-audio completion or receiver activation. A room that has actually started
and is playing the file is already live even though normal conversation is gated.
This decision adds no runtime playback, endpoint, provider API, or schema release.

### First-message behavior — approved G7 decision

Each agent participant selects one of three behaviors for its first message:

- wait for input, without an unsolicited startup greeting;
- speak fixed greeting text; or
- generate a greeting using its normal permitted model context.

Apply the selection on that participant's first activation in the call, after any
configured opening audio and once required connections and capabilities are
ready. An inbound agent can welcome the caller immediately; an outbound agent
can wait for the recipient's hello.
The policy belongs to the agent participant, not a rule inferred from call
direction. It uses the existing first-message concept; exact JSON encoding is
not frozen by this decision and no implicit fallback mode is introduced here.

Reconnect and later reactivation of the same participant do not replay its
startup greeting. Another participant gets its own first activation, and another
call starts afresh. Returning agents may converse normally; this rule prevents
automatic greeting replay, not ordinary contextual speech. Greetings use normal
output and must respect current privacy permissions.

Voicemail-message delivery is deferred. Closing wording and when to invoke
existing hangup belong to agent instructions (R31).
There is no platform speak-then-end/closing-message API, mandatory playback-drain
deadline, or automatic pending-hangup cancellation on speech interruption.
Normal/immediate hangup and the hard-duration limit are unchanged; instructions
alone do not guarantee finished audio playback or add playout-aware hangup.
These modes and the timing policies below are approved designs, not behavior
newly implemented in the current playground.

### Startup, idle, tool waiting, and duration — approved R27–R30

Required provider/connection readiness has a configurable 30-second deadline
beginning with the actual admission/startup attempt after joining. Preparation
of a database record and token issuance/expiry do not run this clock. A definitive
terminal startup failure fails early; expiry aborts startup, releases resources,
and reports a clear failure. Deliberate `opening_audio` playback is not itself
failed readiness and is not truncated by a new 30-second audio rule. Preserve
the media-input gate and `started_at` at actual live start; pre-live failure must
not invent a start timestamp.

An agent genuinely waiting for caller input receives a configurable 15-second
idle notification. Its instructions determine whether to nudge, wait, or invoke
a permitted end-call tool; there is no automatic silence-based hangup default.
Opening playback, agent output, holding, dialing, and tool-wait do not count as
caller silence. Use conversation/media evidence appropriately without introducing
local VAD/models, repeated announcements, or an autonomous nudge cadence.
Human-only portions do not depend on an agent that no longer exists.

Long tools trigger no automatic periodic progress speech. The same agent's
instructions coordinate kickoff/result speech and regular conversation through
one voice while background work continues. Music for startup or long-tool waits
is [deferred](../docs/issues/wait-music.md); no wait-music option, playback feature,
or transfer-consultation behavior is approved now.

The whole live call defaults to 30 minutes (`1800000` ms), using
`limits.max_duration_ms`. Resolve an explicit call-definition value first, then
tenant settings, then application settings, then the platform default. Pin the
effective value in the resolved call plan; this differs from retention's current
policy for all calls. Later configuration edits do not change a live call's
limit. Measure from actual `started_at`, excluding prepared wait and never
resetting for transfers/recovery. The limit also covers human-only portions.
On expiry, the engine ends with a clear duration-limit reason. This adds no
creation-time override, unlimited mode, extra warning/grace policy, or closing-
speech guarantee. R31 keeps that conversational decision with agent instructions.

### Provider answering-machine detection — resolved R32

Use provider-supplied answering-machine/voicemail detection when supported and
configured for use; it is not mandatory on every call.
Both [Telnyx](https://developers.telnyx.com/docs/voice/programmable-voice/answering-machine-detection)
and [Twilio](https://www.twilio.com/docs/voice/answering-machine-detection) provide
that facility. Preserve provider provenance and unknown results; do not infer
human acceptance from STT/LLM output or add a local beep classifier. A provider's
human/machine classification is not explicit transfer acceptance.

When that detection reports a machine, disconnect the attempted outbound
destination leg. For a transfer, return a typed failure to the source and retain
the original caller/source conversation under normal permissions; do not hang up
the whole room. For an initial outbound call to its only remote human, end that
attempted leg/call without voicemail speech.

Unknown, disabled, or unavailable detection is neither machine nor human proof.
An unknown transfer continues awaiting explicit recipient acceptance within the
existing total 30-second attempt deadline, without resetting or extending it.
Classification is not an accuracy guarantee or a replacement for acceptance.
No local classifier, beep inference, provider tuning, or automatic message is added.
Leaving voicemail is [deferred for later review](../docs/issues/voicemail-message-delivery.md),
without reintroducing the rejected platform closing-speech workflow.

### One participant per definition key — approved G2 decision

Each participant definition key can identify at most one runtime participant in
a call. This applies to human and agent definitions, including both entry refs
and every transfer target. The same reusable definition may serve many calls;
each call has its own participants, never a shared cross-call identity.

For example, once one staff member is admitted as `human-support-agent`, a second
person cannot join that call under the same key. Reject the second admission
without replacing the first person's connection or sharing their participant
identity. A second staff role needs a different definition key, such as
`human-supervisor`; the rule does not limit the number of distinct human roles.

Where agent re-entry is permitted, it uses the bound participant with a fresh
activation, not a new instance of its definition. A disconnect or transfer does
not make the key available for a different person to take over. Same-call caller
reconnection is deferred for the initial slice; neither a definition key nor a
fresh join token proves that the same person is returning. First admission of
other eligible participants into a live call remains supported. After logical
call termination, connecting again starts a new call, not a resumed participant
in the old call. Temporary transport loss is not automatically that termination.

Admission and transfer preparation must enforce this invariant centrally,
including concurrent requests. Repeated work must not create another participant
or duplicate an already-pending dial/agent preparation. A transfer ref therefore
selects either the call's existing participant for that definition or its one
not-yet-admitted participant; no multi-instance selector is needed. Detailed
retry responses remain part of the pending admission/transfer protocols.

This is a fixed contract, not a new cardinality option in the call JSON. It
resolves G2's participant-count and duplicate-person ambiguity; it does not
authorize runtime implementation or define every reconnect/failure policy.

### Runtime participant and transfer identities

`Participant` is the room-level runtime identity. Its `kind` may be `human` or
`agent`. An agent in the call definition is reusable configuration; when the
room admits an instance of it, that instance is a participant with
`kind: agent`. A person working in a support role may be called an agent by the
surrounding business, but remains a participant with `kind: human` in the
engine's type system.

Transfer is an engine-owned platform tool derived from the active agent
participant definition's `transfers` list. Each entry directly names another
definition-local participant. That participant's definition says whether it is
human or agent and contains the trusted information needed to materialize it.

When an agent has no transfer possibilities, the compiler does not expose a
transfer tool. When it has one or more, the compiler exposes one platform
`transfer` tool whose destination argument is restricted to those participant
refs. The model may receive each allowed destination's safe description, but it
never receives arbitrary runtime participant IDs, telephone numbers, transport
destinations, or provider configuration.

The generated input schema is only the first guard. At invocation, the executor
checks that the source participant and activation are current and resolves the
chosen ref through that active agent's immutable transfer allowlist. A stale,
unknown, or other-agent destination is rejected before the room receives a
command. The room then validates and commits the actual control mutation.

### Track active control directly; do not introduce a graph

The room already has the state needed for participant transfers. The resolved
plan needs the two initial participant refs, named participant specs, and
resolved tool bindings, while the room tracks an optional active agent
participant and its fresh activation ID. For an agent receiver, the control
flow is:

```text
prepare/admit entry_caller and entry_receiver
  -> when the receiver is an agent, activate after connection/capability readiness
  -> the participant converses or requests an allowlisted transfer tool
  -> tool executor validates the target and asks the room to commit the transfer
  -> previous activation becomes stale
  -> resolve/admit the destination participant and commit control/routing
```

`active_agent_participant_id: nil` is a valid running-room state. A transfer can
move control from an agent participant, such as an intake agent, to a human
participant, such as a human service agent. It can leave two or more human
participants connected after the agent participant has been detached.
The room lifecycle is therefore determined by room/call disposition and
participant connections, not by whether an agent participant remains active.

The private plan must not become a second copy of room state. The room remains
authoritative for active control, participants, connections, media, turns,
tools, typed variables, and call legs. Provider requests and tool execution remain
concurrent supervised work.

If a concrete use case later requires guaranteed sequencing, deterministic
branching, waiting, joins, or compensation, design that use case independently.
Do not pre-install a node-and-edge execution model into `CallDefinition` or
`ResolvedCallPlan` merely because another product calls such behavior a flow.

This separation also avoids conflating three different concepts:

- a **tool** is a model-selectable typed operation available to an active agent;
- a **task** is a bounded conversational subroutine that returns typed data and
  then yields control; and
- a **workflow** is deterministic orchestration across conversational and
  non-conversational steps.

### Call variables are typed, sectioned, and permissioned

Call Variables is the name for the typed, structured values shared during a
call. They are grouped into sections: `booking` is a section and `status` is a
variable within it. Use "variable" consistently, not "field", for these named
values. A variable may contain an object or array; the name does not imply a
flat dictionary. Call variables remain owned by the room and survive agent
transfers, including periods when only humans remain.

Keep three concepts distinct:

- **Call variables:** shared structured values, with schemas, permissions, and
  revisions, separate from agents' private scratch state.
- **Conversation history:** messages and tool calls/results. A spoken transcript
  is a view of what participants said, not the mutable variable store.
- **Model context:** everything supplied to the LLM, including instructions,
  selected history, and the permitted projection of call variables.

The approved names in the unreleased definition candidate are:

| Surface | Name |
| --- | --- |
| Definition's section schemas | `call_variables.sections` |
| Invocation's initial values | `initial_variables` |
| Agent's section grants | `variable_permissions` |
| Read selected sections | `read_variables(sections)` |
| Merge several variables in a section | `update_variables(section_name, data)` |
| Set one direct variable | `update_variable(section_name, variable_name, value)` |

The planned room-scoped state owner is the `CallVariables` GenServer; the private
commands are `ReadCallVariables` and `UpdateCallVariables`, and the metadata-only
update event is `CallVariablesUpdated`. These names belong to the unreleased
candidate, not a runtime migration or a new schema release. The existing
`Tool.Context` execution metadata is a different concept and is not renamed.

The definition declares named top-level variable sections. Each section describes
an object schema, not initial values or defaults. Only an authorized call-setup
invocation prefills values, directly in that section structure; no separate
input schema, input-to-variables mapping, or default-merge layer is required.
Unprovided variables remain unfilled; variables may be collected over several
updates. Datatypes still have to match, but missing variables do not fail a
required-variable check. Supplied initial values and tool results can populate
variables without repeatedly extracting the same information from history.

The naming hierarchy is explicit: root keys in the variable data are section
names, and direct keys inside each section object are variable names. Any deeper
objects are nested data within that variable, not extra section names or a path
language. For example, `address` is a section and its direct `city` and
`postal_code` keys are variables. This describes the data supplied in
`initial_variables` and held by the room; it does not remove the call definition's
`call_variables.sections` schema wrapper or change revision metadata.

Each agent declares `variable_permissions` keyed by section name. The supported
grants are read-only or read+write:

- `["read"]` includes the section in the model-visible call-variable projection
  but does not permit updates;
- `["read", "write"]` permits reading and validated updates to that section; and
- an omitted section is neither visible nor writable.

Write access always includes read access. A standalone `["write"]` grant is
invalid at definition compilation; do not silently add a read grant or create
a write-only mode. This removes the need for a separate revision-only projection
or special write-only validation-error handling. The existing section boundary,
all-or-nothing read authorization, and privacy of ungranted sections remain.

Start with top-level section permissions rather than dot notation, wildcards,
or array indexing. This gives each section a clear schema, ownership, revision,
audit stream, and atomic update boundary. If variable-level grants become necessary,
use unambiguous JSON Pointer paths in a later dated schema rather than inventing
dot-path escaping rules.

Authoring guidance: keep variables simple and shallow where practical. For example,
make `address` a section containing `city` and `postal_code`, rather than burying
it under several objects in another section. The section can then have its own
schema, permissions, and revision boundary. This is guidance for integrating
applications and definition authors, not a ban on nested objects or an automatic
flattening step. When nesting is useful, object updates must preserve omitted
nested variables through recursive merging.

An agent never mutates the map directly. Read grants cause the engine to offer
the read tool; read+write grants also enable the update tools. Each tool is
constrained to that agent's granted sections.
The variables process validates the target room incarnation, trusted agent
participant identity, section permission, expected section revision, update
bounds, and the resulting section's populated values against its schema before
applying an update and emitting its event. It does not check current agent
activation or consult the room authority. Schema checks do not require missing
variables to be filled first.
MCP results do not update call variables implicitly. The agent calls the remote
MCP tool, receives its result, then calls `update_variables` or `update_variable`
to save the relevant data. For example, it calls a booking tool, receives a
confirmation, and updates variables in the `booking` section. It needs read+write
permission on that section; read-only sections remain read-only.

The remote MCP need not know anything about Vxpipe, room state, or our variable
tools. Vxpipe owns the variables and authorizes the agent's separate update.
There is no automatic mapping layer or platform-only result section required
for this flow. The external service remains responsible for its booking and
verification rules; a copied result in our variables is not the service's source
of truth. Submitted MCP calls survive ordinary conversational interruption as
approved below; other external-operation retry/cancellation questions remain
under G4 review.

One `CallVariables` GenServer per room incarnation is the sole runtime owner of
mutable values and revisions. It holds the compiled variable schemas and
per-agent grants from the pinned resolved plan, and serializes its own reads,
merges, validation, and commits. `RoomAuthority` retains the pinned plan and
participant/lifecycle orchestration, not a second mutable variables map.
The variables process lives under the room supervisor, outside each agent's
execution subtree, so transfers and human-only periods do not destroy it.
Large documents, media, and tool artifacts live elsewhere and appear in variables
only as bounded references.

A platform variable tool runs in the supervised model/tool request process and
makes a bounded `GenServer.call` directly to `CallVariables`. Neither the request
nor the authorization/commit passes through `RoomAuthority`. The engine-private
tool context supplies the room/incarnation and trusted agent participant identity;
activation, command, correlation, and tool-call IDs remain attribution metadata,
not a current-activation condition for variable access. The model supplies only
the requested read or mutation, never its identity or permission claims.

A committed transfer terminates the source agent's whole execution subtree, including its
capabilities and model/tool workers. Once shutdown completes it cannot issue new
requests. An update already sent to `CallVariables` is not retracted by caller
termination and may commit afterwards. The variables process needs no activation
mirror, deactivation notification, or per-operation room-authority round trip.
It never executes model/provider or remote MCP tool work. For database-backed
updates it waits on a configured snapshot-persistence port before publishing
new values or returning success; the adapter owns SQL/Ecto. Calls remain bounded
and return typed unavailable/timeout results; a timeout or lost reply does not
prove an already-submitted update was cancelled or a transaction rolled back.

At the start of an agent turn, the model/tool worker obtains an immutable
projection directly from `CallVariables` using its trusted identity and grants.
Granted sections include their value and revision, including
every section the agent can update. Ungranted sections expose neither values nor
revision metadata. Model inference inserts this projection as a transient
engine-owned variable message; it is regenerated for each turn and is not appended
to private conversation history. A read tool can
refresh the projection during a multi-round tool loop if another authorized
actor has changed it.

A participant-transfer packet is an immutable projection of allowed call-variable
sections plus the selected spoken-history policy. It names the concrete source
and destination participant identities and kinds, reason, causation, and
visibility. When an agent participant is the destination, its projection is
further constrained by that agent definition's variable permissions. It is an
event/result, not a second mutable variables bag. Client and human-participant
access to call variables uses separate authenticated permissions rather than
inheriting an agent definition's grants.

### Working call-variable schema candidate

There is now enough agreement to implement a dated schema. The next candidate is
`20260906.02`; it supersedes the earlier `20260906.01` discussion shape by using
one participant catalog and direct participant refs for entry and transfer. The
call-variable portion is:

```json
{
  "schema_version": "20260906.02",
  "entry_caller": "caller",
  "entry_receiver": "reception",
  "call_variables": {
    "sections": {
      "customer": {
        "schema": {
          "type": "object",
          "properties": {
            "id": {"type": "string", "minLength": 1}
          },
          "additionalProperties": false
        }
      },
      "intake": {
        "schema": {
          "type": "object",
          "properties": {
            "summary": {"type": "string"},
            "topic": {"type": "string"}
          },
          "additionalProperties": false
        }
      }
    }
  },
  "participants": {
    "caller": {
      "type": "human",
      "connection": {
        "service": "web",
        "mode": "receive",
        "admission": "start_call"
      }
    },
    "reception": {
      "type": "agent",
      "variable_permissions": {
        "customer": ["read"],
        "intake": ["read", "write"]
      },
      "transfers": ["billing", "human-support-agent"]
    },
    "billing": {
      "type": "agent",
      "description": "Handles billing questions.",
      "variable_permissions": {
        "customer": ["read"],
        "intake": ["read"]
      },
      "transfers": []
    },
    "human-support-agent": {
      "type": "human",
      "description": "A human support participant.",
      "connection": {
        "service": "configured-telephony-service",
        "mode": "dial",
        "number": "+1234123412"
      }
    }
  }
}
```

The schema fields and runtime values have distinct jobs:

- `call_variables.sections` defines the only legal top-level sections and the
  shape of each section. The initial version requires every section root to be
  an object.
- `CallInvocation.initial_variables` supplies values by declared section name,
  matching these schemas directly. It replaces the earlier `input_schema` and
  `call_variables.initialization` mapping. For example, the caller supplies
  `customer: {id: "customer-456"}`, not a separate `customer_id` input to map.
- Variables have no default values, at either section or nested schema-property
  level. The definition describes shape and permissions only; reject variable
  `default` declarations rather than using or silently ignoring them. There is
  no merge precedence to specify. This does not remove capability/provider
  configuration defaults elsewhere in the call definition.
- Validate the datatypes and schema constraints of supplied initial values
  before room/provider startup, not required-variable completeness. Missing
  `customer.id` or another unfilled variable does not fail variable validation.
  No dummy value, coercion, or schema default fills a missing variable. Omitted
  variables/sections stay unfilled in storage, rather than receiving automatic
  `{}`, `null`, or other values. Explicitly supplied empty section objects are
  allowed; their variables can be collected later.
  The invocation example prefills `customer.id` only; `intake` has no initial
  value. Later authorized variable updates are still supported.
- Admission initializes variables independently of agent write grants. Both
  agents can read `customer`, but neither can change it through variable tools.
- `variable_permissions` is present only on agent participants and refers only
  to declared top-level sections. It does not control client or human access.
- Application configuration supplies hard limits for total variable bytes,
  section bytes, update bytes, and operations per update. A definition may
  lower those limits but cannot raise them.

Do not add schema-depth or declared-variable-count limits now. There is no
measured schema-size threshold or observed validation bottleneck behind that
earlier proposal. Keep the existing datatype, supplied-value, byte, and operation
checks; schema declaration count alone is not the amount of populated data an
update must validate. Additional complexity caps can be reconsidered if evidence
justifies them, not as a prerequisite for this slice.

The `schema` objects use a closed Vxpipe-supported subset of JSON Schema-shaped
keywords. The initial subset should cover object, string, boolean, integer,
number, explicit nullable variable types, arrays as replaceable values, properties,
enums, bounded strings/arrays/numbers, and
`additionalProperties: false`. The dated
Vxpipe schema defines exactly which keywords work; accepting this shape must not
claim support for arbitrary JSON Schema vocabularies, references, or executable
formats. Required-variable presence is not part of variable validation: check the
values that are populated, including their datatypes, without demanding a
complete object at any nesting depth. Both setup and later updates permit
partial variables. The examples omit `required` declarations; there is no
separate final-completeness check or new validation mode in this decision.

Nullability is explicit: an absent variable is not the same as a populated null.
The variable's datatype still decides whether an explicitly supplied `null` is an
allowed value. A nullable variable can be cleared while retaining its key; a
non-nullable variable rejects an explicit null. An absent section may be represented
by null in a read response without storing a null section or violating its object
type. No variable gains an automatic null default, and populated section roots
remain objects.

Each runtime section has independent revision state:

```text
CallVariables
├── global_revision
└── sections
    ├── customer -> value + revision
    └── intake   -> value + revision
```

The global revision supports snapshots and event correlation. The section
revision is the optimistic-concurrency token used by tools. Independent sections
can change without causing unrelated updates to conflict.
Declarations and revision metadata do not themselves populate section values.
Reads of unfilled sections return null as described below; the read does not
populate state or advance a revision. Their existing revision metadata still
lets an authorized writer submit its first update with the normal concurrency
check.

### Platform variable tool contracts

The compiler adds a read tool when an active agent has at least one read grant,
and object-level and single-variable update tools when it has at least one write
grant. Authors do not list these platform tools in the agent's general `tools`
map. The generated tool schemas describe the permitted sections and their data
shape, with closed section enums derived from that agent's grants.
Variable update argument schemas must allow partial data objects too, rather
than reintroducing required variables before the variables process receives them.
The read tool is named `read_variables`; the approved update names appear below.

The read request and result are shaped as follows:

```json
{
  "sections": ["customer", "intake"]
}
```

```json
{
  "global_revision": 4,
  "sections": {
    "customer": {"revision": 1, "value": {"id": "customer-456"}},
    "intake": {"revision": 3, "value": {"topic": "billing"}}
  }
}
```

Read authorization is all-or-nothing. `CallVariables` checks every requested
section against the trusted agent participant's read grants, even though the
agent is already informed of the permitted sections. If any requested section is
forbidden, return a permission error and no variable values, including values
from otherwise permitted sections in that request. Do not silently ignore the
forbidden names. The agent can correct its request and retry with permitted
sections only. A successful read returns only the sections requested, not every
readable section. Empty, unknown, expired, wrong-incarnation, malformed, or
oversized requests still return typed errors without values. Agent shutdown does
not invalidate an already-submitted request. Errors must not disclose hidden values.

#### Missing reads and incremental population — approved G3 decision

After authorization, an unpopulated requested section returns `value: null` in
its normal section result, alongside revision metadata. Return null only at the
requested value level: an unset `address` does not become an object containing
`city: null`, `postal_code: null`, or recursively generated placeholders. If
`address` already contains only `city`, reading the section returns that partial
object without adding `postal_code`. The current read tool requests sections;
this does not introduce a nested-variable read API.

This is a read representation of absence, not a stored default, a mutation, or
permission to read forbidden sections. A forbidden section still fails the
whole request; an unknown section still receives the existing typed error.
Reads neither create a value nor change revisions.

The first `update_variables` on a declared but unpopulated section creates its
value from the supplied object. Later updates use the same recursive merge.
The variable-update form can likewise populate its declared direct variable in an
unfilled section. Both keep the normal grants, room identity, revision, datatype,
and size checks. No other variables or nested placeholders are materialized.

For example, an `address` section declares string variables `city` and `postal_code`:

1. With no supplied address, reading it returns null at the section value level.
2. `update_variables("address", {"city": "Newtown"})` stores just the city.
3. `update_variables("address", {"postal_code": "12345"})` adds the postal code
   while retaining the city.
4. Supplying a number for either string variable fails datatype validation without
   changing data or revisions, including when other variables in that update match.

Required-variable completeness checks are deferred, at setup and at every nesting
depth of an update. Datatype/schema checks for populated values are not removed.
This supersedes the earlier requirement to reject missing variables before
startup or demand a complete schema-valid object on every write. It does not
weaken call-definition validation, entry refs, tool argument envelopes, or
authentication. Variables can be incomplete without authorizing an external tool
to omit that tool's own required arguments.

The approved update surface offers both forms:

```text
update_variables(section_name, data)
update_variable(section_name, variable_name, value)
```

The object form accepts multiple variables in one tool call; the variable form offers
a focused single-variable change. Both use one atomic section update and the same
authorization, schema, limits, and expected-revision checks. These are interface
sketches, not complete wire schemas: they omit revision and engine-private
execution metadata for brevity. A variable-update convenience does not introduce
variable-level permissions; the existing section write grant still governs it.

Approved addressing: `section_name` selects one exact declared root section,
and `variable_name` selects one exact schema-declared direct key in that section.
`update_variable` does not split dots, parse JSON Pointers, or interpret
array-index notation. A name with no matching direct variable fails validation;
the tool never creates or traverses a nested path from it. If a schema permits
a literal key containing punctuation, it still names only that exact key.

For example, `update_variable("address", "city", "Newtown")` addresses a
direct variable. For a section containing a nested address, use
`update_variables("profile", {"address": {"city": "Newtown"}})` instead. The
object form deep-merges that data and retains omitted nested values; deeper
updates need no additional path syntax or tool. Both forms keep the same
section permission, validation, and revision boundary.

Approved object-update behavior: `update_variables(section_name, data)` recursively
merges supplied objects into that section's existing data. Where both old and
incoming values are objects, merge their variables recursively instead of replacing
the old object wholesale. Supplied variables add or update schema-permitted values;
omitted variables keep their current values at every object depth. The tool does
not replace the entire section with the submitted object, and omission is not
deletion. One call can change several variables atomically. This is a deep merge;
a deep copy alone duplicates a value without defining how updates combine.

For example, updating only `topic` preserves the existing `summary`. These labels
illustrate the merge; they are not a new request/response envelope:

```json
{
  "section": "intake",
  "before": {"summary": "Needs a billing review", "topic": "billing"},
  "data": {"topic": "delivery"},
  "after": {"summary": "Needs a billing review", "topic": "delivery"}
}
```

The variables process checks the expected revision, merges into a copy, and validates
the populated values in the resulting section, including retained variables,
before committing. Missing variables are allowed, not merely variables already stored
but omitted from the update. Invalid supplied variables, an invalid merged result,
a permission failure, or a revision conflict leave the whole section and
revisions unchanged.
This merges existing runtime data, not definition defaults into initial variables;
the supplied-only initialization rule is unchanged.

If a schema permits an address nested inside a section, changing only its city
also preserves its postal code. This is another merge illustration, not a new
wire envelope or a requirement to nest addresses:

```json
{
  "before": {"address": {"city": "Oldtown", "postal_code": "12345"}},
  "data": {"address": {"city": "Newtown"}},
  "after": {"address": {"city": "Newtown", "postal_code": "12345"}}
}
```

The preferred shallow alternative is an `address` section: the author can then
use `update_variables("address", {"city": "Newtown"})`, retaining its postal code
under the same merge rule. No existing schema example is automatically flattened.

Approved clearing behavior: an explicit `null` sets a variable's value to null;
it does not remove the key. Both `update_variable("address", "apartment",
null)` and `update_variables("address", {"apartment": null})` express the same
clear operation when the address schema permits a nullable apartment variable.
Omitting `apartment` instead preserves its previous value.

For such a nullable variable, the result is (illustrative values, not a wire envelope):

```json
{
  "section": "address",
  "before": {"city": "Newtown", "apartment": "4B"},
  "data": {"apartment": null},
  "after": {"city": "Newtown", "apartment": null}
}
```

During deep merge, an explicitly supplied null is an assigned value, not a
request to recurse into the old value, skip the update, or delete the variable.
Populated values must still validate: clearing a non-nullable variable rejects
the entire update without changing values or revisions. The existing permission
and expected-revision checks apply to clears too. Unfilled variables are not
automatically materialized as null, and a section root cannot be cleared to null
because section roots must be objects.

Separate variable-deletion tools and physical key removal are deferred. There is
no null-means-delete convention or new array-element merge operation.
Addressing is settled: section keys select root
objects, variable names select direct keys, and partial nested updates use the
object tool. The earlier mutation list remains a possible internal representation.

The existing internal command candidate below can represent a bounded atomic
section update; the exact lowering from the two tools must preserve the approved
recursive merge, explicit-null assignment, and literal-variable behavior. It is
not a third model-facing update tool:

```json
{
  "section": "intake",
  "expected_revision": 3,
  "changes": [
    {"op": "set", "path": "/summary", "value": "Needs a billing review"},
    {"op": "set", "path": "/topic", "value": "billing"}
  ]
}
```

Paths in this internal candidate are RFC 6901 JSON Pointers relative to the
selected section, not model-facing variable names. If this representation is used,
the binding must encode each literal variable name as one path component rather
than interpreting its punctuation as traversal. The initial
mutation language for these tools uses bounded `set` operations, including
explicit null assignment. The earlier `remove` operation is deferred along with
physical variable deletion. Arrays are replaced as values rather than edited by
index. An empty path may replace the complete section object. This is deliberately not full JSON
Patch. An internal whole-section replacement must not turn `update_variables`
into replacement of the section by its partial input: the merged candidate
must preserve omitted variables at every object depth. The variables process applies all
changes to a copy, checks populated values without required-variable completeness,
then commits all of them or none of them. In database-backed mode, it first
requires the candidate snapshot/latest-pointer transaction to commit before
adopting the new values/revisions or returning success.

A successful result always returns the section name, new section revision,
new global revision, and resulting value to the authorized agent: every writer
has read access to that section. An authorized revision conflict returns the
current revision; the agent can refresh the value with the read tool. Errors
must not disclose ungranted sections or private execution data. Invalid paths,
oversized changes, a failed resulting schema, an expired deadline, wrong
incarnation, and missing permission do not change the variables or revisions.

The public `CallVariablesUpdated` event contains section name, changed paths,
revisions, source participant and activation, tool-call/correlation identity,
and outcome. It does not broadcast the new value. Retained update history uses a
separate private full snapshot committed with the update and linked to its turn/tool
invocation; it does not add full values to this public event or to the agent's
tool result. The persistence section specifies its latest-snapshot pointer.
Acknowledged updates require committed snapshots; full room recovery remains a
separate contract.

### Tools and authoritative control must remain separate

Model-facing tools are the common request mechanism for participant transfer,
hangup, data collection, and external actions. The model can request an
operation; it must not directly change the active agent participant, connection,
leg, or room state.

An engine-owned tool invocation should therefore have:

- stable invocation and correlation IDs;
- an input and output schema;
- source participant identity and optional agent activation/turn identity;
- grants and an optional approval policy;
- deadline, cancellation, retry, and idempotency policy;
- progress plus one terminal result;
- result visibility to the model, room, clients, and artifacts; and
- an authoritative command emitted only after validation succeeds.

A participant-control transfer, a telephony-leg transfer, and ending a call
remain different commands even if all are exposed to a model as tools. Agent to
agent and agent to human are variants of participant-control transfer, not
separate top-level runtime identity models.

### Participant presence constrains the capability topology

**Approved R38:** normal call-wide settings live in `media_policy`; a participant's
optional `while_present` adds room-wide restrictions while it is authoritatively
admitted. Both use `audio_routes`, `transcript_routes`, `record_audio`, and
`save_transcripts`. Public policy controls media publishing/subscription, live
transcript sharing, and independent transcript/audio retention, not STT/TTS
capability-denial selectors. Call Variables and their permissions/transaction
boundary remain unchanged.

This approved fragment omits connection details, entry refs, and other required
definition fields; it is not a complete deployable definition or implemented runtime:

```json
{
  "participants": {
    "caller": {"type": "human"},
    "intake": {"type": "agent", "transfers": ["specialist"]},
    "specialist": {
      "type": "human",
      "while_present": {
        "audio_routes": {
          "caller": ["specialist"],
          "specialist": ["caller"]
        },
        "transcript_routes": {
          "caller": ["caller", "specialist"],
          "specialist": ["caller", "specialist"]
        },
        "record_audio": false,
        "save_transcripts": false
      }
    }
  }
}
```

Each route map uses definition participant keys, for humans and agents alike.
`audio_routes` maps each permitted publisher to its recipient array. An explicit
map is a complete allowlist: only its listed sources may publish room audio, and
only its listed recipients receive that source. An empty recipient array gives
no other participant access. There are no implicit self-loops or full-room monitor
grants. `transcript_routes` separately maps a speech-source participant to live
derived-transcript recipients; explicit self entries are allowed. No wildcards,
role selectors, dot paths, expressions, or new override matrix are introduced.

An omitted field adds no restriction/inherits normal policy; an explicit empty
route map permits no routes. Do not deep-merge maps and preserve unlisted routes.
Intersect source-publisher permissions and recipient routes across normal policy
and all present contributions, subject to host/application authorization as a
ceiling. No participant may loosen another's restrictions. For storage booleans,
false wins. Leaving removes only that participant's contribution; remaining
restrictions stay effective. A mere transport disconnect does not clear
authoritative presence or reset work.

`record_audio` and `save_transcripts` are separate room-wide booleans initially,
not per-source capture overrides. Composable examples:

- `"while_present": {"record_audio": false}` changes audio recording permission
  only, leaving normal transcript routes/storage unchanged.
- `"while_present": {"record_audio": false, "save_transcripts": false}` restricts
  both storage paths without disabling authorized live transcript sharing.
- `"while_present": {"transcript_routes": {}, "record_audio": false, "save_transcripts": false}`
  allows neither live transcript delivery nor transcript/audio storage.

False applies to the current interval. Audio prohibition covers Vxpipe-owned
individual tracks, full mixes, and recording derivatives; transcript prohibition
covers automatic stored transcripts and copies through archival/log/export paths.
Automatic model-debug archives must not copy denied transcript content. Previously
permitted intake history is not deleted retroactively, and whole-call retention
cleanup is unchanged. The booleans permit capture/storage, not a new `call_retention`
duration or clock. Automatic paths honor the source interval even when processed
later. Complete observed tool history retains its privacy and
credential/header exclusions. This does not add generic sensitive-data redaction
or taint tracking for arbitrary externally copied text, guarantee control of
independent provider/client copies, or claim universal compliance.

These are permissions, not commands to enable unconfigured recording/STT or activate
all catalog participants. Live transcription sends audio to a provider; no storage
does not mean no processing. If neither a permitted live transcript recipient nor
a permitted storage consumer needs recognition, the engine stops those STT flows.
Configured capabilities remain internal implementations, not the public privacy
control. Unfilled variables, datatype checks, section grants, and snapshots are
unchanged.

During private preparation the destination receives only authorized briefing/
configured notice through the isolated transfer lane; the caller cannot hear it.
The destination is not yet admitted to the main conversation. Phone/web acceptance
stays bound to the pending attempt. At authoritative commit, apply `while_present`
restrictions before connecting main media, then hand off/terminate the source.
This uses the existing preparation phase, not global publishing of the briefing,
a new workflow graph, or general concurrent-agent consultation. The total transfer
deadline, late-acceptance handling, and bounded source restoration still apply.

`RoomAuthority` authorizes the pinned resolved policy/topology. Enforce it at
mixing, media-route, transcript-projection, recording, and archive boundaries,
not by frontend muting or database lookup per packet. Fail closed if policy cannot
apply before commit. New delivery, queued/late old output, reactivation, and
retrospective replay must not bypass the restricted interval.

The denial-specific paragraphs and selector example below are retained only as
superseded history, not current schema/validation requirements. The approved
policy above replaces them while retaining the transfer/media invariants.

#### Superseded capability-denial candidate

Capability denials belong to participant and room policy, not to each transfer
path. A participant carries an immutable, resolved `presence_policy` that
applies while it is admitted to the room's media topology. The policy comes from
trusted application or tenant destination configuration for a human participant
and from the resolved agent definition for an agent participant; it is never
supplied by an attaching client.

Positive capability intent remains in the resolved call and active-agent plans:
these say which capabilities should normally run. A presence policy only lists
capabilities that are not allowed. The room derives lifecycle actions such as
cancel, stop, or later restart from that declarative denial instead of exposing
runtime states in the policy schema.

The room computes its effective capability topology by filtering the normal
intent through room/application policy and every applicable participant denial.
Denials accumulate and always win. An activation or proposed topology that
requires a denied capability cannot commit.

The policy owner and the affected participants are separate dimensions:

- `applies_while: admitted` means the owner contributes the policy while it is
  authoritatively present in the media topology;
- `applies_while: active_agent` means an agent participant contributes it only
  while it owns conversational control; this trigger is invalid for a human
  participant; and
- each denial's `participants` field is a non-empty list of selectors whose
  matches are unioned. The initial schema supports only `type: all` and
  `type: agent`; an agent selector also carries its definition-local agent
  `ref`.

For example, this denies a capability to the `xyz` and `abc` agent participants
even when the room contains four participants:

```json
{
  "participants": [
    {"type": "agent", "ref": "xyz"},
    {"type": "agent", "ref": "abc"}
  ]
}
```

Selectors are resolved to runtime participant IDs against the proposed room
topology before enforcement. Duplicate matches are harmless and are normalized
to one ID. `{"type": "all"}` must be the list's only entry because combining it
with agent selectors is redundant.

Selecting individual human participants, a human kind, a participant
destination, `self`, or arbitrary runtime participant IDs is deliberately
deferred. Their identity and lifecycle requirements should be designed with the
first concrete use case rather than added speculatively. `active` must not mean
“currently speaking”; Vxpipe does not infer policy activation from voice
activity.

This makes a rule such as “while this human service participant is present, no
participant in the room may use speech recognition or synthesis” a property of
that participant's trusted destination policy. Every transfer to that
destination inherits the rule without repeating it. Conversely, an active agent
participant obtains its positive capability intent from its agent definition.

The room recomputes the effective capability state whenever its authoritative
participant set or active agent participant changes. A connection loss alone
must not remove a presence policy; the room must detach or expire that
participant through an explicit lifecycle decision first. When the last
participant imposing a denial leaves, the room reconciles back toward the normal
resolved capability intent. This does not start every known capability
indiscriminately: only capabilities enabled by the call and current agent plans
resume, and any remaining participant or room denial still applies.

#### Retained transfer and media enforcement invariants

A transfer request names an allowed target from the source participant's
`transfers` list. Shared defaults belong to call-level `transfer_policy`, while
destination-specific connection/acceptance requirements stay with the destination.
The private destination briefing is in initial scope under R37; broader concurrent
consultation/history choices are not implied. There are no named transfer objects
or source/per-pair defaults. The room authority runs prepare and commit phases,
keeping destination briefing isolated from caller conversation before acceptance.
It resolves destination requirements and the proposed media/transcript policy,
enforces authorized routes/capture, and makes permitted required capabilities
ready. R38 applies the destination's `while_present` at commit before main-media
connection, after its isolated preparation/acceptance.
Only then does the room atomically admit or
activate the destination, change control/routing, apply the source disposition,
and emit `transfer.completed`. For an agent source, successful handoff terminates
its execution subtree under the approved lifecycle below.

The initial `CallDefinition` therefore has no generic `on_success` field. Host
code can observe `transfer.completed`, and a later deterministic workflow can
model an explicit next action if a real use case requires one. Neither is part
of the transfer's safety-critical commit transaction.

Enforcing privacy is a commit barrier, not best-effort cleanup. Unauthorized media,
derived transcript data, and capture must not pass through queued/in-flight work,
late output, or reactivation. A later policy change cannot retrospectively replay
or transcribe a restricted interval. Failed enforcement follows the transfer's
failure policy without exposing the proposed bridge. The source remains responsible
until commit, and acceptance alone cannot disclose full room media.

Recording, live transcript sharing, and transcript/audio retention are independent
approved permissions, not consequences inferred merely from a provider's
process being present or stopped. Preserve the opening-audio media-input gate and
actual-start clocks. Implement the approved media/retention policy above, not the
historical denial selectors; this checkpoint changes documentation only.

### Transfer success and failure — approved G8 baseline

Until the destination is ready and the transfer successfully commits, the source
agent retains conversational responsibility. The room and its supervisor do not
change owners: `RoomAuthority` still authorizes and commits the transfer. Do not
terminate the source merely because its transfer tool was invoked, a destination
is dialing, or an attempt failed.

If human support is busy or does not answer, return a typed failure to the source
agent through the existing invocation/result path. The source can explain the
failure and choose its next permitted action: continue helping, offer a different
allowed destination, or end the call using its available tools. The caller is not
abandoned and the platform does not silently choose a different destination.
Only a successful committed handoff emits `transfer.completed` and terminates
the source's entire execution subtree, including capabilities and model/tool
workers. A variable request already submitted to the separate variables process
may still finish under the existing rules; local shutdown is not remote rollback.

Current privacy permissions still apply during preparation and failure handling.
Keeping the source responsible does not permit forbidden processing or guarantee
speech if a safety constraint prevents it.

**Approved R36 restoration:** exactly one bounded attempt may restore permitted
source capabilities after a failed transfer. Supervisor/application restart or
retry loops must not reset that one-attempt budget. If it fails and no usable
conversation remains, end the call. An already working, valid human conversation
can continue. The detailed failure reason is stored internally, never communicated
to the end user through speech, client events, or tool-debug UI; agent/public
outcomes are generic without cause/provider details, even for samples/full tool
visibility. Existing permissions and whole-call duration continue to apply.
This restores capabilities within a still-live call, not a crashed call runtime.

**Approved R37 private briefing:** caller speaks with intake, then an outbound
human support destination privately hears who is calling and the purpose, plus an
optional recording notice, before press-1 acceptance and bridge. Caller audio must
not include that destination briefing. Web follows the analogous client-owned,
authenticated acceptance flow. Share only permitted minimum-necessary variables/
history, not the entire transcript by implication. Source TTS uses the agent voice
when applicable and permitted; no new voice selection/configuration format is fixed.
Source responsibility continues until commit, and acceptance alone does not admit
full room media. This is not a universal compliance claim or general concurrent-agent
consultation. R38 supplies the approved policy/commit boundary above;
do not count the approved initial-scope choice as pending again under R37.

**Approved R33 configuration boundary:** `transfer_policy` is call-level shared
defaults. Source `transfers: [allowed participant refs]` remains a simple list;
destination-specific connection and acceptance requirements belong to that
participant. No named transfers, graph, source-default/per-pair override machinery,
or extra frozen policy enums/options are added initially.

**Approved R34 readiness/acceptance:** an agent destination needs conversation
readiness and its required capabilities. A human destination needs usable media
and explicit acceptance. For a phone leg, use deterministic press-1 DTMF associated
with that pending destination leg, never inferred STT/LLM agreement. For web,
the client handles presentation and user interaction and sends an authenticated
message that the transfer is accepted; the platform does not mandate/build a
button UI.

Bind acceptance server-side to the destination participant/connection and current
pending transfer attempt. Caller/source/model assertions cannot accept for that
destination. Stale or duplicate acceptance cannot commit a transfer twice or
accept a different attempt. This is a protocol-neutral/internal adapter control
contract, not a claim about an RTVI core standard field. Merely connecting the
destination transport does not admit full conversational media or disclose private
data. Source responsibility and target-presence capability barriers remain until
the room commits the handoff.

**Approved R35 total deadline:** the call-level `transfer_policy` has a configurable
30-second total attempt deadline from acceptance of the preparation request.
Preparation, dialing, and acceptance share that one interval; phases do not each
restart it. Busy/no-answer or other definitive failure ends the attempt earlier.
On failure/timeout, stop the destination attempt, return its typed outcome, and
let the source continue when permitted. A late answer/acceptance cannot commit an
expired attempt; cleanup targets its exact mapped leg without automatic redial.
This is separate from startup readiness and the whole-call duration clock and
does not promise certainty about remote effects or add a durable recovery framework.

### Keep telephony provider-neutral and pin the resolved definition in the room

The Telnyx integration review refined the participant model. This section
supersedes the earlier split in this labnote between inline agent definitions
and externally configured participant destinations. A call definition should
contain every potential participant in one definition-local participant map,
whether that participant is an agent or a human. The map is a catalog of what
the room may materialize during this call; it is not a claim that every entry is
connected when the room starts.

A human participant may carry participant-specific, non-secret connection
intent in the definition. For example, a human support participant may name the
telephony service, a telephone number, and whether Vxpipe must originate or
receive the provider connection:

```json
{
  "participants": {
    "caller": {
      "type": "human",
      "connection": {
        "service": "telnyx",
        "mode": "receive",
        "number": "+15550001000",
        "admission": "start_call"
      }
    },
    "reception": {
      "type": "agent",
      "transfers": ["xyz", "abc", "human-support-agent"]
    },
    "human-support-agent": {
      "type": "human",
      "connection": {
        "service": "telnyx",
        "mode": "dial",
        "number": "+1234123412"
      }
    }
  }
}
```

`mode: dial` tells the room to originate a provider leg when it materializes
the participant. `mode: receive` tells ingress to adopt an incoming provider
leg as that participant. `admission: start_call` means a matching incoming leg
may create the call and room; joining a pre-existing telephony room still needs
an explicit admission mode and an unambiguous provider-leg correlation mechanism.
The approved web start/join routes are specified separately below. A fixed number
can live in the definition. R13 also allows a declared creation-time variable as
the connection's number source, under the protected-routing rules below.

#### Protected dynamic dial destinations — approved R13 decision

For a dialing participant, choose either existing literal `connection.number` or
candidate `connection.number_from_variable`, never both. The latter identifies
one declared section and one direct variable by name. It is not a template,
expression, dot path, or caller-supplied variable reference.

For example, this call-definition excerpt routes the same support role to the
authorized number selected by the integrating backend for each call:

```json
{
  "call_variables": {
    "sections": {
      "routing": {
        "schema": {
          "type": "object",
          "properties": {
            "support_number": {"type": "string"}
          },
          "additionalProperties": false
        }
      }
    }
  },
  "participants": {
    "reception": {
      "type": "agent",
      "transfers": ["human-support-agent"]
    },
    "human-support-agent": {
      "type": "human",
      "connection": {
        "service": "configured-telephony-service",
        "mode": "dial",
        "number_from_variable": {
          "section": "routing",
          "variable": "support_number"
        }
      }
    }
  }
}
```

This is a focused excerpt, not a complete new schema release; the normal entry
refs, caller, agent prompt, and capability configuration are omitted. At creation,
the authorized backend supplies `initial_variables.routing.support_number` using
the ordinary section-shaped payload. It must choose a permitted destination for
its business request, not blindly relay an arbitrary number from the caller.

Every agent must lack write permission to each section referenced by
`number_from_variable`. Reject the definition if any agent can write that
section, even if the agent requesting the transfer cannot. Existing section
permissions suffice; no per-variable grant or new runtime mutation API is added.
Agent read access is optional and not necessary for engine resolution. In the
excerpt no agent grant to `routing` is present; adding a read-only grant would
not authorize changing its destination.

The resolver uses the trusted pinned connection definition/reference and protected
backend-initialized data. Validate the selected value before asking the provider
to dial. A missing, null, or invalid number yields the existing typed transfer
failure and leaves the source responsible; do not fabricate a default or require
all call variables to be populated at creation. Literal-number definitions keep
their existing behavior.

The generated transfer tool still takes only destination participant refs from
the source agent's compiler-derived `transfers` allowlist. Neither number,
provider, URL, nor variable reference is a tool argument; the executor rechecks
the source's allowlist instead of trusting model/schema compliance. The agent
can decide when to request an allowed transfer and which explicitly permitted
role to select. It cannot select an arbitrary dial destination. Business timing
restrictions, if required, must be enforced outside the LLM; no generic outbound
allowlist/region matrix or expression system is approved here. This is documented
candidate syntax and behavior, not an implemented transfer or variable resolver.

`service` selects a configured telephony adapter; it is not a credential. API
keys, webhook verification material, provider account/application identifiers,
public ingress addresses, and deployment policy remain application- or
tenant-configured. Participant-specific topology such as service selection,
connection mode, and a non-secret destination may live in the call definition.

Telnyx is only the first concrete adapter. The same common room sequence must
also support Twilio and later telephony services:

```text
resolve participant connection intent
  -> ask the configured telephony adapter to dial or adopt a leg
  -> correlate provider lifecycle events with the room connection
  -> attach the provider media transport
  -> report common connected, failed, and disconnected outcomes
  -> let the room execute provider-neutral transfer and cleanup policy
```

Provider adapters translate this sequence into their own webhook events, REST
commands, call/leg identifiers, media WebSocket framing, and bridge or
conference operations. Provider-specific identifiers and webhook payloads stay
in adapter/runtime state. The call definition describes participant and
connection intent rather than Telnyx or Twilio command payloads.

The active room authority should receive one fully validated and resolved call
plan when the room is created and retain that immutable plan for the room
incarnation. It should include the exact call-definition revision, all
participant definitions, transfer allowlists, policies, resolved non-secret
service configuration, and pinned integration/profile revisions required to
orchestrate the call. Transfers and other ordinary room decisions must resolve
against this in-memory plan rather than repeatedly looking up mutable database
rows.

The database remains the control plane for drafts, publication, version
selection, and recovery. At call admission, Vxpipe selects a published revision
and compiles a snapshot. Subsequent edits or publication of a newer revision do
not affect the running room. Events and artifacts carry the pinned revision and
plan digest so the interaction can be explained or replayed against the exact
configuration it used. Recovery may reload that same immutable snapshot; it
must not silently substitute the latest database revision.

### Definition version, deployment selection, and invocation are different

The reviewed control planes support stored and inline definitions, drafts,
published revisions, explicit version selection, and environment aliases. These
are useful control-plane features but should not complicate the first engine
contract.

The public schema identifier is a fixed-width string in `YYYYMMDD.NN` form. The
date is the UTC publication date of that schema and `NN` is the two-digit schema
release sequence for that date, beginning at `01`. The current working value is
`"20260906.02"`. Every published schema shape receives a new identifier;
compatible and incompatible evolution is determined by a schema registry and
explicit decoder/migration rules, not by interpreting the identifier as semantic
versioning. Unknown identifiers are rejected.

Schema identity is independent from the revision of a stored call definition.
For example, revision `7` of one definition may still use schema
`"20260906.02"`. RTVI protocol versions, provider API versions, integration
catalog revisions, and resolved-plan digests also remain separate identities.

Vxpipe should distinguish:

```text
Application integration catalog
  + Tenant integration catalog
  + Call definition revision
  + Call invocation
        -> definition resolver/compiler
        -> immutable resolved call plan + private credential leases
        -> running interaction / room incarnation
        -> events, artifacts, and result
```

- Application configuration owns shared provider/integration instances,
  credentials, server behavior, and deployment defaults.
- Tenant configuration owns tenant-specific integration instances and
  credentials. The authenticated call principal supplies the tenant ID; a
  definition or invocation cannot select another tenant.
- A call definition owns portable conversational composition and policy,
  including the tool bindings selected independently in each agent's `tools` map.
  It does not own MCP endpoints or credentials.
- A call invocation owns caller/destination identity, definition selection,
  schema-validated initial variables, transport attachment, idempotency, and an
  optional authorized client tool-visibility selection. It does not override
  either entry ref and carries no MCP authentication.
- A resolved call plan pins all references, capability/profile defaults, adapter
  capabilities, selected integration/catalog revisions, discovered tool schemas, policy
  versions, and credential-lease references without retaining secret values.
- A running room owns mutable state. Editing a definition cannot mutate an
  existing room.

Draft/publish/history storage can live above the portable engine. The engine
only needs a schema version, an immutable resolved-plan identity, and a content
digest/revision for correlation and replay.

## Recommended contract direction

### Canonical representation

Use validated Elixir structs as the canonical in-process representation:

```text
CallDefinition
CallDefinition.Participant
CallDefinition.AgentParticipant
CallDefinition.HumanParticipant
CallDefinition.ConnectionIntent
CallDefinition.CapabilitySelection
CallDefinition.CallVariables
CallDefinition.VariableSection
CallDefinition.VariablePermissions
CallDefinition.Policy
CallDefinition.AgentToolBinding
CallDefinition.CapabilityEffect
CallInvocation
ResolvedCallPlan
ResolvedCallPlan.Participant
ResolvedCallPlan.IntegrationBinding
ResolvedCallPlan.ToolBinding
ResolvedCallPlan.CredentialBinding
```

The constructors accept ordinary Elixir data and return path-specific typed
errors. A JSON codec should map one-to-one onto the public structures after the
semantics work in embedded use. JSON remains a first-class public format, but
raw decoded maps must not flow into room processes.

This order avoids implementing a JSON loader before the domain is understood,
while preserving the future container contract. A YAML adapter would be
mechanical once the JSON-safe schema exists and does not need separate runtime
semantics.

### Minimal initial `CallDefinition`

The initial dated schema should contain only:

- `schema_version` as a `YYYYMMDD.NN` string;
- optional display metadata, while durable ID and revision stay in the resource
  envelope;
- `entry_caller` and `entry_receiver` string refs into the participant catalog;
- shared capability-profile defaults;
- named inline `participants`, each typed as human or agent;
- typed call-variable schemas for initial values and subsequent mutations;
- shared call policies for turns, interruption, limits, failure, ending, and
  client tool visibility; and
- artifact/event policy references.

Each agent participant should contain:

- a stable definition-local name;
- an inline prompt or versioned prompt-profile reference;
- optional capability-profile overrides;
- first-message behavior;
- one `tools` map containing stable agent-local bindings for selected remote MCP
  tools, built-in non-transfer tools, and registered host tools;
- a direct list of allowed destination participant refs;
- call-variable permissions by top-level section;
- input, output, and action-guardrail policy references;
- optional limits stricter than the call defaults.

Each human participant may contain a provider-neutral connection intent, such as
a configured service ref, `dial` or `receive` mode, a literal number or protected
`number_from_variable` source, and admission behavior. The intent
contains no credentials or provider command payloads.

The compiler resolves each agent participant's transfer refs into an immutable
allowlist. It derives one platform transfer-tool schema whose destination
choices are those refs and whose safe descriptions come from the target
participant definitions. The author does not add transfer to the agent's `tools`
map. An absent or empty transfer list produces no model-visible transfer tool.

The room checks that the source participant is current and, for an agent
participant, that its activation is current. It also checks that the target is
allowlisted and ready and that transfer budgets are not exhausted. A host
command can request the same declared transfer without giving the model
authority over the room mutation.

The initial schema should keep participants inline so one call definition is
portable in the standalone JSON configuration and resolves without a dependency
graph. A later control plane may offer reusable participant or agent resources
and allow a definition to pin one by ID and revision, but it must compile that
reference into the same self-contained immutable plan before the room starts.

### Application/tenant MCP integrations and agent enablement

Remote MCP integrations are reusable infrastructure, not call-definition data:

- **Application configuration** may configure an application-wide MCP
  integration containing its stable ID, HTTPS endpoint, authentication, tool
  policy, discovery/cache policy, timeouts, and concurrency limits.
- **Tenant configuration** may configure an integration with the same shape for
  one tenant. Tenant integrations are isolated by the authenticated tenant ID
  and are the normal home for tenant-owned Google Docs, Zapier, or similar
  access.
- Each **agent** in the call definition selects a bounded set of tools through
  one `tools` map. An MCP binding names an available configured integration and
  a remote tool; a built-in binding names a platform operation. There is no
  separate integration-enablement block on the agent.
- The **call invocation** carries neither MCP configuration nor credentials.

Use these terms consistently:

- **configured**: an integration record exists at application or tenant scope;
  that scope controls its availability and allowed operations;
- **enabled tool**: an agent selects an allowed operation in its `tools` map;
  an MCP tool's integration reference is sufficient to resolve its backing
  integration, without another agent-level grant;
- **resolved**: compiling the call pins each agent's bindings plus the selected
  scope, integration/catalog revision, and private credential lease;
- **active**: the agent activation currently owns conversational control, so its
  enabled tools may be included in model requests; and
- **invoked**: the active agent's model selected an enabled tool and the executor
  issued `tools/call`.

This creates three narrowing layers before invocation:

```text
available application or authenticated-tenant integration and tool policy
  -> agent-local selection in the unified tools map
  -> currently active agent activation
```

The effective model tool surface is their intersection. Making a remote MCP
integration available does not expose all of its tools to an agent. Selecting a
tool on one agent does not select it on another. For example, a research agent
may receive a document-search tool while a transaction agent in the same call
receives a Zapier action tool. An inactive agent's tools are absent from the
active model context.

Tenant integration lookup takes precedence as one whole integration record:

```text
tenant integration for (authenticated tenant_id, integration_id)
  > application-wide integration for integration_id
  > resolution error
```

Endpoint, authentication, policies, and limits are not deep-merged across those
scopes. Atomic replacement prevents a tenant credential from being combined
accidentally with an unrelated application endpoint or policy. The tenant ID
comes from the authenticated principal; neither the definition nor invocation
may override it.

Conceptually, application configuration can provide a shared integration:

```elixir
config :vxpipe_call_engine, :remote_mcp_integrations, %{
  "utilities" => [
    url: "https://tools.example.test/mcp",
    authentication: [type: :bearer, token: {:system, "UTILITIES_MCP_TOKEN"}],
    allowed_tools: ["get_current_time"]
  ]
}
```

An embedded host can provide tenant integrations through an engine-owned
resolver backed by its database or vault. A standalone/container deployment can
use a bounded tenant-integration map from application configuration. In both
cases the lookup is equivalent to:

```text
resolve_integration(authenticated_tenant_id, integration_id)
  -> tenant integration, application integration, or not configured
```

Start with closed authentication variants `none`, `bearer`, and validated custom
headers. A supplied OAuth access token is a bearer credential; performing an
interactive OAuth flow is a separate control-plane feature. Custom headers must
not override protocol routing, content-length, host, or other transport-owned
headers.

The integration owner also owns bounded `tools/list` discovery, schema
validation, catalog TTL/refresh, health, concurrency, and circuit state. These
can be reused by calls sharing the same application integration or tenant
integration rather than repeated for every call. Catalog and connection state
must never cross tenant/integration/credential boundaries.

#### Initial remote protocol and input validation — approved R22/R23

Target `2026-07-28` Streamable HTTP with JSON and request-scoped SSE responses,
using its request metadata/lifecycle rather than legacy initialize/session rules.
Other revisions and legacy HTTP+SSE need explicit tested compatibility; otherwise
incompatible endpoints fail clearly. Pin this profile in the resolved binding.
[MCP transport](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http).

Use a proper JSON Schema validator with 2020-12 baseline to check actual outgoing
arguments against the selected/discovered pinned `inputSchema` before submission.
Enforce required/type/enum/nested constraints, unlike incremental Call Variables.
Unsupported dialect/features or model representation reject enabled bindings
before exposure. Never weaken constraints, submit unvalidated input, or fetch
external `$ref`s automatically. No validator library, extra caps, or full output
schema design is selected. [MCP schema rules](https://modelcontextprotocol.io/specification/2026-07-28/basic#json-schema-usage).

For example, an enabled scheduling tool requires a date and a permitted slot
value. Missing the date, choosing a value outside its enum, or supplying an
invalid nested object fails before the remote request. The agent may correct its
arguments in a separate invocation; the executor does not silently retry or
relax the schema. This does not add required-variable checks to Call Variables.

**Approved R26 endpoint security:** use trusted application/tenant integration
endpoints only, never model-selected routing URLs. Require verified HTTPS;
configured private CAs are acceptable, insecure TLS and implicit loopback HTTP
are not. Public-address defaults block private, link-local/cloud metadata,
CGNAT, multicast, and unspecified targets, with address-at-connect checks against
DNS rebinding. Private destinations require explicit host-application network
authorization that tenants cannot bypass, not a blanket opt-out from safeguards.
Do not follow automatic redirects or forward credentials across them; configure
the intended endpoint. Custom clients/proxies must preserve the same protections.

These safeguards adopt the [SDK security guidance](https://go.sdk.modelcontextprotocol.io/protocol/#server-side-request-forgery)
at Vxpipe's outbound boundary. The source's defaults concern OAuth discovery
helpers; they are not a guarantee that every MCP transport request is protected.
No Go dependency, per-call credentials, generic artifact fetching, or gateway/
inbound/CORS policy change is introduced.

#### Received results and deferred server interactions — R24/R25

Store received MCP responses, including structured content and attachment/resource
descriptors, under complete observed tool history. Preserve reported success/error
and unknown outcomes. The agent decides further steps, including inspecting a
document through authorized available tools; a saved descriptor is not a downloaded
file, an understood document, or permission for a new reader. No automatic
attachment fetching/playback or generic media-inspection ability is approved.
An uninspected file does not change a reported business success into failure.
Detailed result-to-model projection, output normalization, and document/resource
inspection support are [deferred in the result issue](../docs/issues/mcp-result-and-document-inspection.md).

Server-requested sampling, elicitation, and related interactions are
[deferred separately](../docs/issues/mcp-server-requested-interactions.md).
Do not advertise unimplemented capabilities, gain authority from server input,
or silently perform such requests; report missing capability clearly. In the
selected revision, input requests use `input_required`/MRTR rather than older
independent server requests. Continuation/resubmission needs later design and is
not an approved automatic-retry exception. Ordinary agent conversation remains.
Existing grants, privacy, credential exclusions, retention, and unknown-outcome
semantics stay intact. No runtime adapter or new inspection tool is implemented.

Each agent uses the same `tools` map for built-in and remote MCP bindings:

```json
{
  "participants": {
    "timekeeper": {
      "type": "agent",
      "tools": {
        "current_time": {
          "type": "mcp",
          "integration": "utilities",
          "tool": "get_current_time"
        },
        "end_call": {
          "type": "platform",
          "tool": "hangup"
        }
      }
    }
  }
}
```

The `participants.timekeeper.tools.current_time` entry selects that operation
for the agent. Its `integration` selects the configured ID through tenant-first
resolution, while `tool` names the remote operation. The model sees the map key
`current_time`, not an endpoint, credential, or unfiltered remote catalog.
`tools.end_call` exposes the built-in `hangup` operation under the local name
`end_call`. Multiple entries can select different tools from the same MCP
integration without repeating its configuration or adding another grant.

Transfer remains derived from `transfers`, and variable tools remain derived from
variable permissions; neither needs a duplicate entry in `tools`. Tool aliases
must remain unambiguous across authored and compiler-generated tools.

At call resolution, the compiler verifies the unified tool map against the
appropriate platform/host registry or configured integration catalog and policy.
It derives the required integration bindings from the selected MCP tools and pins
normalized definitions plus catalog revisions in the agent's resolved plan.
Multiple agents may resolve the same configured integration; the runtime may
deduplicate its transport, catalog, and credential lease internally, but the
enabled tool sets remain independent. Configured integrations referenced by no
agent tool create no call binding or credential lease. The first version fails
call creation when a selected tool or its backing integration cannot be resolved;
optional/degraded integrations can be designed later.

The selected credential moves into a call-scoped private credential lease. The
resolved plan and room state retain only an opaque lease reference and non-secret
scope such as `tenant_integration` or `application_integration`. The lease must
redact process status/crash formatting and expire with the room incarnation.
Remote definitions, annotations, and results remain untrusted even when the
integration is configured.

The effective call plan is resolved once. A running call pins the selected
integration and catalog revision rather than changing tool definitions midway
through a turn. Credential revocation may invalidate its lease and make later
tool calls fail, but must not silently switch the call to another tenant or
application credential.

A transfer away from an agent participant changes the effective tool surface
and shuts down its execution subtree, including capabilities and model/tool
workers. After shutdown, that source cannot issue new tool requests. Already-sent
local variable requests can still finish in the room's `CallVariables` process;
source termination does not cancel or roll them back. Remote side effects and
uncertain outcomes remain under G4 review, not an automatic rollback guarantee.
An agent-participant destination receives only its own bindings; a human
destination receives no model tool surface. Tool results and events retain
participant and activation identity so late source output cannot revive the old
model loop or speech, even when both agents use the same configured integration.

#### Submitted MCP calls and conversational interruption — approved G4 decision

An interruption of speech is not evidence that the user intended to cancel a
tool call. Once an MCP request has been submitted, let it finish within its
existing timeout even if the user speaks or sends interrupting text. This
applies to reads as well as actions; do not infer cancellation intent from the
interruption or from a read/write classification.

Stop the interrupted conversational output, not the submitted MCP request.
Keep its result associated with the original tool invocation for subsequent
agent reasoning; completion must not revive the cancelled model continuation
or resume old speech. The result alone does not mutate Call Variables: the agent
still uses a separate authorized variable-update tool when appropriate. This
does not authorize additional unsent tool calls from the cancelled model turn.

For example, an agent submits a booking request and the user starts speaking
before the response arrives. Keep that request running to its result or timeout;
do not cancel it merely because speech was interrupted. Receiving a booking
confirmation is distinct from resuming the interrupted utterance or undoing the
booking.

This is the ordinary-interruption rule while the agent remains running. Transfer
still terminates its execution subtree, including its model/tool workers; room
shutdown also ends their work. Local termination does not guarantee cancellation
or rollback of an action already submitted to the remote system. Timeout outcome
reporting is approved below. No automatic executor retries apply initially,
including known non-submission failures; retry/idempotency enhancements are
deferred. Explicit cancellation is deferred to the
[cancellation issue](../docs/issues/explicit-tool-call-cancellation.md), not
required for this slice. Generic platform confirmation is out of scope as
documented below. External recovery notifications after timeout or shutdown are
deferred to the future event mechanism.
No new operation ledger or durable worker design is approved by this decision.

The runtime does not implement this separation yet. `ModelInference` currently
executes tools inside its model request task, and `cancel_current/1` kills that
task on interruption. Implementation must separate the lifetime of a submitted
MCP invocation from the interrupted model/output turn while retaining its agent
ownership and existing timeout. Do not describe this as current playground
behavior.

#### Provider-independent background tools — approved G4 decision

Use application-level background tool orchestration for every model provider,
including remote MCP invocations. Do not select a different conversation
workflow when a provider offers native asynchronous function calls. Provider
adapters translate messages; Vxpipe owns invocation lifetime and conversation
ordering. This is a design decision, not an implemented runtime feature.

For a background invocation:

1. Validate and accept the enabled tool call under the existing trusted agent
   identity and tool-access rules, and start independently supervised local
   execution within that agent's execution subtree.
2. Return a prompt tool acknowledgement indicating that the invocation is
   running, correlated with the original tool-call ID. This acknowledges accepted
   work, not business success. Do not acknowledge work that failed to start.
3. Let the same agent handle further conversation and send text to TTS while
   execution continues. Preserve text accompanying a model's tool calls; an
   optional kickoff utterance is distinct from the eventual result.
4. Deliver the result to the latest conversation as a separate, invocation-linked
   update. Do not append a second ordinary tool response for the already
   acknowledged call or replay the old model-turn context. The agent coordinates
   any subsequent response with current user/bot speech rather than creating a
   competing voice. Result data remains untrusted tool output, not instructions.

For example, a report request starts in the background; the agent can acknowledge
it and answer another question while it runs. When the report finishes within
its deadline, the agent receives the result against the same invocation and can
discuss it in the current conversation. The acknowledgement must not cause a
second report request or imply that a report already exists.

This approach is preferred over provider-native async branches because it keeps
one conversation and lifecycle contract across model providers. No native async
flag is required in the call definition. Provider-specific encoding and live
interoperability still need verification; accepting a message in a local context
does not prove a provider accepts it or that a model follows its instructions.

The separation makes targeted local cancellation possible without stopping the
conversation, but explicit cancellation exposure and policy are deferred for
later review in the cancellation issue. Ordinary interruption, transfer/shutdown,
existing deadlines, unknown remote outcomes, and no automatic executor retry
retain their approved rules.
No durable worker, outcome ledger, automatic variable update, or recovery after
agent shutdown is introduced. An on-time background result is not the deferred
external-notification scenario after a timeout.

`req_llm` 1.22.0 already leaves execution and subsequent model requests with its
host. Its context helpers accept a running acknowledgement as a normal tool
result, and responses can contain both text and tool calls. Vxpipe still needs
independent invocation workers and conversation updates: its model loop waits
for tools inside the model-turn task, and its buffered adapter currently drops
accompanying text when returning tool calls. The model result contract must
retain both without duplicating text already emitted by streaming.

#### MCP timeouts with unconfirmed outcomes — approved G4 decision

If a submitted MCP request reaches its timeout without a definitive remote
result, report the outcome as `unknown`. The local timeout is known; whether
the remote action succeeded or failed is not. Do not tell the agent or caller
that an action definitely failed or was rolled back merely because its response
did not arrive. The existing timeout still bounds the local wait.

For example, a booking service creates a booking but its response is lost.
Vxpipe reports that the booking outcome could not be confirmed, not that the
booking failed. Retain a definitive success/failure result if one is already
known; this rule does not turn known outcomes or pre-submission validation errors
into unknown outcomes. Unknown is not a successful tool result and does not
automatically populate Call Variables.

The approved initial tool/MCP executor policy is no automatic retry of any failed
invocation (R14), including known non-submission failures. Return the definitive
error or unknown outcome to the agent; do not silently submit another attempt.
A booking whose response was lost may already exist, so repeating the request
could create a second booking. A definite validation/non-submission error remains
definite rather than being relabeled unknown.

A later tool call requested by the agent is a separate invocation, not a hidden
retry by the executor. This distinction is not an exactly-once or deduplication
guarantee: the separate invocation may still repeat an external action. No
automatic-retry exception based on tool classification or idempotency metadata
is approved now. Skip the trusted read-only/idempotent-write/side-effect
classification layer (R15). Automatic retries and business-idempotency exceptions
(R16) are deferred to the
[retry/idempotency issue](../docs/issues/automatic-tool-retries-and-idempotency.md),
not required to implement this baseline. Call-creation idempotency (R39) is not
offered; admission recovery (R40) finishes bookkeeping for existing work without
repeating a crashed call. Ordinary database transaction semantics remain separate;
explicit cancellation is deferred to the cancellation issue. External late-result
handling is deferred below, not a prerequisite for this slice. No new wire
envelope or retry configuration is added.

#### Late business notifications are external events — deferred

A booking confirmation arriving after the MCP request timed out is an external
concern, not a reason to keep the original tool execution open or add late-result
reconciliation now. For example, the booking call times out and reports unknown;
a few seconds later the booking service sends a success webhook to the gateway.

In the future, a general external-event mechanism could route that information
to the relevant call room or agent if the room is still active. Defer this entire
scenario for now. It is not a current MCP requirement, new gateway endpoint, or
automatic follow-up tool result. Do not add polling, webhook ingestion, background
reconciliation, durable operation workers, or an outcome ledger solely to support it.

Event authentication, correlation, delivery, handling when a room is inactive,
and how an agent uses the event or updates variables belong to that future design.
This decision does not select those mechanisms, restart an ended call, or change
the approved timeout/unknown/no-automatic-retry behavior. Existing variable and
conversation-history contracts remain unchanged.

#### Tool confirmation stays with agent instructions and the domain

Do not add a generic platform-level confirmation mechanism for MCP tools now.
For example, an agent can ask "Shall I confirm this booking?" as instructed in its
prompt before calling the enabled booking tool. That is conversational behavior,
not a Vxpipe-issued confirmation token or a platform state machine.

Any enforceable business authorization or consent requirement belongs to the
integrating application/MCP. Prompt instructions are not a security guarantee.
Vxpipe must still enforce which tools the agent may use and its existing trusted
identity and argument checks; this decision does not replace those with prompts.

The earlier proposal to bind platform confirmation to arguments, participant,
variable revision, and expiry is not required for this slice. No confirmation
token, new call-definition option, approval endpoint, or generic confirmation
state is introduced. Domain-specific tool behavior remains the domain's concern.

The public engine boundary should accept a definition (or immutable definition
reference) plus an invocation. The current `CreateRoom` command remains a lower
level engine command and should eventually receive only a resolved-plan identity
or typed plan, never decoded call JSON or credentials.

### Tool event visibility and sample debugging — approved G5 decision

Client access to tool events is a property of the call, not a special entitlement
inferred from which frontend is connected. The call definition declares its
client tool visibility. The authorized backend/OTP host may explicitly select a
different visibility when creating the call; that selection overrides the
definition's value. Resolve and store the effective value with the call record
and immutable resolved plan. A prepared call remains a record until admission;
this policy needs no live process tree before the caller joins.

Supported visibility behaviors are:

| Call policy | What an authorized client receives |
| --- | --- |
| Hidden tool activity | No tool lifecycle events or payloads |
| Lifecycle metadata only | Invocation ID, tool name, and status, without arguments/results |
| Full tool visibility | Tool lifecycle events including arguments/results |

Use `tool_visibility` with `hidden`, `metadata`, or `full` for these behaviors.
When neither definition nor call creation selects visibility, hide tool events entirely.
Metadata-only and full visibility require explicit selection; metadata is not
a mandatory disclosure floor for every call. Per-tool overrides may select any
of these same detail levels. An explicit binding override takes precedence over
the call-wide default; tools with no override inherit that default.

Identify a visibility override by the participant definition key plus the local
configured key in that participant's `tools` map. These are definition-local
references, not runtime participant IDs or remote MCP operation names. The
executor's server-owned participant/tool binding supplies the identity for each
invocation; a joining client cannot select a different identity to change its
visibility. This works with the unified built-in/MCP tool map and does not alter
tool execution permissions. Resolve and pin the selections with the call policy.

For example, both `reception` and `billing` may configure `lookup_customer`.
With the call-wide default hidden, an override can expose only reception's lookup
at metadata-only detail; billing's lookup stays hidden. Sharing a local name or
binding to the same remote operation must not share visibility between agents.
The optional `tool_visibility_overrides` map uses participant definition keys,
then local tool binding keys, each selecting one of the same levels:

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

This illustrative policy exposes reception's `lookup_order` metadata and
`create_booking` payloads; other bindings inherit hidden, including the same
local tool names on another participant. Omitting both keys means hidden with
no overrides. A trusted creation-time selection replaces this effective policy
pair from the definition; omitted creation policy inherits it. This does not
define a deep-merge/patch API or another configuration container. Within the
selected pair, an explicit binding override always wins over its default.

Calls created for the `samples/` playground explicitly select full tool visibility
because it is our developer debug UI: effective `{"tool_visibility":"full"}`
with no overrides. The trusted creator replaces the policy pair; setting only
the default to full while retaining a hidden binding override would not expose
that binding. This uses the same call policy available
to integrations, not a frontend-specific bypass or additional debug-session
authorization. The backend/dev setup makes the trusted selection; a joining
browser, frontend flag, or UI route cannot change a prepared call's policy.
Editing the stored definition later does not change an existing call's value.

The gateway filters tool events before sending them, not merely before rendering
them. Hiding tool events does not disable tool execution, ordinary conversation,
or TTS. Full visibility does not expand an agent's variable/tool grants, authorize
access to another call, or expose the entire variables store or private snapshot.
Existing credential/header exclusions remain in force; it does not authorize
exposing integration credentials or raw transport requests.
R36's detailed failed-transfer restoration reason also remains internal-only,
including for samples/full tool visibility. Generic agent/public failure may be
shown without the cause; tool-debug UI and speech must not reveal the detail.

This supersedes the earlier mandatory metadata-only client default and separate
sample-debug session grant. It is an approved design boundary, not current
gateway behavior. Complete observed tool-history storage is always required,
described in the persistence section below: client visibility neither enables nor
suppresses it. Private variable history uses the approved turn/tool-linked full
snapshots and call-level latest pointer described there. Retention periods use
application settings with tenant overrides and an application retain-forever
default. Completed-call finite retention starts at `ended_at`, without expiring
active calls or assigning an expiry to forever. The current application/tenant
period applies to past and future calls, not a per-call pinned period. Expiry
deletes the call record and all associated Vxpipe-managed data. Available history
is stored when permitted; R38's explicit transcript/audio retention is separate
from live sharing under the approved room-wide booleans. Cleanup uses periodic external-first
deletion under the retention contract below. General
sensitive-input redaction is deferred as described below.

### Sensitive input and deferred redaction — approved G5 boundary

Do not build general redaction of sensitive voice audio or input passing through
STT/the LLM in the current slice. Redaction for model-visible sensitive input is
later work, not a prerequisite for the approved call-definition/runtime design.
This is a scope decision, not a claim that such input is automatically masked.

For example, an account number can be collected through deterministic DTMF input
and processed outside the LLM instead of asking the agent to interpret the digits.
The collection/routing integration needs its own design; this decision does not
add a DTMF collector, tool schema, provider API, or new endpoint. DTMF alone does
not guarantee confidentiality: raw digits or tones can still reach recording,
logging, or tool-result paths unless the integration explicitly controls them.

Existing credential/header exclusions, agent grants, recording permissions, and
client visibility remain mandatory. Apply those exclusions before persistence
and client delivery, not just at final export. Hidden tool events do not redact
information already present in spoken audio, transcripts, or model context.

### Initial agent-transfer history policies

Start with a closed set:

- `fresh`: no prior model history;
- `all_spoken`: confirmed user and played assistant utterances only;
- `last_n_spoken`: a bounded window of confirmed spoken turns; and
- `selected`: no history, only allowlisted typed variables plus an explicit reason.

Do not include model system messages, private scratch state, hidden tool
arguments, tool credentials, or generated-but-unplayed assistant text. Add
summary generation only after it has its own deadline, failure, provenance, and
fallback semantics.

### Runtime overrides

Avoid arbitrary deep-merge overrides. `CallInvocation.initial_variables` may
provide only sections and variables permitted by the definition's variable schemas.
Provider selection, tool grants, guardrails, and routing must not be silently
replaced by caller-supplied maps. Initial variables are data, not a definition patch.

Client tool visibility is an explicit approved creation-time policy selection,
separate from initial variables. Only the authorized backend/OTP host may use
it to override the definition's visibility; it is not an arbitrary definition
patch or an option accepted from the joining browser. Pin the effective value
with the prepared call and resolved plan.

MCP integration selection and authentication are not invocation overrides. They
resolve from the authenticated tenant's integration catalog with an
application-wide fallback. Differences that need reuse across calls belong in a
tenant integration or a separate call-definition revision, not an arbitrary
per-call patch.

If future applications need controlled variation, add explicit typed override
slots with their own validation and public visibility rather than generic JSON
patches.

### Transport and telephony boundary

The definition may declare integration tool references, requirements, and
transfer targets, but it should not contain MCP endpoints, live socket
identifiers, carrier call IDs, literal credentials, or provider webhook state.

For the initial schema, one call maps to one room with multiple participants and
connections. Agent transfer changes conversational control inside that room.
Human or telephony transfer is an engine-owned tool/command that creates or
changes participant connections and call legs. A later warm-transfer workflow
may create a temporary consultation room, but that should not force multi-room
orchestration into the initial definition.

**Superseded R38 candidate:** the following presence-policy example and explanation
preserve the earlier capability-denial proposal, not the current approved privacy
schema. Connection intent remains valid; the approved `media_policy`/`while_present`
route maps and storage booleans above replace this candidate. It remains here for
history, not as a second accepted policy format.

```json
{
  "type": "human",
  "connection": {
    "service": "configured-telephony-service",
    "mode": "dial",
    "number": "+1234123412"
  },
  "presence_policy": {
    "applies_while": "admitted",
    "capability_denials": [
      {
        "participants": [{"type": "all"}],
        "capabilities": ["speech_to_text", "text_to_speech"]
      }
    ]
  }
}
```

Materializing this definition copies the validated presence policy into the
runtime participant. The client that eventually attaches to that participant
cannot add, remove, or weaken it.

Changing the list to `[{"type": "agent", "ref": "xyz"}]` means the same policy
owner denies those capabilities to agent participants instantiated from agent
definition `xyz`. If `xyz` requires either capability for activation, it cannot
become the active agent until the denial is removed. An inactive `xyz`
participant can remain admitted without those capabilities.

### Web participant admission routes — approved G2 routing

The gateway identifies a web participant through a tenant-scoped connection
route, not by guessing from `transport.type` or scanning participant definitions.
Saving a definition can create an opaque connection key and routing record for
each eligible web participant definition. Publishing/enabling makes the route
callable; saving a draft must not silently expose it. These are records behind
generic HTTP handlers, not generated router code or room processes. The route
keys belong to deployment metadata, not portable call-definition JSON.

The approved HTTPS route shapes are:

```http
POST /api/tenants/{tenant_key}/participants/{participant_key}/calls
POST /api/tenants/{tenant_key}/calls/{call_id}/participants/{participant_key}/sessions
POST /api/tenants/{tenant_key}/calls/{call_id}/participants/{participant_key}/join-tokens
```

- The first route prepares a new call as the selected initiating participant. It
  resolves the tenant and participant connection key to a deployment/definition
  and participant ref, authenticates the backend API key, validates initial
  variables, and stores the preparation with a pinned revision. It returns a join
  token, not a live media connection. For this caller-start route, the selected
  participant must match `entry_caller`; `entry_receiver` identifies the initial
  handler. The route cannot silently replace either ref or make a transfer-only
  participant the initial caller.
- The second route admits a participant to a prepared or already-live call. It
  resolves the tenant and call first, then uses that call's pinned definition
  and participant mapping rather than the latest deployment. A support
  participant cannot be joined using only a reusable participant key: the URL
  must also identify the tenant and the particular call. A prepared-call token
  authorizes only its assigned participant, not any participant named in a URL.
- The third route issues a fresh join token for a participant in an existing
  **call record**, which may still be prepared with no live room. This is a
  backend-only API-key-authenticated operation with no CORS grants, separate
  from the browser-facing join operation. It checks tenant/call/participant
  authority and admission eligibility without creating another call record or
  changing the pinned definition/variables. An ended call or active-connection
  takeover is rejected; an in-progress admission must be reconciled first.
- Preparation returns an opaque join token; authorized joining obtains a
  room-bound transport session. WebRTC remains the first browser transport:
  HTTPS handles admission/signaling, media tracks carry audio, and a data channel
  carries RTVI messages. A WebSocket adapter uses the same admission identities,
  but its upgrade is a separate GET handshake, not any JSON POST above.
  Exact WebSocket route names remain unspecified; routing keys are not tied to
  the media transport.

Public identifiers are separate from database primary keys:

| Identifier | Approved public shape | Meaning |
| --- | --- | --- |
| `tenant_key` | 16 URL-safe random characters | Stable external tenant identifier |
| `participant_key` | UUID | Connection route for a participant definition |
| `call_id` | UUID | One prepared, live, or historical call |

Generate a tenant key from 12 cryptographically random bytes encoded as unpadded
base64url, rather than truncating a UUID; this yields 16 characters and 96 bits of
randomness. Enforce identifier uniqueness in storage. Do not expose internal
database row IDs in these URLs. The participant connection key is not the
runtime participant ID, and the call ID is not a room incarnation ID.

The tenant in the URL selects a routing scope; it is not proof of authorization.
The gateway validates access to that tenant, call, and participant role before
issuing a narrowly scoped session. An opaque key does not confer staff privileges
or permission to join another call. The planned database-neutral Calls admission
boundary owns route/definition resolution; the gateway does not acquire direct
Repo responsibility. The room holds the resulting pinned plan for runtime work.

The routing decision is supplemented by the approved initial-variables and
authentication contract below and the approved two-entry startup contract above.
Personalization is handled through agent instructions and permitted variable
reads, while the remaining security/lifecycle details still need G2 review.
No endpoint or ID generator was implemented here.

### Initial variables and API-key admission — approved G2 decisions

The integrating application supplies initial call-variable values directly in
the structure declared by the call definition. There is no second input schema
or input-to-variable binding layer. The reusable definition declares schemas and
agent permissions, with no variable defaults; the call invocation supplies any
initial values. The authorized backend may prefill any schema-declared section,
including one that no agent can write. Supplying initial variables does not edit
the stored definition or grant an agent write access.

R10 is already covered by this creation contract. The authorized creator,
integrating backend, or trusted ingress adapter supplies any known declared
initial variables when creating the call. Telephony ingress uses the same input;
no additional automatic customer lookup or admission resolver is required.
Unknown values remain unfilled for normal permitted variable tools to populate.
There is no required completeness or definition-default fallback. Do not
silently turn a provider caller number into verified customer identity.

For example, a shopping application starts support for order `ORD-1042`. The
definition declares an `order` section containing `id`. Its backend authorizes
the customer's access to that order and supplies
`initial_variables: {order: {id: "ORD-1042"}}`. Reception and billing may both have
`order: ["read"]`, while no agent has `write`. Admission initializes the section
once, and transfers preserve it without allowing an agent to rewrite the order
ID. The representative JSON below uses the same mechanism for `customer.id`.

The integrating backend now needs one long-lived credential: a gateway-issued
API key, sent as `Authorization: Bearer <api_key>` over HTTPS for preparation.
The application payload needs no separate signature. This replaces the earlier
separate client-ID/client-secret pair, HMAC signing, and browser forwarding of a
signed initial-variables envelope. Short-lived browser join tokens are delegated access,
not another long-lived integration credential. All API clients use the same
prepare/create, obtain-token, then join flow; a backend can join with its token
itself or hand only that token to its browser frontend.

**Common flow — authenticated preparation, token-based client join (R08):**

1. The backend authorizes its business request, then POSTs initial variables to
   the tenant/participant preparation route with its API key. That HTTP endpoint
   grants no cross-origin browser access.
2. Vxpipe verifies the key's tenant and permissions, validates variables, pins the
   definition revision and initial values, and stores a prepared call with a
   stable `call_id`. It returns an opaque, short-lived, single-use join token
   scoped to that call and its assigned participant. The token contains no
   readable variables.
3. The backend passes only that token to the frontend, or uses it to join itself.
   Both join the previously prepared call with the token; neither can replace
   stored variables, definition, tenant, or participant in the join request.
4. Accepted admission atomically consumes the token before starting the room,
   not when the browser receives confirmation. Joining activates the prepared
   call's room once and obtains the transport session. Conversation waits for
   any configured opening audio and transport/capability readiness. The token is
   not authority to inspect private variables, and the browser receives no full
   preparation snapshot. Event, tool-result, and speech disclosure policies
   must still protect sensitive variables during the call.

Prepared-call storage and live room startup are separate stages. A prepared call
is just a database record with its pinned definition and initial variables;
issuing a token does not start the call process tree, connect live conversational
providers, or dial the receiver. Opening-asset preparation is separate and does
not itself start the call. Its `created_at` records creation; `started_at` stays
unset until the call actually starts, not merely when a token is issued or consumed. The
token expires, but the unstarted record has no separate automatic admission
deadline. An authorized backend can request a fresh token
for that same eligible record. The definition and values are pinned at
preparation, not reselected from a newer deployment at join. Token claim and
activation must coordinate idempotently without holding a database transaction
across room or provider startup. The single-use and backend-mediated recovery
contract below is approved. Tokens default to five minutes, with longer lifetimes
accepted from the authenticated requester. R40's recovery only finishes records
about existing work, never repeats a crashed call or redials an uncertain attempt.
This API-client lifecycle does not turn provider webhooks into browser clients;
telephony adapters retain their authenticated ingress and common call-admission
responsibilities. There is no separate direct API-client start path.

**Removed alternative — direct backend WebSocket startup (R09 superseded):**

There is no separate direct-start endpoint or API-key-authenticated media socket
that accepts initial variables to create a call. Backend clients prepare through
the same authenticated API and join with the returned token. Initial variables
belong to preparation, not the first WebSocket application message. This removes
the setup message for which a ten-second deadline and 64 KiB limit were proposed;
neither value is approved or moved to HTTP preparation or token delivery.
Existing-call token issuance still serves eligible unstarted records and first
admission of eligible participants into live calls under the existing rules.

The upgrade uses a GET handshake; it is not a JSON POST that becomes a socket.
WebSockets do not use ordinary HTTP CORS permission checks. Browser joins need
an allowed-`Origin` check plus token authentication; backend joining also uses
token authentication, not an API-key direct-start bypass. No CORS grant is not an
authentication boundary. See [WebSocket handshakes](https://www.rfc-editor.org/rfc/rfc6455.html#section-4.1)
and [origin checks](https://www.rfc-editor.org/rfc/rfc6455.html#section-10.2).

The standard browser WebSocket constructor cannot set arbitrary authorization
headers. A browser-compatible token exchange, such as a bounded first
application message, must authenticate before any room access; its exact wire
encoding remains transport implementation work, not another admission flow.
Do not put API keys, initial variables, or bearer tokens
in query strings or logs. HTTP browser join/signaling endpoints can grant CORS
to configured origins separately. This keeps the preparation/token model usable
with the existing WebRTC transport rather than requiring its replacement with
WebSockets. See the [browser WebSocket interface](https://websockets.spec.whatwg.org/#the-websocket-interface).

**Credential ownership and storage:**

- The gateway generates cryptographically random API keys through an authorized
  management operation and returns each key once. Keys stay on the integrating
  backend. Trusted OTP/CLI administration creates the first key without requiring
  an existing API key. Each key is tenant-bound with `admin` and `calls` permission
  scopes. This approves the scope split, not per-definition allowlists, arbitrary
  per-operation grants, an admin HTTP API, or an implicit relationship between
  the two scopes. Tenant/scope metadata remain ordinary stored records. No
  separate client ID is required in integration requests.
- A tenant may have multiple independently revocable keys for separate
  integrations or overlapping rotation. Issue a replacement, deploy it to the
  integration, and then revoke the old key; other keys remain usable.
- Revocation rejects further authentication with that API key, including requests
  for more join tokens. It does not invalidate previously issued unused tokens
  or end established connections. Token admission checks the token's own expiry,
  single-use status, scope, and current tenant/call/participant eligibility,
  not the requesting API key's revocation status. No issuing-key dependency is
  needed to validate a token. Explicit session/call termination remains separate.
- Gateway authentication uses a credential-store port; the persistence adapter
  owns database details. Calls owns preparation/activation workflows and the
  engine receives only the trusted principal, plan, and variables. No API key or
  join token becomes call variables or a public event. These credentials remain
  separate from application/tenant MCP integration credentials.
- **Approved storage: one-way hashes for Vxpipe-issued API keys.** Persist only
  a cryptographic digest of each high-entropy random key alongside its tenant
  and permission metadata, never the plaintext key or a decryptable copy.
  Authentication hashes the supplied key and checks the stored record and its
  authorization; the stored digest is not itself an accepted API credential.
  Ordinary management responses and logs expose neither keys nor their hashes.
- Return the original key only at issuance. A lost key cannot be retrieved;
  issue a replacement through authorized management. Verifying API keys needs
  no decryption or database encryption key. This supersedes the earlier
  reversible-storage choice for gateway API keys: HMAC needed a recoverable
  signing secret, but these requests now supply the key for verification.
- This decision does not hash MCP/provider credentials that Vxpipe must send to
  remote services. Those credentials must remain recoverable through their
  configured secret boundary; if persisted in the database, protect them with
  encryption at rest and keep its runtime encryption key outside the database
  and source control. The existing encrypted-field pattern remains applicable
  there, not to Vxpipe-issued API keys. No new vault dependency is added here.
  [Encrypted-field documentation](https://cloak-ecto.hexdocs.pm/install.html).

API-key authentication establishes the integrating application's authority, not
independent proof that the speaker owns an order. Its backend still authorizes
the business variables. A browser join token grants only its assigned admission
scope; possession is not proof of a person's identity. Treat it as a secret,
short-lived bearer credential. [Bearer-token security](https://www.rfc-editor.org/rfc/rfc6750.html#section-5).
Provider webhook authentication remains a separate adapter concern.

**Join-token lifetime:** default to five minutes from issuance. An authenticated
backend requesting the preparation token or an existing-call token may request
a longer lifetime. No additional maximum or application/tenant TTL override
hierarchy is approved here. The browser cannot extend an issued token by changing
its join request. For example, a backend can request fifteen minutes for a
user who needs time before connecting; that token still expires at its issued
deadline even if the requesting API key is revoked in the meantime. A default
token instead expires after five minutes. Neither expiry ends an established
call nor deletes its prepared record. Exact request field and duration encoding
are implementation details, not new approval items.

**Still pending:** temporary transport failure versus call-end triggers and exact
transport response encoding. Periodic storage cleanup, single-use claim, existing-call
token issuance, and R40's no-repeat bookkeeping boundary are approved. HMAC algorithm selection,
payload canonicalization, and signature-envelope fields are no longer
implementation questions. Variable-default assembly is eliminated: only supplied
setup values prefill variables. G3's variable ownership is settled below;
R11/R12's instruction-based personalization/time ownership is approved, and R10's
telephony variables already use call creation. No credentials, configuration, dependencies, database, or
runtime authentication/transport behavior were changed in this checkpoint.

### Single-use join tokens and existing-call recovery — approved G2 decisions

Both the initial preparation token and tokens issued for an existing call are
single-use admission credentials. They are not reusable reconnect credentials,
and the lifetime of a token is not the lifetime of the conversation.

For example, a backend prepares support for order `ORD-1042`. The browser sends
its token; Vxpipe accepts admission and starts the room, but the connection drops
before confirmation arrives. Retrying must not create another call or replace
the original participant with a new identity. The accepted token stays consumed
even if the browser never received the response.

The approved rules are:

1. Validate the token's scope, expiry, and current admission eligibility, then
   atomically record its consumption and accepted admission. Only one competing
   attempt may claim it. Acceptance precedes live startup and does not wait for
   client acknowledgement. A failure afterwards does not make the token unused
   again. Do not hold a database transaction across room/provider startup.
2. Before acceptance, the browser may retry the same unused, unexpired token.
   After acceptance, that token cannot authorize another join. An uncertain
   browser cannot assume a lost response means the server rejected the request.
3. Replacement issuance for an eligible unstarted call goes through the
   integrating backend. It rechecks the user's authorization and uses its API
   key to request a fresh token from the existing-call `join-tokens` route.
   Neither a call ID nor possession of the old token authorizes issuance by
   itself. The API key remains on the backend; only the fresh scoped token
   reaches the frontend. After an uncertain accepted admission, reconcile the
   existing attempt first; a new token is not permission to resume a caller
   whose call already started.
4. Gateway authentication and the Calls workflow resolve that same call record
   and participant. Issuance requires an eligible state: reconcile pending
   admission before retrying, reject ended calls and unauthorized access, and
   never silently take over an active connection. A revoked API key cannot
   request another token, but existing tokens do not inherit key revocation.
   Recheck eligibility when consuming the new token so intervening joins or call
   termination cannot bypass the same rules. This preserves the singleton
   participant binding.
5. An eligible **prepared call** still has no live room: issuing a token does
   not start one, and accepted joining activates it once. For a **running call**,
   a fresh token may authorize first admission of an eligible transfer destination
   or other not-yet-admitted participant. This retains the room, current variables,
   and pinned plan; it does not restart or reinitialize the call. Same-call caller
   reconnection is deferred and is not another use of this token route.
6. A token expires five minutes after issuance by default; the authenticated
   token requester may request a longer lifetime. API-key revocation does not
   invalidate an already-issued token. A token's expiry only prevents a future
   claim. Once admission was accepted, that token expiring does not hang up the
   established call. Its expiry is unrelated to whether the transport later
   fails or the logical call ends.
7. An unstarted call record does not automatically expire because its token
   expired or because time passed since preparation. Without a valid token the
   browser cannot join, but the record remains eligible for backend-authorized
   fresh-token issuance subject to the same authorization/lifecycle checks.
   Reissuance preserves its pinned definition and initial variables; it does not
   require another call record. Data retention and cleanup are separate policies,
   not an automatic deletion or invalidation triggered by token expiry.
8. Issuing another token for the same eligible unstarted record does not
   supersede or invalidate earlier unused tokens (R06). Each has its own expiry
   and single-use status. Distinct tokens still share call/participant admission
   eligibility: whichever admits the caller first does not let another token
   create a duplicate caller, take over its connection, reconnect that caller,
   or reuse the call after it ends. For a lost issuance response, requesting a
   second token leaves the first governed by its original rules; no token
   replacement/revocation coupling is needed.

Gateway owns authentication and token handling; Calls owns the existing-call
workflow and uses persistence ports for admission/claim state. No live database
lookup is added to ordinary room turns or transfers. The existing browser
WebRTC path and future WebSocket path share these admission rules; issuing a
token is distinct from negotiating either transport.

**Caller reconnection scope — approved R07 deferral:** keep replacement tokens
for unstarted prepared calls, but do not require same-call caller reconnection in
the initial slice. A new token authorizes admission, not identity continuity.
Once the logical call ends, connecting again starts a new call with a new record
and call ID. It cannot revive or reset the ended record. Existing live rooms may
still admit an eligible destination for the first time; this is not caller
reconnection. No new browser-session mechanism or token/API-key revocation
linkage is needed.

A temporary transport interruption is not automatically a call-ending
disconnect. The exact transport failure/end trigger is not selected here, and
no rule says any participant disconnect ends a multiparty call. These boundaries
avoid turning a narrowed admission scope into an unapproved call-end policy.
For example, replacing a token that expired before the caller ever joined
preserves the prepared order variables. Returning after an ended call instead
requires a newly authorized call; a new token for the old call cannot restore it.

This resolves single-use consumption, before/after-acceptance retry behavior,
and the backend-authorized existing-call token endpoint. Token expiry suffices
for this admission contract; there is no additional unstarted-call TTL. It does
not yet settle transport failure/end triggers or status/error response shapes.
R39 offers no API creation idempotency; R40 only completes existing-work bookkeeping
without repeating calls. Cleanup uses the approved periodic retention contract.
No runtime endpoint or authentication code is implemented here.

### Agent instructions own personalization and business time — approved R11/R12

Leave personalization in agent instructions. The agent uses its existing enabled
`read_variables` tool to obtain only sections it may read and handles missing
information through those instructions and conversation. No interpolation,
template, binding engine, or new missing-binding compiler/default behavior is
required. Existing section permissions, null/absence behavior, and datatype
checks remain unchanged.

Locale, timezone, and business-time interpretation belong to the integrating
application and its agent instructions. Provide date/current-time tooling for a
fresh observation through the ordinary enabled-tool boundary; do not freeze the
current time as a call-start value. This is tool capability intent, not a new
named room capability or a frozen tool name/schema. No call-level locale/timezone
fields or default hierarchy are approved. Authoritative `created_at`, `started_at`,
and `ended_at` retain their existing meanings.

For example, an agent can read permitted order variables to personalize its
response and obtain the current date/time when discussing availability according
to the application's instructions. It need not expand a prompt template first.
This does not grant tool/variable permissions; R13's protected connection source
is separate from conversational personalization. Opening audio remains fixed configured text or a file,
not a new interpolation surface. No runtime tool or schema was added here.

## Representative JSON shape

This is the working input for the first implementation checkpoint. It remains a
candidate until the constructor and compiler tests make every field precise:

```json
{
  "schema_version": "20260906.02",
  "name": "customer-support",
  "entry_caller": "caller",
  "entry_receiver": "reception",
  "defaults": {
    "capabilities": {
      "speech_to_text": "default-stt",
      "model_inference": "fast-general",
      "text_to_speech": "default-voice"
    }
  },
  "call_variables": {
    "sections": {
      "customer": {
        "schema": {
          "type": "object",
          "properties": {
            "id": {"type": "string", "minLength": 1}
          },
          "additionalProperties": false
        }
      },
      "intake": {
        "schema": {
          "type": "object",
          "properties": {
            "summary": {"type": "string"},
            "topic": {"type": "string"}
          },
          "additionalProperties": false
        }
      }
    }
  },
  "participants": {
    "caller": {
      "type": "human",
      "description": "The person starting the call.",
      "connection": {
        "service": "web",
        "mode": "receive",
        "admission": "start_call"
      }
    },
    "reception": {
      "type": "agent",
      "description": "Understands the request and selects the next participant.",
      "prompt": "Understand why the caller is contacting us and route the conversation.",
      "first_message": {"mode": "generated"},
      "variable_permissions": {
        "customer": ["read"],
        "intake": ["read", "write"]
      },
      "tools": {
        "lookup_customer": {
          "type": "mcp",
          "integration": "records",
          "tool": "lookup_customer"
        },
        "end_call": {
          "type": "platform",
          "tool": "hangup",
          "description": "Use after the conversation is complete."
        }
      },
      "transfers": ["billing", "human-support-agent"]
    },
    "billing": {
      "type": "agent",
      "description": "Handles billing questions.",
      "prompt": "Resolve billing questions.",
      "capabilities": {
        "model_inference": "careful-general"
      },
      "first_message": {"mode": "generated"},
      "variable_permissions": {
        "customer": ["read"],
        "intake": ["read"]
      },
      "tools": {},
      "transfers": []
    },
    "human-support-agent": {
      "type": "human",
      "description": "A human support participant.",
      "connection": {
        "service": "configured-telephony-service",
        "mode": "dial",
        "number": "+1234123412"
      }
    }
  },
  "limits": {
    "max_duration_ms": 1800000,
    "max_transfers": 6
  }
}
```

The corresponding embedded-host invocation selects a definition directly and
carries initial variables matching its section schemas. It is not the
authenticated HTTP request body for the keyed web routes above: those resolve
the definition and participant from the route and authenticate the request
before constructing an invocation. The JSON illustrates domain data, not an
API-key or token wire format.

```json
{
  "call_definition": {
    "id": "customer-support",
    "revision": 7
  },
  "initial_variables": {
    "customer": {"id": "customer-456"}
  },
  "transport": {
    "type": "web"
  }
}
```

The authenticated principal supplies tenant and actor identity; neither is a
caller-controlled field. The gateway creates runtime room, incarnation,
participant, connection, and call IDs. The transport attachment belongs to the
invocation or an inbound routing resource, not to reusable conversational
behavior. For `reception`, the compiler exposes one transfer tool whose closed
destination choices are `billing` and `human-support-agent`; the model cannot
submit a third destination or see the latter participant's service and number.
The compiler also exposes read and update variable tools restricted to the
participant's declared section permissions.

In this invocation, only `customer.id` is prefilled. Declaring the `intake`
section does not initialize it to an empty object or manufacture any values;
it remains unfilled until a permitted update supplies data.

Provider/profile strings are closed registry names resolved by the host. They
do not name Elixir modules. Inline prompts may later be replaced by immutable
prompt references without changing the runtime semantics. Agent-scoped tools,
knowledge, guardrails, MCP enablement, and artifact-policy references fit into
this shape without changing its initial-role refs and transfer-tool model, but
they should be specified in separate focused checkpoints.

## Alternatives considered

### Embed the caller definition inside an entry field or infer it by scanning

Rejected. Both `entry_caller` and `entry_receiver` are refs into one participant
catalog. Embedding the caller would introduce a second participant-definition
location; inferring it from connection options would leave initial roles
implicit. Parse/save-time validation and the pinned call plan already avoid
repeated runtime discovery. The earlier `entrypoint` name is superseded rather
than retained as a second way to choose the receiver in the working candidate.

### Require a second input schema and mappings into call variables

Rejected for call-start variables. The integrating backend can supply values in
the definition's variable-section shape directly. A separate `input_schema` and
JSON Pointer initialization map duplicate that contract without helping the
order-ID example. JSON Pointers remain a possible internal representation for
authorized mutations, not syntax accepted by the variable tool. Removing
initialization bindings does not remove the variable update tool.

### Put default values in variables definitions or merge them into setup data

Rejected. Variables declarations provide schemas and permissions, not initial
values. Only supplied call-setup data prefills variables; omitted optional data
stays unfilled. There is no variable-default construction or merge layer. This
does not change capability/profile configuration defaults or later authorized
variable updates.

### Replace a complete variable section with a partial object update

Rejected for `update_variables`. Merge the supplied variables into the existing
section and preserve omitted variables. Replacing the section with the submitted
object would lose previously collected data or require the agent to resend it
on every update. The same rule applies to partial nested objects: recursively
merge them rather than losing omitted children. Validate and commit the complete
merged result atomically without requiring missing variables. Explicit null
assignment clears a nullable variable while retaining its key; physical removal
is deferred.

### Treat null as deletion or require a separate tool just to clear a value

Rejected for the initial variable tools. Use explicit null assignment through
either update form, retain the variable's key, and validate nullability under its
schema. Omission means preserve, not clear; optional does not imply nullable.
Do not add a variable-deletion tool for this decision.

### Require complete variables before accepting setup or an update

Rejected for now. Data collection is iterative: saving a known city must not
wait for an unknown postal code. Keep datatype checks and other supplied-value
constraints, section grants, revision checks, and bounds, but do not enforce
required-variable presence at any object depth. Reads return one null for a
requested unpopulated value rather than manufacturing a nested default object.
This decision adds neither a final-completeness gate nor a validation toggle.

### Interpret variable names as nested paths

Rejected. Root keys identify sections and direct section keys identify variables.
The variable tool performs literal-name lookup only. Use a nested object through
`update_variables` for deeper partial updates; do not expose the internal pointer
representation, dot paths, or array-index syntax as a second addressing system.

### Cancel submitted variable updates when a conversational turn is interrupted

Rejected. Conversation interruption does not cancel or undo an already-submitted
local variable update. Let the command finish under the normal room identity,
permission, deadline, schema, size, and revision checks, including after source
agent shutdown. There is no current-activation check. Corrections use another
variable-update tool call; conflicting old updates are not blindly retried.
There is no additional live-turn/tool-cancellation check or mutation journal
for this rule. External tool operations remain a separate review concern.

### Silently filter forbidden sections from a variable read

Rejected. The agent is informed of its readable sections. A request containing
a forbidden section receives a permission error and no values, so the agent
can correct the request rather than treating a partial response as complete.
This does not add variable-level grants or change write authorization.

### Allow agents to write sections they cannot read

Rejected. Agent section grants are read-only or read+write, with no access when
omitted. A standalone write grant is invalid. Every writable section uses the
same value-and-revision read projection, so no revision-only writable view or
write-only error policy is needed. This does not broaden access to other
sections, other participants, public events, or artifacts.

### Keep separate client-ID/HMAC authentication for browser-forwarded payloads

Superseded. The backend sends initial variables under API-key authentication
when preparing a call, then either joins with its token or passes only the token
to its browser. The common admission flow removes signature generation,
canonicalization, and signed-envelope verification from the integration contract.
It does not remove HTTPS/WSS, tenant authorization, replay/claim protection for
join tokens, or same-call admission exclusion. R39 does not offer API creation
idempotency. API keys remain outside browser bundles,
call definitions, call variables, and logs; sensitive variables stay server-side
in the prepared-call flow.

### Reuse consumed join tokens or recreate the call after a lost response

Rejected. A lost acknowledgement does not undo accepted admission. Reusing the
token could grant a second connection; recreating the call would duplicate its
record, variables, and potentially provider work. Recovery instead reauthorizes
through the backend and reconciles the same call/participant before considering
another attempt. A fresh token may replace one for an eligible unstarted record;
it does not authorize an already-started caller to reconnect in this slice. After
actual logical termination a newly authorized call has a new record. Token expiry
is not a call-duration limit, and an existing-call token must never silently evict
an active connection.

### Automatically expire unstarted call records on a separate deadline

Rejected for this admission contract. Before joining, the call is only a stored
record, not a running room/provider process tree. Expired tokens already fail
admission; an authorized backend can obtain a fresh token for the same eligible
record. There is no need to force creation of a new call solely because the
original token expired or the record is old. Retention/cleanup of stored data
remains separate from admission and is not specified by this decision.

### Start with a fully expressive JSON graph

Rejected for both the public definition and the initial private plan. A graph
front-loads node taxonomy, expression semantics, parallelism, joins,
compensation, graph migration, and visual-editor concerns before Vxpipe can
switch between two agents. Even a minimal `agent`/`end` graph makes the common
case less direct than explicit entry refs with transfer tools and risks making
the graph rather than the room the source of truth. Named agent specs, resolved
tool bindings, and the room's active-agent-participant state are sufficient.

### Make executable Elixir modules the only definition

Rejected as the public contract. Code-first composition is natural for embedded
users and remains an important extension seam, but module-only configuration is
not portable to JSON, cannot be safely accepted by a container API, and makes
definition inspection/versioning harder.

Registered host callbacks can implement tools and policies behind stable names.
They are resolved before the plan reaches the room.

### Embed Lua immediately

Deferred. A scripting VM could eventually provide compact deterministic routing,
calculation, and transformation without recompiling the host. Starting there
would introduce a second type system, sandbox, resource accounting, module/API
surface, determinism rules, serialization rules, upgrade compatibility, and
debugging model before the basic domain contracts are proven.

If an embedded language is later justified, it should run behind a narrow
`PolicyEvaluator` or `ActionExecutor` port in a supervised, bounded worker. It
must not execute inside the room authority, access BEAM/runtime internals, hold
secrets, or mutate room state directly. Its output should be the same typed
commands available to declarative policies.

### Add a general expression language now

Deferred with Lua. A participant transfer can be model-selected through an
engine-owned tool or requested explicitly by the host. When deterministic
branching is needed, design it around its first concrete use with a small typed
condition algebra over declared variables (`eq`, `in`, `exists`, `all`,
`any`, `not`) rather than putting natural-language expressions into transfer
tools. This remains serializable, validatable, and testable.

### Put MCP endpoints or credentials directly in each call definition

Rejected. Remote MCP integration configuration is reusable infrastructure, not
call behavior. The definition contains only stable integration/tool references.
Literal endpoints and credentials do not belong there: embedding them makes
reusable definitions, revisions, inspection, and logging unsafe. Authentication
belongs to an application-wide or tenant-scoped integration. The compiler pins
an opaque credential lease rather than its value.

### Configure remote MCP integrations per invocation

Rejected for the initial contract. Endpoints, credentials, discovery caches,
health, limits, and policies are reusable at application or tenant scope.
Per-invocation integration maps would repeat work, increase secret traffic, and
make authorization harder to audit. A separate call-definition revision can
narrow tool use for a particular call shape without rebuilding the integration.

### Treat a configured MCP integration as enabling all its tools for every agent

Rejected. Application or tenant configuration may make an integration and tool
catalog available, but an agent selects specific operations in its `tools` map.
This keeps one agent from inheriting tools merely because another agent, call, or
tenant happens to use the same MCP server.

## Validation requirements

Compilation and admission validation should reject at their respective
boundaries, with path-specific errors:

- malformed, unknown, or unsupported dated schema identifiers;
- an absent or non-string `entry_caller` or `entry_receiver`, an entry ref naming
  an unknown participant, or both refs naming the same participant;
- duplicate or invalid names;
- an unknown participant type or type-specific field on the wrong participant;
- a transfer list with an unknown, duplicate, or invalid participant ref;
- a user-authored `transfer` tool or another tool alias that collides with the
  compiler-generated platform tool;
- a human connection intent with an unknown service, mode, admission behavior,
  literal credential, or invalid destination;
- unauthorized media/transcript routes or retention under the applicable policy;
- unknown participant-definition keys in `audio_routes`/`transcript_routes`, invalid
  route-map/recipient-array shapes, or non-boolean `record_audio`/`save_transcripts`;
  route maps use direct human/agent keys, not the historical denial selectors;
- duplicate tool names within one source agent;
- tool or integration references not present in closed registries;
- duplicate agent-local tool aliases within one agent;
- an MCP tool's integration reference unavailable to the authenticated
  tenant and absent from the application catalog;
- a remote tool absent from the selected integration catalog or excluded by its
  integration-level policy;
- any attempt by a definition or invocation to select another tenant or supply
  an endpoint or credential;
- tenant integration state escaping its tenant boundary;
- forbidden or malformed custom authentication headers;
- duplicate or invalid call-variable section names and unsupported schemas;
- any variables `default` declaration, including section-level and nested schema
  properties; variable values belong in the call-setup payload, not the definition;
- an agent variable permission naming an unknown section or permission other
  than `read` or `write`;
- an agent section grant containing `write` without `read`;
- a transfer variable projection containing a section the destination cannot
  read;
- initial variables containing undeclared sections/variables, non-object section
  roots, invalid populated values, or exceeded size limits; missing variables are
  permitted and do not cause required-variable validation failures;
- policies outside bounded ranges;
- incompatible required capabilities; and
- any private runtime term or literal secret at the public boundary.

Transfer cycles are not inherently invalid: callers may legitimately return to
the initial receiver's agent participant. They require bounded transfers and
session duration. Unreachable agents should initially be a compiler warning or
a lint error, not necessarily a runtime-invalid definition.

At runtime, destination resolution must produce a concrete participant ID and a
supported `human` or `agent` kind before the room commits the transfer. A missing
identity, a kind mismatch, a destination absent from the active agent's transfer
allowlist, or a stale source participant/activation rejects the operation
without changing control or routing.

Admission and destination preparation must also preserve one participant per
definition key per call. Concurrent or repeated operations cannot allocate a
second identity for an already-bound key, and a different person cannot take
over an existing participant through the same route.

## Call-variable implementation plan

### Current implementation gap

The current code confirms that this is a new domain boundary rather than a small
map addition:

- `CreateRoom` accepts a hard-coded single-agent preset, not a resolved call
  plan.
- `RoomAuthority` owns participants, connections, turns, capabilities, event
  sequencing, and the room snapshot, but stores neither the pinned plan nor call
  variables.
- `Room.Snapshot` contains only room identity and lifecycle fields. It should not
  grow an unrestricted variables map because snapshots are broadly observable.
- `ModelInference` constructs only a system message, private turn history, and
  the current user message. It has no activation-scoped variable projection.
- `Tool.Executor` exposes a static application-configured module list.
  `Tool.Context` carries trusted room and participant identities, but not an
  engine-private route to a variables process. No dedicated variable owner or
  agent-lifetime variable tool binding is implemented yet.

The existing placement of tool execution is useful: model and tool work runs in
the supervised capability request task, outside `RoomAuthority`. Variable tools
can call the dedicated variables process directly. However, current model/tool
tasks use `Task.Supervisor.async_nolink` under a shared application supervisor;
capability `terminate/2` attempts cleanup but is not a lifecycle guarantee.
The approved transfer design must make the entire agent execution subtree,
including those tasks, terminate together. Stopping only a participant process
or relying on best-effort cleanup does not establish that contract today.

### Runtime ownership and boundaries

Use a dedicated variable owner and immutable views:

```text
CallDefinition + CallInvocation
  -> pure validation and compilation
  -> ResolvedCallPlan + initialized variable values
  -> RoomAuthority holds the pinned plan and orchestrates room lifecycle
  -> CallVariables GenServer owns variable state for one room incarnation
       ├── holds compiled section schemas and per-agent grants from that plan
       ├── answers direct authorized reads and per-turn projections
       ├── merges, validates, and commits direct tool updates
       └── advances revisions and emits variable update events

Agent model/tool worker -> CallVariables -> reply to that worker
```

`ResolvedCallPlan` is immutable. The `CallVariables` GenServer is the only owner
of mutable variable values and revisions for the room incarnation. Keep pure
initialization, projection, merge, and validation logic separately testable; it
does not create another authoritative copy. The process owns authorization using
trusted identity and pinned grants, and commits each update atomically with its
revision checks. Neither operation routing nor authorization needs a synchronous
call to `RoomAuthority`.

Place `CallVariables` under the room supervisor, outside the per-agent execution
subtrees. It survives A-to-B transfer and human-only periods. Room shutdown also
ends the variables process; no write is guaranteed to finish if that process
itself is stopped. Durability/recovery remains a separate checkpoint; do not
silently recreate live variables from empty state or a newly published plan.

This supersedes the earlier single-`RoomAuthority` ownership decision. We do not
require variable commits to be atomic with agent deactivation: already-submitted
requests may finish after source shutdown. No activation mirror, revocation
acknowledgement, current-agent query, or worker-to-authority final commit is
required for variable reads and writes. Ordinary updates occupy only the
variables process, not the room authority.

Database or control-plane storage is not the live owner. The room is created
with the exact resolved definition revision and initialized values. Normal reads
and transfers use that in-memory snapshot. A database-backed update validates
against it and commits a full candidate snapshot through the persistence port
before publishing the new in-memory values and returning success. Reconstructing
a room after restart remains a separate design; stored values must not cause it
to adopt a newly published definition.

### Authorization transaction

Add explicit engine commands rather than exposing the state module:

```text
ReadCallVariables
UpdateCallVariables
```

The model/tool worker builds them from an engine-private execution context with
the variables-process target and trusted tenant, room, incarnation, and agent
participant identity. Source participant, agent activation, originating command,
correlation, and tool-call IDs remain attribution metadata; activation is not
checked against current room state. Requested sections, expected revision, and
proposed update data are model-supplied inputs. The update bindings normalize
object/variable requests into
the engine command while preserving omitted section variables. The object tool must
also preserve omitted nested variables and treat explicit null as assignment,
not deletion. The variable binding resolves a literal direct key and must not
interpret it as a path, including when encoding an internal pointer.

The platform tool makes one bounded `GenServer.call` directly to `CallVariables`.
In order, the variables process verifies:

1. the command deadline and tenant/room/incarnation identity;
2. that the engine-bound agent participant identity belongs to this call's pinned
   participant/grant mapping, without checking current activation or liveness;
3. that the resolved plan grants that agent `write` on the named section;
4. that the section is declared and `expected_revision` matches, even if its
   value is not populated yet;
5. operation count, pointer shape, and encoded byte limits;
6. that applying every change to a copy succeeds; and
7. that the candidate is an object and its populated values match the compiled
   schema's datatypes and value constraints, without requiring missing variables.

After all checks pass, compute the complete candidate snapshot and next section/
global revisions. For a database-backed call, commit the snapshot and conditional
latest-pointer update through the configured persistence port. Only confirmed
commit allows the owner to replace the section, publish the new revisions, emit
the ordered update event, and return success. Serialize updates through this
boundary so a second candidate cannot be committed from unconfirmed state.
Validation failures retain their existing typed errors. A transaction error
returns variable-save failure. Both leave current in-memory values/revisions
unchanged and emit no update-success event.
Use the transaction's normal success/error result; the proposed extra commit-status
lookup and reconciliation workflow are not required for this slice. Reads run the
same room/agent identity checks and require every requested section to be readable.
A forbidden section produces a permission error for the whole request
with no variable values; the variables process does not filter it into partial
success.

The variables process does not call the authority for a second authorization
check or execute model/provider or remote MCP work. It waits for its configured
snapshot-persistence port on database-backed updates; the adapter, not the engine,
owns SQL and Ecto. The persistence request belongs to the variables/room lifecycle,
not to the source agent's execution subtree. Provider requests and other tool
rounds remain in the agent's supervised workers.
The general prohibition on cyclic synchronous calls still applies; add a focused
regression test proving variable operations can finish while `RoomAuthority` is
not servicing messages.

### Variable updates and conversational interruption — approved G3 decision

A variable update is a bounded local room command. Once the tool submits it to
`CallVariables`, a conversational interruption, cancellation of the model turn,
or shutdown of the source agent does not retract that command or roll back a
committed value. A later correction is another variable-update tool call. This
avoids adding turn/tool cancellation
tracking to the variable authorization transaction: neither the originating turn
nor the source agent process needs to remain live. Tool-call/correlation and
activation IDs remain useful for attribution, not an additional cancellation check.

Letting the command finish does not guarantee success or bypass the checks
above. The target room/incarnation, trusted agent identity, pinned permissions,
bounded deadline, schema, limits, and expected section revision must still be
valid. Transfer does not itself invalidate a queued request: it terminates the
source agent's execution subtree to prevent further requests, including its
capabilities and model/tool workers, without letting supervision restart that
departed execution. A queued or executing variable update may finish after that
shutdown. Stopping the room's variables process is different; a pending operation
may then fail or lose its reply. That is not a completion guarantee, nor does it
undo a database transaction that already committed. A returned update success
in database-backed mode requires that commit.

Keep `expected_revision` to prevent lost updates. If the original update commits
first, the correcting call uses the resulting revision, refreshing its permitted
view if needed. If the correction commits first against the same revision, the
delayed original update conflicts instead of overwriting it. Do not blindly
retry that stale update with a newer revision; any subsequent call must reflect
the current intended correction and existing permissions.

For example, A sends an update and then transfers to B. A and its workers stop;
the room's variables process may still commit A's submitted update. B reads the
current committed revision and can refresh later if that update completes after
its first read. No transfer-time flush or frozen "all A writes are finished"
snapshot is promised. Revision conflicts still prevent silently overwriting a
newer update from B.

Completion does not revive a cancelled model response or resume stale audio.
A missing acknowledgement does not undo a committed write. No separate mutation
ID deduplication/journal subsystem is approved by this decision, and the policy
for other external MCP/host side effects remains under G4 review. Late business
notifications are deferred to the future external-event mechanism, not handled
as new variable writes in this slice. No extra call-definition fields are needed.

### Agent model and tool integration

Compile an activation-specific effective tool surface from three sources:

- platform tools derived from the agent definition, including transfer, hangup,
  and the read, object-update, and variable-update variable tools;
- explicitly enabled application tools; and
- explicitly enabled remote MCP bindings.

The platform variable tools are engine bindings, not arbitrary Elixir modules and
not MCP calls. Their executor receives an engine-private variables-process target.
Host tool modules keep receiving the existing redacted identity context, and remote
MCP servers receive only their declared arguments. Neither receives a PID,
permission map, resolved plan, or variable values unless an explicit authorized
binding supplies a value.

Before the first provider request in a turn, the worker requests a frozen
agent-permission-scoped projection directly from `CallVariables`. Model inference
renders it as a distinct transient engine message after the agent's system prompt
and before private conversation
history. The message contains values and section revisions for read-only and
read+write sections; ungranted sections are absent. It is rebuilt on
the next turn and never becomes a historical user or assistant message.

After a successful variable update, the tool result supplies the new revision and
an authorized value projection. The next model round in the same request can
reason about its update. `read_variables` permits an explicit refresh if
another authorized command changed variables during that tool loop. Transfer to a
new agent creates a fresh projection and tool surface from the destination's own
permissions. Source-agent execution stops on transfer; requests already sent to
the variables process may still finish without an activation check.

### Incremental red-green checkpoints

1. **Pure definition contract:** add failing tests for the smallest
   `20260906.02` participant-first definition with variable schemas and no variables
   defaults, direct initial variables, agent permissions, and direct transfer refs.
   Accept read-only/read+write grants and reject standalone write grants.
   Implement typed constructors and path-specific errors without starting processes.
2. **Pure variable state:** add failing tests for initialization, projection,
   absent-section null reads without mutation, iterative population, bounded
   pointer changes, atomic datatype rejection without required-variable checks,
   independent section revisions, and exclusion of ungranted sections. Implement
   pure variable-state logic used by the GenServer.
3. **Dedicated room variable owner:** add failing room tests proving creation
   pins a resolved plan and starts one `CallVariables` process with initialized
   values, schemas, and grants. A correct update commits once; wrong incarnation,
   untrusted identity, missing grant, revision conflict, invalid schema, and
   oversized input leave state unchanged. Add bounded direct read/update calls
   and protocol-neutral events without storing variable state in `RoomAuthority`.
   Use a controlled snapshot-port fake: an update cannot publish new state or
   return success before commit confirmation; confirmed failure preserves state.
4. **Platform tool surface:** once remaining tool details are settled, add failing
   executor/model tests proving the read tool and both update tools appear only
   when the active agent has the matching grant, their section schemas are
   closed, trusted identity is not model-controlled, and a variable update can
   finish while `RoomAuthority` is not servicing messages. Route engine platform
   tools separately from host modules and MCP bindings.
5. **Turn projection:** add failing model tests proving current readable variables
   is present in every provider request, is not appended to private history,
   ungranted sections are absent, and an update result is available to the next
   model round.
6. **Transfer continuity:** with two deterministic agent participants, prove a
   value written by the source remains room-owned, the destination sees only its
   projection, and terminating the source's execution subtree stops its
   capabilities and model/tool workers without restarting them. An already-sent
   source update may still commit after termination; a revision conflict still
   rejects it. Prove the variables survive transfer and human-only periods,
   and distinguish agent shutdown from stopping the room's variables process.
7. **Database integration and external access:** implement the snapshot commit
   port in the persistence adapter and verify its transaction in the tagged
   PostgreSQL lane. Database-backed variable tools require this before claiming
   success implies storage. Separately design authenticated host/client read and
   update commands; do not reuse agent permissions for human/client authorization.

The first usable vertical slice should complete checkpoints 1 through 4 with one
agent and two sections. Checkpoints 5 and 6 then make variables useful across real
model turns and transfers without changing its ownership model.

### Planned verification

During implementation, run focused tests from `apps/vxpipe_call_engine` after
each red and green step. The focused cases must demonstrate:

- initial variables initialize only schema-declared sections and variables;
- variable initialization uses only supplied values, rejects default declarations,
  and leaves omitted variables unfilled without required-variable checks;
- setup accepts partial or explicitly empty section objects while still rejecting
  populated values of the wrong datatype and other invalid supplied values;
- admission can initialize a section that agents can read but none can write;
- definition compilation accepts read-only and read+write grants, and rejects
  a standalone write grant without implicitly granting read access;
- an agent reads only granted sections and receives section revisions;
- read-only agents receive the read tool but not update tools for that section;
  read+write agents receive both and can read their successful update results;
- a read containing a forbidden section returns a permission error and no
  values, even when other requested sections are readable; a corrected request
  for permitted sections succeeds without adding unrequested sections;
- an authorized read of an unfilled section returns null at that section's
  value level, with no nested placeholders, stored value, or revision change;
- reading a partially populated section returns only its stored variables, and
  the first write populates an unfilled section under its existing revision;
- an agent can update multiple variables through one object-update tool call, or
  one variable through the variable-update tool, without removing omitted section variables;
- root keys select sections and variable names select direct schema-declared keys;
  unmatched names fail validation without creating or traversing nested paths;
- names containing dots, slashes, or index-like punctuation never navigate;
  when explicitly declared as literal variables, they update only that exact key;
- nested partial changes use the object tool and preserve omitted siblings;
- an object update preserves omitted existing variables, allows still-missing
  variables, and rejects a wrong-datatype multi-variable update atomically;
- repeated partial updates collect variables iteratively, both for a new section
  and a new nested object, without a required-variable completeness check;
- a partial nested-object update preserves omitted sibling values at every
  object depth; a nested datatype failure changes nothing;
- shallow sections and schema-permitted nested objects both work without
  automatic flattening or an implicit ban on nesting;
- both update forms clear a nullable variable by storing null while retaining its
  key, including inside an object merge; omitted variables stay unchanged;
- null supplied to a non-nullable variable rejects the entire update atomically;
  permitting absence does not imply accepting an explicit null;
- no clear operation deletes a key or generates stored nulls for unfilled
  variables; a null read response is not a clear operation;
- ungranted sections expose neither values nor revision metadata in model
  projections; error responses cannot bypass those access rules;
- an unknown section, unauthorized section, untrusted identity, wrong incarnation,
  bad pointer, revision conflict, invalid resulting schema, or size violation
  performs no mutation and emits no success event;
- two valid changes in one request commit atomically with one section revision;
- conversational interruption does not cancel an already-submitted variables
  update; a later correction uses a new call with the appropriate revision;
- racing the original and correcting updates cannot silently overwrite a newer
  revision, and a stale update is not blindly replayed;
- direct variable reads/updates finish while `RoomAuthority` is not servicing
  messages, proving there is no hidden authorization or commit round trip;
- source-agent shutdown stops its capabilities and model/tool workers, but an
  already-sent valid variable update can commit afterwards without stale speech;
- B can read or refresh the resulting values under its own grants, and a queued
  A update cannot silently overwrite a newer B revision;
- the room-scoped variables process survives source-agent shutdown and human-only
  periods, while stopping that process gives no pending-write completion guarantee; and
- room snapshots and public events do not expose variable values.

After each coherent code checkpoint, run the umbrella completion checks:

```shell
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix deps.unlock --check-unused
```

Once the gateway accepts call definitions, add a manual sample using the working
JSON: start a room with `initial_variables.customer.id`, confirm the first agent
can read the initialized `customer.id`, ask it to store an `intake` summary,
advance a turn, and confirm the same room returns the saved value. A later
two-agent sample should transfer to `billing`, confirm `billing` reads the same
allowed data, and confirm it cannot update `intake` when its definition has only
`read`.

## Persistence, call records, usage, and artifacts

These concerns share correlation IDs and retention policy, but they do not share
one owner or storage shape. Separate the live room, relational records, object
artifacts, and derived publication:

| Concern | Live authority | Durable representation |
| --- | --- | --- |
| Definition drafts and immutable revisions | `vxpipe_calls` | PostgreSQL |
| Inbound number/service routing | `vxpipe_calls` | indexed PostgreSQL rows |
| Pinned definition and resolved plan for a running call | `RoomAuthority` | call row plus non-secret resolved-plan snapshot/digest |
| Mutable call variables | room-scoped `CallVariables` GenServer | full turn/tool-linked snapshots and a call-level latest pointer, committed before update success |
| Ordered call, turn, tool, transfer, and provider-usage facts | engine events | append-only PostgreSQL ledger plus query projections |
| Live participant and monitor audio | room media mixer | bounded realtime mix and mix-minus streams |
| Participant tracks and the live full mix | room recording capability | object storage plus relational artifact metadata |
| Optional repaired/remixed audio and final call-details JSON | post-call jobs | derived versioned objects plus publication status |

The database is the durable system of record for management and the call ledger;
it is not the live synchronization mechanism for a room. Object storage holds
large media and exported JSON; it is not queried to authorize a turn or transfer.
The final call-details object is a projection built from already persisted facts,
not the only surviving record of the call.

### Inbound routing selects an immutable definition revision

An inbound provider webhook cannot scan call-definition JSON looking for a
matching number. Publishing or deploying a definition must materialize an
indexed route from the definition's `receive` plus `start_call` participant
connection intent. The lookup key should include the trusted configured
telephony integration/account identity and normalized called number, not only
the number supplied by the webhook. The integration or verified endpoint first
establishes the application/tenant boundary.

Use separate persisted resources:

```text
CallDefinition
└── immutable CallDefinitionRevision(s)
    └── Deployment (for example, the currently selected production revision)
        └── materialized InboundRoute(s)
```

An inbound route records at least tenant/application scope, configured telephony
service identity, normalized called number, deployment, entry/admission
participant ref, enabled state, and effective interval. A database uniqueness
constraint prevents two simultaneously active routes for the same trusted
integration and number. Changing a deployment affects only calls admitted after
the change.

The webhook/admission sequence is:

```text
verify provider request and identify configured integration
  -> normalize provider call/event ID and called number
  -> resolve one active indexed route
  -> load the route's immutable definition revision
  -> validate initial variables and compile a resolved plan
  -> idempotently create the durable call admission record
  -> start the room with call ID, plan, and initialized variables
  -> mark the call running or record a typed admission failure
  -> issue provider-neutral leg/media commands
```

Do not hold a database transaction open while starting OTP processes or making a
provider API call. Use trusted provider admission identities, short database
transactions, and explicit `admitting`, `running`, `failed`, and terminal call
states. Repeated delivery of the same provider webhook must return or advance
the same call rather than starting a second room.

R39 does not offer API creation idempotency: no `Idempotency-Key`, duplicate-
suppression key, or response cache. Repeated authorized creation may create
separate prepared records for the application/user to delete later through an
authorized mechanism. This does not add a deletion endpoint or UI. Single-use
token claims, same-call admission exclusion, and provider webhook/leg deduplication
remain intact; they are not deduplication of separate creation requests.

R40 uses the short admission claim without holding a transaction across startup.
If the original room/leg still exists, identify it and finish bookkeeping without
starting another. If the actual runtime crashes or terminates, do not automatically
restart the call, redial, or reconnect the caller. Record uncertain provider dial
outcomes as failed/unknown as appropriate and clean up known resources, never make
a speculative second dial or promise remote rollback. Recover records about
existing work, not the phone call; no general durable recovery framework is added.

An outbound call follows the same admission path except that an authenticated
API invocation selects an allowed deployment or exact revision and the resolved
plan tells the room which `dial` participant to materialize. Every call row pins
the exact definition revision, schema version, and resolved-plan digest. A
deployment change never mutates that row or its active room.

### Stable call identity is distinct from a room incarnation

Introduce a `call_id` generated at admission and carry it through engine
commands, domain events, provider operations, variable updates, artifacts, and
publisher jobs. The call ID remains stable for bookkeeping about its existing
runtime and legs; R40 does not automatically recreate a crashed room. `room_id`
identifies the live collaboration/media scope, and `incarnation_id` rejects stale
work for one execution of that room. The initial implementation may enforce one
room per call, but the identifiers must not be conflated because a call can have
multiple telephony legs. Any separately designed future room recovery would need
another incarnation, not an implicit restart or redial in this slice.

The relational `calls` row should contain durable identity and summary state,
not every detail as one mutable JSON document. It records tenant/application,
definition revision, plan digest, direction, route/invocation identity, current
room/incarnation, lifecycle state, distinct `created_at`, `started_at`, and
`ended_at` timestamps, terminal reason, archive status, and
`latest_variables_snapshot_id` for the latest retained variables snapshot.
Do not store a per-call retention period, policy version, or fixed expiry; use
the current application/tenant setting when evaluating expiry. Provider-native
call IDs belong in a separate call-leg/provider-identity record with appropriate
uniqueness and redaction.

### Record creation and actual call start — approved timing contract

The call record exists independently of its live runtime. Keep these timestamps
distinct in call details and persistence:

- `created_at` is when the call record is first created. It is not the call's
  start time and does not change when a token is reissued or the caller joins.
- `started_at` is unset (`null` in JSON) until the first actual live-call start:
  the admitted caller starts the call runtime and the call transitions to
  `running`. Record creation, token issuance/reissuance, token consumption, and
  a still-pending startup do not set it. If admission fails before the call
  starts, it remains unset.
- The authoritative live-start transition supplies the occurrence timestamp.
  Calls persists that timestamp through its repository port when recording the
  running call; delayed database writes or event delivery must not substitute
  their own write/receipt time. Do not default `started_at` to the row's insert
  timestamp or fill it when preparation is saved.
- Set the first live-start time once for that call ID. Transfers,
  duplicate event delivery, token reissuance, and recovery of the same call do
  not restart the call clock. Room-incarnation and participant/leg timings are
  separate facts, not replacements for the original `started_at`. Connecting
  again after logical termination starts a new call with its own timestamp,
  rather than resuming the old caller in this slice.
- Report elapsed call duration from actual start, not creation. For an ended
  call this is the interval from `started_at` to `ended_at`; prepared waiting
  time is excluded. A call that never starts has no live duration. Any
  `max_duration_ms` call limit likewise starts with the live call, not with the
  stored record or token. Provider billing intervals remain separately measured.

For example, a record created at 10:00, actually started at 10:15, and ended at
10:18 represents a three-minute call, not an eighteen-minute call. The fifteen
minutes before joining are preparation wait, with no live call process tree.
This defines timestamp semantics only; no database columns or runtime lifecycle
implementation are added in this checkpoint.

### Persist facts incrementally and derive the transcript

Do not wait for `CallDetailsPublisher` to receive an in-memory transcript at the
end of the call. A node, room, provider, or deployment can fail before that
callback. Persist an ordered, idempotent event envelope during the call and build
query-friendly projections from it.

The minimum relational shapes are:

- `call_events`: append-only protocol-neutral event envelopes keyed uniquely by
  call ID, room incarnation, sequence, and event ID;
- `call_participants`: runtime participant ID, definition-local participant ref,
  human/agent type, admission/removal state, and timestamps;
- `agent_activations`: agent participant, activation ID, model/tool profile
  identity, start/end sequence, and terminal reason;
- `call_turns`: one row per committed human input or agent output with speaker,
  modality, correlation/utterance IDs, lifecycle, timestamps, and transcript
  provenance;
- `provider_operations`: one row per external STT, model, TTS, MCP, or telephony
  operation, including actual provider/model and request lifecycle;
- `usage_records`: normalized observations linked to the call and provider-operation
  attempt/component, with participant/service-interval and turn links when honest;
  effective amounts are derived without duplicating charges across those views;
- variable snapshot history: immutable full Call Variables snapshots with
  call/room-incarnation identity, originating turn/tool invocation, source
  participant, revisions, and commit timestamp for database-backed calls;
- `artifacts`: object key, kind, participant/connection/track correlation,
  timing, codec/content type, bytes, checksum, and publication state;
  and
- an outbox/job table for idempotent post-call publication and retries.

`call_events` preserves ordering and future replay evidence. The other rows are
projections for efficient product queries and publication; they can be rebuilt
from retained events where the retention policy permits it. Do not put audio,
large transcripts, or a continually rewritten all-call JSON blob on the `calls`
row.

Always save permitted available transcripts, turn details, and observed usage/model/cost
information with the call, alongside complete observed tool history and committed
variable snapshots. R38 qualifies the earlier no separate storage toggle per category
rule for transcript/audio retention independent of live sharing. It adds no new
usage/tool/variable toggle matrix. The approved `record_audio`/`save_transcripts`
booleans govern Vxpipe-owned automatic storage paths for the restricted interval.
Not saving transcripts does not itself stop recognition or permitted live sharing.
Conversely, live receipt is not archival permission. This does not start
STT, TTS, or prohibited processing merely to produce archival data. A text-only
call retains its submitted text without STT; if speech recognition is absent or
prohibited, do not fabricate a speech transcript. When retention permits the data,
keep these source facts distinct:

- committed human text input stores the submitted text and `text` provenance;
- human audio stores the provider-final committed transcript and provider/model
  identity; observed partial replacements are event facts, not new
  transcript turns;
- agent output stores generated text separately from confirmed delivered/spoken
  text, including interrupted or truncated state; and
- every turn names the runtime participant, definition-local participant ref,
  and agent activation when applicable.

Do not bypass `save_transcripts: false` through transcript copies in automatic
event archival, logs, exports, or model-debug archives. Enforce source-interval
privacy without claiming generic taint tracking/redaction of arbitrary externally
copied text. Prior permitted history is unchanged; tool-history and credential/
authorization-header exclusions still apply, and whole-call retention deletes
permitted retained data under its existing policy.

This follows the existing engine rule that generated assistant text and audio
confirmed as played are different facts. A final transcript must not claim that
interrupted generated text was heard. Preserve supplied word timing, confidence,
and provenance as bounded sidecar data when a provider supplies them; their
absence must not be replaced with invented precision.

Store available call audio only when recording is integrated, explicitly enabled,
and permitted. It remains subject to participant/room denials and the
`opening_audio` media-input gate, not an auto-enabled archive feature or redundant
storage-switch matrix. Available history does not grant wider client visibility
or agent access. Credential/header exclusions remain unchanged. General turn/tool/
usage archival stays asynchronous; variable snapshots retain their transaction-
confirmed tool-success boundary. Missing usage/prices stay unavailable, not zero
or invented observations. R44/R45 settle observation accounting and attribution;
pricing-source/version/fallback choices remain R46.

### Tool-history storage is independent of client visibility — approved G5 decision

Always store all observed tool invocation data with the call, regardless of client
visibility: invocation/participant/tool identity and metadata, timing/outcomes,
arguments/request payloads, and responses/results/errors. There is no tool-history
enable switch, metadata-only storage mode, per-tool payload selection, or
arguments/results opt-in. Integration credentials and authorization headers remain
excluded before persistence; removing them only from the final export is
insufficient. This is not raw wire credential capture or a general redaction
feature. An unknown timeout stays unknown; never fabricate a remote response.

The call-ledger/storage consumer must receive its own projection from the engine
event source, not reuse the browser-filtered stream. A hidden client tool event
still has its observed arguments/result stored. Metadata/full client visibility,
including in sample calls, does not change what is stored.
Storage access does not grant browser access, agent tool execution, or broader
agent variable permissions. General tool-history archival remains asynchronous.
The variable snapshot transaction below is an explicit acknowledgement boundary
for variable-update tools, not a reason to gate every tool or room event on SQL.
This capture requirement does not resolve archival failure handling or implement
a synchronous completion acknowledgement for ordinary tools.

For example, keep a booking tool hidden from the browser while saving its complete
observed invocation for operational review. Another call may show the result live
and saves the same complete history. Neither needs a tool-storage setting.
Retention periods use application configuration with tenant overrides and an
application retain-forever default. Completed-call finite retention starts at
`ended_at`, using the current period for both past and future calls. Periodic
external-first cleanup is approved below. General
sensitive-input redaction is deferred. Expiry deletes the entire call and its associated
Vxpipe-managed history and artifacts. This decision does not add runtime
persistence or guarantee complete room recovery.

### Variable history snapshots and the latest pointer — approved G5 decision

In a database-backed call, save a full post-update Call Variables
snapshot for each committed `update_variables` or `update_variable` invocation.
Link it to the call, room incarnation, originating turn, tool invocation, source
participant/activation, section/global revisions, and commit timestamp. Several
updates in one turn remain separate snapshots identified by invocation and revision,
not one overwritten history row. A delayed update stays linked to its original
turn even if a later turn or agent is now active. Rejected updates do not create
successful state snapshots; their failures remain tool-history outcomes.

Reuse the saved tool call and its arguments to inspect the requested change.
There is no separate changeset, patch journal, or duplicate argument payload in
the snapshot record. The always-stored complete tool history already includes
these arguments; no payload selection is needed. The snapshot records the
resulting state after merge, not just the
arguments or a claim that an attempted update succeeded.

`CallVariables` computes the complete candidate values and next revisions together
after validation, without yet publishing them as current state. It sends this
exact snapshot to its configured persistence port. Do not query the live
owner later and attach newer values to an earlier turn. Full means all populated
Call Variables, including unchanged sections, not only the updating agent's
readable section. Missing variables stay absent; no defaults are synthesized.
This is a private retention payload, not a larger tool result, public event, or
room snapshot for clients. Existing agent grants and storage/privacy boundaries
remain in force. Retained supplied initial values form a baseline snapshot with
no invented tool call or conversational turn. Initialize the call's pointer to
that baseline so latest lookup works before any update. Saving this baseline
does not start a prepared call's room or its live-call clock.

Store `latest_variables_snapshot_id` on the call record. An indexed lookup by
that ID, or a simple join, returns the latest persisted values without aggregating
history or maintaining a second mutable variables copy. This replaces the earlier
proposed `call_variable_sections` latest-state projection. In the persistence adapter,
insert a snapshot and conditionally advance the same call's pointer in one
database transaction. For a new update, a failed prior-revision/pointer check
rejects the whole transaction; merely inserting an older candidate without
advancing the pointer must not count as success. Transaction failure rolls back
the insert and any pointer change. Recognizing an already-committed operation
on retry is not a new update and must not replace newer in-memory values.
Use the existing event identity, revisions, and room-incarnation fencing for
idempotency and stale-delivery checks: retries must not duplicate history or move
the pointer backward, and a pointer must never reference another call's snapshot.

The variable-update tool returns success only after this database transaction
commits. On confirmation, `CallVariables` adopts the exact committed values and
revisions, emits the update event, and replies. A transaction error returns
variable-save failure and leaves current in-memory state unchanged, with no
update-success event; no failed database write becomes memory-only success.
Use ordinary transaction handling without an extra commit-status lookup or
reconciliation workflow. No second candidate update may pass a pending predecessor.
Database latency therefore affects the variable-update tool, but does not block
`RoomAuthority`, media, or unrelated capabilities. There is no separate changeset
or new write-ahead journal: the snapshot/pointer transaction is the required write.

This supersedes the earlier proposal to acknowledge a memory update and persist
its snapshot later. General call/tool/usage events can still be archived
asynchronously. Full process/room recovery remains a separate concern, not a
prerequisite to the normal variable-save transaction. An explicitly database-free
deployment has no database-commit guarantee; a database-backed call must never
silently fall back to it when storage fails. Storage duration resolves as below.
Referenced snapshots are deleted with the expired call, including its latest
snapshot. Cleanup follows the ordered periodic contract below; the exact database
schema remains an implementation follow-up.
This checkpoint adds no runtime behavior or migrations.

### Retention periods — approved application and tenant policy

Configure stored call-data retention periods at application level, with tenant
overrides. The application default is retain forever. An explicitly configured
tenant period wins; otherwise inherit the application period, including its
forever default. Periods are not agent-defined or client-selected settings.

**Approved R19 encoding:** the application/tenant setting `call_retention` accepts
the JSON string `"forever"` or a finite duration object, for example
`{"seconds":2592000}` for 30 days. Omitted application configuration defaults to
`"forever"`; omitted tenant configuration inherits the application value. An
explicit tenant `"forever"` overrides even a finite application period. These are
not call-definition, call-creation, or participant options, and are not copied
onto each call. No human-readable duration parser or null/magic sentinel is added.

Forever means Vxpipe applies no age-based expiration to retained data. It does
not start STT or recording, bypass privacy permissions, retain excluded credentials,
expose stored payloads to clients, keep room processes or live buffers forever,
or promise backup/recovery. Capability permissions, privacy, and
client visibility remain separate from how long permitted stored data is kept.

For example, leaving both levels unspecified retains permitted stored history
forever. Configuring an application period changes the inherited value, and a
tenant override changes only that tenant's effective period. An explicit forever
selection is also a period choice, not an absent configuration or zero-duration
expiry. The serialized setting uses the string or seconds object above.

For completed calls with a finite period, retention starts at `ended_at`.
Compute the expiry threshold as `ended_at + retention_period`, not from
`created_at`, `started_at`, individual snapshot insertion, or final archive
publication. A later storage write does not reset the call's retention clock.
Do not expire retained data while the call is active. Forever has no expiry
threshold, regardless of how old a call is.

For example, a record created Monday for a call that ends Wednesday, with
seven-day retention, reaches its expiry threshold the following Wednesday.
When `ended_at` is unset, do not substitute creation time. This completed-call
rule does not introduce automatic expiry for prepared/unstarted records.

The current application/tenant retention period applies to all calls, past and
future. Resolve the current tenant override or application fallback when
evaluating expiry. Do not pin the period, a policy version, or a fixed expiry
in a call record, room plan, or artifact as its governing retention setting.
The call's existing tenant/application identity and `ended_at` are sufficient
inputs; changing policy requires no per-call policy rewrite or migration.
This rejects applying changes only to new calls, which would require maintaining
separate historical retention settings per call. Pinned call definitions,
capability permissions, and client visibility do not become mutable as a side effect.

For example, changing a tenant from 90 days to seven days makes a call that ended
14 days ago eligible for cleanup. Increasing the period or choosing forever
changes eligibility for data still present, but cannot restore deleted data.
Application changes affect inheriting tenants; an explicit tenant override still
wins. These policy changes do not expire active calls or substitute creation time
when `ended_at` is unset. Eligibility is not a promise of immediate deletion.

Retention expiry deletes the entire call and all Vxpipe-managed data belonging
to it, not just its transcript or recording:

- the call record itself, including initial variables, any call-specific pinned
  definition/plan copy, and its latest-snapshot reference;
- participant/leg, agent activation, admission/token/claim, event/debug, and turn
  records, including transcripts;
- tool invocations and retained arguments/results, provider operations, and
  usage/token/model/cost history;
- every variable snapshot, including the baseline and latest snapshot;
- all recordings if present, including separate tracks, live mixes, derivatives,
  and their metadata/manifests; and
- published call-details documents, other call-specific exports/copies, and
  call-owned publication/outbox data.

The list is illustrative, not an exemption for other stored call-specific data.
Do not leave a soft-deleted call, summary-only record, or latest snapshot behind.
Shared call definitions and application/tenant configuration are not owned by
this call and remain; their call-specific copies and references are deleted.
Independent copies held by integrating apps or providers are outside Vxpipe's
control, not something this cleanup can promise to erase.

Both database rows and stored objects must be deleted. This is one deletion
scope, not an atomic transaction spanning the database and object storage.
Cleanup is not complete while call-owned data remains in either. Pending or late
archival/publication work must not recreate purged call data.

**Periodic external-first cleanup — approved R20/R21:**

1. Background sweeps select completed calls that meet the current application/
   tenant retention period from `ended_at`. Crossing the threshold does not
   instantly delete a call or start a per-call expiry timer. Keep the existing
   forever, active-call, and missing-`ended_at` exclusions. The sweep interval and
   deployment default are not selected here; there is no approved hourly cadence
   or exact deletion SLA.
2. Delete all managed call-owned external objects/copies before deleting call-owned
   database data or the call record. A definitive object-key-not-found response
   means that object is already absent. Only after every relevant object is
   absent may database cleanup proceed.
3. Actual object-store errors, timeout/unknown outcomes, and authentication or
   permission failures are not missing-key success. Keep the call/artifact rows
   and their object references so a later sweep can retry. If a job crashes after
   deleting some or all objects, the later job repeats deletes from those records;
   already-missing objects succeed before the remaining database cleanup.
4. A database deletion failure also leaves the call for a later sweep. Use these
   retained call/artifact records as progress rather than adding a per-object
   journal, separate reconciliation subsystem, or permanent tombstone. After
   successful cleanup, no call record, snapshot, or summary remains.

For example, deletion removes the audio object and then the worker stops before
removing the database row. The next sweep finds the eligible call, sees that the
audio key is already absent, deletes any other remaining call-owned objects, and
then removes its database data. A network timeout is not evidence that a key is
absent, so it cannot justify deleting the references needed for the next attempt.

The cleanup and archive/publisher owners must coordinate at their existing
responsibility boundary to prevent late work recreating purged data. External-
first ordering alone does not solve that race. No elaborate coordination
mechanism or new durable journal is approved here. Shared definitions/configured
assets remain untouched, including reusable opening audio not owned by one call.
Internal sweep retries are distinct from the tool/MCP executor's no-retry policy.

Unstarted-record housekeeping remains separate. No automatic cleanup is
implemented here. This decision does not alter
the requirement to commit a variable snapshot before update-tool success.

### Usage observations and call, participant, and turn attribution — approved R44/R45

A turn can incur multiple independent charges. One agent turn may require
several model requests because of tool rounds, several TTS requests because text
is segmented, and a long-lived STT stream that spans multiple human turns.
Telephony and MCP charges may be call-, leg-, or operation-scoped. Therefore a
single cost column on `call_turns` is insufficient.

Always store available usage/model/cost observations; there is no separate usage
storage toggle. Unavailable units or prices remain unavailable, not invented or
zero. Pricing-source/version/fallback policy remains R46; these decisions do not
select a rate catalog or manufacture a price when provider billing is unavailable.

Every observation belongs to the call. Add participant, activation, service-active
interval, call-leg, and turn correlations only where supported by the work/evidence.
Participant attribution does not require turn attribution. STT and TTS may run over
several service-active intervals for one participant, using actual observed starts/
stops rather than assuming continuous participant membership or inventing billable
duration. LLM requests can link to their agent/turn; TTS turn links depend on provider
support. Shared/unattributable work stays call-scoped, not equally divided across
turns. A canonical billable fact may carry call/participant/turn refs without becoming
three charges; each aggregate counts each effective service-operation attempt once.

Preserve actual provider request/operation IDs when available, with provider and
configured-integration/tenant namespace. Absent provider IDs remain absent; do not
label a local correlation ID as a provider-issued ID. Known usage units can coexist
with unknown monetary cost. The normalized evidence can carry:

- local operation/attempt identity and available actual provider request/operation IDs;
- capability (`speech_to_text`, `model_inference`, `text_to_speech`, `mcp`, or
  telephony);
- configured provider and actual provider/model/voice identifiers used after
  fallback;
- measured units as typed values, such as input/output/cached/reasoning tokens,
  characters, synthesized audio duration, transcribed audio duration, connection
  duration, or request count;
- observation/sequence/delivery identity when available, incremental versus cumulative
  semantics, and independent estimate/final/correction status with provenance;
- an available cost amount as exact decimal, currency, and component breakdown;
  preserve its observed source without selecting R46's pricing/fallback policy;
- an available provider billing reference or existing estimate-source metadata,
  not an assumed pricing catalog or rate;
- started/completed timestamps and success/failure/cancellation status; and
- call, room/incarnation, participant, activation, turn, utterance, and tool-call
  correlations that actually apply.

Retain observations and derive one effective usage amount per provider-operation
attempt/component. This supersedes the earlier one-immutable-row-per-operation
proposal. Incremental deltas and cumulative totals have different arithmetic;
estimate/final/correction status is a separate dimension, not an update mode.
Finality does not turn a delta into a total. Final evidence replaces estimates;
late stale estimates cannot override a known final. Explicit provider corrections
can lower or raise the effective amount. Do not blindly sum reports, use arrival
order as authority, or choose `max()` as the correction rule.

| Observed reports for one attempt/component | Effective usage |
| --- | --- |
| Incremental deltas 100 and 60 | 160 |
| Two distinct incremental deltas of 50 | 100; equal values are not proof of duplication |
| Cumulative 100 then 160 | 160, not 260 |
| Cumulative 1000, 1600, then final total 1700 | 1700, not 4300 |
| Final total 1700, explicit corrected total 1650, then stale estimate 1800 | 1650; correction can decrease usage and stale estimates do not win |

Deduplicate only where observation/sequence/delivery identity proves repeated
delivery. Keep units, currency, components, and provenance distinct. Do not add
a total to its included token subcategories, or coalesce distinct attempts that
each performed billable work. Failed/interrupted operations still retain observed
usage and must survive stale conversational-output filtering. Missing usage is
unknown, not zero. Never use floating-point amounts as billing records. Preserve
original observations when later evidence changes the effective amount; the
no-automatic-MCP-retry and cancellation contracts are unchanged.

A configured provider integration may include both its streaming service and an
optional asynchronous billing capability that looks up cost using persisted
provider IDs where the provider API supports that lookup. The lookup runs outside
the media hot path and `RoomAuthority`, can outlive the call room, and must not
block a live call or reset `ended_at`/retention. Not all providers expose request-
level billing; this does not guarantee later cost resolution. Existing tenant
integration authentication/isolation applies without per-call credentials.
Billing schema, API/credential details, dependencies, and provider implementations
are not chosen here. No fallback price/catalog calculation is adopted under R46.

Ordinary usage archival remains asynchronous, not a new transaction acknowledgement
gate like variable snapshots. R41–R43 still own archive overflow, export revision,
and finalization policy. All permitted-data/media restrictions and whole-call
retention remain; optional billing cannot recreate data already purged.

The current model provider boundary returns only text/tool calls/errors, so it
cannot carry usage. The current ReqLLM adapter classifies the final response and
discards its normalized usage even though ReqLLM exposes token and best-effort
cost data for buffered and streaming responses. A usage slice should introduce
a typed provider result plus a protocol-neutral `ProviderUsageRecorded` event
for every model request, including intermediate tool rounds. STT and TTS adapter
contracts need equivalent typed usage/finalization signals based on the unit the
provider actually reports. Measured service duration/characters remain evidence
with their source, not an invented billed amount or monetary fallback. The concrete
pricing/estimate policy still needs R46 review; this is not runtime implementation.

### Mix live; record participant tracks and the live mix

The room must mix audio in realtime. Participants need audio from the other
active sources, and an authorized silent monitor needs one full-room stream while
the call is happening. Waiting until call end cannot satisfy either requirement.

Treat live mixing as an engine-owned media pipeline under the room incarnation,
not as a database, gateway, or post-call concern. A `RoomMixer` receives
normalized, timestamped audio frames for every admitted audio-producing
participant. It produces:

- a mix-minus stream for each speaking participant, excluding that participant's
  own source to avoid feeding their audio back to them;
- a full-room mix for an authorized monitor that contributes no audio; and
- optional individual-track subscriptions for an authorized debugger.

The gateway owns only the monitor's external transport and authorization. After
admission, its output sink subscribes to the appropriate engine mix exactly like
another participant connection. Monitoring does not read audio back from S3 and
does not make the gateway the mixer.

The live mixer is a media-pipeline component rather than an external provider
capability. Recording is a separately enabled room capability. Its coordinator
lives alongside the call engine's other room capabilities and attaches bounded
media taps to the mixer inputs and outputs. That capability decides, from the
resolved call and participant policy, whether to retain individual tracks, the
full live mix, both, or neither.

The intended room topology is:

```text
RoomIncarnationSupervisor
├── RoomAuthority
├── CallVariables
├── RoomParticipantSupervisor
├── RoomCapabilitySupervisor
│   └── RoomRecording (when enabled)
└── RoomPipelineSupervisor
    └── RoomMixer (when the topology requires mixing or monitoring)
```

`RoomAuthority` authorizes participants, subscriptions, and recording policy,
but does not process frames or own mutable variables. `CallVariables` owns
variable state and access independently of agent execution subtrees.
`RoomMixer` owns realtime frame alignment and
fan-out. `RoomRecording` owns the room-scoped recording lifecycle and media taps.
Call-scoped `ArtifactWriter` workers are started through the artifact
application's owning dynamic supervisor; they monitor the recording session and
finalize or mark uploads incomplete if the room disappears.

The recorder must not perform object-store I/O in `RoomAuthority` or the live
mixer. It forwards bounded chunks to supervised artifact-writer processes. Those
workers upload rolling segments or bounded multipart parts to S3-compatible
object storage and persist artifact progress through the artifact metadata port.
This is the split between engine ownership and external storage:

```text
participant/agent audio
  -> RoomMixer
       ├── mix-minus -> participant output sinks
       ├── full mix  -> silent monitor output sink
       └── media taps -> RoomRecording capability
                           -> ArtifactWriter -> object storage
                           -> artifact metadata -> PostgreSQL
```

Recording the live full mix provides the single call-audio object requested for
ordinary playback. Recording individual participant/connection tracks at the
same time preserves speaker isolation and permits later repair, analysis, or a
different mix. These artifacts share one room clock. Every segment manifest
includes call, room/incarnation, participant, connection, track, codec/sample
format, monotonic start offset, sample count or duration, gaps, and terminal
status. Agent output is correlated with the utterance and the portion accepted
by the egress path; generated-but-discarded TTS audio is not recorded as delivered
call audio.

Object-store latency never blocks live mixing. Queue overflow and uploader
failure have explicit policy: normally mark recording incomplete and continue
the call; a deployment that requires recording may fail admission or end the
call. A post-call mixer is optional and consumes the timestamped separate tracks
only to repair or produce another presentation format. It is not the source of
the participant or monitor audio and is not required to obtain the normal
combined recording.

Recording remains an explicitly enabled and permitted capability, not a separate
per-category archival toggle. Disabling speech
recognition or synthesis does not disable recording, and enabling either does not
authorize recording. Participant/room policy must explicitly allow the media
tap, artifact type, and access scope; the opening-audio input gate still applies.
Storage duration follows the current
application/tenant retention period, not a participant-specific period.

### `CallDetailsPublisher` is a final projector, not the live recorder

`CallDetailsPublisher` is a good name for the post-call boundary if its job is
narrow: after a terminal call state, read persisted call facts and finalized
artifact manifests, construct a versioned JSON document, store it in object
storage, and record its checksum/object reference. It should not own the live
transcript, usage counters, variables, or audio buffers.

The versioned call-details JSON can contain:

- call identity, lifecycle, direction, route, definition revision, and plan
  digest;
- participants, connections/call legs, and agent activations;
- ordered transcript turns with speaker, provenance, interruption, and delivery
  status;
- provider operations and normalized usage/cost records, plus explicitly
  identified derived totals;
- tool and transfer summaries;
- permitted final variable sections or variables revision metadata according to
  retention policy; and
- separate-track, recorded live-mix, optional remixed-audio, and other artifact
  references with checksums and completeness state.

Publishing is an idempotent outbox-driven job keyed by call ID and archive schema
version. It runs outside the room process and retries safely. Required artifacts
may keep the publication in `pending` or `incomplete`; failure to build the final
JSON does not erase the underlying call ledger. Prefer immutable versioned
objects over overwriting one key when late usage reconciliation or artifact
repair requires a new publication.

### Umbrella application and Ecto boundaries

Do not add Ecto to `vxpipe_call_engine`. Its reusable contract should continue to
work with an inline/static call definition, an in-memory event sink, and no
database. Do not put Ecto schemas or direct `Repo` calls in `vxpipe_gateway`
either; the gateway owns HTTP/webhook verification and protocol translation, not
definition revisioning or call-ledger transactions.
The engine defines a small typed snapshot-commit port for database-backed variable
updates, injected through application/supervision settings. The persistence
adapter implements it alongside the repository ports owned by `vxpipe_calls`.
This is dependency inversion, not an engine dependency on Calls, Ecto, or Repo.
An explicitly database-free mode makes no database durability claim and is never
an automatic fallback for a failed configured persistence adapter.

The target umbrella split is:

```text
vxpipe_gateway
  -> verifies and normalizes HTTP/provider input
  -> asks the call-admission API to admit or attach a call
  -> after admission, sends realtime client/transport commands to call_engine
     and projects subscribed engine events

vxpipe_calls
  -> owns database-neutral call admission and archive application workflows
  -> selects definition/deployment through configured repository ports
  -> compiles the plan through vxpipe_call_engine contracts
  -> creates the durable call record through a port
  -> starts the room on live admission/authorized activation
  -> coordinates terminal publication

vxpipe_call_engine
  -> owns live room/participant/capability state and protocol-neutral events
  -> has no Ecto, PostgreSQL, S3, or gateway dependency

vxpipe_persistence
  -> owns Ecto.Repo, Ecto schemas, migrations, transactions, projections, and
     outbox persistence
  -> implements repository/journal ports defined by vxpipe_calls

vxpipe_artifacts (when the recording slice begins)
  -> owns object-store adapters, track writers, optional offline remix/export
     jobs, and archive objects
  -> implements artifact/publisher ports without entering the room hot path
```

The short responsibility test is:

- `vxpipe_calls` answers **which immutable definition starts this durable call,
  and what is its admission/publication lifecycle?**
- `vxpipe_call_engine` answers **what is happening in the live room right now?**
- `vxpipe_persistence` answers **how are the durable records read and written in
  PostgreSQL?**
- `vxpipe_artifacts` answers **how are retained media and exported documents
  written to object storage?**

`vxpipe_persistence` has one concrete purpose: it is the PostgreSQL adapter for
durable platform data. It owns the Ecto Repo, migrations, Ecto schemas,
constraints, transactions, query implementations, idempotent event inserts,
projections, and outbox rows. It does not own a live call, decide which agent is
active, mix or record audio, call a provider, authorize an RTVI command, or
construct the final archive document. Its Ecto schemas are database records, not
the domain structs passed through the call engine.

`vxpipe_calls` owns the application workflow that needs persistence. It uses
small repository ports synchronously from an admission task before a room starts.
For live admission, such as a verified telephony call or a token claim following
authenticated API preparation:

```text
Gateway webhook/API handler
  -> Vxpipe.Calls.admit(request)
       -> InboundRouteRepository.resolve(route_key)
       -> CallDefinitionRepository.fetch_revision(revision_id)
       -> CallEngine compile/resolve functions
       -> CallRepository.begin_admission(call, admission_identity)
       -> CallEngine.create_room(resolved_plan)
       -> CallRepository.mark_running(call_id, room/incarnation)
  <- admitted call/session result
```

The admission identity above belongs to same-call/provider admission, not an API
creation idempotency header. The running-state write records the actual live-start
occurrence timestamp, not the earlier record creation/admission-request time or the database write
time. It preserves the call's first `started_at` when retried or reconciled.

Browser preparation splits this workflow at the durable boundary: resolve and
pin the plan/variables, persist the prepared call, then return the scoped join
token without creating a room. An authorized join claims that preparation and
activates the same call ID before issuing its room-bound transport session.
It does not create another call row or resolve a newer deployment. Calls owns
both phases; the persistence adapter stores preparation and claim state through
ports. Accepted admission consumes the join token atomically; recovery resolves
the same call through the backend-authenticated workflow. Pending admission must
be checked for existing work, not recreated. Replacement issuance for an eligible
unstarted record is not caller reconnection to a running call. R40 permits finishing
bookkeeping for an existing room/leg, never restarting a crashed call or redialing
an uncertain attempt. Internal claim mechanics add no general recovery framework
or database transaction held across engine/provider startup.

In a managed deployment, `vxpipe_persistence` implements those repository ports
with Ecto. In a standalone JSON-configured deployment, static/in-memory modules
implement the same ports. The gateway calls `vxpipe_calls`; it does not know
which implementation resolved the definition. Repository calls are ordinary
bounded function calls made by the admission workflow, but the workflow never
keeps a database transaction open while calling the engine or a provider.

`vxpipe_call_engine` does not use the Repo for normal runtime persistence. Once a
room exists, it owns hot mutable state and emits ordered protocol-neutral events
to a supervised event dispatcher:

```text
RoomAuthority commits a lifecycle transition / CallVariables commits an update
  -> RoomEventDispatcher accepts the event for ordered delivery
       ├── gateway projection subscribers
       ├── call-ledger consumer -> CallLedger port -> vxpipe_persistence/Ecto
       ├── telemetry consumers
       └── authorized application subscribers
```

The dispatcher acceptance is a short in-memory operation with explicit queue
bounds. The call-ledger consumer performs database work in its own process,
batches when useful, retries idempotently by event ID, and reports lag/failure.
This keeps ordinary archival latency out of the room authority while making
committed turns, variable events, usage observations, transfers, and terminal
events available for storage. Variable snapshot commits are the explicit exception:
their tools wait for the snapshot port rather than this asynchronous event sink.

Variable events retain their section/global revisions and source attribution.
For retained update history, the full snapshot and call pointer have already
committed through the snapshot port before the update event is emitted. A private
projection can reference that snapshot and its original turn/tool linkage; the
ordinary ledger consumer must not create a second snapshot or become its commit
gate.
Dispatcher delivery order is not an atomic ordering of variable commits with
transfers: a source-agent update may commit after that agent shuts down. Reporting
an update does not route its authorization or state mutation through `RoomAuthority`.

There are therefore two different meanings of “inline”:

- A call-variable tool makes an inline bounded `GenServer.call` to
  `CallVariables`, which authorizes and computes the candidate, waits for the
  configured snapshot/pointer transaction, then publishes the committed state and
  returns success. The room authority is not on this request path; the adapter
  owns SQL and the bounded database transaction.
- Ordinary archival inserts follow the ordered event path and do not gate room
  commands or other tool results. The acknowledged variable-snapshot write does
  not make the whole room or media path synchronous with PostgreSQL.

Call admission itself is durably inserted before room creation because it is
outside the room hot path and needs idempotency for webhook retries. Call events,
transcript projections, usage, and artifact metadata are normally persisted
asynchronously. Variable snapshot/pointer transactions are committed before their
update-tool acknowledgement. This does not require a separate mutation journal
or decide the broader room lifecycle/recovery protocol.

`vxpipe_calls` is preferable to a generic `core` application: it has the cohesive
responsibility of a call's durable-neutral application lifecycle outside the
realtime room. `vxpipe_persistence` has the separate reason to change of the
relational storage implementation. Only `vxpipe_persistence` needs `ecto_sql`
and the PostgreSQL adapter, and only `vxpipe_artifacts` needs the object-store
client.

Dependency inversion avoids a compile cycle. `vxpipe_calls` defines small ports
such as definition repository, inbound route repository, call ledger, and
publication outbox, and receives configured implementation modules in its
supervision options. `vxpipe_persistence` depends on those contracts to implement
them, and also implements the engine-owned snapshot-commit port; neither
`vxpipe_calls` nor the call engine compiles against Ecto. The managed release
includes and starts the persistence adapter before reporting admission readiness. The
standalone JSON-configured release supplies static/in-memory implementations and
does not start a Repo.

The gateway therefore requires a call-admission implementation, not a database.
In managed mode that implementation uses `vxpipe_persistence`; in standalone
mode it uses the validated JSON catalog. The call engine requires only an already
resolved plan, configured event/media sinks, and a snapshot port for database-backed
variable updates. It issues no SQL or external directory lookup to find a number;
protected variable-based dial sources resolve from trusted call-owned data under
the pinned connection definition.

The engine event fan-out needs a first-class subscriber/sink boundary. The
current room authority sends most domain events only to the participant
connection that caused the turn, which is insufficient for a complete call
ledger. Add a protocol-neutral room event sink outside the authority hot path.
It receives the same ordered event once, then independently fans out to gateway
participants, persistence projection, telemetry, and other authorized consumers.
Persistence backpressure must not be hidden in a connection process or create
unbounded room mailboxes.

### Persistence consistency levels

The first ledger can be an asynchronous archive: a supervised sink batches and
idempotently inserts events, and the room remains available through a temporary
database slowdown. This may lose the final buffered events during a node failure
and is not sufficient to promise room recovery.

Variable updates have a stronger approved acknowledgement contract: a successful
tool result means its snapshot and latest-pointer transaction already committed.
The owner waits for that confirmation before making new values current. A
transaction error returns variable-save failure without publishing the candidate.
No separate commit-status lookup, polling, or reconciliation subsystem is required
for this slice. Transaction atomicity covers the snapshot and pointer together;
it does not guarantee reply delivery. A lost reply does not undo a committed
snapshot. This limitation does not add another current implementation prerequisite.

Full room recovery is not implemented or automatically invoked by this slice;
R40 expressly does not repeat a call after runtime failure. A future recovery
design would need its own approval. Committed snapshots neither restart a room
nor make asynchronous events lossless. Do not execute Ecto queries inside
`RoomAuthority` or hold a database transaction across room/provider work.

### Persistence red-green checkpoints

1. **Database-neutral admission ports:** in `vxpipe_calls`, test route resolution,
   immutable revision selection, plan compilation, call ID creation, and
   same-call admission exclusion using in-memory fakes. Prove no provider request or room
   process runs inside a repository transaction.
2. **Ecto adapter:** create `vxpipe_persistence` with Repo and migrations for
   definitions, immutable revisions, deployments, materialized inbound routes,
   calls, and same-call/provider admission identity. Use PostgreSQL integration tests for route
   uniqueness, revision pinning, transactions, and retry behavior; keep them in
   the tagged integration lane.
3. **Gateway admission slice:** make one normalized web or fake-telephony inbound
   request resolve a stored route and start the admitted room with its pinned plan.
   Replayed provider events/token claims cannot start that call twice; separate
   authorized API creation requests may create separate prepared records. The
   static JSON admission implementation must continue to work without Repo.
4. **Ordered call ledger:** add the engine event sink and persist call lifecycle,
   participant, activation, and final turn events idempotently. Build
   `call_turns` as a projection and prove partial STT updates do not create
   duplicate turns.
5. **Variable commit boundary:** persist private full post-update snapshots linked to
   turns/tool invocations, reusing recorded tool arguments rather than a separate
   changeset. Insert history and conditionally advance the call's latest-snapshot
   pointer in one transaction before tool success or publication of new in-memory
   state. Test a held commit, confirmed failure, duplicate/stale persistence requests,
   and latest lookup without replaying history. Prove public events and room
   snapshots still contain no variable value. Finalization uses committed snapshots,
   not an assumption that unconfirmed attempts were persisted.
6. **Model usage:** change the provider contract to preserve observations from
   each request/tool round, including partial/final/corrected reports. Derive
   effective attempt/component usage and honest turn/participant/call views
   without duplicate charges, invented cost, or floating-point billing records.
7. **STT/TTS/telephony usage:** retain honest participant/service-interval or
   call-scoped evidence and real provider IDs, with turn links only when supported.
   Exercise optional asynchronous supported billing lookup outside the room and
   preserve unavailable cost; do not choose R46 pricing fallback or R41–R43 guarantees.
8. **Live mixing and recording:** add a bounded room mixer with two fake
   participant inputs, mix-minus outputs, and a full silent-monitor output. Then
   attach the recording capability to one participant track and the live full
   mix, proving object-store slowdown cannot block mixer progress. Extend to
   rolling upload, timing manifests, multiple tracks, artifact rows, and explicit
   incomplete status.
9. **Call-details publication:** on a terminal call, enqueue one idempotent job,
   assemble versioned JSON from the persisted projections, include artifact
   checksums/status, upload it, and record publication success. Prove retries do
   not duplicate call, usage, or artifact records.

The smallest useful database vertical slice is checkpoints 1 through 3. It
answers the inbound number-to-definition question and pins a durable call record
without mixing transcript, billing, or recording into admission. The next slice
adds the event/turn ledger. Usage, recording, mixing, and final publication then
build on stable call and event identities rather than inventing their own.

### Persistence alternatives rejected

- **Ecto in `vxpipe_call_engine`:** couples the realtime/embedded engine to one
  database and puts storage failure pressure on room state transitions.
- **Repo calls in gateway handlers:** mixes provider protocol handling with
  definition/version and ledger transactions and makes non-HTTP admission harder.
- **One final in-memory publish:** loses the complete record if the call or node
  ends abnormally before publication.
- **One mutable call-details JSON row:** creates write contention, poor query
  boundaries, and no trustworthy idempotent event history.
- **Cost columns only on turns:** cannot represent multi-round model calls,
  streaming STT sessions, segmented TTS, call legs, or later reconciliation.
- **Only a combined live recording:** loses separate speaker tracks and makes
  overlap, remixes, and artifact repair harder.
- **Archival needs enabling processing:** available transcripts/turns and usage
  observations are stored, but this does not start STT or authorize recording;
  audio needs an explicitly enabled, permitted recording capability.

## Observable runtime contracts needed

The first multi-agent slice needs protocol-neutral events for:

- call admission requested, resolved, started, failed, and ended with stable
  call identity and pinned definition revision; actual live start carries its
  occurrence timestamp, distinct from record creation and event persistence;
- call plan resolved;
- agent participant admitted and ready;
- agent participant activated and deactivated;
- participant transfer requested, accepted, completed, rejected, failed, and
  cancelled, including source and destination participant IDs and kinds;
- presence-driven `media_policy`/`while_present` transition and enforcement outcomes,
  with authorized participant/route attribution, not superseded denial selectors;
- transfer packet created and delivered, with values redacted by visibility;
- call-variable section initialized, updated, or rejected, including section
  revision and trusted source-agent attribution, without a live-activation gate;
- provider operation started/completed/failed/cancelled and normalized usage
  recorded, including actual provider/model and correlation scope;
- recording track/segment started, finalized, incomplete, or failed;
- artifact and call-details publication queued, completed, incomplete, or
  failed;
- tool invocation lifecycle;
- routing changed; and
- call ended with a typed reason.

These are internal facts projected by audience. R36's detailed restoration failure
reason stays private even for full sample tool visibility; public ends/failures
and agent-facing results carry only generic outcomes without that detail.

Only one agent participant may own generated conversational output for a
connection/lane at a time. Inactive agent participants must not consume turns or
emit user-visible output. They also must not advertise or invoke their MCP
tools. A committed transfer shuts down the source agent's execution subtree, including its
capabilities and model/tool workers, and the destination receives its own tool
surface. Already-sent variable requests survive source shutdown in the separate
room-scoped variables process; remote outcomes and reconciliation remain a G4
decision.

Late conversational output from a previously active agent participant must be
rejected by room incarnation, participant, turn, and activation identity. This
does not reject or undo a variable request already submitted by that agent.

## Suggested red-green checkpoints

1. **Definition and invocation data:** red tests for a minimal one-agent
   participant catalog, both entry refs, dated schema validation, shared
   capability defaults, agent overrides, initial-variable validation, and a
   credential-free invocation. Implement immutable structs and pure path-specific
   validation only.
2. **Basic plan resolution:** use fake closed capability-profile registries to
   prove defaults and overrides resolve into a self-contained, secret-free
   `ResolvedCallPlan`; unused profiles leave no runtime binding.
3. **Call-variable contract:** test typed top-level sections, per-agent read/write
   grants, model-visible read projection, authorized writes, schema rejection,
   section revisions, and absence of ungranted sections.
4. **Participant and transfer data:** test human and agent participant
   definitions, connection intent, missing and duplicate transfer refs,
   absent/empty transfers producing no tool, non-empty transfers producing one
   closed destination choice set, participant kinds, transfer cycles,
   unreachable-participant linting, and path-specific errors. Presence/media
   validation must use R38's approved schema, not the superseded
   capability-denial selectors.
5. **Active-agent-participant reducer:** test activation, agent-to-agent and
   agent-to-human participant transfer, `active_agent_participant_id: nil`,
   terminal state, stale activation, and transfer-budget behavior using
   deterministic fake participants; implement a pure reducer with one optional
   active agent participant and activation ID.
6. **Behavior-preserving agent:** prove a one-agent resolved plan produces
   the same text/audio turn behavior as the current preset path.
7. **Human-only transfer:** using R38's approved policy structure, prove
   private briefing before acceptance and enforce permitted publication,
   subscriptions, live transcript sharing, and retention at the bridge boundary.
   The source remains until commit; no queued or later replay may bypass a
   restricted interval. This does not implement the historical denial schema
   or require per-transfer capability shutdown lists.
8. **JSON and gateway boundary:** round-trip definition/invocation data, reject
   unknown keys, dynamic atom creation, arbitrary runtime overrides, credentials,
   and tenant overrides.
9. **Integration resolution:** use fake application and tenant integration
   catalogs to prove tenant lookup comes from the authenticated principal, a
   tenant integration atomically replaces the application-wide integration,
   only agent-enabled tools reach model inference, unavailable tools reject the
   call, and no state crosses tenant boundaries. Produce private credential
   leases outside the public plan.
10. **Remote MCP execution:** behind the engine-owned tool backend, configure one
   HTTPS MCP integration, enable one tool on one agent, call it, preserve
   room/RTVI identity and event attribution, and prove ordinary spoken or typed
   interruption leaves an already-submitted request running until result or its
   existing timeout, without reviving cancelled speech. Keep the result tied to
   its invocation for subsequent reasoning, with no automatic variable mutation
   or additional old-turn tool execution. Separately prove transfer shuts down
   the agent's local execution subtree, without claiming remote rollback.
   Do not add stdio or an MCP server endpoint.
11. **Agent-to-agent participant transfer:** use two deterministic agent
   participants and one compiler-derived transfer tool to prove only the active
   agent participant receives turns, only its declared destination refs are
   accepted, the destination's required capabilities are ready before commit,
   and stale output is rejected.
12. **Scoped transfer packet:** prove allowed spoken history and typed variables
   reach the destination while hidden variables, private tool data, credentials,
   and unplayed text do not.
13. **Later workflow surface:** add deterministic `action`, human transfer,
    `wait`, and `branch` behavior only alongside its first concrete use. Do not
    assume a graph, subgraph, parallel-branch, join, or race model.

## Decision for the next checkpoint

Proceed first with typed `CallDefinition`, `CallInvocation`, and
`ResolvedCallPlan` contracts without MCP fields in the first proof. The smallest
proof is an inline one-agent participant catalog using schema `"20260906.02"`, a
human caller and agent receiver selected by definition-local entry refs,
shared capability-profile defaults,
typed call-variable sections and directly supplied initial variables,
per-agent section permissions, and bounded limits becoming a self-contained
immutable plan. Route the existing single-agent behavior through that plan
before adding participant transfer or integration resolution.

Remote MCP integrations still live in application or tenant catalogs, where
they are **configured** and made available. Each agent selects individual MCP,
built-in, or registered host operations in one **tools** map. An MCP entry names
its configured integration and remote tool; it requires no separate agent-level
integration-enablement block. MCP endpoints and credentials are neither
definition nor invocation data. A tenant integration atomically takes precedence
over an application-wide integration with the same stable ID; neither catalog
exposes its tools to every agent automatically. Do not begin an MCP transport
implementation until the general call-definition boundary exists.

Use the participant-definition public input with two explicit entry refs and
agent-scoped tools. The private plan contains resolved participant specs,
connection intents, transfer allowlists, and tool bindings; it does not contain
generic nodes or edges. The room directly owns the pinned plan, participant
routing, and the optional active agent participant, and a running room may have
no agent participant. Platform tools include at least `hangup`, `transfer`, and
the permission-constrained call variable read and update operations. A participant
transfer does not enumerate capability shutdowns; R38 uses presence-driven
`while_present` restrictions over normal `media_policy` for publishing/subscription,
live transcript sharing, and separate transcript/audio retention. Enforce authorized
routes/capture before main-media connection at commit without treating the
historical denial schema as final. Do not start with Lua,
arbitrary executable hooks, natural-language condition evaluation, or a broad
workflow interpreter.

The typed call-definition constructor/compiler remains the prerequisite for
database work: storage must not make unvalidated JSON authoritative. After that
contract is green, the first persistence vertical slice introduces
database-neutral admission in `vxpipe_calls`, the Ecto/PostgreSQL adapter in
`vxpipe_persistence`, immutable definition revisions and deployments, an indexed
inbound route, and one idempotently created call row that pins the resolved plan.
Do not combine transcript, usage, recording, or final publication into that
admission slice; add them incrementally through the ordered event and artifact
boundaries described above.

## Design gap review — pending approval

The existing participant-first structure still fits the intended scenarios.
Keep `entry_caller` and `entry_receiver`, direct participant-ref transfer lists,
agent-scoped tool enablement, immutable resolved plans, room-owned variables, and
live mixing. This checkpoint identifies missing contracts and inconsistencies;
it does not add runtime functionality. G1 records the approved tool layout and
G2 records the approved web routes, direct initial variables, hash-only API-key
storage, OTP/CLI bootstrap, tenant-bound `admin`/`calls` scopes, independently
revocable multiple keys, and no revocation coupling to already-issued tokens.
Token lifetime defaults to five minutes; authenticated requests may ask for
longer. It also approves single-use tokens with existing-call recovery and no
automatic call-record expiry, prepared-token and direct-backend connection flows,
explicit initial participants/startup, and one
participant per definition key per call. G3's initialization rule now permits
only supplied setup values, with no variable defaults. Its interruption rule
allows submitted variable commands to finish under existing authorization and
revision checks, with corrections made through later tool calls. Read requests
containing a forbidden section fail as a whole with a permission error. The two
update forms are retained, with object updates recursively merging supplied
objects and preserving omitted variables. Missing authorized reads return one null
at the requested value level without storing placeholders. First writes populate
sections; subsequent writes collect variables iteratively. Datatypes still match,
but required-variable presence is not validated at setup or on updates.
Agent section grants are read-only or read+write, so the write-only projection
and error-handling proposals no longer apply.
Explicit null assignment clears nullable variables without removing keys;
physical deletion is deferred. Root keys are
section names and direct section keys are literal variable names; deeper updates
use the object tool. Call Variables and its tool names are approved. The agent
records MCP results through these tools; the platform-only result-section and
automatic mapping proposals are withdrawn. A dedicated room-scoped `CallVariables`
GenServer now owns values and validates direct tool requests using pinned grants,
without a current-activation check. Source-agent subtree shutdown prevents new
work, not completion of already-submitted variable requests. Additional schema
complexity limits are not adopted now; datatype and value-size checks remain.
G3 is resolved in documentation. G4 now preserves submitted MCP calls across
ordinary conversational interruption and reports a timeout without a definitive
remote result as outcome `unknown`, without automatic executor retry. Later
agent-requested calls are separate invocations. Late business notifications are
deferred to future external-event delivery to active rooms/agents. Generic
platform confirmation is out of scope; conversational confirmation belongs to
agent instructions and enforceable business authorization to the application/MCP.
G5's call-level client tool visibility and full-visibility sample calls are
approved, with tool events hidden by default. Per-tool overrides use participant
definition key plus local configured tool key, otherwise falling back to the
call-wide default. Independent tool-history storage always retains all observed
metadata, arguments/request payloads, and responses/results/errors, with credential/header
exclusions. Variable history now saves full post-update snapshots linked to turns
and tool invocations, without separate changesets; the call record points to the
latest persisted snapshot. Database-backed update tools wait for the snapshot/
pointer transaction before returning success. Retention periods resolve from
tenant overrides and application settings, with retain forever as the application
default. Normal transaction errors return variable-save failure; no extra commit
reconciliation is required. Completed-call finite retention starts at `ended_at`;
active calls are not expired, and forever has no expiry threshold. Available
transcripts/turns and usage/model/cost facts are stored when permitted; audio requires
enabled, permitted recording. R38 separates transcript/audio retention from live
sharing without changing mandatory tools/variables/usage or inventing missing data;
periodic external-first cleanup is approved.
General voice/LLM-input
redaction is deferred. Current application/tenant periods apply to all calls, past and future,
without per-call retention settings. Expiry deletes the entire call and all
associated Vxpipe-managed data, including its record and latest variable snapshot.
First-message modes and first-activation-only greeting behavior are approved.
The source agent stays responsible until successful transfer commit and receives
failed-attempt outcomes. G7's current-slice decisions are resolved; deferred
voicemail delivery and G8's remaining questions are distinct from approved work.
Open decisions are listed individually in the focused review document.
Detailed reasoning and evidence live in the
[call-definition gap review](../docs/call-definition-gap-review.md).

### Remaining review count — 2026-09-08

There are **8 individual decisions awaiting review**, enumerated as R41–R43 and R46–R50
in the focused gap review. R01–R06, R08, R10–R15, R17–R23, R26–R40, and R44/R45 are resolved;
R07's caller reconnection, R16's retry exceptions, and R24/R25 are deferred; R09's setup limits are
superseded. All retain their IDs. Additional tokens do not supersede unused ones,
and initial variables already belong to creation. Personalization/time context
stay with application/agent instructions; R13 uses protected initial routing
variables without expanding the model's transfer arguments.
G1/G3, G7/G9's current-slice decisions, and G10's initial scope are closed;
G2/G4/G5/G6/G8 retain follow-up context without reopening R38's approved structure.
G headings are background
organization, not the current count. Earlier progress entries retain their
historical group counts and do not describe the current individual-item total.

Count only an unresolved choice requiring user approval. Do not count already
approved behavior awaiting implementation, tests, SQL indexes, adapter internals,
or each JSON key as another product decision. Explicit cancellation, late
external-event delivery, general redaction, and generic platform confirmation
remain deferred/excluded rather than current-slice prerequisites. DTMF collection
integration, OAuth onboarding, and optional post-call summary/evaluation are
separate future feature designs. There is still no additional automatic expiry
for unstarted records. R32's machine-disconnect policy is resolved; leaving
voicemail moves to a deferred issue. R37's bounded private briefing is approved;
its media representation and commit boundary are resolved by R38.
R44/R45's accounting/attribution choices are resolved; pricing remains R46.
The next five are R41–R43 and R46–R47.

### Baseline and scope

- The pre-review labnote was already committed in `e7a769e` and the worktree was
  clean before editing. Review documentation will be a separate checkpoint.
- The original review preserved schema examples and decisions for comparison.
  Approved follow-ups align G1's tool examples and document G2's tenant-scoped
  start/join routes and authenticated direct-variables admission. Obsolete input
  mappings are removed from both variables examples and the invocation example.
  A further approved follow-up replaces `entrypoint` with two entry refs and
  records startup behavior. The subsequent cardinality decision allows only one
  participant per definition key in each call. The admission simplification
  supersedes client-ID/HMAC signing with API keys and two connection flows.
  Its storage follow-up approves one-way hashes for Vxpipe-issued keys while
  keeping recoverable upstream credentials separate.
  The token follow-up approves atomic single-use admission and backend-authorized
  issuance for the existing call record, separate from browser joining.
  The expiry clarification rejects an additional unstarted-call deadline: only
  the token expires, while record retention remains a separate concern.
  The variables correction removes default values from both schema examples and
  the initialization contract. Capability/profile defaults remain unchanged.
  The interruption follow-up rejects an additional turn-cancellation check for
  submitted variable updates while preserving revision and lifecycle checks.
  The read follow-up rejects silent filtering: a forbidden section causes the
  entire request to fail without values. It also records the requested object
  and variable update tools without selecting merge/replace semantics or new names.
  The merge follow-up selects preservation of omitted section variables and
  atomic validation of the merged result. The recursive-merge clarification
  preserves omitted nested variables too and recommends shallow authoring such as
  a dedicated `address` section. Explicit null now clears nullable variables without
  removing their keys; physical variable deletion is deferred.
  The addressing follow-up fixes root keys as section names and direct section
  keys as literal variable names; the object tool handles deeper partial updates.
  The incremental-population follow-up returns a single null for a missing read
  value and allows first writes to populate it. It supersedes required-variable
  completeness checks, while retaining datatype and supplied-value validation.
  The permission follow-up limits agent section grants to read-only or
  read+write. Standalone write grants, revision-only writable projections, and
  special write-only errors are no longer part of the design.
  The naming follow-up adopts Call Variables and calls each direct value a
  variable within a section. It also settles MCP results: the agent saves them
  through our variable tools, without automatic mappings or MCP awareness of
  Vxpipe. The prior platform-only result-writer proposal is withdrawn.
  The other proposed corrections still require review.
- No engine, gateway, dependencies, application configuration, or tests changed.
  No new umbrella application, provider call, or database was introduced.

### Gaps and options to review

The numbering below matches G1–G13 in the focused review document.

1. **Tool layout — approved and documented:** each agent has one `tools` map
   containing MCP, built-in, and registered host bindings. An MCP entry uses
   `type: mcp`, `integration`, and `tool`; a built-in entry uses `type: platform`
   and `tool`. The map key is the model-visible alias. Application/tenant
   configuration controls integration availability and allowed operations;
   listing a selected tool needs no separate agent `integrations` block. The
   earlier separate-block proposal is withdrawn. Examples now consistently use
   `participants` and read-only `billing` access to `intake`; transfer and variables
   tools remain compiler-derived. This resolves G1's documentation ambiguity,
   not the future compiler implementation or its verification.
2. **Admission — routes, variables, credentials, and entry roles approved:**
   tenant-scoped HTTPS routes select the participant connection key when starting
   a call and additionally the public call ID when joining one. Tenant keys are
   16 URL-safe random characters; participant keys and call IDs are UUIDs, separate from
   database primary keys. Joining uses the call's pinned definition and requires
   authorization before a transport session is issued. Initial variables now
   matches the definition's sections directly; no separate input-binding layer.
   The integrating backend holds a gateway-issued API key and sends unsigned
   variables over TLS. It may prepare a call and give its frontend only a scoped
   join token, or join with that token itself. No separate direct WSS start or
   first-message initial-variables path remains. Preparation pins/stores variables
   without starting the room; authorized joining activates it. Browser HTTP signaling uses
   configured CORS grants; browser WebSockets require Origin validation.
   Admission may initialize sections that agents can read but none can write.
   `entry_caller` and `entry_receiver` are required refs to different participants
   in the same catalog. Startup selects those two, not every catalog entry;
   configured opening audio permits capability warmup but gates participant
   audio delivery and normal conversation until playback completes. Omitting it
   uses normal startup without a notice delay;
   other participants are admitted later as required. Initial refs remain pinned
   across transfers. The caller-start route must agree with `entry_caller`.
   Each definition key can bind only one participant in that call. A different
   person cannot claim an occupied key. Permitted agent re-entry uses the existing
   participant, while same-call caller reconnection is deferred.
   API-key storage is resolved: persist only one-way hashes, show keys once,
   and verify submitted keys without recovering secrets. Upstream MCP/provider
   credentials remain separate and recoverable where needed.
   First-key creation uses trusted OTP/CLI administration. API-key permissions
   are tenant-bound with `admin` and `calls` scopes; multiple independently
   revocable keys support separate integrations and overlapping rotation.
   Revoking a key blocks further authentication with it, not already-issued
   join tokens or established connections. No token-to-key revocation coupling
   is required. Tokens default to five minutes; the authenticated requester may
   request longer, with no additional maximum approved here.
   Join tokens are consumed once at accepted admission. Before acceptance an
   unused/unexpired token can be retried; replacement issuance for an eligible
   unstarted record reauthorizes via the backend and existing-call `join-tokens`
   route. Issuing another token does not invalidate earlier unused ones; each
   retains its expiry/single-use status, with shared admission checks preventing
   duplicate callers. Reconcile pending admission first and reject ended calls
   or active-connection takeover. Token expiry does not end an established call.
   Unstarted call records have no separate automatic expiry; an expired token
   prevents joining with that token, not later authorized fresh-token issuance.
   Their `created_at` is distinct from `started_at`, which remains unset until
   actual live startup and is preserved across transfers/recovery. Connecting
   after logical call termination starts a new call. First admission of an eligible
   transfer destination into a live call remains supported. Call duration excludes
   preparation wait.
   Record cleanup is separate from admission/token expiry. Retention periods now
   have an application retain-forever default with tenant overrides. G2 still needs
   temporary transport failure versus call-end triggers, issuance retry
   details, and admission/transfer crash handling. R10 already uses initial
   variables supplied by an authorized creator/backend/trusted ingress, leaving
   unknown values unfilled without a new automatic resolver. There is no blanket
   participant-disconnect hangup rule.
   R11 leaves personalization to instructions/permitted variable reads, and R12
   leaves locale/timezone/business-time context to the integrating app with date
   tooling. No new template engine or call-level time configuration is required.
   R13 permits either a literal dial number or a direct section/variable source
   protected from every agent's writes. The backend supplies an authorized number
   at creation; engine resolution needs no agent read grant. Transfers still
   accept only allowlisted participant refs, and missing/null/invalid numbers fail
   before dialing with source responsibility retained. No generic outbound policy
   matrix or variable-expression language is introduced.
   A valid API key authenticates the integrating application, not the speaker's
   customer identity; the backend authorizes the supplied business variables.
3. **Variable initialization, interruption, reads, and object merging resolved:**
   there are no variable defaults and no initialization merge. Only authorized
   call-setup input prefills variables. Validate supplied datatypes and value
   constraints, not required-variable completeness, and leave omitted values
   unfilled. An authorized read returns null at a missing requested value's
   level, without generating nested placeholders or storing a default. The
   first write populates the section, and later writes collect variables iteratively.
   Both variable schema examples now omit defaults and required-variable lists;
   capability/profile configuration is unchanged.
   Submitted local variable updates continue despite conversational interruption
   and source-agent shutdown; corrections use another tool call. Keep room/agent
   identity, permission, deadline, schema, size, and revision checks, but add no
   current-activation or live-turn/tool-cancellation guard or
   mutation journal. A delayed conflicting update must not overwrite a newer
   revision or be blindly retried; committed values are not rolled back.
   Mixed authorized/unauthorized reads fail as a whole with a permission error
   and no values; do not ignore forbidden names. A corrected request can succeed.
   Object-level updates deep-merge supplied objects into existing section data,
   preserving omitted variables recursively and validating populated values without
   demanding missing variables. Prefer simple, shallow sections, such as a dedicated
   `address`, without banning schema-permitted nesting. The single-variable tool remains
   available. Explicit null clears schema-nullable variables while retaining their
   keys; omission preserves existing values. Physical deletion is deferred.
   Addressing is resolved: root section names and direct literal variable names,
   with deeper changes expressed as objects through `update_variables`. Naming
   is settled: Call Variables, sections, and variables, with `read_variables`,
   `update_variables`, and `update_variable` as the tool names.
   Permissions are read-only or read+write; standalone write grants are invalid.
   Every writable section is also readable, removing the write-only error
   question and revision-only writable projection. Ungranted sections stay
   absent from projections. Do not add schema-depth or declared-variable-count
   caps now; datatype and value-size checks remain. A dedicated room-scoped
   `CallVariables` GenServer owns state and permissions, and receives tool calls
   directly without `RoomAuthority`. Transfer terminates the source agent's whole
   execution subtree, not the variables process or its already-submitted requests.
   MCP result handling is settled too: the agent receives the MCP result, then
   saves relevant data through the variable tools under its normal permissions.
   Remote MCPs need no knowledge of Vxpipe. The platform-only result-section and
   automatic result-mapping proposals are withdrawn. External services still own
   their business rules; copied variable values do not replace those services.
4. **External side effects — interruption and timeout reporting resolved:**
   interrupting speech does not show intent to cancel a tool call. Submitted MCP
   requests, including reads, continue to result or their existing timeout while
   the agent remains running. Completion remains associated with the invocation
   for subsequent reasoning, not a revival of old model output or an automatic
   variable write. Transfer still shuts down the source's local execution subtree.
   A submitted MCP request that times out without a definitive result reports
   outcome `unknown`, not confirmed failure or rollback. Preserve a definitive
   outcome if already known. The executor does not automatically retry any
   failure, including known non-submission; a later agent-requested call is a separate invocation, without an
   exactly-once guarantee.
   Late booking confirmations are an external concern: a future gateway webhook
   or other external event could reach the relevant room/agent while the room
   is active. Handling that scenario, including reconciliation and operation
   storage solely for it, is deferred and not required for the current slice.
   R15 skips trusted tool classification; R16's retry/idempotency exceptions are
   deferred to their issue. R39/R40 admission concerns and ordinary database
   transaction handling remain separate. Explicit cancellation is deferred
   to its issue and is not a current-slice prerequisite. Any future retry
   exception would need its own idempotency/reconciliation contract;
   none is approved by the no-retry default. Generic platform-level confirmation
   is excluded for now: agent instructions can request conversational confirmation,
   while the application/MCP owns enforceable business authorization. Prompts
   are not a security guarantee; Vxpipe's tool-access checks remain. A start event
   is not proof of successful completion.
5. **Private tool data and archive projections — partly resolved:** resolve
   client tool visibility from the definition and any authorized call-creation
   selection, and pin it with the call. Support no tool events, metadata only,
   or full arguments/results; sample calls explicitly select full visibility.
   Omitted visibility hides all tool events; joining browsers cannot change it.
   Per-tool overrides target participant definition key plus local configured
   tool key and take precedence over the call-wide default. `tool_visibility`
   and `tool_visibility_overrides` now define that policy pair; trusted creation
   can replace it, and samples use full with no overrides. Runtime implementation
   remains pending. Tool-history storage always
   retains observed metadata, arguments/request payloads, and responses/results/errors,
   independently of visibility, with credentials/authorization headers excluded before
   persistence. Variable history uses full post-update snapshots linked to the
   originating turn/tool call, reuses saved tool arguments without a changeset,
   and advances the call's latest-snapshot pointer transactionally before update
   success. Application retention defaults to retain forever, with tenant settings
   overriding application values. `call_retention` uses `"forever"` or an explicit
   seconds-duration object; omitted tenant settings inherit, while explicit
   forever overrides finite application retention. Transaction error means
   variable-save failure; extra commit-status lookup/reconciliation is not
   required. Available transcripts, turn details, and usage/model/cost facts are
   stored when permitted; audio needs enabled, permitted recording. R38's explicit
   transcript/audio retention is independent from live sharing under the approved
   room-wide `record_audio`/`save_transcripts` booleans.
   This does not start forbidden processing or invent missing data. General voice/LLM-input
   redaction is deferred; deterministic collection such as DTMF need not involve
   the LLM, but its recording/logging paths still need explicit protection.
   Completed-call finite retention starts at `ended_at`;
   active calls are not expired, and forever has no expiry threshold. The current
   application/tenant period applies to past and future calls; no per-call
   retention settings.
   Expiry deletes the call record and all associated Vxpipe-managed data, including
   every variable snapshot, usage history, recording, and export. Shared definitions
   and application/tenant configuration remain.
   R20/R21 use periodic background sweeps, not instant per-call expiry timers.
   Delete all external objects first, then database data; definitive key-not-found
   succeeds, while errors/unknown outcomes preserve rows/references for retry.
   No new progress journal or permanent tombstone; late writers still require
   coordination. Exact interval/default is unspecified, not an hourly policy.
6. **Remote integration compatibility — partly resolved:** R22 selects
   `2026-07-28` Streamable HTTP with JSON/request-scoped SSE and its metadata/
   lifecycle; incompatible revisions need explicit compatibility work. R23 uses
   proper JSON Schema validation of outgoing arguments before submission, without
   weakening schemas or automatically fetching refs. R24 result/document inspection
   and R25 server-requested interactions are deferred, not automatic fetching,
   server authority, or retry exceptions. Store received responses and let agents
   choose authorized next steps. R26 adopts outbound SDK-aligned address/TLS
   safeguards, explicit host authorization for private destinations, and no
   automatic redirects. Discovery and credential lifecycle remain
   pending. Existing HTTP actions still need a remote MCP facade or trusted host
   adapter; they are not automatically MCP tools.
7. **Greeting, silence, voicemail, and ending — current slice resolved:** agent-selected
   wait-for-input, fixed greeting, and generated greeting modes are approved for
   first activation only; reconnect/reactivation do not replay the greeting.
   Readiness defaults to a configurable 30 seconds from post-join startup;
   genuine agent input-wait defaults to a configurable 15-second idle notification.
   Long tools have no automatic progress cadence, and wait music is deferred.
   The whole-call limit defaults to 30 minutes, pinned with definition/tenant/
   application precedence and measured from actual start, including human-only
   portions. R31 leaves closing wording and hangup timing with instructions,
   without a new platform drain/closing API or playback guarantee. R32 uses
   configured provider AMD when supported: machine disconnects that attempted
   destination leg, retaining a transfer's original caller/source. Unknown still
   requires explicit acceptance within the existing total deadline; absent detection
   is not classification evidence. Leaving messages is deferred. Preserve provider
   uncertainty and the no-local-model/no-local-VAD scope.
8. **Transfer policy and media routing — partly resolved:** the source agent stays
   responsible until committed handoff; failed attempts return to it for the next
   permitted action. Only success terminates its execution subtree. R33 chooses
   call-level `transfer_policy`, source allowed-ref lists, and destination
   connection/acceptance requirements without source/per-pair defaults. R34 needs
   agent readiness or human usable media plus current-attempt-bound explicit
   DTMF/web acceptance. R35 has one configurable 30-second attempt deadline and
   exact-leg late-callback cleanup, without auto-redial. R36 allows one bounded
   permitted-source restoration attempt, then ends if no usable conversation
   remains; failure detail is internal even for samples. R37 includes private
   destination briefing/optional notice before explicit acceptance/bridge, sharing
   only permitted minimum-necessary information and excluding the caller. This is
   not general concurrent-agent consultation; R38 supplies representation/routing.
9. **Presence-driven media/transcript policy — resolved:** R38 supersedes
   primary capability denials with explicit publishing/subscription, independent
   live transcript sharing, and transcript/audio retention. Normal `media_policy`
   and participant `while_present` use complete source-to-recipient allowlists and
   room-wide storage booleans. Omission inherits, explicit empty maps allow none,
   present policies intersect, and storage false wins under host authorization.
   Apply restrictions at commit before main media, after private preparation and
   acceptance. Stop STT only when no permitted live/storage consumer needs it.
   Preserve no unauthorized capture, queued-output/reactivation bypass, or delayed
   replay; storage restrictions affect the interval, not prior permitted history.
   Variables remain unchanged.
10. **Admission crash recovery — resolved scope:** distinguish webhook delivery
    IDs from stable call/leg admission identity. Transfer legs attach to their
    pending transfer, not a fresh lookup. R39 adds no API creation idempotency;
    separate requests may create separate prepared records. R40's short claim
    and bookkeeping may identify an existing room/leg, never restart a crashed
    call. Mark uncertain dial outcomes failed/unknown as appropriate and clean
    known resources without speculative redial or remote rollback promises.
11. **Archive completeness and finalization:** specify bounded per-consumer
    overflow behavior and explicit incomplete state. Current typed-input events
    lack the submitted text needed to reconstruct a transcript. Call end,
    operation settlement, artifact completion, and publication are distinct.
    Consider publication revisions and source watermarks, not only a call/schema
    job key, so late corrections can produce another immutable export. Retain
    engine-side live mixing/recording with external upload workers; upload is not
    a live monitoring feed. Distinguish sent from device-confirmed audio.
12. **Usage settlement — R44/R45 resolved, R46 pending:** preserve observations and
    effective attempt/component usage. Distinguish delta/cumulative mode from
    estimate/final/correction status, deduplicate only proven repeat identities,
    retain failed/interrupted usage, and avoid included-subcategory double counting.
    Every fact belongs to the call; participant/service-interval/turn links are
    optional and evidence-based, with no forced turn allocation or duplicate charge.
    Keep real namespaced provider IDs for optional later supported billing lookup
    outside the room. Missing units/cost stay unknown; pricing-source/version/
    fallback remains R46, not a chosen rate catalog.
13. **Provider profiles and long-call budgets:** specify supported profile
    options, adapter compatibility, token-aware model-context/history budgets, and
    fallback behavior without arbitrary executable provider configuration.
    Fallback cannot weaken permissions or repeat an uncertain external action.

### Planned acceptance steps, after approval and implementation

These are future verification scenarios, not capabilities available in the
playground today. Use deterministic fakes first and synthetic data throughout.

1. Compile one definition whose initial variables comes directly from
   `initial_variables`, with no mapping or defaults. Missing variables do not prevent
   setup; wrong datatypes and other invalid populated values must fail before
   a room or provider starts.
   Reject section-level and nested variable defaults; retain ordinary capability
   defaults. Supply only `customer.id` and confirm no `intake` value is invented.
   Omission prefills no values. Explicitly supplied empty section objects are
   allowed, not instructions to populate defaults. Repeat with missing variables
   inside a supplied nested object; no required-variable check demands them.
2. Start a room, save intake through the agent tool, then read it on another
   turn. First check definition compilation accepts `["read"]` and
   `["read", "write"]`, rejects `["write"]` without silently adding read, and
   grants no access to an omitted section. Read-only grants expose the read
   tool; read+write grants also expose updates and their resulting section value.
   Verify ungranted sections expose neither values nor revision metadata in
   model projections. Transfer to a read-only agent; the value remains available
   but writes fail. Request both a readable and a forbidden section; expect a
   permission error with no values, then retry the readable section alone successfully.
   Confirm success does not add unrequested sections. Create separate calls with
   hidden, metadata-only, and full client tool visibility; verify no tool events,
   metadata-only events, or synthetic arguments/results respectively. Sample calls
   explicitly use full visibility through trusted setup, without an extra debug
   session grant. Test definition inheritance and an authorized creation override;
   editing the definition or sending a browser debug flag after preparation must
   not change the pinned value. Hidden tool events must not stop tool execution
   or conversational audio. Check unchanged agent variable grants and credential/
   header exclusions in every mode. Omit visibility at definition and creation
   and verify no tool events reach the client. Configure two agents with the
   same local tool key and different visibility overrides, then invoke each:
   only the originating participant/tool binding's override applies. Repeat
   with bindings to the same remote operation and check that an unlisted binding
   inherits the call-wide default. Exercise the documented `tool_visibility` /
   `tool_visibility_overrides` example: reception's `lookup_order` emits metadata,
   `create_booking` emits full detail, and unlisted bindings stay hidden. Trusted
   sample creation replaces the policy pair with full and no overrides; an
   omitted creation policy inherits the definition. No browser upgrade is allowed.
   A hidden binding in the effective pair must stay hidden even when
   the call-wide default is full. With client tool events hidden, verify complete
   observed synthetic metadata, arguments/request payloads, and responses/results/errors
   reach storage while no tool events reach the browser. Select metadata or full
   visibility and expect the same stored history without a tool-storage setting.
   Keep unknown outcomes unknown without inventing a remote response. Check
   credential/header exclusions before persistence, not just on export. In a
   database-backed call, also archive text-only input and an interrupted agent
   response: available text/turn/tool/variable/usage facts must be retained without
   category switches, typed provenance preserved, and generated text not mistaken
   for confirmed delivery. Missing speech/usage/prices stay unavailable; do not
   start STT or invent values. Compare disabled, denied, and permitted recording:
   only enabled, permitted recording stores audio, after the opening media-input
   gate permits delivery. Confirm ordinary archival adds no new SQL success gate.
   Verify the initial
   baseline is reachable through the call pointer without an invented turn, and
   hold a snapshot commit behind a test-owned barrier. Assert no update-tool
   success, newly published values/revisions, or success event before confirmation.
   Release commit and verify the snapshot and latest pointer exist before success.
   Make two updates in one turn and another later; each snapshot must contain
   the exact resulting state, unchanged sections, and original turn/tool identity,
   without a separate changeset. Retry a persisted operation, submit a stale one,
   and fail a transaction: no duplicate history, pointer regression, cross-call
   pointer, or partially committed snapshot/pointer pair is allowed. A transaction
   error returns variable-save failure, preserves prior in-memory values/revisions,
   and emits no success event, without requiring an extra commit-status lookup.
   Verify `RoomAuthority` and media can progress while the variable
   tool waits for storage. Fetch latest values directly through the call pointer.
   Separately omit retention settings at both levels and expect retain forever;
   set an application period and verify tenant inheritance, then override one
   tenant without affecting another. Duration selection must not enable additional
   capture or client disclosure. Use distinct record-created, started, ended, and
   archive-written timestamps: the finite expiry threshold must use `ended_at`
   plus the period, with no reset from a later write. Active calls must not expire;
   missing `ended_at` must not fall back to creation time, and forever must produce
   no expiry threshold. Change retention from 90 days to seven after a call ended
   14 days ago: expect eligibility under the new setting without rewriting call
   records. Increase the period or choose forever and verify eligibility changes
   for data still present, without restoring deleted data. An explicit tenant
   override must still win over an application change. Expire a call with retained
   transcripts, tool/usage history, variable snapshots, recordings, and exports:
   verify all call-owned rows and objects are deleted, including the call record
   and latest snapshot, while shared definitions/configuration and other calls
   remain untouched. Cross the threshold without running a sweep and expect no
   immediate per-call deletion. Run a controlled sweep: all managed external
   objects must be absent before deleting call-owned database data. Definitive
   key-not-found counts as absent; network/authentication/permission failures and
   unknown outcomes retain rows/references for a later sweep. Crash after partial
   or complete object removal but before database deletion, then repeat the sweep:
   missing-object deletes succeed and database cleanup completes only once all
   objects are absent. A database failure also leaves retryable work without a
   separate progress journal. Late publication must not recreate deleted data;
   verify coordination rather than assume ordering solves the race. Leave no
   permanent tombstone/summary/snapshot after success. Do not assert an unapproved
   sweep interval. Verify `call_retention: "forever"` and a duration value of
   `{"seconds":2592000}` (30 days): application omission defaults forever, tenant
   omission inherits, and explicit tenant forever overrides a finite application
   period without a per-call policy copy. These are planned checks, not current playground
   guarantees.
   Before writing an unfilled section, read it: expect one null in its value slot,
   not nested nulls, with no stored value or revision change. Write only one
   variable, read back that partial object,
   then add another variable in a later update. Repeat for the variable tool's first
   write and for a newly populated nested object. Verify a multi-variable object update
   needs one tool call and commits atomically; a variable update uses the same
   section grant and revision boundary. Update only `intake.topic` and confirm
   the existing `intake.summary` remains. Missing variables must not block an update;
   a variable of the wrong datatype or other invalid populated value must reject it
   atomically. A bad variable or invalid merged result must reject the whole update
   without changing values or revisions. Repeat with a partial nested address: changing
   its city must retain the postal code if one is already stored, and succeed
   without inventing one if it is not. Verify preservation across deeper objects
   and atomic rejection of invalid nested values. Also exercise a shallow `address` section without
   automatic flattening. Clear a nullable apartment using each update form and
   confirm its key remains present with null while other variables stay unchanged.
   Check nullable variables retain their keys, and non-nullable variables reject an
   explicit null even though absence is permitted. Include an invalid clear in
   a multi-variable update and verify no partial commit. An omitted variable must not be cleared;
   no separate delete tool or automatic null population is introduced.
   Verify direct-variable addressing with an `address` section and nested updates
   with a separate object-shaped fixture. A variable argument such as `address.city`
   or `/address/city` must not navigate into an object; if no exact direct variable
   is declared, it fails validation. Where a schema explicitly declares a
   punctuation-bearing literal key, only that key changes. Internal pointer
   encoding must preserve this behavior, with all grants/revision checks intact.
3. Submit a variable update, then interrupt the conversation before the variables
   process commits. Confirm it can finish under normal authorization/revision
   checks without resuming cancelled
   speech. Correct it with another tool call using the resulting revision.
   Also race two updates against the same revision: if the correction commits
   first, the delayed original must conflict and must not be blindly retried.
   Separately send A's update, transfer A to B, and confirm A's capabilities and
   model/tool workers terminate without restart. Let the queued update execute
   after A stops: it may still commit under the same grants, deadline, datatype,
   size, and revision checks. B reads or refreshes the saved values under its own
   permissions; the completion must not revive A or its audio. Verify direct
   reads/updates finish while the room authority is not servicing messages.
   Use test-owned acknowledgements/barriers and process monitors, not sleeps or
   liveness polling, to establish the sequence. Stopping the variables process
   itself is different: pending work has no completion guarantee. Committed
   values are not rolled back because their source agent stopped.
4. With a fake MCP, acknowledge request submission and delay its response using
   a test-owned barrier. Interrupt speech or send interrupting text while keeping
   the agent running; confirm the request is not cancelled. Release the response
   and confirm it remains associated with that invocation for subsequent reasoning,
   without reviving the cancelled model continuation, old speech, or unsent tools.
   Check no Call Variables change without a separate variable-update command.
   Repeat for a read-only tool; interruption is not cancellation intent in either
   case. Keep a separate timeout case to prove the existing deadline still
   applies. In that case, let the fake service commit a booking but withhold its
   response until the local deadline expires. Assert the reported outcome is
   `unknown`, with timeout as the cause, not confirmed failure, success, or rollback.
   Also check an already-known definitive result is not replaced with unknown
   and no variables are populated automatically. Observe the fake MCP through
   an explicit executor-completion acknowledgement and assert exactly one
   invocation: the executor must not resubmit the unknown-outcome request.
   Then explicitly request another tool call from the agent and verify it is
   a separate invocation, not a hidden retry or an exactly-once guarantee.
   Transfer/shutdown must still terminate the local agent workers, with
   no assertion that local termination undoes an external action. Use explicit
   acknowledgements and monitors, not sleeps or liveness polling.
   For the common background workflow, hold a submitted report request at a
   barrier and verify its running acknowledgement reaches model history. Supply
   another user turn and verify the agent responds and TTS receives text before
   releasing the tool result. Release it and verify a separate completion update
   reaches the latest history with the original invocation ID, not a second
   ordinary response to the acknowledged tool call. Check mixed text/tool output
   in buffered and streaming modes without lost or duplicated spoken text.
   Exercise result arrival during user and bot speech to check response ordering.
   Repeat the same contract for every supported model adapter; keep live-provider
   interoperability in the tagged integration lane. These are planned checks,
   not behavior available in the current playground.
   Return a known non-submission error or definite remote failure and verify the
   executor makes no automatic second attempt. Keep known errors definite, and
   distinguish a later model-requested invocation. No operation-classification
   fixture or automatic-retry exception is required for this baseline; those
   enhancements are deferred to their issue. Do not add a generic confirmation-token or changed-confirmation-arguments
   test: that mechanism is out of scope. Domain-specific conversational confirmation
   can be exercised with an agent prompt and fake tool; separately prove that
   prompt instructions cannot grant access to an unavailable tool. Do not require
   a late-confirmation webhook or reconciliation test for this slice: that scenario belongs to the
   deferred external-event mechanism, not the unknown-timeout no-retry contract.
5. Return a synthetic confirmation from a fake remote MCP booking tool that
   knows nothing about Vxpipe. Confirm the result alone changes no call variables.
   Let the agent call `update_variables` for its read+write `booking` section:
   the update commits under the normal identity, grant, datatype, size, and
   revision checks.
   An update to a read-only section must fail. Inspect permitted logs/events and
   archive projections for privacy; no automatic mapping or special trusted-result
   section is needed. Remote business validation remains the service's concern.
6. Return instructions that request an undeclared tool or destination. The
   engine must reject the operation regardless of the model's choice.
7. Hold destination preparation behind a test barrier. Verify the source retains
   conversational responsibility and is not terminated by a transfer request.
   Return busy/no-answer and verify the source receives a typed failure, can
   continue or choose another allowed action, and emits no `transfer.completed`.
   On successful ready/accepted handoff, verify commit then source-subtree
   termination using monitors. Applicable privacy boundaries must remain enforced.
   Machine detection follows R32 below; richer voicemail delivery is deferred.
   Exercise the single restoration attempt described below, not a restart loop.
8. Feed distinguishable fake audio into caller and consultation routes. Confirm
   each sink, monitor, and recorder hears only its authorized mix. Slow the upload
   and verify live audio continues while incomplete recording is reported.
9. Replay provider lifecycle events or same-call token claims and preserve one
   admitted call/runtime. Separate authorized API creation may create separate
   prepared records. After an admission crash, identify existing work for
   bookkeeping only; never repeat a crashed call or redial an uncertain leg.
10. Send typed input, interrupt generated output, end the call, and deliver late
    usage/artifact updates. Verify honest transcript provenance, no double-counted
    costs, and explicit missing data. Corrected-export revision and finalization
    assertions await R42/R43; usage settlement alone does not approve them.
11. Exercise the approved web route shapes with synthetic tenant keys, participant
    keys, and call IDs. Preparation stores a call in the selected tenant; joining
    requires that tenant's call and an authorized participant from its pinned
    definition. Wrong-tenant calls, invalid role assignments, and missing call
    correlation must fail. Publish a newer definition and confirm joining an
    existing call still uses its earlier participant mapping. Verify that no
    database primary key appears in the public URL or session identifiers.
12. After implementing the approved boundary, provision a synthetic API key and
    use it only on a test backend to prepare initial order variables. Confirm that
    preparation persists the pinned plan/variables but starts no room/live provider;
    only the scoped join token reaches the frontend. Joining activates that call
    without returning private preparation/variable data. Two read-only agents
    can read the order but cannot rewrite it. Reject bad keys, wrong-tenant or
    participant access, wrong datatypes/invalid populated values, and variables
    policy overrides; missing variables alone must not fail preparation.
    Exercise the same creation input through trusted telephony ingress: supplied
    known values initialize normally, unknown values remain unfilled, and no
    automatic customer lookup/resolver is required. Caller number alone must not
    populate verified customer identity; permitted tools can later fill variables.
13. Prepare calls with an authenticated backend, then exercise browser joining
    and backend joining with their issued tokens. Both use the same scoped
    admission checks; an API key on a media socket or first-message initial
    variables cannot bypass preparation. Initial values are validated during
    preparation, with empty variables and partial sections allowed. No direct
    initialization message or its proposed ten-second/64 KiB limits are required.
    Verify browser Origin rejection and HTTP CORS
    policies separately; lack of CORS grants must never bypass authentication.
    Preserve the browser WebRTC admission/signaling path. Keys/tokens stay out of
    URLs, ordinary management responses, room state, events, errors, and logs;
    only the delegated join token reaches the browser. Token lifetime, key
    bootstrap/scopes, and rotation/revocation now have approved checks below;
    exact issuance-retry and wire cases await their remaining review. These
    are future checks, not a claim of implemented authentication or storage.
14. Compile both entry refs as strings resolving to different catalog members.
    Reject missing refs, inline objects in entry fields, unknown refs, and a
    caller equal to the receiver. The caller-start route must match the declared
    caller; a different role cannot silently replace it. Confirm both refs remain
    pinned through a transfer and after publishing a newer definition.
15. Start the caller/reception/billing/support fixture with fake connections and
    providers, with `opening_audio` omitted. Only the initial caller and receiver
    are prepared; billing and human support start no provider or dial work just
    because they are listed.
    Delay readiness and confirm the agent does not interact prematurely. A later
    transfer prepares its destination without treating a dial request as an
    established connection. In a human-to-human entry fixture, no implicit AI
    receiver is created.
16. Admit one staff member as `human-support-agent`, then attempt a second
    person's admission through the same call/participant route. Reject the
    second without replacing or sharing the first participant's identity.
    Exercise permitted agent re-entry: its participant ID stays bound to the
    definition while it gets a fresh activation. Do not require caller reconnection.
    Race two admissions or transfer preparations and confirm at most one
    participant and one pending preparation exist for that definition. Admit
    `human-supervisor` independently and repeat the original definition in a
    different call to prove the limit is per key per call, not global. These
    are future runtime checks; exact retry/transport responses remain unspecified.
17. Issue a synthetic API key once and inspect its raw storage record: it contains
    only the one-way digest and metadata, with no plaintext or decryptable key.
    Restart the authentication boundary and verify the original key still works
    without a credential-decryption key. Wrong keys and attempts to submit the
    stored digest as the API key fail. Check tenant/permission enforcement and
    that ordinary management responses, events, and logs expose neither key nor
    digest. No retrieval operation can recover a lost key; authorized replacement
    issues a new one. Upstream credential retrieval remains outside this test.
    Start with no API keys and provision the first through trusted OTP/CLI
    administration. Verify tenant isolation and the `admin`/`calls` scope split
    without assuming admin implies calls or introducing definition allowlists.
    Issue separate keys for two integrations, overlap an old and replacement
    key, and revoke only the old one. Further authentication with that key fails,
    including fresh-token issuance; the other keys continue to work.
    A previously issued unused token remains claimable if its own scope, expiry,
    single-use, and lifecycle checks pass. Established connections continue.
    Do not require an issuing-key status lookup when validating the token.
    These are future project-owned boundary checks, not tests of a hash library.
18. With fake transports/providers, race two joins using the same token. Only
    one claims admission and starts the room. A failure before acceptance can
    retry the unused, unexpired token; a lost response after acceptance cannot
    reuse it. Neither case creates a second call or participant. Advance a fake
    clock: expiry rejects an unclaimed token but does not end an accepted call
    or expire/delete an unstarted record. The latter still starts no room or
    provider work as time passes.
    Without a requested lifetime, a new token expires five minutes after
    issuance. Request fifteen minutes from the authenticated backend and confirm
    admission remains possible after five minutes but fails at fifteen. Cover
    both preparation and existing-call issuance, and reject any browser attempt
    to extend the already-issued deadline. No unapproved maximum is assumed.
    Issue two distinct tokens for the same eligible unstarted call. Issuing the
    second must not invalidate the first; each keeps its own expiry and single-use
    status. Race their claims and prove shared call/participant admission creates
    only one caller/room startup. The other token grants no active takeover,
    caller reconnection, or ended-call reuse despite its independent lifetime.
19. Use a synthetic backend API key with the existing-call `join-tokens` route.
    For an eligible prepared record whose original token expired, issuance
    starts no room; joining with the fresh token starts it once with its pinned
    plan/variables and the same call ID. No new preparation is required solely
    because the old token expired or the record aged. Separately first-admit an
    eligible transfer destination into a running call and preserve its live room
    and updated variables. Reject using a fresh token to resume an already-admitted
    disconnected caller in this slice. After actual logical termination, a new
    authorized call has its own record and call ID, not a resumed old call.
    Do not infer termination from temporary transport loss or any participant
    disconnect; the precise end trigger still needs definition. Confirm token
    requests create no extra call record and accept no
    initial-variables or definition replacement. The route grants no browser CORS
    access; the separate browser join still uses the configured browser policy.
20. Attempt backend recovery with a wrong tenant/participant/key, ended call,
    revoked API key, or active connection; reject without takeover. Already-issued
    tokens do not inherit API-key revocation. Lose the join response
    while admission is still pending and confirm bookkeeping identifies that same
    existing work, never repeats a crashed call. If state changes after fresh-token issuance,
    joining rechecks eligibility and cannot admit a second connection. Exact
    status responses and transport-failure timing remain implementation/design
    details; R40's bounded recovery checks below apply. These are planned tests.
21. Use a fake clock to create a record at 10:00, then issue/expire/reissue tokens
    and leave startup pending: `created_at` stays 10:00 and `started_at` remains
    unset. Actually start the call at 10:15, delay persistence, and confirm its
    `started_at` is still 10:15 rather than the write time. End at 10:18 and
    report three minutes of live duration, not eighteen. Verify the configured
    call-duration limit also ignores preparation wait. Duplicate delivery,
    transfer and same-call recovery preserve the first start time;
    failure before live startup leaves it unset. These are future project-owned
    lifecycle/projection tests, not tests run for this documentation checkpoint.
22. Start one fake agent for each first-message mode. Before readiness, expect no
    startup output. After readiness, wait-for-input sends no unsolicited greeting;
    fixed mode submits its configured text and generated mode starts its normal
    permitted model output. Repeat readiness and reactivate the same participant
    and verify the startup greeting is not repeated, without requiring same-call
    caller reconnect support. Activate a different participant
    or start a new call and verify its independent first activation. All output
    still follows current privacy permissions. These are planned checks, not tests run here.
23. Start with `opening_audio` omitted and verify normal startup without an
    announcement delay. Configure a synthetic WAV/file source and hold playback
    completion behind a fake transport acknowledgement. Allow all room/participant
    capabilities to initialize and report ready while playback continues, but
    prove none receives user/participant audio through its normal media input.
    Transport packet receipt and provider readiness must not release the gate.
    Downloading/enqueueing audio is also insufficient. After completion, normal
    authorized audio delivery and the receiver's first-message policy apply.
    Failed/incomplete playback must not silently release media or conversation;
    exact transport completion/failure handling needs its own implementation
    contract. Do not treat opening the gate as permission to capture or replay
    the blocked interval; no new replay/buffering behavior is specified here.
    Keep `started_at` at actual live start, not playback completion.
24. Configure fixed text opening audio with an initial agent's resolved TTS
    profile. A fake renderer produces/cache-reuses the asset; other capabilities
    may warm up but participant media and ordinary conversation remain gated.
    Change text, provider/model/voice, and output settings and verify stale audio cannot be
    reused; distinguish tenant/configured bindings and keep secrets out of cache
    keys/logs. Rendering/caching is neither playback completion nor live call
    start. Do not invent a voice/agent for human-only entry. Exact cache storage,
    render timing, and unsupported-profile behavior remain unselected.
25. Use agent instructions with permitted variable-read and date/current-time
    tools. Confirm the existing section grants still constrain reads and missing
    values remain unfilled; personalization needs no template expansion/default
    layer. Obtain fresh date/time observations without changing call timestamps
    or introducing call-level locale/timezone fields. Tool identity/encoding and
    business-time interpretation follow their owning contracts; no new public
    schema or runtime tool is claimed by this documentation check.
26. Compile the protected routing excerpt and an equivalent literal-number
    fixture. Reject both number sources together, unknown section/variable refs,
    or any agent write grant to a referenced routing section. With no agent read
    grant, trusted resolution still uses the backend-initialized number. A
    read-only grant remains optional. Attempt arbitrary number/provider/URL/
    variable-ref transfer arguments and a destination outside the source's
    compiled list; none may reach a provider dial. Missing/null/invalid routing
    values yield the typed failure before dialing, keeping source responsibility
    and not inventing defaults. A permitted participant-ref transfer resolves its
    pinned source even after a definition revision changes. These are future
    checks, not an implemented resolver, general policy matrix, or timing guard.
27. Use a controlled `2026-07-28` remote endpoint that returns JSON and request-
    scoped SSE in separate cases. Verify matching revision metadata/lifecycle
    and clear rejection of incompatible versions without legacy fallback.
    Pin a tool input schema, then submit missing required values, invalid types,
    enum values, and nested data: no invalid request reaches the endpoint. Reject
    unsupported enabled schemas before model exposure, never weaken them or
    fetch external refs. Return structured content and a document descriptor:
    save the observed response without automatically downloading/playing content
    or relabeling remote success as failed inspection. Request an unimplemented
    sampling/elicitation capability: it must not have been advertised and must
    produce a clear missing-capability outcome without extra model authority or
    automatic continuation/resubmission. Detailed inspection and server-interaction
    tests await those deferred designs; these are planned checks, not runtime results.
28. Use synthetic trusted MCP endpoint configurations and controlled DNS/address
    resolution. Verify certificate validation (including a configured private CA),
    default non-public/metadata restrictions, and address-at-connect rebinding
    checks. Private destinations require host permission; tenant input cannot
    grant itself that permission. Redirect responses must cause no redirected
    request or credential forwarding. Custom network clients cannot bypass the
    boundary; no Go SDK protection is assumed for Vxpipe's transport.
29. Prepare a record and wait before joining: the readiness timer has not begun.
    Join with controlled required connections/providers, fail one definitively,
    and separately hold readiness beyond the configured 30-second deadline.
    Expect early failure or timeout cleanup respectively, with clear outcomes
    and no fabricated pre-live start. Play configured opening audio longer than
    that interval with ready providers: playback alone must not count as failed
    readiness or lose its input gate. These checks introduce no wait music.
30. Put an agent into genuine caller-input wait and verify the configurable
    15-second notification; instructions choose the next permitted action.
    Contrast output/opening playback, holding/dialing, and tool-wait, which do
    not trigger caller-silence logic. A long tool produces no automatic progress
    speech; ordinary background conversation retains one coordinated voice.
    Human-only portions do not require agent idle handling.
31. Resolve whole-call duration from definition, tenant, application, and absent
    settings: expect that precedence and a `1800000` ms platform default. Change
    settings after admission and keep the pinned limit. Delay joining, then
    transfer/recover into a human-only portion: only actual live time counts,
    the clock never restarts, and expiry ends with a clear duration-limit reason.
    Do not assert an unapproved warning, grace interval, or closing utterance.
32. Ask an agent to end under its instructions and use the existing permitted
    hangup tool. Verify no new speak-then-end/closing API, mandatory drain timer,
    or automatic pending-hangup cancellation on interruption is required. Keep
    delivered/spoken evidence honest rather than infer complete playback from a prompt.
33. Configure shared `transfer_policy`, source allowed refs, and destination
    requirements. Hold an agent destination's required readiness and ensure no
    commit. For a phone destination, connect media without press-1 acceptance,
    then provide DTMF on the correct pending leg. For web, submit authenticated
    acceptance from the destination connection after client-owned interaction.
    Source/caller/model, wrong-attempt, stale, and duplicate signals cannot
    authorize or repeat commit. Connection alone exposes no full conversation;
    target capability barriers and source responsibility still apply.
34. Hold preparation, dialing, and acceptance across one configurable 30-second
    total attempt interval; changing phase must not restart it. Return busy/no-answer
    early or expire the total deadline: stop the destination, return typed failure,
    and preserve source responsibility when permitted. A late answer/acceptance
    must not commit; clean only the mapped leg without auto-redial or a fabricated
    remote-outcome guarantee. Keep startup and whole-call clocks independent.
35. Feed configured provider AMD machine and unknown results through a controlled
    adapter. A machine result disconnects only the attempted destination leg,
    returning typed failure while a transfer's original caller/source remain under
    normal permissions. Separately verify termination of an initial outbound-only
    attempt without message speech. Unknown keeps waiting for explicit acceptance
    within the same total deadline; disabled/unavailable detection invents no
    classification. Preserve provenance/uncertainty, no LLM/STT/local substitute,
    and no inferred acceptance or voicemail delivery. These are planned checks,
    not runtime tests.
36. Fail a transfer and require source restoration. Allow exactly one bounded
    permitted-capability attempt; supervisor/application retries cannot reset it.
    Fail that attempt: end when no usable conversation remains, or preserve an
    already valid working human conversation. Save the detailed cause internally,
    then inspect speech, client events, and samples/full tool-debug output: only
    generic outcomes may appear, never provider/cause detail.
37. Brief an outbound human support recipient with minimum-necessary permitted
    caller/purpose information and optional notice before acceptance. The caller
    cannot hear it. Verify destination-bound phone/web acceptance and room commit
    before full media bridging, with source responsibility retained. Do not claim
    general concurrent-agent consultation. R38's approved commit policy applies.
38. Repeat an authorized API creation request: separate prepared records are
    permitted, with no creation idempotency header/cache. Separately race token
    claims and replay provider events for one call: those identities still exclude
    duplicate startup. Test short admission claims with existing work, actual runtime
    failure, and unknown dial outcomes: finish bookkeeping only for existing work,
    never repeat/redial/reconnect automatically, and clean up known resources.
39. Compile the documented `media_policy`/`while_present` shape with human and agent
    keys. Exercise omission, explicit empty maps, empty recipient arrays, explicit
    self-transcript routes, and two present restrictive policies: only intersected
    publishers/routes survive, storage false wins, and host authorization cannot
    be loosened. Leaving removes only that contribution; transport loss does not.
    Apply recording-only, recording-plus-transcript-storage, and no-transcript-route
    restrictions independently. Live permitted transcripts may continue without
    storage; no permitted live/storage consumer means those STT flows stop. Do not
    auto-enable recording or unconfigured STT. Verify individual tracks/full mix/
    derivatives and automatic transcript/log/export/model-debug copies honor the
    restricted source interval, without deleting prior permitted intake history.
    Keep existing whole-call retention and credential exclusions unchanged.
    During private preparation only the destination hears authorized briefing/
    notice; after bound acceptance, enforce restrictions before main-media commit.
    Failed enforcement exposes no bridge, and queued/late output or later replay
    cannot bypass the barrier. Variables and commit-confirmed snapshots are unchanged.
    These are planned checks, not new runtime behavior or a generic redaction test.
40. Feed distinct incremental deltas 100 and 60, cumulative totals 100 and 160,
    and cumulative 1000/1600/final1700 for separate attempt/components. Expect
    effective 160, 160, and 1700 respectively. Deliver a duplicate observation
    identity and ensure it is not added again; two distinct deltas of 50 must both
    count. Final evidence supersedes estimates, stale estimates cannot override it,
    and an explicit correction can lower as well as raise usage. Do not infer
    update mode from finality, use arrival-order/max rules, sum included subcategories,
    or coalesce distinct billable attempts. Failed/interrupted work keeps observed
    usage even after output is stale; unknown units/cost are not zero.
41. Retain call-wide usage, two separated STT/TTS service-active intervals for one
    participant, LLM turn work, and TTS with/without provider-supported turn evidence.
    Verify honest optional links without invented billed duration or allocation,
    and no triple charge from call/participant/turn views. Keep actual provider IDs
    namespaced by provider/integration/tenant; absent IDs are not local IDs in disguise.
    With a fake optional billing adapter, fetch available cost after room end without
    blocking media or resetting `ended_at`/retention. Unsupported billing or missing
    cost stays unavailable; later jobs cannot recreate purged data. Leave R46 pricing
    and R41–R43 archive/finalization choices unimplemented. These are planned checks.

### Review checkpoint verification

These entries are chronological evidence, not competing current contracts.
The later incremental-population decision supersedes earlier required-variable
completeness checks and closes the missing-read/first-write questions. Earlier
checkpoint test descriptions retain what was verified or planned at that time.
The later permission decision also removes write-only access and its special
projection/error handling; it is not a remaining implementation option.
Terminology in these historical entries is aligned with the final Call Variables
name. Earlier naming questions and the proposed platform-only result writers
are superseded by the naming and agent-mediated MCP decisions below.
The later R07 deferral also supersedes earlier same-call caller reconnect
promises and planned reconnect tests. Their historical text does not require a
current reconnect implementation; the canonical admission contract above applies.
The common client-admission decision supersedes the earlier separate direct
backend WebSocket flow and its setup-message checks. Their historical text does
not reinstate that endpoint or its proposed limits.
The subsequent opening-audio clarification supersedes the stop-all-capabilities
gate: startup/warmup is allowed while participant media is withheld until playback
completes. Earlier R06/R10 questions are resolved by independent unused tokens
and the existing initial-variables creation contract.
The R11/R12 and R14–R16 decisions supersede earlier personalization-binding,
platform timezone-hierarchy, and current-scope tool-retry/classification proposals.
Retries/idempotency enhancements now live in a deferred issue; call-creation
idempotency and admission recovery remain separate pending work.
R13's later protected-variable routing decision supersedes the remaining dynamic
destination proposal without introducing conversational template bindings.
The R20/R21 cleanup decision supersedes earlier unselected ordering/scheduling
proposals. Historical counts and checks do not override the periodic external-
first contract; the exact sweep interval remains deployment tuning to select.
R19's later encoding decision supersedes historical statements that serialized
retention values/units remain open; other storage configuration is still separate.
The later complete-tool-history decision supersedes historical metadata-default,
payload opt-in, and tool-storage enablement rules; client visibility levels remain.
R17's later visibility-key/map decision supersedes historical statements that
the exact visibility syntax is open. No new runtime behavior follows from it.
R18's later available-history decision supersedes historical optional transcript,
usage, or history storage selection. Audio still requires explicit permitted
recording; this is not permission to generate missing history or bypass denials.
R22/R23's later remote-profile and input-validation decisions supersede earlier
unselected protocol/schema proposals. R24/R25 move detailed result inspection and
server-driven interactions to deferred issues, not implicit implementation work.
The 2026-09-08 R26–R30 decisions supersede earlier unselected egress and startup/
silence/tool-progress/duration proposals. Wait music remains a deferred issue;
closing delivery and voicemail are not resolved by those timer defaults.
The later R31 decision places closing speech/hangup timing in agent instructions,
superseding the platform closing/drain workflow proposal. R33–R35 select transfer
configuration, acceptance, and total deadline; R32 settles detection source only,
not the action after machine/unknown classification.
The subsequent R32 decision supersedes that remaining action question: configured
machine detection disconnects the attempted destination leg; unknown retains the
existing explicit-acceptance deadline. Voicemail-message delivery is deferred.
The later R36–R40 decisions supersede repeated source-restoration, API creation
idempotency, and automatic crashed-call recovery proposals. R37's private briefing
is in initial scope. R38 supersedes capability denials as primary privacy control
and blanket transcript retention irrespective of policy; old denial examples and
checks are historical pending the replacement media/transcript schema.
The subsequent R38 approval supplies that replacement: `media_policy`, participant
`while_present`, complete route allowlists, room-wide storage booleans, and the
preparation/commit privacy barrier. Earlier under-redesign wording is historical,
not a remaining schema question.
The later R44/R45 approval supersedes the one-immutable-usage-row-per-operation
proposal and requires no forced turn allocation. Retain observations, derive
effective attempt/component amounts, and attribute honestly to call/participant/
service interval/turn.
Optional supported billing lookup does not choose R46 prices or R41–R43 archival
guarantees; earlier references to those accounting choices as pending are historical.

The original review passed `git diff --check`, syntax parsing of all 10 JSON
fences in this labnote, and existence/anchor checks for 13 local documentation
links across the two changed documents. The labnote terminology check also passed. JSON parsing is
syntax verification only, not validation against an implemented call-definition
schema. Only this labnote and its focused review document belong to the review
commit. No runtime suite was run for this documentation-only checkpoint. The
next implementation scope remains subject to user review; this checklist is not
authorization to add features.

For the approved G1 follow-up, reran these documentation checks and verified that
the JSON examples contain no `agents` root or separate participant `integrations`
block. The mixed built-in/MCP tool example and both read-only `billing` examples
match the approved layout. No runtime tests were run or features implemented.

For the approved G2 routing follow-up, all 10 JSON fences still parse, all 14
local links/anchors resolve, and both documents contain the same approved
tenant-scoped start/join routes. Unified tool examples and labnote terminology
checks still pass, as does `git diff --check`. Added future routing acceptance
steps; no runtime tests or endpoint/ID implementation were added. At that
checkpoint, G2 input, personalization, and lifecycle proposals remained open.

For the earlier 2026-09-07 initial-variables and credential follow-up (HMAC
authentication is superseded by the API-key decision below):

- Parsed all 10 JSON fences and resolved all 15 local links/anchors across the
  labnote and focused review document.
- Checked that both variables examples agree, the invocation supplies the declared
  required `customer.id` directly, and no JSON example retains `input_schema`,
  an `input` envelope, or an initialization mapping. Both agents keep read-only
  customer access, and billing keeps read-only intake access.
- Rechecked unified tool layout, approved route strings, labnote terminology,
  absence of local absolute paths, and `git diff --check`.
- Added future signed-admission, read-only-variables, ciphertext-storage, and
  secret-redaction acceptance steps. These were not run: no runtime behavior or
  authentication implementation changed. At that checkpoint, precise
  signing/replay, credential lifecycle, and partial/default variables semantics
  remained pending; later decisions remove the signing questions and reject
  variable defaults rather than defining assembly rules.
- Kept `20260906.02` as the existing unreleased illustration; no schema release
  or implementation was published. At that checkpoint, the next discussion was
  G2 participant startup/cardinality, not authorization to implement it.

For the approved 2026-09-07 entry-role and startup follow-up:

- Updated this original labnote's contract, both JSON definition examples,
  resolved-plan discussion, validation requirements, routing, alternatives,
  implementation checkpoints, and review status. The focused review document
  is synchronized with these decisions, not a replacement for this labnote.
- Parsed all 10 JSON fences and resolved all 16 local links/anchors. Both
  definition examples have distinct string entry refs naming existing catalog
  participants, and the smaller variables example now includes its human caller.
- Checked transfer refs, direct initial variables, read-only grants, unified tools,
  unchanged route shapes, terminology, and absence of local absolute paths.
  `entrypoint` remains only in historical/rejected-shape explanations; no JSON
  example or proposed struct list retains the old entry field/type.
- Added future acceptance steps 14–15 for entry validation, startup/readiness,
  human-only entry, and pinned initial roles across transfer. No runtime test
  suite was run, and no schema release or runtime functionality was implemented.
  `git diff --check` passed.
- At that checkpoint, participant-instance cardinality and duplicate/reconnect
  admission were next; the entry rename alone had not approved a count limit.

For the approved 2026-09-07 one-participant follow-up:

- Recorded one participant per definition key per call in this original labnote
  and synchronized the G2 review status. Authorized reconnect/re-entry retains
  identity; another person cannot share or take over an occupied definition key.
  The contract adds no JSON option or multi-instance selection mechanism.
- Added future acceptance step 16 for duplicate-person admission, reconnect,
  agent activation, concurrent preparation, and isolation across definitions
  and calls. Exact reconnect deadlines and retry responses remain pending.
- Parsed all 10 JSON fences, resolved all 17 local links/anchors, and checked
  entry refs, existing variable grants/tool layout, terminology, local-path
  hygiene, and `git diff --check`. No runtime tests or behavior changed.
- At that checkpoint, the next review was G2 initial-variables sourcing for an
  inbound phone call, which cannot by itself supply the example's required
  customer/order identifier.

For the approved 2026-09-07 API-key admission simplification:

- Updated this original labnote and synchronized the focused review. Backend
  integrations now use one long-lived API key, not a separate client ID and
  signed payload. The previous HMAC contract and signing questions are marked
  superseded, including the old acceptance steps; historical evidence remains
  explicitly historical.
- Recorded backend preparation/browser token joining and direct authenticated
  backend WSS initialization. Preparation stores the pinned call/variables without
  creating its live room; Calls owns preparation and later activation through
  persistence ports. Existing browser WebRTC remains supported.
- Checked the WebSocket GET handshake, browser header constraints, and Origin
  validation against the protocol/browser specifications linked above. HTTP
  CORS grants and WebSocket Origin checks are distinct from authentication.
  Wire details, token lifecycle, and retry/recovery rules remain pending.
- Replaced future acceptance steps 12–13 with API-key, prepared-variables privacy,
  deferred startup, direct initialization, browser-origin, and redaction checks.
  No new endpoints, credentials, dependencies, storage, or runtime tests were
  implemented or exercised.
- Parsed all 10 JSON fences, checked both complete definition examples for
  distinct valid entry refs, transfer refs, matching variable schemas, direct
  invocation variables, and unified tools. Resolved all 17 local links/anchors;
  checked route agreement, terminology, local-path hygiene, and whitespace.
  `git diff --check` passed. The candidate schema remains `20260906.02`.
- At that checkpoint, API-key storage was next: encryption had not yet been
  replaced, and hash verification required approval. The following storage
  decision resolved that choice; token lifecycle was still open at that stage.

For the approved 2026-09-07 one-way API-key storage follow-up:

- Approved hash-only storage for gateway-issued keys in this original labnote
  and synchronized the focused review. Verification hashes the presented key;
  no recoverable key copy or API-key decryption key is required. Keys are shown
  once and replaced if lost. The earlier reversible-storage choice is superseded
  for these keys, not for upstream secrets Vxpipe must retrieve and send.
- Updated G2's status, rejected alternatives, and future acceptance step 17.
  At that checkpoint, credential management and token lifetime/claim/reissue
  remained pending; no precise key encoding/hash profile, migration, or runtime
  implementation was introduced by that documentation decision.
- Verified all 10 JSON examples are unchanged and parse, both complete examples
  retain consistent entry/variables/tool contracts, and all 17 local links/anchors
  resolve. Route, terminology, local-path hygiene, and `git diff --check` checks
  passed. No runtime tests were run for this documentation-only checkpoint.
- At that checkpoint, G2 token claim/reuse and recovery were next, including
  losing a connection after redemption. The following approval resolves those
  high-level rules without choosing every expiry or reconciliation detail.

For the approved 2026-09-07 join-token recovery follow-up:

- Updated this original labnote and synchronized G2's focused review. Both
  initial and replacement tokens are single-use, consumed atomically when
  admission is accepted rather than when the browser receives confirmation.
  Unused/unexpired tokens can retry before acceptance; afterwards recovery is
  backend-authorized and uses a fresh token for the same call/participant.
- Added the approved tenant/call/participant-scoped `join-tokens` route. It uses
  backend API-key authentication with no CORS grants and operates on an existing
  call record, even before its room exists. Issuance starts no room, changes no
  pinned definition/variables, and cannot bypass eligibility or take over an
  active connection. Pending admission must be reconciled first.
- Added future acceptance steps 18–20 for races, lost responses, fresh-token
  recovery, preserved live state, authorization, and expiry versus call duration.
  No endpoint, credential, storage migration, or runtime test was implemented.
- Verified all 10 JSON examples are unchanged and parse; both complete examples
  retain their entry/variables/tool contracts. All 18 local links/anchors resolve,
  and both documents agree on the three approved HTTP route shapes. Admission
  terminology, local-path hygiene, and `git diff --check` checks passed.
- At that checkpoint, single-use admission and the recovery endpoint were
  resolved; unused-call expiry was next. The following clarification rejects
  the additional admission deadline without choosing a data-retention policy.

For the approved 2026-09-07 token-only expiry clarification:

- Clarified that a prepared call is only its persisted record, pinned definition,
  and initial variables until joining starts the call process tree. There is no
  separate automatic admission expiry for this unstarted record.
- Expired tokens cannot join, but do not permanently disable or delete the call
  record. Authorized fresh-token issuance can reuse the same eligible record,
  definition, and variables. Established calls are not ended by token expiry.
- Removed unused-call expiry from the pending admission decisions and recorded
  it as a rejected alternative. Retention/cleanup remains separate housekeeping;
  no token TTL value, cleanup policy, or runtime behavior was added.
- Updated future acceptance steps 18–19 for token expiry without record expiry
  and fresh-token admission to that same record. No runtime tests were run.
- Verified all 10 JSON examples are unchanged and parse, both complete definition
  contracts remain consistent, and all 18 local links/anchors resolve. The three
  route shapes, terminology, local-path hygiene, and `git diff --check` pass.

For the approved 2026-09-07 actual call-start timing clarification:

- Separated `created_at` from `started_at` in the original labnote and focused
  review. A stored, unstarted call has no start timestamp; token operations and
  pending/failed-before-start admission do not create one.
- Actual live startup supplies the timestamp persisted by Calls, not database
  insertion or delayed event receipt. Reconnect, transfer, and recovery preserve
  the first start time; live duration and its configured limit exclude the
  preparation interval.
- Added future acceptance step 21 with distinct creation, live-start, and end
  times, delayed persistence, duplicate/recovery handling, and pre-start failure.
  No implementation, database schema, dependency, or runtime test was changed.
- Verified all 10 JSON examples are unchanged and parse, both complete definition
  contracts remain consistent, and all 19 local links/anchors resolve. Route and
  timing-example consistency, terminology, local-path hygiene, and
  `git diff --check` pass.

For the approved 2026-09-07 supplied-only variables clarification:

- Removed variable defaults from both definition examples and the compiler,
  initialization, and review contracts. Variables declarations define schemas
  and permissions only; initial values come exclusively from authorized
  call-setup data. There is no default construction or merge precedence.
- Retained required setup validation and later permission-checked updates.
  Omitted optional variables stay unfilled; an explicitly supplied empty object
  must satisfy its schema. The invocation prefills only `customer.id`, not
  `intake`. Capability/provider configuration defaults are unchanged.
- Updated planned acceptance checks and marked G3 initialization resolved in
  both documents. Remaining authority questions and the precise read/first-write
  contract for unfilled sections still need review; no runtime work was added.
- Verified all 10 JSON examples parse and compared them with the prior commit:
  their only changes are removal of the two `intake.default` properties. Entry,
  variable permissions, transfer refs, tools, and capability defaults otherwise
  remain unchanged. All 19 local links/anchors resolve; route consistency,
  terminology, local-path hygiene, and `git diff --check` pass. No runtime tests
  were run for this documentation-only correction.

For the approved 2026-09-07 variable-update interruption simplification:

- Updated the original variable contract and synchronized G3 in the focused
  review: an already-submitted local variable update can finish despite
  conversational interruption, and a correction is another tool call. The
  proposed live-turn/tool-cancellation guard and mutation-ID journal are not
  required for this rule. Committed values are not rolled back.
- Preserved the existing bounded authorization transaction, including agent
  activation, permissions, schema, and section revision checks. Transfer,
  deactivation, and room end remain distinct lifecycle boundaries. A conflicting
  delayed update cannot overwrite a newer revision or be blindly replayed.
- Replaced planned acceptance step 3 and the corresponding review scenario
  with interruption-then-correction, both update orderings, unchanged lifecycle
  checks, and no revival of cancelled speech. Kept external tool outcomes in
  G4 rather than making this a blanket tool-cancellation policy. Mixed-read
  authorization, unfilled-section access, and trusted-result rules still need
  review; no runtime code or new call-definition fields were introduced.
- Verified all 10 JSON examples are unchanged and parse, both complete definition
  contracts remain consistent, and the existing authorization transaction is
  unchanged. All 20 local links/anchors resolve. Route consistency, removal of
  superseded cancellation assertions, terminology, local-path hygiene, and
  `git diff --check` pass. Runtime tests were not run for this docs-only change.

For the approved 2026-09-07 variable-read authorization follow-up:

- Made the original read contract and authorization transaction explicit: a
  forbidden requested section causes a permission error for the whole read,
  with no variable values. This supersedes silent filtering. Agents are informed
  of their permitted sections and can correct the request; a successful retry
  returns only the requested, permitted data. Existing section grants remain
  the permission boundary, not a newly introduced variable-level policy.
- Recorded both requested update forms: one object-level tool call can update
  several variables, and a variable-level convenience handles a single change. The
  existing mutation-list example already batches changes and remains an internal
  command candidate. Both forms share atomic section validation and revision
  checks. At that checkpoint, final naming, merge/replacement, and nested/removal
  behavior were pending; no runtime implementation or schema-key rename was made.
- Updated G3's status and future acceptance steps in both documents. Verification
  scenarios cover a mixed-permission read failing without values, a corrected
  permitted read, no unrequested data, and the two update forms once their exact
  semantics are approved. Other G3 and external-operation questions remain open.
- Verified all 10 JSON examples are unchanged and parse, both complete definition
  contracts remain consistent, and the seven write-authorization checks are
  unchanged. All 20 local links/anchors resolve; update-form, route, terminology,
  local-path, superseded-read-wording, and `git diff --check` checks pass. No
  runtime or browser tests were run for this documentation-only checkpoint.

For the approved 2026-09-07 object-update merge decision:

- Resolved object merge versus replacement in the original tool contract and
  G3 review: supplied variables update the existing section, omitted section variables
  remain, and one tool call commits a schema-valid merged result atomically.
  Required values already present need not be resent. Invalid data or a revision
  conflict leaves values and revisions unchanged; initialization still has no
  defaults. At that checkpoint, nested-object, removal/null, and final naming
  details remained open; the recursive-merge clarification below resolves nesting.
- Added a before/data/after illustration and future acceptance checks for
  preservation of omitted variables, retained required variables, multi-variable atomic
  validation, and unchanged permission/revision boundaries. The existing internal
  mutation example is not a third model-facing tool or a replacement shortcut.
- Counted the original 13 numbered review groups: G1 is resolved, G2/G3 are
  partly resolved, and G4–G13 await approval, leaving 12 open groups. This is not
  a count of individual edge cases. At that checkpoint, nested-object merge
  behavior was next to discuss, not yet an approved feature.
- Verified all 11 JSON examples parse: the previous 10 are unchanged, and the
  new illustration preserves `summary` while updating `topic`. Both complete
  definition contracts and the seven write-authorization checks are unchanged.
  All 20 local links/anchors resolve; the group count, route consistency,
  terminology, local-path hygiene, and `git diff --check` pass. No runtime
  implementation, runtime tests, or browser checks were part of this checkpoint.

For the approved 2026-09-07 recursive-merge and shallow-variables clarification:

- Confirmed that `update_variables` performs a deep merge, not merely a deep copy:
  when old and supplied values are objects, merge recursively and retain omitted
  variables at every object depth. The nested address example retains `postal_code`
  when only `city` changes. Existing schema, permission, revision, and atomic
  validation boundaries remain in place.
- Added authoring guidance to favor simple, shallow sections, such as making
  `address` its own section. This does not forbid nesting, flatten data at runtime,
  add variable-level permissions, or introduce a new depth limit. Neither full
  definition example was changed. At that checkpoint, removal/null and
  variable-addressing details, final naming, and other review questions remained open.
- Updated both documents and future verification scenarios for omitted nested
  siblings/required variables, deeper objects, nested validation failures, and
  shallow authoring. G3's nested-merge question is resolved; the count remains
  12 open numbered groups because other G3 decisions still need review.
- Verified all 12 JSON examples parse: the prior 11 are unchanged and the new
  nested illustration produces the expected recursive merge. Both complete
  definition contracts and the seven write-authorization checks are unchanged.
  All 20 local links/anchors resolve; review counts, route consistency,
  terminology, local-path hygiene, and `git diff --check` pass. No runtime
  implementation or runtime/browser tests were part of this documentation update.

For the approved 2026-09-07 explicit-null clearing decision:

- Resolved clearing in both update forms: explicitly supplied null is stored
  as the variable value while retaining its key; omission preserves the old value.
  Deep merge does not skip null or interpret it as deletion. No separate tool
  is needed to clear a value, and physical key removal is deferred along with
  the earlier internal `remove` operation.
- Recorded explicit nullable-variable support in the schema requirements. Optional
  does not imply nullable, required nullable variables retain their keys, and a
  non-nullable variable rejects null under the same atomic schema/permission/revision
  checks as other writes. Section roots remain objects; missing variables are not
  automatically populated with null. No schema version or runtime API changed.
- Added a clearing illustration and planned acceptance cases for both tools,
  retained keys and other variables, non-nullable rejection, required/optional
  distinctions, and atomic failure of a multi-variable update. G3's clearing
  question is resolved; its other questions keep the count at 12 open groups.
- Verified all 13 JSON examples parse: the prior 12 are unchanged and the new
  clearing example retains `apartment` with null and preserves `city`. Both
  complete definition contracts and the seven write-authorization checks are
  unchanged. All 20 local links/anchors resolve; review counts, route consistency,
  terminology, local-path hygiene, and `git diff --check` pass. No runtime
  implementation or runtime/browser tests were part of this documentation update.

For the approved 2026-09-07 section/variable addressing decision:

- Defined the data hierarchy in the original labnote and focused review: variables
  root keys are section names, direct section keys are variable names, and deeper
  objects are data within those variables. The definition's schema wrapper and
  revision metadata are unchanged.
- Made the variable tool a literal direct-key operation with no dot, pointer, or
  array-index interpretation. Unknown direct names fail validation; explicitly
  declared punctuation-bearing keys remain literal. Partial nested updates use
  the object tool and its existing deep merge. Any internal pointer encoding
  must preserve these semantics without adding an agent-facing path language.
- Updated planned acceptance cases for direct variables, nested objects, unknown
  names, and literal punctuation under the same section grants and revisions.
  G3's addressing question is resolved; final naming and other review questions
  remain open, leaving the count at 12 numbered groups. No runtime tool, schema
  version, dependency, or permission model was changed.
- Verified all 13 JSON examples are unchanged and parse, both complete definition
  contracts and the seven write-authorization checks are unchanged, and all 20
  local links/anchors resolve. Addressing examples, removal of superseded open
  questions, review counts, route consistency, terminology, local-path hygiene,
  and `git diff --check` pass. Runtime/browser tests were not run for this
  documentation-only checkpoint.

For the approved 2026-09-07 missing-read and incremental-population decision:

- Updated this original labnote and the focused review: a missing authorized
  section read returns null at the requested value level, without nested
  placeholders, a stored default, or a revision change. Reads of partial objects
  do not manufacture omitted variables. Unknown sections and forbidden reads keep
  their existing error rules.
- The first write populates a declared section; subsequent updates collect data
  iteratively. The initial request was clarified to retain datatype validation
  while deferring required-variable completeness, not to remove schema validation.
  Setup, nested updates, generated variable-tool arguments, and authority checks
  now consistently allow missing variables while checking populated values.
- Removed variables `required` lists from the two illustrative definitions.
  Datatypes, value constraints, nullability, section grants, literal variable
  addressing, deep merge, revision checks, and lifecycle fencing are retained.
  An absent section's null read result is not a stored null or a datatype error.
- Updated future test steps for missing reads without mutation, first writes,
  multiple collection rounds, nested partial objects, and atomic rejection of
  wrong datatypes. No final-completeness gate, validation toggle, new read tool,
  schema release, or runtime implementation was added. Other G3 questions remain
  open; the count stays at 12 numbered review groups.
- Verified all 13 JSON examples parse; their only edits remove the two variables
  `required` lists. Both definition examples retain their datatypes, value
  constraints, entry refs, permissions, tools, and transfers; merge/null examples
  are unchanged. All 20 local links/anchors resolve, unrelated write checks and
  admission routes are preserved, and review-count/terminology/path hygiene and
  `git diff --check` pass. No runtime or browser tests were run for this
  documentation-only checkpoint.

For the approved 2026-09-07 read-only/read+write permission decision:

- Limited agent section grants to read-only or read+write; omission grants no
  access. Standalone write grants are invalid, not normalized into broader
  permissions. Existing definition examples already use the supported grants.
- Updated value/revision projections, update results, definition checks, and
  future acceptance steps. Every writer can read its section; ungranted sections
  expose neither values nor revision metadata in model projections. Removed
  revision-only writable views and the write-only error review question.
- Retained section-level authorization, datatype checks without required-variable
  completeness, incremental population, deep merge, revisions, and lifecycle
  fencing. Public events and other participants gain no new variables access.
- Updated the original labnote and focused review only. Other G3 questions keep
  the count at 12 open numbered groups; no runtime implementation or schema
  release was introduced.
- Verification: all 13 JSON examples are unchanged and parse; both definition
  examples use only supported section grants. The seven write-authorization
  checks are unchanged, all 20 local links/anchors resolve, and the old
  write-only execution/error paths are absent from the active design. Route,
  review-count, terminology, path-hygiene, and `git diff --check` checks pass.
  No runtime or browser tests were run for this documentation-only checkpoint.

For the approved 2026-09-07 Call Variables naming and MCP-result decisions:

- Adopted Call Variables for the collection, section for `booking`, and variable
  for `status`. Updated candidate JSON keys to `call_variables`,
  `initial_variables`, and `variable_permissions`; tools are `read_variables`,
  `update_variables`, and `update_variable`, with `variable_name` for the direct
  name argument. Updated the planned state/command/event names, persistence
  sketches, examples, and heading links consistently.
- Added the distinction from conversation history and model context to the
  original design and runtime architecture. Execution metadata such as
  `Tool.Context` and unrelated definition fields retain their actual meanings.
  Sections, datatypes, grants, revisions, merges, null handling, and incremental
  population are unchanged; the illustrative dated candidate is still unreleased.
- Resolved the MCP result-writer question: remote MCP tools return results to
  the agent, which then invokes Vxpipe variable tools to save relevant values.
  No remote knowledge of Vxpipe, automatic mapping, or platform-only result
  section is required. Updated planned acceptance steps to prove the result
  alone causes no mutation and the subsequent agent write obeys existing checks.
- Removed the naming and result-writer questions from pending review. Only
  schema-complexity bounds remain in G3; G2 and G4–G13 keep the overall count at
  12 numbered groups. This checkpoint changes documentation only, not runtime
  APIs, dependency versions, or a published schema.
- Verification: all 15 fenced JSON examples across the three documents parse
  (13 in this labnote, two in architecture). Compared with the prior commit,
  their only changes are the three approved key renames. Both definition
  contracts and all seven authority checks retain their semantics; all 31 local
  links/anchors resolve and external source URLs are unchanged. Identifier,
  section/variable terminology, resolved-review, route, privacy, and whitespace
  checks pass. No runtime or browser tests were run for this docs-only checkpoint.

### Dedicated variable owner — approved 2026-09-07

- Replaced the earlier room-authority-owned variable state with one room-scoped
  `CallVariables` GenServer. Tools and per-turn projections call it directly;
  it owns values, revisions, compiled schemas, and pinned per-agent grants.
  `RoomAuthority` remains responsible for the pinned plan and room/participant
  lifecycle, not variable authorization or commits.
- Removed current-activation/admission-liveness checks from variable operations.
  Trusted room/agent identity, section permissions, deadlines, datatypes,
  supplied-value/size bounds, and optimistic revisions remain. Agent identity
  and permissions cannot come from model arguments; activation IDs may still
  identify the origin in events without becoming an access gate.
- Approved source-agent subtree termination on transfer, including capabilities
  and model/tool workers, without restarting the departed execution. The
  separate variables process survives; requests already sent by A can finish
  after A shuts down. This deliberately supersedes earlier checkpoint claims
  that transfer/deactivation fences submitted variable writes. B can refresh
  its permitted values, and revisions still prevent lost updates. No rollback,
  transfer-time flush, or revival of A's model/speech is implied.
- Rejected additional schema-depth or variable-count limits for now. The earlier
  performance concern was unmeasured. Keep datatype and value-size checks while
  allowing iterative population without required-variable completeness.
- Rechecked the current room supervision and model/tool task path: tasks use a
  shared task supervisor with `async_nolink`; `terminate/2` attempts cleanup.
  The agent-wide shutdown guarantee therefore still needs implementation, not
  an assumption that stopping a participant automatically stops all its workers.
- Synchronized the ownership diagram/table, persistence event path, tool and
  transfer contracts, future red-green tests, and manual acceptance steps with
  the architecture and focused review. G3 is resolved in documentation, leaving
  11 open numbered groups: G2 and G4–G13. Earlier review counts above describe
  their historical checkpoints. Remote side-effect recovery remains unapproved.
- Verification: all 15 fenced JSON examples parse and are unchanged from the
  previous commit, including both complete definition fixtures. All 31 local
  links/anchors resolve; API routes and external source URLs are unchanged.
  Direct ownership/routing, removal of the activation gate, review status,
  restricted terminology, local-path hygiene, and `git diff --check` pass.
  Reviewed the complete documentation diff. No runtime implementation,
  dependencies, or schema release changed; no runtime/browser tests were run
  for this documentation-only checkpoint.

### Submitted MCP calls survive speech interruption — approved 2026-09-07

- Approved the distinction between interrupting speech and intending to cancel
  a tool: ordinary spoken or typed interruption leaves an already-submitted MCP
  request running until its result or existing timeout while the agent remains
  running. This applies to reads as well as actions, without inferring intent
  from interruption or tool classification.
- Keep the result associated with its invocation for subsequent agent reasoning,
  without reviving the cancelled model continuation or old speech. Do not run
  additional unsent old-turn tools or automatically map results into Call Variables;
  the agent still makes a separate authorized variable-update call when appropriate.
- Retained agent-subtree termination on transfer and room shutdown. Stopping
  local workers does not guarantee remote cancellation or rollback. Explicit
  cancellation, timeout/unknown outcomes, retries/idempotency, confirmation, and
  post-shutdown recovery remain unapproved G4 questions; this decision does not
  introduce an operation ledger or durable-worker mechanism.
- Rechecked `ModelInference`: tools execute in its request task, and interruption
  invokes `cancel_current/1`, which kills that task. Separating submitted MCP
  invocation lifetime from conversational output therefore needs implementation;
  its agent ownership and existing timeout must remain intact.
- Replaced the contradictory planned MCP test that cancelled remote requests on
  interruption. Added deterministic delayed-result/read/action and timeout cases,
  with no stale output, automatic variable mutation, or unsent-tool execution.
  The original labnote, architecture, and focused review now agree. G4 is partly
  resolved; the count remains 11 open groups, G2/G4 and G5–G13.
- Verification: all 15 JSON examples and both complete definition fixtures are
  unchanged and parse; all 31 local links/anchors resolve. API routes and external
  references are unchanged. G3's authorization transaction and the architecture's
  implemented-runtime descriptions are unchanged. Interruption policy, remaining
  review boundaries, restricted terminology, local-path hygiene, and
  `git diff --check` pass. Reviewed the complete documentation diff. Documentation
  only; no runtime or browser tests were run.

### Unknown MCP timeout outcomes — approved 2026-09-07

- Approved reporting outcome `unknown` when a submitted MCP request times out
  without a definitive remote result. Timeout describes the local wait, not
  proof of remote failure or rollback; preserve a definitive outcome if already
  known. The existing timeout and explicit variable-update rules remain intact.
- Kept retry/no-retry policy, idempotency, reconciliation, later receipts, explicit
  cancellation, and operation storage unapproved. This is outcome reporting, not
  approval of a new wire schema, durable worker, or retry mechanism.
- Updated the original contract, architecture, G4 status, and planned acceptance
  case: a fake booking commits remotely, its response is withheld, and local
  timeout reports unknown without asserting success/failure or changing variables.
  G4 remains partly resolved and the count remains 11 open numbered groups.
- Verification: all 15 JSON examples and both definition fixtures are unchanged
  and parse; all 31 local links/anchors resolve. Routes, external references,
  G3's authorization transaction, and implemented-runtime descriptions are
  unchanged. Interruption/timeout reporting, retry-review boundaries, restricted
  terminology, local-path hygiene, and `git diff --check` pass. Reviewed the
  complete documentation diff. No runtime or browser tests were run.

### No automatic retry after an unknown timeout — approved 2026-09-07

- Approved the executor default: return the unknown outcome for a submitted MCP
  request whose timeout leaves its remote result unconfirmed; do not silently
  retry that request. It may already have completed its external action.
- A later agent-requested tool call is a separate invocation, not an executor
  retry. This provides no exactly-once guarantee and does not prevent a separate
  invocation from duplicating an external action. No automatic-retry exception
  based on tool metadata or classification is approved now.
- Updated the original contract, architecture, review status, and acceptance
  steps to observe one executor invocation through its completion acknowledgement,
  then distinguish a separately requested call. Other retry/failure policies,
  reconciliation, later receipts, and explicit cancellation remain open. G4 is
  still partly resolved; the count remains 11 open numbered groups.
- Verification: all 15 JSON examples and both definition fixtures are unchanged
  and parse; all 31 local links/anchors resolve. Routes, external references,
  G3's authorization transaction, and implemented-runtime descriptions are
  unchanged. Reviewed the complete diff, including the distinction between
  executor retries and new agent invocations. Retry scope, remaining-review
  status, restricted terminology, local-path hygiene, and `git diff --check`
  pass. Documentation only; no runtime or browser tests were run.

### Late confirmations are deferred external events — approved 2026-09-07

- Classified late booking confirmations as an external concern. A future
  general event mechanism could receive a gateway webhook and route the
  information to the relevant call room/agent if the room is still active.
  Handling that scenario is not important for the current MCP slice.
- Deferred event ingress/delivery, polling, late-result reconciliation, and
  operation storage solely for that scenario. No new endpoint, event payload,
  background worker, or automatic continuation of the old tool call is approved.
  Authentication, correlation, inactive-room behavior, and agent handling belong
  to the future design, not extra decisions required for this slice.
- Removed late-result processing from current acceptance requirements and
  updated the original contract, architecture, and focused review. Kept ordinary
  interruption, timeout-as-unknown, no automatic executor retry, and variable
  ownership/permissions unchanged. Other G4 questions keep it partly resolved;
  the overall count remains 11 open numbered groups.
- Verification: all 15 JSON examples and both definition fixtures are unchanged
  and parse; all 31 local links/anchors resolve. API routes, external references,
  G3's authorization transaction, and implemented-runtime descriptions are
  unchanged. Reviewed the complete diff for deferred scope and preservation of
  the approved MCP policies. Remaining-review status, restricted terminology,
  local-path hygiene, and `git diff --check` pass. Documentation only; no runtime
  or browser tests were run.

### Provider-independent background tools — approved 2026-09-07

- Selected application-level acknowledgement and later conversation updates for
  all model providers. Native async-tool support does not select an alternative
  lifecycle. Kept execution agent-owned and separate from individual model and
  speech turns; explicit cancellation policy remains open.
- Source inspection of installed `req_llm` 1.22.0 confirmed host-owned execution,
  tool-result context helpers, and responses carrying text alongside tool calls.
  Offline checks accepted a normal running acknowledgement and retained mixed
  text/tool output. They also confirmed native delayed-result support exists,
  but that provider-specific path is not the selected design.
- The first offline probe through Mix was blocked by development runtime
  configuration requiring a speech-provider key. Re-running directly against
  compiled modules avoided application startup and credentials; all five
  synthetic checks passed. No provider or MCP requests were made.
- Updated the original contract, architecture, G4 summary, and planned test flow.
  Runtime implementation, per-provider interoperability, and explicit cancellation
  policy remain pending; 11 numbered review groups remain open.
- Documentation verification: all existing fenced examples are unchanged and all
  15 JSON examples parse. Link references and external URLs are unchanged. Only
  the three intended documentation files changed; restricted terminology,
  local-path hygiene, review-status preservation, and whitespace checks pass.
  No runtime implementation or live-provider/browser verification was performed.

### Generic tool confirmation is out of scope — approved 2026-09-07

- Excluded a generic platform-level confirmation mechanism for now. Agent
  instructions may ask for conversational confirmation before a tool call; any
  enforceable business authorization belongs to the integrating application/MCP.
  Prompt instructions are not a security guarantee.
- Retained Vxpipe's tool-access, trusted-identity, and argument checks. The earlier
  proposal for platform confirmation tied to arguments, participant, variable
  revision, and expiry is not required: no confirmation token, approval endpoint,
  call-definition option, or generic confirmation state is introduced.
- Updated the original contract, architecture, review status, and acceptance
  scope. Replace the generic changed-confirmation-arguments test with the
  domain-specific prompt/tool flow and proof that prompts cannot grant access
  to an unavailable tool. Explicit cancellation and other tool/retry policies
  remain under review; G4 is partly resolved and 11 groups remain open.
- Verification: all 15 JSON examples and both definition fixtures are unchanged
  and parse; all 31 local links/anchors resolve. Routes, external references,
  G3's authorization transaction, and implemented-runtime descriptions are
  unchanged. Reviewed the complete diff for confirmation scope and preservation
  of tool-access and prior MCP contracts. Review status, restricted terminology,
  local-path hygiene, and `git diff --check` pass. Documentation only; no runtime
  or browser tests were run.

### Explicit tool cancellation deferred — 2026-09-07

- Moved the opt-in cancellation proposal to
  [its issue](../docs/issues/explicit-tool-call-cancellation.md) for later review.
  Recording the proposal does not approve a `cancellable` schema option,
  generated cancellation tools, or their implementation.
- Retained the background-tool workflow and existing interruption,
  transfer/shutdown, timeout, unknown-outcome, and no-automatic-retry decisions.
  Local worker cancellation and remote business cancellation remain distinct.
- Updated active review status and architecture references. Other G4 questions
  remain open; the overall count stays at 11 numbered groups. Historical
  checkpoint entries above retain the status at their respective decisions.
- This checkpoint changes documentation only. The issue records future
  verification needs; no runtime or browser tests were run.
- Verification: all existing fenced examples are unchanged and all 15 JSON
  examples parse. All nine issue links/backlinks and anchors resolve; external
  URLs are unchanged. The diff contains only the four intended documentation
  paths, with restricted terminology, local-path, and whitespace checks passing.

### Default tool redaction and sample-debug visibility — approved 2026-09-07

- Approved metadata-only tool lifecycle events for ordinary clients, with
  arguments/results visible to the sample debug UI through an explicitly
  server-authorized session projection. Frontend concealment or a client flag
  is not the boundary, and development debugging must remain useful.
- Retained credential/header exclusions and independent agent, variable, and
  call-access permissions. Debug inspection does not approve payload persistence.
- Updated the original contract, architecture, G5 status, and planned tests.
  G5 is partly resolved; archive/retention and sensitive-input policies remain
  under review. The count remains 11 open numbered groups.
- Documentation only: no runtime or sample frontend behavior was changed, and
  no browser or live-provider checks were run.
- Verification: all existing fenced examples are unchanged and all 15 JSON
  examples parse. Links and external URLs are unchanged. Only the three intended
  documentation files changed; G5 status, retained review count, restricted
  terminology, local-path hygiene, and whitespace checks pass.

### Client tool visibility belongs to call setup — approved 2026-09-07

- Refined the visibility decision: configure it in the definition or select it
  explicitly during authorized call creation, with creation taking precedence.
  Pin the effective policy with the call; joining clients do not choose it.
- Include no tool events as a valid behavior, not just payload redaction. Sample
  calls explicitly select full tool visibility through the same call policy;
  a separate frontend/debug-session entitlement is not required.
- Replaced the active special-debug-projection contract, updated the runtime
  override boundary and planned tests, and retained historical checkpoint notes.
  Omitted visibility hides all tool events; exact schema names and selective
  per-tool visibility remain under review. No per-tool policy is approved here.
  Archive/retention questions remain open; the review count stays at 11 groups.
- Documentation only; no gateway, engine, or sample UI behavior changed.
- Verification: all existing fenced examples and all 15 JSON examples are
  unchanged and valid. Links and external URLs are unchanged; only the three
  intended documentation files changed. Hidden-default/precedence checks,
  pending per-tool policy, review count, restricted terminology, local-path
  hygiene, and whitespace checks pass.

### Per-tool visibility targets local participant bindings — approved 2026-09-07

- Approved participant definition key plus local configured tool key as the
  visibility target. Do not use a remote MCP operation name alone: two agents
  can use the same local name or remote operation with different visibility.
- A binding override selects hidden, metadata-only, or full detail; unlisted
  bindings inherit the call-wide default, which is hidden when unspecified.
  Pin selections with the call and resolve invocation identity server-side.
  Existing call-creation precedence and tool/variable permissions are unchanged.
- Updated the original contract, architecture, G5 summary, and planned acceptance
  steps. Exact configuration syntax and private archive/retention decisions
  remain open. G5 is partly resolved; the count stays at 11 open groups.
- Documentation only: no runtime or sample UI changes, and no runtime/browser
  tests were run. Existing schema examples remain unchanged.
- Verification: all existing fenced examples are unchanged and all 15 JSON
  examples parse. Links and external URLs are unchanged. Only the three intended
  documentation files changed; targeting/fallback, retained review status,
  restricted terminology, local-path hygiene, and whitespace checks pass.

### Independent tool-history storage — approved 2026-09-07

Historical checkpoint: its metadata-only default and payload opt-in were later
superseded by always storing complete observed tool history. The independent
storage/client projection boundary and credential exclusions still apply.

- Approved retaining tool-call data according to storage policy independently
  of client visibility. With tool-history storage enabled, metadata is the
  default; arguments/results require explicit retention selection.
- Retained invocation and participant/tool identity, timing, and outcome for
  operational history. Client-hidden events can still have permitted payloads
  stored; full sample visibility does not implicitly enable payload retention.
- Keep storage on its own engine-event projection and asynchronous consumer
  path. Exclude integration credentials and authorization headers before writing.
  Neither stored payloads nor client visibility change agent tool/variable grants.
- Updated architecture, the original persistence/visibility contracts, G5 status,
  and planned cross-policy acceptance checks. Private variable-history payloads,
  retention periods, broader redaction, and configuration syntax remain open.
  G5 stays partly resolved; the count remains 11 open review groups.
- Documentation only: no runtime, database, or sample UI changes; no runtime or
  browser tests were run. No storage duration or new recovery guarantee is set.
- Verification: all existing fenced examples and all 15 JSON examples are
  unchanged and valid. Links and external URLs are unchanged; only the three
  intended documentation files changed. Independent-storage/default checks,
  retained review status, restricted terminology, local-path hygiene, and
  whitespace checks pass.

### Turn-linked variable snapshots and latest lookup — approved 2026-09-07

- Record full post-update variable snapshots associated with originating turns
  and tool invocations. Reuse the saved update-tool arguments; the initially
  discussed separate changeset is unnecessary and is not adopted.
- Capture exact committed values in `CallVariables` for private asynchronous
  retention. Multiple updates in a turn remain distinguishable; rejected updates
  add no successful state snapshot. Live ownership and agent grants are unchanged.
- Adopt the call-record `latest_variables_snapshot_id` pointer, replacing the
  proposed separate latest-section projection. Latest persisted values need an
  indexed lookup or join, not history aggregation or a second mutable copy.
- Insert the snapshot and conditionally advance its same-call pointer in the
  storage consumer, with existing identity/revision/incarnation checks preventing
  duplicate history and stale-pointer regression. This does not put SQL on the
  tool path or promise that asynchronous storage is crash-lossless.
- Updated the original variable/event/persistence contracts, architecture, G5
  summaries, and planned checks. Exact configuration, retention/cleanup, and
  sensitive-input policy remain open; G5 stays partly resolved, with 11 groups open.
- Documentation only: no runtime/database/UI changes or runtime/browser tests.
- Verification: all existing fenced examples and all 15 JSON examples are
  unchanged and valid. Links and external URLs are unchanged; only the three
  intended documentation files changed. Snapshot/turn/pointer consistency,
  retained review status, restricted terminology, local-path hygiene, and
  whitespace checks pass.

### Retention defaults and committed variable updates — approved 2026-09-07

- Approved retention periods at application and tenant level. Tenant settings
  override application values; the application default is retain forever.
  This means no age-based expiration, not broader capture/client access or
  unbounded live buffers. Finite-expiry/cleanup and exact configuration remain open.
- Clarified that database-backed variable-update tools return success only after
  the full snapshot and latest-pointer transaction commits. The earlier
  acknowledge-memory-first/asynchronous-snapshot proposal is superseded.
- `CallVariables` validates and serializes candidates, waits on an engine-owned
  snapshot-persistence port, then adopts the committed state and returns success.
  The adapter owns Ecto/SQL; no room-authority hop or reverse engine dependency
  on Calls is introduced. General tool/turn/usage archival remains asynchronous.
- Confirmed transaction failure cannot become memory-only success. An unknown
  commit outcome is neither success nor proof of rollback; precise uncertain
  commit/restart handling remains open. Snapshot durability does not automatically
  restore a crashed room. No separate changeset or mutation journal is added.
- Updated ownership, authorization, persistence interaction, G5 status, and
  planned commit-barrier/retention-resolution checks across the original labnote,
  architecture, and gap review. G5 stays partly resolved; 11 groups remain open.
- Documentation only: no runtime, database migrations, configuration files, or
  deletion jobs changed. No runtime or browser tests were run.
- Verification: all existing fenced examples and all 15 JSON examples are
  unchanged and valid. Links and external URLs are unchanged; only the three
  intended documentation files changed. Commit-before-success, retention
  precedence/default, retained review status, restricted terminology, local-path
  hygiene, and whitespace checks pass.

### Normal variable-save transaction handling — approved 2026-09-07

- Use the database transaction's normal success/error result. Commit permits
  adoption of the candidate state and tool success; an error returns variable-save
  failure, preserves current in-memory state, and emits no update-success event.
- The extra commit-status lookup/reconciliation proposal is not required for
  this slice. Preserve transaction atomicity and existing invocation/revision
  safeguards without adding a recovery subsystem. Lost replies do not undo commits;
  complete room recovery remains separate from this ordinary save path.
- Updated the original contract, architecture, gap-review status, and planned
  error-path checks. Retention defaults and MCP timeout behavior are unchanged;
  G5 remains partly resolved, with 11 open groups.
- Documentation only; no runtime/database/UI changes or runtime/browser tests.
- Verification: all existing fenced examples and all 15 JSON examples are
  unchanged and valid. Links and external URLs are unchanged; only the three
  intended documentation files changed. Transaction success/error scope, retained
  review status, restricted terminology, local-path hygiene, and whitespace checks
  pass.

### Completed-call retention starts at ended_at — approved 2026-09-07

- Approved `ended_at` as the start of finite retention for completed calls.
  The threshold is `ended_at + retention_period`, not record creation or later
  snapshot/archive writes. Do not expire active-call data; forever has no expiry.
- Missing `ended_at` does not fall back to `created_at` or introduce an automatic
  expiry for prepared records. Cleanup scheduling, referenced snapshots, and
  policy changes affecting existing data remain under review.
- Updated the original retention contract, architecture, review status, and
  planned timestamp/active-call/forever checks. No other pending proposals were
  approved here; G5 stays partly resolved and 11 review groups remain open.
- Documentation only: no runtime/configuration/UI changes or deletion jobs;
  no runtime or browser tests were run.
- Verification: existing fenced examples and all 15 JSON examples are unchanged
  and valid. Links and external URLs are unchanged; only the three intended
  documentation files changed. Retention-clock/default/precedence checks,
  retained review status, restricted terminology, local-path hygiene, and
  whitespace checks pass.

### Current retention applies to all calls — approved 2026-09-07

- Approved the current application/tenant retention period for all calls, past
  and future. Resolve it when evaluating expiry, using tenant override before
  application fallback; do not maintain a historical period or fixed expiry per
  call. This rejects the new-calls-only proposal and its per-call policy storage.
- Shortening a period can make existing completed calls eligible for cleanup;
  increasing it or selecting forever changes eligibility only for remaining data
  and cannot restore deleted data. The `ended_at` clock, active-call exemption,
  and missing-ended_at handling remain unchanged.
- Aligned the call/artifact record descriptions and room-plan pinning with this
  decision. Definition versions, capture permissions, and client visibility remain
  separate. Updated the original retention contract, summaries, architecture,
  gap review, and planned policy-change checks.
- The other four proposals in this review batch remain pending. G5 is still
  partly resolved and the count remains 11 open review groups. No cleanup job,
  runtime/configuration/UI change, or migration is implemented here.
- Verification: existing fenced examples and all 15 JSON examples are unchanged
  and valid; links and external URLs are unchanged. Three-file scope, current
  policy/precedence/clock rules, unrelated review sections, terminology/local-path
  hygiene, and whitespace checks pass. No runtime or browser tests were run.

### Retention expiry deletes the entire call — approved 2026-09-07

- Approved deletion of the call record and everything stored for that call after
  retention expires: transcripts, tool/usage history, all variable snapshots,
  recordings if present, exports, and other call-owned rows/copies. A soft delete
  or retained summary/latest snapshot does not satisfy this scope.
- Shared definitions and application/tenant configuration remain. Both database
  and object-storage data are in scope; no cross-store atomicity is claimed.
  Pending or late archival/publication must not recreate deleted call data.
- Updated architecture, the gap review, the original retention/snapshot
  contracts, summaries, and planned whole-call cleanup checks. Current-policy
  resolution, the `ended_at` clock, and active/forever rules remain unchanged.
- This resolves item 2 of the five-item review batch; the other three proposals
  remain pending. G5 stays partly resolved and 11 review groups remain open.
  Scheduling and cleanup mechanics remain to be designed. No runtime, deletion
  job, migration, or UI was changed, and no stored call data was deleted.
- Verification: unchanged fenced examples and 15 valid JSON examples, unchanged
  links/URLs, three-file scope, deletion and existing retention contracts,
  unrelated review sections, terminology/local-path hygiene, and whitespace
  checks pass. No runtime or browser tests were run.

### Greeting, transfer failure, and redaction scope — approved 2026-09-07

- Approved per-agent wait-for-input, fixed greeting, or generated greeting on
  first activation in a call. Reconnect/reactivation do not replay startup speech.
- Approved source-agent conversational responsibility until successful handoff;
  failed attempts return a typed outcome for that agent's next permitted action.
  Room authority remains separate; committed transfer ends the source execution
  subtree without undoing previously submitted variable commands.
- Deferred general voice/LLM-input redaction. Deterministic collection such as
  DTMF can bypass LLM interpretation, but its input and recording/logging paths
  are not automatically confidential or newly implemented. Existing secret
  exclusions and permissions remain required.
- Updated the original contracts, architecture, G5/G7/G8 status, and planned
  acceptance checks. All five items in the latest batch are now resolved.
- Replaced the active group count with an auditable backlog of 50 individual
  decisions (R01–R50); the next five proposals are R01–R05 and are not approved.
  Deferred features and implementation-only work are tracked separately.
- Documentation only: no runtime, schema release, UI, or provider integration
  changed. Verification covers unchanged fenced/JSON examples and links, the
  approved boundaries, exact backlog IDs/count, unrelated contracts, terminology,
  local-path hygiene, and whitespace. No runtime or browser tests were run.

### API-key scopes and independent join-token lifetime — approved 2026-09-07

- Resolved R01–R05: trusted OTP/CLI first-key creation; tenant-bound `admin` and
  `calls` scopes; multiple independently revocable keys; revocation that rejects
  further key authentication without invalidating issued tokens or established
  connections; and five-minute default tokens with longer requested lifetimes.
- Rejected the proposed coupling between API-key revocation and unused join
  tokens. Admission still checks token scope, its own expiry and consumption,
  and current call/participant eligibility. Fresh issuance requires a valid key.
- The authenticated backend can request longer expiry for either preparation or
  existing-call tokens. No unapproved cap, TTL configuration hierarchy,
  per-definition key allowlist, arbitrary operation-grant scheme, or complete
  admin API was added. Whether admin implies calls is not asserted.
- Updated canonical admission/recovery contracts, summaries, architecture, and
  planned bootstrap/scope/rotation/revocation/lifetime checks. Stable IDs R01–R05
  are resolved; 45 individual decisions remain, R06–R50. The next batch,
  R06–R10, remains proposals. Earlier progress counts describe earlier checkpoints.
- Documentation only: no credential, endpoint, CLI command, configuration, schema
  release, or runtime authentication behavior changed. Verification covers the
  three-file scope, unchanged fenced examples and 15 valid JSON examples,
  unchanged links/URLs, resolved/pending IDs and counts, retained unrelated
  contracts, terminology/local-path hygiene, and whitespace. No runtime or
  browser tests were run.

### Unstarted-call tokens without caller reconnection — approved 2026-09-07

- Kept backend-authorized replacement token issuance for eligible unstarted
  records. Expiry before first joining does not require preparing another call:
  preserve the existing call ID, pinned definition, and initial variables, and
  start no room at issuance.
- Deferred same-call caller reconnection (R07) for the initial slice. A fresh
  token does not prove the returning person's identity. After logical call
  termination, connecting again starts a newly authorized call with a new record
  and identity, not a resumed old call. No browser session-tracking mechanism is
  introduced. First admission of an eligible transfer destination or another
  not-yet-admitted participant into a live room remains supported.
- Preserved single-use claim, backend/tenant/call/participant authorization,
  pending-admission reconciliation, no active takeover, independent token/key
  revocation, five-minute default/requested longer lifetime, and no automatic
  unstarted-record expiry. A temporary transport interruption is not automatically
  a logical call end; no exact end trigger or any-participant-disconnect hangup
  policy was approved.
- R06 remains open specifically for whether issuing another token supersedes
  earlier unused tokens. There are 44 individual pending decisions: R06 and
  R08–R50. R01–R05 remain resolved and R07 is deferred. Prior historical reconnect
  promises/counts are superseded, not evidence of a current runtime feature.
- Updated canonical admission, cardinality, timing and persistence summaries,
  architecture, backlog, and planned checks for unstarted replacement, first
  destination admission, rejected caller resume, and a new call after termination.
  Greeting non-replay still applies; its checks no longer require reconnection.
- Documentation only: no transport, endpoint, runtime, configuration, or schema
  changed. Verification covers exact three-file scope, unchanged fenced examples
  and 15 valid JSON examples, unchanged links/URLs, backlog statuses/count,
  admission boundaries, retained unrelated contracts, terminology/local-path
  hygiene, and whitespace. No runtime or browser tests were run.

### Common token admission and optional opening audio — approved 2026-09-07

- Resolved R08 with one API-client workflow: authenticated call preparation with
  initial variables returns a scoped token, then either browser or backend joins
  with that token. Removed the separate API-key media-socket start and first-
  message variable setup from active contracts/tests. Existing WebRTC, eligible
  unstarted-record reissuance, and first admissions into live calls remain.
- Marked R09 superseded: its direct setup message no longer exists. The proposed
  ten-second deadline/64 KiB limit was not approved for another route. Token wire
  encoding remains adapter work, not another direct-start design. R06's unused-
  token supersession, R10's inbound variables, and R11 personalization stay open.
  Current backlog: 42 individual pending decisions, R06 and R10–R50.
- Named the optional call-level setting `opening_audio`. Omission preserves
  normal startup with no announcement delay. A configured file URL or fixed text
  rendered as audio plays to the caller before receiver activation and normal
  room audio services; it is distinct from agent `first_message` and applies to
  initial startup, not every transfer. No mandatory disclosure or legal guarantee.
- Fixed text uses the initial receiving agent's resolved TTS/voice and produces
  a reusable cached asset. Cache identity covers exact text, resolved provider/
  model/voice and relevant output settings, scoped to tenant/configured binding;
  changed inputs cannot reuse stale audio. No secrets in cache keys/logs. No
  arbitrary map-order voice or later transfer agent is selected for human-only
  entry; missing initial-agent/TTS applicability remains open.
- Kept only minimal caller playback active before completion. Fixed-text TTS
  rendering is a narrow asset-preparation exception, not normal agent/STT/model/
  recording activation. Download/render/cache/enqueue does not prove playback
  completion; failed/incomplete configured audio does not silently release the
  gate. Actual live-call start still owns `started_at`; asset generation itself
  starts no call tree or clock. Reusable configuration assets are not per-call
  recording/export retention. Exact render timing, source schema/formats,
  cache/fetch infrastructure, completion evidence/failure handling, and later-
  participant notices remain unselected.
- Synchronized original admission/startup contracts, architecture, review status,
  and planned common-client, optional-playback, and text/cache checks. Historical
  direct-start proposals are retained as superseded. Documentation only; no
  runtime, endpoint, dependency, configuration, or schema release changed.
- Verification covers three-file scope, unchanged fenced examples and 15 valid
  JSON examples, 37 local links/anchors and unchanged external URLs, stable
  backlog IDs/count, admission/startup boundaries, prior independent auth,
  retention and variable-commit contracts, terminology/local-path hygiene, and
  whitespace. No runtime or browser tests were run.

### Capability warmup, independent tokens, and existing initialization — approved 2026-09-07

- Corrected opening-audio gating from capability startup to participant-media
  input. Room/participant capabilities may start and warm up during playback;
  no user or other participant audio is delivered to them or normal conversational
  media paths until playback completes. Transport receipt/provider readiness do
  not authorize delivery. Normal greeting/conversation still wait; this does not
  approve text barge-in, capture, or retrospective replay of the blocked interval.
  No buffering/replay mechanism is added. Omission, actual-playback evidence,
  failed/incomplete-playback gating, initial-agent TTS/cache semantics, and actual
  call-start timing remain unchanged.
- Resolved R06: another token for the same eligible unstarted call does not
  invalidate earlier unused tokens. Each retains its own expiry/single-use rules;
  shared admission prevents duplicate callers/startups, active takeover,
  same-call caller reconnection, and ended-call reuse. No issuing-key revocation
  coupling or automatic prepared-record expiry is introduced.
- Closed R10 as already covered, not a new feature: an authorized creator,
  backend, or trusted ingress supplies known declared initial variables at call
  creation. Unknown values remain unfilled for normal permitted tools. Removed
  the proposed automatic admission/customer-lookup resolver; caller number is
  not silently treated as verified customer identity.
- R09 remains superseded with the removed direct WebSocket setup path; asking
  for clarification does not approve its proposed limits elsewhere. R11 and
  other pending items remain unapproved. Current backlog: 40 individual
  decisions, R11–R50, with stable IDs and historical counts left as checkpoints.
- Updated canonical startup/admission/initialization sections and future tests,
  not only progress notes. Verification covers exact three-file scope, unchanged
  fenced examples and 15 valid JSON examples, 37 local links/anchors and unchanged
  URLs, resolved/pending IDs/count, earlier auth/retention/variable contracts,
  terminology/path hygiene, and whitespace. Documentation only; no runtime,
  endpoint, schema, configuration, or browser changes/tests.

### Instruction-owned personalization and deferred executor retries — approved 2026-09-07

- Resolved R11: keep personalization in agent instructions using the existing
  permitted variable-read tools, without a template/interpolation/binding engine.
  Missing values and permissions retain their existing variable contracts.
- Resolved R12: locale/timezone/business-time context belongs to the integrating
  application and agent instructions. Provide date/current-time tooling for fresh
  observations; no call-level fields/default hierarchy, frozen new tool schema,
  or change to authoritative call timestamps is approved.
- Resolved R14 with no automatic tool/MCP executor retries for any failure,
  including known non-submission. Known errors remain definite; ambiguous remote
  outcomes remain unknown. A later model-requested invocation is distinct, not
  an exactly-once or deduplication guarantee.
- Resolved R15 by skipping trusted read-only/idempotent-write/side-effect
  classification now. Deferred R16's automatic retry/business-idempotency
  exceptions to `docs/issues/automatic-tool-retries-and-idempotency.md`, recording
  future correlation/idempotency, attempts, budgets, and verification questions
  without adopting a retry mechanism. R39 call-creation idempotency, R40 admission
  recovery, and normal database transactions are not deferred or changed by it.
- Updated active contracts, review scenarios, architecture, and future checks.
  R13 remains a separate pending destination question at this checkpoint. The
  individual backlog is 35: R13 and R17–R50; stable resolved/deferred IDs remain.
- Documentation only. Verification covers the exact four files, unchanged
  existing fenced examples and 15 valid JSON examples, preserved existing links
  and external URLs plus the new issue links, local targets/anchors, exact
  statuses/count, previous admission/opening/retention/variables contracts,
  terminology/local-path hygiene, and whitespace. No runtime or browser tests.

### Protected creation-time dial routing — approved R13, 2026-09-07

- Kept literal participant numbers and added candidate `number_from_variable`
  with direct section/variable keys as a mutually exclusive alternative. The
  trusted backend selects an authorized number and supplies it through ordinary
  initial variables; no blind forwarding of caller-selected destinations.
- Require every agent to lack write permission to referenced routing sections;
  reject definitions that grant it. Read permission is optional and not required
  for trusted resolution. No per-variable grants or runtime routing-mutation API.
- The resolver uses the pinned definition/reference and protected initialized
  data. Missing/null/invalid numbers fail before dialing through the existing
  typed outcome, retaining source-agent responsibility and avoiding defaults.
  Updated the old no-number-lookup wording to distinguish internal resolution
  from forbidden SQL/external-directory work in the engine.
- Model-facing transfers remain destination-participant refs only, with executor
  rechecks of the compiler-derived source allowlist. No phone/provider/URL/
  variable-ref arguments. The model may choose timing and among allowed roles;
  any business timing enforcement belongs outside the LLM, not a new guardrail
  feature here. No generic outbound allowlist/region matrix or expression system.
- Added one focused candidate excerpt and future source/grant/validation tests.
  R13 is resolved at this scope; 34 individual decisions remain, R17–R50.
  The retry/idempotency issue and R39/R40 status are unchanged.
- Documentation only. Verification covers the three-file scope, all 15 existing
  JSON examples unchanged plus the new valid routing excerpt, unchanged existing
  fences/links/URLs, local targets/anchors, resolved/pending IDs/count, protected
  routing and unrelated contracts, terminology/path hygiene, and whitespace.
  No runtime or browser tests were run.

### Periodic external-first retention cleanup — approved R20/R21, 2026-09-07

- Approved periodic background sweeps selecting completed calls under current
  tenant/application retention from `ended_at`, not instant threshold-triggered
  deletion or per-call timers. No fixed period/policy is copied to each call.
  Exact cadence/default is unspecified; no hourly frequency or deletion SLA.
- Delete all managed call-owned external objects/copies first, then call-owned
  database data and the call record. Definitive key-not-found means already
  absent; actual failures/timeouts/authentication/permission/unknown outcomes keep
  the database records and references for a later sweep.
- Resume after partial deletion/crash by repeating deletes from retained call/
  artifact rows. Missing objects succeed; database failure also leaves retryable
  work. No per-object progress journal, separate reconciliation subsystem, or
  permanent tombstone. Complete cleanup leaves no call row, summary, or snapshot.
- Retained the late-writer coordination requirement: external-first ordering
  alone cannot prevent recreation. No new detailed writer-fencing mechanism is
  approved. Shared configuration/assets and unrelated calls are not deleted;
  internal cleanup retries do not change the no-automatic-tool-retry policy.
- R20/R21 are resolved; actual R22 remote-protocol support is unchanged. Current
  backlog: 32 individual decisions, R17–R19 and R22–R50. Updated canonical
  retention sections/summaries and planned crash/error/not-found/writer tests.
- Documentation only; no cleanup job or stored-data deletion performed. Checks
  cover exact three-file scope, all 16 existing JSON examples and fences unchanged,
  unchanged links/URLs, local anchors, exact statuses/count, ordering/failure and
  prior routing/admission/variables contracts, terminology/path hygiene, and
  whitespace. No runtime or browser tests.

### Retention setting encoding — approved R19, 2026-09-07

- Chose application/tenant `call_retention` as `"forever"` or an explicit finite
  duration object, such as `{"seconds":2592000}` for 30 days. Application omission
  defaults forever; tenant omission inherits; explicit tenant forever overrides
  finite application retention. No call-level field, policy copy, null sentinel,
  or human-readable duration parser.
- Preserved current policy for past/future calls, the `ended_at` clock and
  active/unstarted exclusions, whole-call deletion, and periodic external-first
  cleanup. Exact sweep interval remains unspecified deployment tuning.
- R19 is resolved; 31 individual decisions remain, R17, R18, and R22–R50.
  Updated canonical contracts and planned encoding/inheritance checks.
- Documentation only. Verified exact three-file scope, all 16 existing JSON
  examples/fences unchanged, links/anchors, statuses/count, unchanged prior
  contracts, terminology/path hygiene, and whitespace. No runtime tests.

### Complete observed tool history — approved 2026-09-07

- Always store invocation/participant/tool metadata, timing/outcomes, arguments/
  request payloads, and observed responses/results/errors with the call. Removed
  the tool-history enable switch, metadata-only storage mode, per-tool payload
  selection, and arguments/results opt-in from active contracts and test plans.
- Kept client hidden/metadata/full visibility and per-binding overrides separate.
  Exclude integration credentials/auth headers before persistence; no raw wire
  credential capture or general redaction is added. Unknown remote outcomes stay
  unknown, without fabricated results.
- General tool/event archival remains asynchronous. Variable updates still need
  their full snapshot/latest-pointer transaction to commit before tool success;
  saved arguments already describe changes, without a changeset journal. Retention
  deletes this complete history with the call.
- R18's tool portion is resolved; non-tool capture/storage configuration remains
  pending. Count remains 31 individual decisions: R17, R18, and R22–R50.
- Documentation only. Checked exact three-file scope, unchanged 16 valid JSON
  examples/fences and links/anchors, obsolete active storage rules, prior
  contracts, statuses/count, terminology/path hygiene, and whitespace. No runtime tests.

### Tool visibility configuration — approved R17, 2026-09-07

- Adopted `tool_visibility` (`hidden`, `metadata`, or `full`) and optional
  `tool_visibility_overrides`, keyed by participant definition then local tool
  binding. Omission hides all events; binding overrides win over the default,
  and identical local names on different participants remain independent.
- Trusted creation may replace the effective policy pair from the definition;
  omitted creation policy inherits it. Samples use full with no overrides, not
  a default-only edit that would retain hidden bindings. No deep-merge/patch API,
  extra debug grant, or browser-controlled upgrade.
- Pinned server-side projection, execution/variable grants, credential exclusions,
  and complete observed tool storage remain unchanged. Added illustrative JSON
  policy examples and planned precedence/omission/sample checks; no runtime changes.
- R17 is resolved; 30 individual decisions remain, R18 and R22–R50.
- Verified exact three-file scope, 16 preserved JSON examples plus two new valid
  visibility examples, existing fences/links/anchors, statuses/count, prior
  contracts, terminology/path hygiene, and whitespace. No runtime/browser tests.

### Available call history without category toggles — approved R18, 2026-09-07

- Always save available transcripts, turn details, and usage/model/cost
  observations alongside complete tools and committed variables. No per-category
  storage switches. Preserved typed-text provenance, provider-final speech facts,
  generated versus confirmed spoken/delivered agent text, and interruption state.
- Store audio only through explicitly enabled and permitted recording, respecting
  participant/room denials and the opening-audio media-input gate. Do not start
  STT or recording merely to produce archival data. Missing transcripts, usage,
  or prices remain unavailable, not fabricated or treated as zero.
- Preserved asynchronous general archival, snapshot/latest-pointer transactions
  before variable-tool success, credential exclusions, agent/client permissions,
  and whole-call retention. Detailed accounting and archival failure choices
  remain pending; no new general SQL acknowledgement boundary.
- R18 is resolved; 29 individual decisions remain, R22–R50. The next five are
  R22–R26; their proposals are not adopted by this decision.
- Documentation only. Verified exact three-file scope, all 18 existing JSON
  examples/fences unchanged, links/anchors, active capture/permission boundaries,
  prior contracts, statuses/count, terminology/path hygiene, and whitespace.
  No runtime or browser tests.

### Remote MCP profile and deferred interactions — R22–R25, 2026-09-07

- R22 selects `2026-07-28` Streamable HTTP, JSON/request-scoped SSE, and its
  revision-specific request metadata/lifecycle. Other revisions/legacy transports
  need explicit tested compatibility; no old session assumptions or runtime claim.
- R23 requires a proper JSON Schema validator, baseline 2020-12, for actual
  outgoing arguments against the selected/discovered pinned input schema before
  submission. Reject unsupported enabled bindings before exposure; no schema
  weakening, unvalidated calls, automatic network refs, library choice, or new caps.
  Incremental Call Variables remain exempt from required-variable completeness.
- R24 saves received structured responses and resource/attachment descriptors
  with observed outcomes. Agents choose authorized next steps; storing a link
  does not fetch/understand it or negate reported success. Added a deferred
  result/document-inspection issue rather than an automatic reader or text-only filter.
- R25 defers sampling, elicitation, and related interactions in a separate issue.
  No unsupported capability advertisement or ambient authority. `input_required` /
  MRTR continuation is future work, not approval of automatic resubmission/retries.
- Reaffirmed available history storage; audio requires recording to be available,
  integrated, enabled, and permitted. Privacy, grants, retention, asynchronous
  ordinary archival, and variable transaction acknowledgements are unchanged.
- R22/R23 resolved and R24/R25 deferred: 25 individual decisions remain, R26–R50;
  the next five R26–R30 remain proposals. Planned checks cover JSON/SSE transport,
  required/type/enum/nested argument failures before submission, unsupported schema
  rejection, descriptor storage without fetch, and unsupported interactions with
  no capability advertisement, extra permissions, or automatic continuation.
- Rechecked official transport/schema/tool/interaction references. Verified exact
  five-file scope, 18 unchanged valid JSON examples/fences, existing and new
  links/anchors, statuses/count, prior contracts, terminology/path hygiene, and
  whitespace. Documentation only; no dependencies, runtime, or browser tests.

### Endpoint security and conversation timing — approved R26–R30, 2026-09-08

- Adopted SDK-aligned endpoint/address protections at Vxpipe's own outbound
  boundary, not a Go dependency or claim its OAuth-helper defaults protect all
  MCP traffic. Verified HTTPS, controlled host-authorized private access, connect-
  time checks, and no automatic redirects/credential forwarding are required.
- R27 defaults required startup readiness to configurable 30 seconds from the
  actual post-join attempt; terminal failures fail early and expiry releases
  resources. Deliberate opening playback is separate, preserving its gate and
  actual-start timestamps rather than truncating the file.
- R28 defaults genuine agent input-wait to a configurable 15-second notification,
  with instructions selecting nudge/wait/permitted hangup. Excluded non-idle phases,
  automatic silence hangup, and invented repeated announcements/local VAD/models.
- R29 keeps kickoff/result speech instruction-driven with one agent/voice, no
  periodic tool-progress speech. Added the deferred wait-music issue for startup
  and long-tool waits without media/configuration implementation.
- R30 sets the 30-minute platform duration default using `limits.max_duration_ms`;
  definition overrides tenant, then application. Pin the resolved value and clock
  from actual `started_at`, across transfers/recovery and human-only portions.
  End with a clear duration-limit reason; no new creation override, unlimited
  mode, warning/grace, or closing-speech guarantee. Retention stays current-policy.
- R26–R30 resolved: 20 individual decisions remain, R31–R50; next five R31–R35
  are unapproved. Updated canonical sections and planned checks 28–31.
- Verified exact four-file scope, 18 unchanged JSON examples/fences, links and
  anchors including the new issue, statuses/count, timers/security and prior
  contracts, terminology/path hygiene, and whitespace. Documentation only;
  no dependencies, runtime, or browser tests.

### Transfer acceptance and instruction-owned closing — 2026-09-08

- R31 leaves closing wording and choosing when to call existing hangup with
  agent instructions. No new closing API, mandatory playback drain, automatic
  pending-hangup cancellation on speech interruption, or playback guarantee.
- R33 chooses shared call-level `transfer_policy`, simple source `transfers`
  lists, and destination connection/acceptance requirements without named/source-
  default/per-pair machinery or further frozen schema options.
- R34 requires agent conversation/capability readiness or human usable media plus
  explicit press-1 DTMF/web acceptance. The web client owns interaction; server
  checks bind it to the destination connection/participant and pending attempt.
  Stale/duplicate/source/model assertions cannot commit. Source responsibility
  and target capability barriers remain; transport connection alone is not admission.
- R35 sets one configurable 30-second total attempt interval from accepted
  preparation, including dialing/acceptance. Fail early on definite failure;
  timeout/failure stops the destination and returns a typed outcome. Late callbacks
  cannot commit; cleanup is exact-leg, without auto-redial or new recovery claims.
- R32 uses supported provider AMD with provenance/unknown retained, not local
  inference or transfer acceptance. Post-detection machine/unknown actions remain
  pending; rechecked the official provider detection references without selecting
  modes, tuning, end-leg, or message behavior.
- R31/R33/R34/R35 resolved: 16 individual decisions remain, R32 and R36–R50;
  next five R32 and R36–R39. Updated canonical contracts and planned checks 32–35.
- Verified exact three-file scope, 18 unchanged JSON examples/fences, links and
  anchors, statuses/count, transfer/closing/privacy and prior contracts,
  terminology/path hygiene, and whitespace. Documentation only; no runtime tests.

### Machine-detected destination handling — 2026-09-08

- Resolved R32: configured provider detection reporting machine disconnects the
  attempted outbound destination leg. Transfer failure returns to the source,
  preserving original caller/source conversation when permitted, not ending the
  room. Initial outbound-only attempts terminate without voicemail speech.
- Unknown, disabled, and unavailable detection remain uncertain, not machine/human
  proof. Unknown transfers await explicit acceptance within the same total attempt
  deadline; no clock reset, automatic speech, local classifier, or accuracy promise.
- Created the deferred voicemail-message-delivery issue for future provider evidence,
  source/policy, correct-leg privacy, delivery outcomes/deadlines, and compatibility
  questions. It does not reinstate a platform closing-speech workflow.
- Updated canonical behavior and planned acceptance step 35. There are now 15
  individually pending decisions, R36–R50; next five R36–R40 remain unapproved.
- Verified exact four-file scope, 18 unchanged JSON examples/fences, old/new links
  and anchors, leg/outcome/deadline boundaries, prior contracts, statuses/count,
  terminology/path hygiene, and whitespace. Documentation only; no runtime tests.

### Private briefing and bounded recovery — 2026-09-08

- Resolved R36 with exactly one bounded permitted-source restoration attempt,
  no reset through supervisor/application retries, and call end if no usable
  conversation remains. A valid working human conversation may continue. Detailed
  cause remains internal, not speech/events/debug UI, including full samples.
- Resolved R37's initial scope: private destination briefing/optional notice before
  acceptance/bridge, minimum-necessary permitted information, source retained until
  commit. No general concurrent-agent consultation or compliance guarantee.
- R38's approved direction replaces primary capability denial with presence-driven
  media publishing/subscription, independent live transcript sharing, and transcript/
  audio retention. Marked denial examples as historical and revised canonical
  invariants; no replacement schema selected. R18 stores permitted available data,
  not forbidden transcripts/audio; tools/usage and variable snapshots stay intact.
- Resolved R39 without API creation idempotency: repeated requests may create
  separate prepared records. Same-call token/admission and provider webhook
  identities still prevent duplicate startup; no deletion endpoint/UI implemented.
- Resolved R40 as bookkeeping recovery only for existing work. Never automatically
  repeat/redial/reconnect a crashed call; uncertain dialing gets an appropriate
  failed/unknown record and known-resource cleanup, not a speculative second dial.
- Updated planned checks 36–39 and the earlier relevant scenarios. There are 11
  individually pending decisions, R38 and R41–R50; next five R38 and R41–R44.
- Verified exact three-file scope, valid unchanged JSON examples, the deliberate
  admission-identity text-example correction, preserved links/anchors, prior
  contracts and approved supersessions, count/status, terminology/path hygiene,
  and whitespace. Documentation only; no runtime or browser tests.

### Presence-driven routing and retention — approved R38, 2026-09-08

- Normal call-wide `media_policy` and participant `while_present` use direct-key
  audio/transcript route maps plus independent room-wide `record_audio` and
  `save_transcripts`. Explicit maps are complete allowlists; omission inherits,
  empty maps allow none, present restrictions intersect, and storage false wins.
  Host authorization remains the ceiling; transport loss does not clear presence.
- Added the approved specialist fragment and composable storage examples. Kept
  old denial JSON clearly superseded, not another accepted public policy format.
- Live transcription and storage are independent. Stop STT flows with no permitted
  live/storage consumer; permissions neither enable unconfigured capabilities nor
  activate every catalog participant. Interval restrictions cover automatic Vxpipe
  capture/archive/log/export/model-debug copies, without retroactive deletion of
  earlier permitted history or generic redaction/control of independent copies.
- Private preparation carries only authorized destination briefing/notice; caller
  cannot hear it. At commit apply presence restrictions before main media, then
  hand off/terminate source. Mixing, routing, transcript, recording, and archive
  boundaries enforce the pinned room-authorized policy and fail closed.
- Updated canonical sections, summaries, validation, and planned check 39. R38 is
  resolved: 10 individual decisions remain, R41–R50; next five R41–R45 unapproved.
- Verified three-file documentation scope, preserved historical examples, new
  JSON syntax and policy semantics, links/anchors, exact status/count, unchanged
  remaining review rows, prior contracts, terminology/path hygiene, and whitespace.
  Documentation only; no runtime or browser tests.

### Usage evidence and honest attribution — approved R44/R45, 2026-09-08

- Every usage observation belongs to the call, with participant/activation/service-
  interval/turn links where supported. STT/TTS may have several observed service
  intervals per participant; no invented billable duration, forced turn allocation,
  or duplicate charge from multiple aggregate views. TTS turn links are provider-dependent.
- Preserve actual provider IDs with provider/integration/tenant namespace, distinct
  from local correlation. Optional supported billing lookup is asynchronous and
  outside room/media work, may outlive the room, and never resets `ended_at` or
  promises a cost when lookup is unavailable. Integration auth/isolation is unchanged.
- Retain observations and derive effective attempt/component usage: delta/cumulative
  mode is distinct from estimate/final/correction status. Proven repeated identities
  deduplicate; equal values do not. Finals supersede estimates, explicit corrections
  may decrease, and stale estimates cannot win by arrival order. Preserve failed/
  interrupted usage and distinct components/units/currencies without fabricated zero.
- Replaced the old single immutable usage-row contract and updated planned checks
  40–41 plus the earlier usage steps. Pricing-source/version/fallback remains R46;
  R41–R43 archive guarantees are not implied. Ordinary usage archival stays async,
  variables retain transaction-confirmed snapshots, and privacy/retention still apply.
- R44/R45 resolved: 8 individual decisions remain, R41–R43 and R46–R50; next five
  R41–R43 and R46–R47. Verified exact three-file scope, unchanged JSON examples and
  links/anchors, accounting arithmetic, unchanged remaining review rows, prior
  contracts, count/status, terminology/path hygiene, and whitespace. Documentation
  only; no runtime or browser tests.

## Verification evidence

- Reviewed existing Vxpipe architecture, product intent, current create-room
  command, and prior runtime-extraction research.
- Reviewed the complete local comparative research corpus.
- Rechecked current first-party documentation for stored versus inline
  definitions, draft/published versions, multi-agent member composition,
  graph/node flows, tool-triggered handoffs, variables strategies, typed tasks,
  active-agent/session ownership, and visual-builder limitations.
- Confirmed that the current Vxpipe create-room contract still accepts at most
  one hard-coded agent preset, so the proposed first checkpoint has a bounded
  integration target.
- Confirmed that the current tool executor accepts only a static list of trusted
  Elixir modules. Remote MCP bindings therefore require a backend-neutral tool
  binding, but do not require changing the model/room/RTVI tool lifecycle.
- Refined integration scope after review: remote MCP endpoint, authentication,
  discovery, health, and limit configuration is application-wide or
  tenant-scoped, never invocation-scoped. A configured integration becomes
  available infrastructure; each agent selects specific operations through its
  unified `tools` map. Other agents in the same call do not inherit that surface.
- Refined the authoring contract after review: schema identifiers use the
  date-based `YYYYMMDD.NN` format; the current proposal is `"20260906.02"`.
  `entry_caller` and `entry_receiver` are definition-local participant refs;
  they replace the earlier single entry field. Participant-control
  transfers are engine-owned tools, a room may continue without an active agent
  participant, and neither the public definition nor resolved plan uses generic
  nodes or edges.
- Clarified the runtime identity model: every room member is a participant whose
  kind is `human` or `agent`; an agent definition materializes an agent
  participant. Transfer refs name definition-local participant definitions,
  while the room always commits a transfer between concrete runtime
  participants. This includes an intake agent participant transferring control
  to a human service agent participant.
- Made transfer availability derive from each agent participant definition's
  direct `transfers` ref list. An absent or empty list exposes no transfer tool;
  a non-empty list produces one compiler-owned tool restricted to that active
  agent's destination refs. Authors do not place transfer tools in the general
  `tools` map.
- Corrected capability-policy ownership: there is no generic `on_success` action
  bag and transfer possibilities do not enumerate capability changes. Each
  runtime participant inherits an immutable presence policy from its trusted
  agent definition or application/tenant destination. Positive capability
  intent remains in the call and active-agent plans; presence policies only deny
  capabilities. The room filters normal intent through applicable denials
  before transfer commit and reconciles back toward that baseline when a
  restrictive participant leaves.
- Separated a presence policy's owner activation from its affected participant
  selector. A policy can apply while its owner is admitted or, for an agent,
  while it is the active agent. The initial selector surface constrains either
  all participants or instances of a named agent definition; `active` never
  means voice activity.
- Kept each capability denial's `participants` field as a non-empty selector
  list with union semantics, but narrowed the initial selector grammar to
  `{"type": "all"}` and `{"type": "agent", "ref": "..."}`. Individual-human,
  kind, destination, self, and runtime-ID selection are deferred.
- Added room-owned typed variable sections with per-agent `read`/`write` grants.
  Top-level section grants are the initial contract; nested dot-path and wildcard
  permissions are deferred.
- Reviewed Callpipe's Telnyx webhook, Call Control, media WebSocket, call-router,
  participant-connection, and handoff paths. Refined telephony as a common
  adapter contract that can support Telnyx, Twilio, and later providers while
  keeping provider commands, identifiers, and webhook payloads out of the public
  definition. Participant-specific non-secret connection intent may select a
  configured service, connection mode, and number in the definition; provider
  credentials and deployment ingress configuration remain application- or
  tenant-scoped.
- Recorded that the room authority owns the immutable resolved call plan for the
  entire room incarnation. The plan pins the exact definition revision,
  participant catalog, transfers, policies, and resolved service/profile
  revisions in memory. Normal orchestration does not repeatedly consult mutable
  database definitions, and recovery must reload the same snapshot rather than
  adopting a newer revision.
- Inspected the current room authority, room-incarnation supervisor, room
  snapshot, model-inference loop, and tool executor before planning variables.
  Initially selected `RoomAuthority` ownership; the approved dedicated-process
  follow-up supersedes it. `CallVariables` now owns variable state, schemas,
  grants, and atomic revision checks, and receives bounded calls directly from
  model/tool workers. Source-agent shutdown does not cancel submitted updates.
- Specified a working `20260906.02` variables shape with section schemas, direct
  initial-variable values (replacing the earlier input bindings), per-agent
  section permissions, independent revisions, activation-scoped projections,
  and compiler-generated read/update tools. The plan includes focused red-green
  checkpoints and manual acceptance steps; no runtime implementation was
  performed in this checkpoint.
- Inspected an existing encrypted-Ecto credential implementation: a runtime
  Base64-decoded 32-byte key, supervised Cloak vault, AES-GCM cipher, redacted
  encrypted fields, and binary database columns. Applied that approved storage
  pattern to the earlier gateway client-credential design without accessing any
  real credential or environment-file contents. The later API-key decision
  superseded HMAC; the subsequent storage decision selects one-way hashes for
  Vxpipe-issued keys. Recoverable upstream credentials remain a separate concern,
  and authentication remains outside the call engine.
- Inspected the umbrella dependencies and persistence-related runtime surfaces.
  The repository currently has only gateway and call-engine applications and no
  Ecto/Repo boundary. The gateway directly creates an engine room, while room
  events are sent primarily to participant connection processes rather than one
  complete durable event sink.
- Confirmed that the current model-provider behavior and ReqLLM adapter return
  only text/tool/error outcomes to model inference. ReqLLM already exposes
  normalized response usage and best-effort cost for buffered and streaming
  requests, but the adapter currently discards it. STT and TTS provider
  contracts likewise have no normalized usage result.
- Corrected the audio boundary after review: the current engine has direct
  participant ingress and agent TTS egress but no multi-source room mixer or
  monitor subscription. The target adds a live engine-owned mixer with
  mix-minus participant outputs and a full silent-monitor output. The recording
  capability taps participant tracks and the live full mix and streams them to
  external artifact writers; offline remixing is optional only.
- Split the persistence proposal into definition/routing, call/event/variables
  ledger, provider usage, live room mixing, recorded live-mix and separate-track
  artifacts, optional offline remix, and final call-details publication.
  Selected database-free `vxpipe_calls`
  application workflows, an Ecto-owning `vxpipe_persistence` adapter, and a
  later object-store-owning `vxpipe_artifacts` boundary; the call engine and
  gateway keep direct Repo access out of their responsibilities.
- Reviewed the official MCP `2026-07-28` tool specification, Streamable HTTP
  transport, and generated schema:
  - <https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2026-07-28/server/tools.mdx>
  - <https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2026-07-28/basic/transports/streamable-http.mdx>
  - <https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/schema/2026-07-28/schema.json>
- No runtime test suite or browser checks were run; this checkpoint changes
  research documentation only and uses the documentation checks recorded above.
