# Participant-owned outbound MCP sessions

Status: implementation in progress, updated 2026-11-08. The first checkpoint makes
handle close target an exact session and retires that session on client loss.
The next checkpoint owns asynchronous POST, SSE and receiver workers under each
integration session, with observed worker/socket cleanup in eight loopback cases
and a ninth regression rejecting startup with an already-dead supervisor.
Participant placement, complete bounded retirement and queued catalogs remain pending.
The user requested a milestone for moving agent-used MCP connections into the
participant's call tree. The [implementation milestone](../../labnotes/milestones/participant-owned-mcp-sessions.md)
tracks that work separately from the integrations-directory workflow approval.
The user's follow-up adds persistent tenant catalog maintenance through a standard
background job queue, with application-configured expiry and a confirmed 30-minute
duplicate-scheduling window.

## Decision and boundary

Give each agent activation its own outbound MCP session subtree. Deduplicate
selected tools from the same resolved integration within that activation only.
Another participant, another call, or a replacement activation gets a fresh
client and protocol session, even when it uses the same saved credential grant.
Call Engine supplies lifecycle authority; `vxpipe_mcp` supplies the supervised
session components; ExMCP continues to implement the protocol and transport.

This concerns **outbound clients** used by agents. The **inbound platform MCP
endpoint**, used by external AI harnesses, stays in Gateway beside the reusable
HTTP API. Console mounts that Gateway in its Phoenix listener; Gateway and
Console remain separate umbrella applications. See the
[Gateway/Console boundary](../gateway-console-boundary.md),
[MCP endpoint](../../apps/vxpipe_gateway/lib/vxpipe/gateway/mcp/endpoint.ex), and
[Console endpoint](../../apps/vxpipe_console/lib/vxpipe/console/endpoint.ex).
The outbound application-wide connection supervisor is not that inbound server.

Target ownership, with names illustrative rather than new public API commitments:

```text
Room incarnation
└── ParticipantSupervisor
    └── AgentActivationSupervisor
        ├── MCP session supervisor
        │   ├── integration A: ExMCP client and owned transport work
        │   └── integration B: ExMCP client and owned transport work
        ├── remote tool binding owner
        ├── tool invocation/request supervisors
        └── agent coordinator and LLM session
```

The LLM and MCP resources share the activation owner. A worker running an LLM
request need not become a supervisor. Root registries, immutable catalog caches,
credential storage and bounded credential-operation coordination can remain
shared; they must not retain or revive a retired activation's protocol session.

## Findings in the current checkout

Research baseline: Vxpipe `abcd9db8`; ExMCP git revision
`5fa760207bb09fc3b19b3049bc481b5e55106095`, plus the tracked
[runtime credential patch](../../patches/ex_mcp/runtime-request-credentials.patch).
The table and dependency observations below describe that research baseline.
Subsequent implementation evidence is recorded in the milestone; in particular,
the detached transport-worker findings are addressed by the
[session transport ownership hook](mcp-runtime-transport.md#session-transport-ownership).

| Boundary | Current evidence | Consequence |
| --- | --- | --- |
| Session identity | [ConnectionKey](../../apps/vxpipe_mcp/lib/vxpipe/mcp/connection_key.ex) contains scope, integration ID and credential generation. | Equal identities within one tenant can share a session across calls; no activation identity is present. |
| Physical ownership | [Connections](../../apps/vxpipe_mcp/lib/vxpipe/mcp/connections.ex) opens/reuses clients under the root [ConnectionSupervisor](../../apps/vxpipe_mcp/lib/vxpipe/mcp/application.ex). | Stopping a participant does not structurally stop these clients. |
| Activation bindings | [RuntimeGraph](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/agent_activation/runtime_graph.ex) starts [IntegrationOwner](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/remote_mcp/integration_owner.ex), which acquires leases, opens shared clients and monitors the client PIDs. | Activation ownership currently covers bindings and execution authority, not the complete transport lifetime. |
| Credential leases | [CredentialLeases](../../apps/vxpipe_mcp/lib/vxpipe/mcp/credential_leases.ex) removes dead holders and distributes explicit local revocation. | Losing the last holder does not close the global client. |
| Catalog discovery | [CatalogLoader](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/remote_mcp/catalog_loader.ex) uses the same connection API; the optional [CatalogRefresher](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/remote_mcp/catalog_refresher.ex) is application-owned. | Discovery can legitimately happen outside calls, but needs its own operation lifetime and must not borrow a participant session. |
| Credentials | [MCPRuntimeCredentials](../../apps/vxpipe_calls/lib/vxpipe/calls/mcp_runtime_credentials.ex) and [MCPOAuthRefresh](../../apps/vxpipe_calls/lib/vxpipe/calls/mcp_oauth_refresh.ex) resolve current saved authority and coordinate durable refresh claims. | A separate protocol session does not imply a separate OAuth grant or independent refresh-token rotation. |

The pinned dependency requires particular attention. In its
[`HTTP.send_message/2`](https://github.com/HashNuke/ex_mcp/blob/5fa760207bb09fc3b19b3049bc481b5e55106095/lib/ex_mcp/transport/http.ex)
SSE path, POST work uses `spawn_monitor`, without a link to the client or a reverse
owner monitor in that worker. The patched client tracks monitor references and
request IDs, not a supervised worker tree. The inspected `ExMCP.Client` has no
`terminate/2` callback; `stop/2` calls `GenServer.stop`, while explicit
`disconnect/1` performs transport cleanup. Its HTTP `close/1` attempts session
DELETE before closing streams. `BoundedClient` owns a Mint connection in the
request process, so terminating only the client is insufficient evidence that
an asynchronous POST/socket has ended. `SSEClient` and `BoundedStream` have their
own links, cancellation and timer paths that must also be verified.

Production enables reconnect and SSE in
[ClientOptions](../../apps/vxpipe_mcp/lib/vxpipe/mcp/client_options.ex); the inspected
client defaults idle health checks to 30 seconds. A globally retained client can
therefore do network work without a live call holder. This proposal requires
effective worker, socket and timer evidence, not merely a different parent PID
or a call to `disconnect/1` in best-effort termination.

## Ownership and identity contracts

1. **Separate authority from session identity.** Keep the tenant/application,
   integration and credential-generation key for authorization/revocation.
   Use a fresh session-owner PID/reference for each live activation instance;
   keep room/participant/activation IDs as authority and diagnostic context.
   The owner identity changes even if OTP rebuilds children under the same
   logical activation ID. No additional compound identity framework is required.
   Connection lookup, close, readiness and returned handles must distinguish
   sessions by that identity. Never append an activation string to the tenant
   or credential generation to simulate a separate authority domain.
2. **Only compatible aliases share.** Within one activation, tools may reuse a
   session only when their resolved endpoint, configuration/credential pins and
   effective transport policy agree. Conflicting response limits/configuration
   must fail validation or be resolved deterministically before startup; the
   first map entry must not choose policy for the others. Catalog/tool pins and
   alias-specific execution budgets remain independently enforced.
3. **Supervise the real work.** Start dynamic session children through the
   activation-owned supervisor. All call-specific protocol clients, asynchronous
   POST workers, stream readers and reconnect/health work have a structurally
   enforced lifetime within that subtree. Dependency internals may use links
   and owner monitors, but cannot escape via unowned background tasks. Avoid
   reverse dependencies from `vxpipe_mcp` to Calls, Gateway or Call Engine.
4. **Publish readiness atomically.** Open only integrations selected by the
   activation's pinned tools. Complete the approved initialization and current
   credential check before publishing bindings/readiness. A second integration
   failing, caller cancellation, startup timeout or owner death retires every
   partially opened child and lease. Do not block room authority on network work.
5. **Preserve the activation failure domain.** Client loss invalidates its bound
   handles and follows the existing bounded activation recovery policy. An
   internal restart may not leave old bindings pointing to a replacement client.
   Rebuild with a fresh runtime incarnation and revalidate authority; never replay
   a submitted tool call. Failure of A does not retire B's session in another
   activation. Do not add a second unbounded restart loop around ExMCP reconnect.

For example, tenant A's saved connection 42 and its cached catalog can serve
call 1 through owner P1 and call 2 through owner P2. Restarting call 1's agent
creates owner P3. A late close/result addressed to P1 cannot resolve to P3.
These are local process identities, not database connection IDs or the remote
server's optional MCP session ID. Tenant and credential-generation checks remain.

## Retirement and external effects

Here, **retirement means stopping an agent activation and releasing its resources**:
on hangup, after a successful transfer, or before replacing a failed activation.
It does not delete the tenant's saved connection, credentials or catalog.

Retirement first fences new tool submissions and readiness. The submission fence
must cover the effective transport boundary, including requests already queued
in ExMCP and workers stalled in authorization, DNS or connect. Binding lookup or
caller death alone is not that fence. Serialize final submission admission with
retirement, then quiesce/terminate previously admitted local workers before
acknowledging the fence; distinguish work that may already have reached the
network from work rejected before submission. A callback released after retirement
must not turn queued or pre-submission work into a new tool POST. Only explicitly
permitted cleanup traffic may be admitted during the grace period.

Stop invocation workers before disposing of their clients; preserve the existing one-for-all
activation semantics and use child order deliberately. All close paths are
idempotent and target an exact owner/session incarnation. A delayed close or
result from an old incarnation cannot affect its replacement.

Normal retirement may send protocol cancellation for an eligible pending request
and one best-effort session DELETE, using current authority. These operations
consume a single finite cleanup budget shared across the activation's sessions;
they must not extend shutdown once per integration or wait through reconnect
backoff. Start with a **1,000 ms graceful cleanup budget per activation**, then
force local worker/socket termination and acknowledge completion only after
monitored descendants are down. DNS, credential resolution, cancellation of
call-owned renewal jobs and an unresponsive DELETE all consume that budget.
Cleanup uses a fresh, non-renewing credential resolution: if authorization is
unavailable, requires token renewal, or cannot be obtained within the remaining
budget, skip DELETE. Never start a token exchange solely to clean up a session
and never use cached credentials. This default
is a proposed engineering choice to verify in the implementation checkpoint,
not a claim about current shutdown timing. Supervisor children remain proper
supervisors with OTP shutdown semantics; a bounded lifecycle worker owns the
network grace period.

Forced death need not send DELETE or execute `terminate/2`. It must still remove
local call-owned work. After teardown completion there is no call-session POST,
GET, ping, reconnect or delayed retry. Bytes already submitted before fencing
may arrive later at the remote server. We cannot promise to kill that server,
roll back tool side effects or erase its session state. A stateless server may
also omit a session ID entirely: client/worker isolation still applies.

The approved [MCP lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle)
uses transport closure for shutdown. The
[Streamable HTTP contract](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)
makes session IDs optional, recommends DELETE when finished, permits a 405 response,
and does not equate a disconnected stream with request cancellation.
[Cancellation](https://modelcontextprotocol.io/specification/2025-11-25/basic/utilities/cancellation)
is cooperative and can lose a race with completion. Preserve the existing
[submit-only tool outcome contract](../tool-execution-model.md): a request that
may have reached the peer remains unknown without definitive evidence, with no
automatic executor replay. Retired activations cannot receive late continuations.

**Saved credential disconnect is a different event from call retirement.**
Preserve current saved-runtime behavior: a request submitted before a Console
disconnect may finish in its still-running room; subsequent transport submissions
must resolve current authority and fail. Explicit local `Connections.revoke/1`
currently retires clients and notifies holders; preserve that stronger behavior
across all matching owner sessions. Closing one session must never implicitly
revoke the shared grant. Keep the separate-node request-time authority checks;
a local registry alone is not cluster-wide revocation.

OAuth storage and refresh claims remain grant-scoped. Keep the existing bounded,
caller-monitored renewal runner and crash fencing, including ambiguous rotating
refresh-token outcomes; do not add a refresh scheduler for each participant.
Call-owned callers must disappear on retirement so their pending renewal work
is cancelled, without cancelling a different caller's job. Root-owned renewal
workers are an explicit exception to physical subtree placement, not to lifetime
ownership: teardown needs operation-specific cancellation/termination acknowledgement
from the runner as well as descendant DOWN messages. A request queued at the
runner but not yet admitted must be fenced against later admission/submission;
processing a caller DOWN eventually is insufficient for teardown acknowledgement.
The same common deadline covers cancellation and observed termination of these
jobs; no detached post-teardown cleanup waiter may keep the call's work alive.
A token exchange
already accepted remotely may still have effects; late results cannot restore
revoked/replaced grants. Ordinary unrelated management/renewal operations remain
possible outside a call. The guarantee is removal of the retired call's work,
not that the entire application becomes silent when one call ends.

## Discovery, compatibility and capacity

Saved catalog reads remain metadata-only. Management checks, OAuth discovery and
background catalog jobs use independently bounded operation subtrees, with
caller/job cancellation and deadlines. They release clients on success and
failure, never lend them to calls, and never consume a call's remote session state.
Registries and database catalog snapshots can outlive operations. A catalog job
may run with no calls active; ending a call does not cancel that independent job.

The older optional embedded `CatalogRefresher` reads application configuration,
not saved tenant database rows. Its `async_nolink` ownership/publication concern
remains recorded in the original research; it is not the scheduler selected for
saved tenant maintenance. Adapt embedded session ownership only as necessary for
the changed client API. Broader embedded refresher recovery/publication work is
a separate follow-up, not a prerequisite for the queue described below.

Migrate every shipped consumer of the current global `Connections.open/2` path.
The library should expose explicit owner-supervisor/session construction for
trusted embedded hosts; an ownerless fallback must not silently restore sharing.
Document any changed `open`, `lookup`, `close`, test-provider and handle contracts.
Keep standalone ExMCP integration usable without Call Engine or a database, with
the embedding host providing the owner. Existing saved IDs, call specs, grants,
tool selections and Console workflows require no migration. A rolling mix of
old/new runtimes cannot promise this ownership guarantee for calls on old nodes;
rollout evidence must identify the running revision and drain old sessions.

Connect only the finite set of selected integrations, deduplicated once per
activation. Use one absolute activation/readiness deadline (and a transfer's
existing total budget), with no unbounded queue or
per-client reset of that deadline. Preserve existing tool/admission bounds.
Measure session/worker counts and handshake/teardown latency at a declared call
concurrency; do not claim unlimited provider capacity. Provider session-limit
rejection fails readiness cleanly, leaving a transfer source responsible. New
cross-tenant quotas or automatic eviction are separate product work.

The present ReqLLM activation path owns `IntegrationOwner`. The native STS path
[compiles descriptors without a remote owner](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/plan_startup/speech_to_speech_activation.ex),
and [remote binding construction](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/tool/invocation_binding.ex)
rejects that missing owner. This milestone changes ownership for supported MCP
execution; it does not silently claim new native STS MCP support. Keep that
unsupported combination explicit and regression-tested. Any later STS MCP
feature must use the same participant-lifetime contract.

## Persistent tenant catalog maintenance

The cached catalog contains the complete discovered tool descriptors, including
names, descriptions and schemas, for one **tenant-owned saved connection**.
Two tenants using the same endpoint must retain separate snapshots: upstream
authorization can expose different tools. Pin the snapshot to the connection's
configuration/credential generation. Never share it merely by endpoint/directory
entry or treat cached tools as a substitute for current request authorization.

The current [connection schema](../../apps/vxpipe_persistence/lib/vxpipe/persistence/schema/mcp_connection.ex)
already stores the catalog. Static connection setup discovers it during save;
[OAuth completion](../../apps/vxpipe_console/lib/vxpipe/console/mcp_oauth_completion.ex)
discovers it after the user's successful authorization and token exchange,
including the DCR/CIMD paths. Preserve this initial readiness check. Manual
`refresh_tools` also exists. This milestone adds durable scheduling and freshness
timestamps, not a second catalog database or a new consent workflow.

### Queue and application ownership

Select **Oban with the existing PostgreSQL Repo** for the Sidekiq-style job model.
Use its periodic scheduling to enqueue a sweep job; the sweep enqueues one job
per due tenant connection. Use its ordinary retries, finite worker timeouts,
orphan recovery and job pruning. No Redis service, paid extension, custom queue
engine or one permanent timer/client per saved connection is required.

`vxpipe_persistence` owns the Oban dependency, migrations, supervision after Repo,
transactional enqueue adapter and thin workers. Workers invoke a trusted Calls
catalog-maintenance workflow through repository/protocol ports. Calls remains
database/queue-library independent; `vxpipe_mcp` owns bounded protocol operations.
Do not add a Persistence-to-Console dependency or fabricate a browser principal.
Extract any reusable headless discovery/credential adapter currently placed in
Console to its owning lower application, retaining existing management behavior.
Start jobs only in configured persistence hosts; standalone Call Engine/MCP
embedding still works without PostgreSQL or Oban.

Read application configuration for catalog expiry, sweep cadence, batch size,
queue concurrency and worker timeout. **Do not add environment variables.** A
proposed starting policy is a one-hour expiry, one-minute sweep and batches of
100, with four refresh jobs per node and a finite operation timeout. The expiry
is deliberately adjustable, and the confirmed rescheduling window is 30 minutes.
For example, the planned domain policy can be expressed as:

```elixir
config :vxpipe_calls, :mcp_catalog_refresh,
  expiry_seconds: 3_600,
  reschedule_after_seconds: 1_800
```

Queue/cron settings belong in the persistence host's Oban application configuration.
Validate positive bounds. Per-node queue concurrency is not a cluster-wide limit.
Use bounded indexed batches rather than scanning/decrypting every tenant record
on every sweep; the sweep needs metadata only. Exclude connections with incomplete
matching jobs before applying the batch limit, or use bounded keyset progress so
those rows cannot occupy every sweep's first batch and starve later connections.
Keep scheduling and network work off call startup and the audio path.

### Timestamp and scheduling contract

Add nullable UTC timestamps with microsecond precision to each saved connection:

| Field | Meaning and writes |
| --- | --- |
| `refresh_scheduled_at` | Time the latest background refresh job was durably enqueued. Update only in the same transaction as insertion of a new job; not when a sweep merely sees the row, a duplicate is suppressed, or an existing job retries. |
| `refreshed_at` | Time the latest complete validated catalog was successfully committed. Set alongside the initial saved catalog and each accepted automatic/manual refresh, even when the catalog is unchanged or validly empty. Failure never advances it. |

Use database time for persisted comparisons. General `updated_at`, OAuth token
renewal and encryption-key rotation do not establish catalog freshness. Existing
records with unknown catalog age retain their catalog and start with null
`refreshed_at`, making them eligible for a bounded first sweep; do not invent
historical freshness from a migration's execution time.

The user confirmed this eligibility rule, including the direction of the
30-minute comparison:

```text
connected
AND (refreshed_at IS NULL OR refreshed_at <= now - configured_expiry)
AND (refresh_scheduled_at IS NULL OR refresh_scheduled_at <= now - 30 minutes)
```

Thus a stale catalog scheduled five minutes ago is skipped; the same stale
catalog becomes a candidate after 30 minutes. A fresh catalog is always skipped.
The timestamps control periodic enqueue eligibility, not remote authorization
or an exactly-once execution guarantee.

For each candidate, briefly lock/recheck the row and enqueue the job plus update
`refresh_scheduled_at` in **one Repo transaction**. An enqueue/transaction failure
must leave neither a committed scheduling timestamp nor a committed job. Multiple
sweepers must converge on one scheduling decision. Use Oban uniqueness keyed by
tenant, connection and connection generation as a secondary guard; timestamp
checking outside a transaction is insufficient. Use ordinary unique insertion
inside the bounded batch, not a bulk insert that bypasses uniqueness. Oban may
return `{:ok, job}` for a uniqueness conflict: advance the timestamp only for an
actual insertion (`conflict? == false`). Match available, scheduled, executing
and retryable jobs (or the selected version's incomplete-state equivalent), not
completed history.

Before inserting a replacement after 30 minutes, check whether a matching job
is still queued, running or retryable. Keep/recover that job instead of adding
a duplicate due to queue delay; do not advance the timestamp on that no-op.
Oban's configured orphan recovery handles abandoned executing jobs. Choose a
rescue age above the finite worker timeout and below the 30-minute recovery
window. Missing, cancelled or discarded jobs allow a new scheduling decision
once the row is eligible. Configure bounded attempts/backoff and monitor repeated
failures; no permanently stuck job may suppress refresh forever.

### Refresh execution and failure behavior

Job arguments contain only tenant/connection IDs, connection generation and
the committed scheduling timestamp. Resolve current credentials when the job
executes; do not serialize tokens, headers, secrets or whole connection records
into the queue. OAuth token renewal reuses existing grant coordination.

At execution, recheck connection status/generation, scheduling stamp and catalog
freshness; obsolete jobs finish without network work. Open a job-owned temporary
MCP session, initialize, fetch every catalog page within the existing deadline
and response limits, validate, then close all protocol resources on completion,
timeout or job cancellation. Do not hold a database transaction during network I/O.

Commit the catalog and `refreshed_at` together only if the connection is still
connected, its generation/scheduling stamp still match, and `refreshed_at` exactly
matches the value observed before discovery, using a NULL-safe comparison. Every
accepted publication must change that value: use database time, advancing at least
one microsecond beyond the prior value if the clock is equal or moves backwards.
This makes the existing freshness field a reliable publication guard without a
separate version framework. It also prevents an old queued result from replacing
a newer manual refresh, including under a fixed clock. Manual refresh remains
an immediate authorized operation and uses the same conditional publication
contract; successful initial/manual refresh does not pretend a job was scheduled.
Replacement/reconnect publishes its newly discovered catalog and clears obsolete
scheduling state. Disconnected/deleted connections are never revived by late jobs.

Queue delivery/rescue can repeat a discovery attempt. Treat discovery as read-only
and publication as conditional/idempotent; do not claim exactly-once execution.
Successful no-change discovery still updates freshness. Transient failure keeps
the last complete snapshot and old `refreshed_at`; partial discovery must never
replace it with an empty or incomplete list. Authorization failure uses existing
fail-closed behavior, with a redacted job outcome and no credential fallback.
Use existing job error/attempt data rather than adding a new failure-history system.

Newly discovered tools never expand a published agent's explicit selection or
rewrite a running call's pinned schema. Catalog caching removes per-call tool
discovery; it does not remove per-activation MCP initialization. A queue backlog
must not stop call startup solely because a refresh job is pending; existing
generation and current-authority checks still apply.

### Library research and scope

Official Oban documentation inspected on 2026-11-08 describes
[transactional insertion](https://hexdocs.pm/oban/Oban.html#insert/5),
[periodic scheduling](https://oban.hexdocs.pm/Oban.Cron.html),
[worker timeouts/retries](https://hexdocs.pm/oban/Oban.Worker.html),
[uniqueness](https://hexdocs.pm/oban/unique_jobs.html) and
[orphan recovery](https://oban.hexdocs.pm/Oban.Lifeline.html).
Uniqueness concerns insertion, not exactly-once execution; time-based orphan
recovery can duplicate an attempt. The transactional row check and conditional
publication are project-owned safeguards. The inspected docs report Oban 2.24.2
and use `Oban.Cron`; the old `Oban.Plugins.Cron` entry is deprecated. Verify and
pin a compatible maintained version during implementation, with its migrations
and lockfile. No Oban dependency or migration is added by this planning change.

## Alternatives and implications

| Alternative | Decision and tradeoff |
| --- | --- |
| Retain the global pool and close after the last lease | Rejected: shared protocol state/failure domains remain, and lease cleanup still needs crash-safe transport ownership. |
| Put one shared client pool under each room | Rejected: another participant can inherit session state, and transferring out does not retire the source's session while the room lives. |
| Put clients under the stable participant identity | Insufficient by itself: re-entry and activation recovery must create fresh protocol state. Use the activation subtree and a runtime incarnation. |
| New connection for every tool invocation | Rejected: unnecessary repeated initialization and no coherent activation session for related tool calls. |
| Move credentials/refresh storage into the participant | Rejected: duplicates shared grant state and risks refresh-token rotation races; credentials and protocol sessions have different lifetimes. |
| Replace ExMCP or implement a second HTTP/MCP client | Rejected: repair the pinned dependency ownership boundary through its public integration or a reviewed narrow patch. Retain the approved protocol/conformance gates. |

The chosen design uses more processes and upstream sessions, repeats initialization
on activation/re-entry and loses cross-call warm-session reuse. Transfer preparation
temporarily needs both source and destination sessions. In return, it isolates
protocol state and failures and makes local call teardown enforceable. Shared
generic transport infrastructure is acceptable only if it retains no retired
call-specific requests, auth snapshots, streams or protocol state.

## Verification and implementation evidence

The [milestone](../../labnotes/milestones/participant-owned-mcp-sessions.md) requires
deterministic project-owned supervision/fencing tests and real ExMCP loopback
wire acceptance. It includes two same-tenant calls, same-room participants,
transfers/re-entry, partial startup, blocked POST/GET/DELETE, credential/renewal
races and bounded churn. Tests must observe descendant termination and peer
activity, not infer it from a dead binding owner or wait for an arbitrary sleep.

Source research and primary documentation were read on 2026-11-08. The
[Supervisor documentation](https://hexdocs.pm/elixir/Supervisor.html) informs child
ordering and restart/shutdown design. Published
[ExMCP documentation](https://hexdocs.pm/ex_mcp/ExMCP.Client.html) describes the
public API, but the locked revision plus checked patch is the implementation
baseline. No new runtime reproduction, load benchmark or conformance run was
performed for the original documentation proposal. Review and evidence are recorded
in the [research labnote](../../labnotes/20261108-1135-participant-mcp-ownership.md).
Subsequent reproductions, fixes and verification are recorded in the
[implementation labnote](../../labnotes/20261108-1401-participant-mcp-implementation.md).
