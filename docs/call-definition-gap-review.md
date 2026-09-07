# Call-definition gap review

Reviewed: 2026-09-06 UTC
Last updated: 2026-09-07 UTC
Status: G1 and G2's web routes, initial context, API-key admission with one-way
hash storage and prepared token-join or direct-backend connection, explicit entry
participants/startup, and one participant per definition key per call approved;
remaining G2 questions and G3–G13 pending review.
Documentation only; no runtime implementation.

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
metadata, with separate HTTPS operations to prepare and join:

```http
POST /api/tenants/{tenant_key}/participants/{participant_key}/calls
POST /api/tenants/{tenant_key}/calls/{call_id}/participants/{participant_key}/sessions
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

**Approved authentication and connection flows:** replace separate client IDs,
client secrets, and HMAC-signed envelopes with a gateway-issued API key in the
backend's `Authorization: Bearer <api_key>` header over HTTPS/WSS. Payloads are
unsigned. The backend authorizes the business context; key verification checks
the integrating application's tenant/operation authority, not customer identity.

1. **Backend prepares, browser joins:** the backend POSTs initial context to the
   preparation endpoint, which grants no CORS access. Vxpipe validates it, stores
   a prepared call with pinned revision/context, and returns an opaque short-lived
   join token scoped to that call and participant. No room/providers start yet.
   The frontend receives only the token, not private context or the API key.
   Authorized joining activates that same call; conversation waits for transport
   and required capabilities. The browser cannot replace the prepared context,
   and joining must not return its private contents in a snapshot. Later event,
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

The following G2 proposals remain open and must be reviewed separately:

**API-key management lifecycle:** administrator bootstrap, permission
granularity, multiple-key management, and rotation/revocation still need review.
One-way hash storage is resolved; exact key encoding/hash profile remains an
implementation detail to specify. HMAC algorithm, canonicalization, and
signature fields are no longer questions for this contract.

**Prepared-call and token lifecycle:** specify token lifetime, claim/reissue and
retry rules, unused preparation expiry/retention and limits, and crash recovery.
Concurrent joins must not activate duplicate rooms or participants; token claim
and activation cannot hold a database transaction across external work. Exact
transport routes, token delivery, initialization limits/timeouts, and errors
remain unapproved wire details. Deferred browser startup does not impose token
preparation on an inbound telephony call or an already-authorized outbound dial.

**Reconnect and retry lifecycle details:** the approved singleton participant
binding is not permission to resume an ended/revoked session. Specify reconnect
eligibility and deadlines, transport replacement, and repeat/concurrent
join/transfer responses without creating a second participant or allowing a
different person to take over. Do not reopen multi-instance selection as a
requirement for the approved initial contract.

**Telephony initial-context sourcing:** an inbound phone call cannot supply the
example's required trusted `customer.id` by itself. The approved direct-context
shape eliminates remapping, not the need for a trustworthy source of values.
Keep definition defaults, authorized initial context, trusted ingress metadata,
and subsequent agent assertions distinguishable. Provider-asserted
caller number is a routing/contact claim, not verified customer identity. An
admission resolver can perform a bounded lookup before room creation; otherwise
leave identity unverified for a tool to establish later.

**Personalization and evaluation time:** consider allowlisted bindings for prompt
and first-message personalization, locale, IANA timezone, and dynamic dial
numbers. Specify when each value is evaluated:
call-start time is pinned; “current time” is a typed clock/tool observation, not
a permanently frozen prompt variable. Missing required bindings fail early;
optional values need explicit defaults. No arbitrary templates, code evaluation,
tenant overrides, or unvalidated deep merges. Destination bindings remain
subject to tenant outbound-call policy and rate limits.

The [intent request][intent-request] supplies variable overrides, and the
[scheduling prompt][scheduling] includes time formatting. These illustrate the
need, not a reason to adopt their unrestricted authoring surface.

### G3 — P1: Context validation is not enough to establish authority

At baseline, the [context candidate][context-design] required defaults to satisfy
the full schema *before* initialization, forcing dummy values or optional fields
for data supplied only at call start. The approved G2 revision removes input
mappings and allows initial values in the declared section shape, including a
required value with no default. It does not settle partial/default assembly.
Proposed resolution for review: validate supplied defaults for types/unknown
keys, specify section replacement versus field merge, then validate the complete
initialized section, including required fields. Specify missing/omitted and null
behavior. No overlapping-input-binding rule is needed now that those mappings
have been removed. All initialization must succeed before room/provider work
starts; exact assembly semantics still need approval.

The [authorization transaction][context-authorization] checks activation, but
interruption can leave the same agent activation active. Require a still-live
originating turn and tool invocation as well as incarnation, participant,
activation, deadline, permission, and revision. A GenServer call timeout is not
cancellation of an already queued mutation. Check validity at the authority's
commit point; deduplicate retries with a mutation ID and payload digest. A write
committed before interruption remains a fact; the acknowledgement being lost
does not undo it. Whole-node exactly-once behavior needs the separate durable
journal mode already deferred in the labnote.

Resolve the read wording to all-or-nothing authorization: if any requested
section is unreadable, return no section values. Write-only errors must not echo
existing values or schema-validator data. Bound schema complexity as well as
value bytes so validation cannot monopolize the room process.

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
outcome. An interrupted turn immediately loses output/context-write authority;
safe read work can be canceled, while an already submitted write needs a
receipt/status reconciliation path. Late external facts can enter the private
operation ledger without resuming an old model turn or applying its stale patch.

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
| Initialize a required context field directly, with no input mapping or dummy default | Compilation succeeds; absent required initial data fails before room startup; partial/default assembly follows a separately approved rule |
| Prepare private order context using a backend API key, then join from the browser using only a token | Preparation pins/stores context without starting providers; authorized joining activates that call; private preparation data is not returned; agents read but cannot rewrite read-only sections; invalid keys, tenant/participant access, and context fail |
| Connect a backend WSS client with an API key and send unsigned context as its first message | Invalid authentication fails before upgrade; invalid/missing/oversized context cannot start the room; browser Origin and HTTP CORS policies are checked separately; keys/tokens stay out of URLs, room state, events, and logs |
| Issue a key once, inspect storage, and verify it after restarting authentication | Only a digest and metadata persist; the original key works without decryption; wrong keys and the digest itself fail as credentials; keys/hashes are redacted; lost keys are replaced, not retrieved |
| Write/read intake, then transfer to a read-only agent | Same room value is visible; unauthorized writes and mixed authorized/unauthorized reads fail without mutation/disclosure |
| Interrupt while a context update is queued | Ordering determines one commit-before-interrupt or a stale-work rejection; replayed mutation ID cannot write twice |
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
- Do not embed the caller in an entry field or infer it from catalog scanning.
  Both entry fields reference one participant catalog; compilation resolves
  initial roles explicitly. Listing a participant does not make it live.
- The earlier client-ID/HMAC contract is superseded: no signature envelope or
  canonicalization is needed for these backend API-key flows. Never put API keys
  in browsers, definitions, or plaintext database fields. Reversible storage is
  also rejected for Vxpipe-issued keys: keep only a one-way hash. Recoverable
  upstream credentials remain a separate concern. Hash storage does not replace
  TLS, scoped-token lifecycle, or credential management.
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

[design]: ../labnotes/20260905-0405-call-definition-design.md
[architecture]: architecture.md
[mcp-design]: ../labnotes/20260905-0405-call-definition-design.md#applicationtenant-mcp-integrations-and-agent-enablement
[json-design]: ../labnotes/20260905-0405-call-definition-design.md#representative-json-shape
[context-design]: ../labnotes/20260905-0405-call-definition-design.md#working-room-context-schema-candidate
[context-authorization]: ../labnotes/20260905-0405-call-definition-design.md#authorization-transaction
[web-admission]: ../labnotes/20260905-0405-call-definition-design.md#web-participant-admission-routes--approved-g2-routing
[api-admission]: ../labnotes/20260905-0405-call-definition-design.md#initial-context-and-api-key-admission--approved-g2-decisions
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
