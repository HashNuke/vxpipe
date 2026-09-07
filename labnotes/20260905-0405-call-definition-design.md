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
The tool executor must not automatically retry that request; return the unknown
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
storage is independently configured: metadata by default when enabled, with
explicit arguments/results retention and existing credential/header exclusions.
Variable history uses full post-update snapshots linked to the originating turn
and tool invocation, reusing saved tool arguments without a separate changeset.
The call record points to the latest persisted snapshot; the GenServer remains
the runtime owner. Database-backed updates return success only after the snapshot
and latest-pointer transaction commits. Retention periods use tenant overrides
over application settings, with retain forever as the application default.
Exact configuration, finite-expiry/cleanup, uncertain database outcomes,
sensitive-input handling, G2's remaining admission details, the rest of G4, and
G6–G13 remain pending user review.
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

Transfer terminates the source agent's whole execution subtree, including its
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
cold handoff, source disposition, variable projection, and presentation. The
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
call remains a G2 personalization question; the direct initial-variables decision
does not introduce automatic variable-to-dial bindings.

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
reporting is approved below; other retry/idempotency policies remain G4 review
questions. Explicit cancellation is deferred to the
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

The approved executor policy is no automatic retry of a submitted MCP request
whose timeout leaves its outcome unknown. Return that outcome to the agent;
do not silently resubmit the request. A booking whose response was lost may
already exist, so repeating the request could create a second booking.

A later tool call requested by the agent is a separate invocation, not a hidden
retry by the executor. This distinction is not an exactly-once or deduplication
guarantee: the separate invocation may still repeat an external action. No
automatic-retry exception based on tool classification or idempotency metadata
is approved now. Policies for other failures remain separate G4 decisions;
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

These describe behavior, not final JSON key or enum names. When neither
definition nor call creation selects visibility, hide tool events entirely.
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
The two-part target is approved; the exact JSON layout and field/enum names are
still under review. No new schema release or generated-tool configuration is
introduced by this decision.

Calls created for the `samples/` playground explicitly select full tool visibility
because it is our developer debug UI. This uses the same call policy available
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

This supersedes the earlier mandatory metadata-only client default and separate
sample-debug session grant. It is an approved design boundary, not current
gateway behavior. Tool-history storage is approved as an independent policy,
described in the persistence section below: client visibility neither enables nor
suppresses it. Private variable history uses the approved turn/tool-linked full
snapshots and call-level latest pointer described there. Retention periods use
application settings with tenant overrides and an application retain-forever
default. Exact storage configuration, finite-expiry/cleanup, uncertain database
outcomes, and sensitive transcript handling remain G5 review questions.

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
Personalization and the remaining security/lifecycle details are still pending
G2 review. No endpoint or ID generator was implemented here.

### Initial variables and API-key admission — approved G2 decisions

The integrating application supplies initial call-variable values directly in
the structure declared by the call definition. There is no second input schema
or input-to-variable binding layer. The reusable definition declares schemas and
agent permissions, with no variable defaults; the call invocation supplies any
initial values. The authorized backend may prefill any schema-declared section,
including one that no agent can write. Supplying initial variables does not edit
the stored definition or grant an agent write access.

For example, a shopping application starts support for order `ORD-1042`. The
definition declares an `order` section containing `id`. Its backend authorizes
the customer's access to that order and supplies
`initial_variables: {order: {id: "ORD-1042"}}`. Reception and billing may both have
`order: ["read"]`, while no agent has `write`. Admission initializes the section
once, and transfers preserve it without allowing an agent to rewrite the order
ID. The representative JSON below uses the same mechanism for `customer.id`.

The integrating backend now needs one long-lived credential: a gateway-issued
API key, sent as `Authorization: Bearer <api_key>` over HTTPS/WSS. Both supported
flows use unsigned application payloads. This replaces the earlier separate
client-ID/client-secret pair, HMAC signing, and browser forwarding of a signed
initial-variables envelope. Short-lived browser join tokens are delegated access,
not another long-lived integration credential.

**Flow 1 — backend preparation, browser token join:**

1. The backend authorizes its business request, then POSTs initial variables to
   the tenant/participant preparation route with its API key. That HTTP endpoint
   grants no cross-origin browser access.
2. Vxpipe verifies the key's tenant and permissions, validates variables, pins the
   definition revision and initial values, and stores a prepared call with a
   stable `call_id`. It returns an opaque, short-lived, single-use join token
   scoped to that call and its assigned participant. The token contains no
   readable variables.
3. The backend passes only that token to the frontend. The browser joins the
   previously prepared call; it cannot replace the stored variables, definition,
   tenant, or participant by adding new values to the join request.
4. Accepted admission atomically consumes the token before starting the room,
   not when the browser receives confirmation. Joining activates the prepared
   call's room once and obtains the transport session. Conversation waits for
   transport/capability readiness. The token is not authority to inspect private
   variables, and the browser receives no full preparation snapshot. Event,
   tool-result, and speech disclosure policies
   must still protect sensitive variables during the call.

Prepared-call storage and live room startup are separate stages. A prepared call
is just a database record with its pinned definition and initial variables;
issuing a token does not start the call process tree, connect providers, or dial
the receiver. Its `created_at` records creation; `started_at` stays unset until
the call actually starts, not merely when a token is issued or consumed. The
token expires, but the unstarted record has no separate automatic admission
deadline. An authorized backend can request a fresh token
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
   Authenticate before upgrading; an unsigned variable message is not a way to
   create an unauthenticated call.
2. After the upgrade, the backend sends initial variables in the first application
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
shape is still pending. Do not put API keys, initial variables, or bearer tokens
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

**Still pending:** administrator bootstrap, permission granularity,
rotation/revocation, token lifetime settings, separate record-retention and
storage-limit policies, precise transport messages/timeouts and WebSocket routes,
reconnect eligibility/deadlines, and detailed retry/crash reconciliation. Single-use claim
and existing-call token issuance are approved below. HMAC algorithm selection,
payload canonicalization, and signature-envelope fields are no longer
implementation questions. Variable-default assembly is eliminated: only supplied
setup values prefill variables. G3's variable ownership is settled below; telephony
initial-variables sourcing and personalization
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
   room, retaining its identity, current variables, and pinned plan. It does not
   reinitialize variables from the original values or create a replacement call.
6. A token's expiry only prevents a future claim. Once admission was accepted,
   that token expiring does not hang up the established call. Later reconnect
   still needs a fresh token and whatever reconnect eligibility is approved.
7. An unstarted call record does not automatically expire because its token
   expired or because time passed since preparation. Without a valid token the
   browser cannot join, but the record remains eligible for backend-authorized
   fresh-token issuance subject to the same authorization/lifecycle checks.
   Reissuance preserves its pinned definition and initial variables; it does not
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

Superseded. The backend sends initial variables directly under API-key
authentication, either preparing a call for token-based browser join or
initializing its own authenticated connection. This removes signature generation,
canonicalization, and signed-envelope verification from the integration contract.
It does not remove HTTPS/WSS, tenant authorization, replay/claim protection for
join tokens, or request idempotency. API keys remain outside browser bundles,
call definitions, call variables, and logs; sensitive variables stay server-side
in the prepared-call flow.

### Reuse consumed join tokens or recreate the call after a lost response

Rejected. A lost acknowledgement does not undo accepted admission. Reusing the
token could grant a second connection; recreating the call would duplicate its
record, variables, and potentially provider work. Recovery instead reauthorizes
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
Validation or a confirmed transaction failure returns a typed error and preserves
current values/revisions. A timeout or missing commit reply is not proof of either
commit or rollback; uncertain-outcome/restart handling remains a separate review
item and must not silently become success. Reads run the same room/agent identity
checks and require every requested section to be
readable. A forbidden section produces a permission error for the whole request
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
commands, domain events, provider operations, variable updates, artifacts, and
publisher jobs. The call ID survives room-incarnation recovery. `room_id`
identifies the live collaboration/media scope, and `incarnation_id` rejects stale
work for one execution of that room. The initial implementation may enforce one
room per call, but the identifiers must not be conflated because a call can have
multiple telephony legs and a recovered room receives another incarnation.

The relational `calls` row should contain durable identity and summary state,
not every detail as one mutable JSON document. It records tenant/application,
definition revision, plan digest, direction, route/invocation identity, current
room/incarnation, lifecycle state, distinct `created_at`, `started_at`, and
`ended_at` timestamps, terminal reason, archive status, retention-policy identity,
and `latest_variables_snapshot_id` for the latest retained variables snapshot.
Provider-native call IDs belong in a
separate call-leg/provider-identity record with appropriate uniqueness and
redaction.

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
- Set the first live-start time once for that call ID. Reconnects, transfers,
  duplicate event delivery, token reissuance, and recovery of the same call do
  not restart the call clock. Room-incarnation and participant/leg timings are
  separate facts, not replacements for the original `started_at`.
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
- `usage_records`: normalized billable units and cost observations linked to a
  provider operation and, when meaningful, a turn;
- variable snapshot history: immutable full Call Variables snapshots with
  call/room-incarnation identity, originating turn/tool invocation, source
  participant, revisions, and commit timestamp when variable retention is enabled;
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

### Tool-history storage is independent of client visibility — approved G5 decision

Store tool-call data according to storage policy regardless of client visibility.
When tool-history storage is enabled, retain invocation identity, participant/tool
identity, timing, and outcome by default. Retaining arguments/results requires
explicit selection in the storage policy. Integration credentials and
authorization headers remain excluded before persistence, even when payload
retention is selected; removing them only from the final export is insufficient.

The call-ledger/storage consumer must receive its own projection from the engine
event source, not reuse the browser-filtered stream. A hidden client tool event
can still have its permitted arguments/result stored. Conversely, full client
visibility, including in sample calls, does not implicitly enable payload storage.
Storage access does not grant browser access, agent tool execution, or broader
agent variable permissions. General tool-history archival remains asynchronous.
The variable snapshot transaction below is an explicit acknowledgement boundary
for variable-update tools, not a reason to gate every tool or room event on SQL.

For example, keep a booking tool hidden from the browser while explicitly saving
its arguments/result for operational review. Another call may show the result
live but save only metadata. Both are supported without changing tool behavior.
Retention periods use application configuration with tenant overrides and an
application retain-forever default. Exact configuration syntax, finite-expiry/
cleanup, and broader sensitive-input/redaction policy remain under review. This
decision does not add runtime persistence or guarantee complete room recovery.

### Variable history snapshots and the latest pointer — approved G5 decision

When variable retention is enabled, save a full post-update Call Variables
snapshot for each committed `update_variables` or `update_variable` invocation.
Link it to the call, room incarnation, originating turn, tool invocation, source
participant/activation, section/global revisions, and commit timestamp. Several
updates in one turn remain separate snapshots identified by invocation and revision,
not one overwritten history row. A delayed update stays linked to its original
turn even if a later turn or agent is now active. Rejected updates do not create
successful state snapshots; their failures remain tool-history outcomes.

Reuse the saved tool call and its arguments to inspect the requested change.
There is no separate changeset, patch journal, or duplicate argument payload in
the snapshot record. Argument retention is selected through the existing
tool-storage policy; this decision does not change unrelated tools' metadata-only
default. The snapshot records the resulting state after merge, not just the
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
revisions, emits the update event, and replies. Confirmed transaction failure
leaves current state unchanged; no failed database write becomes memory-only
success. No second candidate update may pass an unresolved predecessor. Database
latency therefore affects the variable-update tool, but does not block
`RoomAuthority`, media, or unrelated capabilities. There is no separate changeset
or new write-ahead journal: the snapshot/pointer transaction is the required write.

This supersedes the earlier proposal to acknowledge a memory update and persist
its snapshot later. General call/tool/usage events can still be archived
asynchronously. A lost reply does not undo a committed snapshot; exact uncertain
commit and process-restart handling remain open, and successful snapshot storage
does not by itself implement full room recovery. An explicitly database-free
deployment has no database-commit guarantee; a database-backed call must never
silently fall back to it when storage fails. Storage duration resolves as below;
cleanup of referenced snapshots and exact database schema remain follow-ups.
This checkpoint adds no runtime behavior or migrations.

### Retention periods — approved application and tenant policy

Configure stored call-data retention periods at application level, with tenant
overrides. The application default is retain forever. An explicitly configured
tenant period wins; otherwise inherit the application period, including its
forever default. Periods are not agent-defined or client-selected settings.

Forever means Vxpipe applies no age-based expiration to retained data. It does
not enable storage that is disabled, retain otherwise excluded credentials,
expose stored payloads to clients, keep room processes or live buffers forever,
or promise backup/recovery. Capture enablement, payload selection, privacy, and
client visibility remain separate from how long permitted stored data is kept.

For example, leaving both levels unspecified retains permitted stored history
forever. Configuring an application period changes the inherited value, and a
tenant override changes only that tenant's effective period. An explicit forever
selection is also a period choice, not an absent configuration or zero-duration
expiry. Exact serialized values/units are not frozen by this prose contract.

Finite-expiry clock origin, policy changes affecting existing data, deletion-job
behavior, and cleanup of snapshots referenced by a call remain under review.
No automatic cleanup is implemented here. This retention decision does not alter
the requirement to commit a variable snapshot before update-tool success.

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

Recording remains a separate capability and retention choice. Disabling speech
recognition or synthesis does not disable recording, and enabling either does not
authorize recording. Participant/room policy must explicitly allow the media
tap, artifact type, access scope, and retention period.

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

The running-state write records the actual live-start occurrence timestamp,
not the earlier record creation/admission-request time or the database write
time. It preserves the call's first `started_at` when retried or reconciled.

Browser preparation splits this workflow at the durable boundary: resolve and
pin the plan/variables, persist the prepared call, then return the scoped join
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
variable updates. It neither looks up a number nor issues SQL itself.

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
The owner waits for that confirmation before making new values current. A lost
reply can still leave a committed database snapshot; uncertain commit/restart
handling needs explicit review and must not be mistaken for a definite rollback.

Full room recovery remains a separate contract for restoring the pinned plan,
variables, participants, capabilities, and lifecycle safely. Committed variable
snapshots do not by themselves implement that recovery, nor make all asynchronous
events lossless. Do not execute Ecto queries inside `RoomAuthority` or hold a
database transaction across room/provider work.

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
5. **Variable commit boundary:** persist private full post-update snapshots linked to
   turns/tool invocations, reusing recorded tool arguments rather than a separate
   changeset. Insert history and conditionally advance the call's latest-snapshot
   pointer in one transaction before tool success or publication of new in-memory
   state. Test a held commit, confirmed failure, duplicate/stale persistence requests,
   and latest lookup without replaying history. Prove public events and room
   snapshots still contain no variable value. Finalization uses committed snapshots,
   not an assumption that unconfirmed attempts were persisted.
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
  call identity and pinned definition revision; actual live start carries its
  occurrence timestamp, distinct from record creation and event persistence;
- call plan resolved;
- agent participant admitted and ready;
- agent participant activated and deactivated;
- participant transfer requested, accepted, completed, rejected, failed, and
  cancelled, including source and destination participant IDs and kinds;
- participant capability denial applied or removed, including policy-owner and
  matched participant IDs, and capability reconciliation requested, enforced,
  acknowledged, timed out, or failed;
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

Only one agent participant may own generated conversational output for a
connection/lane at a time. Inactive agent participants must not consume turns or
emit user-visible output. They also must not advertise or invoke their MCP
tools. A transfer shuts down the source agent's execution subtree, including its
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
agent-scoped tool enablement, immutable resolved plans, room-owned variables, and
live mixing. This checkpoint identifies missing contracts and inconsistencies;
it does not add runtime functionality. G1 records the approved tool layout and
G2 records the approved web routes, direct initial variables, hash-only API-key
storage, single-use join tokens with existing-call recovery and no automatic
call-record expiry, prepared-token and direct-backend connection flows, explicit
initial participants/startup, and one
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
call-wide default. Independent tool-history storage retains metadata by default
when enabled and arguments/results by explicit selection, with credential/header
exclusions. Variable history now saves full post-update snapshots linked to turns
and tool invocations, without separate changesets; the call record points to the
latest persisted snapshot. Database-backed update tools wait for the snapshot/
pointer transaction before returning success. Retention periods resolve from
tenant overrides and application settings, with retain forever as the application
default. Exact configuration, finite-expiry/cleanup, uncertain database outcomes,
and sensitive-input handling remain under review. Other G4 questions, remaining
G2 details, and G6–G13 remain unapproved.
Detailed reasoning and evidence live in the
[call-definition gap review](../docs/call-definition-gap-review.md).

### Remaining review count — 2026-09-07

There are **11 open review groups** out of the original 13: G2, G4, and G5 are
partly resolved, and G6–G13 still need approval. G1 and G3 are resolved in
documentation.
This counts the numbered groups, not individual edge cases or implementation
tasks. Section-level merging, recursive preservation inside nested objects,
explicit-null clearing, root-section/direct-variable addressing, missing reads,
and iterative population without required-variable checks are resolved
within G3. The read-only/read+write permission decision also removes the
write-only error question. Naming and agent-mediated MCP result updates are also
resolved. The dedicated variables-process ownership and submitted-write lifecycle
are approved, and additional schema-complexity caps are not adopted now. That
closes G3 and reduces the count from 12 to 11; implementation is still pending.
G4's ordinary-interruption rule, unknown-outcome reporting on timeout, and no
automatic executor retry for that timeout are approved. Its other questions keep
that group open and the overall count at 11.
Late confirmations are explicitly deferred as an external-event concern, not an
additional prerequisite for the current MCP slice.
Generic platform-level confirmation is also excluded for now. Other G4 questions
remain, so the review count is unchanged.
The provider-independent acknowledgement/background-result workflow is approved;
explicit cancellation is deferred to its issue for later review. Other G4
questions remain pending and the count stays at 11.

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
   join token, or authenticate a direct WSS connection and send variables in its
   first application message. Preparation pins/stores variables without starting
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
   Their `created_at` is distinct from `started_at`, which remains unset until
   actual live startup and is preserved across reconnects/recovery. Call duration
   excludes preparation wait.
   Record cleanup is separate from admission/token expiry. Retention periods now
   have an application retain-forever default with tenant overrides. G2 still needs
   API-key management review, token TTL settings, finite-expiry/cleanup, telephony
   variables sourcing, personalization, timezone and dynamic destinations, plus reconnect
   eligibility/deadlines, issuance retry
   details, and admission/transfer crash handling.
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
   outcome if already known. The executor does not automatically retry that
   request; a later agent-requested call is a separate invocation, without an
   exactly-once guarantee.
   Late booking confirmations are an external concern: a future gateway webhook
   or other external event could reach the relevant room/agent while the room
   is active. Handling that scenario, including reconciliation and operation
   storage solely for it, is deferred and not required for the current slice.
   Other retry exceptions remain unapproved. Explicit cancellation is deferred
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
   tool key and take precedence over the call-wide default. Exact configuration
   syntax and runtime implementation remain pending. Tool-history storage is
   independent: metadata by default when enabled, arguments/results by explicit
   selection, and integration credentials/authorization headers excluded before
   persistence. Variable history uses full post-update snapshots linked to the
   originating turn/tool call, reuses saved tool arguments without a changeset,
   and advances the call's latest-snapshot pointer transactionally before update
   success. Application retention defaults to retain forever, with tenant settings
   overriding application values. Exact configuration, finite-expiry/cleanup,
   uncertain database outcomes, broader redaction, and sensitive user-input handling
   remain proposals for review.
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
   inherits the call-wide default. A hidden binding must stay hidden even when
   the call-wide default is full. With client tool events hidden, explicitly
   enable tool payload storage and verify permitted synthetic arguments/results
   reach the storage consumer while no tool events reach the browser. Reverse
   the settings: full client visibility with tool-history storage enabled but
   no payload retention selection must store only invocation/participant/tool
   identity, timing, and outcome. Check credential/header exclusions before
   persistence, not just on export. Enable variable retention, verify the initial
   baseline is reachable through the call pointer without an invented turn, and
   hold a snapshot commit behind a test-owned barrier. Assert no update-tool
   success, newly published values/revisions, or success event before confirmation.
   Release commit and verify the snapshot and latest pointer exist before success.
   Make two updates in one turn and another later; each snapshot must contain
   the exact resulting state, unchanged sections, and original turn/tool identity,
   without a separate changeset. Retry a persisted operation, submit a stale one,
   and fail a transaction: no duplicate history, pointer regression, cross-call
   pointer, or partially committed snapshot/pointer pair is allowed. A confirmed
   transaction failure preserves the prior in-memory values/revisions and returns
   no success. Verify `RoomAuthority` and media can progress while the variable
   tool waits for storage. Fetch latest values directly through the call pointer.
   Separately omit retention settings at both levels and expect retain forever;
   set an application period and verify tenant inheritance, then override one
   tenant without affecting another. Duration selection must not enable additional
   capture or client disclosure. Finite-expiry cleanup awaits its own reviewed
   semantics. These are planned checks, not current playground guarantees.
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
   After the remaining G4 policies are approved, add cases for other failure/retry
   policies. Do not add a generic confirmation-token or changed-confirmation-arguments
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
    use it only on a test backend to prepare initial order variables. Confirm that
    preparation persists the pinned plan/variables but starts no room/provider;
    only the scoped join token reaches the frontend. Joining activates that call
    without returning private preparation/variable data. Two read-only agents
    can read the order but cannot rewrite it. Reject bad keys, wrong-tenant or
    participant access, wrong datatypes/invalid populated values, and variables
    policy overrides; missing variables alone must not fail preparation.
13. Authenticate a direct backend WSS connection using the key in its handshake
    header, then send unsigned variables in its first application message. Missing
    or invalid keys fail before upgrade; a missing initialization message or
    malformed/oversized initialization cannot start room/providers. An empty
    variables or a partial section in a valid message is allowed. Verify browser
    Origin rejection and HTTP CORS
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
    plan/variables and the same call ID. No new preparation is required solely
    because the old token expired or the record aged. For an eligible disconnected
    participant in a running call, joining preserves the live room, identity, and updated
    variables. Confirm token requests create no extra call record and accept no
    initial-variables or definition replacement. The route grants no browser CORS
    access; the separate browser join still uses the configured browser policy.
20. Attempt recovery with a wrong tenant/participant/key, ended call, revoked
    access, or active connection; reject without takeover. Lose the join response
    while admission is still pending and confirm recovery reconciles that same
    attempt before allowing another. If state changes after fresh-token issuance,
    joining rechecks eligibility and cannot admit a second connection. Exact
    status responses, timing, and crash-recovery tests await those detailed
    contracts; these steps describe future behavior, not tests run here.
21. Use a fake clock to create a record at 10:00, then issue/expire/reissue tokens
    and leave startup pending: `created_at` stays 10:00 and `started_at` remains
    unset. Actually start the call at 10:15, delay persistence, and confirm its
    `started_at` is still 10:15 rather than the write time. End at 10:18 and
    report three minutes of live duration, not eighteen. Verify the configured
    call-duration limit also ignores preparation wait. Duplicate delivery,
    reconnect, transfer, and same-call recovery preserve the first start time;
    failure before live startup leaves it unset. These are future project-owned
    lifecycle/projection tests, not tests run for this documentation checkpoint.

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
