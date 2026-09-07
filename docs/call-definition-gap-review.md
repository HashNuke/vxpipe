# Call-definition gap review

Reviewed: 2026-09-06 UTC
Last updated: 2026-09-07 UTC
Status: G1 and G2's web routes, initial context, API-key admission with one-way
hash storage, single-use tokens with existing-call recovery and no automatic
call-record expiry, prepared token-join or direct-backend connection, explicit
entry participants/startup, and one participant per definition key per call approved;
G3 initialization approved with no context defaults, and submitted context
updates continue through conversational interruption under existing checks.
Reads containing a forbidden section fail with a permission error and no values.
Object updates recursively merge objects and preserve omitted nested fields;
shallow sections are preferred. Explicit null clears nullable fields without
deleting their keys; physical deletion is deferred. Context root keys name
sections, direct section keys name fields, and the field tool uses literal names.
Unpopulated authorized reads return a single null at the requested value level,
without nested placeholders or stored defaults. Updates populate context
iteratively: datatype checks remain, but required-field completeness is not
validated at setup or on updates.
Agent section grants are read-only or read+write, never write-only. Every writer
can read its section; omitted grants give no access. The write-only projection
and error-handling proposals are withdrawn.
Final naming remains open for the object/field tools;
remaining G2/G3 questions and G4–G13 pending review.
Record creation and actual live-call start have distinct approved timestamps.
Documentation only; no runtime implementation.

Review count: **12 open numbered groups** — G2 and G3 partly resolved, G4–G13
awaiting approval; G1 resolved in documentation. Individual sub-decisions are
not counted separately here. Object merge versus replacement and preservation of
omitted nested fields, explicit-null clearing, direct-field addressing, missing
reads, and iterative population without required-field checks are
resolved within G3; its other questions remain open, so the group count has
not changed. The read-only/read+write decision removes the write-only error
question without closing the remaining G3 group.

## Conclusion and scope

Keep the participant-first definition, `entry_caller` and `entry_receiver`,
direct `transfers` ref lists, agent-scoped tool enablement, room-owned context,
and immutable resolved plan. The scenarios below do not require nodes, edges,
named transfers, or a general expression language. The missing pieces are mostly enforceable runtime
contracts around those primitives, not a different top-level JSON structure.

This reviews the [call-definition labnote][design] and
[runtime architecture][architecture] at Vxpipe commit
`e7a769e0ce4ec3cc0bb39faf300f759f125d9c4e`. Source inspection confirms that
`CreateRoom` still selects a preset, not a call definition; tools are trusted
Elixir modules; there is no definition compiler, room context, remote MCP client,
telephony transfer, database adapter, or room mixer implementing the proposal.
“Design fit” below must not be read as “works in today's playground.”

The external comparison uses all four assistant directories in
[VapiAI/examples at a pinned revision][examples], commit
`242a4ef9ac720c3ce000e1635f5197768f6e9945`. Reviewed assistant JSON, tool JSON,
the instruction handler, scheduling workflow structure, and accompanying
READMEs. No example endpoint was called, example code executed, workflow deployed,
SMS sent, or recording evaluated. The GitOps submodule was not audited. These are
integration examples, not proof that every advertised behavior is enforced.

## Scenario fit

| Scenario and concrete evidence | What our design can express | Missing work or limitation |
| --- | --- | --- |
| Scheduling: [assistant][scheduling], [booking tool][booking], [external workflow][workflow] | Agent prompt, scoped context, enabled calendar tools, transfer to a human, hangup | The supplied tools use function webhooks, not MCP. They need a remote MCP facade or trusted host adapter. Define action confirmation, idempotency, timeout/unknown outcomes, result-to-context authority, and timezone bindings. The external scheduling system remains the booking authority. |
| Intent routing: [assistant][intent], [request overrides][intent-request], [instruction handler][instructions] | One agent retrieves instructions through a tool; alternatively several specialized agent definitions transfer by ref | Define typed personalization and trusted ingress metadata, provenance of retrieved instructions, and closed participant destinations. Runtime text must not grant tools or introduce arbitrary telephone destinations. |
| Voicemail: [assistant][voicemail], [native voicemail tool][voicemail-tool] | Outbound human connection intent, agent first-message policy, platform ending tool | Waiting for the other party, answer classification, optional beep evidence, delivery deadline, and speak-then-end are runtime behavior, not solved by a prompt alone. |
| SMS verification: [assistant][sms], [code tool][code], [SMS tool][sms-tool] | Agent-scoped remote tools, typed verification context, provider-neutral external action | Requires an external verification service or trusted host implementation. Verification truth, expiry, attempt limits, recipient binding, and replay protection must not be writable by the model. Do not run JSON-provided JavaScript. |

Two distinctions matter when using these sources:

- The intent handler returns instruction strings; it is not itself a retrieval
  engine or business-action executor. Some returned scripts claim a report was
  submitted without a corresponding submission tool in that assistant's tool
  list. Our acceptance test must check an actual operation receipt, not spoken
  confirmation. Its README, instruction strings, and tool JSON also use
  differing tool names; it is not a directly importable compatibility fixture.
  [Handler][instructions], [assistant][intent], [lookup tool][instruction-tool].
- The SMS code tool uses `Math.random()` and returns the code to the model; the
  assistant prompt performs comparison and retry handling. This demonstrates a
  conversational flow, not authoritative authentication. We should preserve the
  user experience while changing who owns verification. [Code][code],
  [assistant][sms].

## Findings and proposed solutions

Priorities indicate implementation gates, not a demand to build everything now:
P1 blocks the corresponding first compiler/private-context/external-action slice;
P2 is required before claiming the relevant telephony or archive feature.

### G1 — Resolved in documentation: one agent tools map

At the review baseline, the MCP example used an `agents` root and nested
`integrations.<alias>.tools`, while the representative definition used
`participants` and direct MCP bindings in `tools`. The two examples also granted
`billing` different access to `intake`. They did not describe one grammar.

Approved resolution: each agent has a unified `tools` map for built-in, MCP, and
registered host bindings. The map key is the model-visible name; `type` selects
the backend. An MCP entry names `integration` and `tool`; a built-in entry names
`type: platform` and `tool`. Integration configuration, credentials, availability,
and allowed operations remain at application/tenant scope. The agent selects
individual tools, without a separate integration-enablement block. This replaces
the review's original proposal to keep MCP bindings in a separate block.

For example, `tools.lookup_customer` can select the `lookup_customer` operation
from the configured `records` integration beside `tools.end_call`, which selects
the platform `hangup` operation. Configuring `records` does not expose all its
operations to every agent. The compiler resolves the selected tools against the
appropriate catalog and policy. [Updated tool example][mcp-design],
[representative JSON][json-design].

The examples now use `participants.<ref>.type: agent` and consistently give
`billing` read-only `intake` access. Transfer/context tools remain derived from
their existing grants; tool aliases must not collide with generated names.

G1's authoring ambiguity is resolved, but no compiler was implemented. A future
compiler checkpoint still needs canonical positive/negative fixtures and a
supported-field/keyword matrix. Partial illustrations are not complete executable
definitions, and the broad representative JSON is not a commitment to implement
every field in the first slice. No new dated schema release is published here.

### G2 — Partly resolved: admission, authentication, and entry roles approved

At baseline, `transport.type: web` did not map an incoming connection to a
participant definition. The original `entrypoint` identified only the initial
handler, not necessarily that connection's human participant. The approved
entry-role refinement below makes both initial participants explicit.

Approved routing: create tenant-scoped participant connection keys as routing
metadata, with separate HTTPS operations to prepare, join, and issue fresh tokens
for an existing call record:

```http
POST /api/tenants/{tenant_key}/participants/{participant_key}/calls
POST /api/tenants/{tenant_key}/calls/{call_id}/participants/{participant_key}/sessions
POST /api/tenants/{tenant_key}/calls/{call_id}/participants/{participant_key}/join-tokens
```

Use a 16-character cryptographically random URL-safe tenant key, UUID participant
connection keys, and UUID call IDs, separate from database primary keys. The
preparation route selects a deployment/definition and initiating participant,
which must match that definition's `entry_caller`; it stores the pinned plan and
context and returns a scoped join token without starting the room. A join route
must identify the particular tenant and call and resolve the participant using
that call's pinned definition.
It cannot choose a call from a reusable support key alone. Authorization precedes
issuing the call-specific transport session.
The `join-tokens` route is backend-only and API-key-authenticated, with no CORS
grants. It issues for an authorized participant in an existing prepared or live
call record, not a newly created call, and does not itself start a room. The
separate browser-facing join operation consumes the token.
WebRTC is the first browser transport; routing can also serve a future WebSocket
adapter. These are generic gateway handlers backed by route records, not code
or room processes created for every saved definition. See the
[approved web admission contract][web-admission]. No runtime implementation was
authorized by this documentation decision.

**Approved entry roles and startup:** replace `entrypoint` with `entry_caller`
and `entry_receiver`. Both are required string refs to different existing keys
in the same `participants` map; neither embeds a participant definition. The
caller stays in the catalog with the receiver and possible transfer targets.
Validate refs when parsing/saving the definition and retain resolved refs in the
pinned call plan. The benefit is explicit intent, not an assumption that runtime
must otherwise repeatedly scan the catalog or query the database.

For caller/reception/billing/human-support, live startup prepares only caller and
reception; token issuance alone starts neither. Activate an agent receiver once
its required connection/capabilities are ready. Other catalog entries do not
automatically start providers or dial out; prepare them when an authorized
transfer/admission needs them. Dialing is
not evidence that a human has joined. A human receiver does not imply an AI
receiver, and a human-to-human call may begin without any AI participant.
Transfers change current control/routing, not the pinned initial-role refs.
The refs describe conversational roles, not which backend submits the request
or originates a carrier leg; connection configuration retains that job. See the
[approved entry and startup contract][entry-participants]. No runtime startup
behavior was implemented.

**Approved participant cardinality:** each definition key binds at most one
runtime participant per call, for humans and agents alike. Once a staff member
occupies `human-support-agent`, another person cannot join under that key, share
its identity, or replace their connection. An authorized reconnect resumes the
existing participant; permitted agent re-entry retains its participant identity
and receives a fresh activation. Different staff roles use different definition
keys, and another call gets its own independent participants.

Enforce the binding during admission and transfer preparation, including races
and repeated requests: neither a second participant nor duplicate pending
preparation may be created. Direct transfer refs remain unambiguous without an
instance-selection field. The count is a fixed contract, not a JSON option.
Detailed reconnect eligibility, wire responses, and admission/transfer retry
semantics remain follow-ups; cardinality itself is resolved. See the
[approved one-participant contract][participant-cardinality].

**Approved initial context:** the integrating application's backend supplies
values directly in the section structure declared by the call definition. Drop
the separate `input_schema` and JSON Pointer initialization mappings. For order
`ORD-1042`, it supplies `initial_context: {order: {id: "ORD-1042"}}` to a definition
declaring that section. Admission initializes it; several agents can read it
while none has write access. The definition declares the data shape and
permissions, not a second remapping layer. The authorized backend may prefill
any declared section, including one that no agent can write. Initial context
cannot override providers, tools, either entry ref, tenant, or other definition
policy.
There are no context defaults: only values supplied at call setup prefill it.
Schemas describe the allowed structure; they do not manufacture initial values.

**Approved authentication and connection flows:** replace separate client IDs,
client secrets, and HMAC-signed envelopes with a gateway-issued API key in the
backend's `Authorization: Bearer <api_key>` header over HTTPS/WSS. Payloads are
unsigned. The backend authorizes the business context; key verification checks
the integrating application's tenant/operation authority, not customer identity.

1. **Backend prepares, browser joins:** the backend POSTs initial context to the
   preparation endpoint, which grants no CORS access. Vxpipe validates it, stores
   a prepared call with pinned revision/context, and returns an opaque short-lived
   single-use join token scoped to that call and participant. No room/providers
   start yet.
   The frontend receives only the token, not private context or the API key.
   Accepted admission atomically consumes the token before activating that same
   call, not when the browser receives confirmation; conversation waits for
   transport and required capabilities. The browser cannot replace the prepared
   context, and joining must not return its private contents in a snapshot. Later event,
   tool, and speech disclosure remains a separate policy responsibility.
2. **Backend connects directly:** a non-browser WSS client supplies its API key
   in the handshake header. Authenticate before upgrade, then receive unsigned
   context in a bounded first application message. Validate before starting the
   room/providers. This path needs no browser join token.

A WebSocket upgrade is a [GET handshake][websocket-handshake], not a JSON POST
that upgrades. Browser WebSockets require server-side [Origin validation][websocket-origins],
not ordinary HTTP CORS grants. Browser HTTP join/signaling can use a configured
CORS allowlist; neither policy replaces authentication. The [browser WebSocket
interface][browser-websocket] cannot supply arbitrary authorization headers;
token delivery (for example, the first message) still needs its wire contract.
Keep credentials/context out of query strings and logs. Existing browser WebRTC
remains supported; this auth decision does not switch its media transport.

The gateway generates random API keys through authorized management and returns
each once to the backend. Gateway authentication uses a credential-store port;
persistence owns storage, Calls owns preparation/activation, and the engine
receives neither keys nor join tokens.

**Approved API-key storage:** persist only a one-way cryptographic digest of each
high-entropy generated key with its tenant/permission metadata. Hash the supplied
key to verify it and apply authorization; do not accept the stored digest as a
credential. Do not keep plaintext or decryptable copies. Ordinary management
responses and logs expose neither keys nor hashes. The original key is returned
once, and a lost key must be replaced through authorized management, not retrieved.
This replaces reversible storage for Vxpipe-issued API keys; API-key verification
does not need a credential-decryption key.

MCP/provider credentials are different: Vxpipe must be able to retrieve and send
them to remote services. They remain in their configured secret boundary, with
encryption at rest if stored in the database and its runtime key kept outside it.
The [Cloak/Ecto pattern][cloak-ecto] remains applicable to those recoverable
secrets, not gateway-issued API keys. This decision adds no dependency or vault.

The join token is delegated, short-lived access, not a second long-lived
integration credential or proof of a person's identity. Apply scope, TLS, and
limited lifetime consistent with [bearer-token security][bearer-tokens]. See the
[approved context and admission contract][api-admission] for ownership,
alternatives, and future verification steps.

**Approved single-use admission and existing-call recovery:** an unused,
unexpired token may retry before acceptance. Once admission is accepted, it
stays consumed even if startup fails or the browser loses the response. Only
one racing attempt may claim it; no transaction spans room/provider startup.

Recovery after acceptance or token expiry goes through the integrating backend,
which rechecks the user's authorization and uses its API key with `join-tokens`.
Vxpipe checks the tenant/call/participant and current eligibility, reconciles an
in-progress admission first, and rejects ended calls, revoked/unauthorized
access, and active-connection takeover. Recheck eligibility at token claim;
issuance does not guarantee that a later join is still allowed. A caller's old
token or public call ID alone never authorizes fresh-token issuance.

Issuance preserves the existing call record and pinned definition/context. For
an eligible prepared call, subsequent joining activates the room once; an
eligible reconnect to a running call attaches to the same participant/room and
preserves current context rather than reinitializing it. Expiry prevents future
token claims, not continuation of an already accepted call. Gateway owns token
authentication; Calls coordinates the lifecycle through persistence ports.
See the [approved recovery contract][join-token-recovery].

**Approved token-only expiry:** a prepared call is only a database record with
its pinned definition and initial context, not a live call process tree. It has
no separate automatic admission deadline. Token expiry rejects use of that token
but does not expire or delete the unstarted record; an authorized backend can
obtain a fresh token for the same eligible record and later joining starts its
room. Record retention/cleanup is a separate policy, not a token-expiry effect.

**Approved call-start timing:** `created_at` records database record creation;
`started_at` remains unset until the first actual live-call start, when caller
admission starts the runtime and the call transitions to running. Token issuance,
reissuance, consumption, and pending startup are not a start. Failure before the
call starts leaves `started_at` unset.

Persist the authoritative live-start occurrence timestamp, not the later write
or delivery time. Reconnects, transfers, duplicate events, and same-call recovery
preserve it. Live duration and `max_duration_ms` exclude the preparation wait;
a never-started record has no live duration. Creation at 10:00, start at 10:15,
and end at 10:18 means a three-minute call. Provider billing intervals remain
separate. See the [approved timing contract][call-start-timing].

The following G2 proposals remain open and must be reviewed separately:

**API-key management lifecycle:** administrator bootstrap, permission
granularity, multiple-key management, and rotation/revocation still need review.
One-way hash storage is resolved; exact key encoding/hash profile remains an
implementation detail to specify. HMAC algorithm, canonicalization, and
signature fields are no longer questions for this contract.

**Remaining token details and separate storage policy:** specify token TTL
settings, repeated issuance requests or superseding other unused tokens, and
detailed crash reconciliation. Review record retention/cleanup and storage
limits separately. Single-use claim, backend-mediated recovery, the existing-call
token route, and the absence of automatic call-record expiry are resolved.
Exact WebSocket routes, token delivery, initialization limits/timeouts, and errors
remain unapproved wire details. Deferred browser startup does not impose token
preparation on an inbound telephony call or an already-authorized outbound dial.

**Reconnect and retry lifecycle details:** the approved singleton participant
binding and fresh-token route are not permission to resume an ended/revoked
session or evict an active connection. Specify reconnect eligibility/grace
periods, how failed transports are confirmed disconnected, and detailed
join/transfer responses and crash fencing. The approved recovery rules already
preserve the same call and participant; multi-instance selection is not required.

**Telephony initial-context sourcing:** an inbound phone call cannot establish
the example's trusted `customer.id` by itself. Context validation does not require
that field to be present at admission. The approved direct-context
shape eliminates remapping, not the need for a trustworthy source of values.
There is no definition-default fallback. Keep authorized initial context,
trusted ingress metadata, and subsequent agent assertions distinguishable; do
not silently copy ingress data into business context. Provider-asserted
caller number is a routing/contact claim, not verified customer identity. An
admission resolver can perform a bounded lookup before room creation; otherwise
leave identity unverified for a tool to establish later.

**Personalization and evaluation time:** consider allowlisted bindings for prompt
and first-message personalization, locale, IANA timezone, and dynamic dial
numbers. Specify when each value is evaluated:
call-start time is pinned; “current time” is a typed clock/tool observation, not
a permanently frozen prompt variable. Missing required bindings fail early;
optional bindings need explicit omission/fallback behavior without filling room
context. No arbitrary templates, code evaluation, tenant overrides, or
unvalidated deep merges. Destination bindings remain
subject to tenant outbound-call policy and rate limits.

The [intent request][intent-request] supplies variable overrides, and the
[scheduling prompt][scheduling] includes time formatting. These illustrate the
need, not a reason to adopt their unrestricted authoring surface.

### G3 — P1, partly resolved: Context initialization, authorization, and updates

**Approved initialization:** the [context candidate][context-design] has no
default values. Its earlier section defaults and proposed merge rules are
withdrawn. Only an authorized call-setup invocation prefills context in the
declared section shape. Reject section-level and nested schema `default`
declarations. Capability/provider configuration defaults are a separate concern
and remain unchanged.

Validate supplied datatypes and value constraints before room/provider work,
without requiring missing fields. Omitted fields/sections remain unfilled in
storage, not automatically `{}`, `null`, or another value. Callers may explicitly
supply an empty section object and collect its fields later. Schemas and
permissions do not populate data, and later authorized context updates remain
supported. Both labnote examples omit
context defaults; the invocation prefills only `customer.id`, leaving `intake`
unfilled. There is no default-merge or input-remapping contract left to decide.

**Approved missing reads and incremental population:** an authorized read of a
declared but unpopulated section returns null in its value slot, retaining the
normal revision metadata. Null is returned only at the requested value level;
do not construct null-valued nested fields or store the response as context.
A partial section is returned as stored, without filling missing children.
Reads do not mutate state or revisions. Forbidden sections still fail the whole
request, and unknown sections still receive the existing typed error. No new
field-read API is introduced.

The first `update_context` populates an unfilled section with its supplied
object; later updates recursively merge into it. The field form can also
populate a declared direct field in a new section. For an `address` section
with string fields, an agent can save `city` first and `postal_code` later.
Missing fields do not fail validation, including within nested objects. A
number supplied for either string field still fails, with no partial commit.
The same section grants, lifecycle, revision, and size checks apply.

This defers required-field completeness checks, not datatype or other
supplied-value validation. It applies to both initial context and updates;
there is no new final-completeness gate or configuration toggle. Call-definition
structure, tool argument envelopes, and external tools' own required inputs
remain separate contracts. The labnote examples remove their context `required`
lists while retaining datatype and value constraints.

**Approved interruption rule:** let an already-submitted local context update
finish, and use another tool call for a correction. The
[context interruption contract][context-interruption] adds no live-turn or
tool-cancellation check to the [authorization transaction][context-authorization].
Room/incarnation, participant/activation, permission, deadline, schema, limits,
and expected section revision still apply. Transfer/deactivation and room end
remain different from conversational interruption and can invalidate a command.

If the original update commits first, the correction uses the resulting revision,
refreshing its permitted view if necessary. If the correction wins a race against
the same revision, the delayed original conflicts; do not blindly replay it with
a newer revision. Committed values stay committed, even if the turn is cancelled
or its acknowledgement is lost. Completion cannot revive cancelled model speech.
The earlier live-turn check and mutation-ID deduplication/journal proposal are
withdrawn for this decision. External tool outcomes remain a separate G4 review.

**Approved read authorization:** inform the agent of its permitted sections, but
still validate every request at the authority. If any requested section is
forbidden, return a permission error and no context values, including otherwise
permitted values from that same request. Do not silently filter forbidden names.
The agent can retry with permitted sections only; successful reads do not add
unrequested sections. This clarifies existing section grants, not a new
field-level permission system. Error responses must not expose hidden values.

**Approved permission simplification:** agent section grants are `["read"]` or
`["read", "write"]`; an omitted section grants no access. Standalone
`["write"]` is invalid at definition compilation, not silently expanded into
read+write. Every writable section is readable, with its value and revision in
the normal model projection and its resulting value in successful update results.
Ungranted sections expose neither values nor revision metadata in that projection.
Read-only grants expose the read tool; read+write grants also expose update tools.
This withdraws revision-only writable views and the special write-only error
proposal. Ordinary authorization and context privacy still apply to errors,
other sections, public events, and other participants.

**Approved object merge, further details pending:** offer both
`update_context(section_name, data)` for multiple fields in one call and
`update_context_field(section_name, field_name, value)` for a single-field
change. These are working interface names, not final wire schemas. Both share
the existing atomic section boundary, write grant, validation, and revision
checks. The labnote's existing operation-list example already batched updates;
it is retained as an internal command candidate, not a third model-facing tool.
`update_context` recursively merges supplied objects into the existing section;
omitted fields retain their values at every object depth. Where old and supplied
values are both objects, recurse rather than replacing the object wholesale.
For example, changing `intake.topic` preserves an existing `intake.summary`;
changing a nested `address.city` preserves its `postal_code`. This is a deep
merge, not just a deep copy. Check the expected revision and validate populated
values in the merged result, including retained values but not missing fields,
then commit once or reject the whole update without changing values or revisions.
This changes runtime values without introducing defaults or an initialization merge.
Prefer simple, shallow context: make `address` its own section with `city` and
`postal_code`, giving it an explicit schema, grant, and revision boundary.
This is authoring guidance, not a ban on schema-permitted nesting or a runtime
flattening step. Final terminology remains for review;
recursive object merging does not add array-element merge operations. No schema
keys or runtime modules are renamed yet.

**Approved addressing:** keys at the root of context data are section names;
direct keys within each section object are field names. The definition's schema
wrapper and revision metadata are not renamed. `update_context_field` selects
one exact declared direct field; it does not interpret dots, JSON Pointers, or
array-index notation. Unmatched names fail validation rather than traversing or
creating a path. An explicitly declared punctuation-bearing key remains literal.
For example, use `update_context_field("address", "city", "Newtown")` for a
direct field. For a nested address in another section, use
`update_context("profile", {"address": {"city": "Newtown"}})` and its recursive
merge behavior. Internal pointer encoding must preserve literal-name semantics.
No new tool, field-level permission system, or path syntax is introduced.

**Approved clearing behavior:** both update forms accept explicitly supplied
null for a schema-nullable field. It stores null while retaining the key, rather
than skipping or deleting it. For example, clearing `address.apartment` changes
`"4B"` to null without removing `apartment` or altering the other address fields.
An omitted field remains unchanged. Nullability must be explicit: permitting an
absent field does not imply accepting an explicit null, and cleared keys stay
present. Populated values, write grant, and expected revision still validate;
null in a non-nullable field fails the whole update without mutation. No missing
value is automatically populated with null, and section roots remain objects.
Separate deletion tools and physical key removal are deferred, not prerequisites
for clearing a value. No null-means-delete convention is adopted.

The following G3 proposals remain unapproved. Bound schema complexity as well as
value bytes so validation cannot monopolize the room process. There is no
remaining write-only error decision because write-only grants are unsupported.

Finally, separate **agent assertions** from **verified facts**. For example,
`intake` may be agent-writable; `verification` and committed booking receipts
should be writable only by a trusted platform binding that validates the
external result. Section-level permissions make this possible without new
field-level permission syntax. A schema-valid `verified: true` written by an
agent is not proof of verification.

### G4 — P1: Tool cancellation does not roll back an external action

The labnote names retries, cancellation, and idempotency, but does not settle
their interaction. A booking or SMS can succeed remotely before the local
request times out or is killed by barge-in. Retrying blindly can duplicate it;
discarding the result entirely can erase the only explanation of what happened.
The [scheduling workflow][workflow] even configures retries on booking POSTs;
that alone does not prove deduplication by the external API.

Proposal: distinguish a conversational tool invocation from an external
operation. A supervised operation worker owns a stable operation ID, bounded
deadline, attempts, and one of confirmed success, confirmed failure, or unknown
outcome. An interrupted turn loses output authority; safe external read work can
be canceled, while an already submitted external write needs a receipt/status
reconciliation path. Late external facts can enter the private operation ledger
without resuming an old model turn. Whether and how those results can initiate
new context updates remains under review; this proposal does not cancel G3's
already-submitted local context commands or bypass their revision checks.

Default mutating operations to no automatic retry after an ambiguous submission.
Permit retry only with a documented provider idempotency contract or a safe
reconciliation strategy. MCP request IDs are correlation, not business-action
idempotency keys. Business validation, slot uniqueness, and atomic booking
remain responsibilities of the external system; room context is not its
transaction database.

Tool policy should distinguish read-only, idempotent write, and non-idempotent
write using trusted configuration, not model arguments or untrusted remote
annotations. Bind any required confirmation to the exact validated action
arguments, requesting participant, context revision where relevant, and expiry.
Changing the action invalidates confirmation. Do not announce successful sending
or booking from a request-start event. Progress speech is separate from result
speech, with only one owner of each utterance.

### G5 — P1: Private context would leak through the existing tool event path

This is a concrete integration hazard, not just an omitted future feature.
`RoomAuthority.emit_tool_call_started/4` puts arguments in an event;
`emit_tool_call_completed/5` includes the result. The
[RTVI codec][codec] sends both to the client. Today's clock tool is harmless,
but reusing that path for private context or verification defeats the proposed
section permissions even if context-update events contain only metadata.

Proposal: keep private execution payloads separate from audience-specific
events. Model, authorized operator, call-ledger consumer, telemetry, and browser
are different audiences. Default public tool lifecycle events to safe IDs,
status, and approved display names, with arguments/results omitted. Keep the
standard RTVI lifecycle usable without distributing private tool content.
Gateway authorization remains necessary even when an internal event is trusted.

The archive also needs a separate permissioned private context payload/patch:
it cannot rebuild section values from metadata-only public events. Apply
retention/redaction before persistence, not just before final export. Never put
expected verification codes or credentials into prompts, public events, or
ordinary archives. User-spoken verification input can itself enter STT/model
history; sensitive collection requires explicit transient/redaction policy or an
out-of-band verification step. Do not label a code-hidden tool as end-to-end
secret handling if the input transcript still retains the code.

### G6 — P1: “Remote MCP” needs a tested interoperability profile

The configured-versus-enabled distinction is already strong. It does not mean
the example HTTP webhooks, native SMS, or code tools are MCP endpoints. Keep
those behind a remote MCP facade or an explicitly registered host tool; do not
add arbitrary HTTP/JavaScript execution to the call-definition JSON.

Define supported protocol revisions and server features at the adapter boundary.
The checked [2026-07-28 Streamable HTTP specification][mcp-http] does remove
protocol sessions and the GET stream, but still requires JSON and request-scoped
SSE response handling. Older revisions have different lifecycle rules. Thus
stateless must not be interpreted as “POST a JSON tool name to any server.”
Either test a narrow revision profile and reject incompatible servers clearly,
or implement and test explicit backward compatibility. Record the negotiated
profile in the resolved binding.

Before the remote slice, specify bounded discovery/pagination, tool-schema
compatibility, structured/text/error result normalization, and unsupported
server requests. The context-schema subset must not silently truncate an MCP
tool schema. Reject unsupported schema features before advertising a tool.
Sampling/elicitation and other unimplemented features should fail explicitly,
not acquire ambient authority.

Pin tool schemas, not the remote service's changing business data. Returned
instructions are untrusted tool content, never new system policy or permission
grants. Cache by authorization boundary and integration/credential generation;
do not share user-specific discovery/results simply because an endpoint matches.
Keep revocation fail-closed with no silent fallback to application credentials.
For configurable endpoints, bound responses, enforce TLS/egress policy, and do
not forward credentials across redirects. OAuth onboarding/refresh remains a
separate control-plane feature; document when supplied bearer tokens expire.

### G7 — P2: Conversation lifecycle needs more than `first_message: generated`

First-message behavior is mentioned but only one mode is illustrated. Define
silent/wait-for-input, static text, and generated greeting modes, with bounded
startup, silence, tool-wait, and maximum-call timers. Specify whether greeting
runs on first activation or reactivation; reconnect must not replay it by
accident. Silence timers should distinguish waiting for a human from generating,
playing audio, holding, dialing, or waiting for a tool.

Treat speak-and-end as an engine lifecycle: stop accepting new conversational
work, enqueue an authorized closing utterance, wait for the configured delivery
evidence or a deadline, then terminate the intended call/leg with a typed reason.
Immediate end remains separate. Define how interruption affects the closing
utterance. A prompt telling a model to wait until speech finishes cannot enforce
this ordering.

The [voicemail example][voicemail] waits for input and delegates to a native
tool. Vapi's [tool documentation][voicemail-docs] distinguishes assistant-chosen
voicemail from automatic detection and ends the call after the configured
behavior. For our adapter contract, answer classification and beep evidence need
source/confidence, timeouts, and an unknown outcome. An answered leg is not proof
of a human, and STT text alone does not establish a beep. Reject policies that
require unavailable evidence. Start with a safe narrow outbound policy; do not
claim full answering-machine or IVR support from generic hangup/transfer tools.

### G8 — P2: A transfer allowlist is not the complete transfer policy

Keep `transfers: ["specialist", "human-support-agent"]`. The labnote says a
transfer declares warm/cold behavior, source disposition, and context projection,
but gives those settings no home after rejecting named transfer objects.

Proposed location: a call-level handoff policy with source-agent outgoing
defaults and destination acceptance requirements. The compiler resolves one
effective policy per allowed pair; target safety constraints cannot be weakened
by the source. This preserves the simple list. Defer per-pair authoring until
a real case needs it. Policy keys are proposals, not accepted schema additions.

Specify dialing, ringing, answered, media-ready, accepted, committed, failed,
and canceled states; their deadlines; and cleanup for late provider callbacks.
Busy, no-answer, declined, voicemail, caller departure, and failure while
stopping capabilities must each have an outcome. Preparation has external side
effects: it cannot promise that nothing changed if a leg was dialed or an STT
session stopped. Use compensating cleanup, bounded source re-preparation, and a
safe degraded/terminal outcome if restoration fails. Never resume forbidden
processing just to restore the earlier user experience.

Live mix-minus alone is insufficient for a private consultation. Define an
authorized source-to-sink routing matrix: caller hears hold audio, operator and
consulting agent hear each other, caller cannot hear consultation, and monitor
and recording taps follow explicit grants. A full monitor mix is not permission
to hear every restricted lane. If concurrent consultation is needed, define a
second lane's agent ownership or defer it; the current single active-agent rule
does not magically support concurrent agents. This extends routing policy, not
the public definition into a workflow graph.

The repository transfer tools demonstrate basic destination transfer, not warm
consultation. The additional [first-party warm-transfer guide][warm-transfer]
describes hold, operator acceptance, cancel, and fallback; that is separate
evidence for the richer scenario, not a claim about the example JSON.

### G9 — P1: Capability denials must cover routed dependencies

An agent-scoped denial of `speech_to_text` is ambiguous when the actual STT
instance belongs to the human input participant and feeds that agent. Stopping
only capabilities physically owned by the matched agent would not stop its
consumption of transcripts. See the [capability ownership terminology][terms]
and [presence policy][presence].

Proposal: compile both capability-instance ownership and authorized consumers.
An agent-specific denial must block that agent's recognition input/derived
transcript route, not just an instance named on the agent. Unaffected agents may
continue only if room/participant policy permits the shared upstream processing.
`type: all` STT denial stops recognition input/provider work for the whole
applicable topology. Before commit, invalidate queued derived output as well as
media subscriptions; reconciling later must not transcribe the denied interval
from a recording. Keep recording and monitoring permissions independent.

This is a semantic choice the compiler must settle before accepting denials;
otherwise identical JSON can mean different privacy guarantees depending on
where an adapter happens to be attached.

### G10 — P2: Durable admission has crash windows and admission-key ambiguity

The [persistence plan][persistence] already separates short database transactions
from room/provider work. Add reconciliation to the gap between
`begin_admission`, room creation, provider dialing, and `mark_running`.

Distinguish webhook-delivery deduplication from call admission deduplication:
multiple lifecycle events for one provider leg are not multiple new calls.
Namespace keys by trusted tenant/integration and normalized leg identity. A
transfer-created leg must attach through the pending transfer/participant ID,
not re-enter number-to-definition admission. Reusing a client idempotency key
with a different normalized request must conflict.

Use a claimed admission state with fencing/CAS transitions and a reconciler that
can find an already-started room before retrying. Test crashes after every
boundary. Do not retry an uncertain outbound dial as though no leg exists.
One room registry is not a durable cross-node exactly-once guarantee.

### G11 — P2: Archive completeness and publication identity are underspecified

The async archive is correctly described as potentially lossy on node failure.
Specify per-consumer bounded queue/overflow behavior and independent private
versus public projections. A slow browser must not stall the ledger, and a slow
ledger must not silently turn an archive into a complete record. Record missing
sequence ranges or an incomplete watermark. A retention policy can intentionally
omit data; distinguish that from accidental loss. Required-audit mode needs the
explicit durable acknowledgement protocol, not a larger mailbox.

There is also an immediate source gap: the engine's text-input start/completion
events contain modality and IDs but not submitted text. Add a committed-input
fact, with visibility and retention policy, before claiming the event stream can
rebuild the human text transcript. [Room authority][authority].

Call end, operation settlement, artifact finalization, and archive publication
are different states. The proposed `(call_id, archive_schema_version)` job key
cannot distinguish a corrected export using the same schema. Use a publication
revision plus source event/usage/artifact watermarks; retries of one revision
deduplicate, later revisions create new immutable objects. Finalization must
survive room loss, using an outside-room coordinator and persisted expected
operations/artifacts with a bounded incomplete outcome.

Preserve live recording beside the engine and upload workers outside its hot
path. Multipart upload is not a live monitor feed; monitor from the authorized
live mix. Track manifests need clock mapping across ingress/egress and room
incarnations, explicit gaps, and evidence distinguishing scheduled, sent, and
device-confirmed playback. A sink accepting audio does not prove a listener heard
it. Post-call summary/evaluation is a separate optional, metered job; it cannot
overwrite authoritative room context or invent missing transcript segments.

### G12 — P2: One usage row per operation is too restrictive for settlement

Keep usage attached to provider operations with optional turn attribution, as
already proposed. Refine “one immutable usage record per billable operation” to
allow multiple versioned observations: estimates, cumulative stream updates,
terminal usage, and billing reconciliation. An operation can also have several
attempts, each potentially billable.

Deduplicate observations by provider/attempt identity and derive one effective
amount per priced component. Do not sum every estimate and correction, every
cumulative sample, or token subcategories that a provider already includes in a
total. Shared STT/telephony usage can remain call-scoped; if allocated across
turns, record the allocation basis and conserve the original total. Interrupted
or failed operations may still cost money and must outlive stale-turn filtering.
Keep unknown usage unknown, with currency and pricing-version provenance.

### G13 — P2: Provider tuning and long-call limits need an explicit profile contract

The examples configure different languages, endpointing, pronunciation/numeral
options, voice formatting, and interruption thresholds. Our provider-profile
references are a good home for those choices, but references alone do not define
which options exist or how incompatibilities fail. [Scheduling][scheduling],
[voicemail][voicemail].

Separate supported provider options from engine-owned turn/interruption policy.
Compile required evidence/features against adapter capabilities; do not silently
ignore unsupported options or import executable timing expressions. Keep hosted
provider endpointing and the existing no-local-VAD/no-local-model scope.

For long calls, declare token-aware history/tool-result/context budgets,
truncation or compaction policy with provenance, and provider failure/fallback
outcomes. The current turn-count history bound does not bound a large prompt or
tool response in model tokens. Fallback must preserve authorization, tool schema,
privacy restrictions, and actual-provider usage attribution; it cannot repeat
an uncertain external action. These are profile/runtime checkpoints, not a
reason to add provider-native payloads to each participant definition.

## Possible checkpoint order and acceptance scenarios

This sequence is an option for review, not an approved implementation plan. Do
not add the suggested fields or functionality before the user reviews the gaps.

1. **Compiler and one-agent context:** implement the approved G1 layout only
   when runtime work is authorized; review G2–G3, the private-event part of
   G5, and denial semantics in G9. Use one canonical fixture with two context
   sections and an engine-owned context tool. Prove the existing text/audio path
   works through a typed plan. Do not start with telephony or Ecto.
2. **Safe remote action:** add one tenant-configured remote MCP integration,
   enabled on one agent, with a fake scheduling backend. Cover G4/G6 and trusted
   result projection before making real mutating calls.
3. **Transfers and lifecycle:** prove an agent-to-agent transfer first, then one
   fake outbound human transfer with busy/no-answer/accept outcomes and enforced
   presence denials. Add G7–G9 and live routing/mixing before claiming human-only
   bridging or consultation.
4. **Durable admission and archive:** retain the previously proposed Calls,
   persistence, and artifact boundaries; add G10–G12 incrementally. No Repo/S3
   calls enter the room's state-transition callback.

Use scenario fixtures rather than copying complete third-party definitions:

| Future acceptance test | Evidence of success |
| --- | --- |
| Two staff members try to join as the same definition; the original member reconnects | Only the original authorized participant is retained; the second person's admission fails without takeover; another definition or call has its own independent participant |
| Race admissions/transfers and re-enter an agent definition | One participant and no duplicate pending preparation per key per call; agent re-entry retains identity with a fresh activation |
| Compile two distinct entry refs and start a caller/reception/billing/support definition | Missing, non-string, identical, and unknown refs fail; only the initial pair is prepared, not every provider/dial target |
| Start with a human receiver, then exercise a separate agent-to-agent transfer scenario | No implicit AI receiver is created; transfer changes live control while the initial refs and pinned plan stay unchanged |
| Declare schemas with no context defaults and supply partial initial context | Supplied datatypes/value constraints validate before startup; missing fields do not fail, including in nested objects; intake stays unfilled; context defaults fail; capability defaults still work; explicit empty section objects are accepted without filling values |
| Prepare private order context using a backend API key, then join from the browser using only a token | Preparation pins/stores context without starting providers; authorized joining activates that call; private preparation data is not returned; agents read but cannot rewrite read-only sections; invalid keys, tenant/participant access, and context fail |
| Connect a backend WSS client with an API key and send unsigned context as its first message | Invalid authentication fails before upgrade; a missing message, malformed/oversized context, or wrong datatypes cannot start the room; empty context and partial sections are allowed; browser Origin and HTTP CORS are checked separately; keys/tokens stay out of URLs, room state, events, and logs |
| Issue a key once, inspect storage, and verify it after restarting authentication | Only a digest and metadata persist; the original key works without decryption; wrong keys and the digest itself fail as credentials; keys/hashes are redacted; lost keys are replaced, not retrieved |
| Race the same join token and lose the response after admission is accepted | Only one claim and room startup; retry before acceptance may use the unused token, but accepted tokens stay consumed; expiry does not end an accepted call |
| Request a fresh token for an existing prepared call or an eligible disconnected participant | Backend API-key authorization uses the same call record; issuance starts no room; joining activates the prepared call once or reconnects to its existing participant/room without resetting context |
| Leave a call unstarted until its token expires, then request a fresh token | Old-token joining fails, but the record and pinned definition/context remain; authorized reissuance starts no room and later joining activates that same call without creating a replacement record |
| Create a record well before joining, delay persistence of live start, and later reconnect/end | `started_at` stays unset before actual start and records that occurrence time once; duration and its limit exclude preparation; reconnect/recovery preserve the timestamp; failure before start leaves it unset |
| Recover during pending startup, after call termination, or while a connection is active | Pending admission is reconciled first; ended/revoked/unauthorized access and takeover fail; eligibility is rechecked at claim; no duplicate call or participant |
| Write/read intake, then transfer to a read-only agent | Same room value is visible; unauthorized writes fail; mixed authorized/unauthorized reads return a permission error and no values; retrying permitted sections succeeds without adding unrequested data |
| Compile read-only, read+write, and standalone write grants; leave another section ungranted | First two grants succeed; standalone write fails without silently adding read; read-only grants expose reads, read+write grants also expose updates and their resulting values; ungranted sections expose neither values nor revisions in model projections |
| Read an unpopulated section, then populate it over multiple updates | Read returns one null in the requested value slot, no nested placeholders or state/revision change; first object or field write creates supplied data, later writes add fields; partial reads do not fill missing children; unknown/forbidden sections still fail |
| Merge several fields with the object tool, then change one field with the field tool | One call per operation; omitted stored fields remain; missing fields need not be supplied; wrong datatypes/invalid populated values reject atomically; the same write grant/revision boundary applies |
| Update only a nested address city, then exercise a shallow address section | An existing postal code and omitted siblings remain recursively; a missing postal code is neither required nor invented; wrong nested datatypes reject the whole update; shallow and permitted nested shapes work without automatic flattening |
| Clear an apartment using explicit null through each update form | A nullable field remains present with null; omitted fields stay unchanged; non-nullable fields reject explicit null atomically even though absence is allowed; no deletion tool or stored null defaults |
| Select a direct field, then attempt a dot/pointer/index-like field name | Only exact declared direct keys are addressed; unmatched names fail, punctuation is never traversal, explicitly declared literal keys remain literal, and nested changes use the object tool |
| Interrupt after submitting a context update, then correct it with another call | The submitted command can finish under existing checks without reviving speech; correction uses the new revision; a delayed original loses a same-revision race without blind retry; transfer/deactivation and room end still fence pending writes |
| Book, interrupt after remote commit but before response, then retry | One external booking; durable/observable receipt or explicit unknown outcome; no stale speech or automatic duplicate |
| Change an action after confirmation | Old confirmation cannot authorize the new arguments |
| Request verification, then have the model write `verified: true` | Write is denied; only backend verification updates trusted status; codes/results stay out of public events |
| Retrieve instructions asking for an undeclared transfer/tool | Request is rejected by server authority despite model intent |
| Reach voicemail, busy, no answer, or a human who declines | Typed leg/transfer outcome; no false `transfer.completed`; caller has defined fallback |
| Enter a restricted human-only segment | Denied processing/routes stop before bridging; unaffected permitted audio continues; later restart does not replay the denied interval |
| Slow the recording upload or archive consumer | Live mix progresses; recording/archive becomes explicitly incomplete according to policy, not silently complete |
| Replay admission events and crash between admission stages | One durable call and at most one current fenced room; uncertain dialing is reconciled |
| Reconcile late usage after call end | Corrected archive has a new publication revision; totals do not double-count observations |

These are planned red-green tests, not tests run during this review. Before each
implementation checkpoint, write and run the smallest failing project-owned
contract test, then implement it and run the umbrella completion checks. Add
network/provider interoperability cases to the tagged integration lane. Use
synthetic identities, destinations, and data; do not operate example endpoints.

## Alternatives rejected and verification evidence

- Do not replace the participant-first contract with a workflow graph to encode
  these scenarios. Most business branching stays in prompts and external tools;
  safety transitions remain small engine-owned state machines.
- Do not use arbitrary API/code tool definitions as a shortcut around remote MCP
  or trusted host registration. They would expand the authoring trust boundary.
- Do not treat prompt instructions, actor authentication, and verified customer
  identity as interchangeable authority.
- Do not duplicate the room-context schema with a second call-input schema and
  initialization map. The backend can supply the declared context shape directly.
- Do not populate context from definition defaults, merge in fallback values,
  or store empty objects or nulls for omitted values. Only supplied setup data
  prefills context; later writes still need their existing grants. Returning
  null for a missing requested value is a read representation, not a default.
- Do not demand complete context before accepting setup or an update. Agents
  collect fields iteratively; retain datatype/supplied-value checks without
  required-field completeness checks at any object depth.
- Do not add turn/tool-cancellation tracking or rollback for submitted local
  context updates. Let them finish under normal authorization/revision checks;
  corrections use another tool call, not blind retries of an obsolete patch.
- Do not silently ignore forbidden sections in a context read. Return a
  permission error and no values so the agent can correct its request.
- Do not support write-only agent section grants or a revision-only writable
  projection. A section is read-only, read+write, or ungranted; standalone write
  is invalid. Existing public-event and cross-participant privacy still apply.
- Do not replace a complete context section with the partial object passed to
  `update_context`. Recursively merge objects, preserve omitted fields at every
  object depth, and validate populated values without demanding missing fields;
  omission is not deletion.
- Do not interpret explicit null as key deletion or add a tool solely to clear
  a value. Store null through either update form when its schema allows it;
  optionality alone does not grant nullability.
- Do not interpret model-facing section or field names as paths. Root keys name
  sections, direct section keys name fields, and nested object updates already
  provide the mechanism for deeper changes. Internal pointers stay internal.
- Do not embed the caller in an entry field or infer it from catalog scanning.
  Both entry fields reference one participant catalog; compilation resolves
  initial roles explicitly. Listing a participant does not make it live.
- The earlier client-ID/HMAC contract is superseded: no signature envelope or
  canonicalization is needed for these backend API-key flows. Never put API keys
  in browsers, definitions, or plaintext database fields. Reversible storage is
  also rejected for Vxpipe-issued keys: keep only a one-way hash. Recoverable
  upstream credentials remain a separate concern. Hash storage does not replace
  TLS, scoped-token lifecycle, or credential management.
- Do not reuse consumed join tokens, silently take over a connection, or recreate
  a call after losing its admission response. Backend-authorized recovery must
  reconcile and reuse the existing call/participant. Token expiry is not an
  automatic hangup of an established call.
- Do not impose an additional automatic admission expiry on unstarted call
  records. Token expiry already blocks use of that token; authorized reissuance
  can reuse the same record. Record retention/cleanup is a separate decision.
- Do not use record creation, token redemption, or event-persistence time as the
  call's start time. Record actual live start once and exclude preparation wait
  from call duration; reconnects do not start a new call clock.
- Do not serialize full tool payloads into a universal room event stream and
  attempt to recover privacy only at the final publisher.
- Do not move mixing, recording coordination, or room context into persistence.
  No new umbrella application was created as part of this review.

Evidence is source inspection at the commits above and targeted first-party
protocol documentation, not a successful end-to-end deployment of the external
examples. Documentation verification covers local link targets, fenced JSON
syntax in the updated labnote, whitespace, and scoped diffs. Runtime tests and
browser checks are not applicable to this documentation-only checkpoint.
The approved credential-storage follow-up also inspected an existing Cloak/Ecto
implementation: runtime key validation, supervised vault, encrypted binary
fields, redaction, and binary database columns. No environment-file contents or
real credentials were read, and no credentials were generated. The existing
gateway still uses a development principal; this review adds no authentication
implementation. The labnote records the follow-up's documentation-check results.
The subsequent entry-role follow-up checks both examples for distinct resolvable
string refs, removes the obsolete entry field/type proposal, and records future
startup/readiness checks. A separate subsequent decision approves one participant
per definition key per call and adds future duplicate/reconnect/race acceptance
cases. Runtime tests remain out of scope; the labnote records documentation
verification separately from those unimplemented checks.
The API-key follow-up supersedes the HMAC wire contract, separates prepared-call
tokens from live room sessions, and checks WebSocket handshake/Origin/browser
constraints against first-party specifications. It does not implement the new
routes or change the current browser transport. At that checkpoint, key storage
was left open. The subsequent approved storage decision selects one-way hashes
for Vxpipe-issued API keys, replaces the earlier encrypted-storage baseline for
those keys, and adds future storage/verification/redaction acceptance checks.
No authentication implementation, migration, dependency, or secret was changed.
The subsequent token-recovery decision approves single-use consumption at
accepted admission and the backend-only existing-call `join-tokens` route. Both
documents now distinguish prepared records from live rooms, token issuance from
browser joining, and token expiry from call duration. Future acceptance cases
cover races, lost responses, and recovery without duplicate calls or takeover.
At that checkpoint, unused-call expiry was still open. The subsequent
clarification rejects a separate automatic admission deadline for unstarted records: tokens
expire, records remain, and authorized fresh-token issuance can reuse them.
Token TTL settings, record-retention policy, and detailed crash handling remain
open. These are documentation decisions, not implemented runtime behavior.
The later timing clarification distinguishes record creation from actual live
start and preserves that start across delayed persistence and recovery. Its
future acceptance cases cover duration, token operations, and pre-start failure;
no runtime timestamp or database schema was changed.
The subsequent context correction removes defaults from both labnote schema
examples and approves supplied-only initialization. It replaces the merge-rule
proposal, retains capability/profile defaults, and updates planned acceptance
checks. At that checkpoint, G3's remaining runtime authority questions were still
open; no context compiler or runtime implementation was changed.
The subsequent interruption decision lets submitted local context commands
finish while retaining authorization, lifecycle, and revision checks. It removes
the proposed live-turn cancellation guard and mutation-ID journal requirement,
updates the race/correction acceptance case, and leaves external-tool policy
and the other G3 questions pending. No runtime cancellation behavior was changed.
The read-authorization follow-up approves whole-request permission errors instead
of filtering and updates the original read contract and future acceptance cases.
It records the requested object and field update tools, retaining batching and
the existing section authorization boundary, with naming and update semantics
pending at that checkpoint. No runtime implementation or schema rename was introduced.
The subsequent object-update decision selects merging into existing section
data while preserving omitted fields. The labnote adds a before/data/after
illustration and planned checks for retained required fields and atomic invalid
update rejection. At that checkpoint, nested/removal details and final naming
remained open; no runtime merge implementation was introduced.
The subsequent clarification approves recursive object merging and preservation
of omitted nested fields. It recommends shallow authoring, such as an `address`
section, without banning nesting. The original note adds a nested illustration
and planned verification, while retaining the 12 open-group count and the
then-open removal/null, field-addressing, and naming questions. No runtime code,
schema flattening, or new nesting limit was introduced.
The clearing decision now assigns explicit null to nullable fields while keeping
their keys, leaves omission as preservation, and defers physical deletion. Both
documents update nullable-field requirements and planned verification without
changing runtime behavior or adding a new model-facing tool. G3 still has other
open questions, so the numbered review-group count remains 12.
The addressing decision now fixes context root keys as section names and direct
section keys as literal field names. It routes deeper partial changes through
the object-update tool, separates model-facing names from internal pointer
encoding, and adds future direct-key/path-confusion checks. Other G3 questions
remain open; no runtime tool or schema-wrapper change was introduced.
The missing-read and incremental-population decision returns one null at a
requested absent value, without nested placeholders or a stored default. First
writes populate a declared section; later writes collect fields iteratively.
This supersedes earlier required-field completeness checks mentioned in the
historical checkpoints above, while retaining datatype and supplied-value
validation. Context-tool argument shapes must also allow partial objects. The
two definition illustrations remove only their context `required` lists, and
planned acceptance steps now cover absence, partial/nested collection, and wrong
datatypes. G3's read/first-write questions are resolved; other G3 questions keep
the count at 12 open groups. No runtime implementation was changed.
Verification parsed all 13 JSON examples, confirmed the only example changes
are the two context `required` removals, and checked both definition contracts,
unrelated write checks, 20 local links/anchors, routes, review counts, and
documentation hygiene. `git diff --check` passed; no runtime/browser tests ran.
The permission follow-up limits agent section access to read-only or read+write,
with no access when omitted and standalone write grants rejected. It removes
revision-only writable projections and the write-only error review question,
aligns update results and planned acceptance steps, and preserves ungranted
section privacy. Existing JSON examples already match this decision. Other G3
questions remain, leaving 12 open groups; no runtime implementation changed.
Verification confirmed all 13 JSON examples are unchanged and parse, both
definitions use supported grants, all seven write-authorization checks remain,
and all 20 local links/anchors resolve. Superseded write-only paths, routes,
review counts, documentation hygiene, and `git diff --check` were checked;
no runtime or browser tests were run.

[design]: ../labnotes/20260905-0405-call-definition-design.md
[architecture]: architecture.md
[mcp-design]: ../labnotes/20260905-0405-call-definition-design.md#applicationtenant-mcp-integrations-and-agent-enablement
[json-design]: ../labnotes/20260905-0405-call-definition-design.md#representative-json-shape
[context-design]: ../labnotes/20260905-0405-call-definition-design.md#working-room-context-schema-candidate
[context-authorization]: ../labnotes/20260905-0405-call-definition-design.md#authorization-transaction
[context-interruption]: ../labnotes/20260905-0405-call-definition-design.md#context-updates-and-conversational-interruption--approved-g3-decision
[web-admission]: ../labnotes/20260905-0405-call-definition-design.md#web-participant-admission-routes--approved-g2-routing
[api-admission]: ../labnotes/20260905-0405-call-definition-design.md#initial-context-and-api-key-admission--approved-g2-decisions
[join-token-recovery]: ../labnotes/20260905-0405-call-definition-design.md#single-use-join-tokens-and-existing-call-recovery--approved-g2-decisions
[call-start-timing]: ../labnotes/20260905-0405-call-definition-design.md#record-creation-and-actual-call-start--approved-timing-contract
[entry-participants]: ../labnotes/20260905-0405-call-definition-design.md#entry-participants-and-startup--approved-g2-decisions
[participant-cardinality]: ../labnotes/20260905-0405-call-definition-design.md#one-participant-per-definition-key--approved-g2-decision
[presence]: ../labnotes/20260905-0405-call-definition-design.md#participant-presence-constrains-the-capability-topology
[persistence]: ../labnotes/20260905-0405-call-definition-design.md#persistence-call-records-usage-and-artifacts
[terms]: architecture.md#domain-terminology
[codec]: ../apps/vxpipe_gateway/lib/vxpipe/gateway/rtvi/codec.ex
[authority]: ../apps/vxpipe_call_engine/lib/vxpipe/call_engine/room_authority.ex
[examples]: https://github.com/VapiAI/examples/tree/242a4ef9ac720c3ce000e1635f5197768f6e9945
[scheduling]: https://github.com/VapiAI/examples/blob/242a4ef9ac720c3ce000e1635f5197768f6e9945/assistants/healthcare_scheduling/assistant.json
[booking]: https://github.com/VapiAI/examples/blob/242a4ef9ac720c3ce000e1635f5197768f6e9945/assistants/healthcare_scheduling/tools/scheduling/book.json
[workflow]: https://github.com/VapiAI/examples/blob/242a4ef9ac720c3ce000e1635f5197768f6e9945/assistants/healthcare_scheduling/tools/scheduling/n8n_workflow.json
[intent]: https://github.com/VapiAI/examples/blob/242a4ef9ac720c3ce000e1635f5197768f6e9945/assistants/multi_intent_handler/assistant.json
[intent-request]: https://github.com/VapiAI/examples/blob/242a4ef9ac720c3ce000e1635f5197768f6e9945/assistants/multi_intent_handler/assistant_request.json
[instructions]: https://github.com/VapiAI/examples/blob/242a4ef9ac720c3ce000e1635f5197768f6e9945/assistants/multi_intent_handler/tools/get_instructions.ts
[instruction-tool]: https://github.com/VapiAI/examples/blob/242a4ef9ac720c3ce000e1635f5197768f6e9945/assistants/multi_intent_handler/tools/get_instructions.json
[voicemail]: https://github.com/VapiAI/examples/blob/242a4ef9ac720c3ce000e1635f5197768f6e9945/assistants/voicemail_detection/assistant.json
[voicemail-tool]: https://github.com/VapiAI/examples/blob/242a4ef9ac720c3ce000e1635f5197768f6e9945/assistants/voicemail_detection/tools/leave_voicemail.json
[sms]: https://github.com/VapiAI/examples/blob/242a4ef9ac720c3ce000e1635f5197768f6e9945/assistants/otp-sms/assistant.json
[code]: https://github.com/VapiAI/examples/blob/242a4ef9ac720c3ce000e1635f5197768f6e9945/assistants/otp-sms/tools/code_tool.json
[sms-tool]: https://github.com/VapiAI/examples/blob/242a4ef9ac720c3ce000e1635f5197768f6e9945/assistants/otp-sms/tools/VAPI_Send_SMS_tool.json
[voicemail-docs]: https://docs.vapi.ai/tools/voicemail-tool
[warm-transfer]: https://docs.vapi.ai/calls/assistant-based-warm-transfer
[mcp-http]: https://raw.githubusercontent.com/modelcontextprotocol/modelcontextprotocol/main/docs/specification/2026-07-28/basic/transports/streamable-http.mdx
[cloak-ecto]: https://cloak-ecto.hexdocs.pm/install.html
[websocket-handshake]: https://www.rfc-editor.org/rfc/rfc6455.html#section-4.1
[websocket-origins]: https://www.rfc-editor.org/rfc/rfc6455.html#section-10.2
[browser-websocket]: https://websockets.spec.whatwg.org/#the-websocket-interface
[bearer-tokens]: https://www.rfc-editor.org/rfc/rfc6750.html#section-5
