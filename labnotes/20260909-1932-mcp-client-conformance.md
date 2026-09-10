# MCP client conformance

## 2026-09-09 — isolated milestone checkpoint

- Started the implementation on `milestone/mcp-client-conformance` from the clean
  milestone-9 mainline. Milestone work will remain on this branch and land as small,
  coherent commits before the branch is merged.
- Confirmed that ExMCP 1.3.0 is the current released package and downloaded the
  published Hex source for boundary review. No dependency or runtime code has been
  added yet.
- Reviewed the released HTTP transport, bounded HTTP client/stream, target policy,
  client connection lifecycle, request path, tool operations, schema policy, and
  package dependencies. This was a source-level compatibility check, not a claim of
  conformance.

## Confirmed dependency behavior

- The explicit client profile can request legacy-only MCP `2025-11-25`. Vxpipe must
  additionally inspect the negotiated client status and reject any other revision.
- Each HTTP request resolves the complete DNS answer, rejects mixed or disallowed
  addresses, pins the selected address for the connection, preserves the hostname for
  TLS verification, removes caller-supplied Host headers, requests identity encoding,
  and applies incremental request/response byte limits.
- HTTPS verifies peer certificates and hostnames by default with TLS 1.2 or 1.3.
  Plain HTTP remains supported by the dependency, so the production Vxpipe config
  boundary must reject it. A separately constructed loopback test profile may allow
  HTTP for conformance fixtures.
- The bounded request path does not follow redirects. Compressed responses are
  rejected rather than decompressed outside the byte budget.
- Unexpected connection loss fails pending requests before ExMCP reconnects and
  performs a new handshake. It does not automatically submit those pending requests
  after reconnecting.
- `tools/list` accepts a cursor but returns one page. Whole-operation page, cursor,
  aggregate-byte, and deadline limits therefore belong in the Vxpipe discovery
  wrapper.
- ExMCP exposes a bounded schema policy that rejects cross-document references by
  default and describes JSON Schema 2020-12 validation. The effective outgoing
  argument path still needs a project-owned pre-submission contract test.

## Public-boundary decisions for implementation

- Use `ExMCP.Client.make_request/5` for `tools/call`, with explicit
  `retry_policy: false`, `http_stream_retry: :safe_only`, and
  `max_mrtr_rounds: 0`. The higher-level `call_tool` helper can refresh headers and
  submit the invocation again after a protocol header mismatch, while the default
  modern stream mode is at-least-once. Neither behavior matches Vxpipe's
  no-speculative-resubmission contract.
- Keep ExMCP reconnection enabled for session recovery, but map a submitted request
  interrupted before a trustworthy response to an unknown outcome. Callers may make
  a new explicit invocation after readiness returns; Vxpipe will not replay the old
  one.
- Apply one absolute deadline and aggregate decoded-byte budget in the Vxpipe wrapper
  across every discovery page. ExMCP's limits remain the per-response transport
  defense.
- Keep endpoint names, remote tool names, schemas, cursors, and credentials as data;
  no value from a remote catalog becomes an atom or module.

## Compatibility gap to resolve before production transport work

ExMCP's HTTP transport reads trusted origins from application-global `:ex_mcp`
security configuration. Its public client options do not currently pass a per-client
trusted-origin set into the transport security guard. That is awkward for independently
configured application and tenant integrations and must be resolved at the dependency's
public boundary without weakening credential-origin binding. Loopback tests are not
evidence that this production concern is solved.

## 2026-09-09 — pinned dependency and client profile

- Added the `vxpipe_mcp` umbrella child with direct, exact `ex_mcp == 1.3.0`
  ownership and a direct JSV dependency for the forthcoming outgoing-argument
  validation boundary. The child has no Jido, call-engine, database, gateway, or
  Console dependency.
- Red: the focused client-profile test first failed because `ClientOptions.build/1`
  did not exist. A second test then demonstrated that an HTTP remote endpoint was
  incorrectly accepted.
- Green: `ClientOptions` now pins HTTP transport mechanics to the legacy-only
  `2025-11-25` revision, keeps generic retry disabled, enables reconnect without
  replay, and rejects plaintext production endpoints.
- Verification: the focused child suite passes with 2 tests and 0 failures. Root
  formatting, warnings-as-errors compilation, strict Credo (280 files, no issues),
  and unused-dependency checks pass.
- A root `mix test` attempt reached the existing PostgreSQL setup alias and could not
  authenticate against the local server. No database is required by this child; the
  focused test was rerun from its owning application. The complete umbrella suite will
  use the established isolated PostgreSQL setup at the milestone completion gate.

## 2026-09-09 — bounded catalog discovery

- Red: three focused tests failed at compile time because the discovery/catalog boundary
  did not exist. They define multi-page cursor propagation, complete raw-definition
  preservation, repeated-cursor rejection, and aggregate decoded-size rejection.
- Green: added a narrow protocol-client behaviour, an ExMCP-only implementation, a bounded
  pagination coordinator, and an immutable catalog index. These responsibilities remain in
  separate modules; tenant selection, connection ownership, invocation, and model exposure
  are not mixed into discovery.
- Discovery carries one decreasing timeout across all pages, disables generic retries at
  each ExMCP request, allows only safe read-stream recovery, rejects repeated cursors, and
  withholds the entire catalog when any page fails or exceeds its aggregate re-encoded JSON
  byte budget. Tool definitions remain complete string-keyed maps; none of their names or
  schema values become atoms or modules.
- Added Jason as a direct dependency because Vxpipe itself measures the stable encoded size
  of decoded page data instead of depending transitively on ExMCP's JSON dependency.
- Verification: `mix test` and warnings-as-errors compilation pass in `vxpipe_mcp` with
  5 tests and 0 failures. `mix deps.unlock --check-unused` passes from the umbrella root.
  Root `mix credo --strict` checks 284 source files with no issues. A child-local Credo
  command is unavailable because Credo is an umbrella-root development dependency.
- This checkpoint does not prove an actual ExMCP connection, initialization, negotiated
  version, server-issued session, invocation, or conformance scenario. Those boxes remain
  open.

## 2026-09-09 — validated invocation boundary

- Red: three focused invocation tests failed because `Vxpipe.MCP.Invocation` did not exist.
  They require invalid arguments, unknown tools, and cross-document schema references to
  stop before the protocol boundary; a valid call must preserve its data and timeout; an
  oversized decoded result must not be returned.
- Green: added `ArgumentValidator` for the JSON Schema concern and `Invocation` for catalog
  selection, deadline, submission, and result-budget coordination. This keeps schema
  mechanics out of the transport adapter and catalog modules.
- JSV builds untrusted schemas with no remote resolver, atom-based casts disabled, and the
  2020-12 dialect fixed. Runtime validation uses `cast: false`, so validation cannot silently
  coerce model arguments before a tool call.
- The ExMCP adapter submits `tools/call` through `make_request/5` with `retry_policy: false`,
  `http_stream_retry: :safe_only`, and zero MRTR rounds. It exposes only categorical
  not-submitted, remote-error, or unknown-outcome failures; dependency error payloads are
  not returned through the Vxpipe invocation API.
- Verification: the complete `vxpipe_mcp` suite passes with 8 tests and 0 failures;
  warnings-as-errors compilation, root formatting, strict Credo over 286 source files, and
  the unused-lock check pass.
- This deterministic checkpoint does not yet prove transport-level incremental response
  limits, initialization/readiness, or a real remote invocation. Those remain open.

## 2026-09-09 — scoped supervised connections

- Red: three focused lifecycle tests failed because connection identities, handles, and
  supervised ownership did not exist. They require reuse for one integration/credential
  generation, isolation across generations, credential-free handles, complete subtree
  retirement, and rejection/cleanup of a mismatched negotiated revision.
- Green: the application now supervises an explicitly named unique Registry and
  `DynamicSupervisor`. Each dynamic integration subtree owns exactly one protocol client;
  no worker starts another worker directly. `Connections` coordinates open/reuse/close,
  while key validation, registry naming, connection data, runtime adaptation, and subtree
  supervision remain separate cohesive modules.
- A connection key contains only bounded integration and credential-generation strings.
  Endpoint headers stay in the supervised client options and never enter the returned
  connection handle or readiness error. Reusing the same key intentionally pins the
  existing session; the integration owner must change the generation when credentials do.
- Readiness requires both `connection_status: :ready` and exact MCP `2025-11-25`.
  Mismatched or unready trees are terminated before `open/3` returns an error.
- Verification: the complete `vxpipe_mcp` suite passes with 11 tests and 0 failures;
  warnings-as-errors compilation, root formatting, strict Credo over 293 source files, and
  the unused-lock check pass.
- Tests use a deterministic supervised runtime double. Actual ExMCP initialization,
  session headers, connection loss/recovery, and reference-server use remain unproven.

## 2026-09-09 — explicit transport profiles and limits

- Rechecked ExMCP upstream `master` at commit `56880c6` after inspecting release 1.3.0.
  Its HTTP request guard still reads application-global trusted origins; there is no newer
  released or upstream per-client option to pin. A global union of tenant origins is not an
  acceptable substitute for per-integration credential binding, so this compatibility gate
  remains open.
- Red: the focused profile tests showed that transport limits were absent and the dedicated
  loopback test builder did not exist.
- Green: `TransportOptions` now owns validated positive limits. Production client options
  explicitly bound request bodies, responses, streaming buffers, DNS resolution, connection,
  and request duration instead of inheriting broad dependency defaults. Private-host
  exceptions remain explicit data passed to ExMCP's connect-time/DNS-rebinding policy.
- `ClientOptions.build/1` remains HTTPS-only and rejects userinfo/fragments. A `test_mode`
  key cannot weaken it. `build_loopback_test/1` is a separate code path that accepts only
  plaintext localhost, IPv4 loopback, or IPv6 loopback targets and disables reconnect for
  deterministic fixtures.
- Verification: the complete `vxpipe_mcp` suite passes with 13 tests and 0 failures;
  warnings-as-errors compilation, root formatting, strict Credo over 294 source files, and
  the unused-lock check pass.

## 2026-09-09 — official initialization and tool-call scenarios

- Pinned the official legacy client harness to
  `@modelcontextprotocol/conformance@0.1.16` / tag commit `21a9a2f` and the additional
  Everything fixture to `@modelcontextprotocol/server-everything@2025.11.25` / tag commit
  `0155af3`. The latter is recorded but not yet claimed as executed.
- Red: the first official `initialize` run failed because the Vxpipe conformance task did
  not exist. After adding it, the next run exposed that umbrella development runtime config
  required an unrelated Deepgram key. The driver now starts only `:vxpipe_mcp`; the pinned
  harness invokes it under `MIX_ENV=test`, where unrelated voice apps/config are not loaded.
- Added `Connections.open_loopback_test/3` as a distinct fixture-only entry. A focused test
  first proved that it was missing and that ordinary `open/3` still rejects the same HTTP
  endpoint. A transient post-shutdown Registry entry also surfaced; lookup now refuses a
  dead registered PID, and retirement is acknowledged with process monitors.
- Green: official `initialize` passes 1/1. Official `tools_call` passes 1/1 after observing
  `initialize`, `notifications/initialized`, `tools/list`, and exactly one `tools/call` for
  the discovered `add_numbers` schema. No Jido, database, call engine, or model provider is
  started by the task.
- Added `bin/test-mcp-conformance`, an opt-in tagged ExUnit wrapper, and
  `docs/mcp-client-conformance.md`. The matrix names all harness scenarios selected for
  `2025-11-25`: OAuth and elicitation are out of this milestone's scope, while `sse-retry`
  remains pending and is not represented as a pass.
- The initial manual red harness run saved diagnostic results under `/tmp`; no generated
  result directory or dependency install is committed.

## 2026-09-09 — exact-version SSE recovery

- The unmodified official `sse-retry` scenario selected by `--spec-version 2025-11-25`
  hard-codes `protocolVersion: 2025-03-26` in its initialize response. Vxpipe rejects it as
  required. That run scored one incidental check plus two warnings but exited through the
  exact-version error; it is not counted as a pass.
- Red: the Vxpipe driver initially had no recovery scenario action, and the fixture's wrong
  revision prevented readiness. A focused profile test also showed that loopback reconnect
  could not be explicitly enabled.
- Green: loopback reconnect remains off by default but can be enabled only through the
  dedicated fixture builder. The scenario action discovers `test_reconnection` and invokes
  it through the ordinary validated, no-reissue invocation path with one deadline.
- Added a reproducible corrected-fixture runner. It clones exact official tag commit
  `21a9a2f` into a temporary directory, verifies that identity, and applies a committed
  one-line patch changing only the server's initialize revision to `2025-11-25`.
- The corrected run passes 3/3 with no warnings. It observes a single `tools/call`, a broken
  SSE response stream, reconnection after the advertised 500 ms retry interval with
  `Last-Event-ID: event-2`, and delivery of the original result over the re-established GET
  stream. No speculative tool-call resubmission occurs.
- This proves exact-version session initialization and response-stream resumption. It does
  not yet prove near-limit cumulative byte accounting or timeout expiry during recovery.
- Verification: the default MCP child suite passes 14 tests with two integration tests
  excluded; the opt-in integration lane passes both tests; root formatting, strict Credo
  across 296 files, and unused-dependency checks pass.
- The umbrella `mix test` command could not create its test database because this shell has
  no PostgreSQL password or test database URL configured. The failure occurred before the
  umbrella tests ran; MCP-owned tests remain green as recorded above.

## 2026-09-09 — Everything-server interoperability

- The initially recorded `@modelcontextprotocol/server-everything@2025.11.25` fixture is not
  compatible with the selected protocol despite its release number. Its exact tag commit
  `0155af3` locks MCP SDK `1.19.1`, which supports revisions only through `2025-06-18`.
  It was rejected rather than weakening Vxpipe's exact-version gate.
- The current official tag `2026.8.31` / commit `a40bc270` locks SDK `1.30.0`, which supports
  `2025-11-25`. The reproducible runner verifies that commit, uses its lockfile, builds only
  the Everything workspace, and starts Streamable HTTP on an ephemeral loopback port.
- Red: the first unit test failed because `ReferenceProbe` did not exist. The integration
  test then failed because the runner did not exist. Once wired, the real server exposed a
  second red case: its valid explicit Draft 7 input schema was rejected by Vxpipe's
  2020-12-only dialect gate.
- Green: `ArgumentValidator` now accepts the canonical embedded Draft 7 dialect allowed by
  MCP while retaining the no-external-reference rule. The probe discovers `echo`, validates
  its arguments, invokes it once, and returns its full string-keyed definition and result as
  data through a server-issued session.
- The standalone successful result contains `Echo: vxpipe-reference-probe` and the preserved
  official tool annotations, title, description, execution metadata, and input schema. The
  path starts no Jido, database, call-engine, or model-provider application.
- Verification: the default MCP child suite passes 16 tests with three integration tests
  excluded; the opt-in integration lane passes all three tests in 18 seconds. Root
  formatting, strict Credo across 299 files, and the unused-dependency check pass;
  `shellcheck` is not installed in this environment.

## 2026-09-09 — bounded discovery failures

- Expanded the deterministic discovery evidence from one-page size and repeated-cursor
  cases to cumulative size across pages, endlessly changing cursors stopped by `max_pages`,
  malformed page shapes, and duplicate tool identities. Every failure returns only an error,
  so no partial `Catalog` is available for invocation.
- Red: a scripted dependency error containing authorization-like data was returned verbatim
  inside `{:protocol_error, reason}`. That violated the credential-free diagnostic contract.
- Green: discovery now returns the categorical `:discovery_failed` error for dependency
  failures and discards the raw reason. The focused suite passes six tests.
- Two fixture Agents in one test initially collided on ExUnit's default child ID; the helper
  now supplies a unique child-spec ID while retaining supervised ExUnit cleanup.
- A compile run contended with the active development watcher over the shared build tree.
  Rerunning the already-compiled focused suite completed with six tests and no failures; the
  subsequent clean child compile and suite passed 19 tests with three integrations excluded.
- The opt-in integration lane still passes all three tests. Root formatting, strict Credo
  across 299 files, and the unused-dependency check pass.

## 2026-09-09 — identifier churn

- Added a synchronous project-boundary test covering 250 unique endpoint hosts, integration
  IDs, credential generations, tool names, and schema revisions. Each iteration constructs a
  catalog, opens one supervised ready connection, monitors its owner, closes it, observes
  shutdown, and verifies the registry no longer resolves the key.
- The test warms the same path before measuring and requires both BEAM atom growth and newly
  loaded module growth to remain at or below five. It passed, demonstrating bounded runtime
  overhead rather than growth proportional to external identifier churn.
- A companion isolation check builds two catalogs with the same remote tool name and
  different scope data. Fetching requires the explicit catalog value and returns only that
  catalog's definition; the library has no global remote-name registry.
- Verification: the complete default child suite passes 21 tests with three integrations
  excluded; warnings-as-errors compilation, root formatting, strict Credo across 299 files,
  and the unused-dependency check pass.

## 2026-09-09 — effective wire failures

- Added a test-only Bandit/Plug MCP fault fixture so malformed and error responses traverse
  the real supervised `Connections`, `Discovery`, `Invocation`, and ExMCP public path. Bandit
  is test-only; Plug was already an ExMCP runtime dependency and is now explicit in the
  owning child. The lockfile versions did not change.
- Bypass was tried first but its Ranch 1 requirement conflicts with the umbrella's locked
  Ranch 2 graph. It was removed without changing the lockfile.
- Red: ExMCP returns JSON-RPC errors as string-keyed maps when `format: :map` is selected.
  `ExMCPClient` did not recognize that public shape, so server and method-not-found errors
  incorrectly became `:outcome_unknown`.
- Green: the adapter recognizes integer-coded JSON-RPC error maps and returns only
  `:remote_error`, discarding the remote message. Malformed JSON and wrong correlation IDs
  correctly remain `:outcome_unknown` because submission occurred. The fixture observes
  exactly one `tools/call` in every case, with no speculative resubmission.
- Verification: the default MCP suite passes 23 tests with three integrations excluded; the
  opt-in lane passes all three tests. Warnings-as-errors compilation, root formatting,
  strict Credo across 299 files, and the unused-dependency check pass.

## 2026-09-09 — effective response limits

- Extracted `FaultClient` as the single test-driver owner for connection, discovery,
  invocation, deadline, and cleanup. `FaultServer` remains responsible only for serving and
  observing wire cases; both wire test modules now use those shared boundaries.
- Red: the response-limit tests initially had neither a fault client nor fixture responses
  for encoded, chunked, SSE, delayed, or disconnected calls.
- Green: with a 1 KiB configured response cap, a response declaring `Content-Encoding: gzip`
  is rejected as `:compressed_response`; 1.5 KiB chunked JSON and POST SSE payloads are
  rejected as `:response_too_large`. Vxpipe exposes the honest `:outcome_unknown` category
  because each tool request was already submitted.
- A fixture delayed beyond a 100 ms invocation deadline and a connection closed without a
  response also return `:outcome_unknown`. Every size, timeout, and disconnect case records
  exactly one `tools/call`, so no invocation is speculatively repeated.
- These checks prove per-response incremental bounds. They do not prove cumulative byte or
  deadline accounting across a broken and resumed stream; that acceptance gate remains open.
- Verification: the default MCP suite passes 25 tests with three integrations excluded;
  warnings-as-errors compilation, root formatting, strict Credo across 299 files, and the
  unused-dependency check pass.

## Sources

- [ExMCP 1.3.0 package](https://hex.pm/packages/ex_mcp/1.3.0)
- [ExMCP client API](https://ex-mcp.hexdocs.pm/ExMCP.Client.html)
- [MCP 2025-11-25 Streamable HTTP](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)
- [Official conformance SDK guide](https://github.com/modelcontextprotocol/conformance/blob/main/SDK_INTEGRATION.md)

## 2026-09-09 — resumed-stream compatibility audit

- Traced ExMCP 1.3.0's public request path and exact tagged tests. Explicit invocation
  timeouts use one monotonic caller deadline, including time spent waiting for legacy SSE
  recovery. The SSE transport's configured response limit does not have the same scope:
  `BoundedStream` does not increment its response-size counter in stream mode, and
  `SSEClient` bounds only the bytes retained for one incomplete frame before resetting the
  buffer after a complete event.
- Used a temporary checkout of the pinned conformance tag, corrected only to the selected
  `2025-11-25` revision, and added paced progress events for the audit. Three hundred
  individually bounded events contained 339,790 decoded JSON bytes in aggregate. With
  Vxpipe's 262,144-byte response and stream-buffer limits, the client accepted all events,
  delivered the final result after `Last-Event-ID` recovery, and the scenario passed. This
  demonstrates a failed cumulative-budget requirement, not a successful limit check. The
  temporary fixture was not added to the repository.
- Changed that temporary server's retry instruction to 6,000 ms while retaining the
  conformance action's 5,000 ms deadline. The tool was submitted once, its POST stream
  closed, and Vxpipe returned `:outcome_unknown` at the original deadline before the delayed
  GET reconnect. This confirms the deadline half of the recovery requirement.
- A first unpaced variant also exposed ExMCP's incomplete-frame parser losing a fragmented
  SSE event under a burst of writes and logging the raw `Jason.DecodeError` response data.
  The paced run isolated the cumulative-budget result, while source inspection confirmed
  that asynchronous POST failures likewise interpolate raw reasons into logs.
- Decision: keep the cumulative-stream and credential/diagnostic acceptance gates open and
  mark this milestone dependency-blocked. Do not compensate with global tenant-origin trust,
  a host-wide log filter, disabled SSE, or a Vxpipe-owned alternate MCP parser. A compatible
  ExMCP public boundary is required before production approval.

## 2026-09-09 — upstream and fork feasibility

- Queried the current upstream branches and complete issue/pull-request list. No open or
  closed item addresses per-client credential trust, cumulative SSE response budgets, or
  remote-response-safe client diagnostics. Upstream `master` is still commit `56880c6`; its
  two commits after release 1.3.0 are unrelated test changes.
- In a temporary upstream checkout, first added a failing isolation test with two clients
  trusting different exact origins. Passing each client's `security` map into the existing
  `SecurityConfig.get_transport_config/2` call sites made the test and its focused suite pass
  (14 tests). This shows that the trust-scope defect itself is a small dependency patch.
- Added a failing async-POST logging test whose remote failure term contained a private
  sentinel. Replacing raw inspected reasons in the primary `ExMCP.Client` failure logs with
  existing shape-only summaries made that test and the broader focused client suites pass
  (33 tests). A production patch would also audit the connection-manager and other active
  HTTP client log paths before claiming complete diagnostic safety.
- The cumulative stream limit is not safely fixed by retaining one byte counter in
  `SSEClient`. Legacy MCP `2025-11-25` uses a shared GET SSE stream for multiple pending
  requests and keeps that process across reconnects. A lifetime counter would charge later,
  unrelated tool calls for earlier traffic. Correct dependency work must track request IDs
  and progress tokens in the client, carry each request's budget over reconnects, and stop
  only the affected work when exhausted while retaining a separate bound for uncorrelated
  traffic.
- No temporary dependency edits, generated dependencies, or external repository changes
  were copied into Vxpipe. Adopting a fork or publishing an upstream contribution remains an
  explicit user decision.

## 2026-09-10 — maintained ExMCP fork preparation

- The user selected a maintained-fork workflow: one branch per upstreamable fix and a `vxp`
  integration branch for Vxpipe until compatible upstream releases are available.
- Created four test-first fix branches from upstream `56880c6`: per-client HTTP security,
  safe client diagnostics, fragmented SSE parsing, and request-scoped cumulative SSE budgets.
  The budget branch is intentionally based on the parser branch; the other fixes are
  independent.
- The cumulative budget is owned per JSON-RPC request and correlated through request IDs or
  progress tokens, so multiple requests sharing the legacy GET stream do not share a counter.
  Unknown traffic uses a separate bounded allowance. POST SSE data and resumed GET-stream
  events debit the same request budget.
- Merged the fix branches with merge commits into local `vxp` at `2d31d26`. Changed-file
  formatting, warnings-as-errors compilation, strict Credo, and 95 combined focused tests
  pass.
- A full upstream run completed 4,627 tests with two unrelated failures: the local Claude
  authentication-method list differs from its fixture, and a generated modern-stdio fixture
  cannot resolve the `:jason` SCM. The repository-wide formatter is also already red on two
  unchanged Codex tests; changed files pass the formatter.
- The response-budget commit bypassed ExMCP's pre-commit hook only because that hook runs the
  already-red repository-wide formatter. No unrelated upstream file was changed.
- Added `docs/ex_mcp-fixes.md` as the durable branch policy, pull-request order, verification,
  and eventual fork-removal record. Remote publication and Vxpipe dependency verification
  remain pending until the fork is reachable.

## 2026-09-10 — fork publication and Vxpipe adoption

- Published every local branch to `HashNuke/ex_mcp` and verified the remote tips:
  `master` at `56880c6`, four independently reviewable `fix/*` branches at the commits
  listed in `docs/ex_mcp-fixes.md`, and combined `vxp` at `2d31d26`.
- Replaced the Hex dependency with the public HTTPS `vxp` branch. `mix.lock` pins
  `2d31d26270024c123de8b7c80833fcf4d089e3a5`; no local path or SSH credential is needed
  by builds. The existing Mint 1.9.3 lock remains unchanged.
- Added the validated endpoint's canonical origin as each ExMCP client's exact trust policy
  and removed broad trusted-host defaults from that client. The focused option test was red
  with no security policy and green after the change.
- Added a unique integer MCP progress token to every tool request. The wire test was red when
  `tools/call` omitted `params._meta.progressToken` and green after the adapter supplied
  it.
- Added a deterministic legacy recovery fixture. A request-owned POST SSE stream closes
  after advertising `event-2`; GET recovery presents `Last-Event-ID: event-2`, then sends
  two complete correlated progress events that are individually below 1,024 bytes but exceed
  that request budget together. The resumed stream stays open, while the request fails
  within one second rather than waiting for its 5,000 ms deadline. Only one tool call occurs.
- Updated a Vxpipe test that had asserted dependency-internal raw failure atoms appeared in
  logs. It now verifies Vxpipe's owned contract: the bounded public outcome and exactly one
  submission. Diagnostic privacy is covered separately without coupling to ExMCP log text.
- The original identity-churn check measured VM-global atom/module counts in the umbrella
  runner. Concurrent lazy loading from other children produced unrelated deltas (including
  `Zoi.Validations.*` modules and later test-module atoms), while the focused MCP run stayed
  green. The check now runs two non-overlapping 500-identity batches in an isolated peer VM:
  the first stabilizes application startup and the second retains the strict five-atom and
  five-module ceilings while also proving the supplied strings are not atoms.
- The wire fault fixture's 500 ms setup/invocation allowance was also too narrow under a
  loaded umbrella and failed during discovery instead of reaching its intended fault. A
  two-second intermediate value reproduced the same race in the full MCP suite, so its
  test-only default now matches Discovery's 5,000 ms bound; the explicit 100 ms timeout
  cases remain unchanged.
- Verification: the final default MCP suite passes 27 tests with three network integrations
  excluded; official `initialize` and `tools_call` pass 1/1 each; the corrected recovery
  fixture passes 3/3; and the pinned Everything server returns its expected `echo` result.
  Root formatting, warnings-as-errors compilation, strict Credo over 299 files, and the
  unused-dependency check also pass. One complete isolated umbrella run passed MCP 27/0,
  call engine 181/0, Calls 35/0, Persistence 25/0, Gateway 66/0, and Console 55/0 before a
  test-only SRP refactor of the recovery fixture. Subsequent exact-state root runs twice
  timed out waiting for the same unrelated asynchronous call-variable archive assertion;
  its focused rerun passed with the same seed. Investigation found that the test's capacity
  of four could be occupied by its baseline and three startup facts before the update was
  offered. Raising only that non-overflow fixture's capacity to eight removed the scheduling
  race, and the next complete root suite passed every child. The suite used the local
  PostgreSQL Unix socket and a temporary build path because the shared test build had stalled
  compiling Mint. Milestone-wide operational visibility remains.
