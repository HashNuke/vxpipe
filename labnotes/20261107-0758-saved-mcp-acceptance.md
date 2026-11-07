# Saved MCP admission and cross-node acceptance

Saved web-admission checkpoint in progress, following independent acceptance
review. T7/T8 remain unchecked. Independent-node, telephony, transfer and rendered
authenticated-browser acceptance are separate work. The early-duplicate checkpoint
was committed separately as `7ff87cc2`.

## Evidence before this checkpoint

- Console `test/integration/saved_mcp_runtime_test.exs` persists, publishes and
  prepares PostgreSQL records, builds Gateway options, then manually starts
  IntegrationOwner. Actual HTTP tool execution/revocation is covered; admission
  and the room/model path are bypassed.
- CallEngine `remote_mcp/live_call_test.exs` covers room/model/tool execution with
  injected catalogs/protocols. Console outbound OAuth renewal exercises real HTTP
  but not saved tool execution in an admitted room.
- Persistence OAuth concurrency tests use distinct PostgreSQL sessions in one
  BEAM. Existing peer tests cover identity churn, not shared grant/transport state.

## Runnable acceptance checkpoints

1. Join saved publication/preparation to authenticated browser admission and
   model-selected HTTP tool execution. Reuse Console's saved runtime fixtures,
   `managed_web_hangup_test.exs` real HTTP/session admission and the CallEngine
   live-call scripted model. Assert durable running state and admission release.
2. Cover managed incoming, managed outgoing and legacy incoming entry points;
   tenant isolation, store outage, zero tools, changed/deleted schemas, admitted
   revocation, already-submitted calls and delayed destination transfer activation.
3. Exercise independent BEAM renewal/revocation with separately booted repository
   pools and local runtime configuration, sharing committed synthetic records.

The existing `SavedMCPWireConnectionProvider` and `RemoteMCPWireServer` can retain
actual ExMCP traffic. Before this checkpoint, `CallEngineOptions.build/1` dropped a
trusted `remote_mcp_connection_provider` option. The independently reviewed narrow
server-owned seam is now implemented. Never accept an adapter or loopback policy
from HTTP input or a call spec; transport policy remains unchanged.

## Web-admission implementation and evidence

- Independent design review approved the narrow trusted provider option, while
  requiring real admission, model selection, wire credentials and results,
  authenticated tenant disconnect, same-room failure and observed teardown. An
  API-key principal cannot disconnect MCPs; the fixture now logs in through Console
  with the existing fake identity backend, obtains real CSRF/session state and
  calls the production DELETE route. This does not prove real identity-provider or
  tenant-role isolation.
- Gateway's focused option test failed because CallEngineOptions discarded the
  server-owned connection provider. Forward only that option; preserve saved
  catalog construction and reject protocol overrides. The six boundary tests pass;
  poisoned call/plan values do not supply a provider, and the endpoint rejects an
  unknown JSON provider field before consuming the join token.
- The first complete call test exposed a separate production bug: a saved MCP
  tool without a description publishes and prepares, but agent startup fails with
  invalid configuration. IntegrationCatalog normalizes the optional description
  to an empty string; AgentRuntime requires a nonempty model description. A focused
  red test reproduced that mismatch. The MCP projection now uses `Call <alias>.`
  only for an empty description, preserving the selected schema and public alias.
  All six descriptor tests pass. The approved
  [MCP schema](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/schema/2025-11-25/schema.ts#L1172)
  declares Tool.description optional. Inventing a remote description or loosening
  all host-tool validation was unnecessary.
- The new tagged Console case publishes a saved PostgreSQL record, creates and
  admits a call through Console routes, establishes real local WebRTC, sends RTVI
  input and has a scripted model choose the explicit tool. ExMCP uses the existing
  loopback-only test provider; the server requires both the saved bearer credential
  and custom header. Its distinctive result reaches the model, then final text
  reaches the peer. Disconnecting through the authenticated management route makes
  the next invocation fail in that same running incarnation without a second
  tools/call. No injected catalog, protocol implementation, IntegrationOwner startup
  or test admission bypass is used by this case.
- Fixture corrections during iteration: blocking invocations still produce a
  model acknowledgement before the engine completion observation; use the actual
  exchange and correlate decoded completion IDs/status. Management responses may
  legitimately contain their endpoint, while call/session/model projections must
  not; all exclude credentials, keyring and runtime resolver fields. An empty
  scripted final response is invalid, so the fixture supplies a normal acknowledgement.
- Independent source review found no production issue and requested privacy
  inspection of every consumed WebRTC frame plus a no-extra-wire-request assertion
  after final output and observed room/connection cleanup. Both are implemented;
  all six saved-runtime/managed-web integration tests pass afterward. Independent
  adversarial re-review found no remaining source or test issues; its two wording
  corrections distinguish pre-checkpoint evidence and the new endpoint/protocol
  acceptance from the still-open rendered/browser and broader runtime gates.
  All five root gates pass: format, warnings-as-errors compilation, strict Credo,
  unused-dependency check and 4,986 tests with zero failures (202 excluded, seed
  666644). Independent exact-index review of the nine implementation/evidence paths
  is clean. No UI source, source-cutover or speech state machine changed;
  frontend/Lean lanes are not applicable to this checkpoint. The index is updated
  with this scoped evidence while the milestone remains unchecked.

## Required observable cases

- A foreign tenant ID or platform selection fails before remote startup, while an
  unrelated tenant's valid call remains usable.
- Selected saved tools fail closed on store outage during preparation/startup and
  later credential resolution. Native-only calls remain usable without fallback.
- Empty or unsupported tool catalogs create no phantom tools; selecting a missing
  tool fails. After schema/deletion changes, stale admission fails before tool
  invocation; repreparing preserves explicit selection and current schema pins.
- Revocation during a real room blocks the next tool request without submission,
  retries or browser consent. A held, already-submitted request need not be
  retracted, but cannot be duplicated or authorize subsequent work.
- Revoke/replace a destination connection before delayed transfer activation:
  destination fails without stale credentials and source ownership/restoration is
  correct. Also prove a successful transfer followed by actual MCP execution.
- Inspect actual prepare/create/session responses, model tool definitions, events
  and persisted plans for private configuration. Saved execution must survive a
  directory outage independently of local catalog or status-store failures.

## Independent-node cases

- Node A revokes/replaces while B owns an existing transport: B's next POST, SSE
  reconnect and DELETE re-resolve and refuse stale credentials; local cleanup
  completes. Include an admitted room and delayed transfer.
- A/B race delegated refresh and machine renewal: one token request, no loser
  submission with the old token, and B's existing client uses persisted replacement
  credentials without local notification or recreation.
- Revoke/replace while redemption is held; a late success cannot resurrect the
  old grant or generation.
- Kill the redeeming BEAM after request submission but before persistence. The
  survivor rejects its active claim and eventually requires reconnect after claim
  expiry, with no second redemption or stale-token request.
- One node's exhausted renewal runner/unavailable resolver does not break an
  unrelated connection. Admission capacity is per instance; only durable claims
  provide the cross-instance fence.

Reconstruct adapters inside each peer. Parent-Agent closures or a shared Sandbox
transaction would invalidate this evidence. Assert distinct VM identities and
PostgreSQL backend PIDs. CredentialLeases is local, and disconnect persists
revocation without broadcasting to that registry: test per-request database
revalidation, not an artificial local revocation message.

Useful fixtures: Console `OutboundMCPOAuthCase`, `OutboundMCPOAuthServer` and
`mcp_oauth_renewal_boundary_test.exs`; MCP `runtime_auth_provider_test.exs`; Gateway
`call_admission_adapter_test.exs`, `outgoing_calls_test.exs` and
`phone_transfer_scenario.ex`; CallEngine `agent_transfer_room_test.exs`.
