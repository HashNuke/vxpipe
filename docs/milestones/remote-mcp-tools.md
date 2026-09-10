# Remote MCP tools in a live call

Status: implementation in progress. Protocol, configuration, catalog, binding, security and
activation foundations are implemented. The completed
[ReqLLM agent runtime](reqllm-agent-runtime.md) now projects exact remote descriptors, delegates
their private handlers, and runs the deterministic non-blocking live-room conversation. Remaining
acceptance covers mixed tools, visibility/archive evidence, failure matrix, and churn.
Prerequisites: [Asynchronous history](asynchronous-call-history.md), including its
background-tool and tenant admission prerequisites; [MCP client integration and
conformance](mcp-client-library.md); [ReqLLM agent runtime](reqllm-agent-runtime.md).
See the [runtime/tool-binding decision](../reqllm-agent-runtime.md).
Sources: [Configured integrations](../../labnotes/20260905-0405-call-definition-design.md#applicationtenant-mcp-integrations-and-agent-enablement); [remote profile](../../labnotes/20260905-0405-call-definition-design.md#initial-remote-protocol-and-input-validation--approved-r22r23); [R22–R26/R49](../call-definition-gap-review.md).

## Runnable outcome

A call's reception agent invokes one tenant-configured remote tool through an explicitly
non-blocking binding, continues speaking while it runs, receives the result, and explicitly
updates permitted variables. Another agent/tenant cannot use that binding or its credentials.

## Specification

- Application/tenant integrations are configured infrastructure; each agent enables named operations through its unified local-key tools map. Tenant override replaces the whole integration record, not a deep merge. Calls carry no per-call MCP endpoint/credential override. Resolve tenant from trusted principal and pin bindings/catalog/schema/config generations in the call plan.
- Use the selected ExMCP integration with MCP `2025-11-25` Streamable HTTP JSON/SSE responses, initialization/capability negotiation and scoped session handling. The earlier `2026-07-28` target is superseded. Do not advertise unsupported sampling/elicitation/tasks or silently negotiate an untested profile.
- Consume the separately verified thin `vxpipe_mcp` adapter around `ex_mcp`. An engine-side
  tool bridge exposes enabled remote tools through the established
  `Vxpipe.AgentRuntime` data-tool and private-executor contracts.
  The integration owner supplies resolved configuration, private credentials, deadlines,
  pinned schemas and network policy; it owns tenant selection, grants, catalog scoping,
  call/agent lifecycle and result history. Neither gateway nor room processes implement
  another MCP parser. ExMCP owns its protocol/client integration; the internal adapter has
  no dependency on the agent runtime or those domain applications. Do not add a second MCP
  client or an agent-framework bridge to manufacture model-tool definitions.
- Expose each enabled local binding with its pinned remote schema while keeping endpoint,
  credential and remote-operation selection outside model arguments. No externally driven
  module/atom growth, private proxy APIs or generic model-visible endpoint/tool dispatcher.
  Project the descriptor through the ReqLLM runtime while resolving and executing only its
  paired private binding inside the current activation.
- Keep platform and runtime remote bindings in the same agent-runtime loop. Prove two
  local aliases can share a handler while retaining independent schemas and private grants.
  This lifts the historical Jido Action-name restriction without changing the definition
  contract. Do not introduce a second production model/tool loop inside Call Engine or MCP.
- Auth variants are none, bearer, or validated custom headers; transport-owned headers cannot be overridden. Secrets stay in the private integration boundary, recoverable through configured secret storage, never tool arguments/plan projections. Authorization-scoped discovery/cache/health/concurrency state must not cross tenant/integration/credential generation.
- Follow ExMCP and MCP SDK security guidance at Vxpipe's actual outbound boundary:
  trusted configured endpoints, verified HTTPS, address-at-connect/rebinding defenses, no
  automatic redirects/credential forwarding. Private destinations require explicit host
  permission, not tenant bypass. Revoked/invalid tenant credentials never fall back silently
  to application credentials.
- Use a real JSON Schema 2020-12 validator for actual outgoing tool arguments against pinned inputSchema, including required values; reject unsupported dialect/features/bindings before exposure and never fetch external refs automatically. Variable partial-population rules do not weaken MCP schemas.
- Enforce a configurable 1 MiB (1,048,576-byte) cumulative decoded/decompressed response limit incrementally, including streamed responses and resumption across HTTP responses. Preserve the invocation's absolute deadline and byte budget across progress/reconnects. Stop excessive receipt without asserting remote action failure or full archival. Accepted permitted responses archive fully; if too large for model context, return explicit projection omission, not chopped JSON or automatic summarization/retry.
- Reuse the application-level submit-only [tool execution contract](../tool-execution-model.md).
  Every remote call runs in an independently supervised worker; its local binding blocks later
  caller conversation unless it explicitly selects `non_blocking`. Results/linked resources
  are untrusted; preserve observed outcomes/descriptors, do not auto-fetch attachments or
  auto-map variables. Submitted timeout is unknown unless definitive evidence exists; no
  executor retries.

## Implementation checklist

- [x] Red-test a controlled remote MCP fixture for discovery, valid tool invocation, slow result, schema failure, auth and response-size limits.
- [ ] Prove the `Vxpipe.AgentRuntime` data-tool/private-binding interface in a deterministic
  mixed platform/remote run without a second model loop.
- [x] Wire the verified ExMCP adapter through the integration owner; preserve its pinned
  profile/conformance evidence and enforce dependency direction.
- [x] Implement private scoped integration resolution/cache/discovery and data-backed binding
  validation without unbounded external atom/module creation.
- [ ] Connect tools/call to background workers, complete private history, and safe model/client projections.
- [x] Test security at the effective network client, not only a configured URL string; isolate real network interoperability tests.

## Acceptance and failure checks

- [ ] A deterministic agent-runtime run alternates a platform tool and remote tool over
  successive model rounds, then answers; `vxpipe_agent_runtime`, not Call Engine or MCP,
  owns model continuation.
- [ ] Model-visible tools preserve exact local names/pinned schemas, including two aliases
  sharing one handler. Unknown bindings fail before execution; endpoint selectors and
  credentials never enter the model schema/arguments or public events.
- [ ] Tenant/app precedence is whole-record; bad/revoked tenant credentials do not fall back or leak to another endpoint/cache.
- [ ] Reject unknown/unauthorized tools, argument schema violations, unsafe redirects/private addresses/rebinding, external schema refs and unsupported interactions before unauthorized work.
- [ ] At/exceed the 1 MiB boundary with compressed and many-chunk bodies; no cap reset per chunk or full-body buffering before checking.
- [ ] Validate definite non-submission vs unknown submitted timeout; exactly one invocation, no automatic retries or implicit variables updates.
- [ ] Run while speaking; preserve live context and permitted archived result/descriptors; hidden client events remain hidden.
- [ ] Refresh/change a discovery catalog: existing calls retain pinned enabled schemas;
  new calls may resolve the new catalog, and unresolved enabled bindings fail preparation.
- [x] Revocation fails closed instead of reusing stale authorization; private credential leases
  redact process status/crash output and are released/invalidated at room-incarnation end.
- [ ] Library invocation receives only scoped resolved inputs; domain authorization/history
  are tested here, protocol behavior in the library. Real integration uses that same client.
- [ ] Reconfigure unique tenant endpoint/tool/schema catalogs repeatedly: the live binding
  path does not grow atoms/modules with external churn, expose endpoint selectors to the
  model, or let a binding escape its pinned call plan.

## Manual verification

1. Configure a synthetic remote service at tenant scope and enable one tool for reception only.
2. Create/join a call, invoke it, converse during its controlled delay, then ask the agent to save the result using a variable tool.
3. Repeat with another tenant, invalid args, timeout, and oversized response; inspect safe outcomes and permitted history.
4. Run the tagged HTTPS/streaming interoperability lane before claiming compatibility with a real configured MCP.

## Scope boundaries

No local/stdio MCP, per-call credentials, automatic retry/idempotency, explicit cancellation, late webhook reconciliation, OAuth onboarding, result/document fetching, or server-requested sampling/elicitation. Existing issue links describe deferred work, not dependencies.

## Completion and evidence

- [ ] Demonstrate the runnable outcome and every acceptance/failure check above.
- [ ] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [ ] Update this milestone, the index checkbox, relevant architecture/user docs, and
  implementation labnote with actual test/browser/integration evidence in the implementation commit.

Milestone completion evidence is incomplete. Do not mark this slice complete because its
definition boundary has started or its specification has been reviewed.

### Implementation progress

- [x] The call-definition parser accepts an MCP selection as a model-visible local alias
  containing only `integration` and remote `tool` identifiers. It rejects configuration and
  credentials through the closed input grammar. An unresolved MCP selection now fails at its
  exact participant/tool path instead of raising. Focused compiler tests pass 11/11 and the
  call-engine child passes 182 tests with two tagged integrations excluded. This establishes
  the authoring boundary only; scoped catalog resolution and live execution remain unchecked.
- [x] ExMCP connection keys require an explicit application or tenant scope. Tenant identity
  participates in registry/cache identity, and a deterministic lifecycle test proves two
  tenants with equal integration and credential-generation labels receive distinct supervised
  client subtrees. The MCP child passes 32 tests with three tagged integrations excluded.
- [x] The compiler resolves an enabled tenant integration to a safe immutable tool descriptor.
  The plan pins the selected scope, integration/configuration/credential/catalog generations,
  local alias, remote operation, validated public input schema, deadline, and result limit;
  private connection configuration remains in the integration catalog. The focused compiler
  test proves an endpoint and authorization sentinel do not appear in the plan.
- [x] Tenant/application resolution uses whole-record precedence: an application integration is
  considered only when the tenant has no record with that integration ID. Runtime checkout
  returns private configuration only for the exact scope and complete descriptor/generation
  identity pinned in the plan. Missing/replaced tenant records fail stale without application
  fallback. The focused catalog test passes 2 tests and the call-engine child passes 185 tests
  with two tagged integrations excluded. Runtime ownership and invocation remain unchecked.
- [x] Resolve and pin an authorized tenant/application catalog entry into the immutable plan.
- [x] A standalone supervised integration owner converts exact checked-out records into safe
  activation-local runtime bindings. It deduplicates scoped clients by connection key, applies
  the pinned cumulative response/stream-frame limit at client open, validates actual arguments,
  invokes only the pinned remote operation under its deadline/result limit, and normalizes
  excessive or ambiguous outcomes without retry. Its inspectable state retains no private client
  configuration. Focused tests pass 3 tests and the call-engine child passes 188 tests with two
  tagged integrations excluded. This first checkpoint did not wire the owner into agent
  activation or agent runtime.
- [x] The tool executor and dispatcher accept an explicit activation-local remote owner plus a
  closed set of local aliases. Every remote alias is background-only, participates in the same
  admission/timeout/completion lifecycle as a background host tool, and cannot collide with a
  host tool. A controlled invocation proves the dispatcher remains responsive while the remote
  request waits, completion retains the local alias, and only the pinned remote operation reaches
  the protocol client. This first dispatcher checkpoint did not attach the runtime to the
  agent-activation supervisor or expose it through the runtime's model-visible definitions.
- [x] Agent activation now conditionally starts a named remote integration owner before its tool
  dispatcher. The owner and dispatcher participate in the existing one-for-all restart domain;
  a controlled owner crash replaces the entire activation, and stopping the activation removes
  its authorization bindings. Host-only activations retain the original four-child topology.
  The activation owns only its checked-out bindings; the application-scoped connection cache and
  any reusable protocol client remain separately supervised.
- [x] The integration owner monitors every deduplicated protocol client. Losing a client fails the
  owner closed with `:connection_lost`, so its one-for-all activation rebuilds rather than retaining
  a dead handle. Both owner and activation-supervisor inspection redact private client
  configuration nested in their runtime/startup state.
- [x] The MCP connection cache now tombstones an explicitly revoked scoped credential generation,
  closes its reusable protocol subtree, and refuses to reopen that generation. Every activation
  acquires a monitored non-secret lease before opening clients; revocation ends current binding
  owners with `:credential_revoked`, while normal activation shutdown releases its leases without
  closing a connection shared by another authorized activation. Focused lifecycle tests prove
  existing and subsequent use fail closed, and the configured credential source—not this runtime
  lease registry—remains responsible for durable revocation across application restarts.
- [x] Configured infrastructure and discovered snapshots now have a narrow engine-owned boundary.
  A private `ConfiguredIntegration` value validates exact application/tenant scope, generations,
  allowed operations and bounded discovery/invocation policy without exposing client settings in
  inspection. `CatalogLoader` opens the same scoped reusable Vxpipe MCP connection used later by
  activations, enforces the result cap before discovery, and publishes an `Integration` only after
  complete bounded discovery proves every configured allowed operation exists. Focused tests pass
  3/3; the Call Engine suite passes 196 tests and the deterministic umbrella suite passes 411,
  with nine tagged network integrations excluded. Catalog TTL/refresh orchestration and the
  configuration source remain pending; this does not claim the broader
  resolution/cache/discovery checklist or model exposure complete.
- [x] A separately supervised `CatalogStore` owns only atomic publication of the current immutable
  application/tenant snapshot; catalog loading stays outside its callbacks. A controlled
  replacement test starts an activation-local owner from generation 1, publishes generation 2
  with a different schema and client, and proves the active owner still validates/invokes its
  original pinned binding while subsequent resolution sees generation 2. Credential revocation
  remains the explicit mechanism that invalidates an active generation. Automatic TTL scheduling
  and configuration-source integration remain pending. The Call Engine suite passes 197 tests;
  the deterministic umbrella suite passes 412, with nine tagged network integrations excluded.
- [x] Calls definition validation and prepared-call compilation now use a narrow Call Engine
  facade that resolves the current catalog snapshot internally. Calls supplies only its ordinary
  public registries and an optional opaque store reference; it receives only the safe immutable
  plan, never the private integration catalog or connection settings. Both Calls workflows share
  one `CallPlanCompiler` responsibility instead of duplicating configuration lookup. The focused
  engine contract passes 1 test, the affected Calls workflows pass 14 tests, the Call Engine
  suite passes 197 tests, the Calls suite passes 35 tests, and the deterministic umbrella suite
  passes 412 tests with nine tagged integrations excluded. Live room startup, configuration
  source/refresh orchestration, and agent-runtime projection remain pending.
- [x] A one-shot `CatalogRefresh` operation now validates a bounded set of scoped integration
  identities, discovers them with explicitly bounded concurrency, assembles one complete
  application/tenant snapshot, and publishes it atomically. A controlled failure after loading a
  replacement proves no partial catalog becomes visible and the prior snapshot remains current.
  Duplicate identities and concurrency beyond the configured bound fail before discovery.
  Focused verification passes 3 tests and the Call Engine suite passes 200 tests with two tagged
  integrations excluded; the deterministic umbrella suite passes 415 tests with nine tagged
  integrations excluded. Configuration retrieval, periodic scheduling, TTL expiry, and generation
  removal/revocation remain separate pending work; this checkpoint does not claim automatic
  production refresh.
- [x] Remote integration configuration now enters through a small `ConfigurationSource`
  behaviour. Its first adapter reads raw records from the
  `:vxpipe_call_engine, :remote_mcp_integrations` OTP application setting and converts the full
  set into validated, inspection-redacted `ConfiguredIntegration` values at runtime. A missing
  setting is an empty source; one invalid record rejects the whole source. Focused verification
  passes 3 tests, the Call Engine suite passes 203 tests with two tagged integrations excluded,
  and the deterministic umbrella suite passes 418 tests with nine tagged integrations excluded.
  The adapter deliberately does not discover or publish tools, schedule refresh, own TTL expiry,
  or define a future tenant/vault persistence implementation.
- [x] An optional engine-supervised `CatalogRefresher` now runs configuration/discovery cycles in
  an explicitly named task supervisor, starts immediately, repeats at a bounded interval, and
  times out blocked cycles without blocking catalog reads or its own status callback. Temporary
  failures retain the last complete snapshot until `stale_after_ms`; expiry atomically publishes
  an empty catalog, and a later success recovers. A successful empty source removes configured
  integrations immediately. State inspection omits source/refresh options, and public status keeps
  only normalized outcomes. Focused lifecycle/application verification passes 6 tests across
  three seeds; the Call Engine suite passes 208 tests with two tagged integrations excluded. The
  deterministic umbrella suite passes all 423 default-lane tests with one test case scheduled at a
  time and nine tagged network integrations excluded. Snapshot replacement/removal still does not
  revoke an active pinned credential generation.
- [x] An isolated-BEAM churn probe now runs 100 unique tenant, endpoint, integration, generation,
  remote-operation, local-alias, and schema-field identities through configuration, discovery,
  catalog resolution, exact activation checkout, argument validation, and invocation. After an
  equal warm-up it measures zero atom growth, zero module growth, and no external identity
  convertible through `String.to_existing_atom/1`. The private endpoint is absent from inspected
  configuration/catalog/plan/binding/owner values. Root formatting, warnings-as-errors, strict
  Credo, and dependency checks pass; the serialized umbrella suite passes all 424 default-lane
  tests with nine tagged integrations excluded. This proves the engine-owned data path through
  runtime execution; the separate agent-runtime model-projection acceptance check remains pending.
- [x] A controlled loopback server now proves `CatalogLoader` and `IntegrationOwner` use the real
  `vxpipe_mcp`/ExMCP client for authenticated discovery and exact pinned invocation. Five focused
  engine tests cover success, authentication rejection, schema rejection before submission,
  submitted slow/oversized outcomes with exactly one request, and redirect refusal without
  forwarding credentials. A separate MCP-child wire test injects a mixed loopback/public DNS
  answer and proves the effective client rejects it before connecting. Plaintext remains available
  only through a test-only provider. The MCP child passes 34 tests and the Call Engine child passes
  214 tests, with their tagged integrations excluded. Root formatting, warnings-as-errors, strict
  Credo, and dependency gates pass; the serialized umbrella suite passes all 430 default-lane tests
  with nine tagged integrations excluded. This does not expose remote bindings to a model.
- [x] Remote client authentication now has one closed parser supporting absent/none, bearer, and
  bounded custom-header variants. Raw transport headers, malformed bearer/header values,
  case-insensitive duplicates, and transport-owned header overrides fail before client startup.
  The OTP configuration source validates the complete production HTTPS/client profile and rejects
  the whole source when any endpoint or authentication setting is invalid, while private values
  remain inside inspection-redacted integration records. Focused verification passes all 7 MCP
  authentication/client-profile tests and all 4 application-source tests; the MCP child passes 37
  tests and the Call Engine child passes 215 tests, with their tagged integrations excluded. Root
  formatting, warnings-as-errors, strict Credo over 322 source files, and unused-dependency gates
  pass. The serialized umbrella suite passes all 434 default-lane tests with nine tagged
  integrations excluded. This checkpoint does not change the outstanding agent-runtime
  model-tool projection boundary.
- [x] Agent Runtime descriptor compilation now accepts a resolved MCP tool only when it has an
  opaque activation-owned remote handler. The model receives the exact local alias, description,
  and pinned schema; it receives no remote operation, endpoint, credential, or owner reference.
  `AgentActivationSupervisor` conditionally owns the remote integration process in the same
  one-for-all generation as its Session, invocation registry, and invocation supervisor. A real
  remote binding executes through the common supervised invocation worker and preserves a bounded
  remote result. Red evidence first found the missing descriptor API, then the absent activation
  child; focused checks pass 13 tests and the complete Call Engine suite passes 225 tests with one
  tagged integration exclusion. All 495 default umbrella tests pass with ten tagged integration
  exclusions. Plan/room startup still needs to supply the pinned catalog before this is a live-call
  path.
- [x] Expose and execute the pinned runtime binding through the adopted
  `Vxpipe.AgentRuntime` loop.

- [x] Public call startup now obtains one authoritative integration snapshot from its configured
  catalog store, validates each remote generation during plan startup, and passes it privately into
  the activation. A new full-room test compiles a tenant MCP alias, starts and attaches a caller,
  submits the exact remote operation in the common worker, completes the running acknowledgement,
  admits an unrelated caller turn because the binding is explicitly `non_blocking`, preserves the
  same pending invocation in that request, and consumes the terminal result through one private
  continuation. A second test replaces the catalog after plan compilation and proves startup fails
  at the exact participant/tool path without creating a room or falling back. The first red run
  failed at the former host-only plan gate; the stale-generation test first received an unrelated
  model-profile error until startup preserved the tool-specific failure. The focused live tests and
  complete 227-test Call Engine suite pass with one tagged integration exclusion. Root formatting,
  warnings-as-errors compilation, strict Credo, and unused-dependency checks pass. A deterministic
  umbrella run against isolated PostgreSQL 18 passes all 497 default-lane tests with ten tagged
  integration exclusions.

## Specification review

Reviewed independently by milestone_review_a on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Added catalog/schema pinning, unresolved binding failure, revoked authorization and private lease redaction/lifetime tests; re-review approved.
The subsequent internal-library prerequisite and scoped-input/domain-ownership boundary
also passed milestone_review_a's focused follow-up review. The supported protocol revision
and non-resetting invocation bounds remain approved. The later released-package probe
found that Jido owns repeated rounds but rejects data-tool descriptors and loses aliases
in model projection. The 2026-09-10 runtime decision moved that generic loop work into its
own intermediate ReqLLM milestone; this slice consumes the resulting interface. The ExMCP
library checkpoint remains independent. No protocol/security or model-schema requirement
was waived.
The implementation evidence above is current; milestone-wide completion and remaining runtime
checks remain unchecked.
