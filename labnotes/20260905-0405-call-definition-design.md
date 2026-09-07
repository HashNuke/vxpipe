# Call definition design

Research date: 2026-09-05 UTC
Last updated: 2026-09-07 UTC

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

The [design gap review](#design-gap-review--pending-approval) records questions
and possible solutions. G1's unified agent `tools` map and G2's tenant-scoped web
admission routes, direct initial context, API-key authentication with one-way
hash storage, single-use tokens with existing-call recovery and no automatic
call-record expiry, prepared token-join or direct-backend connection, explicit
entry participants/startup, and one participant per definition key per call are
approved and documented below.
G2's remaining admission details and the other suggestions remain pending user
review. Approval of documentation does not authorize runtime implementation.

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
- typed room-context schemas and matching per-call initial values; and
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

1. At live startup, prepare/admit the caller and receiver according to their
   connection intents. Merely storing a prepared call and issuing a join token
   does not start the room or its participants.
   An agent receiver starts interacting when the required connection and
   capabilities are ready.
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

An authorized reconnect resumes the existing participant. Where agent re-entry
is permitted, it uses the bound participant with a fresh activation, not a new
instance of its definition. A disconnect or transfer does not make the key
available for a different person to take over. Reconnect eligibility, deadlines,
and transport replacement details remain lifecycle work; knowing a definition
key is not proof of permission to resume its participant.

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
object with a schema and optional safe default. An authorized invocation supplies
initial values directly in that section structure; no separate input schema or
input-to-context mapping is required. Typed facts should not be
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
  "entry_caller": "caller",
  "entry_receiver": "reception",
  "room_context": {
    "sections": {
      "customer": {
        "schema": {
          "type": "object",
          "properties": {
            "id": {"type": "string", "minLength": 1}
          },
          "required": ["id"],
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
        },
        "default": {}
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
- `CallInvocation.initial_context` supplies values by declared section name,
  matching these schemas directly. It replaces the earlier `input_schema` and
  `room_context.initialization` mapping. For example, the caller supplies
  `customer: {id: "customer-456"}`, not a separate `customer_id` input to map.
- A section `default` is definition data. Required values can instead be supplied
  at admission, as with `customer.id` above; the complete initialized context
  must validate before room/provider startup. The interaction between partial
  defaults and partial supplied sections remains a G3 review item, not an
  approved deep-merge rule. This example supplies the complete `customer` section
  and uses the complete empty default for `intake`.
- Admission initializes context independently of agent write grants. Both
  agents can read `customer`, but neither can change it through context tools.
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
may create the call and room; joining a pre-existing telephony room still needs
an explicit admission mode and an unambiguous provider-leg correlation mechanism.
The approved web start/join routes are specified separately below. A fixed
number can live in the definition. Selecting a number that genuinely varies per
call remains a G2 personalization question; the direct initial-context decision
does not introduce automatic context-to-dial bindings.

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
  schema-validated initial context, transport attachment, and idempotency. It does
  not override either entry ref and carries no MCP authentication.
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
CallDefinition.Participant
CallDefinition.AgentParticipant
CallDefinition.HumanParticipant
CallDefinition.ConnectionIntent
CallDefinition.CapabilitySelection
CallDefinition.RoomContext
CallDefinition.ContextSection
CallDefinition.ContextPermissions
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
- typed room-context schemas for initial values and subsequent mutations;
- shared call policies for turns, interruption, limits, failure, and ending; and
- artifact/event policy references.

Each agent participant should contain:

- a stable definition-local name;
- an inline prompt or versioned prompt-profile reference;
- optional capability-profile overrides;
- first-message behavior;
- one `tools` map containing stable agent-local bindings for selected remote MCP
  tools, built-in non-transfer tools, and registered host tools;
- a direct list of allowed destination participant refs;
- room-context permissions by top-level section;
- input, output, and action-guardrail policy references;
- optional limits stricter than the call defaults.

Each human participant may contain a provider-neutral connection intent, such as
a configured service ref, `dial` or `receive` mode, a fixed number, and admission
behavior. Dynamic destination selection remains pending G2 review. The intent
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

Transfer remains derived from `transfers`, and context tools remain derived from
context permissions; neither needs a duplicate entry in `tools`. Tool aliases
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

Avoid arbitrary deep-merge overrides. `CallInvocation.initial_context` may
provide only sections and fields permitted by the definition's context schemas.
Provider selection, tool grants, guardrails, and routing must not be silently
replaced by caller-supplied maps. Initial context is data, not a definition patch.

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
  context, and stores the preparation with a pinned revision. It returns a join
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
  changing the pinned definition/context. An ended call or active-connection
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

The routing decision is supplemented by the approved initial-context and
authentication contract below and the approved two-entry startup contract above.
Personalization and the remaining security/lifecycle details are still pending
G2 review. No endpoint or ID generator was implemented here.

### Initial context and API-key admission — approved G2 decisions

The integrating application supplies initial room-context values directly in
the structure declared by the call definition. There is no second input schema
or input-to-context binding layer. The reusable definition declares schemas,
optional defaults, and agent permissions; the call invocation supplies the
per-call values. The authorized backend may prefill any schema-declared section,
including one that no agent can write. Supplying initial context does not edit
the stored definition or grant an agent write access.

For example, a shopping application starts support for order `ORD-1042`. The
definition declares an `order` section containing `id`. Its backend authorizes
the customer's access to that order and supplies
`initial_context: {order: {id: "ORD-1042"}}`. Reception and billing may both have
`order: ["read"]`, while no agent has `write`. Admission initializes the section
once, and transfers preserve it without allowing an agent to rewrite the order
ID. The representative JSON below uses the same mechanism for `customer.id`.

The integrating backend now needs one long-lived credential: a gateway-issued
API key, sent as `Authorization: Bearer <api_key>` over HTTPS/WSS. Both supported
flows use unsigned application payloads. This replaces the earlier separate
client-ID/client-secret pair, HMAC signing, and browser forwarding of a signed
initial-context envelope. Short-lived browser join tokens are delegated access,
not another long-lived integration credential.

**Flow 1 — backend preparation, browser token join:**

1. The backend authorizes its business request, then POSTs initial context to
   the tenant/participant preparation route with its API key. That HTTP endpoint
   grants no cross-origin browser access.
2. Vxpipe verifies the key's tenant and permissions, validates context, pins the
   definition revision and initial values, and stores a prepared call with a
   stable `call_id`. It returns an opaque, short-lived, single-use join token
   scoped to that call and its assigned participant. The token contains no
   readable context.
3. The backend passes only that token to the frontend. The browser joins the
   previously prepared call; it cannot replace the stored context, definition,
   tenant, or participant by adding new values to the join request.
4. Accepted admission atomically consumes the token before starting the room,
   not when the browser receives confirmation. Joining activates the prepared
   call's room once and obtains the transport session. Conversation waits for
   transport/capability readiness. The token is not authority to inspect private
   context, and the browser receives no full preparation snapshot. Event,
   tool-result, and speech disclosure policies
   must still protect sensitive context during the call.

Prepared-call storage and live room startup are separate stages. A prepared call
is just a database record with its pinned definition and initial context;
issuing a token does not start the call process tree, connect providers, or dial
the receiver. The token expires, but the unstarted record has no separate
automatic admission deadline. An authorized backend can request a fresh token
for that same eligible record. The definition and values are pinned at
preparation, not reselected from a newer deployment at join. Token claim and
activation must coordinate idempotently without holding a database transaction
across room or provider startup. The single-use and backend-mediated recovery
contract below is approved; exact token TTL settings and crash-reconciliation
mechanics remain open.
This waiting-for-browser lifecycle does not impose a browser token on inbound
telephony or independently requested outbound dialing.

**Flow 2 — direct backend WebSocket:**

1. A non-browser backend opens WSS with its API key in the authorization header.
   Authenticate before upgrading; an unsigned context message is not a way to
   create an unauthenticated call.
2. After the upgrade, the backend sends initial context in the first application
   message. Validate and bound that message before admitting the call or
   starting the room/providers. An upgraded socket alone is not a live call.
3. On successful initialization, the backend participates through that
   connection. No browser join token is needed for this direct path.

The upgrade uses a GET handshake; it is not a JSON POST that becomes a socket.
WebSockets do not use ordinary HTTP CORS permission checks. Browser joins need
an allowed-`Origin` check plus token authentication, while backend connections
need API-key authentication regardless of origin. No CORS grant is not an
authentication boundary. See [WebSocket handshakes](https://www.rfc-editor.org/rfc/rfc6455.html#section-4.1)
and [origin checks](https://www.rfc-editor.org/rfc/rfc6455.html#section-10.2).

The standard browser WebSocket constructor cannot set arbitrary authorization
headers. A browser-compatible token exchange, such as a bounded first
application message, must authenticate before any room access; its exact wire
shape is still pending. Do not put API keys, initial context, or bearer tokens
in query strings or logs. HTTP browser join/signaling endpoints can grant CORS
to configured origins separately. This keeps the preparation/token model usable
with the existing WebRTC transport rather than requiring its replacement with
WebSockets. See the [browser WebSocket interface](https://websockets.spec.whatwg.org/#the-websocket-interface).

**Credential ownership and storage:**

- The gateway generates cryptographically random API keys through an authorized
  management operation and returns each key once. Keys stay on the integrating
  backend. A tenant may have several independently managed keys; tenant and
  permission metadata remain ordinary stored records. No separate client ID is
  required in integration requests.
- Gateway authentication uses a credential-store port; the persistence adapter
  owns database details. Calls owns preparation/activation workflows and the
  engine receives only the trusted principal, plan, and context. No API key or
  join token becomes room context or a public event. These credentials remain
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
the business context. A browser join token grants only its assigned admission
scope; possession is not proof of a person's identity. Treat it as a secret,
short-lived bearer credential. [Bearer-token security](https://www.rfc-editor.org/rfc/rfc6750.html#section-5).
Provider webhook authentication remains a separate adapter concern.

**Still pending:** administrator bootstrap, permission granularity,
rotation/revocation, token lifetime settings, separate record-retention and
storage-limit policies, precise transport messages/timeouts and WebSocket routes,
reconnect eligibility/deadlines, and detailed retry/crash reconciliation. Single-use claim
and existing-call token issuance are approved below. HMAC algorithm selection,
payload canonicalization, and signature-envelope fields are no longer
implementation questions. Partial/default context assembly (G3), telephony
initial-context sourcing, and personalization
also remain open. No credentials, configuration, dependencies, database, or
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
3. After acceptance or token expiry, recovery goes through the integrating
   backend. It rechecks the user's authorization and uses its API key to request
   a fresh token from the existing-call `join-tokens` route. Neither a call ID
   nor possession of the old token authorizes recovery by itself. The API key
   remains on the backend; only the fresh scoped token reaches the frontend.
4. Gateway authentication and the Calls workflow resolve that same call record
   and participant. Issuance requires an eligible state: reconcile pending
   admission before retrying, reject ended calls and unauthorized/revoked access,
   and never silently take over an active connection. Recheck eligibility when
   consuming the new token so intervening joins or call termination cannot
   bypass the same rules. This preserves the singleton participant binding.
5. An eligible **prepared call** still has no live room: issuing a token does
   not start one, and accepted joining activates it once. An eligible reconnect
   to a **running call** attaches to the existing participant in its existing
   room, retaining its identity, current context, and pinned plan. It does not
   reinitialize context from the original values or create a replacement call.
6. A token's expiry only prevents a future claim. Once admission was accepted,
   that token expiring does not hang up the established call. Later reconnect
   still needs a fresh token and whatever reconnect eligibility is approved.
7. An unstarted call record does not automatically expire because its token
   expired or because time passed since preparation. Without a valid token the
   browser cannot join, but the record remains eligible for backend-authorized
   fresh-token issuance subject to the same authorization/lifecycle checks.
   Reissuance preserves its pinned definition and initial context; it does not
   require another call record. Data retention and cleanup are separate policies,
   not an automatic deletion or invalidation triggered by token expiry.

Gateway owns authentication and token handling; Calls owns the existing-call
workflow and uses persistence ports for admission/claim state. No live database
lookup is added to ordinary room turns or transfers. The existing browser
WebRTC path and future WebSocket path share these admission rules; issuing a
token is distinct from negotiating either transport.

This resolves single-use consumption, before/after-acceptance retry behavior,
and the backend-authorized existing-call token endpoint. Token expiry suffices
for this admission contract; there is no additional unstarted-call TTL. It does
not yet settle token TTL defaults/configuration, record retention/cleanup,
reconnect grace periods, status/error response shapes, repeated token-issuance
requests or superseding other unused tokens, or the precise pending-admission
crash reconciler. No runtime endpoint or authentication code is implemented here.

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
  "room_context": {
    "sections": {
      "customer": {
        "schema": {
          "type": "object",
          "properties": {
            "id": {"type": "string", "minLength": 1}
          },
          "required": ["id"],
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
        },
        "default": {}
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
carries initial context matching its section schemas. It is not the
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
  "initial_context": {
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
The compiler also exposes read and update context tools restricted to the
participant's declared section permissions.

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

### Require a second input schema and mappings into room context

Rejected for call-start context. The integrating backend can supply values in
the definition's context-section shape directly. A separate `input_schema` and
JSON Pointer initialization map duplicate that contract without helping the
order-ID example. JSON Pointers remain useful for authorized context mutations;
removing initialization bindings does not remove the context update tool.

### Keep separate client-ID/HMAC authentication for browser-forwarded payloads

Superseded. The backend sends initial context directly under API-key
authentication, either preparing a call for token-based browser join or
initializing its own authenticated connection. This removes signature generation,
canonicalization, and signed-envelope verification from the integration contract.
It does not remove HTTPS/WSS, tenant authorization, replay/claim protection for
join tokens, or request idempotency. API keys remain outside browser bundles,
call definitions, room context, and logs; sensitive context stays server-side
in the prepared-call flow.

### Reuse consumed join tokens or recreate the call after a lost response

Rejected. A lost acknowledgement does not undo accepted admission. Reusing the
token could grant a second connection; recreating the call would duplicate its
record, context, and potentially provider work. Recovery instead reauthorizes
through the backend and reconciles the same call/participant before issuing a
fresh token. Token expiry is not a call-duration limit, and an existing-call
token must never silently evict an active connection.

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
- an MCP tool's integration reference unavailable to the authenticated
  tenant and absent from the application catalog;
- a remote tool absent from the selected integration catalog or excluded by its
  integration-level policy;
- any attempt by a definition or invocation to select another tenant or supply
  an endpoint or credential;
- tenant integration state escaping its tenant boundary;
- forbidden or malformed custom authentication headers;
- duplicate or invalid room-context section names and unsupported schemas;
- a room-context default containing an unknown field or invalid supplied value
  (partial/default completion semantics still require G3 review);
- an agent context permission naming an unknown section or permission other
  than `read` or `write`;
- a transfer context projection containing a section the destination cannot
  read;
- initial context containing undeclared sections/fields, invalid values, or
  required values missing from the complete initialized context at admission;
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
   direct initial context, agent permissions, and direct transfer refs. Implement
   typed constructors and path-specific errors without starting processes.
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

- initial context initializes only schema-declared sections and fields;
- admission can initialize a section that agents can read but none can write;
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
JSON: start a room with `initial_context.customer.id`, confirm the first agent
can read the initialized `customer.id`, ask it to store an `intake` summary,
reconnect or advance a turn, and confirm the same room returns the saved value. A later
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
| Mutable room context | `RoomAuthority` | private section snapshots and/or ordered context updates |
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
  -> validate initial context and compile a resolved plan
  -> idempotently create the durable call admission record
  -> start the room with call ID, plan, and initialized context
  -> mark the call running or record a typed admission failure
  -> issue provider-neutral leg/media commands
```

Do not hold a database transaction open while starting OTP processes or making a
provider API call. Use unique admission/idempotency keys, short database
transactions, and explicit `admitting`, `running`, `failed`, and terminal call
states. Repeated delivery of the same provider webhook must return or advance
the same call rather than starting a second room.

An outbound call follows the same admission path except that an authenticated
API invocation selects an allowed deployment or exact revision and the resolved
plan tells the room which `dial` participant to materialize. Every call row pins
the exact definition revision, schema version, and resolved-plan digest. A
deployment change never mutates that row or its active room.

### Stable call identity is distinct from a room incarnation

Introduce a `call_id` generated at admission and carry it through engine
commands, domain events, provider operations, context updates, artifacts, and
publisher jobs. The call ID survives room-incarnation recovery. `room_id`
identifies the live collaboration/media scope, and `incarnation_id` rejects stale
work for one execution of that room. The initial implementation may enforce one
room per call, but the identifiers must not be conflated because a call can have
multiple telephony legs and a recovered room receives another incarnation.

The relational `calls` row should contain durable identity and summary state,
not every detail as one mutable JSON document. It records tenant/application,
definition revision, plan digest, direction, route/invocation identity, current
room/incarnation, lifecycle state, start/end timestamps, terminal reason, archive
status, and retention-policy identity. Provider-native call IDs belong in a
separate call-leg/provider-identity record with appropriate uniqueness and
redaction.

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
- `usage_records`: normalized billable units and cost observations linked to a
  provider operation and, when meaningful, a turn;
- `call_context_sections`: the latest privately retained section value and
  revision when context retention is enabled;
- `artifacts`: object key, kind, participant/connection/track correlation,
  timing, codec/content type, bytes, checksum, retention, and publication state;
  and
- an outbox/job table for idempotent post-call publication and retries.

`call_events` preserves ordering and future replay evidence. The other rows are
projections for efficient product queries and publication; they can be rebuilt
from retained events where the retention policy permits it. Do not put audio,
large transcripts, or a continually rewritten all-call JSON blob on the `calls`
row.

Transcript persistence is a policy independent of whether STT or TTS happens to
be enabled. Capability enablement permits realtime processing; retention decides
what may be stored and for how long. A call with text input can have a transcript
without STT, and a call may use STT/TTS while policy forbids retaining text or
audio.

When transcript retention is enabled, keep source facts distinct:

- committed human text input stores the submitted text and `text` provenance;
- human audio stores the provider-final committed transcript and provider/model
  identity; partial replacements are optional debug/event retention, not new
  transcript turns;
- agent output stores generated text separately from confirmed delivered/spoken
  text, including interrupted or truncated state; and
- every turn names the runtime participant, definition-local participant ref,
  and agent activation when applicable.

This follows the existing engine rule that generated assistant text and audio
confirmed as played are different facts. A final transcript must not claim that
interrupted generated text was heard. Word timing, confidence, and provenance
may be retained as a bounded sidecar when a provider supplies them; their
absence must not be replaced with invented precision.

### Usage and cost belong to provider operations, with optional turn links

A turn can incur multiple independent charges. One agent turn may require
several model requests because of tool rounds, several TTS requests because text
is segmented, and a long-lived STT stream that spans multiple human turns.
Telephony and MCP charges may be call-, leg-, or operation-scoped. Therefore a
single cost column on `call_turns` is insufficient.

Store one immutable usage record per billable provider operation. Link it to a
turn when attribution is honest, but allow a nullable turn link and retain call,
participant, activation, capability, provider-operation, and call-leg
correlation. Call and turn totals are derived projections over those records.

A normalized usage record should carry:

- provider operation ID and optional provider request ID;
- capability (`speech_to_text`, `model_inference`, `text_to_speech`, `mcp`, or
  telephony);
- configured provider and actual provider/model/voice identifiers used after
  fallback;
- measured units as typed values, such as input/output/cached/reasoning tokens,
  characters, synthesized audio duration, transcribed audio duration, connection
  duration, or request count;
- cost amount as an exact decimal representation, currency, component breakdown,
  and whether it is provider-reported, library-estimated, locally estimated, or
  later reconciled;
- pricing catalog/version or provider billing reference used for an estimate;
- started/completed timestamps and success/failure/cancellation status; and
- call, room/incarnation, participant, activation, turn, utterance, and tool-call
  correlations that actually apply.

Never use floating-point arithmetic as the billing record and never manufacture
zero usage when a provider omits metadata. Preserve raw normalized units, the
price/version used, and the estimate source so a later billing reconciliation
can replace or annotate an estimate without rewriting the original observation.

The current model provider boundary returns only text/tool calls/errors, so it
cannot carry usage. The current ReqLLM adapter classifies the final response and
discards its normalized usage even though ReqLLM exposes token and best-effort
cost data for buffered and streaming responses. A usage slice should introduce
a typed provider result plus a protocol-neutral `ProviderUsageRecorded` event
for every model request, including intermediate tool rounds. STT and TTS adapter
contracts need equivalent typed usage/finalization signals based on the unit the
provider actually bills; measured audio duration or characters may be marked as
estimates when no provider usage is available.

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
├── RoomParticipantSupervisor
├── RoomCapabilitySupervisor
│   └── RoomRecording (when enabled)
└── RoomPipelineSupervisor
    └── RoomMixer (when the topology requires mixing or monitoring)
```

`RoomAuthority` authorizes participants, subscriptions, and recording policy,
but does not process frames. `RoomMixer` owns realtime frame alignment and
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

Recording remains a separate capability and retention choice. Disabling speech
recognition or synthesis does not disable recording, and enabling either does not
authorize recording. Participant/room policy must explicitly allow the media
tap, artifact type, access scope, and retention period.

### `CallDetailsPublisher` is a final projector, not the live recorder

`CallDetailsPublisher` is a good name for the post-call boundary if its job is
narrow: after a terminal call state, read persisted call facts and finalized
artifact manifests, construct a versioned JSON document, store it in object
storage, and record its checksum/object reference. It should not own the live
transcript, usage counters, context, or audio buffers.

The versioned call-details JSON can contain:

- call identity, lifecycle, direction, route, definition revision, and plan
  digest;
- participants, connections/call legs, and agent activations;
- ordered transcript turns with speaker, provenance, interruption, and delivery
  status;
- provider operations and normalized usage/cost records, plus explicitly
  identified derived totals;
- tool and transfer summaries;
- permitted final context sections or context revision metadata according to
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
For immediate live admission, such as a verified telephony call or validated
direct-backend connection:

```text
Gateway webhook/API handler
  -> Vxpipe.Calls.admit(request)
       -> InboundRouteRepository.resolve(route_key)
       -> CallDefinitionRepository.fetch_revision(revision_id)
       -> CallEngine compile/resolve functions
       -> CallRepository.begin_admission(call, idempotency_key)
       -> CallEngine.create_room(resolved_plan)
       -> CallRepository.mark_running(call_id, room/incarnation)
  <- admitted call/session result
```

Browser preparation splits this workflow at the durable boundary: resolve and
pin the plan/context, persist the prepared call, then return the scoped join
token without creating a room. An authorized join claims that preparation and
activates the same call ID before issuing its room-bound transport session.
It does not create another call row or resolve a newer deployment. Calls owns
both phases; the persistence adapter stores preparation and claim state through
ports. Accepted admission consumes the join token atomically; recovery resolves
the same call through the backend-authenticated token-issuance route. Pending
admission must be reconciled before another attempt, not recreated. Detailed
crash/fencing mechanics remain a G2/G10 follow-up, with no database transaction
held across engine or provider startup.

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
RoomAuthority commits a state transition
  -> RoomEventDispatcher accepts the ordered event
       ├── gateway projection subscribers
       ├── call-ledger consumer -> CallLedger port -> vxpipe_persistence/Ecto
       ├── telemetry consumers
       └── authorized application subscribers
```

The dispatcher acceptance is a short in-memory operation with explicit queue
bounds. The call-ledger consumer performs database work in its own process,
batches when useful, retries idempotently by event ID, and reports lag/failure.
This keeps Ecto latency out of `RoomAuthority` while still making every committed
turn, context change, usage observation, transfer, and terminal event available
for storage.

There are therefore two different meanings of “inline”:

- A room-context tool makes an inline bounded `GenServer.call` to
  `RoomAuthority`, because the authority must authorize and atomically mutate
  live state before the tool succeeds.
- An archival database insert is not made inline by `RoomAuthority`; it follows
  the ordered event path because delaying every room command on PostgreSQL would
  couple realtime availability to database latency.

Call admission itself is durably inserted before room creation because it is
outside the room hot path and needs idempotency for webhook retries. Call events,
transcript projections, usage, and artifact metadata are normally persisted
asynchronously. If a future recovery guarantee requires a particular context or
lifecycle mutation to be journaled before acknowledgement, that command uses an
explicit durable-journal protocol and pending state rather than adding an Ecto
query to the authority callback.

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
them; `vxpipe_calls` does not compile against Ecto. The managed release includes
and starts the persistence adapter before reporting admission readiness. The
standalone JSON-configured release supplies static/in-memory implementations and
does not start a Repo.

The gateway therefore requires a call-admission implementation, not a database.
In managed mode that implementation uses `vxpipe_persistence`; in standalone
mode it uses the validated JSON catalog. The call engine requires only an already
resolved plan and configured event/media sinks. It neither looks up a number nor
writes a database row itself.

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

Recovery-grade context and room state is a separate contract. It requires a
durable append/checkpoint acknowledgement before an externally acknowledged
state transition, or an equivalent replicated log. Do not call it durable
recovery merely because asynchronous event rows usually arrive. If that mode is
added, model the room command as pending while an external journal worker writes;
do not execute Ecto queries inside `RoomAuthority` or hold a synchronous database
transaction across room/provider work.

### Persistence red-green checkpoints

1. **Database-neutral admission ports:** in `vxpipe_calls`, test route resolution,
   immutable revision selection, plan compilation, call ID creation, and
   idempotent admission using in-memory fakes. Prove no provider request or room
   process runs inside a repository transaction.
2. **Ecto adapter:** create `vxpipe_persistence` with Repo and migrations for
   definitions, immutable revisions, deployments, materialized inbound routes,
   calls, and admission idempotency. Use PostgreSQL integration tests for route
   uniqueness, revision pinning, transactions, and retry behavior; keep them in
   the tagged integration lane.
3. **Gateway admission slice:** make one normalized web or fake-telephony inbound
   request resolve a stored route, create one durable call, and start one room
   with the pinned plan. Replaying the request must return the same call. The
   static JSON admission implementation must continue to work without Repo.
4. **Ordered call ledger:** add the engine event sink and persist call lifecycle,
   participant, activation, and final turn events idempotently. Build
   `call_turns` as a projection and prove partial STT updates do not create
   duplicate turns.
5. **Context projection:** persist authorized private context section revisions
   asynchronously and finalize the last retained snapshot at call end. Prove
   public events and room snapshots still contain no context value.
6. **Model usage:** change the model provider contract to preserve each response's
   usage, emit one usage event per provider request/tool round, and persist exact
   units/provider/model/cost provenance. Derive turn and call totals without
   storing floats.
7. **STT/TTS/telephony usage:** add provider-specific finalization observations
   according to their actual billing units, retaining estimates and reconciled
   values as separate facts.
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
- **Retention implied by STT/TTS:** confuses processing permission with storage
  permission; transcripts and audio require explicit artifact/retention policy.

## Observable runtime contracts needed

The first multi-agent slice needs protocol-neutral events for:

- call admission requested, resolved, started, failed, and ended with stable
  call identity and pinned definition revision;
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
- provider operation started/completed/failed/cancelled and normalized usage
  recorded, including actual provider/model and correlation scope;
- recording track/segment started, finalized, incomplete, or failed;
- artifact and call-details publication queued, completed, incomplete, or
  failed;
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
   participant catalog, both entry refs, dated schema validation, shared
   capability defaults, agent overrides, initial-context validation, and a
   credential-free invocation. Implement immutable structs and pure path-specific
   validation only.
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
human caller and agent receiver selected by definition-local entry refs,
shared capability-profile defaults,
typed room-context sections and directly supplied initial context,
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
the permission-constrained room context read and update operations. A participant
transfer does not enumerate capability changes; the room reconciles the
proposed topology by filtering its normal capability intent through each
participant's presence-policy denials before commit. Do not start with Lua,
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
agent-scoped tool enablement, immutable resolved plans, room-owned context, and
live mixing. This checkpoint identifies missing contracts and inconsistencies;
it does not add runtime functionality. G1 records the approved tool layout and
G2 records the approved web routes, direct initial context, hash-only API-key
storage, single-use join tokens with existing-call recovery and no automatic
call-record expiry, prepared-token and direct-backend connection flows, explicit
initial participants/startup, and one
participant per definition key per call. G2's
remaining questions and G3–G13 are still unapproved. Detailed reasoning and
evidence live in the [call-definition gap review](../docs/call-definition-gap-review.md).

### Baseline and scope

- The pre-review labnote was already committed in `e7a769e` and the worktree was
  clean before editing. Review documentation will be a separate checkpoint.
- The original review preserved schema examples and decisions for comparison.
  Approved follow-ups align G1's tool examples and document G2's tenant-scoped
  start/join routes and authenticated direct-context admission. Obsolete input
  mappings are removed from both context examples and the invocation example.
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
   `participants` and read-only `billing` access to `intake`; transfer and context
   tools remain compiler-derived. This resolves G1's documentation ambiguity,
   not the future compiler implementation or its verification.
2. **Admission — routes, context, credentials, and entry roles approved:**
   tenant-scoped HTTPS routes select the participant connection key when starting
   a call and additionally the public call ID when joining one. Tenant keys are
   16 URL-safe random characters; participant keys and call IDs are UUIDs, separate from
   database primary keys. Joining uses the call's pinned definition and requires
   authorization before a transport session is issued. Initial context now
   matches the definition's sections directly; no separate input-binding layer.
   The integrating backend holds a gateway-issued API key and sends unsigned
   context over TLS. It may prepare a call and give its frontend only a scoped
   join token, or authenticate a direct WSS connection and send context in its
   first application message. Preparation pins/stores context without starting
   the room; authorized joining activates it. Browser HTTP signaling uses
   configured CORS grants; browser WebSockets require Origin validation.
   Admission may initialize sections that agents can read but none can write.
   `entry_caller` and `entry_receiver` are required refs to different participants
   in the same catalog. Startup prepares those two, not every catalog entry;
   other participants are admitted later as required. Initial refs remain pinned
   across transfers. The caller-start route must agree with `entry_caller`.
   Each definition key can bind only one participant in that call. A different
   person cannot claim an occupied key, and authorized reconnect/re-entry uses
   the existing participant rather than creating another identity.
   API-key storage is resolved: persist only one-way hashes, show keys once,
   and verify submitted keys without recovering secrets. Upstream MCP/provider
   credentials remain separate and recoverable where needed.
   Join tokens are consumed once at accepted admission. Before acceptance an
   unused/unexpired token can be retried; afterwards recovery reauthorizes via
   the backend and the existing-call `join-tokens` route. Reconcile pending
   admission first, preserve the same call/participant, and reject ended calls
   or active-connection takeover. Token expiry does not end an established call.
   Unstarted call records have no separate automatic expiry; an expired token
   prevents joining with that token, not later authorized fresh-token issuance.
   Record retention/cleanup is separate. G2 still needs API-key management
   review, token TTL settings, storage/retention policy, telephony context
   sourcing, personalization, timezone and dynamic destinations, plus reconnect
   eligibility/deadlines, issuance retry
   details, and admission/transfer crash handling.
   A valid API key authenticates the integrating application, not the speaker's
   customer identity; the backend authorizes the supplied business context.
3. **Context initialization and stale work:** G2 removed input mappings, but how
   partial defaults combine with initial context remains open. A supplied
   required field must not need a dummy default. Possible resolution: validate
   partial defaults, assemble values under an explicit rule, then validate the
   complete context. Activation checks alone do not invalidate interrupted work
   from the same activation. Also consider checking live turn/tool
   identity and deadline at mutation commit; deduplicate mutation retries.
   Writes committed before interruption remain facts. Reject mixed authorized
   and unauthorized reads as a whole, and redact write-only validation errors.
   A schema-valid agent write also does not prove identity verification or a
   completed external action. Consider separating intake from trusted-result
   sections; only authorized platform result bindings may update verified status or
   external receipts. Verification expiry, attempt limits, and comparison belong
   to a trusted backend, not model reasoning.
4. **External side effects:** a canceled request may already have booked or
   sent something remotely. Possible resolution: separate tool invocation from
   external operation, preserve confirmed/failed/unknown outcomes, and retry
   ambiguous writes only with provider-supported idempotency or reconciliation.
   Late receipts must not revive canceled model work or apply stale context
   patches. Bind action confirmation to exact arguments and expiry. A start
   event is not proof of successful completion.
5. **Private tool data and archive projections:** current tool events carry
   arguments/results through the gateway. Reusing that path for context would
   leak values despite metadata-only context events. Possible resolution:
   audience-specific lifecycle projections, private execution payloads, and an
   independently authorized private context journal. Apply retention before
   storage, including sensitive user input, not only during final export.
6. **Remote integration compatibility:** configured and enabled are specified,
   but supported protocol revisions, result types, tool-schema features, and
   unsupported server interactions need a tested profile. Possible resolution:
   explicitly bounded discovery and JSON/SSE handling, fail-closed incompatibility,
   credential-scoped caching, safe egress, and no permission changes from returned
   instructions. Existing HTTP actions require a remote MCP facade or trusted
   host adapter; they are not automatically MCP tools.
7. **Greeting, silence, voicemail, and ending:** first-message modes, timer
   phases, reactivation behavior, and speak-then-end ordering are underspecified.
   Possible resolution: closed runtime policies and typed evidence/deadlines.
   Reconnect must not accidentally repeat a greeting. An answered leg does not
   prove a human answered; required beep/classification evidence must actually
   be supported by the adapter. Preserve the no-local-model/no-local-VAD scope.
8. **Transfer policy and media routing:** transfer refs give an allowlist, but
   warm/cold behavior, acceptance, failure, and source disposition still need a
   configuration home. Consider call/source defaults plus target requirements,
   without named transfers. Define busy/no-answer/decline/cancel outcomes and
   compensating cleanup. A failed prepare cannot promise that already-dialed
   legs or stopped providers never changed. Private consultation needs explicit
   authorized audio routes and hold behavior, not only global mix-minus.
9. **Denials on routed capabilities:** denying STT to an agent is ambiguous
   when STT runs on a human participant and routes transcripts to that agent.
   Resolve whether a policy denies processing, consumption, or both; compile
   ownership and consumer routes together. Room-wide denial must stop the
   applicable provider work. Later reconciliation must not replay or transcribe
   the denied interval. Monitor and recording grants remain independent.
10. **Admission crash recovery:** distinguish webhook delivery IDs from stable
    call/leg admission identity. Transfer legs attach to a pending transfer, not
    a fresh definition lookup. Consider claimed/fenced admission transitions,
    request-digest conflicts, and reconciliation between durable creation, room
    startup, dialing, and running status. Do not retry an uncertain dial blindly.
11. **Archive completeness and finalization:** specify bounded per-consumer
    overflow behavior and explicit incomplete state. Current typed-input events
    lack the submitted text needed to reconstruct a transcript. Call end,
    operation settlement, artifact completion, and publication are distinct.
    Consider publication revisions and source watermarks, not only a call/schema
    job key, so late corrections can produce another immutable export. Retain
    engine-side live mixing/recording with external upload workers; upload is not
    a live monitoring feed. Distinguish sent from device-confirmed audio.
12. **Usage settlement:** one operation may have several billable
    attempts and usage observations. Consider observation identity and effective
    component totals rather than summing estimates, cumulative updates, and
    reconciliation. Keep canceled-operation costs and avoid double-counting
    provider token subcategories or allocations across turns.
13. **Provider profiles and long-call budgets:** specify supported profile
    options, adapter compatibility, token-aware context/history budgets, and
    fallback behavior without arbitrary executable provider configuration.
    Fallback cannot weaken permissions or repeat an uncertain external action.

### Planned acceptance steps, after approval and implementation

These are future verification scenarios, not capabilities available in the
playground today. Use deterministic fakes first and synthetic data throughout.

1. Compile one definition whose required context value comes directly from
   `initial_context`, with no mapping or dummy default. Missing required values
   must fail before a room or provider starts. Partial/default assembly cases
   require the pending G3 decision before they can become acceptance tests.
2. Start a room, save intake through the agent tool, then read it on another
   turn. Transfer to a read-only agent; the value remains available but writes
   fail. Inspect client events and confirm private tool values are absent.
3. Queue a context update, then interrupt or transfer before authority commit.
   It must reject stale work. Reverse the order and confirm the earlier committed
   write remains. Retry the same mutation and confirm it does not apply twice.
4. Submit a fake booking, commit it remotely, and delay its response while
   interrupting. Confirm one external action, an honest receipt/unknown outcome,
   no stale response, and no blind duplicate on retry. Change confirmed arguments
   and prove the earlier confirmation cannot authorize the new action.
5. Ask the agent to mark verification successful without backend proof. The
   trusted section must remain unchanged. Test wrong, expired, and reused input;
   inspect permitted logs/events/archive projections for sensitive-data leakage.
6. Return instructions that request an undeclared tool or destination. The
   engine must reject the operation regardless of the model's choice.
7. Simulate busy, no-answer, voicemail, declined, accepted, and late transfer
   callbacks. Check typed outcomes, cleanup, source recovery/failure policy, and
   that restrictive capability policies are enforced before the bridge opens.
8. Feed distinguishable fake audio into caller and consultation routes. Confirm
   each sink, monitor, and recorder hears only its authorized mix. Slow the upload
   and verify live audio continues while incomplete recording is reported.
9. Replay inbound lifecycle events and crash admission between each external
   boundary. Confirm one call and a fenced current room; reconcile uncertain legs.
10. Send typed input, interrupt generated output, end the call, and deliver late
    usage/artifact updates. Verify honest transcript provenance, no double-counted
    costs, explicit missing data, and a new revision for a corrected archive.
11. Exercise the approved web route shapes with synthetic tenant keys, participant
    keys, and call IDs. Preparation stores a call in the selected tenant; joining
    requires that tenant's call and an authorized participant from its pinned
    definition. Wrong-tenant calls, invalid role assignments, and missing call
    correlation must fail. Publish a newer definition and confirm joining an
    existing call still uses its earlier participant mapping. Verify that no
    database primary key appears in the public URL or session identifiers.
12. After implementing the approved boundary, provision a synthetic API key and
    use it only on a test backend to prepare initial order context. Confirm that
    preparation persists the pinned plan/context but starts no room/provider;
    only the scoped join token reaches the frontend. Joining activates that call
    without returning private preparation/context data. Two read-only agents
    can read the order but cannot rewrite it. Reject bad keys, wrong-tenant or
    participant access, schema-invalid values, and context policy overrides.
13. Authenticate a direct backend WSS connection using the key in its handshake
    header, then send unsigned context in its first application message. Missing
    or invalid keys fail before upgrade; missing/invalid/oversized initialization
    cannot start room/providers. Verify browser Origin rejection and HTTP CORS
    policies separately; lack of CORS grants must never bypass authentication.
    Preserve the browser WebRTC admission/signaling path. Keys/tokens stay out of
    URLs, ordinary management responses, room state, events, errors, and logs;
    only the delegated join token reaches the browser. Add
    exact token TTL, record-retention, issuance-retry, rotation/revocation,
    and admin-bootstrap cases after those exact contracts are reviewed. These
    are future checks, not a claim of implemented authentication or storage.
14. Compile both entry refs as strings resolving to different catalog members.
    Reject missing refs, inline objects in entry fields, unknown refs, and a
    caller equal to the receiver. The caller-start route must match the declared
    caller; a different role cannot silently replace it. Confirm both refs remain
    pinned through a transfer and after publishing a newer definition.
15. Start the caller/reception/billing/support fixture with fake connections and
    providers. Only the initial caller and receiver are prepared; billing and
    human support start no provider or dial work just because they are listed.
    Delay readiness and confirm the agent does not interact prematurely. A later
    transfer prepares its destination without treating a dial request as an
    established connection. In a human-to-human entry fixture, no implicit AI
    receiver is created.
16. Admit one staff member as `human-support-agent`, then attempt a second
    person's admission through the same call/participant route. Reject the
    second without replacing or sharing the first participant's identity.
    Exercise an authorized reconnect and agent re-entry: the participant ID
    stays bound to its definition, while an agent gets a fresh activation.
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
    These are future project-owned boundary checks, not tests of a hash library.
18. With fake transports/providers, race two joins using the same token. Only
    one claims admission and starts the room. A failure before acceptance can
    retry the unused, unexpired token; a lost response after acceptance cannot
    reuse it. Neither case creates a second call or participant. Advance a fake
    clock: expiry rejects an unclaimed token but does not end an accepted call
    or expire/delete an unstarted record. The latter still starts no room or
    provider work as time passes.
19. Use a synthetic backend API key with the existing-call `join-tokens` route.
    For an eligible prepared record whose original token expired, issuance
    starts no room; joining with the fresh token starts it once with its pinned
    plan/context and the same call ID. No new preparation is required solely
    because the old token expired or the record aged. For an eligible disconnected
    participant in a running call, joining preserves the live room, identity, and updated
    context. Confirm token requests create no extra call record and accept no
    initial-context or definition replacement. The route grants no browser CORS
    access; the separate browser join still uses the configured browser policy.
20. Attempt recovery with a wrong tenant/participant/key, ended call, revoked
    access, or active connection; reject without takeover. Lose the join response
    while admission is still pending and confirm recovery reconciles that same
    attempt before allowing another. If state changes after fresh-token issuance,
    joining rechecks eligibility and cannot admit a second connection. Exact
    status responses, timing, and crash-recovery tests await those detailed
    contracts; these steps describe future behavior, not tests run here.

### Review checkpoint verification

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

For the earlier 2026-09-07 initial-context and credential follow-up (HMAC
authentication is superseded by the API-key decision below):

- Parsed all 10 JSON fences and resolved all 15 local links/anchors across the
  labnote and focused review document.
- Checked that both context examples agree, the invocation supplies the declared
  required `customer.id` directly, and no JSON example retains `input_schema`,
  an `input` envelope, or an initialization mapping. Both agents keep read-only
  customer access, and billing keeps read-only intake access.
- Rechecked unified tool layout, approved route strings, labnote terminology,
  absence of local absolute paths, and `git diff --check`.
- Added future signed-admission, read-only-context, ciphertext-storage, and
  secret-redaction acceptance steps. These were not run: no runtime behavior or
  authentication implementation changed. At that checkpoint, precise
  signing/replay, credential lifecycle, and partial/default context semantics
  remained pending; the later API-key decision removes the signing questions.
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
  participants, and the smaller context example now includes its human caller.
- Checked transfer refs, direct initial context, read-only grants, unified tools,
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
  entry refs, existing context grants/tool layout, terminology, local-path
  hygiene, and `git diff --check`. No runtime tests or behavior changed.
- At that checkpoint, the next review was G2 initial-context sourcing for an
  inbound phone call, which cannot by itself supply the example's required
  customer/order identifier.

For the approved 2026-09-07 API-key admission simplification:

- Updated this original labnote and synchronized the focused review. Backend
  integrations now use one long-lived API key, not a separate client ID and
  signed payload. The previous HMAC contract and signing questions are marked
  superseded, including the old acceptance steps; historical evidence remains
  explicitly historical.
- Recorded backend preparation/browser token joining and direct authenticated
  backend WSS initialization. Preparation stores the pinned call/context without
  creating its live room; Calls owns preparation and later activation through
  persistence ports. Existing browser WebRTC remains supported.
- Checked the WebSocket GET handshake, browser header constraints, and Origin
  validation against the protocol/browser specifications linked above. HTTP
  CORS grants and WebSocket Origin checks are distinct from authentication.
  Wire details, token lifecycle, and retry/recovery rules remain pending.
- Replaced future acceptance steps 12–13 with API-key, prepared-context privacy,
  deferred startup, direct initialization, browser-origin, and redaction checks.
  No new endpoints, credentials, dependencies, storage, or runtime tests were
  implemented or exercised.
- Parsed all 10 JSON fences, checked both complete definition examples for
  distinct valid entry refs, transfer refs, matching context schemas, direct
  invocation context, and unified tools. Resolved all 17 local links/anchors;
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
  retain consistent entry/context/tool contracts, and all 17 local links/anchors
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
  pinned definition/context, and cannot bypass eligibility or take over an
  active connection. Pending admission must be reconciled first.
- Added future acceptance steps 18–20 for races, lost responses, fresh-token
  recovery, preserved live state, authorization, and expiry versus call duration.
  No endpoint, credential, storage migration, or runtime test was implemented.
- Verified all 10 JSON examples are unchanged and parse; both complete examples
  retain their entry/context/tool contracts. All 18 local links/anchors resolve,
  and both documents agree on the three approved HTTP route shapes. Admission
  terminology, local-path hygiene, and `git diff --check` checks passed.
- At that checkpoint, single-use admission and the recovery endpoint were
  resolved; unused-call expiry was next. The following clarification rejects
  the additional admission deadline without choosing a data-retention policy.

For the approved 2026-09-07 token-only expiry clarification:

- Clarified that a prepared call is only its persisted record, pinned definition,
  and initial context until joining starts the call process tree. There is no
  separate automatic admission expiry for this unstarted record.
- Expired tokens cannot join, but do not permanently disable or delete the call
  record. Authorized fresh-token issuance can reuse the same eligible record,
  definition, and context. Established calls are not ended by token expiry.
- Removed unused-call expiry from the pending admission decisions and recorded
  it as a rejected alternative. Retention/cleanup remains separate housekeeping;
  no token TTL value, cleanup policy, or runtime behavior was added.
- Updated future acceptance steps 18–19 for token expiry without record expiry
  and fresh-token admission to that same record. No runtime tests were run.
- Verified all 10 JSON examples are unchanged and parse, both complete definition
  contracts remain consistent, and all 18 local links/anchors resolve. The three
  route shapes, terminology, local-path hygiene, and `git diff --check` pass.

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
- Specified a working `20260906.02` context shape with section schemas, direct
  initial-context values (replacing the earlier input bindings), per-agent
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
- Split the persistence proposal into definition/routing, call/event/context
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
