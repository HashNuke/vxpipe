# Call definition design

Research date: 2026-09-05 UTC

## Goal

Define the smallest useful call-definition contract for Vxpipe: one reusable,
versionable, participant-first description that can start a single-agent call
today and grow into multi-agent calls, scoped context, transfers between agent
and human participants, tools, and telephony without forcing ordinary calls
into a general-purpose workflow language. Participant-control transfers are
engine-owned tools; neither the public definition nor the private resolved plan
needs a node-and-edge model.

This is a research checkpoint. It does not commit a public schema or change
runtime behavior.

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
  enabled integration references and tool bindings on individual agents so a
  configured integration does not automatically affect every call or expose
  every operation to every agent.
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
drive the profile binding, credential precedence, discovery, and result
normalization decisions below.

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
agent, or a named set of focused agents with one initial entrypoint and explicit,
allowlisted participant handoffs. Graphs appear as a separate structured-flow
product or a code-level orchestration mechanism when deterministic sequencing
is actually needed.

The public `CallDefinition` should therefore be participant-first without
assuming an agent must own the room for its entire lifetime:

- one `entrypoint` naming a definition-local participant;
- shared capability-profile defaults;
- a map of every participant the room is allowed to materialize;
- agent participants with prompts, first-message behavior, capability overrides,
  selected tools, and direct transfer allowlists;
- human participants with any participant-specific, non-secret connection
  intent;
- typed invocation inputs and typed room context; and
- bounded call policies and references to artifact/event policies.

The agent name in the definition is a stable logical role, not a PID, runtime
participant ID, or activation ID. Entering an agent creates a fresh activation
that owns conversational control. Re-entering the same agent may reuse its
private history according to policy, but stale work from an earlier activation
must still be rejected.

The entrypoint resolves within the definition's `participants` map. Its
participant definition determines whether the initial participant is human or
agent and how it is materialized. This permits an initially human-only call and
a definition with no agent participants.

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
plan needs an entrypoint, named participant specs, and resolved tool bindings,
while the room tracks an optional active agent participant and its fresh
activation ID:

```text
admit and activate the entrypoint's agent participant
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
tools, typed context, and call legs. Provider requests and tool execution remain
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

### Room context is typed, sectioned, and permissioned

The reviewed systems distinguish model history, typed session data, and context
selected for a transfer. Vxpipe should make the typed shared data an explicit
room-owned `room_context`, separate from every agent's private model history and
scratch state. It remains available while humans continue the call after the
last agent participant leaves.

The definition declares named top-level context sections. Each section is an
object with a schema and optional safe default. Invocation input may initialize
fields only through definition-declared bindings. Typed facts should not be
re-extracted from a transcript when an authoritative invocation value or tool
result already exists.

Each agent declares `context_permissions` keyed by section name. Permissions are
a set containing `read`, `write`, both, or neither:

- `read` includes the section in the model-visible room-context projection;
- `write` permits a validated room-context update request for that section;
- `write` does not imply `read`; and
- an omitted section is neither visible nor writable.

Start with top-level section permissions rather than dot notation, wildcards,
or array indexing. This gives each section a clear schema, ownership, revision,
audit stream, and atomic update boundary. If field-level grants become necessary,
use unambiguous JSON Pointer paths in a later dated schema rather than inventing
dot-path escaping rules.

An agent never mutates the map directly. Read or write grants cause the engine to
offer platform-owned context tools constrained to that agent's granted sections.
The room authority validates the current room incarnation, agent participant,
agent activation, section permission, expected section revision, patch bounds,
and resulting section schema before applying an update and emitting its event.
MCP results do not update room context implicitly; an explicit tool-result
mapping or authorized context update must request it.

The room authority is the sole runtime owner of the mutable values and revisions.
It already serializes room mutations and owns the pinned resolved call plan, so a
context update can be ordered with transfers, activation changes, and room end.
The context behavior should live in a focused pure `RoomContext` data/reducer
module, but its state must not be copied into another independently authoritative
GenServer. Small JSON-compatible values live in the room heap; large documents,
media, and tool artifacts live elsewhere and appear in context only as bounded
references.

Provider and tool work remains outside the room authority. A platform context
tool runs in the supervised model/tool request process and makes a bounded
`GenServer.call` back to the room authority. The engine-owned tool context carries
the trusted room, incarnation, agent participant, activation, command,
correlation, and tool-call identities. The model supplies only the requested
read or mutation. The authority authorizes that trusted identity and never
accepts participant or permission claims from model arguments.

This call direction is safe only while the authority does not synchronously wait
for provider or tool completion. It may acknowledge dispatch to the capability
worker, but the worker owns the external request lifecycle. That worker may then
call the authority for a short state operation. Every call is bounded and returns
a typed unavailable/timeout result to the model rather than waiting indefinitely.

At the start of an agent turn, the room creates an immutable projection for the
current activation. Readable sections include their value and revision. A
write-only section exposes its revision but not its value, so the agent can make
an optimistic update without gaining read access. Model inference inserts this
projection as a transient engine-owned context message; it is regenerated for
each turn and is not appended to private conversation history. A read tool can
refresh the projection during a multi-round tool loop if another authorized
actor has changed it.

A participant-transfer packet is an immutable projection of allowed room-context
sections plus the selected spoken-history policy. It names the concrete source
and destination participant identities and kinds, reason, causation, and
visibility. When an agent participant is the destination, its projection is
further constrained by that agent definition's context permissions. It is an
event/result, not a second mutable context bag. Client and human-participant
access to room context uses separate authenticated permissions rather than
inheriting an agent definition's grants.

### Working room-context schema candidate

There is now enough agreement to implement a dated schema. The next candidate is
`20260906.02`; it supersedes the earlier `20260906.01` discussion shape by using
one participant catalog and direct participant refs for entry and transfer. The
room-context portion is:

```json
{
  "schema_version": "20260906.02",
  "entrypoint": "reception",
  "input_schema": {
    "type": "object",
    "properties": {
      "customer_id": {"type": "string", "minLength": 1}
    },
    "required": ["customer_id"],
    "additionalProperties": false
  },
  "room_context": {
    "sections": {
      "customer": {
        "schema": {
          "type": "object",
          "properties": {
            "id": {"type": "string"}
          },
          "additionalProperties": false
        },
        "default": {}
      },
      "intake": {
        "schema": {
          "type": "object",
          "properties": {
            "summary": {"type": "string"},
            "topic": {"type": "string"}
          },
          "additionalProperties": false
        },
        "default": {}
      }
    },
    "initialization": [
      {
        "input": "/customer_id",
        "section": "customer",
        "path": "/id"
      }
    ]
  },
  "participants": {
    "reception": {
      "type": "agent",
      "context_permissions": {
        "customer": ["read"],
        "intake": ["read", "write"]
      },
      "transfers": ["billing", "human-support-agent"]
    },
    "billing": {
      "type": "agent",
      "description": "Handles billing questions.",
      "context_permissions": {
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

- `room_context.sections` defines the only legal top-level sections and the
  shape of each section. The initial version requires every section root to be
  an object.
- A section `default` is definition data and must validate against its schema.
  An omitted default starts as an empty object only when that object is valid.
- `room_context.initialization` is a closed list of JSON Pointer bindings from
  validated invocation input to a field in a declared section. It is not an
  expression language or arbitrary deep merge. The compiler validates both
  endpoints, and the complete initialized section must pass its schema.
- `context_permissions` is present only on agent participants and refers only
  to declared top-level sections. It does not control client or human access.
- Application configuration supplies hard limits for total context bytes,
  section bytes, update bytes, and operations per update. A definition may
  lower those limits but cannot raise them.

The `schema` objects use a closed Vxpipe-supported subset of JSON Schema-shaped
keywords. The initial subset should cover object, string, boolean, integer,
number, arrays as replaceable values, properties, required fields, enums,
bounded strings/arrays/numbers, and `additionalProperties: false`. The dated
Vxpipe schema defines exactly which keywords work; accepting this shape must not
claim support for arbitrary JSON Schema vocabularies, references, or executable
formats.

Each runtime section has independent revision state:

```text
RoomContext
├── global_revision
└── sections
    ├── customer -> value + revision
    └── intake   -> value + revision
```

The global revision supports snapshots and event correlation. The section
revision is the optimistic-concurrency token used by tools. Independent sections
can change without causing unrelated updates to conflict.

### Platform context tool contracts

The compiler adds `read_room_context` when an active agent has at least one read
grant and `update_room_context` when it has at least one write grant. Authors do
not list these platform tools in the agent's general `tools` map. The generated
tool schemas contain closed section enums derived from that agent's grants.

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

The authority intersects the requested sections with the trusted activation's
read grants even though the model-facing enum is already constrained. An empty,
unknown, unreadable, stale, or oversized request returns a typed tool error and
no values.

An update modifies exactly one top-level section atomically:

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

Paths are RFC 6901 JSON Pointers relative to the selected section. The initial
mutation language supports only bounded `set` and `remove` operations on object
fields; arrays are replaced as values rather than edited by index. An empty path
may replace the complete section object. This is deliberately not full JSON
Patch. The authority applies all changes to a copy, validates the complete
result, then either commits all of them or none of them.

A successful result always returns the section name, new section revision, and
new global revision. It includes the resulting value only when the same agent
also has `read` permission. A revision conflict returns the current revision but
never leaks a write-only value. Invalid paths, oversized changes, a failed
resulting schema, stale activation, wrong incarnation, and missing permission do
not change the context or revisions.

The public `RoomContextUpdated` event contains section name, changed paths,
revisions, source participant and activation, tool-call/correlation identity,
and outcome. It does not broadcast the new value. Durable recovery may persist
an encrypted/private state event or checkpoint through a separate sink, while
client projections remain permissioned and redacted.

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

A transfer declares only its target and transfer behavior, such as warm versus
cold handoff, source disposition, context projection, and presentation. The
room authority runs it in prepare and commit phases. During prepare, it resolves
the destination and its presence policy outside the active media topology,
while the source participant and its current capabilities may remain active for
announcements and data collection. It then computes the proposed post-transfer
participant set, enforces its denials, and makes the remaining positively
required capabilities ready. Only then does the room atomically admit or
activate the destination, change control/routing, apply the source disposition,
and emit `transfer.completed`.

The initial `CallDefinition` therefore has no generic `on_success` field. Host
code can observe `transfer.completed`, and a later deterministic workflow can
model an explicit next action if a real use case requires one. Neither is part
of the transfer's safety-critical commit transaction.

When a denial is a privacy boundary, enforcing it is a commit barrier rather
than best-effort cleanup. The room makes the capability ineligible to start or
receive new frames, immediately cancels queued/in-flight work, and waits for a
bounded stop acknowledgement before completing or unhiding the human-only
bridge. Failed or timed-out enforcement follows the transfer's failure policy
without changing control or routing. Graceful draining is inappropriate because
it could publish buffered transcription or speech after the boundary.

Generation and activation checks reject late transcription, inference, or
speech output from capabilities that belonged to the earlier state. Stopping
speech-to-text or text-to-speech means closing the provider work and preventing
new input, not merely hiding client events.

This allows a call to begin with an agent participant, admit a human participant
during a warm transfer, detach the source agent participant after the bridge
succeeds, and continue with two human participants. When the restrictive
participant later leaves, reconciliation may restart capabilities required by
the remaining topology without a reverse transfer having to enumerate them.

Recording, analytics, and export are separate capabilities. Stopping speech
recognition and synthesis does not claim to stop those other data paths, so a
private or regulated segment must name every capability its policy requires the
room to stop.

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
may create the call and room; joining a pre-existing room will require a future
explicit admission mode and an unambiguous room-correlation mechanism. A fixed
number can live in the definition. A number that genuinely varies per call may
instead bind to a declared, validated invocation input.

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
  including the integration/tool bindings enabled independently for each agent.
  It does not own MCP endpoints or credentials.
- A call invocation owns caller/destination identity, definition selection,
  permitted runtime variables, transport attachment, and idempotency. It does
  not override the definition's entrypoint and carries no MCP authentication.
- A resolved call plan pins all references, defaults, adapter capabilities,
  selected integration/catalog revisions, discovered tool schemas, policy
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
CallDefinition.Entrypoint
CallDefinition.Participant
CallDefinition.AgentParticipant
CallDefinition.HumanParticipant
CallDefinition.ConnectionIntent
CallDefinition.CapabilitySelection
CallDefinition.RoomContext
CallDefinition.ContextSection
CallDefinition.ContextPermissions
CallDefinition.Policy
CallDefinition.AgentIntegration
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
- an `entrypoint` ref into the participant catalog;
- shared capability-profile defaults;
- named inline `participants`, each typed as human or agent;
- typed invocation-input and room-context schemas;
- shared call policies for turns, interruption, limits, failure, and ending; and
- artifact/event policy references.

Each agent participant should contain:

- a stable definition-local name;
- an inline prompt or versioned prompt-profile reference;
- optional capability-profile overrides;
- first-message behavior;
- MCP integrations enabled for this agent and stable agent-local bindings for
  the selected remote tools;
- engine-owned non-transfer tool grants;
- a direct list of allowed destination participant refs;
- room-context permissions by top-level section;
- input, output, and action-guardrail policy references;
- optional limits stricter than the call defaults.

Each human participant may contain a provider-neutral connection intent, such as
a configured service ref, `dial` or `receive` mode, number or declared input
binding, and admission behavior. It contains no credentials or provider command
payloads.

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
- Each **agent** in the call definition independently enables configured
  integrations and binds a bounded selection of their tools to agent-local
  names.
- The **call invocation** carries neither MCP configuration nor credentials.

Use these terms consistently:

- **configured**: an integration record exists at application or tenant scope;
- **enabled**: an agent selects that configured integration and its allowed
  remote tools;
- **resolved**: compiling the call pins each agent's bindings plus the selected
  scope, integration/catalog revision, and private credential lease;
- **active**: the agent activation currently owns conversational control, so its
  enabled tools may be included in model requests; and
- **invoked**: the active agent's model selected an enabled tool and the executor
  issued `tools/call`.

This creates four narrowing layers before invocation:

```text
configured application or authenticated-tenant integration
  -> agent-enabled integration
  -> agent-local tool bindings
  -> currently active agent activation
```

The effective model tool surface is their intersection. Configuring a remote MCP
integration does not enable it for any agent, and enabling it on one agent does
not enable it on another. For example, a research agent may receive a
document-search tool while a transaction agent in the same call receives a
Zapier action tool. An inactive agent's tools are absent from the active model
context.

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

Each agent binds stable agent-local tool names to catalog entries:

```json
{
  "agents": {
    "timekeeper": {
      "integrations": {
        "utilities": {
          "type": "remote_mcp",
          "ref": "utilities",
          "tools": {
            "current_time": {
              "remote_name": "get_current_time"
            }
          }
        }
      }
    }
  }
}
```

The `timekeeper.integrations.utilities` entry is the enablement decision for that
agent; its `ref` selects the configured ID through tenant-first resolution. The
nested `tools.current_time` entry is the agent-local binding. The model sees
`current_time`, not an endpoint, credential, or unfiltered remote catalog.

At call resolution, the compiler verifies each agent's enabled integrations and
tool bindings against the current integration catalog and pins the normalized
definitions plus catalog revisions in that agent's resolved plan. Multiple
agents may resolve the same configured integration; the runtime may deduplicate
its transport, catalog, and credential lease internally, but the enabled tool
sets remain independent. Configured integrations referenced by no agent create
no call binding or credential lease. The first version fails call creation when
a required enabled integration or tool cannot be resolved; optional/degraded
integrations can be designed later.

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

A transfer away from an agent participant changes the effective tool surface.
Before deactivating the source activation, its in-flight tool calls must be
settled or cancelled. After the transition, source-agent bindings cannot accept
new calls. An agent-participant destination receives only its own activation's
bindings; a human-participant destination receives no model tool surface. Tool
results and events carry participant and activation identity so a late result
from the previous agent participant is rejected even when both agent
participants use the same configured integration.

The public engine boundary should accept a definition (or immutable definition
reference) plus an invocation. The current `CreateRoom` command remains a lower
level engine command and should eventually receive only a resolved-plan identity
or typed plan, never decoded call JSON or credentials.

### Initial agent-transfer context policies

Start with a closed set:

- `fresh`: no prior model history;
- `all_spoken`: confirmed user and played assistant utterances only;
- `last_n_spoken`: a bounded window of confirmed spoken turns; and
- `selected`: no history, only allowlisted typed fields plus an explicit reason.

Do not include model system messages, private scratch state, hidden tool
arguments, tool credentials, or generated-but-unplayed assistant text. Add
summary generation only after it has its own deadline, failure, provenance, and
fallback semantics.

### Runtime overrides

Avoid arbitrary deep-merge overrides. `CallInvocation` may provide only fields
declared as invocation inputs by the definition. Provider selection, tool grants,
guardrails, and routing must not be silently replaced by caller-supplied maps.

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

The participant definition may carry its trusted presence policy next to its
provider-neutral connection intent. For example:

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

## Representative JSON shape

This is the working input for the first implementation checkpoint. It remains a
candidate until the constructor and compiler tests make every field precise:

```json
{
  "schema_version": "20260906.02",
  "name": "customer-support",
  "entrypoint": "reception",
  "input_schema": {
    "type": "object",
    "properties": {
      "customer_id": {"type": "string"}
    },
    "required": ["customer_id"],
    "additionalProperties": false
  },
  "defaults": {
    "capabilities": {
      "speech_to_text": "default-stt",
      "model_inference": "fast-general",
      "text_to_speech": "default-voice"
    }
  },
  "room_context": {
    "sections": {
      "customer": {
        "schema": {
          "type": "object",
          "properties": {
            "id": {"type": "string"}
          },
          "additionalProperties": false
        },
        "default": {}
      },
      "intake": {
        "schema": {
          "type": "object",
          "properties": {
            "summary": {"type": "string"},
            "topic": {"type": "string"}
          },
          "additionalProperties": false
        },
        "default": {}
      }
    },
    "initialization": [
      {
        "input": "/customer_id",
        "section": "customer",
        "path": "/id"
      }
    ]
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
      "context_permissions": {
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
      "context_permissions": {
        "customer": ["read"],
        "intake": ["read", "write"]
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

The corresponding invocation contains only call-specific identity and declared
inputs:

```json
{
  "call_definition": {
    "id": "customer-support",
    "revision": 7
  },
  "input": {
    "customer_id": "customer-456"
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
The compiler also exposes read and update context tools restricted to the
participant's declared section permissions.

Provider/profile strings are closed registry names resolved by the host. They
do not name Elixir modules. Inline prompts may later be replaced by immutable
prompt references without changing the runtime semantics. Agent-scoped tools,
knowledge, guardrails, MCP enablement, and artifact-policy references fit into
this shape without changing its basic entrypoint and transfer-tool model, but
they should be specified in separate focused checkpoints.

## Alternatives considered

### Start with a fully expressive JSON graph

Rejected for both the public definition and the initial private plan. A graph
front-loads node taxonomy, expression semantics, parallelism, joins,
compensation, graph migration, and visual-editor concerns before Vxpipe can
switch between two agents. Even a minimal `agent`/`end` graph makes the common
case less direct than an entrypoint with transfer tools and risks making the
graph rather than the room the source of truth. Named agent specs, resolved tool
bindings, and the room's active-agent-participant state are sufficient.

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
condition algebra over declared context fields (`eq`, `in`, `exists`, `all`,
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

### Treat a configured MCP integration as enabled for every agent

Rejected. Application or tenant configuration may make an integration and tool
catalog available, but only an agent enables it and binds its tools. This
keeps one agent from inheriting tools merely because another agent, call, or
tenant happens to use the same MCP server.

## Validation requirements

Compilation should reject, with path-specific errors:

- malformed, unknown, or unsupported dated schema identifiers;
- an absent or malformed entrypoint, or one naming an unknown participant;
- duplicate or invalid names;
- an unknown participant type or type-specific field on the wrong participant;
- a transfer list with an unknown, duplicate, or invalid participant ref;
- a user-authored `transfer` tool or another tool alias that collides with the
  compiler-generated platform tool;
- a human connection intent with an unknown service, mode, admission behavior,
  literal credential, or invalid input binding;
- a participant presence policy with an unknown activation condition, selector,
  or denied capability kind;
- a capability denial whose `participants` value is not a non-empty selector
  list, contains a selector type other than `all` or `agent`, or combines
  `type: all` with another selector;
- a `type: agent` selector with a missing or unknown definition-local agent ref;
- `active_agent` policy activation owned by a human participant, or an
  unauthorized room-wide or cross-participant selector;
- an activation or proposed participant topology whose positive capability
  intent includes a capability denied by an applicable policy;
- duplicate tool names within one source agent;
- tool or integration references not present in closed registries;
- duplicate agent-local tool aliases within one agent;
- an agent's enabled integration reference unavailable to the authenticated
  tenant and absent from the application catalog;
- a tool binding outside an integration enabled by that same agent;
- a remote tool absent from the selected integration catalog or excluded by its
  integration-level policy;
- any attempt by a definition or invocation to select another tenant or supply
  an endpoint or credential;
- tenant integration state escaping its tenant boundary;
- forbidden or malformed custom authentication headers;
- duplicate or invalid room-context section names and unsupported schemas;
- a room-context default that fails its section schema;
- an initialization binding with a malformed pointer, undeclared input,
  unknown section, invalid destination path, or invalid final section value;
- an agent context permission naming an unknown section or permission other
  than `read` or `write`;
- a transfer context projection containing a section the destination cannot
  read;
- invocation defaults for undeclared fields;
- policies outside bounded ranges;
- incompatible required capabilities; and
- any private runtime term or literal secret at the public boundary.

Transfer cycles are not inherently invalid: callers may legitimately return to
the entrypoint's agent participant. They require bounded transfers and session
duration. Unreachable agents should initially be a compiler warning or a lint
error, not necessarily a runtime-invalid definition.

At runtime, destination resolution must produce a concrete participant ID and a
supported `human` or `agent` kind before the room commits the transfer. A missing
identity, a kind mismatch, a destination absent from the active agent's transfer
allowlist, or a stale source participant/activation rejects the operation
without changing control or routing.

## Room-context implementation plan

### Current implementation gap

The current code confirms that this is a new domain boundary rather than a small
map addition:

- `CreateRoom` accepts a hard-coded single-agent preset, not a resolved call
  plan.
- `RoomAuthority` owns participants, connections, turns, capabilities, event
  sequencing, and the room snapshot, but stores neither the pinned plan nor room
  context.
- `Room.Snapshot` contains only room identity and lifecycle fields. It should not
  grow an unrestricted context map because snapshots are broadly observable.
- `ModelInference` constructs only a system message, private turn history, and
  the current user message. It has no activation-scoped context projection.
- `Tool.Executor` exposes a static application-configured module list.
  `Tool.Context` carries trusted room and participant identities, but not an
  agent activation identity, context grants, or an engine-private route back to
  the authority.

The existing placement of tool execution is useful: model and tool work runs in
the supervised capability request task, outside `RoomAuthority`. Context tools
can therefore call the authority for a short authorization/state transaction
without making the authority execute provider work.

### Runtime ownership and boundaries

Use one owner and several immutable views:

```text
CallDefinition + CallInvocation
  -> pure validation and compilation
  -> ResolvedCallPlan + initialized RoomContext
  -> RoomAuthority owns both for one room incarnation
       ├── creates an activation-scoped read projection for each model turn
       ├── answers authorized reads
       ├── validates and commits authorized updates
       └── orders context events with transfer and lifecycle events
```

`ResolvedCallPlan` is immutable. `RoomContext` is mutable and belongs to the room
incarnation. A focused pure module owns default construction, projection,
pointer mutation, size checks, schema validation, and revision changes;
`RoomAuthority` owns the module's state and decides whether an operation is
authorized at this moment.

Do not introduce a separate context GenServer in the first implementation. Two
independent state owners would require a transaction protocol to order context
updates with agent deactivation, transfer commit, and room end. If context later
requires sharding or an external store, `RoomAuthority` must remain the command
sequencer and commit authority even if storage is delegated.

Database or control-plane storage is not the live owner. The room is created
with the exact resolved definition revision and initialized values. Normal reads,
updates, and transfers use that in-memory snapshot. Durability later records
private context checkpoints and ordered updates so recovery can restore the same
plan revision and values without adopting a newly published definition.

### Authorization transaction

Add explicit engine commands rather than exposing the state module:

```text
ReadRoomContext
UpdateRoomContext
```

The model/tool worker builds them from an engine-private execution context. The
trusted fields include tenant, room, incarnation, source participant, agent
participant, agent activation, originating command, correlation, and tool-call
IDs. Requested sections, expected revision, and changes are the only relevant
model-supplied fields.

`RoomAuthority.update_context/2` performs one bounded `GenServer.call`. In order,
the authority verifies:

1. the command deadline and tenant/room/incarnation identity;
2. that the named agent participant is still admitted and its activation is the
   current active activation;
3. that the resolved plan grants that agent `write` on the named section;
4. that the section exists and `expected_revision` matches;
5. operation count, pointer shape, and encoded byte limits;
6. that applying every change to a copy succeeds; and
7. that the complete candidate section validates against its compiled schema.

Only after all checks pass does it replace the section, increment that section's
revision and the global revision, and emit the ordered update event. Any failure
returns a typed result and preserves both values and revisions. Reads run the
same identity and activation checks, intersect requested names with the read
grant set, and never return a partial unauthorized result.

The authority must not make a synchronous provider/tool call that can call back
into it. Dispatch to model inference may synchronously obtain a bounded
acceptance acknowledgement, but the provider request and all tool rounds execute
after that acknowledgement in the capability-owned task. Add a focused
regression test for this call direction.

### Agent model and tool integration

Compile an activation-specific effective tool surface from three sources:

- platform tools derived from the agent definition, including transfer, hangup,
  and the two context tools;
- explicitly enabled application tools; and
- explicitly enabled remote MCP bindings.

The platform context tools are engine bindings, not arbitrary Elixir modules and
not MCP calls. Their executor receives an engine-private authority target. Host
tool modules keep receiving the existing redacted identity context, and remote
MCP servers receive only their declared arguments. Neither receives a PID,
permission map, resolved plan, or context values unless an explicit authorized
binding supplies a value.

Before the first provider request in a turn, the authority supplies a frozen
activation-scoped projection. Model inference renders it as a distinct transient
engine message after the agent's system prompt and before private conversation
history. The message contains readable values and section revisions, plus
revision-only metadata for writable-but-unreadable sections. It is rebuilt on
the next turn and never becomes a historical user or assistant message.

After a successful context update, the tool result supplies the new revision and
an authorized value projection. The next model round in the same request can
reason about its update. `read_room_context` permits an explicit refresh if
another authorized command changed context during that tool loop. Transfer to a
new agent creates a fresh projection and tool surface from the destination's own
permissions; stale source-agent tool calls fail their activation check.

### Incremental red-green checkpoints

1. **Pure definition contract:** add failing tests for the smallest
   `20260906.02` participant-first definition with context sections, defaults,
   input bindings, agent permissions, and direct transfer refs. Implement typed
   constructors and path-specific errors without starting processes.
2. **Pure context state:** add failing tests for initialization, projection,
   bounded pointer changes, atomic schema rejection, independent section
   revisions, and write-only redaction. Implement the pure `RoomContext` state
   module.
3. **Room ownership:** add failing room tests proving creation pins a resolved
   plan and initialized context; a correct update commits once; wrong
   incarnation, stale activation, missing grant, revision conflict, invalid
   schema, and oversized input leave state unchanged. Add bounded read/update
   calls to `RoomAuthority` and protocol-neutral events.
4. **Platform tool surface:** add failing executor/model tests proving read and
   update tools appear only when the active agent has the matching grant, their
   section schemas are closed, trusted identity is not model-controlled, and a
   context update can call the authority without deadlock. Route engine platform
   tools separately from host modules and MCP bindings.
5. **Turn projection:** add failing model tests proving current readable context
   is present in every provider request, is not appended to private history,
   write-only values are absent, and an update result is available to the next
   model round.
6. **Transfer continuity:** with two deterministic agent participants, prove a
   value written by the source remains room-owned, the destination sees only its
   projection, and source operations arriving after deactivation are rejected.
   Prove the context remains present when the room temporarily has no active
   agent participant.
7. **Durability and external access:** only after the in-memory contract is
   stable, define private checkpoint/event persistence and separate authenticated
   host or client read/update commands. Do not reuse agent permissions for human
   or client authorization.

The first usable vertical slice should complete checkpoints 1 through 4 with one
agent and two sections. Checkpoints 5 and 6 then make context useful across real
model turns and transfers without changing its ownership model.

### Planned verification

During implementation, run focused tests from `apps/vxpipe_call_engine` after
each red and green step. The focused cases must demonstrate:

- invocation input initializes only its declared destination field;
- an agent reads only granted sections and receives section revisions;
- an agent updates an allowed field/object through the platform tool;
- a write-only agent receives no old or resulting section value;
- an unknown section, unauthorized section, stale activation, wrong incarnation,
  bad pointer, revision conflict, invalid resulting schema, or size violation
  performs no mutation and emits no success event;
- two valid changes in one request commit atomically with one section revision;
- interruption or transfer invalidates late tool work; and
- room snapshots and public events do not expose context values.

After each coherent code checkpoint, run the umbrella completion checks:

```shell
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix deps.unlock --check-unused
```

Once the gateway accepts call definitions, add a manual sample using the working
JSON: start a room with `customer_id`, confirm the first agent can read the
initialized `customer.id`, ask it to store an `intake` summary, reconnect or
advance a turn, and confirm the same room returns the saved value. A later
two-agent sample should transfer to `billing`, confirm `billing` reads the same
allowed data, and confirm it cannot update `intake` when its definition has only
`read`.

## Observable runtime contracts needed

The first multi-agent slice needs protocol-neutral events for:

- call plan resolved;
- agent participant admitted and ready;
- agent participant activated and deactivated;
- participant transfer requested, accepted, completed, rejected, failed, and
  cancelled, including source and destination participant IDs and kinds;
- participant capability denial applied or removed, including policy-owner and
  matched participant IDs, and capability reconciliation requested, enforced,
  acknowledged, timed out, or failed;
- context packet created and delivered, with values redacted by visibility;
- room-context section initialized, updated, or rejected, including section
  revision and authorized agent activation;
- tool invocation lifecycle;
- routing changed; and
- call ended with a typed reason.

Only one agent participant may own generated conversational output for a
connection/lane at a time. Inactive agent participants must not consume turns or
emit user-visible output. They also must not advertise or invoke their MCP
tools. A transition cancels or settles the source activation's outstanding tool
work before enabling an agent-participant destination's tool surface.

Late results from a previously active agent participant must be rejected by
room incarnation, participant, turn, and activation identity.

## Suggested red-green checkpoints

1. **Definition and invocation data:** red tests for a minimal one-agent
   participant catalog, entrypoint ref, dated schema validation, shared
   capability defaults, agent overrides, input validation, and a credential-free
   invocation. Implement immutable structs and pure path-specific validation
   only.
2. **Basic plan resolution:** use fake closed capability-profile registries to
   prove defaults and overrides resolve into a self-contained, secret-free
   `ResolvedCallPlan`; unused profiles leave no runtime binding.
3. **Room-context contract:** test typed top-level sections, per-agent read/write
   grants, model-visible read projection, authorized writes, schema rejection,
   section revisions, and absence of ungranted sections.
4. **Participant and transfer data:** test human and agent participant
   definitions, connection intent, missing and duplicate transfer refs,
   absent/empty transfers producing no tool, non-empty transfers producing one
   closed destination choice set, participant kinds, presence-policy denial
   selectors, transfer cycles, unreachable-participant linting, and path-specific
   errors.
5. **Active-agent-participant reducer:** test activation, agent-to-agent and
   agent-to-human participant transfer, `active_agent_participant_id: nil`,
   terminal state, stale activation, and transfer-budget behavior using
   deterministic fake participants; implement a pure reducer with one optional
   active agent participant and activation ID.
6. **Behavior-preserving agent:** prove a one-agent resolved plan produces
   the same text/audio turn behavior as the current preset path.
7. **Human-only transfer:** prove a human destination's capability denials are
   inherited without appearing on the transfer possibility. The source agent
   remains usable during prepare; admission then makes denied capabilities
   reject new frames and cancel queued work, waits for stop acknowledgement, and
   detaches the source only when the room can safely continue with human
   participants and no active agent participant. Detaching the restrictive
   participant reconciles the remaining topology back to its normal enabled
   capabilities without a transfer-specific restart list.
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
   the existing room/RTVI lifecycle, and prove interruption or transfer away
   from the agent participant cancels the remote request. Do not add stdio or an
   MCP server endpoint.
11. **Agent-to-agent participant transfer:** use two deterministic agent
   participants and one compiler-derived transfer tool to prove only the active
   agent participant receives turns, only its declared destination refs are
   accepted, the destination's required capabilities are ready before commit,
   and stale output is rejected.
12. **Scoped transition context:** prove allowed spoken history and typed fields
   reach the destination while hidden fields, private tool data, credentials,
   and unplayed text do not.
13. **Later workflow surface:** add deterministic `action`, human transfer,
    `wait`, and `branch` behavior only alongside its first concrete use. Do not
    assume a graph, subgraph, parallel-branch, join, or race model.

## Decision for the next checkpoint

Proceed first with typed `CallDefinition`, `CallInvocation`, and
`ResolvedCallPlan` contracts without MCP fields in the first proof. The smallest
proof is an inline one-agent participant catalog using schema `"20260906.02"`, a
definition-local `entrypoint` ref, shared capability-profile defaults, declared
invocation inputs, typed room-context sections and initialization bindings,
per-agent section permissions, and bounded limits becoming a self-contained
immutable plan. Route the existing single-agent behavior through that plan
before adding participant transfer or integration resolution.

Remote MCP integrations still live in application or tenant catalogs, where
they are **configured**. Individual agents explicitly **enable** integrations
and bind selected tools to agent-local names. MCP endpoints and credentials are
neither definition nor invocation data. A tenant integration atomically takes
precedence over an application-wide integration with the same stable ID; neither
catalog enables it for any agent automatically. Do not begin an MCP transport
implementation until the general call-definition boundary exists.

Use the participant-definition public input with one entrypoint and
agent-scoped tools. The private plan contains resolved participant specs,
connection intents, transfer allowlists, and tool bindings; it does not contain
generic nodes or edges. The room directly owns the pinned plan, participant
routing, and the optional active agent participant, and a running room may have
no agent participant. Platform tools include at least `hangup`, `transfer`, and
the permission-constrained room context read and update operations. A participant
transfer does not enumerate capability changes; the room reconciles the
proposed topology by filtering its normal capability intent through each
participant's presence-policy denials before commit. Do not start with Lua,
arbitrary executable hooks, natural-language condition evaluation, or a broad
workflow interpreter.

## Verification evidence

- Reviewed existing Vxpipe architecture, product intent, current create-room
  command, and prior runtime-extraction research.
- Reviewed the complete local comparative research corpus.
- Rechecked current first-party documentation for stored versus inline
  definitions, draft/published versions, multi-agent member composition,
  graph/node flows, tool-triggered handoffs, context strategies, typed tasks,
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
  available infrastructure; only an agent enables it and binds its selected
  tools. Other agents in the same call do not inherit that surface.
- Refined the authoring contract after review: schema identifiers use the
  date-based `YYYYMMDD.NN` format; the current proposal is `"20260906.02"`.
  `entrypoint` is a definition-local participant ref, participant-control
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
- Added room-owned typed context sections with per-agent `read`/`write` grants.
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
  snapshot, model-inference loop, and tool executor before planning context.
  Selected `RoomAuthority` as the sole owner and sequencer of bounded mutable
  room-context values, with a pure `RoomContext` module owning validation and
  revision behavior. Context tools run outside the authority and use a bounded
  `GenServer.call` for the short authorization and atomic mutation transaction.
- Specified a working `20260906.02` context shape with section schemas, explicit
  invocation-input bindings, per-agent section permissions, independent
  revisions, activation-scoped projections, and compiler-generated read/update
  tools. The plan includes focused red-green checkpoints and manual acceptance
  steps; no runtime implementation was performed in this checkpoint.
- Reviewed the official MCP `2026-07-28` tool specification, Streamable HTTP
  transport, and generated schema:
  - <https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2026-07-28/server/tools.mdx>
  - <https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2026-07-28/basic/transports/streamable-http.mdx>
  - <https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/schema/2026-07-28/schema.json>
- No implementation or test commands were run because this checkpoint changes
  research documentation only.
