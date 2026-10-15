# Platform MCP implementation

## Starting state and authorization

- User authorized the complete nine-checkpoint milestone, small commits, subagent
  reviews and concise pushnotify progress updates. Existing planning documents are
  included in the first reviewed baseline commit; implementation stays unchecked.
- Working on branch `mcp`. `bin/setup` passed dependencies, assets and dev/test
  migrations. Local Console port 4002; no live credentials were read or tests run.
- Initial pushnotify delivery command completed successfully.
- Planning subagent confirmed scope and dependency direction, and identified
  ambiguous HTTP scope errors versus MCP domain errors. Clarified the boundary:
  shared policy handles pre-dispatch key scope denial; resource visibility and
  ordinary domain failures retain safe tool errors.
- First implementation slice consolidates spec writes over a canonical HTTP
  handler with browser-session/CSRF and API-key adapters. Parallel work inventories
  all UI routes and relocates Identity dependency composition to its owner.

## Shared HTTP and Identity first slice

- Inventory covers all UI product requests, including services, roles, keys,
  onboarding/sample writes and artifact links, plus explicit auth/media exceptions.
  Independent review corrected a stale claim: spec update existence checks already
  live in Calls and should be reused rather than reimplemented.
- Identity composition moved to its own runtime configuration; Console delegates.
  Two new configuration-boundary tests failed first, then 61 Identity and eight
  Console tests passed. Independent review found no remaining composition issues.
- Canonical spec-write tests first failed with 401/no CSRF enforcement. Configured
  browser authentication now resolves a session and applies CSRF before calling
  the same authoring operation used by API keys. Explicit headers never fall back.
- Reviewer identified `:forbidden` mapping to 503. Added restricted-session test,
  confirmed the failure, then mapped it to 403; all 14 endpoint tests now pass.
- Editor write URL test failed on `/admin/api`, then passed after routing writes
  through `/api`. All five adapter tests, TypeScript and assets build passed.
- Headless Chrome inspected desktop and 390px mobile using a sandbox fixture.
  Renaming and Save as draft produced canonical PUT 201 and revision 2. The first
  fixture lacked catalog repository configuration; supplying the real local port
  resolved that setup issue. Browser and sandbox process were closed afterwards.
- Full root suite overlapped agents' intentional red tests and a pending migration;
  its result cannot establish a stable green snapshot. Will rerun after the agents
  finish. Avoid concurrent migrations and sandbox browser transactions: an open
  browser transaction blocked the digest-index migration until fixture shutdown.

## Public ExMCP integration probe

- Gateway now declares its direct ExMCP dependency using the same git pin already
  in the shared lock. Outbound MCP remains independent.
- Three public-boundary tests first failed on the missing probe handler and then
  passed. They exercise actor callbacks, initialize/notifications/ping/tools,
  key-bound sessions, DELETE and monitored timeout cleanup without a network server.
- The pinned 2025 profile requires sessions; stateless behavior selects a different
  protocol revision. Wrong-key reuse deliberately returns 404. Product wrapper
  still needs strict version/method rules, Bearer auth, limits and real mounts.
- Independent review found no blockers and confirmed the limited evidence scope.

## Tenant-independent key authentication

- Added `Calls.authenticate_api_key/2` to resolve stored tenant/scopes without a
  tenant argument. Settings platform keys retain installation authority and an
  explicit platform-key credential kind; legacy operator provenance is separate
  and its secrets are rejected by the new MCP-facing entry point.
- Persistence adds a nonunique digest index and a LIMIT 2 lookup. Ambiguous
  digests, including revoked duplicates, fail closed; old tenant-bound auth is
  unchanged and keys do not need rotation. No raw secret/digest reaches the actor.
- Five Calls and three Persistence red tests failed on missing entry/lookup before
  implementation. Green selections: 26 Calls tests and 11 Persistence tests,
  including existing tenant/platform/legacy compatibility. Test migration passed.
- Independent review found no auth blocker. Raised/exited storage failures need
  HTTP 503 normalization in the forthcoming endpoint (not just returned errors).
- First full-suite run finished with old compiled modules versus newly written
  tests during concurrent edits, plus a compactor scheduling failure. It is not
  a stable-snapshot verification; rerun after the foundation work settles.

## Authenticated MCP mounting boundary

- Exact `/mcp` mounts in Gateway and Console ahead of generic body parsing; prefix
  mounting uses the remaining path segments. Disabled mounts return 404. Runtime
  hosts/origins use the app origin independently of the carrier callback origin.
- Every method reauthenticates one Bearer credential before dispatch. Missing or
  invalid credentials return 401, malformed headers 400, storage exceptions/exits
  503; cookies/query/body fields and MCP session IDs never supply authority.
- Monitored admission leases bound concurrent requests; body/read/handler limits,
  host/origin/HTTPS checks and no-store responses are enforced at this boundary.
- Review identified oversized request IDs retained by the dependency and response
  bodies sent to unknown notifications. Two red regressions reproduced both;
  bounded IDs and empty notification responses now pass. Focused Gateway selection
  passes 21 tests, and Console passes two tests with real local issuance/revocation.
- Rechecked official MCP authorization/client guidance: static Bearer configuration
  remains appropriate for the approved key-based milestone; OAuth is the recommended
  interoperable flow and OAuth-only clients remain explicitly outside its promise.
- Dependency inspection found timeout/crash logs could include arguments or handler
  state. A separate library fix is under review before sensitive tools are enabled.
  No full milestone or full-suite acceptance is claimed by this boundary commit.

## Principal-aware directory and spec reads

- Tenant directory now accepts stored API principals: calls/full tenant keys see
  only their own tenant; Settings platform credentials see the installation.
  Browser visibility/directory checks remain unchanged; malformed repository rows
  fail closed, and filtering/counts/paging remain in bounded repository queries.
- Spec list/source operations now accept tenant admin keys and reject calls-only
  or foreign tenant actors before accessing storage. Shared source fetching keeps
  latest/historical/publication metadata and checks returned tenant/spec ownership.
- Tenant tests first produced five expected failures, then 15 directory tests
  passed. Spec tests first produced five failures, then 55 focused tests passed.
  Independent review found no blocker and confirmed this is domain evidence only.
- Legacy spec listing retains its existing maximum of 100; the new public MCP
  pagination boundary must enforce the approved maximum 50 without silently
  changing unrelated legacy directory contracts.

## Dependency diagnostic privacy

- Timeout logging in the pinned library could include the GenServer request and
  its tool arguments; returned errors and option callbacks also printed raw data.
  Upstream sentinel regressions reproduced these leaks. The reviewed fix records
  classifications/shapes only and preserves response and supervision semantics.
- Rejected a broader generic callback-crash wrapper: translating every crash into
  shutdown would change transient supervision restart behavior. Vxpipe owns its
  tool callback fault handling instead of changing unrelated library lifecycles.
- Published upstream commit `5fa760207bb09fc3b19b3049bc481b5e55106095` on
  `HashNuke/ex_mcp` branch `vxpipe-server-log-redaction`; both umbrella consumers
  now pin that immutable revision. Only this dependency changed in `mix.lock`.
- Upstream focused selection passed 128 tests. With the new pin, Gateway's MCP
  selection passed 22 tests and outbound MCP passed 37 tests (three excluded).
  Independent review found no blocker. Full umbrella acceptance remains pending.

## Canonical tenant HTTP and MCP discovery

- Canonical HTTP list/detail routes share directory policy and safe JSON projection
  with `list_tenants`/`get_tenant`. Tool discovery and invocation consult the same
  Calls policy; foreign lookup stays concealed. Typed MCP schemas reject coercion,
  nulls, extra authority fields and excessive page sizes before repository access.
- Shared HTTP authentication preserves explicit-key precedence. Review caught that
  a connection bound inside `with` was lost in error branches. Two red tests proved
  missing browser response hooks, then the fix passed 39 Gateway and 18 Console
  focused tests, including existing spec-write CSRF behavior. Re-review passed.
- MCP tool tests first failed on empty discovery, missing scope enforcement and
  callback fault handling. Six focused tests now pass. A separate red regression
  identified ExMCP's request metadata injection; metadata is now separated from
  already-validated public arguments before invoking Calls. Unknown tool names
  never reach dependency tool telemetry. Exceptions/exits/throws return safe errors.
- Four Console tests verify real-key session revocation and HTTP/MCP directory
  parity across calls/full/platform access, paging boundaries, duplicate names,
  foreign lookup and empty results. Fixture setup initially assumed an empty test
  installation; corrected it to account for preexisting local bootstrap fixtures.
  Ordering assertions use controlled duplicate-name IDs rather than assuming the
  database collation matches Elixir's binary sort for unrelated baseline records.
- Two request-lifecycle tests prove admission release on request-owner death during
  authentication and tool work, plus termination of the blocked ExMCP handler.
  Session expiry/restart requires isolated-process acceptance because dependency
  public operations address its global manager; no global mutation was added.
- Source and tests are now stable for the full umbrella check. No UI route cutover,
  live provider test, external call or deployment occurred in this checkpoint.
- Stable snapshot passed all root completion commands: formatting, compilation
  with warnings as errors, strict Credo, unused-dependency check and `mix test`.
  Every umbrella application's suite reported zero failures; live/integration
  exclusions stayed enabled. The earlier compactor scheduling failure did not
  recur. No speech/source-cutover state machine changed, so Lean was not required.

## Shared call-spec authority

- Consolidated discovery and tenant resource policy in Calls.CallSpecAuthorization;
  read/write operations and safe catalogs consult it directly. Existing browser
  grants, trusted installation callers and tenant-service ownership are preserved.
- Canonical key authentication previously converted Settings platform authority
  into a tenant principal. Red tests proved platform-service-backed saves failed
  with 403. It now retains the authenticated platform actor; tenant keys remain
  unable to author platform-backed definitions, and legacy operator routes remain.
- Installation list reads now validate the tenant key and repository tenant
  agreement before projection. Four policy/list tests failed before the fix;
  the focused domain selection passed 67 tests and Gateway authority/write checks
  passed 15. Independent policy review found no remaining blockers.
- The broader spec HTTP/MCP checkpoint and stable full-suite verification are
  still in progress; this commit records the independently usable policy fix.
