# Call definition design

Research date: 2026-09-05 UTC

## Goal

Define the smallest useful call-definition contract for Vxpipe: one reusable,
versionable, agent-first description that can start a single-agent call today
and grow into multi-agent calls, scoped context, agent handoffs, human
transfers, tools, and telephony without forcing ordinary calls into a
general-purpose workflow language. A private resolved plan may use a graph
internally, and an explicit workflow authoring surface can be added later.

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

### Use an agent-first public authoring model

The common path across the reviewed systems is not a graph. It is one reusable
agent, or a named set of focused agents with one entry agent and explicit,
allowlisted handoffs. Graphs appear as a separate structured-flow product or a
code-level orchestration mechanism when deterministic sequencing is actually
needed.

The public `CallDefinition` should therefore be agent-first:

- one `entry_agent`;
- shared capability-profile defaults;
- a map of named agents;
- each agent's instructions, first-message behavior, capability overrides,
  selected tools, and handoffs;
- typed invocation inputs and typed session state; and
- bounded call policies and references to artifact/event policies.

The agent name in the definition is a stable logical role, not a PID, runtime
participant ID, or activation ID. Entering an agent creates a fresh activation
that owns conversational control. Re-entering the same agent may reuse its
private history according to policy, but stale work from an earlier activation
must still be rejected.

An agent's `handoffs` are a named allowlist. Each handoff declares a destination,
a model-facing description of when it is appropriate, the context-transfer
policy, and optional presentation behavior. This is easier to author and review
than separate node and edge collections while preserving an exact directed
topology.

### Keep graphs as a private plan and a later advanced surface

A graph still has value for runtime compilation and future deterministic
workflows. The compiler can lower each agent to an internal agent node and each
handoff to an internal edge. The initial runtime needs only one active cursor:

```text
activate entry agent
  -> agent converses or requests an allowlisted handoff
  -> room authority commits the transition
  -> previous activation becomes stale
  -> activate destination agent or end the call
```

That private plan must not become a second copy of room state. The room remains
authoritative for participants, connections, media, turns, tools, typed context,
and call legs. Provider requests and tool execution remain concurrent supervised
work, while the conversational-control cursor is singular.

If a concrete use case later requires guaranteed sequencing, deterministic
branching, waiting, joins, or compensation, add a separate explicit workflow
authoring surface which compiles into the same private plan. Do not make every
ordinary call author understand `agent`, `action`, `wait`, `branch`, and `end`
node kinds merely so two agents can hand off to one another.

This separation also avoids conflating three different concepts:

- a **tool** is a model-selectable typed operation available to an active agent;
- a **task** is a bounded conversational subroutine that returns typed data and
  then yields control; and
- a **workflow** is deterministic orchestration across conversational and
  non-conversational steps.

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
- A call invocation owns caller/destination identity, entrypoint, definition
  selection, permitted runtime variables, and idempotency. It carries no MCP
  authentication.
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
CallDefinition.Agent
CallDefinition.Handoff
CallDefinition.CapabilitySelection
CallDefinition.Context
CallDefinition.Policy
CallDefinition.AgentIntegration
CallDefinition.AgentToolBinding
CallInvocation
ResolvedCallPlan
ResolvedCallPlan.Graph
ResolvedCallPlan.Node
ResolvedCallPlan.Edge
ResolvedCallPlan.Agent
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

### Minimal `CallDefinition` v1

The first version should contain only:

- `schema_version`;
- optional display metadata, while durable ID and revision stay in the resource
  envelope;
- `entry_agent`;
- shared capability-profile defaults;
- named inline `agents`;
- typed invocation-input and session-state schemas;
- shared call policies for turns, interruption, limits, failure, and ending; and
- artifact/event policy references.

Each agent should contain:

- a stable definition-local name;
- instructions or a versioned prompt-profile reference;
- optional capability-profile overrides;
- first-message behavior;
- MCP integrations enabled for this agent and stable agent-local bindings for
  the selected remote tools;
- engine-owned tool grants;
- input, output, and action-guardrail policy references;
- named handoffs to other agents; and
- optional limits stricter than the call defaults.

Each handoff should contain:

- a stable name within the source agent;
- the destination agent;
- a model-facing description of when the route is appropriate;
- optional context/history transfer policy for an agent-to-agent transition;
  and
- optional user-visible transition speech policy.

The compiler can turn model-selectable handoffs into engine-owned route tools
granted only during the source agent's activation. The room checks that the
source activation is still current, the target exists and is ready, and
handoff budgets are not exhausted. A host command can request the same declared
handoff without giving the model authority over the room mutation.

Version one should keep agents inline so one call definition is portable in the
standalone JSON configuration and resolves without a dependency graph. A later
control plane may offer reusable agent resources and allow a definition to pin
one by ID and revision, but it must compile that reference into the same
self-contained immutable plan before the room starts.

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

An agent handoff changes the effective tool surface. Before deactivating the
source activation, its in-flight tool calls must be settled or cancelled. After
the transition, source-agent bindings cannot accept new calls, and only the
destination activation's bindings enter model requests. Tool results and events
carry agent and activation identity so a late result from the previous agent is
rejected even when both agents use the same configured integration.

The public engine boundary should accept a definition (or immutable definition
reference) plus an invocation. The current `CreateRoom` command remains a lower
level engine command and should eventually receive only a resolved-plan identity
or typed plan, never decoded call JSON or credentials.

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
  "name": "customer-support",
  "entry_agent": "reception",
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
  "agents": {
    "reception": {
      "instructions": "Understand why the caller is contacting us and route the conversation.",
      "first_message": {"mode": "generated"},
      "handoffs": {
        "to_billing": {
          "to": "billing",
          "description": "Use when the caller needs help with a billing issue.",
          "context": {
            "history": {"mode": "last_n_spoken", "turns": 6},
            "inputs": ["customer_id"]
          }
        }
      }
    },
    "billing": {
      "instructions": "Resolve billing questions.",
      "capabilities": {
        "model_inference": "careful-general"
      },
      "first_message": {"mode": "generated"},
      "handoffs": {}
    }
  },
  "limits": {
    "max_duration_ms": 1800000,
    "max_handoffs": 6
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
behavior.

Provider/profile strings are closed registry names resolved by the host. They
do not name Elixir modules. Instructions may later be replaced by immutable
prompt references without changing the runtime semantics. Agent-scoped tools,
knowledge, guardrails, MCP enablement, and artifact-policy references fit into
this shape without changing its basic entry-agent and handoff model, but they
should be specified in separate focused checkpoints.

## Alternatives considered

### Start with a fully expressive JSON graph

Rejected as the initial public authoring contract. A fully expressive graph
front-loads node taxonomy, expression semantics, parallelism, joins,
compensation, graph migration, and visual-editor concerns before Vxpipe can
switch between two agents. Even a minimal public `agent`/`end` graph makes the
common case less direct than an entry agent with named handoffs and risks making
the graph rather than the room the source of truth.

An internal graph remains a useful compiled representation. A separate advanced
workflow surface may later expose deterministic nodes and edges when a concrete
use case justifies them; it must compile into the same plan and room authority
rather than introduce a second executor.

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

Deferred with Lua. An agent handoff can be model-selected through an engine-owned
route tool or requested explicitly by the host. When deterministic branching is
needed, add it to the explicit workflow surface with a small typed condition
algebra over declared context fields (`eq`, `in`, `exists`, `all`, `any`,
`not`) rather than putting natural-language expressions into ordinary handoffs.
This remains serializable, validatable, and testable.

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

- unsupported schema versions;
- an absent or unknown entry agent;
- duplicate or invalid names;
- a handoff with an unknown destination;
- duplicate handoff names within one source agent;
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
- context fields with unsupported types or invalid visibility grants;
- invocation defaults for undeclared fields;
- policies outside bounded ranges;
- a model-selectable handoff whose source agent cannot request it;
- incompatible required capabilities; and
- any private runtime term or literal secret at the public boundary.

Cycles are not inherently invalid: callers may legitimately return to the entry
agent. They require bounded handoffs and session duration rather than an
acyclicity rule. Unreachable agents should initially be a compiler warning or a
lint error, not necessarily a runtime-invalid definition.

## Observable runtime contracts needed

The first multi-agent slice needs protocol-neutral events for:

- call plan resolved;
- agent admitted and ready;
- agent activated and deactivated;
- handoff requested, accepted, completed, rejected, failed, and cancelled;
- context packet created and delivered, with values redacted by visibility;
- tool invocation lifecycle;
- routing changed; and
- call ended with a typed reason.

Only one agent may own conversational output for a connection/lane at a time.
Inactive agents must not consume participant turns or emit user-visible output.
They also must not advertise or invoke their MCP tools. A transition cancels or
settles the source activation's outstanding tool work before enabling the
destination activation's tool surface.

Late results from a previously active agent must be rejected by incarnation,
turn, and activation identity.

## Suggested red-green checkpoints

1. **Definition and invocation data:** red tests for a minimal one-agent
   definition, entry-agent selection, shared capability defaults, agent
   overrides, input validation, and a credential-free invocation. Implement
   immutable structs and pure path-specific validation only.
2. **Basic plan resolution:** use fake closed capability-profile registries to
   prove defaults and overrides resolve into a self-contained, secret-free
   `ResolvedCallPlan`; unused profiles leave no runtime binding.
3. **Agent and handoff data:** test handoff
   resolution, missing targets, duplicate names, cycles, unreachable-agent
   linting, and path-specific errors.
4. **Active-agent reducer:** test activation, handoff, terminal state, stale
   activation, and handoff-budget behavior using deterministic fake agents;
   implement a pure reducer with one active cursor and activation ID.
5. **Behavior-preserving agent:** prove a one-agent resolved plan produces
   the same text/audio turn behavior as the current preset path.
6. **JSON and gateway boundary:** round-trip definition/invocation data, reject
   unknown keys, dynamic atom creation, arbitrary runtime overrides, credentials,
   and tenant overrides.
7. **Integration resolution:** use fake application and tenant integration
   catalogs to prove tenant lookup comes from the authenticated principal, a
   tenant integration atomically replaces the application-wide integration,
   only agent-enabled tools reach model inference, unavailable tools reject the
   call, and no state crosses tenant boundaries. Produce private credential
   leases outside the public plan.
8. **Remote MCP execution:** behind the engine-owned tool backend, configure one
   HTTPS MCP integration, enable one tool on one agent, call it, preserve
   the existing room/RTVI lifecycle, and prove interruption or agent handoff
   cancels the remote request. Do not add stdio or an MCP server endpoint.
9. **Agent handoff:** use two deterministic agents to prove only the active
   agent receives turns, model-selectable routes are allowlisted, and stale
   output is rejected.
10. **Scoped transition context:** prove allowed spoken history and typed fields
   reach the destination while hidden fields, private tool data, credentials,
   and unplayed text do not.
11. **Later workflow surface:** add deterministic `action`, human transfer,
    `wait`, and `branch` steps only alongside their first concrete uses. Defer
    subgraphs, parallelism, joins, races, and scripting.

## Decision for the next checkpoint

Proceed first with typed `CallDefinition`, `CallInvocation`, and
`ResolvedCallPlan` contracts without MCP fields in the first proof. The smallest
proof is an inline one-agent definition with an entry agent, shared capability
profile defaults, declared invocation inputs, and bounded limits becoming a
self-contained immutable plan. Route the existing single-agent behavior through
that plan before adding multi-agent handoffs or integration resolution.

Remote MCP integrations still live in application or tenant catalogs, where
they are **configured**. Individual agents explicitly **enable** integrations
and bind selected tools to agent-local names. MCP endpoints and credentials are
neither definition nor invocation data. A tenant integration atomically takes
precedence over an application-wide integration with the same stable ID; neither
catalog enables it for any agent automatically. Do not begin an MCP transport
implementation until the general call-definition boundary exists.

Use the agent-first public input with one entry agent and named handoffs. Compile
it into a private one-cursor plan; do not expose generic nodes and edges in the
initial JSON. Do not start with Lua, arbitrary executable hooks,
natural-language condition evaluation, parallel graph execution, or a broad
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
- Reviewed the official MCP `2026-07-28` tool specification, Streamable HTTP
  transport, and generated schema:
  - <https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2026-07-28/server/tools.mdx>
  - <https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2026-07-28/basic/transports/streamable-http.mdx>
  - <https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/schema/2026-07-28/schema.json>
- No implementation or test commands were run because this checkpoint changes
  research documentation only.
