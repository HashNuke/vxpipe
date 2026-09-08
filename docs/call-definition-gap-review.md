# Call-definition gap review

Reviewed: 2026-09-06 UTC
Last updated: 2026-09-07 UTC
Status: G1 and G2's web routes, initial variables, API-key admission with one-way
hash storage, single-use tokens with existing-call recovery and no automatic
call-record expiry, prepared token-join or direct-backend connection, explicit
entry participants/startup, and one participant per definition key per call approved;
R01–R05 now approve OTP/CLI key bootstrap, tenant-bound `admin`/`calls` scopes,
multiple independently revocable keys, key revocation without invalidating
issued join tokens or established connections, and five-minute default tokens
with longer lifetimes accepted from the authenticated token requester.
G3 initialization approved with no variable defaults, and submitted variables
updates continue through conversational interruption under existing checks.
Reads containing a forbidden section fail with a permission error and no values.
Object updates recursively merge objects and preserve omitted nested variables;
shallow sections are preferred. Explicit null clears nullable variables without
deleting their keys; physical deletion is deferred. Variables root keys name
sections, direct section keys name variables, and the variable tool uses literal names.
Unpopulated authorized reads return a single null at the requested value level,
without nested placeholders or stored defaults. Updates populate variables
iteratively: datatype checks remain, but required-variable completeness is not
validated at setup or on updates.
Agent section grants are read-only or read+write, never write-only. Every writer
can read its section; omitted grants give no access. The write-only projection
and error-handling proposals are withdrawn.
Naming is approved as Call Variables, grouped into sections with variables inside.
The agent receives MCP results and then updates variables through Vxpipe tools;
no remote MCP awareness or automatic result-mapping layer is required.
A dedicated room-scoped `CallVariables` GenServer owns values, schemas, grants,
and revisions, and receives tool calls directly without `RoomAuthority` or a
current-activation check. Agent transfer shuts down the source's execution
subtree, but already-submitted variable requests can finish. Additional schema
complexity limits are not adopted now; datatype and value-size checks remain.
G3 is resolved. G4's ordinary-interruption rule is approved: submitted MCP calls
finish within their existing timeout because interrupting speech does not imply
intent to cancel a tool. A submitted MCP request that times out without a
definitive remote result reports outcome `unknown`, without automatic executor
retry; a later agent-requested tool call is a separate invocation.
Background execution uses one application-level running acknowledgement and
later conversation update for every model provider, not native async branches.
Late confirmations are deferred as external events that a future gateway
mechanism could route to an active call room/agent, not current MCP reconciliation.
Generic platform confirmation is excluded for now: agent instructions handle
conversational confirmation and the application/MCP owns enforceable business
authorization. Prompts are not security checks; Vxpipe tool-access checks remain.
G5's call-level client tool visibility and explicitly full-visibility sample
calls are approved, with all tool events hidden when visibility is unspecified.
Per-tool overrides are also approved: target the participant definition key plus
its local configured tool key, with the call-wide default as fallback. Independent
tool-history storage always saves observed metadata, arguments/request payloads,
and responses/results/errors, with existing credential/header exclusions. Available
transcripts/turn details, committed variables, and observed usage/model/cost data
are stored when permitted. R38 separates live transcript sharing from transcript/
audio retention, superseding blanket media storage without policy; audio still
requires enabled/permitted recording, not automatic processing for archival purposes. Variable
history now uses turn/tool-linked full post-update snapshots, the existing saved
tool arguments rather than a separate changeset, and a latest-snapshot pointer
on the call record. Database-backed variable updates return success only after
that snapshot/pointer transaction commits. Retention periods resolve from tenant
override, then application setting; the application default is retain forever.
Finite retention for completed calls starts at `ended_at`; active calls are not
expired, and forever has no expiry threshold. Current application/tenant periods
apply to all calls, past and future, without per-call retention settings. Expiry
deletes the call record and all associated Vxpipe-managed data, not just payloads.
General voice/LLM-input redaction is deferred; deterministic sensitive collection
such as DTMF need not involve the LLM. G7's three first-message modes and
first-activation-only greeting are approved. G8's source-agent responsibility
until committed handoff and failure return to that agent are approved. Optional
call-level `opening_audio` plays a supplied file or cached fixed-text TTS before
normal conversation. Room/participant capabilities may warm up during playback,
but participant audio is withheld until it completes. All API clients now use
preparation followed by token joining, without a separate direct-start path.
Other configuration, lifecycle, protocol, and persistence questions remain below.
Extra database-commit reconciliation is not required for this slice.
Record creation and actual live-call start have distinct approved timestamps.
Documentation only; no runtime implementation.

Current review count: **6 individual decisions** in the numbered backlog below.
R01–R06, R08, R10–R15, R17–R23, R26–R40, and R42–R45 are resolved; R07's same-call caller
reconnection, R16's retry exceptions, and R24/R25 are deferred, while R09 is superseded by
removal of direct WebSocket setup. Additional tokens do
not supersede earlier unused ones; initial variables already belong to creation.
Personalization and business-time interpretation belong to agent/application
instructions with permitted variable/date tools; no template or timezone hierarchy
is added. R13 allows protected backend-initialized routing variables while
transfers remain participant-ref-only. G1, G3, and G7's current-slice decisions
are resolved; G2/G4/G5/G6/G8 retain follow-up context, G10's current scope is resolved,
G9's media-policy structure is resolved, and G11–G13 still contain proposals.
The G headings organize the background, not the count. Object merge versus
replacement and preservation of
omitted nested variables, explicit-null clearing, direct-variable addressing, missing
reads, and iterative population without required-variable checks are
resolved within G3. The read-only/read+write decision removes the write-only error
question. Naming and agent-mediated MCP result updates are also resolved;
dedicated variable ownership and submitted-write lifetime are approved, and
additional schema-complexity caps are not adopted now. G3 is closed in
documentation; implementation remains pending.
MCP interruption, timeout-outcome reporting, and no automatic executor retry for
that timeout resolve part of G4; its remaining decisions are enumerated below.
Deferring late notifications removes that scenario from the current MCP scope;
other G4 questions still need review.
Excluding generic platform confirmation settles that question without closing G4.
The common background-tool workflow is approved. Explicit cancellation is
[deferred for later review](issues/explicit-tool-call-cancellation.md), not
required for this slice; the proposed opt-in policy is not approved. Other G4
questions remain pending and are counted individually below.

## Individual decisions awaiting review

**6 pending decisions (R41 and R46–R50).** This is the current approval backlog,
not a count of G headings, tests, implementation tasks, or every configuration key.
Each row is one independently reviewable policy/contract choice. R01–R06, R08,
R10–R15, R17–R23, R26–R40, and R42–R45 are resolved; R07/R16/R24/R25 are deferred and R09 is superseded,
all excluded from the count. The next five pending decisions are **R41 and R46–R49**. Mark rows resolved or
deferred as decisions are made and update this count; do not renumber the remaining IDs.

| ID | Background | Decision / review status |
| --- | --- | --- |
| R01 | G2 | **Resolved:** trusted OTP/CLI administration creates the first API key without an existing key. |
| R02 | G2 | **Resolved:** keys are tenant-bound with `admin` and `calls` scopes; no per-definition allowlist or arbitrary per-operation permission scheme is approved. |
| R03 | G2 | **Resolved:** multiple independently revocable keys are allowed, including overlap during rotation. |
| R04 | G2 | **Resolved:** revocation blocks further use of that API key, not previously issued join tokens or established connections; tokens are not coupled to API keys for revocation. |
| R05 | G2 | **Resolved:** tokens default to five minutes from issuance; the authenticated requester may request a longer lifetime, with no additional maximum approved here. |
| R06 | G2 | **Resolved:** another token for the same eligible unstarted call does not invalidate earlier unused tokens; each keeps its own expiry/single-use status, with shared admission checks preventing duplicates/takeover. |
| R07 | G2 | **Deferred:** same-call caller reconnection is outside the initial slice. After the logical call ends, connecting again starts a new call; temporary transport interruption is not automatically call termination. |
| R08 | G2 | **Resolved:** all API clients use authenticated preparation to obtain a token, then token-based joining; no separate direct WebSocket start/initialization path. |
| R09 | G2 | **Superseded:** the direct WebSocket initial-variables message is removed, so its proposed setup deadline/size policy is not applicable or adopted elsewhere. |
| R10 | G2 | **Resolved:** already covered by call creation, which accepts declared initial variables from the authorized creator/backend/trusted ingress; unknown values stay unfilled for permitted tools, without a new automatic lookup/resolver feature. |
| R11 | G2 | **Resolved:** personalization stays in agent instructions using permitted variable reads; no new interpolation/template/binding engine. |
| R12 | G2 | **Resolved:** locale/timezone/business-time context belongs to the integrating application and agent instructions, with date/current-time tooling; no new call-level fields/default hierarchy. |
| R13 | G2 | **Resolved:** the backend may prefill an authorized dial destination through a declared variable; a participant selects that protected section/variable instead of a literal number, while transfer tools accept only allowed participant refs. |
| R14 | G4 | **Resolved:** no automatic tool/MCP executor retries initially, including known non-submission failures; return the outcome and treat any later model-requested call as a separate invocation. |
| R15 | G4 | **Resolved:** skip the trusted read-only/idempotent-write/side-effect classification layer for now. |
| R16 | G4 | **Deferred:** automatic retry/business-idempotency exceptions belong to the dedicated issue, not the initial executor; call-creation idempotency and admission recovery remain separate. |
| R17 | G5 | **Resolved:** `tool_visibility` is `hidden`, `metadata`, or `full`; optional `tool_visibility_overrides` maps participant definition key to local tool binding key to level. Binding overrides win; omission hides events; trusted creation may replace the definition policy pair. |
| R18 | G5 | **Resolved:** qualified by R38 to store permitted available transcripts, turn details, usage/model/cost observations, committed variable snapshots, and complete observed tool history. Approved room-wide transcript/audio storage booleans are distinct from live sharing; recording must be enabled/permitted, without new usage/tool/variable toggles or invented data. |
| R19 | G5 | **Resolved:** application/tenant `call_retention` is `"forever"` or a finite duration object such as `{"seconds":2592000}`; application omission defaults forever, tenant omission inherits, and explicit tenant forever overrides a finite application setting. |
| R20 | G5 | **Resolved:** periodic background sweeps select eligible completed calls using current retention; not instant per-call deletion. Exact deployment interval/default is unspecified, not an hourly policy or deletion SLA. |
| R21 | G5 | **Resolved:** delete all managed external call objects first, treating definitive not-found as absent, then delete call-owned database data; retain records/references on failure and retry in later sweeps, while coordinating late writers. |
| R22 | G6 | **Resolved:** initial remote adapter supports revision 2026-07-28 Streamable HTTP, JSON and request-scoped SSE responses, with revision-specific metadata/lifecycle; other revisions/legacy transports require explicit tested compatibility. |
| R23 | G6 | **Resolved:** use a proper JSON Schema validator, baseline 2020-12, on actual outgoing arguments against pinned inputSchema before submission; reject unsupported enabled bindings before exposure, never weaken constraints or automatically fetch external refs. |
| R24 | G6 | **Deferred:** store received responses and descriptors with observed outcomes; the agent chooses authorized next steps. Detailed result projection and document/media inspection belong to the dedicated issue, not automatic fetching or a text/JSON-only policy. |
| R25 | G6 | **Deferred:** server-requested sampling/elicitation and related interactions belong to the dedicated issue; advertise no unimplemented capabilities, report missing capability clearly, and add no continuation/retry exception. |
| R26 | G6 | **Resolved:** trusted configured endpoints, verified HTTPS and SDK-aligned outbound address/rebinding protections; private destinations need explicit host permission, not tenant bypass; no automatic redirects or forwarded credentials. |
| R27 | G7 | **Resolved:** configurable 30-second required provider/connection readiness deadline from post-join startup; fail early on terminal failure or abort/release resources on expiry; deliberate opening playback is not a readiness failure. |
| R28 | G7 | **Resolved:** configurable 15-second idle notification only while an agent genuinely waits for caller input; instructions choose nudge/wait/permitted hangup, not automatic silence termination or repeated announcements. |
| R29 | G7 | **Resolved:** no automatic periodic long-tool progress speech; instructions own kickoff/results and ordinary background conversation. Startup/tool wait music is deferred in its own issue. |
| R30 | G7 | **Resolved:** limits.max_duration_ms defaults to 1800000; definition overrides tenant, then application, then platform default. Pin it per call, measure from actual started_at without transfer/recovery reset, and end with a clear duration-limit reason. |
| R31 | G7 | **Resolved:** agent instructions own closing wording and when to invoke existing hangup; no platform speak-then-end API, drain deadline, or automatic pending-hangup cancellation on interruption. No prompt-based playback guarantee. |
| R32 | G7 | **Resolved:** when configured provider AMD reports machine, disconnect that outbound destination leg, preserving a transfer's caller/source; unknown still needs explicit acceptance within the existing deadline. Detection is optional, uncertainty remains honest, and voicemail-message delivery is deferred to its issue. |
| R33 | G8 | **Resolved:** call-level transfer_policy holds shared defaults; source transfers remains allowed participant refs and destination-specific connection/acceptance requirements stay with the destination; no named/source-default/per-pair machinery. |
| R34 | G8 | **Resolved:** agent conversation/capabilities ready; human usable media plus explicit acceptance through pending-leg press-1 DTMF or authenticated web control message bound to destination and pending attempt; no stale/source/model acceptance or implicit admission. |
| R35 | G8 | **Resolved:** configurable 30-second total transfer attempt from accepted preparation, including dialing/acceptance; terminal failures end early, timeout/failure stops destination and returns typed outcome to source, late callbacks cannot commit, exact-leg cleanup without auto-redial. |
| R36 | G8 | **Resolved:** exactly one bounded permitted-source restoration attempt, never reset by restart/retry loops; if it fails with no usable conversation, end the call, while a valid working human conversation may continue. Detailed cause stays internal, including against sample full visibility; public/agent outcomes are generic. |
| R37 | G8 | **Resolved:** initial scope includes private human-destination briefing and optional notice before explicit acceptance/bridge, isolated from the caller and using only permitted minimum-necessary information. General concurrent-agent consultation is not approved; R38 supplies the policy/commit boundary. |
| R38 | G9 | **Resolved:** normal media_policy and participant while_present use complete audio/transcript source-to-recipient allowlists and independent room-wide record_audio/save_transcripts. Omission inherits, empty maps allow none, present restrictions intersect and storage false wins; enforce before main-media commit, with isolated pre-acceptance briefing. |
| R39 | G10/G2 | **Resolved:** no API creation idempotency key or deduplication cache; repeated authorized creation may create separate prepared records for later authorized deletion. Same-call token/admission and telephony webhook deduplication remain separate and intact. |
| R40 | G10 | **Resolved:** short admission claim, no transaction spanning startup; identify existing room/leg to finish bookkeeping, never repeat a crashed call or speculatively redial an uncertain one. Record failed/unknown appropriately and clean up known resources; no general recovery framework. |
| R41 | G11 | What happens when the asynchronous archive cannot keep up: continue with an explicitly incomplete record or stop the call? |
| R42 | G11 | **Resolved:** immutable publication revisions use their persisted UTC record timestamp for details-YYYYMMDDHHMMSSmmm.json under the call-owned prefix. Same snapshot retry reuses its identity/file; changed contents create a new revision without a schema_version change merely for values. Keep a latest-publication pointer, detect filename collisions, and never treat timestamps as unique identity or overwrite earlier revisions. |
| R43 | G11 | **Resolved:** finalize outside the room with a configurable 60-second post-end reporting window; publish early when expected work settles, otherwise publish permitted available data with honest pending/missing components. Later facts may refresh publication under R42; no call extension, work cancellation, or false completion during outages. |
| R44 | G12 | **Resolved:** retain observations and derive effective usage per operation attempt/component; distinguish deltas from cumulative totals and estimate/final/correction status. Identity-proven duplicates do not add again; final supersedes estimates, explicit corrections may decrease/increase, and failed/interrupted usage is retained without invented zero. |
| R45 | G12 | **Resolved:** always call-scoped with honest optional participant/service-interval/turn attribution, no forced allocation or duplicate charges. Keep usage separate from unavailable cost and preserve real namespaced provider IDs for optional asynchronous supported billing lookup outside the live call. |
| R46 | G12 | Which pricing source/version determines recorded cost, and how are unavailable usage or prices represented? |
| R47 | G13 | Which provider options belong in profiles versus engine policy, and how do unsupported combinations fail? |
| R48 | G13 | What model-context budget and history truncation/compaction policy apply to long calls? |
| R49 | G13 | How should a tool result too large for model context be bounded or summarized without misrepresenting it? |
| R50 | G13 | When may a failed provider be replaced, and how must fallback preserve permissions, tool semantics, and cost attribution? |

Not counted as current approval blockers:

- already approved behavior awaiting implementation, regression tests, migrations,
  exact hash/key encoding, indexes, adapter internals, or safety checks that follow
  from an approved contract;
- explicit invocation cancellation and late external-event delivery, already
  deferred, and generic platform confirmation, excluded for now;
- general voice/LLM-input redaction, deferred by the latest decision;
- same-call caller reconnection, deferred for the initial slice (R07);
- automatic tool retries, classification, and business-idempotency exceptions,
  deferred under the dedicated issue rather than a current executor prerequisite;
- separate future DTMF collection integration, OAuth onboarding/refresh, and
  optional post-call summary/evaluation features; and
- an additional automatic expiry for unstarted records, which is not approved.
  Separate administrative housekeeping does not reopen that admission decision.

Discovery bounds/cache isolation, webhook identity normalization, transcript
input facts, and media-clock/provenance checks remain engineering requirements
under the relevant contracts. They are not counted once per mechanism or test.
If implementation exposes a genuinely new policy choice, add it explicitly
rather than silently inflating or hiding the review backlog.

## Conclusion and scope

Keep the participant-first definition, `entry_caller` and `entry_receiver`,
direct `transfers` ref lists, agent-scoped tool enablement, room-owned variables,
and immutable resolved plan. The scenarios below do not require nodes, edges,
named transfers, or a general expression language. The missing pieces are mostly enforceable runtime
contracts around those primitives, not a different top-level JSON structure.

This reviews the [call-definition labnote][design] and
[runtime architecture][architecture] at Vxpipe commit
`e7a769e0ce4ec3cc0bb39faf300f759f125d9c4e`. Source inspection confirms that
`CreateRoom` still selects a preset, not a call definition; tools are trusted
Elixir modules; there is no definition compiler, call variables, remote MCP client,
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
| Scheduling: [assistant][scheduling], [booking tool][booking], [external workflow][workflow] | Agent prompt, scoped variables, enabled calendar tools, transfer to a human, hangup | The supplied tools use function webhooks, not MCP. They need a remote MCP facade or trusted host adapter. The agent records MCP results through Vxpipe variable tools. A timeout without a definitive remote result reports unknown. Conversational confirmation belongs in agent instructions; enforceable business authorization belongs to the application/MCP, with no generic platform confirmation now. Business-time interpretation belongs to application/agent instructions with date tooling; automatic retry/idempotency enhancements and late recovery notifications are deferred. The external scheduling system remains the booking authority. |
| Intent routing: [assistant][intent], [request overrides][intent-request], [instruction handler][instructions] | One agent retrieves instructions through a tool; alternatively several specialized agent definitions transfer by ref | Personalization uses agent instructions and permitted variable reads. Retain trusted ingress metadata, provenance of retrieved instructions, and closed participant destinations. Runtime text must not grant tools or introduce arbitrary telephone destinations. |
| Voicemail: [assistant][voicemail], [native voicemail tool][voicemail-tool] | Outbound human connection intent, agent first-message policy, platform ending tool | Configured provider detection reporting machine ends the attempted destination leg; transfer source/caller remain, unknown still requires explicit acceptance within the existing deadline, and leaving a message is deferred. Closing wording and choosing hangup belong to agent instructions, without a platform speak-then-end or guaranteed-playout workflow. |
| SMS verification: [assistant][sms], [code tool][code], [SMS tool][sms-tool] | Agent-scoped remote tools, typed verification variables, provider-neutral external action | Requires an external verification service or trusted host implementation. That service owns verification, expiry, attempt limits, recipient binding, and replay protection; the agent can record its returned outcome in permitted call variables. Storing an outcome does not override the service's rules. Do not run JSON-provided JavaScript. |

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
P1 blocks the corresponding first compiler/private-variables/external-action slice;
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
`billing` read-only `intake` access. Transfer/variable tools remain derived from
their existing grants; tool aliases must not collide with generated names.

G1's authoring ambiguity is resolved, but no compiler was implemented. A future
compiler checkpoint still needs canonical positive/negative fixtures and a
supported-variable/keyword matrix. Partial illustrations are not complete executable
definitions, and the broad representative JSON is not a commitment to implement
every variable in the first slice. No new dated schema release is published here.

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
variables and returns a scoped join token without starting the room. A join route
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

For caller/reception/billing/human-support, live startup selects only caller and
reception; token issuance alone starts neither. If `opening_audio` is configured,
establish caller playback; room/participant capabilities may start and warm up,
but withhold participant audio and normal conversation until playback completes.
Otherwise use normal startup.
Activate an agent receiver only after any notice and required readiness.
Other catalog entries do not automatically start providers or dial out; prepare them when an authorized
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
its identity, or replace their connection. Permitted agent re-entry retains its
participant identity and receives a fresh activation; same-call caller
reconnection is deferred. Different staff roles use different definition
keys, and another call gets its own independent participants.

Enforce the binding during admission and transfer preparation, including races
and repeated requests: neither a second participant nor duplicate pending
preparation may be created. Direct transfer refs remain unambiguous without an
instance-selection variable. The count is a fixed contract, not a JSON option.
Detailed wire responses and admission/transfer retry semantics remain follow-ups;
cardinality itself is resolved. See the
[approved one-participant contract][participant-cardinality].

**Approved initial variables:** the integrating application's backend supplies
values directly in the section structure declared by the call definition. Drop
the separate `input_schema` and JSON Pointer initialization mappings. For order
`ORD-1042`, it supplies `initial_variables: {order: {id: "ORD-1042"}}` to a definition
declaring that section. Admission initializes it; several agents can read it
while none has write access. The definition declares the data shape and
permissions, not a second remapping layer. The authorized backend may prefill
any declared section, including one that no agent can write. Initial variables
cannot override providers, tools, either entry ref, tenant, or other definition
policy.
There are no variable defaults: only values supplied at call setup prefill it.
Schemas describe the allowed structure; they do not manufacture initial values.

**Approved authentication and common connection flow (R08):** replace separate
client IDs, client secrets, and HMAC-signed envelopes with a gateway-issued API
key in the backend's `Authorization: Bearer <api_key>` header over HTTPS. Payloads are
unsigned. The backend authorizes the business variables; key verification checks
the integrating application's tenant/operation authority, not customer identity.

1. **Prepare/create:** the backend POSTs initial variables to the
   preparation endpoint, which grants no CORS access. Vxpipe validates it, stores
   a prepared call with pinned revision/variables, and returns an opaque short-lived
   single-use join token scoped to that call and participant. No room or live
   conversational providers start yet; opening-asset preparation is separate.
2. **Join with the token:** the backend may give its frontend only the token,
   not private variables or the API key, or join using the token itself.
   Accepted admission atomically consumes the token before activating that same
   call, not when the browser receives confirmation; conversation waits for
   transport, any configured startup notice, and required capabilities. No client
   can replace the prepared variables, and joining must not return their private
   contents in a snapshot. Later event, tool, and speech disclosure remains a
   separate policy responsibility.

The former direct backend WebSocket path is superseded: no API key in a media
socket handshake starts a call, and no first-message initial-variables setup is
required. This removes R09's specific setup-limit question; the proposed ten
seconds/64 KiB are not approved for HTTP preparation, token exchange, or any
other route. Existing-call token issuance and eligible first admissions to live
calls remain supported under the same authorization/lifecycle rules.

A WebSocket upgrade is a [GET handshake][websocket-handshake], not a JSON POST
that upgrades. Browser WebSockets require server-side [Origin validation][websocket-origins],
not ordinary HTTP CORS grants. Browser HTTP join/signaling can use a configured
CORS allowlist; neither policy replaces authentication. The [browser WebSocket
interface][browser-websocket] cannot supply arbitrary authorization headers;
token delivery (for example, the first message) still needs its wire contract.
Keep credentials/variables out of query strings and logs. Existing browser WebRTC
remains supported; this auth decision does not switch its media transport.

The gateway generates random API keys through authorized management and returns
each once to the backend. Gateway authentication uses a credential-store port;
persistence owns storage, Calls owns preparation/activation, and the engine
receives neither keys nor join tokens.

**Approved key administration and scopes (R01–R03):** use trusted OTP/CLI
administration to create the first key without an existing API credential.
Each key is tenant-bound and permissions use `admin` and `calls` scopes. Do not
introduce per-definition allowlists or arbitrary per-operation grants from the
earlier proposal. This scope split does not decide that `admin` implies `calls`
or specify a complete admin HTTP API/endpoint matrix. Multiple independently
revocable keys may coexist for a tenant. Rotation can issue a replacement,
deploy it to an integration, then revoke the old key without revoking others.

**Approved API-key revocation (R04):** reject subsequent authentication with the
revoked key, including attempts to issue more tokens. Previously issued unused
join tokens remain valid subject to their own expiry, single-use status, scope,
and current tenant/call/participant admission eligibility. Do not link token
validity to the requesting API key's revocation status. Revocation does not end
established connections; explicit call/session termination is separate.

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
[approved variables and admission contract][api-admission] for ownership,
alternatives, and future verification steps.

**Approved join-token lifetime (R05):** default to five minutes from issuance.
An authenticated backend requesting a token can request a longer lifetime,
both during preparation and through the existing-call `join-tokens` route.
No additional maximum or application/tenant TTL override hierarchy is approved
by this decision. The browser cannot extend a token when joining. Its own
expiry and single-use admission rules remain independent of the requesting
API key's later revocation. Exact duration field/units are implementation detail;
requesting a longer lifetime does not extend the live-call duration or impose
an expiry on the prepared call record.

**Approved additional unused tokens (R06):** issuing another token for the same
eligible unstarted prepared call does not invalidate earlier unused tokens.
Each retains its own expiry and single-use status. All claims still pass the
same tenant/call/participant eligibility checks; two distinct tokens do not allow
duplicate caller admission, active-connection takeover, or reuse of an ended call.
For example, if the first issuance response is lost, the backend can request
another token without revoking the first. Whichever valid token admits the caller
first does not grant another token permission to admit that caller again.

**Approved single-use admission and existing-call recovery:** an unused,
unexpired token may retry before acceptance. Once admission is accepted, it
stays consumed even if startup fails or the browser loses the response. Only
one racing attempt may claim it; no transaction spans room/provider startup.

Replacement issuance for an eligible unstarted call goes through the integrating
backend, which rechecks the user's authorization and uses its API key with
`join-tokens`. Token expiry alone does not require a new prepared record.
Vxpipe checks the tenant/call/participant and current eligibility, reconciles an
in-progress admission first, and rejects ended calls, unauthorized access, and
active-connection takeover. A revoked API key cannot request a fresh token;
previously issued tokens do not inherit that key's revocation. Recheck eligibility
at token claim; issuance does not guarantee that a later join is still allowed.
A caller's old token or public call ID alone never authorizes fresh-token issuance.

Issuance preserves the existing call record and pinned definition/variables. For
an eligible prepared call, subsequent joining activates the room once. The same
route may authorize first admission of an eligible transfer destination or other
not-yet-admitted participant into an existing live call, without restarting that
room or resetting its variables. It does not authorize a disconnected caller to
resume a running call. Expiry prevents future token claims, not continuation of
an already accepted call. Gateway owns token
authentication; Calls coordinates the lifecycle through persistence ports.
See the [approved recovery contract][join-token-recovery].

**Approved caller-reconnection scope (R07):** same-call caller reconnection is
deferred. A fresh token authorizes its scoped admission, not proof that the same
person has returned. Once the logical call ends, connecting again starts a new
call with a new record/identity; it does not resume or reset the ended call.
Replacing an expired token before a call ever starts remains supported. This
does not remove first admission of another eligible participant into a live
multiparty call. Temporary transport interruption is not automatically a
call-ending disconnect; the precise failure/end trigger is not yet specified.
No blanket rule ends the room when any participant disconnects, and no browser
session-tracking mechanism is added.

**Approved token-only expiry:** a prepared call is only a database record with
its pinned definition and initial variables, not a live call process tree. It has
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
or delivery time. Transfers, duplicate events, and same-call recovery
preserve it. Live duration and `max_duration_ms` exclude the preparation wait;
a never-started record has no live duration. Creation at 10:00, start at 10:15,
and end at 10:18 means a three-minute call. Provider billing intervals remain
separate. See the [approved timing contract][call-start-timing].

Remaining G2 review and resolved follow-up clarifications:

**Token details and separate storage policy:** R40 recovers bookkeeping about
existing admission work, not a new call after runtime failure. No creation
idempotency feature is offered (R39). Additional issuance does not supersede unused
tokens (R06 resolved); no token deduplication/cache feature is added.
Retention periods now have an application default
of retain forever with tenant overrides; finite-expiry cleanup uses the approved
periodic external-first contract below. Single-use claim, backend-mediated recovery,
the existing-call token route, and the absence of automatic call-record expiry
are resolved.
R01–R05 settle first-key creation, the tenant/scope split, multiple-key rotation,
revocation effects, and default/requested token lifetime. Exact key encoding,
hash profile, and duration encoding are implementation details, not additional
approval items. HMAC algorithm, canonicalization, and signature variables are
no longer questions for this contract.
Future WebSocket token-delivery encoding and structured failure responses are
transport implementation work, not a second direct-start workflow. Removing the
direct setup message does not approve new limits on another endpoint.
Provider webhooks are not API/browser clients; telephony adapters retain their
authenticated ingress and common admission responsibilities, not a separate
direct API-client start endpoint.

**Admission and transport-failure lifecycle details:** the singleton participant
binding and fresh-token route are not permission to resume an ended call or evict
an active connection. Caller reconnection and its grace/session policy are
deferred rather than current prerequisites. Detailed join/transfer responses,
internal claim mechanics, and the boundary between temporary transport failure and actual
call termination remain unspecified. Pending-startup reconciliation must not
silently admit an already-started caller again. Multi-instance selection is not
required.

**Initial variables already cover telephony (R10 resolved):** the authorized
creator, integrating backend, or trusted ingress adapter supplies any known
declared `initial_variables` when creating the call. A telephony adapter uses
that same contract; there is no additional required automatic customer lookup or
admission resolver. Unknown values stay unfilled for the normal permitted variable
tools to populate. This does not require complete variables or definition
defaults. Provider caller number remains ingress/contact metadata, not silently
verified customer identity. R10 repeated an existing contract, rather than
requiring a new admission feature.

**Approved personalization (R11):** leave it to agent instructions and the
existing permitted `read_variables` tools. The agent obtains available values and
handles missing information through its instructions and conversation. No new
template/interpolation/binding engine or missing-binding compiler policy is
needed. Existing variable permissions and absence/datatype rules remain intact.

**Approved business-time ownership (R12):** the integrating application owns
locale/timezone/business-time context and supplies it through agent instructions.
Provide date/current-time tooling for fresh observations under the ordinary
enabled-tool contract. Do not add call-level locale/timezone fields or a default
hierarchy. Exact new tool naming/schema is not selected here. Authoritative call
timestamps remain separate from conversational time interpretation.

**Approved dynamic dial destinations (R13):** a participant connection may use
either its existing literal `number` or candidate
`number_from_variable: {"section": "routing", "variable": "support_number"}`,
never both. These are direct declared section/variable keys, not expressions or
paths. The trusted backend chooses an authorized number and supplies it through
`initial_variables`; it must not blindly relay a caller-selected destination.

Reject definitions granting any agent write access to a routing section referenced
this way. Read permission is optional and not needed for engine resolution;
existing section grants suffice without a new per-variable permission type.
The engine resolves the pinned definition/reference against protected initialized
data. Missing/null/invalid values fail before dialing through the existing typed
transfer failure, retaining the source agent without inventing a default number.

The agent still invokes transfer with only `human-support-agent` or another
compiler-allowlisted participant ref, not a phone number, provider, URL, or
variable reference. The executor rechecks the source's derived allowlist. The
model may choose timing and among permitted roles; arbitrary destination choice
is not delegated. Business timing restrictions, if needed, belong outside the
LLM. No generic outbound region/allowlist matrix, runtime routing-variable update
API, or expression system is approved. Literal-number behavior remains supported;
this is candidate definition syntax, not implemented runtime.

The [intent request][intent-request] supplies variable overrides, and the
[scheduling prompt][scheduling] includes time formatting. These illustrate the
need; they do not require a new template engine or application-time configuration
layer.

### G3 — P1, resolved: Variable initialization, authorization, and updates

**Approved initialization:** the [variables candidate][variable-design] has no
default values. Its earlier section defaults and proposed merge rules are
withdrawn. Only an authorized call-setup invocation prefills variables in the
declared section shape. Reject section-level and nested schema `default`
declarations. Capability/provider configuration defaults are a separate concern
and remain unchanged.

Validate supplied datatypes and value constraints before room/provider work,
without requiring missing variables. Omitted variables/sections remain unfilled in
storage, not automatically `{}`, `null`, or another value. Callers may explicitly
supply an empty section object and collect its variables later. Schemas and
permissions do not populate data, and later authorized variable updates remain
supported. Both labnote examples omit
variable defaults; the invocation prefills only `customer.id`, leaving `intake`
unfilled. There is no default-merge or input-remapping contract left to decide.

**Approved missing reads and incremental population:** an authorized read of a
declared but unpopulated section returns null in its value slot, retaining the
normal revision metadata. Null is returned only at the requested value level;
do not construct null-valued nested variables or store the response as variables.
A partial section is returned as stored, without filling missing children.
Reads do not mutate state or revisions. Forbidden sections still fail the whole
request, and unknown sections still receive the existing typed error. No new
variable-read API is introduced.

The first `update_variables` populates an unfilled section with its supplied
object; later updates recursively merge into it. The variable form can also
populate a declared direct variable in a new section. For an `address` section
with string variables, an agent can save `city` first and `postal_code` later.
Missing variables do not fail validation, including within nested objects. A
number supplied for either string variable still fails, with no partial commit.
The same section grants, room/agent identity, revision, and size checks apply.

This defers required-variable completeness checks, not datatype or other
supplied-value validation. It applies to both initial variables and updates;
there is no new final-completeness gate or configuration toggle. Call-definition
structure, tool argument envelopes, and external tools' own required inputs
remain separate contracts. The labnote examples remove their variables `required`
lists while retaining datatype and value constraints.

**Approved interruption rule:** let an already-submitted local variable update
finish, and use another tool call for a correction. The
[variables interruption contract][variable-interruption] adds no live-turn or
tool-cancellation check to the [authorization transaction][variable-authorization].
Room/incarnation, trusted agent identity, permission, deadline, schema, limits,
and expected section revision still apply, but current activation is not checked.
Transfer terminates the source agent's execution subtree, including capabilities
and model/tool workers, to prevent further requests. Already-submitted variable
requests can still finish after source termination. Stopping the room's variables
process itself is different: pending work has no completion guarantee.

If the original update commits first, the correction uses the resulting revision,
refreshing its permitted view if necessary. If the correction wins a race against
the same revision, the delayed original conflicts; do not blindly replay it with
a newer revision. Committed values stay committed, even if the turn is cancelled
or its acknowledgement is lost. Completion cannot revive cancelled model speech.
The earlier live-turn check and mutation-ID deduplication/journal proposal are
withdrawn for this decision. External tool outcomes remain a separate G4 review.

**Approved read authorization:** inform the agent of its permitted sections, but
still validate every request at the dedicated variables process. If any requested
section is forbidden, return a permission error and no variable values, including otherwise
permitted values from that same request. Do not silently filter forbidden names.
The agent can retry with permitted sections only; successful reads do not add
unrequested sections. This clarifies existing section grants, not a new
variable-level permission system. Error responses must not expose hidden values.

**Approved permission simplification:** agent section grants are `["read"]` or
`["read", "write"]`; an omitted section grants no access. Standalone
`["write"]` is invalid at definition compilation, not silently expanded into
read+write. Every writable section is readable, with its value and revision in
the normal model projection and its resulting value in successful update results.
Ungranted sections expose neither values nor revision metadata in that projection.
Read-only grants expose the read tool; read+write grants also expose update tools.
This withdraws revision-only writable views and the special write-only error
proposal. Ordinary authorization and variables privacy still apply to errors,
other sections, public events, and other participants.

**Approved object merge, further details pending:** offer both
`update_variables(section_name, data)` for multiple variables in one call and
`update_variable(section_name, variable_name, value)` for a single-variable
change. These names are approved; the sketches are not complete wire schemas. Both share
the existing atomic section boundary, write grant, validation, and revision
checks. The labnote's existing operation-list example already batched updates;
it is retained as an internal command candidate, not a third model-facing tool.
`update_variables` recursively merges supplied objects into the existing section;
omitted variables retain their values at every object depth. Where old and supplied
values are both objects, recurse rather than replacing the object wholesale.
For example, changing `intake.topic` preserves an existing `intake.summary`;
changing a nested `address.city` preserves its `postal_code`. This is a deep
merge, not just a deep copy. Check the expected revision and validate populated
values in the merged result, including retained values but not missing variables,
then commit once or reject the whole update without changing values or revisions.
This changes runtime values without introducing defaults or an initialization merge.
Prefer simple, shallow variables: make `address` its own section with `city` and
`postal_code`, giving it an explicit schema, grant, and revision boundary.
This is authoring guidance, not a ban on schema-permitted nesting or a runtime
flattening step. Call Variables is the approved terminology;
recursive object merging does not add array-element merge operations. Candidate
keys and planned module names are aligned with Call Variables; runtime code is
unchanged.

**Approved addressing:** keys at the root of variable data are section names;
direct keys within each section object are variable names. The definition's schema
wrapper is now `call_variables.sections`; its shape and revision metadata are
unchanged. `update_variable` selects
one exact declared direct variable; it does not interpret dots, JSON Pointers, or
array-index notation. Unmatched names fail validation rather than traversing or
creating a path. An explicitly declared punctuation-bearing key remains literal.
For example, use `update_variable("address", "city", "Newtown")` for a
direct variable. For a nested address in another section, use
`update_variables("profile", {"address": {"city": "Newtown"}})` and its recursive
merge behavior. Internal pointer encoding must preserve literal-name semantics.
No new tool, variable-level permission system, or path syntax is introduced.

**Approved clearing behavior:** both update forms accept explicitly supplied
null for a schema-nullable variable. It stores null while retaining the key, rather
than skipping or deleting it. For example, clearing `address.apartment` changes
`"4B"` to null without removing `apartment` or altering the other address variables.
An omitted variable remains unchanged. Nullability must be explicit: permitting an
absent variable does not imply accepting an explicit null, and cleared keys stay
present. Populated values, write grant, and expected revision still validate;
null in a non-nullable variable fails the whole update without mutation. No missing
value is automatically populated with null, and section roots remain objects.
Separate deletion tools and physical key removal are deferred, not prerequisites
for clearing a value. No null-means-delete convention is adopted.

**Approved ownership and limits:** one `CallVariables` GenServer per room
incarnation owns values, revisions, compiled schemas, and pinned per-agent grants.
Model/tool workers call it directly for reads, updates, and turn projections;
`RoomAuthority` is neither a request intermediary nor a per-operation permission
check. The variables process serializes its own validation and commits. Trusted
identity comes from the engine binding, not model-supplied arguments.
For database-backed updates, it waits for its snapshot-persistence port to confirm
the snapshot/latest-pointer transaction before adopting the values/revisions and
returning tool success. Storage errors cannot become memory-only success. The
adapter owns SQL; neither routing nor acknowledgement requires `RoomAuthority`.

Keep it under the room supervisor, outside each agent's execution subtree. No
activation mirror, deactivation acknowledgement, or live-agent query is needed
for variable operations. A transfer can complete before an already-sent A update
commits; B reads current committed data and may refresh later. Revision checks
still protect against lost updates. No transfer-time flush is promised.
Current tasks run under a shared task supervisor, so implementing the approved
agent-wide shutdown requires supervision work; stopping one participant process
or relying on `terminate/2` cleanup is not sufficient evidence.

Do not add schema-depth or declared-variable-count limits now. There is no
measured threshold or observed bottleneck motivating those proposed caps. Keep
datatype, supplied-value, value-size, and operation bounds without requiring all
variables to be populated. Additional complexity caps can be reconsidered with
evidence. This resolves G3; the write-only error proposal is already withdrawn.

**Approved naming and MCP result flow:** use Call Variables for the collection,
section for a group such as `booking`, and variable for a value such as `status`.
The definition uses `call_variables.sections`, invocation data uses
`initial_variables`, and an agent's section grants use `variable_permissions`.
Tools are `read_variables(sections)`, `update_variables(section_name, data)`, and
`update_variable(section_name, variable_name, value)`. Conversation history means
messages and tool calls/results; model context includes instructions, selected
history, and permitted variables. Neither is the mutable variable store.

The agent calls a remote MCP booking tool, receives its result, then updates the
relevant variables through our tools. The MCP needs no knowledge of Vxpipe's
internals. Vxpipe owns the variables and enforces the agent's section permissions,
datatype checks, and revisions. The proposed platform-only result sections and
automatic result-to-variable mappings are withdrawn, not prerequisites for MCP.
Read-only initial values remain supported; recording tool results requires
read+write permission on the chosen section. Booking/verification rules remain
the external service's responsibility. A copied result is not that service's
source of truth; G4 still owns other remote retry/cancellation and uncertain-outcome
questions beyond the approved conversational-interruption rule below.

### G4 — P1, partly resolved: Tool cancellation does not roll back an external action

**Approved conversational-interruption rule:** the user interrupting speech does
not establish that they intended to cancel a tool call. Let an already-submitted
MCP request finish within its existing timeout while the agent remains running,
for both read-only tools and actions. Spoken or typed interruption stops the old
conversational output, not that request. Keep its result associated with the
invocation for subsequent agent reasoning without reviving the cancelled model
continuation or speech. The result alone does not mutate variables or authorize
additional unsent tool calls from the interrupted turn.

Transfer still terminates the source agent's local execution subtree, including
model/tool workers; room shutdown also stops their work. Local termination is
not remote rollback. Explicit per-invocation cancellation is deferred to the
[cancellation issue](issues/explicit-tool-call-cancellation.md). The opt-in and
generated-tool proposal is recorded there for review, not adopted. Automatic
retry/idempotency enhancements are deferred; generic platform confirmation is
excluded for now and late recovery notifications are deferred below.
No durable operation worker or ledger is approved by the ordinary-interruption
decision. Today's
model request task still contains tool execution and is killed by interruption;
the approved separation needs implementation.

**Approved provider-independent background execution:** Vxpipe owns background
invocations for every model provider, rather than switching to native async-tool
semantics where available. Start supervised execution within the agent lifecycle,
acknowledge accepted work with a correlated running tool response, and allow
further conversation/TTS while it runs. Accompanying model text and tool calls
must both survive the adapter boundary.

Completion is a separate invocation-linked update to the latest conversation,
not a second ordinary result for an already-acknowledged tool call. The agent
coordinates any new speech with the current conversation. An acknowledgement is
not business success; tool results remain untrusted data. Provider encodings and
interoperability need verification. The original labnote includes planned tests
for conversation during blocked execution, result ordering, and mixed text/tool
output. This does not approve explicit cancellation policy, durable execution,
or the deferred external-notification mechanism. Implementation remains pending.

**Approved timeout-outcome reporting:** when a submitted MCP request reaches its
timeout without a definitive remote result, report outcome `unknown`. The timeout
is the known local cause; remote success or failure is unconfirmed. For example,
the booking service may have created a booking before its response was lost.
Do not present that timeout as confirmed failure or rollback. Keep an already-known
definitive success/failure result; pre-submission validation errors do not become
unknown merely because this classification exists. Unknown does not count as
success or automatically change Call Variables.

**Approved executor retry default (R14):** no automatic tool/MCP executor retry
initially, including failures known to occur before submission. Return the
definitive error or unknown outcome instead of silently submitting another
attempt. Ambiguous timeouts remain unknown; a booking may already exist and a
retry could duplicate it. A later agent-requested tool call is a separate
invocation, not a hidden executor retry. This does not provide exactly-once
execution or prevent the agent from requesting a duplicate action.

R15 skips the trusted read-only/idempotent-write/side-effect classification layer.
R16's automatic retry/business-idempotency exceptions are deferred to the
[retry/idempotency issue](issues/automatic-tool-retries-and-idempotency.md), not
current executor prerequisites. Call-creation idempotency (R39) is not offered;
R40 only recovers bookkeeping about existing work, never repeats a crashed call.
Those are separate from tool retries and ordinary database transaction handling.
Late business notifications and mechanisms to reconcile them are deferred below.
The existing local timeout remains in effect; no new wire format or operation-worker
architecture is approved here.

The labnote names retries, cancellation, and idempotency, but does not yet settle
the remaining interactions. A booking or SMS can succeed remotely before the local
request times out or is terminated during transfer. Retrying blindly can duplicate it;
discarding the result entirely can erase the only explanation of what happened.
The [scheduling workflow][workflow] even configures retries on booking POSTs;
that alone does not prove deduplication by the external API.

**Approved scope decision — defer late business notifications:** a late booking
confirmation is an external concern. In a future scenario, an MCP booking times
out, then the booking service sends a success webhook to the gateway. A general
external-event mechanism could route that information to the relevant room or
agent if the room is still active. This is not important for the current MCP
slice and does not require continuing or completing the original tool invocation.

Defer webhook/event ingestion, late-result delivery, polling, reconciliation,
and operation storage solely for this scenario. The earlier proposal for a
supervised operation worker with stable IDs/attempts and a private outcome ledger
is not a prerequisite. Future event authentication, correlation, delivery,
inactive-room handling, and agent use of the information remain undesigned here.
No event endpoint, automatic variable mapping, or call restart is approved.
The current timeout/unknown/no-automatic-retry and G3 variable contracts stand.

**Potential retry exceptions — deferred with R16:** any future automatic retry
after an ambiguous submission would need a documented provider idempotency
contract or a safe reconciliation strategy. No tool-classification or metadata
exception is approved by the default no-retry decision. MCP request IDs are
correlation, not business-action idempotency keys. Business validation, slot uniqueness, and atomic booking
remain responsibilities of the external system; call variables are not its
transaction database.

**Approved confirmation scope:** do not add a generic platform-level confirmation
mechanism now. An agent may ask "Shall I confirm this booking?" through its prompt;
that is conversational behavior. Any enforceable business authorization belongs
to the integrating application/MCP. Prompts are not a security guarantee, and
Vxpipe still enforces its tool allowlists, trusted identity, and argument checks.
The earlier proposal for confirmation bound to arguments, participant, variable
revision, and expiry is out of scope. No confirmation token, approval endpoint,
call-definition option, or generic confirmation state is required for this slice.

Do not introduce tool classification now (R15 resolved). Any future classification
or retry exception belongs to the deferred issue; explicit cancellation also
remains deferred rather than a current-slice prerequisite.
Do not announce successful sending or booking from a request-start event.
Progress speech is separate from result speech, with only one owner of each utterance.

### G5 — P1, partly resolved: Private variables would leak through the existing tool event path

This is a concrete integration hazard, not just an omitted future feature.
`RoomAuthority.emit_tool_call_started/4` puts arguments in an event;
`emit_tool_call_completed/5` includes the result. The
[RTVI codec][codec] sends both to the client. Today's clock tool is harmless,
but reusing that path for private variables or verification defeats the proposed
section permissions even if variable-update events contain only metadata.

**Approved call-level client visibility:** the call definition declares whether
clients can observe tool calls and payloads. The authorized backend/OTP host may
explicitly select visibility when creating the call, overriding the definition's
value. Resolve and pin the effective policy with the call record/resolved plan;
joining browsers do not set or upgrade it. Keep private execution payloads
separate from client projections and filter before transport delivery.

The policy supports hiding tool events entirely, exposing lifecycle metadata
without payloads, or including arguments/results. This replaces a mandatory
metadata-only projection plus special debug-session authorization. When both
definition and creation omit visibility, hide tool events entirely. Metadata
and full visibility require explicit selection. The call-wide key is
`tool_visibility`, with values `hidden`, `metadata`, or `full`. Optional
`tool_visibility_overrides` maps participant definition key to local configured
tool key to that same level, without an additional container or schema variant.
For example, `{"tool_visibility":"hidden","tool_visibility_overrides":{"reception":{"lookup_order":"metadata","create_booking":"full"}}}`
exposes only the two named reception bindings at their selected levels.
Omitting both means hidden with no overrides. An explicit trusted creation
selection replaces this effective policy pair; omission inherits the definition.
No deep-merge/patch API is implied, and binding overrides in the effective pair
still take precedence over its default.

**Approved per-tool targeting:** an override identifies the participant definition
key plus its configured local key in that participant's `tools` map. It selects
hidden, metadata-only, or full visibility for that binding and takes precedence
over the call-wide default; other tools inherit that default. Resolve this identity
from the invocation's server-owned participant/tool binding and pin the selections
with the call policy. Do not match solely on a remote MCP operation name or trust
client-supplied labels. This applies to the unified built-in/MCP tool map without
changing which tools an agent may execute.

For example, `reception` and `billing` can both configure `lookup_customer`.
Expose reception's lookup at metadata-only detail while billing's stays hidden.
Those are separate targets even if both bindings select the same remote operation;
changing one visibility override must not expose the other's events or payloads.

**Approved sample configuration:** calls created for `samples/` explicitly select
full tool visibility for the debug UI through effective `{"tool_visibility":"full"}`
with no overrides, using the same trusted call-creation mechanism. Replace the
policy pair so restrictive definition overrides are not accidentally inherited;
merely changing the default to full would not override a hidden binding.
No frontend-specific exception or additional debug-session grant is
required. A browser flag, route, or visual concealment cannot change that policy.
Existing credential/header exclusions still apply. The detailed failed-transfer
restoration cause is internal even for samples/full visibility. Visibility grants
neither tool execution nor additional agent variable or cross-call access. The current
gateway has not implemented this distinction.

**Approved independent tool-history storage:** always store all observed tool
invocation data with the call: identity/participant/tool metadata, timing/outcomes,
arguments/request payloads, and responses/results/errors. No tool-history enable
switch, metadata-only storage mode, per-tool payload selection, or arguments/results
opt-in. Hidden, metadata, or full client visibility does not alter this storage.
Project storage events independently from the engine source, not the browser-
filtered stream, excluding integration credentials and authorization headers
before persistence. This is not raw wire credential capture or new general
redaction. Retaining data does not authorize disclosure to clients. Save only
observed outcomes: unknown timeouts remain unknown, not fabricated remote results.

For example, a booking invocation hidden from the browser can still have its
arguments/result saved for an authorized operational review. A sample call can
show that result live and saves the same complete observed tool history. General
tool/event archival stays asynchronous; this capture policy does not add a SQL
acknowledgement gate to every tool or resolve archival failure handling.
No runtime persistence is added by this documentation decision.

**Approved available call data (R18, qualified by R38):** always save permitted
available transcripts, turn details, and observed usage/model/cost information,
alongside committed variables
and complete tool history. R38 qualifies the earlier no separate storage toggle
per category rule for explicit transcript/audio retention, independent from live
sharing. The approved room-wide booleans govern automatic storage paths without
a new usage/tool/variable toggle matrix. Not saving transcripts does not itself
stop permitted recognition.
Preserve
typed-text provenance, provider-final speech facts, and generated versus confirmed
delivered/spoken agent text, including interrupted/truncated state. Do not start
STT or other prohibited processing for archival completeness; missing or forbidden
transcription does not justify inventing a transcript. Missing usage/prices remain
unavailable, not zero or invented estimates; R44/R45 resolve usage accounting and
attribution while R46 pricing policy remains pending. General archival remains
asynchronous without a new SQL acknowledgement
gate for every ordinary turn/tool.

Call audio is stored only through an explicitly enabled and permitted recording
capability. Presence-driven privacy policy and the `opening_audio` media-input gate still
apply. Do not auto-start recording for history, or add a redundant storage matrix.
Credential/header exclusions and privacy, client visibility, and agent grants
remain unchanged. This resolves R18, not the remaining archival failure contracts.
Automatic archive/log/export/model-debug paths must honor `save_transcripts: false`
for the source interval; they cannot retain a transcript under another label.
`record_audio: false` covers Vxpipe-owned tracks, full mixes, and derivatives.
Neither flag deletes prior permitted intake history; whole-call retention remains.
The flags permit capture/storage, not a new `call_retention` duration or clock.
This is not generic taint tracking/redaction of arbitrary externally copied text,
or control over independent client/provider copies. Tool-history privacy and
credential/header exclusions remain intact.

**Approved variable history and latest-state lookup:** in a database-backed call,
each committed update saves a full post-update snapshot linked to its
originating turn and tool invocation, source participant, revisions, and commit
timestamp. The saved update tool call and arguments already describe the requested
change; no separate changeset or duplicate argument payload is needed. Argument
storage follows the always-stored complete tool-history contract, not an opt-in.
Several updates in one turn remain distinguishable by invocation and revision;
rejected updates do not create successful state snapshots.

`CallVariables` computes the full candidate state after validation and serializes
updates through confirmed persistence. It must not fetch a later live snapshot
and label it as an earlier update. A configured snapshot-persistence port commits
the history snapshot and conditional `calls.latest_variables_snapshot_id` advance
in one same-call transaction, with revision/incarnation checks and idempotent
snapshot identity. A stale new update must fail the transaction, not insert its
snapshot and report success after skipping pointer advancement. A repeated
already-committed operation must not roll back newer memory or the latest pointer.
Only after commit confirmation does the owner adopt the new values/revisions,
emit the event, and return success. Validation failures retain their existing
errors; a transaction error returns variable-save failure. Both leave current
in-memory values/revisions unchanged and emit no update-success event. Normal
transaction success/error handling is sufficient for this slice; the proposed extra commit-status lookup or
reconciliation workflow is not required.

Latest persisted values need one indexed lookup or simple join, not history
aggregation or a second mutable variables store. The GenServer is the runtime
owner of committed values. Its update tools now wait for database commit, while
`RoomAuthority` and media do not; other archival consumers remain asynchronous.
This supersedes the earlier asynchronous snapshot-success proposal, not the
dedicated variables-process ownership or existing read/write permissions.
Snapshots do not expand client visibility or the updating agent's read grants.
Retained initial values have a baseline snapshot and pointer without fabricating
a conversational turn or tool invocation.

**Approved retention scope/default:** configure stored call-data retention periods
at application level, with tenant overrides. The application default is retain
forever. An explicit tenant period wins; an omitted tenant period inherits the
application value. Forever means no age-based expiration, not enabling additional
storage, retaining credentials, extending live buffers, or granting client access.
For example, with no settings, retained history has no age-based expiry; an
application period can instead be inherited, and one tenant can override it
without changing another tenant's period. Periods are not agent/client settings.

**Approved encoding (R19):** application/tenant `call_retention` accepts the JSON
string `"forever"` or a finite duration object such as `{"seconds":2592000}` for
30 days. Application omission defaults to `"forever"`; tenant omission inherits
the application value, while explicit tenant `"forever"` overrides a finite
application period. This is not a call-definition, creation, or participant field
and adds no per-call policy copy, human-readable duration parser, or null sentinel.

**Approved retention clock:** for completed calls, finite retention starts at
`ended_at`. The expiry threshold is `ended_at + retention_period`; neither call
record creation nor later snapshot/archive writes start or reset that clock.
Do not expire data while the call is active. Forever has no expiry threshold.
An unset `ended_at` is not permission to substitute `created_at`; cleanup of
unstarted records remains separate from this completed-call rule.

For example, a record created Monday for a call that ends Wednesday retains its
data until the following Wednesday under a seven-day period. This defines the
age threshold, not an exact deletion-job schedule or a new cleanup implementation.

**Approved policy changes:** the current application/tenant retention period
applies to all calls, past and future. Resolve the current tenant override or
application fallback when evaluating expiry; do not store a separate period,
policy version, or fixed expiry per call. This avoids per-call policy management
and rejects the proposal to apply changes only to newly created calls.

For example, changing a tenant from 90 days to seven days makes a call that ended
14 days ago eligible for cleanup under the new setting. Increasing the period or
selecting forever changes eligibility for data still present, but cannot restore
deleted data. Application changes affect tenants inheriting that setting, not
tenants with explicit overrides. Active-call and missing-ended_at rules remain;
this approval chooses neither a deletion schedule nor a cleanup implementation.

**Approved deletion scope:** after retention expires, delete the entire call and
all associated Vxpipe-managed data. This includes the call record, transcript,
events, tool calls/results, all variable snapshots including the latest,
participant/leg and admission records, usage/cost history, recordings if present,
artifact metadata, and published exports. Delete call-specific copies as well;
keeping a summary row or hiding the call with a soft-delete flag is insufficient.
Shared definitions and application/tenant configuration remain. This does not
claim control over independent copies held by integrating apps or providers.

For example, expiring a recorded call removes its database rows, latest-snapshot
reference and snapshot history, audio objects, and exported call-details JSON.
No referenced snapshot is kept merely because it was the latest. Object storage
and the database require separate operations; cleanup is not complete while
call-owned data remains in either. Pending or late archival/publication work must
not recreate the deleted data.

**Approved periodic cleanup (R20/R21):** background sweeps select completed calls
that meet the current tenant/application retention period from `ended_at`. No
instant threshold-triggered deletion or per-call expiry timer. The exact sweep
interval/default is deployment configuration still to choose, not an approved
hourly frequency or exact deletion SLA.

Delete every managed call-owned external object/copy first, then call-owned
database rows and the call record. A definitive key-not-found result means that
object is already absent. Proceed to database deletion only after all relevant
objects are absent. Timeouts, network/permission/authentication failures, and
unknown outcomes are not missing-key success: keep the call/artifact records and
references so another sweep can retry.

A crash after some or all objects are deleted is handled by repeating deletes
from those retained references; missing objects succeed, then database cleanup
can complete. A database failure similarly leaves the work for a later sweep.
Reuse call/artifact rows rather than adding a per-object progress journal or
permanent tombstone. Successful cleanup leaves no call row, summary, or snapshot.
Coordinate archive/publisher writers with cleanup so they cannot recreate purged
data; deletion ordering alone does not guarantee this, and the specific mechanism
is not chosen here. Shared configuration/assets remain outside call-owned deletion.
This background cleanup retry policy does not change the tool/MCP no-retry rule.

Unstarted-record housekeeping remains separate; no additional automatic
expiry is approved for those records.
Model, authorized operator, call-ledger consumer, telemetry, and browser remain
different audiences. G5 stays partly resolved. Success now proves the snapshot
transaction committed, not that complete room restart/recovery is implemented.

**Approved sensitive-input boundary:** defer general redaction of sensitive voice
audio and input that reaches STT/the LLM. This is later work, not a prerequisite
for the current slice. A deterministic input path such as DTMF can collect an
account number without LLM interpretation. Its collection/routing integration is
not implemented or fully specified here; DTMF does not by itself exclude digits
or tones from recordings, logs, or tool payloads. No automatic masking is promised.

Existing credential/header exclusions and permission/visibility checks still
apply before persistence and client delivery, not just final export. Do not put
expected verification secrets into prompts or ordinary archives. Hiding a tool
event does not redact sensitive input already in the transcript or audio.

### G6 — P1: “Remote MCP” needs a tested interoperability profile

The configured-versus-enabled distinction is already strong. It does not mean
the example HTTP webhooks, native SMS, or code tools are MCP endpoints. Keep
those behind a remote MCP facade or an explicitly registered host tool; do not
add arbitrary HTTP/JavaScript execution to the call-definition JSON.

**Approved R22:** the initial remote profile is `2026-07-28` Streamable HTTP,
supporting JSON and request-scoped SSE with revision-specific request metadata
and lifecycle, not old initialize/session rules. Other revisions or legacy
HTTP+SSE are not implicitly compatible; fail clearly unless explicitly implemented
and tested. Pin the selected profile in the resolved binding.
[Transport specification][mcp-http].

**Approved R23:** validate actual outgoing arguments against the selected/discovered
pinned `inputSchema` before submission, using a proper JSON Schema validator with
2020-12 baseline. Enforce required/type/enum/nested constraints; incremental Call
Variables rules are not MCP input rules. Unsupported dialect/features or model
representation reject enabled bindings before exposure, without constraint
weakening or automatic external `$ref` fetching. No library, new caps, or full
output normalization design is chosen. [Schema rules](https://modelcontextprotocol.io/specification/2026-07-28/basic#json-schema-usage).

**Deferred R24:** store received responses, including structured content and
attachment/resource descriptors, preserving success/error/unknown observations.
The agent chooses whether to inspect a document through authorized available
tools. Storage is not automatic linked-file download or proof of understanding;
an uninspected attachment does not make a successful business action fail.
Detailed result-to-model projection and inspection support live in the
[result/document issue](issues/mcp-result-and-document-inspection.md), not an
approved text/JSON-only filter or new reader/playback feature.

**Deferred R25:** [server-requested interactions](issues/mcp-server-requested-interactions.md)
remain future work. Do not advertise unimplemented sampling/elicitation or gain
authority from server requests; report missing capability clearly. The selected
revision's `input_required`/MRTR flow is not the older independent-request model.
Continuation/resubmission requires its own future design, not an automatic retry
exception. Ordinary agent dialogue and complete observed response storage remain.

Discovery/pagination and credential lifecycle choices remain separate.

Pin tool schemas, not the remote service's changing business data. Returned
instructions are untrusted tool content, never new system policy or permission
grants. Cache by authorization boundary and integration/credential generation;
do not share user-specific discovery/results simply because an endpoint matches.
Keep revocation fail-closed with no silent fallback to application credentials.
**Approved R26 outbound boundary:** accept only trusted app/tenant integration
endpoints, not model-controlled routing URLs. Verified HTTPS is required; private
CA configuration may be supplied, not insecure TLS or implicit loopback HTTP.
Apply public-address defaults and address-at-connect/DNS-rebinding checks,
including link-local/cloud metadata, CGNAT, multicast, and unspecified targets.
Private network access needs explicit host-application authorization that tenants
cannot bypass. No automatic redirects: configure the intended endpoint, and never
forward credentials across redirects. Custom network clients/proxies must preserve
the same protections. This adopts the [SDK security guidance](https://go.sdk.modelcontextprotocol.io/protocol/#server-side-request-forgery)
at Vxpipe's own boundary; the SDK describes OAuth discovery-helper defaults, not
automatic protection for all transport calls. No Go dependency, generic artifact
fetcher, per-call credentials, or gateway/inbound/CORS change is introduced.
Bound responses as before. OAuth onboarding/refresh remains separate; document
supplied bearer-token expiry.

### G7 — P2: Conversation lifecycle needs more than `first_message: generated`

**Approved optional `opening_audio`:** play an audio-file URL (WAV or another
supported format) or audio rendered from fixed configured text to `entry_caller`
before `entry_receiver` starts normal conversation. It is call-level, not a
participant greeting or mandatory notice. R11 separately leaves personalization
to agent instructions, without a prompt/variable interpolation engine.

For text, render/cache audio using the initial receiving agent's resolved TTS
service and voice, including defaults. No LLM generates the text; no arbitrary
first map member or later transfer agent supplies the voice. Text applicability
without an initial agent/usable TTS remains open. The cache distinguishes exact
text, resolved provider/model/voice, output-affecting settings, and tenant/
configured binding. Changed inputs must not reuse stale output; no secrets in
cache keys/logs. Reusable configured assets are not per-call recordings/exports.
Render timing and cache/fetch infrastructure are not selected, and asset
preparation itself starts no call process tree or call clock.

Room/participant capabilities may initialize and warm up during playback. The
gate is on audio delivery: withhold user and other participant audio from
capabilities and normal conversational media paths until playback completes.
Transport receipt does not authorize delivery to STT, recording, or other
consumers. Opening rendering/playback remains allowed; the receiver's greeting
and ordinary conversation still wait. Capture/retrospective replay of blocked
audio and text barge-in are not approved or implemented by this decision; no
buffer/replay mechanism is added. Downloading, rendering/caching, or enqueueing a
file is not playback completion. Failed/incomplete configured playback does not
silently release the media gate.
Omitting `opening_audio` uses normal startup without an announcement delay.

For example, play a fixed recording announcement, then activate the receiver and
its ordinary greeting policy. A recorder may start but receives no participant
audio while the opening-audio gate is closed.
The actual call-start timestamp remains the live-start occurrence, not notice
completion. Exact completion evidence, source schema/supported formats, failure
handling, and later-participant notices need separate design; this does not
introduce per-transfer playback or a consent guarantee. Fixed configured opening
text does not add variable interpolation.

**Approved first-message behavior:** each agent participant chooses wait-for-input,
fixed greeting text, or a generated greeting. Apply it on the participant's first
activation in that call, after any startup notice and once its required
connections/capabilities are ready.
Reconnect and later reactivation do not replay the startup greeting. A different
participant gets its own first activation, and a new call starts afresh.
For example, an inbound receiver can welcome the caller immediately; an outbound
receiver can wait for the recipient's hello. A returning participant may converse
normally without rerunning its startup greeting. Normal output permissions and
current privacy permissions still apply. Exact JSON encoding is not frozen by
these modes;
finalize the representation with the schema implementation. No implicit fallback
mode is introduced by this decision.

**Approved R27 readiness:** configurable 30 seconds for required providers/
connections to become ready, measured from the actual post-join admission/startup
attempt, not record preparation or token lifetime. Terminal failure fails early;
deadline expiry aborts startup, releases resources, and returns a clear failure.
Deliberate opening-audio playback is separate: no 30-second file truncation or
false readiness failure, and no fabricated `started_at` before live start.

**Approved R28 idle notification:** configurable 15 seconds only when an agent
genuinely waits for caller input. Its instructions choose a nudge, continued wait,
or permitted hangup tool; silence does not automatically end the call. Exclude
opening playback, agent output, holding/dialing, and tool-wait. Use appropriate
conversation/media evidence, not new local VAD/models or an automatic repeated
announcement cadence. Human-only calls do not need an agent to handle silence.

**Approved R29 tool waiting:** no automatic periodic progress speech. Instructions
control kickoff and result speech through the same agent/one coordinated voice,
while regular conversation can continue during background execution.
[Wait music](issues/wait-music.md) for startup and long tools is deferred, with
no new audio option or transfer-consultation behavior approved.

**Approved R30 duration:** whole-live-call `limits.max_duration_ms` defaults to
`1800000` (30 minutes). Resolve explicit definition, then tenant, then application,
then platform default, and pin the effective limit in the call plan. Do not use
retention's current-policy semantics here. Clock from actual `started_at`, excluding
prepared wait and preserving the deadline across transfers/recovery and human-only
portions. The engine ends with a clear duration-limit reason. No creation override,
unlimited mode, automatic warning/grace interval, or guaranteed closing speech.

**Resolved R31:** closing wording and choosing when to invoke the existing hangup
tool belong to agent instructions. Reject the proposed platform speak-and-end
lifecycle/API, mandatory playback-drain deadline, and automatic cancellation of
a pending hangup on speech interruption. Normal/immediate hangup and hard-duration
control remain unchanged. Instructions do not prove completed playout; no
playout-aware hangup guarantee is added. G7's current-slice decisions are resolved;
future voicemail delivery and wait music remain deferred, not requirements for
another platform closing workflow.

The [voicemail example][voicemail] waits for input and delegates to a native
tool. Vapi's [tool documentation][voicemail-docs] distinguishes assistant-chosen
voicemail from automatic detection and ends the call after the configured
behavior. That background does not approve message delivery for this slice.
An answered leg is not proof of a human, and STT text alone does not establish a
beep. Preserve observed provider evidence without inventing confidence or claiming
full answering-machine/IVR support from generic hangup/transfer tools.

**Resolved R32:** use provider-supplied detection when available and configured
for use, preserving provider provenance and unknown outcomes. Detection is not
mandatory for every call. [Telnyx AMD](https://developers.telnyx.com/docs/voice/programmable-voice/answering-machine-detection)
and [Twilio AMD](https://www.twilio.com/docs/voice/answering-machine-detection)
provide that source; no local beep classifier or LLM-inferred human proof is added.
If that detection reports machine, disconnect the attempted outbound destination
leg. A transfer returns a typed failure to the source while preserving the original
caller/source conversation when permitted, not hanging up the room. If it is an
initial outbound call to its only remote human, end that attempted leg/call without
voicemail speech. Unknown, disabled, or unavailable detection is neither machine
nor human proof. An unknown transfer keeps awaiting explicit acceptance within
the existing total 30-second deadline; it never resets or extends the clock.
AMD is not guaranteed accurate or explicit recipient acceptance. Provider tuning,
beep inference, and automatic speech are not introduced. Leaving voicemail is
[deferred](issues/voicemail-message-delivery.md); that future issue does not
reinstate the rejected platform speak-then-end workflow.

### G8 — P2: A transfer allowlist is not the complete transfer policy

**Approved source-agent responsibility:** keep the source agent responsible for
conversation until the destination is ready and the transfer successfully commits.
`RoomAuthority` remains the room/transfer authority; this is conversational
ownership, not a supervisor handoff. Busy, no-answer, or another failed attempt
returns a typed tool error to the source agent, which can explain it and choose
its next permitted action. Do not shut it down when transfer is merely requested.
Successful handoff terminates its entire execution subtree under the existing
lifecycle. This does not cancel a variable update already submitted to the
separate variables process or promise rollback of a remote action.

For example, human support does not answer: the caller stays with reception,
which can offer another allowed destination or continue helping. No failed
attempt emits `transfer.completed`. Current privacy permissions still constrain
what reception can do; failure is not permission to restart forbidden processing.

**Approved R33 location:** call-level `transfer_policy` holds shared defaults.
Keep source participant `transfers: ["specialist", "human-support-agent"]` as
allowed refs; destination-specific connection and acceptance requirements stay
with the destination. No named transfers, graph, source-level defaults, or per-pair
override machinery initially. Naming this boundary does not freeze other policy
fields/enums. Warm/cold and history-projection choices remain separate.

**Approved R34 acceptance:** agents require conversation/required-capability
readiness. Humans require usable media plus explicit acceptance: phone press-1
DTMF tied to the pending destination leg, or an authenticated web transfer-accepted
message. The client owns its web presentation/user interaction; the platform
accepts the control message without mandating a button UI. Bind acceptance
server-side to destination participant/connection and current pending attempt.
Reject source/caller/model assertions, stale acceptances, and duplicate commits.
No STT/LLM inference substitutes for DTMF or explicit acceptance. This is an
internal/adapter protocol contract, not an RTVI core standard field. Connection
alone does not expose full conversational media; source responsibility and target
presence/capability restrictions remain until room-authoritative commit.

**Approved R35 deadline:** configurable 30 seconds in `transfer_policy` for the
whole attempt from the accepted preparation request, including preparation,
dialing, and acceptance rather than separate restarted clocks. Busy/no-answer or
another definitive failure ends it early. Failure/timeout stops the destination
attempt and returns a typed outcome; source conversation continues when permitted.
Late answer/acceptance cannot commit an expired attempt. Clean up the exact mapped
leg and do not automatically redial. Startup readiness (R27) and hard call duration
(R30) remain separate; no remote certainty or durable recovery framework is added.

**Approved R36 restoration:** make exactly one bounded attempt to restore the
source's permitted capabilities after transfer failure. Supervisor/application
retry or restart loops must not reset that budget. If restoration fails and no
usable conversation remains, end the call; a valid, already working human
conversation may continue. Never resume forbidden processing. Retain the detailed
cause internally, not in agent speech, client events, or tool-debug UI, even with
samples/full visibility. Agent/public outcomes are generic without provider/cause
details. This restores capabilities within a still-live call, not a crashed runtime.
Whole-call limits still apply; cleanup is not a promise that dialing or
other external effects never occurred.

**Approved R37 initial scope:** private human-destination briefing before acceptance
and bridge. The intake agent collects information from the caller; outbound support
privately hears who is calling and the purpose, plus an optional recording notice,
then presses 1 to accept. The caller cannot hear the destination briefing. Web
acceptance remains client-owned and authenticated. Share only permitted,
minimum-necessary variables/history, not the entire transcript by implication.
Source TTS may use the agent's voice where applicable and permitted; no new voice
selection/schema is fixed. Source responsibility continues until commit, and
acceptance alone cannot disclose full room media. This is not a universal compliance
guarantee or general concurrent-agent consultation. R38 supplies the approved policy
and media/commit integration; do not count it again under R37.

Voicemail-message delivery and wait music remain deferred. The briefing does not
approve hold music or a second simultaneously conversational agent. Caller-departure
and broader consultation/history behavior still need their applicable design.

The repository transfer tools demonstrate basic destination transfer, not warm
consultation. The additional [first-party warm-transfer guide][warm-transfer]
describes hold, operator acceptance, cancel, and fallback; that is separate
evidence for the richer scenario, not a claim about the example JSON.

### G9 — P1: Presence-driven media and transcript policy — resolved

R38 uses normal call-wide `media_policy` and participant `while_present`, which
contributes room-wide restrictions while authoritatively admitted. Both use
`audio_routes`, `transcript_routes`, `record_audio`, and `save_transcripts`.
This replaces public STT/TTS denial selectors; historical examples are not another
approved format. See the [capability ownership terminology][terms] and the
[approved policy/example][presence].

Audio maps are complete publisher-to-recipient allowlists using human/agent
participant-definition keys. Only listed sources may publish room audio, to listed
recipients; empty arrays grant no other participant access, and self-loops/monitor
access are not implicit. Transcript maps independently route live derived transcripts
from the speech-source participant, with explicit self recipients if desired.
No wildcard, role selector, dot path, expression, or extra override matrix.

Omission inherits normal policy/adds no restriction; an explicit empty route map
allows no routes. Do not deep-merge unlisted routes back in. Intersect publishers/
recipients across present policies and normal policy under the host authorization
ceiling. Storage false wins. Leaving removes only its own restriction; mere
transport loss does not clear presence or reset work.

Storage flags are independent room-wide booleans, not per-source capture settings.
Restrict recording alone, both storage paths, or both storage paths plus empty
transcript routes independently. No storage does not mean no provider processing:
authorized live transcription still sends audio to STT. Stop those STT flows when
neither a permitted live recipient nor storage consumer needs them. Permission
does not enable unconfigured STT/recording or activate every participant. Honor
source-interval restrictions on automatic storage/copies without deleting earlier
permitted intake history or claiming control of independent copies.

Private preparation gives only the destination its authorized briefing/notice,
not main-room admission or caller access to that audio. Acceptance remains bound
to its pending attempt. Commit applies `while_present` before connecting main
media, then hands off/terminates source. This is the existing authorized transfer
lane, not global briefing publication or general concurrent-agent consultation.
`RoomAuthority` authorizes the pinned topology; mixing/routes/transcript projections/
recording/archive enforce it without frontend-only muting or per-packet database
lookups. Fail closed before commit; no queued/late output, reactivation, or delayed
replay bypass. Existing transfer deadline/restoration rules and Variables remain.

### G10 — P2: Durable admission has crash windows and admission-key ambiguity

The [persistence plan][persistence] already separates short database transactions
from room/provider work. R39/R40 now resolve this scope without creation-request
deduplication or a general call-recovery framework.

**Approved R39:** no API `Idempotency-Key`, duplicate-suppression key, or cached
deduplication response. Repeated authorized creation requests may create separate
prepared records; the application/user can later delete unwanted records through
an authorized mechanism. This does not implement a deletion endpoint or UI.

Distinguish webhook-delivery deduplication from call admission deduplication:
multiple lifecycle events for one provider leg are not multiple new calls.
Namespace keys by trusted tenant/integration and normalized leg identity. A
transfer-created leg must attach through the pending transfer/participant ID,
not re-enter number-to-definition admission. Single-use token claims and same-call
admission exclusion still prevent duplicate startup of that same call; these are
not deduplication of separate API creation requests.

**Approved R40:** use a short database admission claim, never a transaction spanning
OTP/provider startup. If the original room/leg still exists, identify it and finish
bookkeeping without starting another. If the actual call runtime crashes/terminates,
do not automatically restart the call, redial, or reconnect the caller. An unclear
provider dial outcome is recorded as failed/unknown as appropriate; clean up known
resources without a speculative second dial or remote rollback claim. Recover
records about existing work, never repeat the phone call. No sweeping durable
recovery or cross-node exactly-once framework is added.

### G11 — P2: Publication revisions and finalization wait resolved; persistence failure policy pending

The async archive is correctly described as potentially lossy on node failure.
Specify per-consumer bounded queue/overflow behavior and independent private
versus public projections. A slow browser must not stall the ledger, and a slow
ledger must not silently turn an archive into a complete record. Record missing
sequence ranges or an incomplete watermark. Distinguish data never produced
because a capability was absent/prohibited, completed-call retention deletion,
and accidental loss of required permitted history. R38 permits explicit transcript/
audio retention restrictions independent from live sharing; tool/usage history is
not made optional. Required-audit mode needs the
explicit durable acknowledgement protocol, not a larger mailbox.

There is also an immediate source gap: the engine's text-input start/completion
events contain modality and IDs but not submitted text. Add a committed-input
fact, with the approved private-storage/client-visibility boundary, before claiming
the event stream can rebuild the human text transcript. [Room authority][authority].

Call end, operation settlement, artifact finalization, and archive publication
are different states. The proposed `(call_id, archive_schema_version)` job key
cannot distinguish a corrected export using the same schema. R42 instead gives
each immutable publication revision its own record, identity, and persisted UTC
timestamp. Use `details-YYYYMMDDHHMMSSmmm.json` under the call-owned object prefix,
with three millisecond digits: `2026-09-08T12:34:56.789Z` on that record produces
`details-20260908123456789.json`. It is not call `created_at` or the current time
when a worker retries. Retry the same snapshot using its persisted identity,
contents, and filename; changed contents require a new publication record/timestamp
and object. Value-only changes leave `schema_version` unchanged. Keep a
latest-publication pointer without overwriting earlier revision objects.

Millisecond timestamps are not uniqueness or global monotonic-clock guarantees.
Creation must detect/handle filename collisions within that call's prefix so
different publications cannot clobber one key. Preserve internal revision identity/
correlation; do not deduplicate solely by time or invent timestamps to claim
uniqueness. The collision mechanism is implementation work. All revisions and
their records remain call-owned and subject to whole-call retention deletion.

R43 is approved: finalization runs outside the room with a configurable 60-second
waiting window after call end. Publish earlier if all expected work is settled;
at the deadline publish available permitted data, explicitly identifying pending,
failed, or missing components. Missing usage/cost is not zero. Intentionally
prohibited, unconfigured, or not-produced media is not accidental loss/incomplete
capture; expected work that remains pending or failed must be reported honestly.

The window limits reporting wait only. It does not extend the call, reset
`ended_at` or retention, cancel uploads/provider work, or stop permitted asynchronous
cost retrieval. Background work can outlive the room. If the database/object store
cannot publish, retain/retry appropriate publication state; never claim published
or complete merely because time expired. R41's overflow/durability choice stays
pending. Later facts may trigger refreshed publication or a new revision under
R42. Known call-owned jobs/references must honor retention
deletion and source-interval privacy, so late work cannot recreate purged data or
capture/copy denied intervals. No new configuration schema or runtime work is added.

Preserve live recording beside the engine and upload workers outside its hot
path. Multipart upload is not a live monitor feed; monitor from the authorized
live mix. Track manifests need clock mapping across ingress/egress and room
incarnations, explicit gaps, and evidence distinguishing scheduled, sent, and
device-confirmed playback. A sink accepting audio does not prove a listener heard
it. Post-call summary/evaluation is a separate optional, metered job; it cannot
overwrite authoritative call variables or invent missing transcript segments.

### G12 — P2: Usage observations and attribution — R44/R45 resolved, R46 pending

Every observation belongs to the call. Attach participant/activation/service-active
interval and turn references only where honest; participant attribution does not
require a turn. STT/TTS may span several actual service-active intervals for a
participant, not one assumed membership interval or invented billable duration.
LLM requests may link to agent/turn; TTS turn attribution is provider-dependent.
Shared/unattributable usage stays call-scoped without equal division among turns.
One fact with call/participant/turn refs is not three charges; count each effective
provider-operation attempt once in an aggregate.

Preserve tokens, durations, characters, and provider units even without monetary
cost; missing usage/cost is unknown, not zero. Save actual provider request/operation
IDs when available with provider/configured-integration/tenant namespace; absent
IDs stay absent, distinct from local correlation IDs. An integration may offer an
optional asynchronous billing capability using those persisted IDs where its API
supports lookup. It runs outside media/`RoomAuthority`, may outlive the room, and
does not block the call or reset `ended_at`/retention. Existing integration auth and
tenant isolation apply; no per-call credentials or guarantee that every provider
exposes request-level billing/eventually resolves cost. Billing APIs, dependencies,
schema details, and pricing/fallback policy are not selected.

R44 retains observations and derives effective usage per provider-operation attempt/
component, replacing the one-immutable-row-per-operation proposal. Deltas 100 + 60
mean 160; cumulative 100 then 160 mean 160, not 260. Cumulative 1000, 1600, then
final total 1700 mean 1700, not 4300. Incremental/cumulative mode is independent
from estimate/final/correction status; finality does not turn a delta into a total.
Final evidence supersedes estimates; late stale estimates cannot replace known
finals. An explicit correction can lower or raise the amount. Do not use blind
arrival order, `max()`, or summing every report.

Deduplicate only when observation/sequence/delivery identity proves repetition;
equal numeric values are not a deduplication key. Keep units, currencies, components,
and provenance distinct; do not add totals to included subcategories or collapse
distinct billable attempts. Interrupted/failed operations still contribute observed
usage despite stale conversational output. Preserve original observations as the
effective amount changes; automatic MCP retry policy is unchanged.

R46 pricing-source/version/fallback remains pending: absent billing support does
not approve catalog math or invented prices. R41 archive persistence/failure policy
remains pending; R42's revision identity and R43's reporting window do not settle it.
General usage archival stays asynchronous while variable snapshots retain their
commit-confirmed boundary. Mandatory usage
storage still respects media/privacy exclusions and whole-call retention; later
billing cannot recreate purged call data.

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

For long calls, declare token-aware history/tool-result/model-context budgets,
truncation or compaction policy with provenance, and provider failure/fallback
outcomes. The current turn-count history bound does not bound a large prompt or
tool response in model tokens. Fallback must preserve authorization, tool schema,
privacy restrictions, and actual-provider usage attribution; it cannot repeat
an uncertain external action. These are profile/runtime checkpoints, not a
reason to add provider-native payloads to each participant definition.

## Possible checkpoint order and acceptance scenarios

This sequence is an option for review, not an approved implementation plan. Do
not add the suggested variables or functionality before the user reviews the gaps.

1. **Compiler and one-agent variables:** implement the approved G1 layout only
   when runtime work is authorized; resolve remaining G2 questions, the
   private-event part of G5, and denial semantics in G9. Use one canonical fixture with two variables
   sections and an engine-owned variable tool. Prove the existing text/audio path
   works through a typed plan. Do not start with telephony or Ecto.
2. **Safe remote action:** add one tenant-configured remote MCP integration,
   enabled on one agent, with a fake scheduling backend. Cover G4/G6 and trusted
   result projection before making real mutating calls.
3. **Transfers and lifecycle:** prove an agent-to-agent transfer first, then one
   fake outbound human transfer with busy/no-answer/accept outcomes and enforced
   presence-driven privacy policy. Add G7–G9 and live routing/mixing before claiming human-only
   bridging or consultation.
4. **Durable admission and archive:** retain the previously proposed Calls,
   persistence, and artifact boundaries; add G10–G12 incrementally. No Repo/S3
   calls enter the room's state-transition callback.

Use scenario fixtures rather than copying complete third-party definitions:

| Future acceptance test | Evidence of success |
| --- | --- |
| Two staff members try to join as the same definition | Only the original authorized participant is retained; the second person's admission fails without takeover; another definition or call has its own independent participant |
| Race admissions/transfers and re-enter an agent definition | One participant and no duplicate pending preparation per key per call; agent re-entry retains identity with a fresh activation |
| Compile two distinct entry refs and start a caller/reception/billing/support definition | Missing, non-string, identical, and unknown refs fail; only the initial pair is prepared, not every provider/dial target |
| Start with a human receiver, then exercise a separate agent-to-agent transfer scenario | No implicit AI receiver is created; transfer changes live control while the initial refs and pinned plan stay unchanged |
| Declare schemas with no variable defaults and supply partial initial variables | Supplied datatypes/value constraints validate before startup; missing variables do not fail, including in nested objects; intake stays unfilled; variable defaults fail; capability defaults still work; explicit empty section objects are accepted without filling values |
| Prepare private order variables using a backend API key, then join from the browser using only a token | Preparation pins/stores variables without starting providers; authorized joining activates that call; private preparation data is not returned; agents read but cannot rewrite read-only sections; invalid keys, tenant/participant access, and variables fail |
| Prepare from an authenticated backend, then join separately with browser and backend clients | Both clients use the same token-admission contract; neither an API key on a media socket nor first-message initial variables bypass preparation; browser Origin and HTTP CORS remain separate; existing WebRTC stays supported; no removed direct-setup limits are implicitly adopted |
| Issue a key once, inspect storage, and verify it after restarting authentication | Only a digest and metadata persist; the original key works without decryption; wrong keys and the digest itself fail as credentials; keys/hashes are redacted; lost keys are replaced, not retrieved |
| Bootstrap a fresh installation and use separate tenant-scoped keys | Trusted OTP/CLI administration creates the first key; tenant boundaries and the `admin`/`calls` scope split are enforced without assuming a scope hierarchy or definition allowlists |
| Overlap two keys during rotation, then revoke only one | Further authentication with the revoked key fails, including token issuance; other keys and established connections continue; already-issued unused tokens still pass their independent admission checks |
| Issue default and explicitly longer-lived tokens using a fake clock | Default expiry is five minutes from issuance; an authenticated fifteen-minute request remains valid after five minutes and expires at fifteen; applies to preparation and existing-call tokens; the browser cannot extend an issued deadline |
| Race the same join token and lose the response after admission is accepted | Only one claim and room startup; retry before acceptance may use the unused token, but accepted tokens stay consumed; expiry does not end an accepted call |
| Issue two tokens for the same eligible unstarted call, then race their claims | Issuing the second leaves the first valid under its own expiry/single-use rules; shared participant/call admission permits only one caller and no takeover, duplicate startup, ended-call reuse, or caller reconnect |
| Create a call through an authorized backend or trusted telephony ingress with known/unknown initial variables | Supplied declared values initialize through the existing contract; missing values remain unfilled for permitted tools; no new automatic lookup/resolver, completeness/default requirement, or verified identity inferred from caller number |
| Request a fresh token for an unstarted prepared call, then admit a new transfer destination into a separate live call | Backend API-key authorization preserves each call record; issuance starts no room; joining starts the prepared call once or first-admits the eligible destination without resetting the live room or variables |
| Disconnect an admitted caller, then attempt same-call joining; separately end a call and create another | Fresh tokens do not authorize caller reconnection in this slice; an ended call cannot resume, and a newly authorized call has a new record/identity; do not infer that temporary transport loss or another participant leaving ended the call |
| Leave a call unstarted until its token expires, then request a fresh token | Old-token joining fails, but the record and pinned definition/variables remain; authorized reissuance starts no room and later joining activates that same call without creating a replacement record |
| Create a record well before joining, delay persistence of live start, and later transfer/end | `started_at` stays unset before actual start and records that occurrence time once; duration and its limit exclude preparation; transfer/recovery preserve the timestamp; failure before start leaves it unset |
| Recover during pending startup, after call termination, or while a connection is active | Pending admission is reconciled first; ended/unauthorized access and takeover fail; a revoked API key cannot request fresh tokens but does not invalidate issued ones; eligibility is rechecked at claim; no duplicate call or participant |
| Write/read intake, then transfer to a read-only agent | Same room value is visible; unauthorized writes fail; mixed authorized/unauthorized reads return a permission error and no values; retrying permitted sections succeeds without adding unrequested data |
| Compile read-only, read+write, and standalone write grants; leave another section ungranted | First two grants succeed; standalone write fails without silently adding read; read-only grants expose reads, read+write grants also expose updates and their resulting values; ungranted sections expose neither values nor revisions in model projections |
| Read an unpopulated section, then populate it over multiple updates | Read returns one null in the requested value slot, no nested placeholders or state/revision change; first object or variable write creates supplied data, later writes add variables; partial reads do not fill missing children; unknown/forbidden sections still fail |
| Merge several variables with the object tool, then change one variable with the variable tool | One call per operation; omitted stored variables remain; missing variables need not be supplied; wrong datatypes/invalid populated values reject atomically; the same write grant/revision boundary applies |
| Update only a nested address city, then exercise a shallow address section | An existing postal code and omitted siblings remain recursively; a missing postal code is neither required nor invented; wrong nested datatypes reject the whole update; shallow and permitted nested shapes work without automatic flattening |
| Clear an apartment using explicit null through each update form | A nullable variable remains present with null; omitted variables stay unchanged; non-nullable variables reject explicit null atomically even though absence is allowed; no deletion tool or stored null defaults |
| Select a direct variable, then attempt a dot/pointer/index-like variable name | Only exact declared direct keys are addressed; unmatched names fail, punctuation is never traversal, explicitly declared literal keys remain literal, and nested changes use the object tool |
| Interrupt after submitting a variable update, then correct it with another call | The submitted command can finish under existing checks without reviving speech; correction uses the new revision; a delayed original loses a same-revision race without blind retry |
| Read/update variables while the room authority is not servicing messages | Direct tool requests finish in the dedicated variables process without a hidden authorization or commit round trip |
| Submit A's update, transfer to B, and let the update execute after A stops | A's execution subtree, capabilities, and model/tool workers terminate without restarting; its already-sent update may still commit under normal checks, B can read/refresh it under its own grants, and A's speech does not resume; stopping the variables process itself gives no pending-write completion guarantee |
| Submit an MCP read or action, delay its response, then interrupt speech or send interrupting text | The submitted request continues to its result or existing timeout while the agent remains running; its result stays tied to the invocation for subsequent reasoning, without reviving cancelled output, executing unsent old-turn tools, or automatically changing variables; transfer still terminates local agent workers |
| Commit a fake remote booking but withhold its response until timeout | Report outcome unknown with timeout as the cause, not confirmed failure, success, or rollback; no automatic variable mutation; already-known definitive results stay definitive; the executor makes no automatic retry |
| Reject a tool before submission or return a definite failure, then request another invocation explicitly | The executor makes no automatic second attempt for any failure; the known error remains definite, while a later model-requested call has a separate invocation identity; no classification layer or idempotency exception is required |
| Personalize a conversation and answer a current-date question through enabled tools | Agent instructions use only permitted variable reads and date/current-time tooling; missing values do not require template defaults, no locale/timezone field hierarchy is introduced, and call timestamps retain their authoritative meanings |
| Explicitly request another tool call after an unknown timeout | A separate agent-requested invocation is distinguishable from an executor retry; no exactly-once or external deduplication guarantee is implied |
| After a separately approved idempotency/reconciliation policy, exercise a retry | Verify any promised duplicate prevention against that policy and provider behavior; it is not guaranteed by the executor's no-automatic-retry default alone |
| Configure an agent to ask before booking, then attempt an unavailable tool | Domain-specific conversational confirmation uses the prompt/tool flow without a platform token; prompt instructions cannot grant tool access or substitute for enforceable application/MCP authorization |
| Create calls with hidden, metadata-only, and full client tool visibility | Gateway sends no tool events, metadata-only events, or tool arguments/results respectively; sample calls explicitly select full visibility; an authorized creation override wins over the pinned definition value and a joining browser cannot change it; credential/header exclusions still apply |
| Give two agents the same local tool key and configure different visibility overrides | Resolve each invocation by participant definition key plus local tool key; apply only that binding's override, otherwise the call-wide default; sharing a remote operation does not share visibility, and execution permissions remain unchanged |
| Omit visibility, apply the documented override map, then create a full-visibility sample call | Omission hides events; reception lookup_order is metadata and create_booking is full while unlisted bindings inherit hidden; trusted sample creation replaces the policy pair with full and no overrides, a hidden effective override still wins over a full default, and browsers cannot upgrade the pinned policy |
| Hide client tool events, then select metadata/full client visibility | Every call stores the same complete observed invocation metadata, arguments/request payloads, and responses/results/errors; client projections alone differ; no tool-storage opt-in or metadata-only storage mode exists, credentials/authorization headers remain excluded, and unknown outcomes do not invent remote results |
| Archive a text-only call, interrupted agent speech, unavailable usage, and calls with/without permitted recording | Save permitted available facts with honest provenance/usage; explicit transcript/audio retention is independent from live sharing under R38, not inferred recognition shutdown, and tool/variable/usage requirements stay intact; audio requires enabled/permitted recording and the opening input gate |
| Exercise the selected remote revision with JSON/SSE and invalid tool arguments | Both response forms follow 2026-07-28 metadata/lifecycle; incompatible revisions fail clearly; a proper validator blocks missing required, wrong type/enum, and invalid nested inputs before submission; unsupported schemas reject enabled bindings before exposure without network ref fetching |
| Receive structured data, a document descriptor, or input_required for an unsupported interaction | Preserve observed response/outcome without auto-fetching or claiming inspection; unauthorized tools remain unavailable; advertise no unimplemented sampling/elicitation capability, report its absence clearly, and do not auto-continue or resubmit |
| Update variables twice in one turn, holding database commit behind a test barrier | No tool success or published candidate state before confirmed commit; each completed update retains its exact full snapshot and original turn/invocation/revision; reuse tool arguments without a changeset; latest lookup follows the call pointer |
| Fail a snapshot transaction, retry persisted delivery, or submit a stale write | Transaction error returns variable-save failure with unchanged current memory and no success event; a rolled-back transaction changes neither durable snapshot nor pointer; no duplicate snapshot, cross-call pointer, or stale regression; no extra commit-status lookup is required, and snapshots never leak through public events or tool results |
| Omit retention settings, set an application period, then override it for one tenant | Omission resolves to retain forever; tenant omission inherits the application period, an explicit tenant setting wins only for that tenant, and retention duration neither starts processing/recording nor changes client visibility; cleanup follows the approved periodic external-first whole-call contract |
| Create a record before its call starts, then end it with finite retention | Expiry is computed from ended_at plus the current application/tenant period, not created_at or storage-write time; active calls are not expired, later archive writes do not reset the clock, forever has no expiry, and missing ended_at does not fall back to creation time |
| Change retention after calls already exist | The current setting applies to past and future calls without per-call policy copies; shortening 90 days to seven makes a 14-day-old completed call eligible, increasing the period or choosing forever changes eligibility only for remaining data, and an explicit tenant override still wins over application changes |
| Configure `call_retention` as `"forever"` or `{"seconds":2592000}` | Application omission retains forever; tenant omission inherits; explicit tenant forever overrides finite application retention; the seconds object denotes 30 days and is not copied into call definitions or records |
| Expire a call with retained history, snapshots, recordings, and exports | Remove the call record and all call-owned rows and objects, including latest snapshots and call-specific copies; no summary-only row remains; shared definitions/configuration and other calls remain untouched; incomplete object deletion is not complete cleanup, and late publication must not recreate purged data |
| Cross the retention threshold, run a sweep, and interrupt external/database deletion | Eligibility alone does not run an instant timer; the sweep uses current settings and deletes all external objects first, then database data; definitive key-not-found is success, actual failures retain records/references for later sweeps, and repeated missing-object deletion safely resumes without a new progress journal |
| Race a late publisher against retention cleanup | Writer/cleanup coordination prevents recreation after purge; ordering alone is not treated as proof; no permanent call summary/tombstone remains after complete cleanup |
| Return a booking result from a Vxpipe-unaware remote MCP, then let the agent save it | The result alone changes no variables; a separate agent update to a read+write section commits under normal checks; read-only writes fail; no automatic mapping or platform-only result section is required |
| Retrieve instructions asking for an undeclared transfer/tool | Request is rejected by server authority despite model intent |
| Dial a participant using a literal number or protected creation-time routing variable | Exactly one number source is accepted; the trusted initialized value resolves without agent read permission; any agent write grant to its section rejects the definition; missing/null/invalid values fail before dialing and retain source responsibility |
| Ask transfer to use arbitrary dial data or bypass its participant allowlist | Number/provider/URL/variable-ref arguments and unlisted destinations fail; executor rechecks the source allowlist; permitted role selection uses only its pinned connection source, with no new expression or outbound policy matrix |
| Receive configured provider AMD evidence, busy, no answer, or a human decline | Machine disconnects only the attempted destination leg and returns a typed transfer failure with source/caller retained; initial outbound-only attempts end appropriately; unknown/disabled/unavailable is not machine/human proof, explicit acceptance still governs transfer within its unchanged deadline, and no voicemail message or false `transfer.completed` appears |
| Hold transfer preparation, then fail it or complete an accepted ready handoff | Source agent remains responsible before commit; failure returns a typed outcome for its next allowed action, while success commits handoff then terminates the source subtree; privacy boundaries and submitted-variable lifetimes remain intact |
| Configure shared transfer policy and prepare agent, phone, and web destinations | Source allowlists remain participant refs; agent conversation/capability readiness and human usable-media plus explicit acceptance are required; phone press-1 and web messages are tied to the destination and current pending attempt, not inferred from speech or connection alone |
| Send stale, duplicate, source-authored, or mismatched transfer acceptance | Server-side participant/connection/attempt checks prevent unauthorized or repeated commits and premature conversational media disclosure; the web client owns its acceptance UI, not a newly mandated core-protocol widget |
| Advance through transfer preparation, dialing, acceptance, and late callbacks | One configurable 30-second total deadline starts at accepted preparation without phase resets; definitive failure ends early, expiry stops the attempt and returns a typed outcome to the permitted source, and late callbacks clean up only their mapped leg without commit or auto-redial |
| Give an agent closing instructions and let it invoke existing hangup | Wording and tool timing remain agent-owned; no platform closing API, mandatory drain timer, automatic pending-hangup cancellation, or promise that prompt instructions prove completed audio playback |
| Start agents in each first-message mode, repeat readiness, and reactivate them | Wait-for-input sends no unsolicited greeting; fixed/generated greeting runs once on first activation after readiness; repeated readiness/reactivation does not replay it; another participant or call has its own first activation; caller reconnect support is not required |
| Start with no notice, then with opening playback whose completion is controlled while capabilities warm up | No notice uses normal startup; all room/participant capabilities may start during playback but receive no user/participant audio until completion; transport receipt/provider readiness/download/enqueue/failure cannot release the media gate; normal greeting waits, started_at is unchanged, and no blocked-audio replay is implicitly authorized |
| Exercise trusted remote endpoints, changed DNS answers, private targets, and redirects | Verified HTTPS and connect-time address policy hold; tenant settings cannot bypass host private-network authorization; metadata/link-local restrictions remain, redirects are not followed and credentials are not forwarded; no Go SDK enforcement is assumed |
| Stall required startup readiness, return a terminal error, and separately play long opening audio | The configurable 30-second readiness clock begins after join/startup, terminal errors fail early, expiry releases resources with clear failure, and deliberate playback is not truncated or mistaken for provider failure; timestamps and input gating remain honest |
| Wait for caller input, play output, dial/hold, and run a long tool | Only genuine agent waiting produces the configurable 15-second idle notification; instructions decide the next action, no automatic hangup/progress cadence or wait music appears, and background conversation retains one voice |
| Resolve duration at each scope, then transfer/recover into human-only conversation | Definition wins over tenant/application/default 1800000, the resolved limit stays pinned despite later settings changes, actual started_at anchors the deadline without preparation wait/reset, and expiry ends with a clear reason without unapproved closing grace |
| Configure fixed text opening audio and reuse/change its resolved voice binding | Render/cache with the initial agent's resolved TTS/voice; capability warmup need not wait but ordinary conversation and participant media do; changed text/provider/model/voice/output settings cannot reuse stale output, and cache scope follows tenant/binding; rendering is not playback completion or call start; no implicit agent/voice is chosen when unavailable |
| Enter a restricted human-only segment | Denied processing/routes stop before bridging; unaffected permitted audio continues; later restart does not replay the denied interval |
| Slow the recording upload or archive consumer | Live mix progresses; recording/archive becomes explicitly incomplete according to policy, not silently complete |
| Repeat authorized API creation, then separately replay provider events or same-call token claims | Creation may produce separate prepared records without an idempotency header/cache; same-call/provider identities still prevent double startup, and no deletion endpoint/UI is implied |
| Fail transfer source restoration and trigger retry/supervisor paths | Exactly one bounded permitted-capability restoration attempt; no budget reset, end if no usable conversation or retain valid working humans, and detailed cause stays internal even with full sample visibility |
| Brief an outbound human privately before acceptance | Caller cannot hear briefing/optional notice; share only permitted minimum-necessary information, then require destination-bound acceptance and room commit; no implicit full transcript or general concurrent-agent consultation |
| Compose normal media policy with two admitted while_present policies | Complete source/recipient allowlists intersect, explicit empty maps allow none, omitted fields inherit, and storage false wins; humans/agents use direct keys, with no implicit self/monitor grants; leaving removes only its contribution and transport loss does not |
| Allow live transcripts but disable storage, then remove all permitted recognition consumers | Live transcripts may use STT without storage; automatic transcript/log/export/model-debug copies and audio tracks/mixes/derivatives honor their source-interval restrictions; with no permitted live/storage consumer those STT flows stop, without auto-enabling unconfigured capabilities or deleting prior permitted history |
| Complete private briefing and acceptance while policy enforcement is held behind a barrier | Destination has only its authorized preparation lane; caller hears no briefing; apply while_present before main media and source termination, with failure closed and no queued/late/replayed output bypass |
| Crash between short admission claim, startup, and bookkeeping | Existing room/leg can finish bookkeeping without duplicate startup; crashed runtime never automatically repeats/redials/reconnects, and uncertain dial is failed/unknown with known-resource cleanup rather than speculative retry |
| Reconcile supported provider billing after call end | Persisted namespaced provider IDs allow an optional lookup outside media/room work; missing billing support/cost remains unavailable, ended_at/retention do not reset, and effective totals avoid duplicate charges; changed publication contents use a new R42 revision |
| Deliver deltas, cumulative samples, finals, stale estimates, and explicit corrections | Apply declared report semantics per attempt/component: 100+60 deltas are 160, cumulative 1000/1600/final1700 is 1700, final beats stale estimates, and a correction can decrease; repeated identity deduplicates but equal independent deltas both count |
| Attribute a call-wide operation, a participant's separated STT/TTS intervals, and supported turn work | Every fact retains call linkage, optional participant/interval/turn refs reflect evidence without forced allocation, each effective attempt counts once, and failed/interrupted usage survives output filtering without invented units/cost/provider IDs |
| End calls with settled work, pending uploads/billing, and deliberately unavailable media | Outside-room finalization publishes early when expected work settles or at the configurable 60-second deadline with permitted available facts and honest pending/missing markers; no fabricated zero or false incomplete capture for prohibited/unconfigured/not-produced media |
| Expire the reporting window, then complete late work or make publication storage unavailable | Call end/retention stay unchanged, allowed uploads/billing continue, later facts can refresh publication, and outages retain/retry publication state without false success; purged data and denied source intervals cannot reappear, while R41 failure policy remains pending |
| Retry a publication, revise its values, and simulate a timestamp collision | Same immutable snapshot reuses its stored UTC timestamp/identity/file despite later wall-clock time; a value correction uses a new record/object without changing schema_version solely for data, earlier revisions survive, the latest pointer tracks publication, and a collision cannot clobber another revision; retention removes every call-owned revision |

Late booking webhook/external-event delivery is deliberately not an acceptance
requirement for the current MCP slice. Add such scenarios only when the deferred
external-event mechanism is separately designed and authorized.
Generic confirmation-token and argument-bound-approval tests are likewise not
requirements for this slice; Vxpipe's existing tool-access checks remain in scope.

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
- Do not duplicate the call-variable schema with a second call-input schema and
  initialization map. The backend can supply the declared variables shape directly.
- Do not populate variables from definition defaults, merge in fallback values,
  or store empty objects or nulls for omitted values. Only supplied setup data
  prefills variables; later writes still need their existing grants. Returning
  null for a missing requested value is a read representation, not a default.
- Do not demand complete variables before accepting setup or an update. Agents
  collect variables iteratively; retain datatype/supplied-value checks without
  required-variable completeness checks at any object depth.
- Do not add turn/tool-cancellation tracking or rollback for submitted local
  variable updates. Let them finish under normal authorization/revision checks;
  corrections use another tool call, not blind retries of an obsolete patch.
- Do not silently ignore forbidden sections in a variable read. Return a
  permission error and no values so the agent can correct its request.
- Do not require remote MCPs to understand Vxpipe or write its call variables.
  The agent receives the result and uses our variable tools; no automatic mapping
  or platform-only result section is required for that flow.
- Do not support write-only agent section grants or a revision-only writable
  projection. A section is read-only, read+write, or ungranted; standalone write
  is invalid. Existing public-event and cross-participant privacy still apply.
- Do not replace a complete variable section with the partial object passed to
  `update_variables`. Recursively merge objects, preserve omitted variables at every
  object depth, and validate populated values without demanding missing variables;
  omission is not deletion.
- Do not interpret explicit null as key deletion or add a tool solely to clear
  a value. Store null through either update form when its schema allows it;
  optionality alone does not grant nullability.
- Do not interpret model-facing section or variable names as paths. Root keys name
  sections, direct section keys name variables, and nested object updates already
  provide the mechanism for deeper changes. Internal pointers stay internal.
- Do not embed the caller in an entry field or infer it from catalog scanning.
  Both entry fields reference one participant catalog; compilation resolves
  initial roles explicitly. Listing a participant does not make it live.
- The earlier client-ID/HMAC contract is superseded: no signature envelope or
  canonicalization is needed for these backend API-key flows. Never put API keys
  in browsers, definitions, or plaintext database variables. Reversible storage is
  also rejected for Vxpipe-issued keys: keep only a one-way hash. Recoverable
  upstream credentials remain a separate concern. Hash storage does not replace
  TLS, scoped-token lifecycle, or credential management.
- Do not reuse consumed join tokens, silently take over a connection, or assume
  a lost admission response means no call started. Backend-authorized recovery
  must reconcile the existing attempt first. Unstarted-record token replacement
  is not same-call caller reconnection; the latter is deferred. Token expiry is
  not an automatic hangup of an established call.
- Do not impose an additional automatic admission expiry on unstarted call
  records. Token expiry already blocks use of that token; authorized reissuance
  can reuse the same record. Record retention/cleanup is a separate decision.
- Do not use record creation, token redemption, or event-persistence time as the
  call's start time. Record actual live start once and exclude preparation wait
  from call duration; transfers/recovery do not restart that clock. A new call
  after logical termination has its own first-start timestamp.
- Do not serialize full tool payloads into a universal room event stream and
  attempt to recover privacy only at the final publisher.
- Do not move mixing, recording coordination, or call variables into persistence.
  No new umbrella application was created as part of this review.

Evidence is source inspection at the commits above and targeted first-party
protocol documentation, not a successful end-to-end deployment of the external
examples. Documentation verification covers local link targets, fenced JSON
syntax in the updated labnote, whitespace, and scoped diffs. Runtime tests and
browser checks are not applicable to this documentation-only checkpoint.
The approved credential-storage follow-up also inspected an existing Cloak/Ecto
implementation: runtime key validation, supervised vault, encrypted binary
variables, redaction, and binary database columns. No environment-file contents or
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
The subsequent variables correction removes defaults from both labnote schema
examples and approves supplied-only initialization. It replaces the merge-rule
proposal, retains capability/profile defaults, and updates planned acceptance
checks. At that checkpoint, G3's remaining runtime authority questions were still
open; no variables compiler or runtime implementation was changed.
The subsequent interruption decision lets submitted local variable commands
finish while retaining authorization, lifecycle, and revision checks. It removes
the proposed live-turn cancellation guard and mutation-ID journal requirement,
updates the race/correction acceptance case, and leaves external-tool policy
and the other G3 questions pending. No runtime cancellation behavior was changed.
The read-authorization follow-up approves whole-request permission errors instead
of filtering and updates the original read contract and future acceptance cases.
It records the requested object and variable update tools, retaining batching and
the existing section authorization boundary, with naming and update semantics
pending at that checkpoint. No runtime implementation or schema rename was introduced.
The subsequent object-update decision selects merging into existing section
data while preserving omitted variables. The labnote adds a before/data/after
illustration and planned checks for retained required variables and atomic invalid
update rejection. At that checkpoint, nested/removal details and final naming
remained open; no runtime merge implementation was introduced.
The subsequent clarification approves recursive object merging and preservation
of omitted nested variables. It recommends shallow authoring, such as an `address`
section, without banning nesting. The original note adds a nested illustration
and planned verification, while retaining the 12 open-group count and the
then-open removal/null, variable-addressing, and naming questions. No runtime code,
schema flattening, or new nesting limit was introduced.
The clearing decision now assigns explicit null to nullable variables while keeping
their keys, leaves omission as preservation, and defers physical deletion. Both
documents update nullable-variable requirements and planned verification without
changing runtime behavior or adding a new model-facing tool. G3 still has other
open questions, so the numbered review-group count remains 12.
The addressing decision now fixes variables root keys as section names and direct
section keys as literal variable names. It routes deeper partial changes through
the object-update tool, separates model-facing names from internal pointer
encoding, and adds future direct-key/path-confusion checks. Other G3 questions
remain open; no runtime tool or schema-wrapper change was introduced.
The missing-read and incremental-population decision returns one null at a
requested absent value, without nested placeholders or a stored default. First
writes populate a declared section; later writes collect variables iteratively.
This supersedes earlier required-variable completeness checks mentioned in the
historical checkpoints above, while retaining datatype and supplied-value
validation. Variable-tool argument shapes must also allow partial objects. The
two definition illustrations remove only their variables `required` lists, and
planned acceptance steps now cover absence, partial/nested collection, and wrong
datatypes. G3's read/first-write questions are resolved; other G3 questions keep
the count at 12 open groups. No runtime implementation was changed.
Verification parsed all 13 JSON examples, confirmed the only example changes
are the two variables `required` removals, and checked both definition contracts,
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

The final naming decision adopts Call Variables, with sections containing
variables rather than "fields". Candidate keys, tool names, planned state and
command types, persistence sketches, and local links use the same vocabulary.
The runtime architecture distinguishes call variables from conversation history
and model context. Existing execution metadata such as `Tool.Context` is not
renamed; no runtime implementation or schema release was introduced.
The MCP clarification resolves the result-writer question: an ordinary remote
MCP returns a tool result, and the agent separately updates Vxpipe variables
under its existing permissions, datatypes, and revisions. The automatic mapping
and platform-only result-section proposals are withdrawn. Revised acceptance
steps cover that flow without imposing knowledge of Vxpipe on the MCP.
At that naming checkpoint, schema-complexity bounds remained open in G3;
naming and MCP result handling did not. The count was therefore 12 numbered
groups, not 12 individual questions.
Verification covered all 15 JSON examples across the design and architecture
documents, confirming only the approved key renames, unchanged definition and
authority semantics, and all 31 local links/anchors. External source URLs,
routes, resolved-review markers, terminology, and `git diff --check` passed.
No runtime or browser tests were run for this documentation-only checkpoint.

The subsequent approved dedicated-owner decision makes `CallVariables` a
room-scoped GenServer with direct tool calls and no current-activation check.
Transfer terminates the source agent's execution subtree, including capabilities
and model/tool workers, but does not cancel already-submitted variable requests.
Normal identity, grant, deadline, datatype, size, and revision checks remain.
The variables process survives transfer; stopping the variables process itself
does not guarantee pending-write completion. Current shared task supervision
still needs implementation work to enforce agent-wide shutdown.
Additional schema-complexity limits are not adopted now. G3 is resolved in
documentation and the current count is 11 open numbered groups, G2 and G4–G13.
Ownership, lifecycle, persistence descriptions, and planned tests are synchronized
with the original labnote and architecture. Verification confirms all 15 JSON
examples and both complete definition fixtures are unchanged, all 31 local
links/anchors resolve, and API routes/external references are unchanged. Ownership,
lifecycle, review counts, terminology, local-path hygiene, and whitespace checks
pass. No runtime implementation, tests, or published schema changed; no runtime
or browser tests were run for this documentation-only checkpoint.

The subsequent MCP-interruption decision approves finishing submitted requests
despite ordinary spoken or typed interruption, within the existing timeout.
Interrupted speech is not evidence of cancellation intent, for reads or actions.
Keep the result associated with its invocation for subsequent reasoning without
resuming the old model/speech, running unsent old-turn tools, or automatically
changing variables. Transfer/room shutdown still end local agent work, without
guaranteeing remote rollback. Current model-task cancellation needs to change
when implementing this policy; no runtime behavior was changed here.
The contradictory planned remote-cancellation assertion is replaced and new
barrier-based acceptance steps cover request completion, timeout, and output
isolation. Other G4 policies remain proposals; the group is partly resolved and
the overall count remains 11. Verification confirms all 15 JSON examples and two
definition fixtures are unchanged and valid, all 31 local links/anchors resolve,
and routes/external references are unchanged. G3's authorization transaction and
implemented-runtime descriptions are preserved; interruption/review consistency,
terminology, path hygiene, and whitespace checks pass. No runtime or browser tests
were run for this documentation-only change.

The timeout-outcome follow-up approves reporting `unknown` when a submitted MCP
request times out without a definitive remote result. Local timeout is not proof
of remote failure or rollback, and any already-known definitive result remains
definitive. Retry policy is explicitly still unapproved, alongside reconciliation
and storage; no wire schema or runtime behavior changed. The lost-booking-response
acceptance case and active design summaries are synchronized. G4 remains partly
resolved with 11 open groups. Verification confirms 15 unchanged valid JSON
examples, both definition fixtures, 31 local links/anchors, unchanged routes and
external references, and preserved G3 and implemented-runtime contracts.
Timeout/interruption policy, retry-review boundaries, terminology, path hygiene,
and whitespace checks pass. No runtime or browser tests were run.

The subsequent retry decision approves no automatic executor retry after an
unknown-outcome timeout. Return the outcome to the agent; a later requested tool
call is a separate invocation, without exactly-once or external deduplication
guarantees. No metadata-based retry exception is approved. Active design summaries
and the one-invocation/separate-invocation acceptance steps are synchronized with
the original labnote and architecture. Other G4 questions remain open and the
count stays at 11. Verification confirms 15 unchanged valid JSON examples, both
definition fixtures, all 31 local links/anchors, and unchanged routes/external
references. Prior G3 and implemented-runtime descriptions are preserved; retry
scope, remaining-review status, terminology, path hygiene, and whitespace checks
pass. No runtime changes or runtime/browser tests.

The subsequent late-confirmation decision defers this scenario as an external
event concern. A future gateway mechanism could route a booking success webhook
to the relevant active room/agent; it is not current MCP timeout reconciliation.
No webhook endpoint, polling, durable outcome worker/ledger, or automatic tool
continuation is required now. Event authentication, correlation, inactive-room
behavior, and agent handling belong to that future design. Active scope and
acceptance requirements are synchronized with the original labnote and architecture;
timeout/unknown/no-automatic-retry behavior remains unchanged. G4 is still partly
resolved and the count remains 11. Verification confirms 15 unchanged valid JSON
examples, both definition fixtures, all 31 local links/anchors, unchanged routes
and external references, and preserved G3/implemented-runtime contracts.
Deferred scope, prior MCP policies, remaining-review status, terminology, path
hygiene, and whitespace checks pass. No runtime or browser tests were run.

The subsequent confirmation decision excludes generic platform confirmation for
now. Conversational confirmation belongs in agent instructions; enforceable
business authorization belongs to the application/MCP. Prompts are not security
checks and Vxpipe's tool-access rules remain. The generic argument-bound token
proposal and its test requirement are removed from this slice, without adding
an endpoint, schema option, or state machine. Original labnote, architecture,
review status, and acceptance scope are synchronized. G4 is still partly resolved
with 11 open groups. Verification confirms 15 unchanged valid JSON examples, both
definition fixtures, all 31 local links/anchors, unchanged routes/external
references, and preserved G3/implemented-runtime contracts. Confirmation scope,
tool-access boundaries, review status, terminology, path hygiene, and whitespace
checks pass. No runtime or browser tests were run.

The R01–R05 follow-up approves OTP/CLI first-key creation, tenant-bound
`admin`/`calls` scopes, multiple independently revocable keys, and revocation
without invalidating issued tokens or established connections. Tokens default
to five minutes; the authenticated requester may request longer. No token/key
revocation coupling, extra TTL cap, per-definition key allowlist, scope hierarchy,
or complete admin API is introduced. Original admission/recovery contracts,
architecture, backlog statuses, and future acceptance checks are synchronized.
At that checkpoint there were 45 pending individual decisions, R06–R50;
R06–R10 was the next batch.
Verification covers unchanged fenced examples and 15 valid JSON examples,
unchanged links/URLs, exact resolved/pending IDs and counts, unrelated contracts,
terminology, local-path hygiene, and whitespace. No runtime or browser tests
were run for this documentation-only checkpoint.

The subsequent caller-reconnection scope decision defers R07 for the initial
slice. Replacement tokens remain available for eligible unstarted records;
logical call termination requires a new call rather than resuming the old one.
First admission of a transfer destination into a live room remains supported.
Earlier running-caller reconnect promises in historical checkpoints are
superseded. R06 still asks whether issuance supersedes unused tokens; temporary
transport failure is not declared to end a call. At that checkpoint: 44 pending
individual decisions, R06 and R08–R50. Verification checks three-file scope,
unchanged fenced examples and 15 valid JSON examples, unchanged links/URLs,
backlog IDs/count, admission boundaries, retained unrelated contracts,
terminology/local-path hygiene, and whitespace. No runtime or browser tests
were run for this documentation-only checkpoint.

The common-admission follow-up resolves R08: every API client prepares with
authenticated initial variables, receives a token, and joins with it. The removed
direct WebSocket setup supersedes R09 and does not adopt its proposed limits on
other routes. Optional call-level `opening_audio` plays a file URL or cached audio
from fixed text before receiver/normal service activation. Text rendering uses
the initial agent's resolved TTS voice/profile as a narrow asset-preparation
exception; no LLM or implicit human-only agent is needed. Cache identity tracks
text, resolved TTS/output settings, and tenant/configured binding. Omission means
normal startup. Playback completion, not download/render/enqueue, releases the
gate; exact evidence/failure/source/cache mechanisms remain unselected. R11's
variable interpolation is not approved by fixed text. At that checkpoint: 42 pending
decisions, R06 and R10–R50. Checks cover unchanged fences, 15 valid JSON examples,
37 local links/anchors, unchanged external URLs, scope/count, prior contracts,
terminology/path hygiene, and whitespace. Documentation only; no runtime or
browser tests were run.

The capability-warmup follow-up replaces opening audio's process-start gate with
a participant-media input gate: capabilities may initialize concurrently, but
receive no user/participant audio until playback completes. Ordinary greeting/
conversation still wait; no text barge-in or retrospective replay is approved.
R06 now preserves earlier unused tokens when another is issued, with independent
expiry/single-use and shared admission checks. R10 is closed as already covered
by initial variables supplied at call creation; no automatic lookup/resolver is
required. R09 remains superseded, not a new limits approval. At that checkpoint: 40
individual pending decisions, R11–R50. Verification checks unchanged fences,
15 valid JSON examples, 37 local links/anchors, unchanged URLs, exact scope/count,
media/admission boundaries and prior contracts, terminology/path hygiene, and
whitespace. No runtime or browser tests were run for this documentation checkpoint.

The instruction/time/retry follow-up resolves R11/R12 with agent instructions,
permitted variable reads and date/current-time tooling, without a template engine
or locale/timezone field hierarchy. R14 permits no automatic executor retries,
including definite non-submission failures; R15 skips operation classification.
R16 moves to the dedicated retry/idempotency issue. At that checkpoint R13
remained pending alongside R17–R50: 35 individual decisions. R39/R40 and ordinary
database transaction behavior remain separate. Checks cover four-file scope,
15 unchanged valid JSON examples, preserved existing links/URLs and the new issue
links, local targets/anchors, backlog statuses/count, prior contracts, terminology/
path hygiene and whitespace. Documentation only; no runtime or browser tests.

The R13 follow-up approves protected creation-time dial variables as an alternative
to literal participant numbers. The backend chooses an authorized number; no
agent may write its referenced section, and agent read permission is not needed
for trusted resolution. Transfer remains participant-ref-only with executor
allowlist enforcement; missing/null/invalid numbers fail before dialing and return
control to the source. No generic policy matrix or expression language is added.
At that checkpoint: 34 individual decisions, R17–R50. Checks cover three-file scope,
15 preserved existing JSON examples plus one new valid routing excerpt, unchanged
existing fences/links/URLs, local anchors, routing permissions and source exclusivity,
prior contracts, exact count/status, terminology/path hygiene, and whitespace.
Documentation only; no runtime or browser tests.

The cleanup follow-up resolves R20/R21 with periodic background selection and
external-first deletion, then database cleanup. Definitive missing keys count as
absent; actual/unknown object failures preserve call/artifact references for a
later sweep, including crash or database-failure recovery. No per-object journal,
permanent tombstone, hourly frequency, or exact deletion SLA is adopted. Late
writers still must be coordinated; ordering alone is insufficient. At that checkpoint,
backlog: 32 individual decisions, R17–R19 and R22–R50. Actual R22 (remote protocol
support) is unchanged. Checks cover three-file scope, 16 unchanged valid JSON
examples, unchanged links/URLs, local anchors, statuses/count, cleanup boundaries
and prior contracts, terminology/path hygiene, and whitespace. No runtime or
browser tests; no stored call data was deleted.

The R19 follow-up chooses application/tenant `call_retention` as `"forever"` or
an explicit seconds-duration object. Omission/inheritance and current-policy
behavior are unchanged; no call-level policy or duration parser is introduced.
At that checkpoint: 31 individual decisions, R17, R18, and R22–R50. Checks cover exact
three-file scope, 16 unchanged valid JSON examples, links/anchors, encoding and
inheritance, prior contracts, statuses/count, terminology/path hygiene, and
whitespace. Documentation only; no runtime tests.

The complete-tool-history follow-up supersedes metadata-default/opt-in storage:
always retain all observed invocation metadata, arguments/request payloads, and
responses/results/errors, regardless of client visibility. Credential/header
exclusions, unknown-outcome semantics, asynchronous general archival, and the
variable snapshot transaction boundary remain unchanged. R18 then asked only about
non-tool capture/storage configuration; that checkpoint retained 31 pending individual
decisions, R17, R18, and R22–R50. Checks cover exact three-file scope, 16 unchanged
valid JSON examples, links/anchors, active-rule consistency, prior contracts,
statuses/count, terminology/path hygiene, and whitespace. Documentation only.

R17 now specifies `tool_visibility` plus `tool_visibility_overrides`, keyed by
participant definition and local tool binding. Trusted creation can replace the
policy pair; an effective binding override still wins over its default. Samples
use full with no overrides, not a browser grant. Complete observed tool storage
is unchanged. At that checkpoint: 30 individual decisions, R18 and R22–R50. Checked
exact three-file scope, 16 preserved JSON examples plus two new valid visibility
examples, existing fences/links/anchors, policy precedence, prior contracts,
statuses/count, terminology/path hygiene, and whitespace. Documentation only.

R18 now resolves the remaining storage question: always retain available
transcripts, turn details, and usage/model/cost observations alongside tools and
committed variables, without per-category switches. Audio requires enabled and
permitted recording; archival needs do not start STT or bypass the opening gate.
Unavailable facts stay unavailable. Async general archival, transaction-confirmed
variable updates, credentials, client visibility, and remaining accounting choices
are unchanged. At that checkpoint: 29 individual decisions, R22–R50. Verified exact
three-file scope, 18 unchanged valid JSON examples/fences, links/anchors, active
capture/permission boundaries, prior contracts, statuses/count, terminology/path
hygiene, and whitespace. Documentation only; no runtime tests.

The remote-boundary follow-up resolves R22/R23 with the selected Streamable HTTP
revision and validated outgoing MCP arguments. R24/R25 move to separate deferred
issues; storing observed responses does not fetch attachments or implement
sampling, elicitation, or continuation. R18's available-history rule is reaffirmed:
audio exists only through available/integrated/enabled and permitted recording.
At that checkpoint: 25 individual decisions, R26–R50; next five R26–R30 remained proposals.
Checks cover exact five-file scope, 18 unchanged JSON examples/fences, old and new
links/anchors, validation/result/authority boundaries, prior contracts,
statuses/count, terminology/path hygiene, and whitespace. Documentation only.

The 2026-09-08 follow-up resolves R26–R30: SDK-aligned safeguards at Vxpipe's
outbound endpoint boundary, configurable 30-second startup readiness and 15-second
agent idle notification, no automatic long-tool progress speech, and a pinned
30-minute default duration with definition/tenant/application precedence. Added
the deferred wait-music issue without playback implementation. At that checkpoint:
20 individual decisions, R31–R50; next five R31–R35 remained unapproved. Verified
exact four-file scope, 18 unchanged JSON examples/fences, existing/new links and
anchors, timer/permission/clock boundaries, prior contracts, statuses/count,
terminology/path hygiene, and whitespace. Documentation only; no runtime tests.

The later 2026-09-08 follow-up resolves R31 and R33–R35: closing wording/hangup
timing belong to instructions; call-level `transfer_policy` shares defaults while
source allowlists and destination requirements retain their existing ownership.
Human transfer acceptance uses pending-leg DTMF or authenticated web control,
bound to the destination and attempt; agent destinations require readiness.
A configurable 30-second total attempt deadline includes preparation/dialing/
acceptance, with typed failure and exact late-leg cleanup. Provider AMD is the
approved detection source, but machine/unknown action then remained R32. At that checkpoint:
16 individual decisions, R32 and R36–R50; next five R32 and R36–R39. Verified exact
three-file scope, 18 unchanged JSON examples/fences, preserved links and local
anchors, statuses/count, transfer/closing/privacy and prior contracts, terminology/
path hygiene, and whitespace. Documentation only; no runtime or browser tests.

The R32 follow-up disconnects an attempted outbound destination leg when configured
provider detection reports machine, without ending an existing transfer's caller/
source conversation. Unknown awaits explicit transfer acceptance within the same
deadline; disabled/unavailable detection does not fabricate classification. Added
the deferred voicemail-message-delivery issue without a message feature, provider
tuning, or a new platform closing workflow. At that checkpoint: 15 individual decisions,
R36–R50; next five R36–R40. Verified exact four-file scope, 18 unchanged JSON examples/
fences, existing/new links and anchors, outcome/leg/deadline boundaries, prior
contracts, statuses/count, terminology/path hygiene, and whitespace. Documentation
only; no runtime or browser tests.

The R36–R40 follow-up resolves R36/R37/R39/R40. Source restoration gets exactly one
bounded attempt, with detailed failure cause internal-only even for full samples.
Private destination briefing/optional notice before acceptance is in initial scope,
not general concurrent-agent consultation. API creation has no idempotency feature;
admission only completes records for existing work, never repeats a crashed call.
R38 replaces the primary denial model with presence-driven publishing/subscription,
live transcript sharing, and independent transcript/audio retention; its exact
schema remains pending. Historical denial examples are marked superseded, and
R18 now stores permitted available media facts without changing variable/tool
contracts. At that checkpoint: 11 individual decisions, R38 and R41–R50; next five
R38 and R41–R44. Verified exact three-file scope, unchanged valid JSON examples,
the deliberate admission-identity text-example correction, links/anchors, counts,
privacy/retry/admission boundaries, and diff hygiene. Documentation only.

The R38 follow-up approves `media_policy` and participant `while_present`, complete
direct-key audio/transcript allowlists, independent room-wide storage flags, and
intersection/false-wins semantics under host authorization. Private preparation
stays isolated; apply presence restrictions at commit before main media. Enforce
automatic source-interval privacy across live routing and storage/copy paths without
retroactively deleting permitted history or adding generic redaction. Historical
denial examples remain superseded. At that checkpoint: 10 individual decisions,
R41–R50; next five R41–R45. Verified three-file scope, preserved examples plus the
new valid approved JSON fragment, local links/anchors, policy/commit/storage
boundaries, exact count/status, unchanged remaining rows, prior contracts, and
terminology/path/whitespace hygiene. Documentation only; no runtime tests.

The R44/R45 follow-up resolves usage observation settlement and honest call/
participant/service-interval/turn attribution. Preserve actual provider IDs for
optional asynchronous supported billing lookup, without promising cost availability.
Incremental/cumulative semantics remain distinct from estimate/final/correction
status; deduplicate by evidence, never by equal values, and count effective attempt/
component amounts once. Pricing remains R46; R41–R43 archive policies were unchanged
at that checkpoint. Its backlog was 8 individual decisions, R41–R43 and R46–R50;
next five R41–R43 and R46–R47. Verified three-file scope, unchanged JSON examples/links, accounting example
arithmetic, prior contracts, exact status/count, unchanged remaining rows, and
terminology/path/whitespace hygiene. Documentation only; no runtime tests.

The R43 follow-up approves the configurable 60-second outside-room finalization
window: publish early when expected work settles, or publish permitted available
facts with honest pending/missing components when it expires. This is reporting
wait, not a live-call extension, cancellation, or false-publication guarantee during
outages. Later facts can refresh publication while retention/privacy remain binding.
R41 overflow, R42 exact publication identity/retry design, and R46 pricing stayed
pending at that checkpoint. Its backlog was 7 individual decisions, R41, R42, and R46–R50; next five
R41, R42, and R46–R48. Verified three-file scope, unchanged JSON examples/links,
new planned finalization checks, accounting/prior contracts, exact status/count,
unchanged remaining rows, and terminology/path/whitespace hygiene. Documentation
only; no runtime tests or new issue.

The R42 follow-up approves immutable publication revisions with filenames from
their persisted UTC record timestamps, including three millisecond digits. Retries
reuse the same snapshot/identity/file; changed contents get a new revision, not a
value-driven schema version or an overwrite. Keep a latest-publication pointer
and collision protection rather than treating time as unique identity. All revisions
obey call retention and source-interval privacy. Current backlog: 6 individual
decisions, R41 and R46–R50; next five R41 and R46–R49. Verified exact three-file
scope, unchanged JSON examples/links, timestamp formatting, unchanged pending rows,
prior contracts, and terminology/path/whitespace hygiene. Documentation only;
R41's separate storage direction is not decided by this publication checkpoint.

[design]: ../labnotes/20260905-0405-call-definition-design.md
[architecture]: architecture.md
[mcp-design]: ../labnotes/20260905-0405-call-definition-design.md#applicationtenant-mcp-integrations-and-agent-enablement
[json-design]: ../labnotes/20260905-0405-call-definition-design.md#representative-json-shape
[variable-design]: ../labnotes/20260905-0405-call-definition-design.md#working-call-variable-schema-candidate
[variable-authorization]: ../labnotes/20260905-0405-call-definition-design.md#authorization-transaction
[variable-interruption]: ../labnotes/20260905-0405-call-definition-design.md#variable-updates-and-conversational-interruption--approved-g3-decision
[web-admission]: ../labnotes/20260905-0405-call-definition-design.md#web-participant-admission-routes--approved-g2-routing
[api-admission]: ../labnotes/20260905-0405-call-definition-design.md#initial-variables-and-api-key-admission--approved-g2-decisions
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
