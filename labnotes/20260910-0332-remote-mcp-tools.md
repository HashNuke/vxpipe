# Remote MCP tools

## 2026-09-10 — milestone start and definition boundary

- Started milestone 11 from `cf9c7e0` on `milestone/remote-mcp-tools`; the worktree
  contained only this new labnote.
- Re-read the approved milestone, call-definition tool grammar, ExMCP boundary, current
  compiler/startup path, background tool runtime, and Jido tool-binding decision before
  changing behavior.
- Rechecked the available Jido interface. Hex still reports Jido AI 2.3.0 as the latest
  release. Upstream `main` was inspected at `e3d0f7671fe1349c00d7f6918eaee95a17c4c33c`;
  `ToolSelection` still accepts only Action modules, `Config.reqllm_tools/1` still derives
  schemas from those modules, and the runner still dispatches through module `run/2`.
  The required public runtime data-tool projection/executor interface therefore remains
  unavailable. No Jido fork, private API, generated module, generic dispatcher, or second
  LLM loop was introduced.
- Red: added a focused definition test for a model-visible `customer_lookup` alias selecting
  the configured `records` MCP integration's `lookup_customer` operation. Compilation first
  failed because `ToolSelection` had no `integration` field. After the parser was green, the
  same test exercised compilation and reproduced an unhandled `FunctionClauseError` for the
  new selection type.
- Green: `ToolSelection` now accepts the closed `host` and `mcp` variants. MCP selections
  require bounded identifier-shaped `integration` and `tool` values; host selections reject
  an integration field. Endpoints, credentials, headers, and arbitrary configuration remain
  rejected as unknown definition fields. Until a scoped catalog is supplied, the compiler
  returns a normal path-specific `:call_definition_resolution_failed` error instead of
  crashing.
- Focused verification: `compiler_test.exs` passes 11 tests. The full call-engine child
  passes 182 tests with zero failures and two tagged integrations excluded; its format check
  also passes.
- The ordinary shared `_build/test` coordination socket was held by an existing long-running
  test-environment BEAM with a saturated accept queue. That process was left untouched. Test
  commands used the uncommitted temporary build path
  `/tmp/vxpipe-remote-mcp-test-build`; no build-path setting was added to source or config.
- After confirmation that no user-started Vxpipe BEAM needed preserving, the blocking
  no-start IEx process was terminated. The focused 11-test suite then passed through the
  normal shared build path, so subsequent work no longer needs the temporary path.
- Root format, warnings-as-errors compilation, and strict Credo checks pass. The root test
  alias reached PostgreSQL setup before running tests and failed because this machine's
  default server requires password authentication while no test database URL/password is
  configured. The database-free owning child suite above remains green; a disposable local
  PostgreSQL run is deferred to the milestone-wide gate.

Next: define the safe resolved MCP tool/catalog records and tenant-first whole-record
resolution, then pin only public schema/generation selectors into the immutable call plan.
Private endpoints and credentials must remain behind the runtime integration owner.

## 2026-09-10 — tenant-scoped protocol clients

- Audited `Vxpipe.MCP.ConnectionKey` before building the tenant integration resolver. Its key
  contained only integration ID and credential generation, which allowed two tenants choosing
  the same labels to reuse one registered ExMCP client and its session.
- Red: a lifecycle test opened the same integration/generation label for `tenant-a` and
  `tenant-b`; both handles returned the same owner/client. A second test showed that missing
  or inconsistent scope options were accepted.
- Green: connection keys now require a closed application or tenant scope. Tenant scope embeds
  the bounded trusted tenant ID in registry equality; application scope rejects a tenant ID,
  tenant scope requires one, and unknown/malformed options fail closed. Reference/conformance
  clients and deterministic fixtures explicitly select application scope.
- Verification: the focused lifecycle file passes 6 tests; the complete MCP child passes
  32 tests with zero failures and three tagged network integrations excluded. No endpoints,
  credentials, headers, tenant IDs, or integration IDs were added to telemetry.

Next: resolve tenant-first whole integration records, reject fallback when a tenant record is
present but invalid/missing the selected operation, and pin only the selected public descriptor
and safe generation identity into the call plan.

## 2026-09-10 — safe compiler-side binding

- Red: a compiler test configured a tenant MCP integration containing an endpoint and an
  authorization sentinel, then selected one remote operation through a different local alias.
  Compilation first failed because no resolved remote-tool record existed.
- Green: the call engine now owns a private configured-integration record, a tenant/application
  integration catalog, and a safe resolved-tool descriptor. The compiler pins tenant scope;
  integration, configuration, credential, and catalog generations; the local alias and remote
  operation; the validated public input schema and description; and the invocation deadline and
  result-size limit. The plan contains neither private client configuration nor its endpoint or
  headers.
- The call engine directly depends on the umbrella MCP adapter because this compilation boundary
  consumes its discovered catalog and JSON Schema validation contract. The MCP adapter remains
  independent of call-domain applications.
- `Vxpipe.MCP.ArgumentValidator.validate_schema/1` reuses the outgoing-argument validator's
  closed JSON Schema build path. Unsupported dialects and external references can therefore be
  rejected before a tool descriptor enters a call plan rather than only at invocation time.
- Focused verification passes: the compiler-side MCP test passes 1 test; the full MCP child
  passes 32 tests with three tagged network integrations excluded; the full call-engine child
  passes 183 tests with two tagged integrations excluded.
- Root verification passes: format, warnings-as-errors compilation, strict Credo, unused
  dependency detection, and the full 397-test umbrella suite with nine tagged integrations
  excluded. The umbrella test used an isolated temporary PostgreSQL instance because the local
  default server requires unavailable password authentication.
- This checkpoint does not claim live MCP execution. Application fallback, tenant whole-record
  rejection, exact generation checkout of private runtime configuration, revocation behavior,
  and the Jido execution bridge remain open.

Next: red-test integration-catalog precedence and exact runtime checkout so an existing call can
use only the private integration generation pinned into its plan and never silently fall back.

## 2026-09-10 — exact private integration checkout

- Red: a focused catalog test proved application fallback worked when no tenant record existed,
  then required private configuration checkout for the exact resolved descriptor. The test
  failed with an undefined `IntegrationCatalog.checkout/2`, while a tenant record that omitted
  the application operation already failed with `:tool_not_allowed` instead of falling back.
- Green: checkout now retrieves from the descriptor's exact application or tenant scope and
  reconstructs the current public descriptor before releasing the private integration record.
  The scope, integration ID, all three generations, allowed operation, schema, description,
  deadline, and result limit must still match. Any missing, replaced, or malformed record returns
  the single closed `:stale_integration` outcome.
- A tenant-scoped descriptor never changes scope during checkout. Removing the tenant record while
  an equivalent application integration exists therefore fails stale rather than exposing the
  application credential. Replacing only the tenant credential generation also fails stale.
- Focused verification passes 2 tests. The complete call-engine child passes 185 tests with zero
  failures and two tagged integrations excluded.
- Root format, warnings-as-errors compilation, strict Credo, unused-dependency detection, and the
  full 399-test umbrella suite pass; nine tagged network integrations are excluded. The root test
  again used an isolated temporary PostgreSQL instance.

Next: introduce a supervised runtime integration owner that checks out this exact private record,
acquires a scoped MCP client, validates outgoing arguments against the pinned schema, and invokes
the pinned remote operation under its absolute deadline and byte limit.

## 2026-09-10 — standalone activation integration owner

- Red: focused tests attempted to start a supervised owner for one local alias backed by a pinned
  tenant tool. Both failed because `RemoteMCP.IntegrationOwner` did not exist. A separate red test
  showed malformed list-shaped private client configuration was accepted as an integration.
- Green: the owner now checks out every MCP binding before opening protocol clients, derives the
  tenant/application-aware `ConnectionKey`, deduplicates equal keys within the activation, and
  retains only safe runtime bindings. Private connection configuration is consumed during client
  open and absent from the owner's inspectable state. Malformed non-keyword configuration now
  fails before startup.
- The owner forces the pinned result limit into both the MCP client's cumulative response budget
  and single buffered-stream-frame budget. Invocation still applies the same limit to the decoded
  result and uses the pinned absolute duration. A test proves schema-invalid arguments make no
  protocol call, while valid arguments use the remote operation rather than its local alias.
- Result normalization preserves valid response maps, maps excessive/malformed results to
  `:invalid_result`, and maps post-submission ambiguity/deadline exhaustion to `:unknown`. Other
  failures are closed `:tool_failed` outcomes. The owner never retries.
- This process is deliberately standalone in this checkpoint. It is not yet a child of the agent
  activation, is not reachable through the current dispatcher/Jido module-only tool surface, and
  does not establish revocation signaling or call-history events.
- Focused owner/configuration tests pass 3 tests. The complete call-engine child passes 188 tests
  with two tagged integrations excluded. Root format, warnings-as-errors compilation, strict
  Credo, unused-dependency detection, and the full 402-test umbrella suite pass with nine tagged
  integrations excluded; the root test used isolated temporary PostgreSQL.
- During this checkpoint, four stale BEAMs left by earlier Vxpipe/ExMCP work were audited by exact
  PID, command, working directory, sockets, and parent. Two old Phoenix VMs, one no-start IEx VM,
  one orphaned infinite-sleep VM, and the old Vxpipe asset watcher were terminated. No unrelated
  tmux panes or Topics Club release processes were touched.

Next: wire the owner beneath the agent-activation supervisor and extend the dispatcher/executor
boundary so remote tools use the existing bounded background lifecycle. The model projection and
Jido continuation remain gated on a supported public runtime data-tool interface.

## 2026-09-10 — bounded remote background execution

- Extracted the deterministic MCP integration fixture from the owner test so activation and
  dispatcher lifecycle tests can use one pinned tenant binding without duplicating private
  setup. The fake protocol can hold a submitted invocation until the test explicitly releases
  its worker; it uses messages rather than timing sleeps.
- Red: configured a dispatcher with the valid activation-local owner and `customer_lookup`
  alias, registered the corresponding tool call, and submitted it. The dispatcher returned
  `{:error, :unknown_tool}` because its executor knew only static host modules.
- Green: `Tool.Executor` now accepts an explicit remote owner and closed alias set. Remote aliases
  are background-only, cannot be duplicated or collide with host names, and are deliberately
  omitted from the static model-definition projection. The dispatcher passes those bindings into
  the existing background worker path; `RemoteMCP.IntegrationOwner` remains the only component
  that selects and invokes the private pinned remote operation.
- A controlled test proves submission returns `running`, the dispatcher answers another request
  while the MCP invocation waits, completion is emitted once under the local alias, and the fake
  protocol receives `lookup_customer` rather than `customer_lookup`. This checkpoint adds no
  retries, implicit variable mutation, second LLM loop, or Jido-private integration.
- Focused executor/dispatcher/owner verification passes 12 tests. The complete call-engine child
  passes 190 tests with zero failures and two tagged integrations excluded.
- Root format, warnings-as-errors compilation, strict Credo, unused-dependency detection, and the
  full umbrella suite pass with all default-lane tests green; nine tagged network integrations
  are excluded. The umbrella suite used an isolated temporary PostgreSQL instance that was
  stopped after the run.

Next: attach the integration owner to the one-for-all agent-activation subtree and prove its
authorization bindings end with that activation. The Jido projection blocker remains separate.

## 2026-09-10 — activation-scoped integration ownership

- Red: started an agent activation with one pinned remote binding and required the scoped client
  to open. No open occurred because `AgentActivationSupervisor` ignored every remote runtime
  option and retained its host-only topology.
- Green: the supervisor now conditionally starts a named `RemoteMCP.IntegrationOwner` before the
  dispatcher and passes only its local alias set plus owner reference to the dispatcher. The owner
  accepts a Registry name while retaining its existing safe runtime state. With no remote tools,
  the original four children and Jido configuration remain unchanged.
- The remote owner is a permanent member of the activation's one-for-all restart domain. A focused
  lifecycle test kills that owner and proves every activation child terminates and is replaced;
  stopping the activation then terminates the replacement owner and removes its Registry entry.
  This ends activation-local authorization bindings, not the separately supervised reusable MCP
  connection cache.
- Focused activation/dispatcher/owner verification passes 10 tests. The complete call-engine
  child passes 191 tests with zero failures and two tagged integrations excluded.
- Root format, warnings-as-errors compilation, strict Credo, unused-dependency detection, and the
  full umbrella suite pass with all default-lane tests green; nine tagged network integrations
  are excluded. The suite used an isolated temporary PostgreSQL instance and left no test server
  running.

Next: the plan startup path still rejects remote bindings because Jido cannot yet project their
exact dynamic names and schemas through a supported public interface. Continue with independent
security/lifecycle checks that do not pretend to lift that blocker.

## 2026-09-10 — fail-closed protocol client loss

- Audited the activation supervisor's restart arguments for private-data exposure. The nested
  `Integration` record's project-owned Inspect implementation excludes `client_config`; an
  activation-level assertion confirms the private sentinel is absent from inspected supervisor
  state as well as owner state.
- Found a separate lifecycle defect: a runtime binding stored the protocol client PID returned at
  checkout, but the separately supervised MCP connection subtree can replace that client. The
  binding owner neither monitored the PID nor refreshed it, so later calls would retain a dead
  handle.
- Red: terminated the fake protocol client after a successful exact checkout and required the
  binding owner to end with `:connection_lost`. The client ended while the owner remained alive.
- Green: the owner now monitors each deduplicated connection client and terminates closed when a
  known monitor reports `:DOWN`. Under agent activation this feeds the already-proven one-for-all
  restart, which performs a fresh exact catalog checkout and connection lookup before serving
  more tool calls. Unknown process messages remain ignored.
- The complete Call Engine child passes 192 tests with two tagged integrations excluded. Root
  formatting, warnings-as-errors compilation, strict Credo, unused-dependency detection, and the
  deterministic full umbrella suite are green.

Next: the remaining milestone blocker is projecting these exact runtime bindings through a
supported Jido-owned loop without generating modules or using private APIs.

## 2026-09-10 — synchronous HTTP response correlation

- Repeated the Vxpipe wire-failure test and found that the test server's wrong-ID response could be
  accepted as the current request's successful result. ExMCP parsed the response ID but discarded
  it in the synchronous HTTP path.
- Added `fix/http-response-correlation` from upstream `56880c6`. Red: both a JSON-RPC result and an
  error carrying another request ID were accepted. Green: ExMCP now accepts either envelope only
  when its ID exactly matches the generated request ID and reports mismatches as non-retryable.
- Published the isolated fix at `8ae7684`, merged it into the fork's `vxp` branch, and
  updated the ordered upstream contribution notes in `docs/ex_mcp-fixes.md`.
- All 12 focused ExMCP result-validation tests, warnings-as-errors compilation, and strict Credo
  passed. The full upstream suite ran 4,622 tests with two unrelated baseline/environment failures:
  a local Claude authentication-method expectation and the modern stdio fixture's child Mix process
  failing to resolve the `:jason` SCM.
- The ExMCP pre-commit hook initially exposed two unformatted files already on upstream `master`.
  Added a mechanical prerequisite branch, `chore/format-acp-tests` at `75d1c6b`, whose commit passed
  the complete hook and 155 focused ACP tests. Merged that prerequisite into every fix branch.
- Running the complete hook against the `vxp` superset then found an unreachable fallback in the
  earlier request-budget fix. Removed it on `fix/request-scoped-sse-budgets` at `261bc90`; its commit
  passed formatting, warnings-as-errors compilation, Credo, Dialyzer, and the skip-tag guard.
  The corrected `vxp` tip is `0bfd0ae`, and all branch tips are published to `HashNuke/ex_mcp`.
- Vxpipe pins that exact integration tip. Its three wire-failure scenarios passed 20 randomized
  repetitions, the MCP child passed 32 tests, and the cumulative SSE reconnection test remained
  green with the loopback-only stream mode made explicit per fixture.
- Root formatting, warnings-as-errors compilation, strict Credo, unused-dependency detection, and
  the complete umbrella suite pass. One initial randomized suite run hit an unrelated persistence
  teardown race; that focused test then passed ten randomized repetitions and the deterministic
  full suite passed all application tests against a disposable PostgreSQL instance.

Next: commit the separately verified protocol-client lifecycle checkpoint.

## 2026-09-10 — credential-generation revocation and activation leases

- Audited the distinction between application-scoped reusable MCP protocol connections and
  activation-local authorization. Stopping an activation already removed its runtime binding but
  did not represent a credential lease, and an explicit credential revocation could neither retire
  the cached session nor prevent the same generation from reopening.
- Red: a connection lifecycle test opened one scoped generation, revoked it, and failed because no
  revocation entry existed. A second owner lifecycle test required one active lease, owner shutdown
  with `:credential_revoked`, lease removal, and rejection before a subsequent private client open;
  it failed because no lease registry existed.
- Green: `Vxpipe.MCP.CredentialLeases` now owns runtime tombstones and monitored holder sets using
  only bounded non-secret connection keys. `Connections.revoke/1` records the tombstone before
  closing the supervised protocol subtree. Connection opening checks before and after open so a
  concurrent revoke cannot leave a newly opened stale session behind.
- Each remote integration owner acquires its deduplicated generation leases before opening clients.
  Revocation notifies every holder and ends it with the internal `:credential_revoked` reason; a
  fresh owner cannot acquire or open the generation. Holder monitors remove leases after ordinary
  activation termination, while the separately supervised connection remains reusable until it is
  explicitly revoked or retired.
- The tombstones are intentionally runtime state, not recoverable credential storage. Application
  restart must rebuild configuration from the durable application/tenant credential source without
  revoked generations. No endpoint, header, credential, tool input, or tenant identity was added to
  telemetry or public call state.
- Focused verification: the connection suite passes 7 tests; the owner/activation lifecycle files
  pass 7 tests under five different seeds; the complete MCP child passes 33 tests with three tagged
  integrations excluded; and the complete Call Engine child passes 193 tests with two tagged
  integrations excluded. Root format, warnings-as-errors compilation, strict Credo, and unused
  dependency checks pass.
- The deterministic full umbrella suite passes 408 tests against disposable PostgreSQL: MCP 33,
  Call Engine 193, Calls 35, Persistence 25, Gateway 66, and Console 56. Nine tagged network
  integrations were excluded, and the disposable server was stopped and removed after the run.

Next: commit and publish this checkpoint. The supported Jido runtime-binding interface remains the
only model-loop blocker.
