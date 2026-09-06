# Call definition design

Research date: 2026-09-05 UTC

## Goal

Define the smallest useful call-definition contract for Vxpipe: one reusable,
versionable, agent-first description that can start a single-agent call today
and grow into multi-agent calls, scoped context, transfers between agent and
human participants, tools, and telephony without forcing ordinary calls into a
general-purpose workflow language. Participant-control transfers are
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

### Use an agent-first public authoring model

The common path across the reviewed systems is not a graph. It is one reusable
agent, or a named set of focused agents with one initial entrypoint and explicit,
allowlisted participant handoffs. Graphs appear as a separate structured-flow
product or a code-level orchestration mechanism when deterministic sequencing
is actually needed.

The public `CallDefinition` should therefore be agent-first without assuming an
agent must own the room for its entire lifetime:

- one typed `entrypoint`, resolved from either an agent-definition reference or
  a trusted participant-destination reference;
- shared capability-profile defaults;
- a map of named agents;
- each agent's prompt, first-message behavior, capability overrides,
  and selected tools;
- typed invocation inputs and typed room context; and
- bounded call policies and references to artifact/event policies.

The agent name in the definition is a stable logical role, not a PID, runtime
participant ID, or activation ID. Entering an agent creates a fresh activation
that owns conversational control. Re-entering the same agent may reuse its
private history according to policy, but stale work from an earlier activation
must still be rejected.

An `agent_definition` entrypoint resolves within the definition's `agents` map
and materializes an agent participant. A `participant_destination` entrypoint
resolves through trusted application or tenant destination configuration and
may produce a human or agent participant. The latter permits an initially
human-only call and an empty agent map; an empty agent map is invalid when any
entrypoint or transfer names an agent definition.

`Participant` is the room-level runtime identity. Its `kind` may be `human` or
`agent`. An agent in the call definition is reusable configuration; when the
room admits an instance of it, that instance is a participant with
`kind: agent`. A person working in a support role may be called an agent by the
surrounding business, but remains a participant with `kind: human` in the
engine's type system.

Transfer is an engine-owned platform tool with typed target selectors. Each
agent definition receives only the target-specific transfer bindings it is
allowed to request. An `agent_definition` selector pins definition-local
configuration that will be admitted as an agent participant. A
`participant_destination` selector pins an allowlisted logical destination,
which the host may resolve to a human or agent participant. These are resolution
paths, not sibling runtime identity types. Model-facing arguments must not accept
arbitrary runtime participant IDs, telephone numbers, or transport destinations.

Each configured transfer tool can carry a model-facing description, context
policy, and presentation policy. This gives the model a typed request surface
while the room authority validates and commits the actual control mutation.

### Track active control directly; do not introduce a graph

The room already has the state needed for participant transfers. The
resolved plan needs an entrypoint, named agent specs, and resolved tool bindings,
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

The definition declares named top-level context sections. Each section has a
schema and optional safe default. Invocation input or authoritative tools may
initialize sections only through separately declared rules. Typed facts should
not be re-extracted from a transcript when an authoritative invocation value or
tool result already exists.

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

An agent never mutates the map directly. A write grant causes the engine to
offer a platform-owned context-update tool constrained to that agent's writable
sections. The room authority validates the active agent, section permission,
payload schema, and current room incarnation before applying an update and
emitting its event. MCP results do not update room context implicitly; an
explicit tool-result mapping or authorized context update must request it.

A participant-transfer packet is an immutable projection of allowed room-context
sections plus the selected spoken-history policy. It names the concrete source
and destination participant identities and kinds, reason, causation, and
visibility. When an agent participant is the destination, its projection is
further constrained by that agent definition's context permissions. It is an
event/result, not a second mutable context bag. Client and human-participant
access to room context uses separate authenticated permissions rather than
inheriting an agent definition's grants.

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

### A transfer may change the room's capability topology

A transfer declares its desired resulting participant topology and the
requirements that must hold at commit. It does not declare imperative
`on_success` callbacks. A source disposition such as `detach` is part of the
atomic transfer result, while capability states such as `ready` or `stopped` are
commit requirements that the coordinator must satisfy before reporting success.

The resolved transition combines capability requirements from four trusted
sources:

- the destination agent definition's required capability profile;
- the participant destination's application- or tenant-configured policy;
- stricter requirements declared by the transfer binding; and
- room/application policy that applies independently of the definition.

No source can weaken another source's constraint. Incompatible requirements
reject plan resolution or the transfer. Thus an agent-to-agent transfer can
require the destination's speech, inference, and speech-output capabilities to
be ready, while a destination policy for a human-only segment can require
speech recognition and synthesis to be stopped.

The room authority runs a transfer in prepare and commit phases. During prepare,
it resolves or admits the destination and may keep the source participant and
its current capabilities active; this permits announcements, data collection,
and a warm handoff. Once the destination is ready, the coordinator satisfies
the merged commit requirements against the proposed resulting participant set.
Only then does it atomically change control/routing, apply the source
disposition, and emit `transfer.completed`.

The initial `CallDefinition` therefore has no generic `on_success` field. Host
code can observe `transfer.completed`, and a later deterministic workflow can
model an explicit next action if a real use case requires one. Neither is part
of the transfer's safety-critical commit transaction.

When a stopped state is a privacy boundary, it is a commit barrier rather than
best-effort cleanup. The room makes the capability ineligible for new frames,
immediately cancels queued/in-flight work, and waits for a bounded stop
acknowledgement before completing or unhiding the human-only bridge. A failed or
timed-out requirement follows the transfer's failure policy without changing
control or routing. Graceful draining is inappropriate because it could publish
buffered transcription or speech after the boundary.

Generation and activation checks reject late transcription, inference, or
speech output from capabilities that belonged to the earlier state. Stopping
speech-to-text or text-to-speech means closing the provider work and preventing
new input, not merely hiding client events.

This allows a call to begin with an agent participant, admit a human participant
during a warm transfer, detach the source agent participant after the bridge
succeeds, and continue with two human participants. A later explicit,
authorized command may restart a stopped capability if policy permits it;
transfer completion must not restart one implicitly.

Recording, analytics, and export are separate capabilities. Stopping speech
recognition and synthesis does not claim to stop those other data paths, so a
private or regulated segment must name every capability its policy requires the
room to stop.

### Definition version, deployment selection, and invocation are different

The reviewed control planes support stored and inline definitions, drafts,
published revisions, explicit version selection, and environment aliases. These
are useful control-plane features but should not complicate the first engine
contract.

The public schema identifier is a fixed-width string in `YYYYMMDD.NN` form. The
date is the UTC publication date of that schema and `NN` is the two-digit schema
release sequence for that date, beginning at `01`. The initial proposed value is
`"20260906.01"`. Every published schema shape receives a new identifier;
compatible and incompatible evolution is determined by a schema registry and
explicit decoder/migration rules, not by interpreting the identifier as semantic
versioning. Unknown identifiers are rejected.

Schema identity is independent from the revision of a stored call definition.
For example, revision `7` of one definition may still use schema
`"20260906.01"`. RTVI protocol versions, provider API versions, integration
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
CallDefinition.Agent
CallDefinition.CapabilitySelection
CallDefinition.RoomContext
CallDefinition.ContextSection
CallDefinition.ContextPermissions
CallDefinition.Policy
CallDefinition.AgentIntegration
CallDefinition.AgentToolBinding
CallDefinition.TransferTool
CallDefinition.CapabilityEffect
CallInvocation
ResolvedCallPlan
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

### Minimal initial `CallDefinition`

The initial dated schema should contain only:

- `schema_version` as a `YYYYMMDD.NN` string;
- optional display metadata, while durable ID and revision stay in the resource
  envelope;
- a typed `entrypoint`;
- shared capability-profile defaults;
- named inline `agents`;
- typed invocation-input and room-context schemas;
- shared call policies for turns, interruption, limits, failure, and ending; and
- artifact/event policy references.

Each agent should contain:

- a stable definition-local name;
- an inline prompt or versioned prompt-profile reference;
- optional capability-profile overrides;
- first-message behavior;
- MCP integrations enabled for this agent and stable agent-local bindings for
  the selected remote tools;
- engine-owned tool grants;
- room-context permissions by top-level section;
- input, output, and action-guardrail policy references;
- optional limits stricter than the call defaults.

An engine-owned transfer-tool binding should contain:

- a stable name within the source agent;
- platform tool kind `transfer`;
- a typed target selector containing either a fixed definition-local
  `agent_definition` reference or an allowlisted logical
  `participant_destination` reference;
- a model-facing description of when the transfer is appropriate;
- optional context/history transfer policy when the destination is an agent
  participant; and
- a typed transition policy containing its handoff mode, source disposition,
  user-visible speech policy, and capability requirements for commit.

The room checks that the source participant is current and, for an agent
participant, that its activation is current. It also checks that the target is
allowlisted and ready and that transfer budgets are not exhausted. A host
command can request the same declared transfer without giving the model
authority over the room mutation.

The initial schema should keep agents inline so one call definition is portable
in the standalone JSON configuration and resolves without a dependency graph. A
later control plane may offer reusable agent resources and allow a definition
to pin one by ID and revision, but it must compile that reference into the same
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

## Representative JSON shape

This is a discussion aid, not a committed schema:

```json
{
  "schema_version": "20260906.01",
  "name": "customer-support",
  "entrypoint": {
    "type": "agent_definition",
    "ref": "reception"
  },
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
    }
  },
  "agents": {
    "reception": {
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
        },
        "transfer_to_billing": {
          "type": "platform",
          "tool": "transfer",
          "target": {"type": "agent_definition", "ref": "billing"},
          "description": "Use when the caller needs help with a billing issue.",
          "context": {
            "history": {"mode": "last_n_spoken", "turns": 6},
            "sections": ["customer", "intake"]
          }
        },
        "transfer_to_person": {
          "type": "platform",
          "tool": "transfer",
          "target": {"type": "participant_destination", "ref": "support_queue"},
          "description": "Use when the caller asks to speak with a person.",
          "transition": {
            "mode": "warm",
            "source_disposition": "detach",
            "commit_requirements": {
              "capabilities": [
                {
                  "participants": {"kind": "human"},
                  "states": {
                    "speech_to_text": "stopped",
                    "text_to_speech": "stopped"
                  }
                }
              ]
            }
          }
        }
      }
    },
    "billing": {
      "prompt": "Resolve billing questions.",
      "capabilities": {
        "model_inference": "careful-general"
      },
      "first_message": {"mode": "generated"},
      "context_permissions": {
        "customer": ["read"],
        "intake": ["read", "write"]
      },
      "tools": {}
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
behavior. `support_queue` is a logical destination resolved through trusted
application or tenant configuration; it is not a runtime participant ID or a
model-supplied address. The target and transition requirements are trusted tool
configuration; the model only supplies arguments allowed by the resolved tool
schema. An agent with a `write` context grant receives a platform context-update
tool restricted to those named sections.

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
- an absent, malformed, or unresolved entrypoint;
- duplicate or invalid names;
- an `agent_definition` selector naming an unknown definition-local agent;
- a transfer tool with an unknown or disallowed destination;
- a participant destination that cannot be resolved within the authenticated
  application or tenant scope;
- participant-destination metadata with an unsupported allowed participant kind;
- a transition with an unknown mode, source disposition, participant selector,
  capability kind, or required state;
- incompatible capability commit requirements after merging the agent,
  destination, transfer-binding, and room/application policies;
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
- an agent context permission naming an unknown section or permission other
  than `read` or `write`;
- a transfer context projection containing a section the destination cannot
  read;
- invocation defaults for undeclared fields;
- policies outside bounded ranges;
- a model-selectable transfer whose source agent lacks that tool grant;
- incompatible required capabilities; and
- any private runtime term or literal secret at the public boundary.

Transfer cycles are not inherently invalid: callers may legitimately return to
the entrypoint's agent participant. They require bounded transfers and session
duration. Unreachable agents should initially be a compiler warning or a lint
error, not necessarily a runtime-invalid definition.

At runtime, destination resolution must produce a concrete participant ID and a
supported `human` or `agent` kind before the room commits the transfer. A missing
identity, a kind mismatch, or a stale source participant/activation rejects the
operation without changing control or routing.

## Observable runtime contracts needed

The first multi-agent slice needs protocol-neutral events for:

- call plan resolved;
- agent participant admitted and ready;
- agent participant activated and deactivated;
- participant transfer requested, accepted, completed, rejected, failed, and
  cancelled, including source and destination participant IDs and kinds;
- capability commit requirement evaluated, state transition requested, state
  reached, acknowledged, timed out, or failed;
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
   definition, typed entrypoint selection, dated schema validation, shared
   capability defaults, agent overrides, input validation, and a credential-free
   invocation. Implement immutable structs and pure path-specific validation
   only.
2. **Basic plan resolution:** use fake closed capability-profile registries to
   prove defaults and overrides resolve into a self-contained, secret-free
   `ResolvedCallPlan`; unused profiles leave no runtime binding.
3. **Room-context contract:** test typed top-level sections, per-agent read/write
   grants, model-visible read projection, authorized writes, schema rejection,
   section revisions, and absence of ungranted sections.
4. **Agent and transfer-tool data:** test `agent_definition` and
   `participant_destination` selector resolution, missing targets, participant
   kinds, duplicate names, transfer cycles, unreachable-agent linting, and
   path-specific errors.
5. **Active-agent-participant reducer:** test activation, agent-to-agent and
   agent-to-human participant transfer, `active_agent_participant_id: nil`,
   terminal state, stale activation, and transfer-budget behavior using
   deterministic fake participants; implement a pure reducer with one optional
   active agent participant and activation ID.
6. **Behavior-preserving agent:** prove a one-agent resolved plan produces
   the same text/audio turn behavior as the current preset path.
7. **Human-only transfer:** prove a human participant joins during prepare while
   the source agent remains usable, commit requirements then make selected
   capabilities reject new frames and cancel queued work, commit waits for stop
   acknowledgement, and the source detaches only when the room can remain alive
   safely with human participants and no active agent participant.
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
   participants and one engine-owned transfer tool to prove only the active
   agent participant receives turns, the destination's required capabilities
   are ready before commit, targets are allowlisted, and stale output is
   rejected.
12. **Scoped transition context:** prove allowed spoken history and typed fields
   reach the destination while hidden fields, private tool data, credentials,
   and unplayed text do not.
13. **Later workflow surface:** add deterministic `action`, human transfer,
    `wait`, and `branch` behavior only alongside its first concrete use. Do not
    assume a graph, subgraph, parallel-branch, join, or race model.

## Decision for the next checkpoint

Proceed first with typed `CallDefinition`, `CallInvocation`, and
`ResolvedCallPlan` contracts without MCP fields in the first proof. The smallest
proof is an inline one-agent definition using schema `"20260906.01"`, an
`agent_definition` entrypoint, shared capability-profile defaults, declared
invocation inputs, typed room-context sections, per-agent section permissions,
and bounded limits becoming a self-contained immutable plan. Route the existing
single-agent behavior through that plan before adding transfer tools or
integration resolution.

Remote MCP integrations still live in application or tenant catalogs, where
they are **configured**. Individual agents explicitly **enable** integrations
and bind selected tools to agent-local names. MCP endpoints and credentials are
neither definition nor invocation data. A tenant integration atomically takes
precedence over an application-wide integration with the same stable ID; neither
catalog enables it for any agent automatically. Do not begin an MCP transport
implementation until the general call-definition boundary exists.

Use the agent-first public input with one typed entrypoint and agent-scoped tools.
The private plan contains resolved agent specs and tool bindings; it does not
contain generic nodes or edges. The room directly owns participant routing and
the optional active agent participant, and a running room may have no agent
participant. Platform tools include at least `hangup`, `transfer`, and the
permission-constrained room context update operation. A participant transfer
may declare capability-state commit requirements before leaving a human-only
room. Do not start with Lua,
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
  date-based `YYYYMMDD.NN` format; the current proposal is `"20260906.01"`.
  `entrypoint` is a typed initial handler, participant-control transfers are
  engine-owned tools, a room may continue without an active agent participant,
  and neither the public definition nor resolved plan uses generic nodes or
  edges.
- Clarified the runtime identity model: every room member is a participant whose
  kind is `human` or `agent`; an agent definition materializes an agent
  participant. Transfer target selectors describe how to resolve a destination,
  while the room always commits a transfer between concrete participants. This
  includes an intake agent participant transferring control to a human service
  agent participant.
- Corrected transfer timing: there is no generic `on_success` action bag. A
  transfer prepares its destination, merges required capability states from
  agent, destination, binding, and room/application policies, satisfies them as
  bounded commit barriers, and only then changes routing and applies the source
  disposition. This supports both capabilities required as `ready` for an agent
  destination and capabilities required as `stopped` for a human-only segment.
- Added room-owned typed context sections with per-agent `read`/`write` grants.
  Top-level section grants are the initial contract; nested dot-path and wildcard
  permissions are deferred.
- Reviewed the official MCP `2026-07-28` tool specification, Streamable HTTP
  transport, and generated schema:
  - <https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2026-07-28/server/tools.mdx>
  - <https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2026-07-28/basic/transports/streamable-http.mdx>
  - <https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/schema/2026-07-28/schema.json>
- No implementation or test commands were run because this checkpoint changes
  research documentation only.
