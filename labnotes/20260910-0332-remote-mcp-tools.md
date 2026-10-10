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
  updated the ordered upstream contribution notes in `labnotes/20260910-0059-exmcp-fork-fixes.md`.
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

## 2026-09-10 — scoped catalog loading

- Audited the live-MCP path after the credential-lease checkpoint. The compiler could consume a
  manually assembled `IntegrationCatalog`, but no engine-owned boundary could turn private scoped
  infrastructure configuration into a complete discovered integration snapshot.
- Kept responsibilities separate: `ConfiguredIntegration` validates one application/tenant
  connection identity, generations, allowed operation names, private connection settings, and
  discovery/invocation limits. `CatalogLoader` alone opens the exact scoped connection, performs
  bounded discovery, and constructs the existing private `Integration` snapshot. Neither module
  compiles calls, owns an activation, or projects tools to Jido.
- Red: the focused loader tests failed with undefined `ConfiguredIntegration.new/1` and
  `CatalogLoader.load/2` calls.
- Green: the loader uses the shared Vxpipe MCP connection boundary, forces the configured result
  limit into response and streaming-frame receipt before `tools/list`, preserves the configured
  discovery deadline/page/decoded-byte bounds, and rejects a snapshot when any configured allowed
  operation is absent. Private client settings are omitted from inspection of both configuration
  and the resulting integration record.
- Focused verification passes 3 tests. The combined loader/catalog/runtime-owner check passes 9
  tests. The child-level Credo task is intentionally unavailable; the repository owns Credo at the
  umbrella root, where the strict gate is run for the checkpoint.
- The complete Call Engine child passes 196 tests with two tagged integrations excluded. Root
  formatting, warnings-as-errors compilation, strict Credo over 311 files, and unused-dependency
  detection pass. The deterministic umbrella run against isolated temporary PostgreSQL passes all
  411 default-lane tests: MCP 33, Call Engine 196, Calls 35, Persistence 25, Gateway 66, and Console
  56; nine tagged network integrations are excluded.
- The first umbrella attempt observed the pre-existing definition-driven archive case missing one
  expected `tool_call_started` fact under full-suite load. The exact unchanged case then passed 20
  consecutive deterministic isolated runs, and the complete deterministic umbrella rerun passed.
  No archive implementation or test was changed in this checkpoint.
- This is the load boundary, not catalog TTL/refresh orchestration or the application/tenant
  configuration source. It does not lift the Jido runtime data-tool blocker or make live MCP calls
  runnable from `PlanStartup`.

Next: add bounded current-snapshot publication/refresh around this loader and prove an active
activation retains its pinned schema while a later compilation sees the replacement snapshot.
The supported Jido runtime-tool interface remains required before the vertical outcome can run.

## 2026-09-10 — atomic catalog snapshot publication

- Kept remote discovery out of a GenServer callback. `RemoteMCP.CatalogStore` has one
  responsibility: return the current immutable `IntegrationCatalog` or atomically replace it
  after an external configuration/discovery owner has prepared a complete snapshot.
- Red: a controlled test could not start the absent `CatalogStore` child.
- Green: the Call Engine application now supervises one explicitly named store initialized with an
  empty valid catalog. The public store also supports unnamed supervised instances for isolated
  tests and embedded composition.
- The replacement test starts an activation-local integration owner from catalog generation 1,
  publishes generation 2 with a different input schema and private protocol client, and resolves
  the new descriptor from the current snapshot. The first owner continues to validate against and
  invoke only generation 1; generation 2's client receives no call. Checking the old descriptor
  against the replacement snapshot fails as `:stale_integration`.
- Publication alone never revokes credentials or mutates active owners. The separately implemented
  credential-generation revocation path remains the fail-closed invalidation mechanism.
- This checkpoint does not schedule TTL refreshes, retrieve application/tenant configuration, or
  wire the store into Calls preparation and room startup. It does not lift the Jido runtime-tool
  blocker.
- Focused verification passes 1 test, and the complete Call Engine child passes 197 tests with two
  tagged integrations excluded. Root format, warnings-as-errors compilation, strict Credo over
  312 files, and unused-dependency detection pass. The ordinary root test command again cannot
  create its database because the machine's default PostgreSQL listener requires an unavailable
  password; the deterministic umbrella run against isolated temporary PostgreSQL passes all 412
  default-lane tests with nine tagged network integrations excluded.

Next: connect catalog lookup to the Calls preparation and live room-start boundaries without
giving Calls or Gateway access to private MCP configuration.

## 2026-09-10 — private catalog resolution at the compilation boundary

- Audited the definition-save and call-preparation paths after catalog publication. Both Calls
  workflows invoked the pure engine compiler directly and could only resolve MCP bindings if a
  private `IntegrationCatalog` was placed in a registries map visible to Calls.
- Red: the remote definition compiler test removed `mcp_integrations` from the supplied public
  registries, provided only a supervised catalog-store reference, and called the intended Call
  Engine facade. Compilation failed because that facade did not exist.
- Green: `Vxpipe.CallEngine.compile_definition/4` now reads the current immutable snapshot and
  injects it within the engine call frame before delegating to the pure compiler. Its return is
  still only the safe `ResolvedCallPlan`; a missing store becomes a structured definition-
  resolution failure. The existing private endpoint/header sentinel remains absent from plan
  inspection.
- `Vxpipe.Calls.CallPlanCompiler` now owns the Calls-side registry lookup and delegation used by
  both `Definitions` and `Admissions`. It can pass an opaque store server reference for embedding
  or tests but has no dependency on MCP types and never receives the snapshot or connection
  configuration. This also removes duplicated registry-resolution functions from those workflows.
- Focused verification passes: the engine boundary test passes 1 test and the affected Calls
  definition/admission files pass 14 tests. The complete Call Engine child passes 197 tests with
  two tagged integrations excluded; the complete Calls child passes 35 tests.
- Root formatting, warnings-as-errors compilation, strict Credo over 313 files, and unused-
  dependency detection pass. The deterministic umbrella suite passes all 412 default-lane tests
  against disposable PostgreSQL: MCP 33, Call Engine 197, Calls 35, Persistence 25, Gateway 66,
  and Console 56; nine tagged network integrations are excluded. The temporary database was
  stopped and removed after the run.
- This checkpoint does not make MCP-enabled rooms start. Live startup must reacquire exact private
  bindings inside Call Engine, and `PlanStartup` must continue rejecting them until Jido can
  preserve their runtime aliases and schemas through a supported public interface.

Next: inspect and connect the room-start private-binding acquisition boundary without putting the
catalog or credentials in Calls, Gateway, the prepared-call record, or the safe plan.

## 2026-09-10 — all-or-nothing catalog refresh operation

- The live-start audit confirmed that acquiring a private MCP client before `PlanStartup` can
  expose the matching tool through Jido would open credentials for a call that is then rejected.
  No placeholder startup path was added. The exact runtime handoff remains sequenced after the
  supported Jido data-tool interface.
- Picked the independent refresh boundary instead. Red: focused tests required a complete mixed
  application/tenant snapshot to become visible after discovery and required a later failed load
  to leave the preceding snapshot unchanged. Both failed because `CatalogRefresh` did not exist.
- Green: `RemoteMCP.CatalogRefresh.run/2` validates a list of existing
  `ConfiguredIntegration` values, rejects duplicate scope/integration identities, loads through
  `CatalogLoader` using `Task.async_stream/3` with bounded concurrency and an explicit infinite
  task timeout, assembles one `IntegrationCatalog`, and then performs one atomic store publish.
  Individual loader deadlines remain the work bounds; refresh does not invent a second protocol
  timeout.
- The first green run showed that the lower discovery boundary intentionally normalizes the fake
  protocol's `:remote_error` to `:discovery_failed`. The test expectation was corrected to the
  owned public error while retaining the failed scoped connection key.
- A failed load returns the failing non-secret `ConnectionKey` and normalized reason. Exceptions
  and exits are collapsed to `:load_failed`; private client configuration remains behind the
  redacted configured/integration values and is never included in the result.
- The operation is deliberately not a GenServer or scheduler. It neither retrieves application/
  tenant configuration nor defines TTL expiry, retry, revocation, or removal behavior. A future
  configuration owner can run it outside the catalog store, whose callbacks remain network-free.
- Focused verification passes 3 tests, including duplicate-identity and bounded-concurrency
  rejection before discovery. The complete Call Engine child passes 200 tests with two tagged
  integrations excluded. Root formatting, warnings-as-errors compilation, and strict Credo over
  314 files plus unused-dependency detection pass. The deterministic umbrella suite passes all 415
  default-lane tests against disposable PostgreSQL: MCP 33, Call Engine 200, Calls 35, Persistence
  25, Gateway 66, and Console 56; nine tagged network integrations are excluded. The temporary
  database was stopped and removed after the run.

Next: add the configuration-source/scheduler and stale-catalog expiry semantics before enabling
automatic refresh; the Jido interface remains the prerequisite for private live-start handoff.

## 2026-09-10 — OTP application configuration source

- Kept configuration retrieval separate from discovery, atomic publication, and periodic timing.
  `RemoteMCP.ConfigurationSource` defines the whole-source boundary; the first
  `ApplicationConfiguration` adapter reads the raw
  `:vxpipe_call_engine, :remote_mcp_integrations` OTP setting.
- Red: focused tests failed because `ApplicationConfiguration` did not exist. They required valid
  application- and tenant-scoped records to become redacted `ConfiguredIntegration` values, an
  absent setting to mean an empty source, and one invalid record to reject the entire source.
- Green: the adapter validates its own options, converts every raw keyword record through the
  existing configured-integration constructor, preserves source order, and returns only after the
  complete set succeeds. It does not log, inspect, or return private connection settings outside
  the redacted values.
- Raw records are converted at runtime so an application's Mix configuration does not have to
  construct project structs before the project modules are compiled. A later tenant/vault-backed
  adapter can implement the same behaviour without changing catalog loading or publication.
- The test module runs synchronously because it mutates OTP application environment and restores
  the previous value after each case. Focused verification passes all 3 tests. The complete Call
  Engine suite passes 203 tests with two tagged integrations excluded. Root formatting,
  warnings-as-errors compilation, strict Credo over 316 source files, and unused-dependency
  detection pass. The deterministic umbrella suite passes all 418 default-lane tests against a
  disposable PostgreSQL instance: MCP 33, Call Engine 203, Calls 35, Persistence 25, Gateway 66,
  and Console 56; nine tagged network integrations are excluded. The temporary database was
  stopped and removed after the run.
- This checkpoint does not wire an automatic refresh process, TTL expiry, configuration removal,
  or durable credential revocation. Those remain the next catalog-lifecycle checkpoint.

Next: add bounded refresh scheduling and stale-catalog expiry without doing network work in the
catalog store or retaining private configuration in inspectable scheduler state.

## 2026-09-10 — bounded catalog lifecycle

- Red: focused lifecycle tests failed because `CatalogRefresher` did not exist, and the
  application-composition test showed that enabling remote MCP added neither its task supervisor
  nor its lifecycle owner. After correcting the test source's own child specification, the red
  failures were solely at those missing project boundaries.
- Green: `CatalogRefresher` starts one refresh immediately and schedules later cycles after the
  configured interval. Configuration retrieval and the existing all-or-nothing refresh operation
  run under an explicitly supplied `Task.Supervisor`; neither the refresher callback nor
  `CatalogStore` performs remote work. A manual refresh joins an already-running cycle rather than
  starting concurrent work.
- Each cycle has a separate wall-clock timeout. A controlled indefinitely blocked source left both
  the refresher status callback and catalog reads responsive, then returned the normalized
  `:refresh_timeout` outcome after its supervised task was killed. Source and refresh options are
  omitted from inspection so a sentinel private value did not appear in process-state output.
- The last complete catalog survives source or discovery failures until `stale_after_ms` from
  lifecycle startup or the latest successful refresh. At expiry, an empty catalog is published to
  fail new resolution closed. A later complete refresh republishes the available catalog and marks
  it fresh. A successful empty source is treated differently from failure: it immediately
  publishes the intentional configuration removal and remains a fresh outcome.
- The stale interval is required to exceed the refresh interval. This guarantees at least one
  scheduled refresh opportunity before expiry. The default application settings keep automatic
  remote MCP refresh disabled and, when enabled, use a 60-second refresh interval, 30-second cycle
  timeout, and five-minute stale limit.
- Publication/removal still does not terminate an existing activation holding a pinned binding.
  The separate credential-generation revocation operation remains the explicit active-call
  invalidation mechanism.
- Refactor after green: moved one source-fetch/publication attempt into `CatalogRefreshCycle`,
  option/default/source validation into `CatalogRefresher.Options`, and the redacted data shape
  into `CatalogRefresher.State`. The GenServer now owns only callback, task, timer, waiter, and
  freshness orchestration. A focused red check showed the newly extracted options struct exposing
  a private source-option sentinel through default inspection; its inspection now omits the clock,
  source, and refresh options. Focused and child suites stayed green after the split.
- Focused refresher/application verification passes 6 tests under seeds 0, 17, and 103. The full
  Call Engine suite passes 208 tests with two tagged integrations excluded. Root formatting,
  warnings-as-errors compilation, strict Credo over 320 source files, and unused-dependency
  detection pass.
- Two ordinary-concurrency umbrella attempts reproduced pre-existing asynchronous assertion races
  outside this checkpoint: the definition-driven archive case observed missing/shifted facts, and
  one Jido loop case inspected its event list before the second tool-start event arrived. Repeating
  the archive case in one VM produced 14 passes before the same sequence race on repetition 15.
  No unrelated archive or agent code was changed here. The complete deterministic umbrella suite
  then passed with one test case scheduled at a time against disposable PostgreSQL: all 423
  default-lane tests passed (MCP 33, Call Engine 208, Calls 35, Persistence 25, Gateway 66, Console
  56), with nine tagged network integrations excluded. The temporary database was stopped and
  removed after every attempt.

Next: commit this catalog-lifecycle checkpoint. Live MCP use remains blocked on the supported Jido
runtime data-tool interface.

## 2026-09-10 — engine runtime identity churn

- Audited existing evidence and found `vxpipe_mcp` already measured protocol catalog/connection
  identity churn, while the Call Engine path had no equivalent proof across configured
  integrations, discovery, resolved bindings, and activation-local invocation.
- Red: the isolated-peer acceptance test failed because the engine probe did not exist. The first
  probe attempt then exposed an invalid test assumption: a clean peer does not inherit umbrella
  Mix configuration, so starting the complete Call Engine application correctly rejected its
  missing application settings.
- Green: the probe starts only the MCP runtime dependency it needs, owns test clients and
  integration owners through a local `DynamicSupervisor`, and exercises 100 unique tenant,
  endpoint, integration, configuration/credential/catalog generation, remote operation, local
  alias, and schema-field strings. Each cycle discovers, resolves, checks out, validates, and
  invokes the exact binding before supervised teardown.
- An equal warm-up precedes measurement in the isolated BEAM. The measured pass reports exactly
  zero atom growth, zero module growth, and no generated external value accepted by
  `String.to_existing_atom/1`. A private endpoint selector is absent from inspection of the
  configured integration, discovered catalog, resolved descriptor, tool binding, and owner state.
- Focused verification passes 1 test; the complete Call Engine suite passes 209 tests with two
  tagged integrations excluded. Root formatting, warnings-as-errors compilation, strict Credo,
  and unused-dependency checks pass. The serialized umbrella suite passes all 424 default-lane
  tests with nine tagged integrations excluded. This does not claim Jido model-tool projection:
  that public API blocker remains unchanged.

Next: commit this independent acceptance checkpoint, then continue the milestone audit without
crossing the unresolved Jido runtime data-tool boundary.

## 2026-09-10 — engine-to-wire acceptance

- The audit found protocol wire/limit fixtures in `vxpipe_mcp` and fake-protocol engine tests, but
  no acceptance path joining engine configuration/discovery/activation to the actual ExMCP client.
- Red: five engine tests failed because the controlled wire server and explicit loopback connection
  provider did not exist. This was the expected boundary failure. The first green attempt also
  caught a bad dependency declaration: test-only Plug conflicted with ExMCP's runtime Plug
  requirement. The redundant declaration was removed; Call Engine owns only Bandit as a test
  fixture dependency.
- Green: the test-only provider calls `Connections.open_loopback_test/3`; production configuration
  still calls `Connections.open/3`, requires HTTPS, and cannot enable plaintext. The controlled
  server implements only initialize, initialized notification, tools/list and tools/call behavior.
- The full path now proves the configured authorization header reaches authenticated discovery and
  the exact pinned remote operation. Invalid typed arguments produce no `tools/call`. Slow and
  oversized submitted calls return the engine's `:unknown` outcome after exactly one request.
  Rejected authentication prevents discovery, and an initialization redirect is not followed or
  given the credential.
- A separate MCP-child wire check injects a mixed loopback/public DNS result and observes that the
  effective ExMCP network client rejects it before the controlled server sees a request. This tests
  Vxpipe's actual runtime option path rather than merely inspecting a URL or policy value.
- The five focused engine checks pass under seeds 0, 17 and 103. The MCP child passes 34 tests and
  the Call Engine child passes 214 tests, with three and two tagged integrations excluded
  respectively. Root formatting, warnings-as-errors compilation, strict Credo over 320 source
  files, and unused-dependency checks pass. The serialized umbrella suite passes all 430
  default-lane tests with nine tagged integrations excluded. The Jido model-tool interface remains
  deliberately untouched.

Next: commit the engine-to-wire checkpoint, then audit the remaining history/client-projection work
that can proceed without the unresolved Jido data-tool interface.

## 2026-09-10 — closed remote authentication configuration

- The post-wire audit found that `vxpipe_mcp` still accepted arbitrary raw HTTP headers and that
  the OTP configuration source constructed a redacted integration without validating its
  production endpoint/authentication profile. Those values would fail only when discovery opened
  a client, despite the source contract describing a validated complete replacement.
- Red: the focused MCP tests failed because the authentication parser did not exist and raw
  headers were still accepted. A Call Engine source test then passed plaintext, raw-header, and
  transport-header-override profiles; it failed because all three entered the configured source.
  A bearer-token edge test also proved that padding was accepted in the middle of a token.
- Green: `Vxpipe.MCP.Authentication` now owns the closed absent/none, bearer, and custom-header
  grammar. It validates bounded token/header values, normalizes names, rejects case-insensitive
  duplicates, and prevents credential configuration from overriding transport-owned headers.
  `ClientOptions` rejects the old raw `:headers` input and receives only normalized authentication
  headers. Bearer padding is accepted only as a suffix.
- `RemoteMCP.ClientConfiguration` is a separate network-free production-profile validator used by
  the OTP source. The source still owns raw-record conversion and whole-source failure; it does not
  gain transport construction details or perform discovery. Other controlled sources and tests can
  continue constructing `ConfiguredIntegration` values without pretending to be the OTP boundary.
- A child-directory `mix format` attempt reported that no local formatter inputs are configured.
  Exact changed paths were formatted from the umbrella root, which owns `.formatter.exs`.
- Focused verification passes all 7 authentication/client-profile tests and all 4 source tests.
  The MCP child passes 37 tests with three tagged integrations excluded. The Call Engine child
  passes 215 tests with two tagged integrations excluded. Root formatting, warnings-as-errors,
  strict Credo over 322 source files, and unused-dependency detection pass. The serialized
  umbrella suite passes all 434 default-lane tests against disposable PostgreSQL: MCP 37, Call
  Engine 215, Calls 35, Persistence 25, Gateway 66, and Console 56; nine tagged integrations are
  excluded.
- The first disposable database start attempted the system socket directory and failed for lack of
  permission before tests ran. Redirecting the socket into the temporary cluster started the
  server. A subsequent diagnostic using `PGHOST` still selected port 5432 because the test config
  does not consume `PGPORT`; the final run used the supported `VXPIPE_TEST_DATABASE_URL` override.
  The completed suite was green, then the cluster was stopped and its temporary directory removed.

Next: commit and push this authentication checkpoint, then resume the remaining milestone audit
without crossing the unresolved Jido runtime data-tool boundary.

## 2026-09-10 — Jido runtime-tool boundary revalidation

- Audited the remaining milestone checks after the authentication checkpoint. Remote execution
  already uses the common bounded background worker, and generic room archival plus the gateway's
  hidden/metadata/full projection are keyed by the local tool name. They cannot form a live remote
  path until the model loop can advertise and dispatch the runtime binding.
- `mix hex.info jido_ai` reports 2.3.0, released 2026-08-05, as the latest official release and the
  currently locked version. No newer released API is available to evaluate.
- Fetched current upstream `main` at `e3d0f7671fe1349c00d7f6918eaee95a17c4c33c` into a temporary
  checkout. `ReAct.ToolSelection` still accepts Action-module values, `Config.reqllm_tools/1`
  rebuilds model definitions from those modules, and the runner resolves and executes the Action
  module. The current interceptor permits argument transformation only after module resolution.
- The related upstream issue 282 remains open. It proposes a bounded generic catalog search/run
  facade and explicitly leaves the shape undecided; it does not provide the required exact local
  alias, pinned schema, and private executor interface.
- The temporary source checkout was removed after inspection. No upstream repository, issue, or
  dependency state was changed. A Vxpipe-side generated-module or generic-selector workaround
  remains outside the approved architecture.

Next: obtain an explicit maintenance decision for a Jido fork/private patch or wait for a supported
upstream runtime data-tool interface before implementing the milestone's live mixed-tool slice.

## 2026-09-10 — Agent Runtime remote descriptor and worker bridge

The completed ReqLLM Agent Runtime removed the historical Jido interface blocker. Reconfirmed the
execution contract before wiring remote tools: every tool is handed to the same independently
supervised Call Engine invocation worker. `conversation_mode` only controls admission of later
caller turns; omission/default `blocking` and explicit `non_blocking` never select different
execution paths.

Red descriptor coverage first failed because `ToolDescriptors.compile/3` did not exist. The new
boundary accepts a resolved remote tool only with an opaque activation-owned owner reference and
copies only its exact local alias, public description, and pinned JSON Schema into Agent Runtime.
A follow-up negative check caught that Elixir's `nil` is an atom: the initial generic named-server
guard mistakenly treated a missing owner as valid. The closed check now rejects `nil`, so an MCP
descriptor cannot exist without its execution owner.

Red activation coverage then started the existing five-child graph and found no remote owner. The
runtime graph now conditionally starts `RemoteMCP.IntegrationOwner` before the coordinator and
includes it in the activation's one-for-all generation. Its private connection configuration stays
behind the integration value's redacted inspection boundary. Host-only activations retain their
existing topology.

The invocation execution boundary now calls the remote owner from the same task-backed temporary
worker used for host and Call Variables bindings. A controlled slow protocol call proved the MCP
operation runs outside both the model request process and the test caller, then reports one bounded
correlated result. Remote `unknown` and `invalid_result` outcomes retain their safe classifications;
unexpected binding/authorization failures remain `tool_failed`.

The descriptor, invocation-worker, and activation checks pass 13 tests. The complete Call Engine
suite passes 225 tests with one tagged integration exclusion. Root format, warnings-as-errors
compilation, strict Credo, and unused-lock checks pass. A fresh complete umbrella run against a
temporary trust-authenticated PostgreSQL 18 instance passes all 495 default tests with ten tagged
integration exclusions; the server was stopped and its temporary data moved to trash. This
checkpoint does not yet make a room start resolve and supply the pinned integration catalog; that
is the next red/green boundary.

## 2026-09-10 — non-blocking remote MCP in a live room

Added a full-room red test around the approved runtime contract. It compiles an explicitly
non-blocking tenant MCP binding, starts the planned room, attaches its caller, and initially fails
with the path-specific host-only runtime rejection. The test then requires the exact local alias in
the model tool list, execution in a process distinct from the provider request, one correlated
running acknowledgement, an unrelated caller turn carrying current pending state, and one private
completion continuation after the remote response.

`CallEngine.start_call/2` now obtains the current integration snapshot from the configured catalog
store only when the pinned plan contains MCP tools. A caller-supplied `mcp_integrations` option is
not an authority: it is discarded for host-only plans and replaced by the store snapshot for remote
plans. Room validation and startup receive the same snapshot. `PlanStartup.AgentActivation` verifies
every pinned resolved tool still checks out from it before passing the redacted catalog into the
activation graph. A replaced generation therefore fails closed before room startup; an owner that
has already started retains the exact checked-out generation as designed.

The live test uses a controlled slow protocol call. While it remains pending, the explicitly
non-blocking second caller turn reaches Agent Runtime with the existing running result and current
safe pending projection. No tool is run in the request process, and no endpoint, remote operation,
credential, or private owner appears in model inspection. The terminal result enters the existing
room lifecycle event and one private engine-origin continuation.

The focused live-room test passes. The complete Call Engine suite passes 227 tests with one tagged
integration exclusion. Test teardown can log the expected owner `connection_lost` when ExUnit stops
the controlled protocol client before the room subtree; the assertions and room behavior are green.

A second red test compiles against one catalog generation, atomically replaces the store with an
empty snapshot, and attempts room startup. The runtime initially returned the generic model-profile
error because `PlanStartup.AgentActivation` flattened its internal MCP failure. It now retains the
first unavailable local alias and returns a bounded `unsupported_call_plan` at that exact
participant/tool path. No room process starts and there is no application-scope fallback.

Root formatting, warnings-as-errors compilation, strict Credo, and unused-dependency checks pass.
The complete umbrella suite was rerun with seed `238092` against an isolated, trust-authenticated
PostgreSQL 18 instance: all 497 default-lane tests pass with ten tagged integration exclusions. The
temporary server was stopped and its data moved to trash. The ordinary local database path could
not authenticate because it supplied no password; this was an environment limitation rather than
a project failure.

## 2026-09-10 — one mixed Agent Runtime tool loop

Added an activation-level acceptance run containing one host tool and two local MCP aliases. Both
remote aliases use the same activation-owned `IntegrationOwner`, but each keeps its own pinned JSON
Schema and maps privately to a different remote operation. The scripted model moves through a host
tool, the first remote alias, the second remote alias, and a final answer as successive requests to
the same Agent Runtime session. Each remote request reaches only its exact configured operation.

The first run failed because the test tried to read a private invocation binding from the provider's
tool list. That list correctly contains binding-free `ModelTool` values. The final test verifies the
shared owner at `ToolDescriptors`, then separately verifies that the provider receives only exact
local names, public descriptions, and the two different schemas. It also confirms neither remote
operation nor the private configuration sentinel is inspectable at the provider boundary.

The focused activation file passes 5 tests; the complete Call Engine suite passes 228 tests with one
tagged integration exclusion. Reviewed existing focused coverage before changing milestone boxes:

- `IntegrationCatalogTest` proves whole-record tenant precedence and no stale application fallback.
- MCP invocation/security and wire tests reject unknown tools, bad schemas/arguments, external refs,
  unsafe addresses, rebinding, and redirects before unauthorized work.
- wire-limit tests cover compressed, incrementally chunked, and resumed SSE responses under one
  cumulative budget; the wire integration proves submitted timeout/oversize is unknown with one
  request and no retry.
- catalog replacement plus live stale-start tests prove old active owners retain their pin while new
  work resolves the replacement or fails closed.
- revocation/lease checks and the isolated runtime-binding churn probe cover authorization lifetime,
  cache separation, and external identity safety.

Remote-specific archive/client-visibility evidence and an integrated scoped-library/domain-history
check remain before the milestone can be completed.

## 2026-09-10 — spoken remote work, archive, and variables

Added two remote-specific live-room acceptance checks. The first enables the selected TTS profile,
starts a non-blocking remote invocation, and drives the provider/audio-sink handshake for the
acknowledgement before releasing the remote worker. The absence of a terminal tool event at that
point proves speech delivery does not wait for MCP completion. The later private continuation and
second spoken response complete normally after the controlled release.

The second run enables one typed Call Variables section with a reception-agent read/write grant and
an asynchronous collecting archive. It archives the remote start and full accepted bounded result,
then lets the remote completion continuation request `update_variables`. The separately supervised
variables tool publishes revision 1 and its full snapshot to the archive. Its success remains a
Call Variables authorization decision; MCP receives no variables handle, room context, participant
grant, or archive interface. The controlled client records only the exact remote operation,
arguments, and timeout. Existing gateway tests apply hidden/metadata/full projection to the same
generic tool-event structs, so remote tools cannot bypass default-hidden visibility.

The focused live-room file passes 4 tests, and the complete Call Engine suite passes 230 tests with
one tagged integration exclusion. The official MCP conformance integration lane also passes all 3
tests against the supported profile. Root format, warnings-as-errors compilation, strict Credo over
367 source files, and unused-dependency checks pass. A full umbrella run with seed `238092` against
an isolated PostgreSQL 18 instance passes all 500 default-lane tests with ten tagged integration
exclusions; the server was stopped and its temporary data moved to trash. No UI changed, so browser
inspection was not applicable. The milestone and index are now complete at 12 of 24 roadmap items.
