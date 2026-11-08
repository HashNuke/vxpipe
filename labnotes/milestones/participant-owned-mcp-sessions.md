# Participant-owned MCP sessions

Status: **specified; not implemented**. Requested 2026-11-08 after the outbound
ownership review. This document records a new runtime slice; it neither changes
the implementation nor completes the integrations-directory workflow approval.

## Prerequisites and design sources

Read the [ownership decision](../../docs/development/participant-mcp-ownership.md),
including its dependency-worker findings, rejected alternatives and shutdown
limitations. It defines the proposed change to the historical shared-client
design in [Remote MCP tools](remote-mcp-tools.md) and
[MCP client integration](mcp-client-library.md).

Implementation depends on their existing protocol and binding contracts, the
[ReqLLM agent runtime](reqllm-agent-runtime.md),
[agent transfers](agent-transfers.md),
[transfer readiness](transfer-readiness-and-wait-sounds.md), and the implemented
saved-runtime/credential portions of
[Integrations directory and tenant MCP connections](integrations-directory-and-tenant-mcps.md).
The latter still awaits its own explicit user workflow approval; this specification
does not supply it. That approval is not a technical prerequisite for isolated
ownership work on its already implemented runtime. No unfinished STS provider,
onboarding, delivery or retention milestone is added as a prerequisite.

Also read [saved-runtime authority](../../docs/development/saved-mcp-runtime.md),
[current transport credentials](../../docs/development/mcp-runtime-transport.md),
[tool outcomes](../../docs/tool-execution-model.md) and
[Gateway/Console ownership](../../docs/gateway-console-boundary.md).

## Runnable outcome

Start two admitted calls using the same saved tenant MCP. Each selected agent
activation initializes its own ExMCP session and executes its allowed tool.
Ending one call removes all of its local MCP clients, request workers, streams
and reconnect work; the other call continues with its original session. An
agent-to-agent transfer prepares an independent destination session, then retires
the source session only after commit. Failed preparation leaves the source usable.

Inbound platform MCP and Console management keep their current public behavior.
This is a runtime ownership change: existing call specs, saved connections, OAuth
consents and approved form workflows do not acquire new fields or steps.

## Contracts for implementation

- Separate shared credential authority from private session ownership. Owner
  identity includes room incarnation, participant, activation and a fresh runtime
  incarnation; aliases may share only inside that owner with compatible pins and
  transport policy. Never key sessions solely by the grant or stable participant.
- Start the MCP subtree inside the agent activation. Enforce ownership of the
  effective ExMCP POST/GET workers and sockets, not only the binding GenServer.
  No detached background client/task may survive call retirement.
- Publish bindings only after every selected integration is ready under the
  existing protocol profile and current authorization. Roll back partial startup.
  Sequential opens share the original absolute readiness/transfer deadline.
- Retire/fence execution before closing transport. Use one proposed 1,000 ms
  graceful cleanup budget for the whole activation, then force local termination;
  acknowledge teardown after all owned descendants have terminated. Cleanup may
  send bounded cancellation/DELETE with current credentials; hard death cannot
  depend on callbacks. No retries, pings or reconnect after teardown completion.
  The fence covers final transport submission admission, queued ExMCP requests,
  and workers blocked before authorization/DNS/connect completion. Binding lookup
  alone cannot authorize a later POST from a retired incarnation. Quiesce admitted
  local work and distinguish possible prior submission from a local rejection.
  Cleanup resolves current credentials without renewal; if that requires a token
  exchange or exceeds the remaining deadline, skip DELETE. Ordinary queued renewal
  work is fenced/cancelled; cleanup does not create a replacement token exchange.
- Preserve one-for-all activation recovery and existing restart limits. A client
  replacement invalidates old handles; any recovery uses a fresh runtime session
  identity and current grants, without replaying already submitted tools.
- Preserve the distinction between session close, explicit local grant revocation,
  and saved Console disconnect. Close affects one owner; local revoke fans out
  to all holders of that credential generation; saved disconnect blocks later
  submissions while already submitted work may finish in an active room.
- Keep shared encrypted credential storage, durable OAuth claims and bounded
  caller-owned renewal jobs. Ending a call cancels its jobs, not another call's
  job or the shared grant. Current request-time checks remain authoritative across
  nodes. Preserve ambiguous refresh handling and generation/revision fencing.
  Teardown acknowledgement also waits for operation-specific cancellation and
  termination of call-owned jobs under the root renewal supervisor. Fence queued
  runner requests that could otherwise be admitted after caller death; eventual
  processing of caller DOWN is not sufficient proof of completed teardown.
- Give discovery/check/refresh operations their own bounded lifetime; no call
  session borrowing and no idle global connection cache left by shipped callers.
  Preserve immutable catalog sharing and metadata-only saved catalog reads.
- Keep ExMCP and the approved `2025-11-25` profile. Any missing dependency ownership
  hook needs a reproduced project-boundary failure and reviewed upstream change
  or checked patch; no replacement protocol client or wider protocol upgrade.
- Keep MCP library APIs independent of Call Engine. Migrate shipped and trusted
  embedded provider contracts to explicit ownership; reject incompatible handles
  rather than falling back to global sharing. Native STS MCP support remains
  explicitly unsupported in this slice, as in the researched current path.

## Implementation checkpoints

Each checkpoint includes red/green evidence, relevant documentation and a coherent
commit. Checkboxes below are runtime work, not specification-review results.

### T1 — Owner-bound standalone session lifecycle

- [ ] Add the smallest failing `vxpipe_mcp` boundary tests: two owners with the
  same credential key receive different clients; stopping one removes only its
  clients, including when initialization is blocked or only partially complete.
- [ ] Introduce explicit owner/session construction and handles without importing
  Calls or Call Engine. Separate exact-session close/lookup from grant revocation.
  Validate compatible deduplication and reject stale/foreign owner handles.
- [ ] Add effective ExMCP fixture tests for an active SSE stream and blocked
  asynchronous POST. Prove owner/client forced death ends transport workers and
  peer sockets; reproduce any gap before fixing the dependency integration.
- [ ] Implement bounded graceful cleanup and forced cleanup, including POST/GET
  connect, DNS, DELETE and credential-resolution stalls. Verify the single total
  grace budget and finite completion with multiple sessions; no `terminate/2`-only
  correctness or one full grace budget per integration.
  Pause requests before submission, including after credential resolution and DNS;
  retire the owner and release the pauses. Observe no tool POST from the retired
  incarnation; cleanup cancellation/DELETE is the only permitted grace traffic.
- [ ] If dependency work is needed, update the exact patch/manifest or git pin,
  migration checks and `mix.lock` as appropriate. Verify fresh checkout preparation,
  supported prior-patch upgrade and the affected official conformance lane.

Exit: a standalone host can own, invoke and retire isolated sessions without a
room/database, with measured descendant and wire cleanup on success/failure.

### T2 — Agent activation composition and failure isolation

- [ ] Red-test activation ancestry and two same-tenant admitted rooms using one
  integration. Wire the local session supervisor before binding publication,
  passing only safe identity/resolver descriptors through saved child specs.
- [ ] Deduplicate compatible aliases within an activation, preserve schema/tool
  pins and per-invocation budgets, and reject conflicting effective policies.
  Native-only agents start no MCP subtree and perform no MCP storage lookup.
- [ ] Open only selected integrations under one absolute readiness budget; fail
  closed and clean every partial child/lease on cancellation, timeout or failure.
  Room authority remains responsive throughout initialization and cleanup.
- [ ] Preserve existing activation restart/failure semantics with fresh runtime
  incarnation identity. Old handles, results, close messages and readiness cannot
  affect a replacement. Prove one participant's failure leaves other sessions usable.
- [ ] Verify supported MCP agents through saved and embedded catalogs; preserve
  fail-closed rejection for unsupported native STS MCP configuration. Do not enable
  a new provider/tool path accidentally while moving ownership.

Exit: real participant-owned clients execute through the ordinary LLM/tool path;
normal stop, crash and bounded recovery isolate protocol state and lifetimes.

### T3 — Shared credentials and independent management operations

- [ ] Red-test two isolated sessions with the same saved grant during expiry,
  disconnect, replacement and local revocation. Keep current credential checks
  before POST, GET/reconnect and DELETE, with no cached fallback on storage failure.
  Add a non-renewing cleanup resolution path: an expired/renewal-required grant
  skips DELETE without a token exchange, while a current valid grant permits it.
- [ ] Verify durable OAuth refresh claims across sessions/nodes; one caller's
  retirement cancels its work without killing another caller's job. Exercise
  held exchange responses, late completion and claimant death; stale results cannot
  resurrect a grant or trigger another token/tool submission for the retired call.
  Include a queued-but-not-admitted renewal request and require the runner's exact
  operation termination/cancellation acknowledgement before reporting teardown.
- [ ] Preserve already-submitted request completion after saved disconnect in an
  otherwise live room. Separately prove call retirement fences its late completion
  and never retries an ambiguous remote side effect.
- [ ] Migrate catalog loading, optional refresh, checks, test providers and
  standalone embedding to explicit bounded operation/host owners. Close clients
  on success, caller death and deadline; verify calls and management never share
  the same session or retire each other's session.
  Bind the optional refresher's task to its coordinator incarnation, including
  hard death; fence catalog publication against stale coordinator/job generations.
  Hold source/discovery work, kill/restart the refresher and release the old work:
  no surviving old task/client, late session creation or stale catalog publication.
- [ ] Remove the obsolete global session-cache path from shipped use and document
  intentional internal API changes. Keep root registries/coordination only for
  their independent responsibilities; preserve inbound MCP and management routes.

Exit: credential authority remains shared and current while all protocol sessions
have explicit lifetimes. Both management and ongoing calls still work independently.

### T4 — Transfers, complete call teardown and acceptance

- [ ] Red-test source/destination overlap using the same integration: distinct
  sessions during preparation, destination ready before commit, source cleanup
  after commit, and failed/cancelled preparation cleans only the destination.
- [ ] Prove re-entry uses the same participant identity with a fresh activation
  and session; activation recovery and room-incarnation replacement also fence
  old close/reconnect/results. The transfer's existing total budget never resets.
- [ ] Extend saved WebRTC and managed incoming/outgoing plus legacy incoming phone
  acceptance through hangup, durable ended state and MCP descendant/wire cleanup.
  Keep call admission, media privacy and transfer routing unchanged.
- [ ] Run a bounded churn/concurrency scenario. Record session/client/worker counts,
  per-activation handshake and teardown latency and the declared concurrency;
  return to baseline after retirement. Include provider session-limit rejection
  during overlapping transfer without switching to shared sessions.
- [ ] Add payload-free lifecycle measurements with bounded labels. Never publish
  raw session IDs, endpoint secrets, authorization headers or tool payloads.
  Verify logs/status/supervisor failures with synthetic secret markers.
- [ ] Complete the acceptance matrix, manual verification and common gates below.
  Update architecture/runtime/API docs and record rollout/drain guidance so old
  globally pooled sessions are not represented as already migrated.

## Acceptance and failure matrix

| Case | Required evidence |
| --- | --- |
| Equal grant across two calls; equal integration across two tenants | Separate local clients and, when assigned by the fixture, remote session IDs; one caller cannot observe the other's session state. Stopping A leaves B callable with its original session. |
| Two participants in one room; multiple aliases in one activation | Separate participant sessions; compatible aliases reuse one local client without expanding grants or changing budgets. |
| Stateless MCP peer | No session ID does not weaken local ownership or worker cleanup. |
| Second integration fails; startup caller/owner dies | No published partial readiness; all first-integration descendants and leases end, including blocked initialization. |
| Shutdown with held POST, idle/resumed GET, pending reconnect or health timer | Monitor descendant DOWN messages and observe peer closure; no newly submitted call traffic after teardown. Controlled release of old callbacks cannot revive work. |
| Work paused before submission, after auth/DNS, or queued in ExMCP/renewal runner | Retirement fences final submission admission; releasing pauses yields no new tool POST or token exchange. Exact-operation cancellation/termination acknowledgement covers root-owned jobs as well as local descendants. |
| DELETE stalls, returns 405 or fails current authorization | Local cleanup completes within the bounded lifecycle; no cached auth, retry loop or shutdown extension per client. Renewal-required credentials skip DELETE without starting a token exchange. |
| Client killed; activation killed; room owner killed | Correct failure-domain handling and fresh identities on permitted recovery; other calls remain usable; graceful callbacks are not required. |
| Saved disconnect vs local revoke vs exact-session close | Existing saved in-flight completion is preserved; later requests fail closed. Local revoke reaches every matching holder. Closing one session does not revoke the grant or close another. |
| Parallel OAuth refresh and remote-node grant changes | Durable claims prevent duplicate refresh authority; retired caller/late response cannot restore stale state; unrelated job continues; no retired session request resumes. |
| Transfer commit, failure, cancellation and re-entry | Distinct overlapping sessions; source remains responsible until commit; cleanup targets exact incarnation; no stale tool continuation or replay. |
| Management discovery during live calls | Own bounded sessions; no change to active call sessions, metadata pins or approved Console workflow. |
| Embedded refresher killed/restarted during held source/discovery | Old job/client terminates and cannot publish stale catalog state or start a new session; replacement refresh works under a fresh incarnation. |
| Repeated calls and provider connection cap | Session/worker counts return to baseline; bounded failure and truthful latency/count evidence; no hidden global pool fallback. |

Use `start_supervised!/1`, process monitors and project/fixture acknowledgements.
For negative network assertions, fence admission, observe worker/socket closure,
release controlled pending callbacks, and inspect the peer's acknowledged request
ledger. Do not substitute sleeps, binding-owner death or mocked `close` calls for
transport proof. Keep real network cases in tagged integration lanes. Tests belong
to the app owning each contract, not to a consumer reaching into another app's
private internals. Dependency behavior is tested only at Vxpipe's integration
and supervision boundary.

## Manual verification

1. Use an authenticated local Console and a controlled MCP with session/operation
   observations. Start two saved-spec WebRTC calls with the same tenant connection;
   execute tools, end the first, and execute again through the second.
2. Transfer between two agents selecting that connection, then re-enter the first.
   Observe the owned trees and initialization/termination records. Repeat with
   destination initialization held past its deadline and with an ordinary hangup.
3. While a call is live, run saved-connection testing/discovery, then disconnect
   the saved grant. Verify independent management cleanup and the existing
   in-flight-versus-new-invocation behavior. Repeat retirement during a held POST.
4. Verify the inbound platform MCP remains available to an external client after
   call shutdown. No new UI is planned; if implementation changes any UI, inspect
   it in rendered desktop/mobile Chrome with `agent-browser` and record evidence.

## Completion gates

- [ ] T1–T4 outcomes and every acceptance row have actual evidence; record gaps
  instead of checking off a partially verified slice.
- [ ] Run focused owner-app tests and tagged ExMCP/saved runtime, transfer, phone
  and renewal lanes. Record commands, revisions, seeds, counts and exclusions.
- [ ] Pass all [common gates](index.md#common-implementation-and-verification-gates):
  root format, warnings-as-errors compile, strict Credo, umbrella tests and unused
  dependency check. Run Lean if source-cutover or speech state machines change.
- [ ] Obtain independent design/source and adversarial lifecycle review of the
  implementation, resolve concrete findings and record remaining limitations.
- [ ] Finish manual acceptance, documentation, implementation labnotes and index
  synchronization, then commit and push coherent checkpoints as requested.

No new UI approval, Railway deployment, directory republishing, public MCP protocol
upgrade, new STS MCP support or remote-side rollback guarantee belongs to this
milestone. Its creation does not release any existing workflow or delivery hold.

## Specification review — separate from implementation

- [x] Research the current source and pinned dependency, approved MCP lifecycle,
  transport and cancellation contracts, and supervisor shutdown ordering.
- [x] Check prerequisite order and distinguish implemented runtime prerequisites
  from the preceding milestone's outstanding user workflow approval.
- [x] Complete independent GPT-6 Astra xhigh design/adversarial review and record
  resolved findings before finalizing this planning checkpoint. Approved on
  2026-11-08 after adding transport submission fencing, exact renewal-job teardown
  acknowledgement and refresher-incarnation publication fencing. Re-review also
  resolved cleanup authorization: use a current non-renewing snapshot or skip
  DELETE. No remaining planning blocker was found; the 1,000 ms grace budget
  remains a proposed implementation acceptance target, not measured behavior.

No implementation tests or acceptance runs have been executed for this new slice.
Research and review evidence belongs in the
[planning labnote](../20261108-1135-participant-mcp-ownership.md).
