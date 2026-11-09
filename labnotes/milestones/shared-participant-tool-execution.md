# Shared tool execution for LLM and speech-to-speech participants

Status: **in progress — 7/20 implementation tasks complete; 0/4 checkpoints complete**.
Requested 2026-11-09. This document is the progress owner for shared native STS
tool/MCP integration. Writing or reviewing it does not implement the feature.

## Runnable outcome

Run an LLM-based participant and a native speech-to-speech participant with the
same selected host, platform, Call Variables and tenant MCP tools. Both validate
and authorize requests, run supervised invocations, observe the selected
conversation mode, consume outcomes and retire resources through common internal
code. Both can read an appointment through MCP, update permitted call variables,
and invoke the existing participant transfer or hangup operation.

A future STS integration supplies the existing semantic session boundary and
passes the common conformance checks. It inherits tool execution and MCP ownership
without its own dispatcher, MCP client, tenant policy or completion policy.

## Prerequisites and design sources

Read the [native STS tools research](../../docs/development/native-sts-tools.md),
[tool execution model](../../docs/tool-execution-model.md),
[participant MCP ownership design](../../docs/development/participant-mcp-ownership.md),
[saved MCP authority](../../docs/development/saved-mcp-runtime.md), and
[speech provider contract](../../docs/speech-provider-contract.md).

Reuse the implemented [ReqLLM runtime](reqllm-agent-runtime.md),
[background tool execution](background-tool-conversation.md),
[Call Variables](call-variables-and-tool-visibility.md),
[remote MCP tools](remote-mcp-tools.md),
[participant-owned MCP sessions](participant-owned-mcp-sessions.md), and
[participant transfer](agent-transfers.md). Existing native allocation, semantic
session and room-tool lifecycle code from [agent STS](agent-speech-to-speech.md)
is the other prerequisite; completion of that entire parent milestone is not.

Saved-connection runtime and credentials are already implemented. The directory's
separate workflow approval, unfinished provider live acceptance, onboarding,
delivery and retention are not prerequisites for this common-code slice.

## Approved scope and parity contract

The user's 2026-11-09 direction is **common internal implementation and the same
tool/MCP integration behavior as LLM-based participants**. This includes both
`blocking` and `non_blocking`; rejecting all native background tools is not
completion of parity.

| Concern | Required common behavior |
| --- | --- |
| Selection and validation | Same immutable selected names, schema checks, variable projections and allowlists. Unknown or unsupported requests fail explicitly; no silent pending calls. |
| Authority | Same tenant, room, participant, activation and policy checks; current MCP credential/grant checks and pinned catalog/tool restrictions. |
| Execution | Same bounded `InvocationRegistry`, `InvocationSupervisor`, `Invocation` and handlers. Every tool runs in an owned worker; model/audio callbacks and GenServers do not execute business operations inline. |
| Conversation mode | `blocking` prevents later business input from overtaking its unconsumed outcome; held caller input is not replayed later. `non_blocking` admits unrelated conversation while preserving knowledge of pending work and subsequent outcome delivery. The engine owns these decisions. |
| Outcomes | Same success, definite failure and uncertain timeout semantics, result bounds and duplicate-submission protection. Delivery retries never repeat the business operation. |
| Effects and lifetime | Same room-authorized hangup/transfer, destination readiness/rollback, interruption survival, activation fencing and teardown. Speech interruption does not cancel admitted work. |
| Privacy and observability | Same permitted lifecycle/usage/archive facts and tool visibility. Credentials, private bindings and raw sensitive payloads never become public tool metadata or diagnostics. |

Parity concerns observable business behavior and authority. Model messages still
follow their transport contracts: the text loop uses its committed running
acknowledgement/private completion; STS uses one final native function result for
a valid exchange. Do not copy the text message sequence into STS, send two native
results, or impersonate caller input to deliver a completion. Terminal authorized
hangup/transfer can end the source without artificial follow-up speech.

The common engine must preserve an outcome when speech interrupts its original
provider association, and deliver it only through a valid semantic completion
path for that same active participant. A retired activation cannot receive it.
If a session cannot express a required operation, fail explicitly at admission or
bounded completion handling and record the contract gap. That is a limitation,
not evidence that full parity passed; no silent downgrade or provider-specific
workaround may be used to check off this milestone.

## Implementation boundary

Own selection, submission, lifecycle, pending state, result consumption and MCP
sessions in `Vxpipe.CallEngine`'s existing tool/activation/room modules. Reuse the
public schema validation and descriptor contracts in `Vxpipe.AgentRuntime` without
adding a reverse dependency on Call Engine. The registry remains the authoritative
invocation store. Text and native controllers translate conversation events to
that shared contract; they do not implement separate tool business rules.

`Speech.STSProvider`, `Speech.Session` and the common channel/capability layer
provide semantic events and result delivery. Provider modules own protocol
encoding, provider call identifiers and socket/session mechanics only. Existing
provider selection and codec differences remain; add no provider-name/model-ID
branches for tool policy, no new model profile table, and no provider-specific
tasks to this milestone.

Existing operations are not interchangeable: `send_tool_result` targets a private
admitted call association; `append_history` accepts already-published caller/agent
text, not arbitrary trusted tool outcomes. The current capability hold can retire
tool associations or close an allocation, so it cannot automatically serve as a
business-tool hold. C3 must prove the required semantics at the common boundary;
these existing APIs alone are not evidence of parity.

Remove superseded implementation paths as their replacements land; this pre-launch
application does not need legacy compatibility branches.

Use existing modules first. Extract a small shared function/module only where
both callers need it. No second LLM/Jido decision loop, generalized workflow
framework, new queue, catalog schema, shared cross-call MCP pool or new protocol
client. No UI changes, new call-spec fields or environment variables are required.
Provider protocol extensions, new models and vendor live-acceptance campaigns
remain outside this milestone. If shared work exposes an adapter deficiency,
record the exact missing semantic operation and affected acceptance check before
expanding scope; do not conceal it with a skip or mark the behavior complete.

## Implementation checkpoints

Each task includes its smallest project-owned failing test, passing implementation
and relevant documentation. Keep checkpoints coherent and usable. Record commands,
results and remaining limitations below when checking items off.

### C1 — Shared descriptor resolution and tool submission (3/5)

- [x] Preserve the compiled private descriptors alongside provider-safe schema
  projections, including injected Call Variables bindings. Test identical selected
  names and authorization for LLM and native participants; private owner handles
  and credentials must not reach provider metadata.
- [x] Route native calls through the existing shared validation, binding
  constructors and registry submission used by the text path. Cover host,
  platform, variables and participant transfer without a parallel STS executor.
- [ ] Remove silent `:deferred` dispatch. Prove unknown names, malformed arguments,
  denied variables, revoked permissions and unsupported operations produce bounded
  rejection before side effects, with no orphaned pending record.
- [x] Apply `PlatformResult` through common room authority. Prove current-time,
  authorized hangup, successful participant transfer and failed transfer recovery;
  stale completions cannot end or transfer a replacement source.
- [ ] Run the same compiled-room contract cases for LLM and native participants,
  preserving existing host/transfer behavior and lifecycle publication. Include
  duplicate requests and partial multi-tool admission without replaying work.

### C2 — Native participant-owned MCP activation (4/5)

- [x] Compose the existing `IntegrationOwner` and session `DynamicSupervisor`
  under the native participant's allocation tree only when MCP tools are selected.
  Reuse common ownership construction where needed; preserve native temporary-tree
  failure semantics and the text path's existing recovery policy.
- [x] Separate schema projection from executable binding readiness. Bind the exact
  owner reference during startup and enforce the original absolute readiness or
  transfer deadline across selected integrations; roll back partial startup.
- [ ] Execute selected MCP tools through the same shared invocation handler,
  tenant catalog snapshot, current authorization/credential checks and result
  normalization as LLM participants. Include aliases, stale pins and saved
  disconnect/revocation races; do not rediscover or refresh catalogs per invocation.
- [x] Prove separate ownership for simultaneous participants/calls and tenant
  isolation; successful transfer retires only the source after commit, while
  destination failure leaves the source usable. Call end/owner loss fences and
  terminates all owned MCP work under the existing cleanup budget.
- [x] Prove catalog maintenance and inbound platform MCP remain independent.
  Reuse controlled MCP fixtures to complete a native room round trip without
  borrowing another call's session or adding maintenance work to audio processing.

### C3 — Common conversation policy and completion lifecycle (0/5)

- [ ] Enforce both conversation modes in common engine code with cross-path tests:
  blocking holds later business input until outcome consumption, non-blocking
  admits unrelated input with pending-work awareness, and a non-blocking completion
  never releases another invocation's blocking hold. Keep native turn transport
  mechanics separate from this policy.
- [ ] Complete native delivery through the semantic session boundary: one final
  result for a valid call, safe same-activation completion after speech interruption,
  and no result/effect delivered to a retired source. Prove provider/result failure
  preserves the outcome or terminates explicitly instead of silently continuing
  with lost work; do not resubmit accepted operations.
- [ ] Settle completion leases through existing acknowledge/release operations
  only on the documented local acceptance or terminal discard boundary. Keep
  consumed-ID retention bounded and prove more than 16 sequential completed tools
  work while concurrent saturation and duplicate protection remain effective.
- [ ] Replace the native hardcoded five-second execution budget with shared
  application-configured invocation bounds, respecting operation and transfer
  deadlines. Prove a legitimate slower MCP/transfer operation, expiry as `unknown`
  where appropriate, cleanup and no automatic side-effect retry.
- [ ] Exercise completion-before-notification, duplicate/late result, interruption,
  session failure and activation replacement races against both participant paths.
  Preserve tool visibility, safe usage/lifecycle facts and terminal effect ordering.

### C4 — Common conformance and acceptance (0/5)

- [ ] Extend existing semantic-session and compiled-room test support into a shared
  tool contract suite. Run it against the LLM path and at least two contrasting
  local STS fixtures (existing ordinary and duplex Morse fixtures where suitable).
  Test common behavior without provider-name conditions or a new test framework.
- [ ] Run the complete receptionist scenario through both paths: selected MCP
  lookup, permitted variable update, continued conversation, participant transfer
  or hangup, and full teardown. Include both conversation modes and controlled
  denied/failed/unknown outcomes, with no skipped parity cases.
- [ ] Record a bounded local concurrency/latency check: invocation work does not
  block common audio/room control, MCP startup observes its deadline, transfer
  overlap remains bounded, and completed/retired calls release capacity. Compare
  equivalent LLM/native fixtures without claiming production vendor percentiles.
- [ ] Update developer integration documentation with the mandatory common tool
  contract and conformance entry point. Reconcile the old STS tool checklist with
  passing evidence; preserve unrelated parent/provider acceptance gates. Record
  any unsupported semantic operation explicitly rather than advertising parity.
- [ ] Pass the five root completion checks and the Lean lane for any changed
  speech/source-cutover state machine; complete focused source/design review and
  synchronize task counts, evidence and the index. Commit and push coherent
  implementation checkpoints under the user's standing instruction.

## Acceptance and evidence

The exit is all 20 tasks with cross-path evidence for both conversation modes,
owned MCP teardown and the runnable receptionist scenario. An adapter-independent
test suite proves common engine behavior; it does not establish a vendor's live
availability. No new hosted/provider-specific work is required to close the common
implementation, but a known semantic incompatibility must remain an explicit
unmet acceptance item rather than being reported as universal support.

Latest interruption checkpoint: common speech interruption no longer cancels
unrelated tool-only turns. Reversible transfer holds preserve same-source tool
associations; stable source/activation and policy interval checks replace transient
speech activity/epoch equality for accepted results. Output-origin invalidation,
queued-effect checks, dirty external/hybrid input fencing and close-for-cutover
remain intact. Ordinary and duplex transfer success/failure now pass, together
with explicit in-flight call/owner-loss teardown. This closes C2's lifetime task.

Genuine provider cancellation retains the accepted worker until its bounded
outcome, then terminates explicitly if delivery is impossible. The inverse race
(completion retained before cancellation) was independently reported and reproduced;
cancellation now asks the existing bridge to redeliver its retained lease, without
resubmitting the business operation. C3 remains incomplete. See the
[interruption labnote](../20261109-0759-native-tool-interruption.md). Full umbrella
verification after the review fix passes: **5,137 tests, 0 failures, 371 excluded**,
seed `380795`; the other four root gates and Lean pass. Final GPT-6 Astra xhigh
source/test/documentation review reports no remaining actionable findings.

Research baseline only: at `f9eefd6a`, 34 focused existing tests passed; a separate
one-test probe reproduced platform dispatch remaining pending. The
[research labnote](../20261109-0258-native-sts-tools.md) records this evidence. None
of it checks off the new integration or parity tasks above.

| Checkpoint | Progress | Implementation evidence |
| --- | --- | --- |
| C1 | 3/5 | Private registry, shared dispatch/validation, variable permissions and scoped platform effects implemented. 112 native/LLM/transfer regressions pass (seed 286573); clean second Astra code review. Revoked/unsupported rejection and shared duplicate/partial-admission acceptance remain. |
| C2 | 4/5 | Shared owner/session construction, exact-PID binding, bounded readiness and independent catalog lifetime implemented. Native aliases, call/tenant isolation, in-flight call/owner-loss cleanup and ordinary/duplex transfer success/failure pass. Full saved-connection races remain open. |
| C3 | 0/5 | Accepted native results acknowledge existing leases, including more than 16 interrupted completions. Speech interruption and reversible transfer hold preserve accepted work. Lost provider associations terminate explicitly after the bounded outcome. Origin-aware stop-hold delivery, final discard, replay and conversation parity acceptance remain open. |
| C4 | 0/5 | Pending |

First C1 checkpoint: native startup retains the existing AgentRuntime `ToolRegistry`
with selected host and permission-derived variable bindings, separately from the
provider's schema-only activation. Red tests reproduced the missing registry;
shared name/schema validation and private projection now pass. This does not yet
route native execution through that registry. All five root gates pass with
5,095 tests, zero failures and 371 exclusions (seed `293285`); independent
GPT-6 Astra xhigh source and documentation reviews found no actionable issues. See the
[implementation labnote](../20261109-0536-shared-tool-dispatch.md).

Second C1 checkpoint: native calls resolve the exact activation's retained registry
and submit its binding directly to the common invocation workers. Platform aliases,
public hangup results and queued effect authorization pass, as do variable read,
update and denied selection. Existing successful/failed native transfer and LLM
platform/transfer cases remain green. Identity and duplex mute/overlap fixtures now
exercise real workers. Expanded regression lane: **112 tests, 0 failures**, seed
`286573`. Obsolete direct completion/timeout handlers and unused wrappers are
removed; two failing real-room tests proved they could prematurely settle owned
work. Format, compilation, strict Credo and unused-dependency checks pass. The
full umbrella run for that checkpoint was interrupted; the ownership checkpoint
below supplies the subsequent complete passing run. Full acceptance and
C1's revoked/unsupported rejection and shared duplicate/partial-admission suite remain open.

Native MCP ownership checkpoint: both participant paths compose the same owner and
session components and execute through the same invocation handler. Native startup
projects schema metadata before allocation, then binds its exact owner PID; input
waits for both speech-provider and MCP readiness. Gated initialization leaves room
and capability control responsive. Initial startup retains its absolute budget;
recovery uses the application readiness timeout. Failed/late readiness terminates
through existing room failure handling. Crash logs redact deferred private options.
Catalog publication remains outside the call tree, and the protocol fixture
rejects discovery during native execution. No inbound platform MCP or maintenance
job implementation changed.

Focused native/text startup, owner, budget and transfer lane: **116 tests, 0
failures, 8 excluded**, seed `961998`. The native room cases cover aliases,
notification ordering, cancellation, exact ownership, tenant isolation, credential
revocation and duplex transfer. The same transfer experiment with ordinary Morse
reproduced the existing interruption/completion-association gap: source retirement
or failed-tool delivery could be lost at that checkpoint. The subsequent
interruption checkpoint above fixes ordinary transfer lifetime and closes C2's
lifetime task; the broader C3 completion contract remains open. The saved-connection
end-to-end race task also remains open; direct credential-lease revocation alone
does not complete it.
See the [ownership checkpoint labnote](../20261109-0621-shared-native-mcp.md).
All five root checks pass for this checkpoint: **5,129 tests, 0 failures, 371
excluded**, seed `401568`, plus formatting, compilation, strict Credo and unused
dependencies. Lean build/oracle/replay passes. Independent GPT-6 Astra xhigh
source/test/documentation review found no actionable issues and approved the
6/20 count. These gates validate the checkpoint; C4 still requires the remaining
behavior and conformance work before final milestone acceptance.

The next settlement checkpoint uses the existing registry acknowledgement after
local native result acceptance or an authorized terminal effect. A 20-request
compiled-room test reproduces and fixes lifetime saturation; provider rejection
now terminates explicitly rather than publishing successful delivery. Duplicate
completion messages and invalid lease acknowledgements remain harmless. A review
test reproduced consumption without delivery when speech activity changed; the
association and lease now remain retained when scope cannot be resolved. This
is partial C3 progress, not completion of interrupted delivery, terminal discard
or replay acceptance. No additional checklist task is checked off.
The final focused native/common-registry lane passes **115 tests, 0 failures**,
seed `915194`; quick root gates and Lean pass. Clean Astra re-review confirms the
scope-retention fix. The preceding 5,129-test root result belongs to the ownership
checkpoint; final integrated validation is still required. See the
[settlement labnote](../20261109-0723-shared-tool-settlement.md).

## Design review and scope reconciliation

Planning review is separate from implementation progress. This milestone takes
over the tool-binding/coordination portion of
[completion-plan Package 1](agent-sts-completion-plan.md#package-1-sts-tool-bindings)
and the open shared lifecycle work in [STS tool ownership](sts-tool-lifecycle.md).
The original parent remains responsible for its other speech/transport features.
Historical duplicated boxes are not extra work or evidence of completion.

The new common-code/parity direction supersedes the earlier recommendation to
finish by rejecting every native non-blocking binding and to add per-model policy
tables. The one-final-native-result constraint remains. Provider-specific findings
in the research are protocol evidence, not implementation tasks or new dependencies.
Existing provider deficiencies may constrain delivery of parity and must be
reported accurately; the milestone does not presume protocols are identical.

Local design/dependency review: shared authority and execution precede MCP startup;
both precede integrated completion/conversation acceptance. Completed ownership
work is reused without reopening it. No unfinished provider milestone is made a
prerequisite. Independent specification review approved the common-code boundary,
both conversation modes, native result semantics, ownership and dependency order.
It identified the linked speech-provider contract's obsolete running/private
continuation requirement; that source was corrected and re-reviewed. The current
semantic API limits are now explicit above. No actionable findings remain.
That review was specification approval only. Subsequent runtime progress and
verification are tracked in the task list and evidence above.
