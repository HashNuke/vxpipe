# Call definition design

Research date: 2026-09-05 UTC

## Goal

Define the smallest useful graph-based call-definition contract for Vxpipe: one
reusable, versionable description that can start a single-agent call today and
grow into multi-agent calls, scoped context, agent handoffs, human transfers,
tools, and telephony without prematurely implementing a general-purpose
workflow language.

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
- Keep reusable definitions secret-free. Permit a call invocation to carry
  one-call credential material, but resolve it immediately into a private
  credential lease and keep its value absent from resolved-plan equality,
  public snapshots, events, errors, and logs.
- Make remote MCP sources, tool bindings, and per-agent tool grants part of the
  call definition. Application configuration may provide integration profiles
  and authentication defaults, but it must not silently add tools to a call.
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

These identify the behaviors a useful call graph must be able to compose. They
do not require arbitrary code, arbitrary expressions, parallel branches, or a
large node taxonomy.

### A graph can be the public composition model without being the domain kernel

Evidence cuts both ways on explicit graphs:

- A graph gives inspectable paths, deterministic action nodes, fallback edges,
  and focused debugging. It works well for regulated or highly structured calls.
- A graph becomes cumbersome when every conversational phase is a node. Model
  behavior must simultaneously follow the current node, evaluate possible
  transitions, and handle digressions. One reviewed control plane is retiring
  this shape in favor of focused agents with tool-selected handoffs.
- Another system compiles a graph into a single prompt for flexible execution,
  but this increases prompt size and weakens deterministic condition handling.
- Code-first systems consistently distinguish persistent agents from temporary
  typed tasks rather than treating every implementation object as the same kind
  of graph node.

Vxpipe can still make a graph the first-class public call definition. The graph
should describe control topology while the existing room model remains the
authority for participants, connections, media, turns, tools, and call legs.
The graph selects which activity owns conversational control and what follows
its typed outcome; it must not become a second copy of room state.

The graph executor should be intentionally small:

```text
enter one node
  -> node starts, completes, or waits
  -> node emits one typed outcome and optional typed context patch
  -> graph follows the matching edge
  -> previous activation becomes stale
  -> enter the next node or finish
```

The graph does not evaluate natural-language edge conditions or execute opaque
code. The source node owns how an outcome is chosen. For example, an agent node
can expose its outgoing model-selectable routes as tools; a branch node can
evaluate a closed deterministic condition; an action node can emit success or
failure after a tool or engine command completes.

Start with one active control node. Media processing, provider requests, tools,
and participant processes remain concurrent under supervision, but parallel
graph branches, joins, races, and compensation are deferred until a concrete
call requires them.

The graph's mutable execution state should remain small: resolved-plan ID,
current node and activation IDs, node lifecycle and entry time, transition and
visit counters, and the last outcome/edge correlation. Typed call context stays
in room-owned state. Asynchronous node work runs outside the room authority and
returns typed results; the room alone commits context patches and transitions.

### Distinguish graph execution primitives from authoring primitives

There are two meanings of primitive:

- **Execution primitives** are the closed node kinds and outcomes understood by
  the runtime. They sit beneath the graph.
- **Authoring primitives** are friendly builders such as single agent, agent
  handoff, collect fields, or warm transfer. They sit on top of the graph and
  compile into ordinary nodes and edges.

Vxpipe can offer both a raw graph API and higher-level builders without creating
two execution semantics. The graph is the common interchange and inspection
form; the builders only produce validated graph data.

The minimal useful execution-node inventory is:

1. `agent`: hold multi-turn conversational control until the model, host, or
   policy selects a declared route;
2. `action`: execute one typed tool or engine command, possibly asynchronously,
   and produce a terminal outcome;
3. `wait`: await a typed room/participant/leg/host event or a deadline without
   starting a side effect;
4. `branch`: choose an outcome through a small deterministic condition algebra
   over declared context fields; and
5. `end`: finish graph execution with a typed result and room/call disposition.

Each kind has one lifecycle-shaped responsibility:

| Node kind | Owns | Waits for | Emits |
| --- | --- | --- | --- |
| `agent` | Conversational control | A declared route or interruption | A route outcome |
| `action` | One requested side effect | Its terminal command result | A typed terminal outcome |
| `wait` | No side effect | One allowlisted event or deadline | The event or timeout outcome |
| `branch` | Deterministic selection | Nothing | One condition arm |
| `end` | Final disposition | Nothing | No further outcome |

An `agent` node represents a logical conversational participant, not a process.
Entering it creates a fresh activation and grants conversational control;
exiting it revokes that control. Re-entering the same node may reuse that
agent's private history according to policy, but still creates a new activation.
Definition node IDs, runtime participant IDs, and activation IDs are therefore
different identities.

Every activation receives a fresh ID, and every outcome carries that ID. The
room rejects outcomes and visible output from stale activations after a
transition. This gives the graph a precise concurrency boundary without adding
parallel graph execution.

Only `agent` and `end` are required for the first two-agent proof. `action` is
the next required kind for tools and human transfer. `wait` and `branch` should
be added only with a focused use case. A task or subflow is composition over
these nodes with typed input/output, not an initial sixth runtime primitive.

This small inventory covers the anticipated features:

- an agent handoff is an `agent -> agent` transition;
- a model tool can run inside an agent, while a guaranteed workflow action is
  an `action` node;
- DTMF collection and a warm transfer are asynchronous actions with explicit
  results;
- waiting for a participant to join or for an external approval is a `wait`;
- deterministic routing on previously collected facts is a `branch`;
- hangup or detach-agent-while-humans-continue is an `end` disposition; and
- a reusable collection or transfer workflow can later compile to a subgraph.

### Context is not one value

The reviewed systems distinguish at least three forms of state:

- model history: ordered user, assistant, tool, configuration, and handoff
  items;
- typed session data: facts collected or loaded during the call; and
- handoff context: a selected copy, summary, recent window, or fresh context for
  the destination agent.

Some systems share all model history by default. Others start every agent with a
fresh history and require an explicit copy. Both demonstrate why Vxpipe must
make the policy explicit. Typed facts should never be re-extracted from a
transcript when an authoritative tool result or invocation value already exists.

The initial context model should distinguish:

- `call`: typed facts visible according to field grants;
- `agent`: private model history and scratch state;
- `participant`: data private to or owned by one participant; and
- `handoff`: an immutable packet created for one transition.

A handoff packet should name its source and destination agents, reason,
authoritative typed fields, selected transcript/history, causation, and
visibility. It is an event/result, not a mutable global bag.

### Tools and authoritative control must remain separate

Model-facing tools are the common request mechanism for agent handoff, hangup,
data collection, and external actions. The model can request an operation; it
must not directly change active-agent, participant, connection, leg, or room
state.

An engine-owned tool invocation should therefore have:

- stable invocation and correlation IDs;
- an input and output schema;
- source agent/turn identity;
- grants and an optional approval policy;
- deadline, cancellation, retry, and idempotency policy;
- progress plus one terminal result;
- result visibility to the model, room, clients, and artifacts; and
- an authoritative command emitted only after validation succeeds.

Agent handoff, participant transfer, telephony-leg transfer, and ending a call
remain different commands even if all are exposed to a model as tools.

### Definition version, deployment selection, and invocation are different

The reviewed control planes support stored and inline definitions, drafts,
published revisions, explicit version selection, and environment aliases. These
are useful control-plane features but should not complicate the first engine
contract.

Vxpipe should distinguish:

```text
Application integration configuration
  + Call definition revision
  + Call invocation and one-call credentials
        -> definition resolver/compiler
        -> immutable resolved call plan + private credential leases
        -> running interaction / room incarnation
        -> events, artifacts, and result
```

- Application configuration owns registered provider/integration profiles,
  default authentication, server behavior, and deployment defaults.
- A call definition owns portable conversational composition and policy,
  including the remote MCP sources available to the call, stable tool bindings,
  and the tools granted to each agent.
- A call invocation owns caller/destination identity, entrypoint, definition
  selection, permitted runtime variables, idempotency, and optional one-call
  authentication overrides for sources declared by that definition.
- A resolved call plan pins all references, defaults, adapter capabilities,
  discovered tool schemas, policy versions, and credential-lease references
  without retaining secret values.
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
CallDefinition.Graph
CallDefinition.Node
CallDefinition.Edge
CallDefinition.Context
CallDefinition.Policy
CallDefinition.ToolSource
CallDefinition.ToolBinding
CallInvocation
CallInvocation.Authentication
ResolvedCallPlan
ResolvedCallPlan.ToolBinding
```

The constructors accept ordinary Elixir data and return path-specific typed
errors. A JSON codec should map one-to-one onto the public structures after the
semantics work in embedded use. JSON remains a first-class public format, but
raw decoded maps must not flow into room processes.

This order avoids implementing a JSON loader before the domain is understood,
while preserving the future container contract. A YAML adapter would be
mechanical once the JSON-safe schema exists and does not need separate runtime
semantics.

### Minimal `CallDefinition` v1

The first version should contain only:

- `schema_version`;
- optional external `id` and `revision` metadata;
- `entry_node`;
- named `nodes` using only `agent` and `end` kinds initially;
- typed `edges` keyed by source-node outcome;
- a typed `context` field schema and initial defaults that are safe to persist;
- named remote MCP tool sources and stable tool bindings available to this call;
- shared call policies for turns, interruption, limits, failure, and ending;
  and
- artifact/event policy references.

Each `agent` node should contain:

- stable node and agent identity;
- instructions or a versioned prompt-profile reference;
- model-inference capability profile;
- optional speech-to-text and text-to-speech profile overrides;
- tool grants;
- input, output, and action-guardrail policy references;
- entry behavior (`wait`, fixed speech, or generated speech); and
- optional limits stricter than the call defaults.

Each edge should contain:

- stable name;
- source node, declared source outcome, and destination node;
- optional model-facing route description consumed only by an `agent` node;
- optional context/history transfer policy for an agent-to-agent transition;
  and
- optional user-visible transition speech policy.

Every node kind defines how its allowed outcomes and result schemas are
declared. The compiler rejects outcomes outside that contract, duplicate
`(source, outcome)` routes, and missing targets. The executor only matches a
typed outcome to an edge; it does not know how the outcome was chosen.

For an agent node, its outgoing edges declare the available route outcomes and
their descriptions for model or host selection. Action and wait outcomes are
closed by their operation/event contracts; branch outcomes are its declared
arms; and `end` has no outgoing outcome. Edges remain ordinary typed routing
data in every case.

For an agent node, the runtime can compile model-selectable outgoing edges into
engine-owned route tools granted only during that node activation. The room
checks that the source activation is still current, the target exists and is
ready, and transition budgets are not exhausted.

### Per-call remote MCP sources and tools

Remote MCP support sharpens the distinction between definition, invocation, and
application configuration:

- The **call definition** declares which remote MCP sources exist for this call,
  which remote tools are bound to stable call-local names, and which agents may
  expose those names to their models.
- The **call invocation** may provide authentication for a declared source. That
  credential exists only for this running call and overrides the corresponding
  application default as one atomic authentication value.
- **Application configuration** may register deployment-owned MCP profiles with
  endpoints and default authentication. It never grants a tool merely because a
  server or credential is configured.

Use three explicit layers rather than treating an MCP server's discovered tool
list as an agent grant:

```text
tool source:  where tools come from
tool binding: stable call-local name -> source + remote tool name
agent grant:  which call-local tool names one agent may expose to its model
```

A source has a stable definition-local ID and uses exactly one of these forms:

1. a registered application profile, where the host owns the endpoint and may
   provide default authentication; or
2. an inline HTTPS Streamable HTTP endpoint, where the invocation supplies any
   required authentication.

For example, the inline form is distinct from a registered profile:

```json
{
  "type": "remote_mcp",
  "endpoint": {
    "transport": "streamable_http",
    "url": "https://tools.example.test/mcp"
  },
  "authentication": "required"
}
```

An application credential must never be selected solely by a caller-controlled
source ID. Otherwise a definition could reuse a trusted ID, substitute an
attacker-controlled URL, and receive the default credential. A registered
profile binds its default authentication to its application-owned endpoint. An
inline endpoint cannot inherit profile authentication unless it resolves through
that profile and passes the profile's endpoint constraints.

The initial tool-binding form should be explicit:

```json
{
  "tool_sources": {
    "utilities": {
      "type": "remote_mcp",
      "profile": "utilities-production"
    }
  },
  "tools": {
    "current_time": {
      "source": "utilities",
      "remote_name": "get_current_time"
    }
  }
}
```

The model sees `current_time`, not an endpoint, credential, profile name, or
unfiltered remote catalog. Different sources can therefore expose the same
remote name without collision, and a remote server may add unrelated tools
without changing the call's granted surface.

The resolver performs bounded `tools/list` discovery before starting the room,
verifies every declared remote binding, validates its input/output schemas, and
pins the normalized definitions in the resolved plan. The first version should
fail call creation when a required source or declared tool cannot be resolved;
degraded optional sources can be designed later. Remote definitions and
annotations are untrusted data even when the endpoint is configured.

Application configuration and invocation authentication have narrow precedence:

```text
invocation authentication for the declared source
  > registered profile's default authentication
  > explicit unauthenticated access
  > resolution error when authentication is required
```

Omission means inherit. An explicit `none` means do not use the configured
default. Authentication objects replace one another whole; their headers,
tokens, and options are never deep-merged. Per-call overrides do not change the
endpoint, transport, tool bindings, grants, timeouts, or application environment.
Those require their own typed definition or invocation fields if a concrete use
case later needs them.

Conceptually, the OTP application default is a closed profile registry:

```elixir
config :vxpipe_call_engine, :remote_mcp_profiles, %{
  "utilities-production" => [
    url: "https://tools.example.test/mcp",
    authentication: [type: :bearer, token: {:system, "UTILITIES_MCP_TOKEN"}]
  ]
}
```

An embedding application may supply the token directly in its application
settings; a release may resolve the system reference in `runtime.exs`; and the
container JSON adapter may decode the same closed authentication shape. All
three paths normalize before call resolution and have the same precedence.

Start with closed authentication variants `none`, `bearer`, and validated custom
headers. A supplied OAuth access token is a bearer credential; performing an
interactive OAuth flow is a separate control-plane feature. Custom headers must
not override protocol routing, content-length, host, or other transport-owned
headers.

At resolution, literal invocation credentials move into a call-scoped private
credential lease. The resolved plan and room state retain only an opaque lease
reference and non-secret provenance such as `invocation_override` or
`application_default`. The lease must redact process status/crash formatting and
expire with the room incarnation. Tool execution retrieves the value only at the
remote MCP adapter boundary.

The effective call configuration is resolved once. A running call does not read
changing application environment or mutate `Application` configuration. New
defaults affect only later calls.

Here, **per-call** means every invocation receives its own resolved catalog,
bindings, grants, and credential leases. It does not require callers to duplicate
an inline definition: several calls may select the same immutable definition
revision while resolving it independently with different invocation credentials.

The public engine boundary should accept a definition (or immutable definition
reference) plus an invocation. The current `CreateRoom` command remains a lower
level engine command and should eventually receive only a resolved-plan identity
or typed plan, never decoded call JSON or literal credentials.

### Initial handoff context policies

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

Authentication is a distinct typed invocation input rather than a behavioral
deep merge. An invocation may replace the default authentication for a remote
MCP source already declared by the definition, but it cannot use credentials to
introduce another source or grant another tool. The entire authentication object
is replaced so credentials from different scopes cannot be combined accidentally.

If future applications need controlled variation, add explicit typed override
slots with their own validation and public visibility rather than generic JSON
patches.

### Transport and telephony boundary

The definition may declare requirements, remote MCP sources, and transfer
targets, but it should not contain live socket identifiers, carrier call IDs,
literal credentials, or provider webhook state. A single API payload may contain
both a definition and an invocation; the credential values still belong to the
invocation envelope rather than the reusable definition within it.

For the first version, one call maps to one room with multiple participants and
connections. Agent handoff changes conversational control inside that room.
Human or telephony transfer is an engine-owned tool/command that creates or
changes participant connections and call legs. A later warm-transfer workflow
may create a temporary consultation room, but that should not force multi-room
orchestration into the initial definition.

## Representative JSON shape

This is a discussion aid, not a committed schema:

```json
{
  "schema_version": 1,
  "entry_node": "triage",
  "context": {
    "fields": {
      "customer_id": {"type": "string", "source": "invocation"},
      "issue_kind": {"type": "string", "visibility": ["triage", "billing"]}
    }
  },
  "tool_sources": {
    "records": {
      "type": "remote_mcp",
      "profile": "records-production"
    }
  },
  "tools": {
    "lookup_customer": {
      "source": "records",
      "remote_name": "lookup_customer"
    },
    "lookup_invoice": {
      "source": "records",
      "remote_name": "lookup_invoice"
    }
  },
  "nodes": {
    "triage": {
      "type": "agent",
      "instructions": "Understand why the caller is contacting us.",
      "model": "fast-general",
      "voice": "default-voice",
      "tools": ["lookup_customer"]
    },
    "billing": {
      "type": "agent",
      "instructions": "Resolve billing questions.",
      "model": "careful-general",
      "voice": "default-voice",
      "tools": ["lookup_invoice"]
    },
    "complete": {
      "type": "end",
      "result": "completed",
      "disposition": "end_call"
    }
  },
  "edges": [
    {
      "name": "triage-to-billing",
      "from": "triage",
      "outcome": "billing",
      "to": "billing",
      "description": "Use after the caller's issue is confirmed to be billing-related.",
      "context": {
        "history": {"type": "last_n_spoken", "turns": 6},
        "fields": ["customer_id", "issue_kind"]
      }
    },
    {
      "name": "billing-complete",
      "from": "billing",
      "outcome": "resolved",
      "to": "complete",
      "description": "Use after the billing issue is resolved."
    }
  ],
  "policies": {
    "max_duration_ms": 1800000,
    "max_handoffs": 6,
    "on_agent_failure": "end_with_error"
  }
}
```

The corresponding invocation may override the application profile's
authentication without changing the call definition:

```json
{
  "definition": "support-call@7",
  "room_id": "room-123",
  "inputs": {
    "customer_id": "customer-456"
  },
  "authentication": {
    "records": {
      "type": "bearer",
      "token": "one-call-access-token"
    }
  }
}
```

The gateway must redact the authentication object as soon as it crosses the
trusted request boundary. It is shown here only to make the input shape and
override scope explicit; the value must never appear in returned JSON or
diagnostics.

Provider/profile strings are closed registry names resolved by the host. They do
not name Elixir modules. Instructions may later be replaced by immutable prompt
references without changing the runtime semantics.

## Alternatives considered

### Start with a fully expressive JSON graph

Rejected, but a minimal graph is accepted. A fully expressive graph front-loads
node taxonomy, expression semantics, parallelism, joins, compensation, graph
migration, and visual-editor concerns before Vxpipe can switch between two
agents. It also risks making the graph rather than the room the source of truth.

The initial graph has one cursor, typed outcomes, ordinary directed edges, and
only `agent` and `end` nodes. New node kinds require externally observable use
cases and focused tests. Higher-level flows compile into this representation and
do not need a separate executor in the room hot path.

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

Deferred with Lua. The first graph transition can be model-selected through a
temporary route tool or requested explicitly by the host. When deterministic
branching is needed, add the `branch` node with a small typed condition algebra
over declared context fields (`eq`, `in`, `exists`, `all`, `any`, `not`) rather
than conditions attached to generic edges or strings evaluated at runtime. This
remains serializable, validatable, and testable.

### Put provider credentials directly in each call definition

Rejected. Remote MCP sources and tool bindings are call behavior and therefore
belong in the definition, either through an inline endpoint or an application
profile reference. Literal credentials do not: embedding them makes reusable
definitions, revisions, inspection, and logging unsafe. Authentication belongs
in the invocation or the referenced application profile, with invocation
authentication taking precedence atomically. The compiler pins an opaque
credential lease rather than its value.

### Let application MCP configuration automatically expose tools

Rejected. Application configuration may make an integration and default
credential available, but the call definition remains the authority for the
source, tool binding, and per-agent grant. This keeps one call from inheriting
tools merely because another call or deployment happens to use the same MCP
server.

## Validation requirements

Compilation should reject, with path-specific errors:

- unsupported schema versions;
- an absent or unknown entry node;
- duplicate or invalid names;
- missing edge endpoints or an edge referencing an undeclared outcome;
- more than one edge for the same source-node outcome;
- tool or profile references not present in closed registries;
- an agent grant referencing an undeclared call-local tool;
- a tool binding referencing an unknown source or unresolved remote tool;
- an inline MCP source attempting to inherit authentication from an unrelated
  application profile;
- invocation authentication for a source not declared by the selected
  definition;
- forbidden or malformed custom authentication headers;
- context fields with unsupported types or invalid visibility grants;
- invocation defaults for undeclared fields;
- policies outside bounded ranges;
- a model-selectable route whose source node cannot request it;
- incompatible required capabilities; and
- any private runtime term or literal secret at the public boundary.

Cycles are not inherently invalid: callers may legitimately return to triage.
They require bounded node visits/transitions and session duration rather than an
acyclic graph rule. Unreachable nodes should initially be a compiler warning or
a lint error, not necessarily a runtime-invalid definition.

## Observable runtime contracts needed

The first multi-agent slice needs protocol-neutral events for:

- call plan resolved;
- graph started;
- node entered, outcome committed, edge traversed, and node exited;
- agent admitted and ready;
- agent activated and deactivated;
- handoff requested, accepted, completed, rejected, failed, and cancelled;
- context packet created and delivered, with values redacted by visibility;
- tool invocation lifecycle;
- routing changed; and
- call ended with a typed reason.

Only one agent may own conversational output for a connection/lane at a time.
Inactive agents must not consume participant turns or emit user-visible output.
Late results from a previously active agent must be rejected by incarnation,
turn, and activation identity.

## Suggested red-green checkpoints

1. **Definition and invocation data:** red tests for a minimal one-agent
   definition, remote MCP profile/inline sources, explicit tool bindings,
   per-agent grants, and invocation authentication limited to declared sources.
   Implement immutable structs and pure path-specific validation only.
2. **Resolution and authentication precedence:** use fake application profiles
   and a fake remote catalog to prove invocation authentication atomically
   replaces an application default, explicit `none` disables it, inline URLs
   cannot steal profile credentials, and missing requirements reject the call.
   Produce a secret-free `ResolvedCallPlan` plus private credential leases.
3. **Graph data contract:** test the entry node, `agent`/`end` nodes, declared
   outcomes, edge resolution, missing targets, duplicate routes, cycles, and
   path-specific errors.
4. **Graph reducer:** test enter, stay, outcome, transition, terminal, stale
   activation, and transition-budget behavior using a deterministic fake node;
   implement a pure reducer with one active cursor and activation ID.
5. **Behavior-preserving agent node:** prove a one-agent resolved plan produces
   the same text/audio turn behavior as the current preset path and that only
   its explicitly granted tool bindings reach model inference.
6. **JSON and gateway boundary:** round-trip definition/invocation data, reject
   unknown keys and dynamic atom creation, and prove credentials are absent from
   responses, errors, snapshots, and inspection output.
7. **Remote MCP execution:** behind the engine-owned tool backend, resolve one
   HTTPS MCP source, call one declared tool, preserve the existing room/RTVI
   lifecycle, and prove interruption cancels the remote request. Do not add
   stdio or an MCP server endpoint.
8. **Agent-to-agent edge:** use two deterministic agent nodes to prove only the
   active node receives turns, model-selectable routes are allowlisted, and stale
   output is rejected.
9. **Scoped transition context:** prove allowed spoken history and typed fields
   reach the destination while hidden fields, private tool data, credentials,
   and unplayed text do not.
10. **Later execution primitives:** add `action`, human transfer, `wait`, and
    `branch` only alongside their first concrete uses. Defer subgraphs,
    parallelism, joins, races, and scripting.

## Decision for the next checkpoint

Proceed first with typed `CallDefinition`, `CallInvocation`, and
`ResolvedCallPlan` contracts. Remote MCP sources, explicit tool bindings, and
per-agent grants are definition data. Literal one-call authentication is
invocation data and atomically overrides a registered application's default for
the same resolved source. Application configuration makes profiles available;
it does not add tools to a call.

The smallest proof is pure resolution using fake profiles and discovery: a
single-agent definition becomes a secret-free immutable plan whose tool surface
is exact and whose credential lease has the correct provenance. Do not begin an
MCP transport implementation until this boundary exists. Then route a
behavior-preserving single-agent call through the plan before connecting one
remote HTTPS MCP tool.

Retain the graph direction with one cursor, typed node outcomes, and directed
edges. Start with `agent` and `end`; do not start with Lua, arbitrary executable
hooks, natural-language edge evaluation, parallel graph execution, or a broad
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
- Reviewed the official MCP `2026-07-28` tool specification, Streamable HTTP
  transport, and generated schema:
  - <https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2026-07-28/server/tools.mdx>
  - <https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2026-07-28/basic/transports/streamable-http.mdx>
  - <https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/schema/2026-07-28/schema.json>
- No implementation or test commands were run because this checkpoint changes
  research documentation only.
