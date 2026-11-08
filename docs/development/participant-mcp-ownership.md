# Participant-owned outbound MCP sessions

Status: researched proposal, 2026-11-08; runtime implementation has not changed.
The user requested a milestone for moving agent-used MCP connections into the
participant's call tree. The [implementation milestone](../../labnotes/milestones/participant-owned-mcp-sessions.md)
tracks that work separately from the integrations-directory workflow approval.

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
These are source observations, not newly executed teardown tests.

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
   Add a private owner/session identity tied to the room incarnation,
   participant, activation and a fresh runtime incarnation. The latter changes
   even if OTP rebuilds children under the same logical activation ID.
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

## Retirement and external effects

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
the optional embedded catalog refresher use independently bounded operation
subtrees, with caller/deadline cancellation, and release their clients on success
as well as failure. They neither lend sessions to calls nor consume a call's
remote session state. Registries and catalog snapshots can outlive operations.
The refresher currently starts `async_nolink` work under a sibling root task
supervisor and cancels from `terminate/2`; moving only CatalogLoader's client
under that task would not tie the task to a hard-killed refresher. Give each job
the refresher incarnation's lifetime and fence publication by that incarnation
at the catalog commit boundary. A held source/discovery result released after
refresher death/restart must neither open another session nor publish stale state.
This is a source-observed planning risk, not a newly reproduced runtime defect.

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
activation. Initially use sequential opens under one absolute activation/readiness
deadline (and a transfer's existing total budget), with no unbounded queue or
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
performed for this documentation proposal. Review and evidence are recorded in
the [research labnote](../../labnotes/20261108-1135-participant-mcp-ownership.md).
