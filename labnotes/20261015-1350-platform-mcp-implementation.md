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

## Isolated MCP reference acceptance

- Added bin/test-platform-mcp with a separate loopback-only BEAM fixture. The
  official SDK exercises the actual Console endpoint, standalone Gateway and
  embedded prefix using synthetic key/storage adapters and production handlers.
- All seven reported groups passed: three SDK mounts, three selected official
  scenarios, and full BEAM restart/accelerated expiry/fresh recovery. The pinned
  conformance CLI lacks custom headers, so its scenarios use an explicitly labeled
  synthetic-header proxy; no OAuth or blanket protocol conformance is claimed.
- Review found a generic rejected-promise assertion could pass on the wrong error.
  It now requires the SDK's HTTP 400 and separately verifies JSON-RPC -32602 on
  the wire. The SDK reports HTTP status before decoding that error body. Global
  client cleanup now runs even after an assertion failure; re-review passed.
- Syntax/format checks and the complete runner passed after those changes. The
  runner starts no database, provider or umbrella application tree. It currently
  invokes read-only tenant tools; wider capability acceptance remains separate.

## Call-workflow prerequisite review

- Read-only review identified two mistaken design descriptions. Existing token
  issuance accepts 300–86,400 seconds, default 300; it does not allow one-second
  tokens. Existing variable validation checks supplied sections without coercion,
  leaves omitted sections nil, and does not materialize schema defaults. Updated
  the design to preserve these established behaviors rather than introduce a
  compatibility change under the MCP adapter.
- Existing tenant-wide idempotency storage can support web preparation as well as
  outgoing calls. The shared workflow must replay before selecting a newer
  publication and must not mint an unused token when creating a prepared call.
- Implementation remains open. The current full-suite run uses the stable spec
  snapshot; this review does not change application source during verification.

## Call-spec HTTP and MCP operations

- Canonical spec list/detail reads now use shared Calls operations for browser
  users, full tenant keys and Settings platform keys. Shared projections preserve
  existing HTTP source/summary shapes; writes still omit source. Provider/model
  catalogs accept browser sessions and opt-in bounded pagination while preserving
  the established unpaged response envelopes.
- Seven MCP spec/catalog tools adapt those same operations and safe projections.
  Schemas reject extra authority fields, coercion, nulls and excessive page sizes.
  Source updates append immutable drafts; publication remains explicit. Calls-only
  keys cannot discover or invoke these operations, and foreign IDs remain scoped.
- Four MCP tests first failed because the tools did not exist. Implementation
  exposed a PCRE/JSON-Schema regex incompatibility in ID validation; the shared
  ASCII hex escape now works in both engines. The publish fixture also needed its
  explicit local model-inference default to produce a publishable source.
- Focused verification passed 40 Gateway HTTP tests, four new MCP tests, 21 Console
  editor/catalog tests, and five persisted-key Console MCP tests. The latter cross
  MCP creation/publication with HTTP update/read/list for both full tenant and
  platform credentials, preserving historical source and concealed foreign IDs.
- Independent reviews of policy, HTTP adapters, MCP tools and final parity tests
  found no remaining blockers. Fast root formatting, warnings-as-errors compilation,
  strict Credo and unused-dependency checks passed. The stable full umbrella suite
  also passed: every application reported zero failures, including 649 Gateway,
  212 Calls and 328 Console tests (integration exclusions retained). No source
  changed during that run; live providers and telephony remained excluded.

## Read-error parity and session credentials

- A transport regression exposed MCP returning authoring errors for spec reads:
  missing tenants and unavailable storage differed from canonical HTTP. Shared
  Calls.CallSpecErrors.read_response now preserves the established read codes for
  both transports; write and catalog projections are unchanged.
- Valid MCP sessions still require Bearer authentication on every request, including
  initialized notifications. Cookie, query and body credentials are rejected before
  authentication storage access; a session ID grants no credential authority.
- Red: one expected HTTP/MCP error mismatch. Green: 36 focused Gateway tests,
  including existing request-owner cleanup coverage. Independent review found no
  blockers. This checkpoint does not claim raw TCP-disconnect cancellation.

## Shared published-spec call claims

- Calls now authorizes the actual browser, tenant-key or Settings platform actor
  before preparing a published spec. Incoming web entries produce prepared calls
  without minting unused tokens; outgoing entries retain their admission path.
- Shared atomic claims preserve existing digest bytes and the tenant-wide
  idempotency namespace. Replay precedes publication lookup, so later publication
  cannot alter an existing attempt. Missing keys still mean distinct creations.
- Token issuance resolves only the call's pinned eligible web entry or explicit
  web participant. Existing TTL, terminal/admission guards and single-use storage
  remain authoritative. No schema migration was needed for call claims.
- Red: seven Calls tests and three Persistence tests failed for missing shared
  functions. Green: all 219 Calls tests and 46 focused Persistence compatibility
  tests. Independent review found no domain/storage blockers. Transport adapters
  and their bounded outgoing request handling remain the next checkpoint.

## Platform-key account domain and audit

- Added a narrow Identity.ApiKeyActor for account operations. It has verified-key
  identity, not fabricated user/session grants. Role CRUD and password reset remain
  outside that authority; direct machine password-hash updates are denied.
- Account writes lock and revalidate the exact active tenantless platform key in
  their transaction. Trusted actor stamping excludes supplied audit identities;
  the audit row records its API-key FK and cannot record both user and key actors.
  Existing target-role, last-superadmin and session-revocation guards remain.
- Migration 20261015000300 adds nullable indexed actor_api_key_id and the exclusive
  actor constraint; system events may still have neither actor. Applied to the
  test database only; deployments must run migrations before account-key writes.
- Canonical account normalization preserves omitted update fields and strict
  enabled booleans. User/role pages are bounded; role options omit grants and reject
  filters their query cannot honor. Legacy browser query errors retain 422 status.
- Missing-API, privilege and transport regressions were reproduced before fixes.
  Green: 67 Identity, 53 focused Persistence and three Console tests. One separately
  selected local SQL integration test proves key revocation waits on the account
  transaction lock and later authorization fails. Independent review found no
  authority/audit blockers; its query-error and ignored-filter findings are fixed.
- Gateway HTTP/MCP account adapters are not part of this domain checkpoint.

## Call creation and token HTTP/MCP adapters

- Added transport-neutral Gateway.CallCreation over the shared Calls claim. HTTP
  preserves its response envelope and 201/200 creation/replay distinction; MCP
  returns only call_id. Both use actual browser/key actors. New web calls have no
  runtime/token effects, and only newly claimed outgoing calls release admission.
- Canonical optional-participant token issuance and the existing explicit route
  use the same pinned eligibility, TTL and storage workflow. Shared projections
  return the secret only in the intended token response; responses are no-store.
- Review found failed web-call replay receiving an outgoing error, a browser
  authentication exception escaping, and broad rescue masking CSRF rejection.
  Focused red tests reproduced each issue; guards and exception handling now keep
  web replay, safe errors and existing browser CSRF behavior intact.
- MCP inherited runtime configuration previously lacked outgoing transport options.
  Endpoint composition now supplies the shared configured runtime and allows
  explicit MCP overrides. Fake-dial wire tests prove outgoing creation/replay.
- The ordinary ten-second callback deadline was too short for the existing
  outgoing submission wait. Authorized create_call now has a configurable
  100-second default; other operations keep their prior bound. Accelerated deadline
  tests verify timeout cleanup and durable same-key recovery without another dial.
- Final focused Gateway selection passed 73 tests. Seven persisted Console tests
  pass across calls/full/platform keys, nested
  variables, canonical/explicit tokens, redemption, foreign/ended denial and
  browser CSRF/key precedence. Independent domain, adapter and deadline reviews
  found no remaining blockers. All seven isolated official-client acceptance
  groups and fast root format/compile/Credo/dependency gates pass. The final stable
  umbrella suite remains pending while subsequent account adapters are implemented.

## Whole-call hangup design review

- Wrote docs/call-hangup-lifecycle.md while the account checkpoint's full umbrella
  suite ran against frozen source. The design uses durable call-row intent,
  existing admission ownership and one bounded Gateway reconciliation path.
- Independent review found that existing archive facts and snapshots do not yet
  share a validated room/incarnation anchor. The implementation must establish
  this under the call-row lock before using archive evidence for recovery.
- Review also identified outgoing pre-start close rejection and carrier owners
  outside the engine subtree. The design now requires a narrow cancellation-close
  projection and explicit Gateway cleanup acknowledgement before reporting ended.
  An engine supervisor exit alone cannot prove remote carrier cleanup.
- Late started projections must retain intent and immutable incarnation binding.
  These are reviewed implementation requirements, not completed hangup behavior.

## Account HTTP and MCP acceptance

- Canonical account endpoints and five MCP tools now invoke the same Gateway
  input/actor adaptation and Identity operations. Settings platform keys become
  narrow verified-key actors; tenant/legacy keys cannot inherit account authority.
- Browser HTTP keeps session/CSRF behavior, explicit Authorization takes precedence,
  and both transports share safe account errors and projections. Partial updates
  retain omitted fields; role options paginate without exposing role grants.
- Gateway declares its direct Identity dependency; endpoint composition supplies
  the configured Identity dependencies to MCP without depending on Console.
- Focused missing-module tests were red before implementation. Eight Gateway
  account tests, 42 broader related Gateway tests and four persisted Console
  account tests passed. Persisted tests exercise actual login/session revocation,
  key-attributed audit, activation, pagination and malformed/unauthorized inputs.
- Independent review found no blockers. All five root completion gates passed
  against frozen source, including every default umbrella application with zero
  failures. No live-provider tests or real telephony ran. UI cutover and hangup
  remain incomplete; the milestone index now reflects actual tool progress.

## Exact room completion monitoring

- Named the incarnation supervisor by tenant, room and incarnation in the existing
  registry. The new engine monitor observes that exact supervisor through cleanup,
  including after RoomAuthority exits, without looking up a replacement room.
- Two red missing-API tests became green; 21 focused completion/lifecycle tests
  passed. The cleanup test holds an owned worker until an explicit acknowledgement
  to distinguish authority exit from whole-tree completion without sleeps.
- Independent review found no blockers. The API and lifecycle design explicitly
  distinguish orderly shutdown from killed/crashed supervisors; Gateway carrier
  owners still require their own cleanup acknowledgement. The full CallEngine
  suite passed 2,225 tests with zero failures (75 integration tests excluded);
  the next stable root verification remains outstanding.

## Durable call cancellation intent

- Added the actual-actor Calls request and narrow repository callback. The call
  row holds the first request timestamp; only a prepared call with no admission
  history, start or incarnation acquires immediate terminal evidence.
- Admitting/running/failed calls retain their state, failure and outgoing facts.
  Token issuance/redemption reject intent using the existing call lock, without
  reversing token/call lock ordering or deleting credentials.
- Red tests covered the missing domain/store API. Invalid UUID review reproduced
  an infrastructure-style error; noncanonical UUID review reproduced mutation
  followed by response mismatch. Both now return not-found before mutation.
- Green: 22 Calls tests, 57 Persistence compatibility tests and two tagged local
  SQL integration tests on separate connections. Lock barriers prove both
  cancellation-first and redemption-first ordering; rollback and failed outgoing
  unknown state are also covered. No external provider or carrier was contacted.
- Migration 20261015000400 is applied to the test database only. Runtime binding,
  reconciled cleanup and transport hangup are separate unfinished work.
- Final independent review found no blockers in authority, lock ordering, terminal
  evidence, rollback or the SQL race tests. Root formatting, warnings-as-errors
  compilation and strict Credo pass; the stable full umbrella suite is running.

## Generalized engine admission gate

- Extended the existing outgoing gate to all resolved plans through call_admission
  and generic admit/cancel APIs. Pending rooms retain owner monitors and readiness
  restrictions; release starts entries once with exact caller/token/incarnation.
- Legacy outgoing control/reasons remain compatible. Outgoing plans keep their
  submission acknowledgement; web/incoming plans do not invent that event.
  Contradictory generic/legacy options are rejected before entry startup.
- Four generic gate tests and one outgoing test failed before implementation;
  all 33 focused gate/outgoing tests passed afterwards. Independent review found
  no ownership/protocol regression, including after dispatch refactoring.
- Strict Credo initially rejected RoomAuthority at 818 lines. Moving cohesive
  gate dispatch into OutgoingAdmission reduced it to 792 without changing the
  threshold. Focused tests passed again; root formatting, warnings-as-errors
  compilation and strict Credo now pass. Full umbrella verification is running
  against frozen source. No source-cutover or speech state machine was changed.
- Gateway binding, carrier cleanup and recovery are still unfinished. These
  prerequisites do not expose the hangup API or mark its checkpoint complete.

## Admission binding and completion design refinement

- Read-only review during the frozen full suite selected a wrapper-preserving
  bind operation with no timestamp: the call-row lock orders binding; existing
  started projections retain actual event times. Incoming answer timing must not
  be replaced by an invented binding start time.
- Running web joins require an engine-side exact-incarnation check, not a
  snapshot followed by an unscoped join. Incoming cancellation must retain original
  carrier identity and activation context before answer submission can fail.
- Archive subscriber tests explicitly allow a close marked incomplete=false
  after a killed supervisor. Archive presence/quality alone cannot prove cleanup.
  Final carrier usage also currently routes through a potentially dead authority;
  the existing result-bearing, deduplicating usage persistence port is the minimal
  path for acknowledged final usage.
- A narrowly scoped Gateway cleanup owner must seal resource registration before
  completion, using the existing incarnation as generation. New managed calls
  defer terminal projection until resource acknowledgements, including when archive
  close precedes hangup. Lost tracking state stays unknown; no empty reconstruction.
- These refinements are implementation contracts only. No runtime changes or
  additional tests ran during this review; the full root suite remains in progress.
- Final document review clarified that managed cleanup metadata belongs in the
  binding transaction before release, and a late monitor returning noproc is not
  orderly termination evidence. Legacy terminal behavior remains explicitly
  compatible; new ownership guarantees are not retroactively claimed for old rows.

## Stable hangup prerequisite verification

- The combined frozen snapshot passed root format check, warnings-as-errors
  compilation, strict Credo, the complete default umbrella suite and unused
  dependency check. Every application reported zero failures; CallEngine reported
  2,230 tests, Calls 222, Gateway 674, Persistence 297 and Console 335.
- Tagged SQL race tests were selected separately and passed; live-provider and
  real telephony lanes stayed excluded. The working implementation remains short
  of runtime binding/reconciliation and UI cutover; the overall milestone is open.

## Scoped participant admission

- Added an optional expected incarnation to participant admission. The authority
  checks it inside serialized handling before participant or archive effects;
  registry replacement races cannot redirect the join to a new incarnation.
- Three regression tests failed for the missing API, then eight join/completion
  tests passed. The full CallEngine suite passed 2,233 tests with zero failures
  (75 excluded). Review found no blockers and suggested exact room cleanup in
  test fixtures; added it and reran all six join tests successfully.
- Existing unscoped API callers remain compatible. This prerequisite alone does
  not finish durable Gateway admission or whole-call hangup. Combined root gates
  will run against the next stable checkpoint with the parallel changes included.

## Durable admission and archive ownership

- Added wrapper-preserving Calls binding for web, incoming and outgoing claims.
  Persistence validates stored admission/carrier ownership and pinned plan under
  the call-row lock, then returns admit/cancel without changing lifecycle times.
  All started projections reject intent and mismatched incarnation.
- Binding began with 13 expected Persistence failures and a missing memory-port
  failure, then 13 Persistence/three Calls tests passed. Four local SQL transaction
  races prove both cancellation/binding and cancellation/token lock orderings.
- Archive review reproduced six failures: wrong-room acceptance, independent
  stream anchors, and conflicting legacy history. Both archive streams now share
  the binding transaction. Three more red regressions caught legacy start paths
  bypassing archive ownership; all three paths now use the same guard.
- Rechecking whole history per write would become quadratic. Migration
  20261015000500 adds a private false-by-default verification flag, set atomically
  after checking legacy facts and snapshots once. Matching verified writes avoid
  repeated scans; errors roll back both anchor and flag. Old writers must be
  drained during rollout because they cannot preserve this new invariant.
- The final Persistence selection passed 326 tests, including local integration
  cases. Independent binding/archive reviews found no remaining blockers. Root
  format, warnings-as-errors compilation, strict Credo and unused dependency
  checks passed. Combined full-suite acceptance remains a subsequent gate.
- Binding and archived ownership do not prove shutdown. Incoming gating,
  acknowledged Gateway cleanup, final usage and reconciled terminal projection
  remain required by the overall milestone.

## Web and outgoing gated admission

- Gateway now orders gated runtime creation, durable binding, synchronous started
  projection and gate release. Running joins bind the full claim and use the
  engine's exact-incarnation join API. HTTP carries the persisted start result
  instead of launching an asynchronous lifecycle projection.
- Cancellation, binding failure and pre-release start failure close only the owned
  gate and preserve lifecycle evidence. No session/provider startup occurs on
  those paths. Outgoing projection-failure replay preserves the admitting call
  and never redials. Existing wire success shapes remain compatible.
- Nine expected red tests preceded implementation; 48 focused Gateway tests then
  passed. Independent review corrected a malformed cancellation fixture and
  restored no-redial replay coverage, with no remaining production blockers.
- The fixtures now create real rooms so Session's exact monitor can be exercised.
  Incoming admission is deliberately still an open runtime checkpoint; this does
  not claim complete hangup/reconciliation behavior.

## Exact-room session lifetime

- Session installs a monitor for its exact room before successful issuance.
  Missing/stale bindings fail closed. Room DOWN closes normal, pending and bound
  sessions; retryable admission release retains a closing supervised owner.
  Issuance, claim and connection binding normalize concurrent session shutdown.
- Five lifecycle tests reproduced missing issuance/DOWN cleanup behavior; two
  synchronized request-versus-shutdown tests reproduced escaped exits. Trace
  barriers confirmed requests reached the stopping Session, without sleeps.
- Initial 10 Session tests passed. Broader Session/endpoint/human-only/transfer
  WebRTC selection ran 101 tests with one failure: a redundant test immediately
  recreated a room before Registry's asynchronous cleanup. Removed that fixture
  coupling; replacement isolation remains at the engine boundary. Final 27
  Session/endpoint tests passed, including all 12 Session cases. No live services.
- Independent review found no blockers. These monitors revoke credentials and
  release admission ownership; full resource-tree and carrier cleanup still need
  the planned cleanup owner and durable reconciliation.

## Combined admission checkpoint verification

- The clean snapshot at d0d1810e passed all five root completion commands:
  format check, warnings-as-errors compile, strict Credo, full default umbrella
  tests and unused dependency check. No source changed during that run.
- Every application reported zero failures: Identity 67, MCP 37, Providers 35,
  AgentRuntime 108, CallEngine 2,233, Calls 225, Gateway 688, Artifacts 20,
  Persistence 320 and Console 335. Tagged live-provider/real telephony lanes
  remained excluded; local SQL transaction races passed in the separate lane.
- Final archive tests also passed seven cases after adding explicit verification-
  flag success/rollback assertions. Changed documentation has no missing local
  link targets. No source-cutover or speech state-machine changes required Lean.
- Next incoming slice: prepare and retain activation context before supervised
  answer submission, then integrate gated binding and fail-closed started
  projection while preserving authenticated answered/media timestamps. Room DOWN
  during a blocked answer must retain original carrier identity for cleanup.
  Cleanup ownership, final usage, reconciliation and exposed hangup remain open.

## Retained incoming answer preparation

- Split incoming activation into prepare and submit. Preparation retains the
  original carrier binding, pinned service, media admission and usage before any
  answer request. Rejection returns finalized context for its future lifecycle
  owner; accepted and unknown submissions retain the existing public result.
- The existing activate wrapper preserves current callers and Twilio media URLs.
  Inspect output hides service credentials and media tokens. Incoming Leg still
  uses the wrapper; asynchronous answer and gated binding remain separate work.
- Three expected missing-API failures preceded implementation. All 21 focused
  activation, admission-adapter and ingress tests passed, including the final
  rerun. Independent review found no blockers. No real carrier calls were made.

## Canonical tenant, spec and account UI requests

- Moved tenant/spec/catalog/account requests and paginated role options to the
  existing canonical API. Updated account filter/input names and tenant list
  parsing. Added the already-public creation timestamp to both HTTP and MCP list
  projections so directory rendering uses one shared contract.
- Account membership editing still needs full role grants. The canonical options
  directory is primary; a separately authorized legacy roles read enriches only
  those returned IDs. Read-only users retain the existing grants-empty fallback.
  Role/service/key administration and other inventoried product migrations remain.
- Nine frontend red cases and one HTTP projection red case preceded the changes.
  Final checks: 759 frontend tests, TypeScript, ESLint, asset build, 13 Gateway
  tests, 11 persisted Console parity tests and seven reference-client groups pass.
- Headless Chrome inspected desktop 1280px and mobile 390px: tenant pages,
  account lists/role options, account creation and membership update/disable,
  plus spec directory/detail/provider catalogs all used canonical network routes.
  No horizontal overflow was observed. A default 120-second sandbox timeout
  interrupted the first editor pass; a bounded 600-second fixture completed it.
  Both fixture and browser were stopped and the sandbox released.
- Independent review caught the SDK fixture's exact old tenant projection. Its
  expected timestamp and HTTP/MCP documentation now agree; review confirmed the
  fix. The inventory records the migrated slice and remaining routes explicitly.

## Exact-incarnation cleanup evidence owner

- Added a temporary supervised owner for immutable call-incarnation cleanup
  membership. It seals registration, monitors the exact engine and resource roots,
  and requires the original registering caller's semantic acknowledgement before
  completion. Abnormal exits or acknowledgement-owner loss remain unknown.
- Original surviving owners may resolve uncertain semantic outcomes after orderly
  root exit. Completed timestamps are retained; lookup never creates replacement
  membership. Atomic observation supplies current state and change notifications
  for the future reconciler without database/provider calls inside the tracker.
- Six expected missing-API failures preceded implementation. Independent review
  found that ancillary binding fields could create duplicate owners; a seventh
  regression reproduced it before canonicalizing startup and lookup identity.
  Additional tests verify acknowledgement-owner death before/after confirmation
  and abnormal engine termination. All ten focused tests pass; follow-up review
  found no remaining blockers. Root format/compile/Credo/dependency gates pass.
- This is a prerequisite only: durable fresh-admission authorization, actual
  resource registration, final usage acknowledgement, reconciler persistence and
  post-persistence retirement still need wiring. An empty recreated tracker must
  never be accepted as recovery evidence. Full-suite verification follows.

## Next integration review

- Independent persistence review recommends private required/completed cleanup
  fields and a one-time reservation in the existing admission-binding transaction.
  Missing reserved membership remains unknown; a running/replayed bind cannot
  manufacture an empty owner. Completion must lock the exact binding and preserve
  the first timestamp. This is a design review, not implemented progress.
- Archive close is stored with both lifecycle projections in one transaction.
  Pending cleanup must defer ended without rejecting the fact, while preserving
  valid outgoing timing/outcome metadata. Review corrected wording that could
  have skipped those metadata updates after the fact was already committed.
  Outgoing close also needs its narrow pre-start cancellation path. Publication
  must be requested after cleanup commits because the earlier finalizer can stop
  on call-not-ended. Final usage needs retained immutable observations and explicit
  storage acknowledgement; today's best-effort reporter discards that evidence.
- The next UI slice can expose the four access-key administration routes through
  explicit Console-owned canonical route metadata, reusing existing controllers
  and domain guards. Any explicit Authorization must deny before session fallback;
  role/key/secret administration has no newly granted machine authority. Preserve
  the existing host guard before mount dispatch and avoid a Gateway-to-Console
  dependency. Roles and services follow this mechanism once verified.
- Review found existing policy mismatches to address in those later slices:
  credential validation permits read-only direct callers while HTTP requires
  write; align the shared operation with the stricter existing HTTP contract.
  Role detail/count composition needs actual-actor authorization, and full role
  listings need bounded pagination. These are pending requirements, not fixes.
- Incoming bootstrap review confirmed another integration requirement: seed an
  already-live carrier leg atomically when starting its cleanup tracker. Otherwise
  engine DOWN could seal and complete an empty tracker before registration. Capture
  the original acknowledgement caller before DynamicSupervisor startup; missing
  engine initialization fails closed while Leg retains carrier identity. This
  extension is still pending, and must precede incoming tracker integration.

## Cleanup and UI checkpoint verification

- The root run against production snapshot 1d014ca6 passed Identity 67, MCP 37,
  Providers 35, AgentRuntime 108, CallEngine 2,233, Calls 225, Gateway 701,
  Artifacts 20 and Persistence 320 tests. Console had one failure among 335:
  its exact canonical tenant-list assertion omitted the newly public timestamp.
- Updated that assertion using the persisted fixture's timestamp. The full Console
  suite then passed all 335 tests; no production source changed between runs.
  Repeated root format check, warnings-as-errors compile, strict Credo and unused
  dependency validation all passed. Review confirmed the exact assertion and
  corrected integration-document wording, with no remaining findings.
- Six changed documents have valid local link targets after correcting one stale
  call-creation source link in the inventory. The prior 759 frontend tests,
  types/lint/build, rendered browser checks and seven MCP acceptance groups remain
  valid for unchanged source. No live-provider or external telephony lane ran.
- Whole-call hangup remains incomplete: durable cleanup reservation/terminal
  projection, atomic incoming registration and asynchronous admission, actual
  resource/usage acknowledgement, reconciliation and public adapters remain next.

## Atomic initial cleanup membership

- Implemented the reviewed initial-resource interlock. `start_new/2` captures the
  admission caller before invoking DynamicSupervisor; tracker init installs its
  existing resource and owner monitors before processing any engine DOWN message.
  An already-live incoming carrier therefore cannot be omitted during startup.
- Three focused tests first failed for the missing API, then all 13 cleanup tests
  passed. They cover immediate engine completion with a live root, lost original
  acknowledgement ownership and missing exact engine. Independent review found
  no blockers. Incoming Leg still needs to select this API when managed admission
  is enabled; missing engines continue to leave cleanup evidence unknown.

## Canonical API-key administration

- Console now explicitly owns four canonical key-management routes. Gateway mount
  bypass uses router metadata only for those routes; host restrictions remain in
  force. Canonical and legacy aliases share the existing controller/Calls policy.
- Session-only authorization is checked before parsing: any Authorization header
  denies instead of falling back to a cookie. Existing CSRF and delegation limits
  remain intact, including foreign-tenant and platform issuance restrictions.
- Missing-route/client tests failed before implementation. A follow-up red proved
  the legacy alias also needed the pre-parser check. The final focused Console
  selection passed 36 tests; all 760 frontend tests, TypeScript, lint and build
  passed. Browser inspection verified list/targets 200, create 201, revoke 204,
  and dismissing the single-use secret. Synthetic fixture and DB sandbox stopped.
- Desktop rendering passed; the existing key table overflows at 390px. This URL
  migration did not change layout. Public HTTP documentation now states the exact
  session-only contract and existing fixed-size pagination, without extending
  machine delegation. Other service/role/UI migration remains outstanding.
- Independent review of canonical and final legacy-alias changes found no blockers.

## Durable managed cleanup reservation

- Added a separate managed binding operation preserving legacy callers. It uses
  the same row lock, stored claim and plan checks, verified incarnation and rollback.
  Only a fresh eligible admitting/unstarted call receives `:new`; `:existing`
  never authorizes replacing lost tracker membership. Running legacy calls cannot
  be upgraded by replay. Private fields are excluded from public write inputs.
- Migration 20261015000600 was applied to the test database. Constraints require
  verified incarnation ownership and order completion after creation/start.
- Archive closure now defers terminal projection for pending managed ownership,
  while preserving valid outgoing metadata. Additional red tests covered all
  three transports closing before start without intent and failed close preceding
  later cancellation. No started/end timestamps are invented by these paths.
- Expected missing-API and six closure-ordering failures preceded the fixes.
  Final 104-test Persistence selection passed, including separate-connection SQL
  reservation/rollback races; four Calls boundary tests passed. Exact files were
  formatted and independently reviewed with no blockers.
- This remains dormant until Gateway integration. Completion storage/retriggering
  publication, resource ownership, final usage and reconciliation remain required.
  Before failed-state recovery, check archive queue ordering: the narrow failed
  close exception intentionally does not admit earlier failed-call snapshots.

## Immutable usage retry timestamps

- Found a real final-usage retry blocker while reviewing carrier cleanup: the
  carrier clock creates millisecond timestamps, but Ecto reads microsecond precision.
  Structural equality rejected an unchanged retry after the first successful write.
- A focused regression reproduced `usage_observation_conflict`. Deduplication now
  compares the timestamp instant and requires every other observation field to
  remain exactly equal. It returns the existing stored row; no usage is counted twice.
- All five UsageStore tests pass, including one-row retry, changed outcome and
  changed instant rejection. Independent review found no blockers. This does not
  implement retained carrier observations or result-bearing final usage flush;
  those remain necessary before acknowledging carrier cleanup.

## Completion integration design review

- Independent source review clarified completion ordering: cancellation projects
  the observed cleanup time and API reason. Without intent, retain acknowledgement
  and project the normal archive close when available. Retry reevaluates intent
  while preserving the original completion timestamp and exact binding.
- Publication source/store currently accept failed calls without cleanup proof.
  Gate both on managed pending cleanup with a distinct retryable pending result.
  The existing finalizer stops on call-not-ended, so merely requesting publication
  after commit can lose a wakeup against an older exiting finalizer. A pending
  result keeps that owner retrying; successful completion retries still trigger.
- Verified archive queue behavior: EctoStorage discards call-not-started errors;
  rejected pre-close failed snapshots do not block indefinitely, but their loss
  must remain reflected in archive quality. This review is pending implementation,
  not evidence that completion/publication behavior has shipped.
- Follow-up review covers acknowledged cleanup still awaiting normal closure:
  managed nonterminal publication reads also stay retryable, preventing the same
  exiting-finalizer race. Legacy nonterminal handling stays unchanged.
- Reviewed the next final-usage API: retain each original full observation and
  require a retained terminal observation before explicit storage acknowledgement.
  Retrying a partial batch must reuse immutable values; persisted unknown usage
  does not establish carrier termination. Implementation remains pending.


## Managed cleanup checkpoint verification

- Full root verification passed Identity 67, MCP 37, Providers 35, AgentRuntime
  108, Calls 226, Gateway 704, Artifacts 20, Persistence 342 and Console 341 tests.
  CallEngine initially failed one replacement-room fixture; its rerun reproduced
  the same race in the second completion fixture. Both await exact supervisor
  DOWN, but public creation can briefly see a dead Registry entry afterward.
- Fixed only replacement setup in those two tests: start through the owning
  DynamicSupervisor and assert the acknowledged fresh incarnation, then exercise
  the unchanged public scoped-join/completion APIs. Retain exact teardown. This
  avoids making the test depend on asynchronous Registry cleanup; production
  public-create behavior was not changed. Independent review found no blockers.
- All eight focused tests passed; final complete CallEngine rerun passed 2,233
  tests. Production source did not change between the root run and reruns. Final
  root format, warnings-as-errors compilation, strict Credo and unused dependency
  checks passed. Five changed documents have valid relative link targets.
- Previously verified 760 frontend tests, TypeScript, lint/build and rendered
  key-management flows remain valid for unchanged frontend source. Local SQL
  races passed separately; no live-provider or external telephony tests ran.


## Retained final carrier usage

- LegUsage now retains its bounded original observation batch alongside unchanged
  live reporting. The explicit persistence operation requires terminal usage and
  an actual terminal observation, then checks each Calls storage acknowledgement.
  Only timestamp representation may differ; every other immutable field must match.
- Partial writes can retry the same retained batch, without regenerating values
  after provider identification or a duplicate terminal callback. Faults and invalid
  acknowledgements return a bounded unavailable result. Nil, unfinished or empty
  usage cannot fabricate success. Persisted unknown usage still means unknown
  carrier outcome; the resource acknowledgement is a separate future check.
- Four focused tests failed for the missing API. After implementation all 45
  selected Gateway usage, incoming activation/ingress and outgoing-leg tests passed.
  Independent review found no blockers; corrected a test title to state isolation
  from the live room rather than claim a room teardown fixture was exercised.
- Added exact verified room/incarnation checks for managed usage. A failed managed
  call accepts retained usage only with cancellation intent, preserving its state
  and terminal evidence. Legacy failures and missing intent still reject writes.
  Two storage regressions failed before implementation, then all eight UsageStore
  tests passed. Carrier-owner scheduling/acknowledgement integration remains next.
- Independent storage review found no blockers in exact managed ownership or the
  narrow failed-cancellation allowance; legacy behavior remains unchanged.


## Canonical service administration

- Moved 16 platform/tenant service, credential, telephony-application and authoring
  phone-number operations to explicit Console-owned canonical routes. Legacy aliases
  reuse the same controllers and session-only pre-parser credential guard. Existing
  CSRF, tenant membership, inheritance, cursor/truncation and secret projections stay.
- Direct credential validation previously accepted read-only actors despite HTTP
  requiring write. It now checks existing write permission before invoking the
  validator. Controllers map domain denials to 403 instead of unavailable errors.
- Updated all four frontend consumers, including onboarding's binding read and
  editor provider-number requests. Demo/sample mutations remain pending product
  workflows. Complete HTTP wire schemas and inventory are documented.
- Calls red23/1 and Console red19/17 preceded implementation; final selections
  passed 53 Calls and 48 Console tests. Nine frontend URL failures preceded updates;
  all 760 frontend tests, TypeScript, lint and asset build passed. Independent
  review found no blockers.
- Rendered Chrome verified platform validation200/create201/delete204, tenant
  directory200/validation200/create201/update200, and onboarding binding lookup200.
  Persisted synthetic session/storage and a fake validator avoided external calls.
  Desktop1440x1000/mobile390x844 inspected; mobile had no horizontal overflow.
  Browser and fixture stopped and database ownership released.
- Existing routing limitation: tenant pages render TenantServicesPage; tenant
  ScopedServicesApp and embedded telephony administration have no production route.
  Their canonical requests have endpoint/component tests, but no rendered coverage
  is claimed. This migration does not redesign or add a production page route.


## Durable cleanup completion and publication

- Added the trusted Calls completion operation and Persistence adapter. One row
  lock checks the exact tenant/call/room/verified incarnation and managed reservation,
  validates time ordering, and preserves the first acknowledgement on retries.
  Cancellation chooses the stored cleanup time and API reason without inventing
  startup; normal completion replays or awaits the normal archive close.
- Both publication reads and writes gate pending managed cleanup and managed
  nonterminal calls awaiting normal close. A retryable pending result keeps an
  existing finalizer alive across overlapping triggers. Successful completion and
  retry request publication after commit; failed persistence does not trigger it.
- Initial red selections failed for missing completion and incorrect publication
  acceptance. Review found ack→intent→archive-before-retry ordering, acknowledged
  failed pre-start close availability, and conflicting normal closes while pending.
  Focused red regressions preceded each fix. Both close orders now preserve API
  cancellation evidence; conflicting normal timestamps roll back instead of
  silently selecting the first stored close.
- A test initially supplied a millisecond timestamp to the older hangup-request
  fixture and hit its existing dump-precision limitation; the fixture now uses its
  established microsecond timestamp. Completion itself normalizes acknowledged
  timestamp precision and verifies immutable retries.
- Final focused verification: 135 Persistence tests including actual SQL locking,
  rollback, publication and legacy archive compatibility; six Calls/finalizer
  tests. All owned files formatted, no migration or public DTO fields added.
  Gateway resource registration, asynchronous incoming admission, acknowledgement
  scheduling/reconciliation and public HTTP/MCP hangup remain necessary.

Independent final completion review found no remaining blockers. It confirmed
transactional conflicting-close rejection, the narrow acknowledged-cancellation
late-close exception, immutable ownership/time, and publication retry gating.
The combined root verification is still running; focused results above are not
a claim that Gateway integration or the full hangup checkpoint is complete.

### Resource integration design review

Independent review selected supervisor-owned WebRTC registration before child
startup. Its early acknowledgement means no independent remote/usage obligation;
whole-root orderly termination is still required. Session acknowledgement follows
successful admission release, with retries and tracker-loss monitoring. Managed
admission must stay disabled until initial/transfer carrier resources are covered.
Incoming inspection also identified synchronous answering and one-second failure
retirement as incompatible with reliable late carrier cleanup. These are design
findings, not implemented resource coverage.

### Combined completion, usage and services verification

All five root gates passed on the frozen source through `ac1db7b0`: formatting,
compilation with warnings as errors, strict Credo, the default umbrella suite and
unused-dependency check. Default suite results: Identity 67, MCP 37 (3 excluded),
Providers 35, AgentRuntime 108 (8 excluded), CallEngine 2,233 (75 excluded),
Calls 230, Gateway 708 (8 excluded), Artifacts 20, Persistence 365 (27 excluded),
and Console 345 (19 excluded), all with zero failures. Focused SQL race evidence
remains recorded separately; excluded live/integration lanes were not represented
as default-suite passes. Local links in the hangup design and milestone are valid.

### Session and WebRTC cleanup registration

Four focused Session regressions failed on missing membership, missing private
binding/lifetime ownership, accepting lost/sealed trackers, and tracker loss not
closing credentials. After implementation all 16 Session tests passed. Three real
WebRTC regressions then failed because no supervision root was registered and a
sealed tracker still accepted an offer.

Sessions now register themselves before issuance, retain private binding and
tracker monitoring, and acknowledge only after admission release succeeds. A
successful release is retained across acknowledgement retries. Managed normal
sessions also monitor claimant/connection lifetimes. Tracker loss closes locally
without recreating membership. Public projection omits the private binding.

WebRTC registers the root supervisor before any children, acknowledges only its
lack of independent carrier/usage obligations, and still requires orderly whole-
root termination. Rejected registration returns Supervisor's `:ignore`; the
connection owner translates that into the existing startup-failed result.

The first combined run found incorrect normalization of DynamicSupervisor's bare
`:ignore` result, fixed directly. The second passed behavior assertions but exposed
a new fixture teardown race: raw `GenServer.stop` conflicted with independent room
shutdown. Only the new managed fixture now uses exact-incarnation `end_call`.
The final combined selection passed all 38 Session, real-WebRTC and tracker tests,
with no compile warnings. No production admission enables managed cleanup yet;
initial/transfer carrier and media coverage plus reconciliation remain required.

Independent Session/WebRTC review found no blockers. It confirmed registration
before effects, retained release/acknowledgement retry state, private projection,
whole-root completion requirements and tracker-loss handling. A documentation
grammar correction was applied before commit.

### Role administration and password-reset cutover

Moved five role routes and password reset to canonical Console session APIs with
legacy aliases sharing handlers, explicit Authorization rejection and CSRF.
Identity role detail/count now authorize the actual actor before exact storage
lookups. Full-role pages apply SQL limit/offset and stable name/public-ID order;
the UI requests one page and only selected full-role metadata for account editing.
Lightweight safe-role selectors retain their existing paged traversal. Restricted
metadata access preserves memberships and loading prevents premature saves.

Initial regressions: two Identity, two Persistence, five Console and three
frontend failures. Final focused results: 24 Identity, 19 Persistence and 29
Console tests passed. All 764 frontend tests across 100 files passed, together
with TypeScript, ESLint and esbuild. Exact owned Elixir files were formatted.
Independent review approved; its outdated fake backend list_roles arity finding
was corrected. The implementing agent verified the HTTP docs against source.

Rendered Chromium verification passed at desktop and mobile sizes: first/second
role pages, protected role controls, custom role create/update/delete, selected
role detail without a full directory scan, preserved membership on save, and
password reset. Canonical network requests returned the expected 200/201/204.
Browser and synthetic database fixture stopped; no live services were used.

### Media sockets follow exact room lifetime

Incoming carrier retention exposed a separate transport-lifetime gap: sockets
only monitored the carrier Leg, which now survives room shutdown until terminal
evidence arrives. Both provider sockets now monitor their exact room during init,
reject stale/unavailable rooms, and close on room DOWN independently of Leg DOWN.
This is prompt media shutdown, not cleanup-tracker completion evidence.

Four regressions failed before implementation. Real-room unit fixtures replace
the previous fabricated room bindings, including the observed Twilio HTTP socket
probe. The first green attempt found a test-only mismatch: the fake Twilio Leg's
state is its observer PID, not a map. Corrected that assertion; all 35 focused
socket/HTTP tests pass. Independent review approved the lifecycle change without
blockers. Incoming local carrier harnesses also passed with the socket changes.
Managed media/socket registration and durable cleanup remain open.

### Incoming admission gate and responsive carrier cleanup

Incoming admission now binds a gated room before answer preparation/submission.
The Leg retains the original configured service and authenticated carrier event
before any activation exists. Answer/end HTTP requests run as bounded supervised
work, cancelled on owner death, while authenticated callbacks remain responsive.
Start projection is persisted before gate release and only follows an actual
answered/media-start event. Usage transitions use the current owner state so a
late answer response cannot overwrite callbacks received during the request.

Initial regressions failed on missing binding/cancellation and blocked callbacks;
the first focused selection passed 24 tests after implementation. Local harnesses
then exposed socket lifetime coupling and old fixtures expecting a started room
before authenticated answer evidence. The separate socket checkpoint fixes that
coupling; harness fixtures now inspect the bound incarnation before startup.

Independent review found late-answer cleanup needed a queued retry, local stop
failure needed to retain retryability after authenticated carrier end, and empty
duplicate replay owners needed retirement without adopting existing effects.
Expected red regressions preceded each fix. Final review additionally found the
unprepared-activation branch discarded cancellation errors; two more reds cover
error propagation and an already-observed exact room shutdown. The private
room_closed? fact is set only by the exact room monitor, never by a missing lookup.

All 59 focused ingress, activation compatibility and local Telnyx/Twilio harness
tests passed with zero warnings. Exact owned files were formatted and independent
source/documentation review approved. No live provider or carrier was used.
Production still uses legacy binding; managed reservation/tracker integration,
final usage acknowledgement and reconciliation remain outstanding. The complete
root checks started on frozen source after this focused verification.

### Incoming lifecycle full-suite verification

The frozen root run passed Identity 69, MCP 37, Providers 35, AgentRuntime 108,
CallEngine 2,233, Calls 230, Gateway 728, Artifacts 20 and Persistence 367 tests.
Console reported two failures among 350 tests: its peer-socket fixtures supplied
fabricated room identities, now correctly rejected by production socket startup.
Only that fixture changed to create a real room and clean up its exact incarnation.
Independent review approved. The complete Console rerun passed all 350 tests;
production source remained unchanged. Across these runs, all 4,177 default-suite
tests passed (140 excluded); no live providers or external telephony were used.
Root formatting, warnings-as-errors compilation, strict Credo and the unused-
dependency check all pass after the fixture correction. No modeled speech or
source-cutover transition changed, so this checkpoint did not require Lean.

### Media tree and socket cleanup membership

Added private exact cleanup bindings to media ownership. The media supervisor
registers its entire root before starting children; provider sockets register the
actual WebSock process before frame handling. These local-only resources may
acknowledge immediately, but the tracker still requires orderly whole-root DOWN.
MediaSession independently monitors the tracker before setup. Tracker loss closes
both media and sockets without creating replacement membership.

Duplicate startup now verifies the existing full binding, socket, stream, original
tracker and actual root PID. It cannot adopt an untracked tree or a replacement
sharing the connection identifier. Private binding validation includes all four
tenant/call/room/incarnation fields; missing/sealed owners reject registration.

Eleven regressions failed in the initial 42-test selection. After implementation,
only four real loopback assertions failed because Bandit uses the orderly reason
`{:shutdown, :local_closed}` rather than `:normal`. Tracker snapshots already
reported complete correctly. Fixed the assertion and made the loopback fixture
return 404 to unrelated non-upgrade probes. The broader selection then passed all
99 tests: cleanup tracker, media admission/session, both provider sockets, local
carrier harnesses and four explicitly selected loopback integration cases.
Independent source/test review found no blockers. The loopback tests complete the
WebSocket close handshake and observe actual owner termination, not just callback
return values. Production admission still does not enable managed cleanup.
Root format, warnings-as-errors compilation, strict Credo and unused-dependency
checks pass for this slice. The earlier 4,177-test baseline predates these hooks;
the final milestone still requires a complete root test run on its final source.

### Tenant creation canonical API

The navigation client now posts to `/api/tenants`. Exact route metadata keeps
canonical GET discovery in Gateway, while canonical/legacy POST use the same
Console session handler. Both aliases reject explicit Authorization before body
parsing and retain CSRF, host and `tenants.write` checks. The shared Calls boundary
now returns forbidden for unsupported actors rather than raising a function-clause
error. Creation preserves its 201 response and creates no implicit keys or grants.

Two endpoint, one direct-domain and one frontend regression failed before the
changes. Final focused verification passed three Calls, 26 Console and 14 frontend
tests; TypeScript, lint, esbuild and formatting passed. Independent review approved.
Rendered desktop/mobile checks using a synthetic local database verified canonical
POST 201 and dashboard navigation while GET discovery remained 200. Browser and
database fixture stopped. Combined root format, compile, Credo and unused-dependency
checks pass. No live providers or external telephony were used.

### Incoming identity before binding

Incoming usage previously started only during answer preparation, so cancellation
or failure at the binding step had no retained attempt despite an existing carrier
leg. Identification now runs once after capturing the gated room and before
binding. It validates the service and retains a private binding/service/usage seed
without issuing media tokens or carrier commands. Preparation reuses that exact
local leg identity and observations. The Leg owns subsequent usage transitions;
a late answer result cannot overwrite callbacks with the initial seed. Cancellation
uses the retained local ID and original authenticated carrier control ID.

Three activation regressions and the strengthened cancellation regression failed
first: 25 tests, four expected failures. The final focused selection passed 55
tests covering activation, ingress and both local carrier harnesses. The existing
blocked-answer usage test also verifies connected/terminal observations survive a
late submission response. This is retention evidence, not durable final usage or
managed cleanup acceptance; those integrations remain open.
Independent source/test/design review approved this checkpoint with no blockers.

### Canonical call inspection and artifact reads

Six canonical session-only GET routes now serve the directory, spec-filter options,
detail, inspection polling, published JSON and streamed WAV. UI callers use `/api`;
legacy routes remain thin aliases. Exact method metadata leaves Gateway call-create
and join-token POSTs untouched. Every explicit Authorization header is rejected
before session fallback. Canonical downloads return JSON 401 without a session;
legacy download aliases retain their login redirect for compatibility. A narrow
artifact pipeline permits audio Accept negotiation without JSON-only parsing.

The shared inspection query owns metadata agreement and verifies tenant, call and
pinned spec identity before history access. Existing artifact ownership, streaming,
range and no-store behavior is preserved. No new key grants or MCP tools are added.

Initial reds: 30 Console tests with 25 expected failures and 37 frontend tests with
five URL failures. Final checks passed 38 Console and all 764 frontend tests, plus
TypeScript, lint, esbuild and formatting. Independent review approved. Rendered
desktop/mobile inspection using a synthetic persisted prepared call verified
canonical directory/filter/detail/polling 200 responses. Missing artifacts returned
private 404 with JSON/audio Accept headers; positive JSON/WAV/range behavior has
endpoint coverage. The current UI has no artifact links to claim rendered coverage
for. Initial browser fixture setup needed explicit archive/usage composition; the
corrected fixture, browser and database sandbox were stopped after verification.

### Outgoing cancellation ownership

Initial and transfer legs no longer exit when a carrier accepts an end command.
Both retain original carrier identity and terminal usage while cancellation runs
as bounded supervised work. Transfer timeout/disconnect abandon through the owner;
they do not force-kill a potentially submitted attempt. Late answer/media evidence
requests or queues another end, and partial known carrier IDs cannot be replaced
by a different callback. Media remains revoked while cancellation is pending.

Independent review found two drainage gaps: abnormal command-observer loss could
leave its HTTP child alive, and an early retention timer could be forgotten before
workers finished. Focused reds reproduced both; sticky unknown-drain state and
retained timer intent now prevent false normal retirement. Normal observer results
follow actual HTTP-task DOWN, and owner retirement waits for observer DOWN too.
Unidentified abandoned legacy attempts retain their existing bounded unknown
retirement; this is not managed cleanup success.

Evidence: initial 30 tests/three expected failures; first focused green 35.
Drainage/timer red selection 34/two failures; final broader selection 95 passed
after two AMD fixtures were corrected to send authenticated ended events rather
than assuming end acceptance proved termination. A partial-control identity red
selection had 35/one failure, then final focused selection passed all 40 tests.
Independent final review approved. No live providers or external telephony ran.
The next drainage alignment must install observer monitors before releasing work
to avoid conservative false unknown state when a fast observer exits before the
owner can monitor it. Tracker registration, private binding propagation, final
usage persistence and managed admission remain separate integration work.

### Combined ownership verification

Root formatting initially found one multiline clause in the Console inspection
query that the child formatter had left differently; root formatting corrected it.
Root format, warnings-as-errors compilation and strict Credo then passed. The
complete default suite ran 4,204 tests with one failure (144 excluded): outgoing
late-identity cancellation observed carrier termination but did not retire.
All other applications passed, including 2,233 CallEngine, 367 Persistence and
358 Console tests. The unused-dependency check passed separately after the test
exit prevented the command chain from reaching it.

The failure is consistent with the independently identified observer startup race:
a command can finish before its owner installs the monitor, producing conservative
`:noproc`/unknown-drain evidence. The next fix installs the monitor before releasing
work and verifies ordering at the adapter boundary. This run is not recorded as
green acceptance; combined verification must follow the fix and incoming drainage.

### Outgoing observer startup ordering

Two adapter-boundary regressions require the owner to monitor the actual observer
before dial/end effects begin. The red selection reproduced both failures and the
original full-suite late-identity failure: 37 tests, three failures. DialSupervisor
now starts a paused observer, installs its monitor in the original caller, then
releases work with a private reference. The observer monitors its owner immediately
and bounds startup waiting. Both dial/end paths retain the returned monitor.

All 42 focused tests pass, including the formerly failing late-identity case; no
warnings and exact-path formatting/diff checks pass. Root and independent subagent reviews
approved the ordering and ownership contract. Full combined verification remains
pending the concurrent incoming drainage and demo-tenant changes.

### Incoming command drainage

The incoming owner previously retired after carrier end plus room shutdown while
answer/end HTTP work could still be running. Three focused regressions reproduced
that behavior and abnormal observer loss: 19 tests, three expected failures.
IncomingSubmission now installs the owner's observer monitor before work begins
and sends results only after actual task termination. Leg retains observer state
until DOWN, preserves unknown drainage after abnormal loss, and uses one retirement
gate for room shutdown and timer events. Late answer results cannot mutate usage
after authenticated carrier termination.

The focused activation/ingress selection passed all 28 tests. A broader 58-test
run found one old Telnyx fixture expecting carrier termination to kill a still
blocked answer. The fixture now explicitly rejects that request, observes its
normal DOWN, then the owner DOWN while preserving the no-answer-effect assertion.
The final 59-test selection passes ingress, activation and both local carrier
harnesses, including answer results before and after terminal usage. Independent
source/test and final fixture reviews approved.
This checkpoint does not register carrier cleanup roots or acknowledge final usage;
those integrations remain open.

Root format, warnings-as-errors compile, strict Credo and unused-dependency
checks pass with the concurrent demo-tenant slice. Full combined tests remain
pending; the last broad failure has focused regression coverage as recorded above.

### Demo tenant canonical operation

The browser ensure-demo-tenant request now passes its actual Identity principal to
Calls.DemoSetup. Authorization runs before repository access; trusted bootstrap
authority remains a separate supported caller. Canonical and legacy routes share
session-only authentication, explicit Authorization rejection, CSRF and host
checks. The UI uses the canonical route; repeated requests reuse the durable
binding without creating implicit grants, keys or specs. Sample installation
remains a separate pending migration.

Expected red selections were Calls 4 tests/two failures, Console 7/three and
frontend 33/five. All selections then passed. TypeScript, ESLint, asset build,
root formatting/compile/Credo/dependency checks and independent review passed.
Rendered Chrome at desktop and mobile verified canonical ensure 200, service
binding 200, reload reuse of the persisted tenant key, empty services/sample
waiting states and no mobile overflow. Browser and synthetic database fixture
stopped. The public API and inventory documents match the implemented contract.

### Bounded cleanup recovery discovery

Added a trusted Calls scan and Persistence adapter for unresolved cancellation
intent and unfinished managed cleanup. The scan returns minimal ownership metadata
without decoding plans or loading secrets. Integer-key pagination uses a fixed
upper watermark per cycle, so unresolved old rows and continuous new insertions
cannot monopolize a traversal. Eligibility changes behind the cursor are picked
up next cycle. Already-ended records are excluded; failed/unbound intent and
completed cleanup with later intent remain discoverable.

Three Calls and three Persistence tests first failed for the missing API (a
duplicate fixture update field was corrected before the final expected red run).
All three Calls and 28 Persistence scan/completion/hangup tests now pass. Migration
20261015000700 applied the matching partial index to the test database. Independent
source/test/design review approved bounds, candidate selection, finite traversal
and plan-independent projection. This adds discovery only; the supervised
reconciler, actual carrier integration and hangup transports remain outstanding.

### Outgoing usage before preparation effects

OutgoingLegDialer now identifies a validated request/service and creates its usage
attempt before deadline checks or media reservation. Preparation reuses that
attempt, and a definite failure emits terminal usage without losing its identity.
Unavailable media storage returns a sanitized failure; invalid requests/services
produce no usage or media effects. The owner records successful reservation and
avoids revoking an unacquired token. Disconnect/abandonment preserves a failed
unreserved owner's result instead of touching unavailable media.

Initial red was 41 tests/four failures. Review found the later disconnect path
still attempted revocation; a follow-up 41-test run reproduced two failures before
the guard was narrowed to failed unreserved owners. All 51 focused tests now pass.
Independent final review approved the four-file delta. Managed registration and
final usage persistence remain integration work.

### Carrier final-usage protocol

Added owner-embedded CarrierCleanup state for exact existing-tracker registration,
immutable terminal usage persistence and original-owner semantic acknowledgement.
Storage runs under the existing admission task supervisor, waits for actual task
DOWN, and retries partial failure/timeout with capped backoff. Unknown terminal
usage is persisted, but acknowledgement separately requires known command drainage
and carrier-ended or definitive not-submitted evidence. Tracker loss stays
unavailable and cannot reconstruct membership.

Initial nine contract tests failed for the absent API, then passed. Independent
review identified a real window when the owner installed a deadline after spawning
the worker: owner death could leave blocked storage unbounded. The worker now
installs its own deadline before storage and cancels it locally after completion.
An owner-death regression covers the boundary. Final selection passes all 27
tests (ten helper, four LegUsage and 13 cleanup tracker), exact formatting and
independent final review. Both carrier owners still require integration; the
helper alone does not enable managed admission or hangup.

### Exact API-requested engine hangup

Added a dedicated trusted CallEngine.hangup_call/3 path with fixed :api_hangup
authority shutdown reason. Existing end_call/3 remains remote hangup. Tenant lookup
and the serialized incarnation check prevent stale requests from stopping a
replacement, with a bounded unavailable result for missing runtime. This remains
a runtime primitive; authorization, durable intent and cleanup evidence belong
to the higher-level workflow.

The initial focused selection failed twice for the absent API (22 tests). It then
passed 26 lifecycle/completion/admission tests. Independent review requested whole
supervision-tree evidence for the new path: parameterized the held-worker drainage
test as well. Final 27 tests pass. The authority exposes the semantic reason while
the root has its ordinary orderly auto-shutdown outcome. No modeled speech/source
transitions changed, so Lean is not applicable to this narrow primitive.

### Canonical sample installation

Moved installation orchestration from Console to Calls using the actual browser
actor and explicit existing demo-tenant key. Both tenant-creation and target
call-spec write grants are checked before storage; inherited platform services
also require their existing authoring permission. Save/publication retain the
actual actor. Installation never creates the demo tenant or issues a machine key.
The canonical route and legacy alias share session-only, CSRF, host and explicit
Authorization policy. The UI sends its known tenant and recognizes all six model
providers supported by the installer.

Replaced the first-directory-page sample search with a tenant-scoped first-revision
name query returning at most two matches. This preserves identity after rename,
detects ambiguous/edited samples without overwriting them, and resumes matching
unpublished drafts. Existing installer concurrency and credential-precedence
coverage moved from Console to owning Calls/Persistence tests; the old Console
installer was removed.

Expected red selections: Calls 2/two, Persistence 4/four, Console 8/one and frontend
8/four. The initial Console green run found a fixture using a disallowed default
host; the request now targets the existing localhost host contract. Final focused
selections passed nine Calls, 19 Persistence, eight Console and 41 frontend tests.
All 768 frontend tests, TypeScript, ESLint, formatting and asset build pass.
Independent source and documentation reviews approved. Rendered Chrome at desktop
and mobile verified canonical POST 200, three installed samples, reload/retry
reuse and no mobile overflow with synthetic Deepgram/OpenAI credential fixtures.
No provider was invoked; browser and sandbox stopped. Full root gates are running
against frozen source. Sample call/transfer workflows remain pending.

### Carrier integration design review

Read-only review during the frozen full-suite run identified required integration
edges beyond simply passing cleanup state. Managed incoming reservation must seed
its existing carrier before an identity failure can bypass ownership. Transfers
need their own exact room monitor. Generic post-dispatch adapter errors can follow
carrier acceptance, so failed state cannot prove no carrier. Retain a separate
dispatched flag and callback correlation for unknown outcomes.

Normal managed failed admissions also need exact-bound final usage storage without
a hangup intent; the current narrower exception would retry forever. The required
expansion preserves failed lifecycle/publication state and rejects legacy or
unverified/mismatched ownership. Tracker attachment failure/loss must retain
validated persistence context without rebuilding membership. Only independently
finished carrier/room/commands and confirmed storage can allow retirement without
acknowledgement, leaving durable completion unknown. These decisions and their
test boundaries are recorded in the lifecycle design; implementation is pending.
Independent incoming/outgoing planning reviews agreed on these obligations.

### Completion persistence ownership review

Found a recovery gap in external-worker completion: after storage commits, a
worker can die before retiring its tracker, while the completed row is no longer
in the pending scan. Independent review recommends the smaller solution: the
existing tracker owns its bounded final persistence task and retries immutable
completion until acknowledgement plus task DOWN, then retires. A surviving
tracker always retains retry responsibility; if it dies there is no orphan to
rediscover. This avoids adding registry recovery machinery or another process.

The reconciler still owns durable discovery and exact shutdown. It replays an
already-stored completion when later intent arrives, without requiring a retired
tracker. Calls retains stored-result validation and publication triggers. The
lifecycle design records failure tests and opt-in fresh-managed configuration.
This is reviewed design only; no runtime source changed during the full suite.

### Combined cleanup and onboarding verification

The frozen runtime snapshot passed all five root completion commands: format,
warnings-as-errors compilation, strict Credo, the complete default umbrella suite
and unused-dependency validation. The full run reported 4,245 tests with zero
failures (144 excluded). Application totals were Identity 69, MCP 37, Providers
35, AgentRuntime 108, CallEngine 2,235, Calls 239, Gateway 766, Artifacts 20,
Persistence 381 and Console 355. The formerly failing outgoing retirement case
now passes in the full run. Source stayed frozen throughout verification.

All 768 frontend tests and the recorded types/lint/build/browser checks also pass.
No live-provider or external telephony lane ran. This establishes a green combined
checkpoint for the committed prerequisites and onboarding installation; it does
not complete managed admission, reconciliation, hangup HTTP/MCP, sample call/
transfer migration or the milestone's final parity/documentation gates.


### Managed failed-call accounting

Removed cancellation intent from the narrow managed-failed usage eligibility
check. Existing locked tenant/call lookup, exact verified room/incarnation,
immutable deduplication and lifecycle immutability remain intact. Real telephony
initial plus failed/unknown terminal batches now persist and replay without
manufacturing cleanup completion. Legacy failed rows remain denied with or without
intent. This addresses ordinary managed preparation failure, which otherwise
would retry final accounting forever without an API hangup request.

Red: ten UsageStore tests with two expected call_not_started failures. Green:
ten UsageStore tests, then 66 usage/binding/completion tests passing. Independent
review approved the two-file runtime/test delta. Changed Elixir paths formatted;
combined root gates remain due after the parallel cleanup/sample slices stabilize.

### Detached carrier accounting

Validated missing/sealed tracker attachment now retains the original owner's exact
binding and storage options as detached helper state. Invalid bindings/options
never receive this state. A storage-only query confirms the matching immutable
terminal batch after successful storage plus actual task DOWN, including after
tracker loss. It rejects foreign owners, incomplete or changed usage and cannot
acknowledge or recreate tracker membership. Carrier/room/drainage proof remains
the integrating owner's responsibility.

Twelve helper tests passed after five expected red failures. Root and independent
agent reviews approved; malformed top-level and nested options have coverage.
Changed paths formatted and diff checked. Managed owner integration remains open.

### Tracker-owned completion persistence

Added explicit completion options to fresh tracker startup, leaving existing
prerequisite callers unchanged. Once all resource evidence is complete, one
supervised worker installs its deadline before storage. The tracker retains its
first timestamp and exact binding across bounded-backoff retries, including a
commit followed by worker death. It retires only after successful validated
storage and actual normal task DOWN, independently of the initiating requester.
Only success/failure crosses the tracker mailbox; full persisted calls stay within
the worker. No production managed admission or reconciler is enabled yet.

Six missing-start_new/3 reds preceded implementation. First combined tracker/helper
run passed 31 tests; after independently reviewed response minimization, all 19
tracker tests passed. Tests exercise requester death, a lost commit result,
blocked-worker deadline even after owner death, seeded semantic obligations and
success arriving before actual worker termination. The last case deliberately
injects the task protocol result using its reference to hold this boundary open.
Root and independent review approved; changed files formatted and diff checked.

### Bounded cleanup reconciliation

Implemented the restartable scheduler and separate exact-binding recovery operation.
One bounded page is retained; row tasks have configurable concurrency and install
worker-local deadlines before effects. A slot is released only after actual task
DOWN. Failed/timed-out rows advance the finite cursor and remain durable for the
next cycle; failed scans retry their current cursor with capped backoff. Wake hints
coalesce without abandoning current work. No trackers or rooms are recreated.
Normal pending cleanup without hangup intent never stops a room. Stored cleanup
completion with later intent replays its original timestamp through Calls.

Five expected missing-module reds preceded implementation. Six tests then passed,
including real local room shutdown, stale and unverified binding protection,
normal cleanup without intent, completion replay without tracker, blocked-row
fairness, current-cursor retry and deadline survival across reconciler death.
Independent source review approved; four Elixir paths formatted. The green command
was inadvertently launched from the umbrella root: it ran the six Gateway tests
and reported no matching paths for other applications, exiting zero. No broader
suite coverage is claimed for that command. Production application supervision,
configuration and hangup wake wiring remain pending with managed admission rollout.

### Outgoing managed-owner integration

Outgoing connector and supervisor now forward private cleanup scope/options. The
owner validates exact tenant/call/room and derived incarnation before usage or
carrier effects, attaches to existing membership and monitors the exact authority
before media/dial, including transfer owners. All reconstructed media bindings
retain that identity. A dispatched generic error stays unknown and correlated;
only no-dispatch or authenticated carrier-end proof can satisfy retirement.
Final immutable storage, actual command-worker DOWN and authority closure remain
independent requirements. Missing/sealed tracker attachment retains accounting
context. Tracker loss closes only this owner's carrier/media, without inventing
whole-call intent, and holds the owner until independent authority closure.
Normal ended transfer owners also retain membership until that closure. The
tracker's separate engine monitor still proves whole-tree completion.

Initial 48-test selection had seven reds; six directly exercised missing behavior
and one also had a media-fixture tuple destructuring error, corrected before green.
First green passed 60 tests; final selection passed 63 (51 outgoing, 12 helper),
including ten managed cases. Added verification covers invalid options before
usage, storage retry after preparation failure, and final accounting despite an
abnormally lost command observer without false acknowledgement. Root and independent
agent reviews approved; all six changed paths formatted and diff checked.
Private validation reuses CarrierCleanup's shared boundary instead of copying
bounds. Production admission opt-in remains absent until the complete rollout.

### Configured sample call and transfer cutover

Replaced stateful Console sample bootstrap with a stateless configuration adapter
and Calls-owned actual-actor workflows. No startup saves/publication, generated
machine key or global latest-call state remains. Call-only actors can reuse a
matching publication; creating/publishing requires the actual author's policy,
including inherited platform-service permissions. An internal expected-revision
check prevents a changed publication from silently preparing another definition.
Transfer takes explicit public tenant/call IDs and reads the pinned participant
routes; normal prepared/cancelled/ended eligibility still applies.

Canonical and legacy routes now share session-only, explicit-header rejection and
CSRF handling. The UI uses canonical URLs and public-ID transfer links, checks
returned call identity and requires a target before requesting transfer. Only the
exact disabled preparation sentinel permits development-room fallback; transfer
disabled shows setup guidance and never falls back. Old ambient-state tests and
fixtures were replaced with owning domain, storage and endpoint contract tests.

Initial reds: Calls one, Persistence three, Console three and five of ten frontend
cases. A publication-race guard and platform-policy HTTP 403 mapping also had
focused reds before implementation. Initial green attempts exposed fixture-only
key-count, prepared-transfer and memory-repository not-found assumptions; corrected
fixtures use real single-use token claim/start projections without runtime/media.
Final focused selections passed nine Calls, six Persistence and 20 Console tests.
All 770 frontend tests pass, with types, ESLint and asset build. An initial parallel
frontend run timed out in existing App.auth; that owning file passed 19 tests and
the bounded-worker full rerun passed without unrelated source edits.

Independent source/docs review approved. Browser checks at 1440x1000 and 390x844
verified canonical preparation 201, a real one-time claim behind a synthetic media
boundary, public-ID transfer link, canonical transfer 201 for that call, missing-
target guidance and no horizontal overflow. No microphone/Connect, media or provider
ran. Browser fixture/sandbox stopped. Combined root completion gates remain due.

### Incoming managed-owner integration

The opt-in backend startup marker establishes managed ownership before binding,
so even malformed or failed reservation responses cannot select legacy retirement.
Fresh exact reservations atomically seed the existing carrier owner; existing
reservations only attach to known membership. The owner retains the updated claim,
then allocates identity/usage before interpreting admit/cancel/error. Its media
binding carries the exact cleanup identity. Authenticated carrier termination,
authority closure, successful immutable final storage and command-worker DOWN all
remain required. Missing identity/usage and abnormal observer loss stay unresolved.
Valid tracker loss retains detached storage; independently completed resources may
retire without claiming a durable acknowledgement.

Initial red runs exposed fixture setup issues: an empty plan, then a scenario
requiring providers. A human/web plus human/phone gated fixture removed that
irrelevant dependency. Six valid missing-contract reds then preceded production
changes. First owning selection passed 35 tests. Broader selection had 66 of 67
passing, including all 30 local Telnyx/Twilio harness cases; its only failure was
an invalid-clock fixture that correctly fell back to real time instead of producing
nil usage. The fixture now explicitly returns nil usage. Final owning 37 tests
passed, followed by all eight managed tests after adding a tracker-DOWN teardown
barrier. Root and independent source review approved. Six paths are formatted and
frozen. Global enablement and outgoing scope propagation from incoming rooms remain
pending; no live carrier or provider was invoked. Combined root gates started on
the frozen runtime snapshot.

### End-command recovery review during source freeze

Root inspection and independent review found that both incoming and outgoing
owners discard end-command results and retry only when a late answer sets a
retry flag. Repeated exact engine stop cannot repair this after the authority is
already gone. Before managed enablement, add owner-held coalesced timer/backoff for
failed or uncertain end commands and submission-start failure. Retry only after
normal observer DOWN establishes command drainage; abnormal observer loss keeps
sticky uncertainty and suppresses overlap. Keep the original carrier control ID,
wait for authenticated adoption if absent, never redial, and cancel retries on
authenticated end. Accepted REST submission alone remains insufficient completion
proof. This is a reviewed integration requirement, not implemented behavior.

A read-only UI fetch audit found only inventoried session/navigation/dashboard,
editor-lookups and account-security helpers still using legacy UI paths. Updated
inventory wording for completed sample migration and canonical tenant projections,
and removed the stale classification of canonical call-filter options as a retained
private helper. Final legacy-controller/schema consolidation still needs audit.

### Combined carrier recovery and sample verification

The frozen-source umbrella run passed every application except one old Console
route-permission assertion: it still expected installation tenant-creation authority
for configured sample calls. The migrated workflow checks the actual actor's
call/spec authority after the authenticated route gate. Corrected that assertion
without changing production behavior; independent review approved. The complete
Console rerun passed 352 tests. Combined application evidence is 4,284 tests with
zero remaining failures and 144 excluded. No live providers or external telephony
ran. This is checkpoint verification, not completed hangup or final parity.
Root format, warnings-as-errors compilation, strict Credo and unused-dependency
checks also passed after the assertion correction.

### Legacy API consolidation

The remaining legacy tenant/spec/catalog and account product aliases now use the
existing session-product precheck, so an explicit Authorization header cannot fall
back to a browser session or parse malformed JSON first. Genuine session/navigation,
dashboard, editor-lookups and own-account helpers keep their existing routing.
Spec update/publication no longer add a read-permission precondition to shared
write operations. Account forms translate legacy membership names and full-form
defaults into AccountInput; shared AccountJSON owns their matching responses.

Red evidence: 53 tests with 17 expected failures. Final focused selection: 58 tests,
zero failures after exact formatting, independently reviewed. The fake creation
fixture's short password/non-UUID role was corrected to the already-existing
production requirements rather than loosening shared validation. Legacy omitted
enabled/membership defaults and nil email/role no-ops remain covered. Documentation
records alias compatibility, the completed UI cutover and the retained helper set.
No UI assets changed; final combined gates remain outstanding.

### Shared hangup workflow and transports

Gateway.CallHangup persists actual-actor cancellation through Calls before waking
reconciliation or requesting exact runtime shutdown. HTTP and MCP share success
and fixed error projections. Already-ended calls cause no new runtime effects;
missing/unverified/uncertain ownership cannot claim completion or recreate an
empty tracker. PreparedCall now exposes the private stored verification bit.
Tracker lookup/snapshot accept bounded timeouts and expose uncertainty even before
sealing, using the tracker-owned resource outcome policy.

Initial workflow reds and three persisted projection reds preceded implementation.
A separate regression exposed uncertainty hidden by an open tracker status. Final
focused checks passed 42 Gateway, seven Calls, 44 Persistence and eight persisted
Console tests. Expected struct equality fixtures now include the verified bit;
no storage behavior was loosened. Independent review approved, exact formatting
and diff checks passed. Real local persisted calls/full/platform parity covers
prepared hangup and rejection of its unredeemed token. No runtime media or live
service was invoked. Global rollout/full lifecycle acceptance remain outstanding.

### Carrier end-command retries

Incoming/outgoing owners now retain only an acceptance boolean until command
observer DOWN. Failed/unknown outcomes and command-start failures schedule one
correlated timer, initially 250 ms with backoff capped at five seconds. Workers
cannot overlap, and abnormal observer loss keeps sticky uncertainty and suppresses
further submissions. Authenticated end cancels pending retry work. Original carrier
control identity and first cancellation reason remain retained; no path redials.

Initial 79 tests had eight expected failures; first green passed 87. After a privacy
refinement and terminal-event suppression cases, 119 owning/local-carrier tests
passed, including both Telnyx/Twilio harnesses. Root review then found that explicit
late-answer retry had stopped reattempting a failed local cancellation. One focused
regression reproduced that gap; restoring close with the retained reason passed
34 incoming/managed tests. Timed retries remain carrier-command-only. Independent
review approved the final fix. Exact paths are formatted; no external services ran.

### Managed admission composition

Web/outgoing starts reserve durable cleanup and create their tracker before
started projection and gate release. Incoming/web/outgoing runtime options scope
only the supported outgoing connector with trusted call identity; arbitrary custom
connectors fail closed in managed mode. Legacy runtime options remain compatible.
Existing reservations cannot reconstruct trackers. Managed running joins require
open, non-uncertain ownership even if new managed admissions are disabled later.
HTTP uses the refreshed claim for both live and pending-transfer Session binding.
The ungated incoming compatibility wrapper rejects managed requests before effects.

Focused expected reds covered absent binding/scoping, unsafe running joins, missing
Session metadata and unsupported incoming/outgoing connectors. The combined group
passed 69 tests. A final guard test initially had an invalid fixture participant;
after correcting it, it reproduced actual unowned startup, then all 12 owning tests
passed with the guard. Independent review approved final ordering and compatibility.
Global configuration is a separate checkpoint; active durable lifecycle acceptance
and final root gates remain outstanding.

### Durable runtime enablement

One Gateway composition function now supplies managed admission options to native
HTTP and Console's embedded mount. Durable runtime configuration enables the
existing admission/archive backend in development and production, and one named
bounded reconciler independent of the native HTTP listener. Incoming defaults
inherit only archive/cleanup options; explicit overrides and custom handlers or
backends remain intact. No Gateway-to-Persistence dependency was introduced.

Gateway's four expected missing-composition failures and Console's missing-flag
failure preceded implementation. Five Gateway tests and 15 Console runtime plus
persisted MCP tests passed. Independent review approved, exact formatting and diff
checks passed. Final active lifecycle/client acceptance and root gates remain.

### Completion evidence audit

Reconciled the shared API, MCP schema/policy and UI migration checkboxes against
source, focused test records, browser evidence and an independent read-only review.
All 17 tools exist; each invocation authorizes independently of discovery. Canonical
HTTP and legacy aliases use shared Calls/Identity/runtime operations, while browser
session authentication remains distinct from explicit Bearer authority. Remaining
private frontend fetches match the documented compositional helper inventory.
Updated the tool catalog and route inventory to remove obsolete pending claims.
Final runtime/client acceptance, request-boundary stress evidence and root gates
remain unchecked; the milestone index remains incomplete.

### Full reference-client capability acceptance

Expanded the isolated official SDK runner from tenant-only adapters to all 17 tools
through each actual Gateway, embedded and Console mount. The fixture starts actual
application trees with shared local SQL sandbox storage, real bootstrap/Settings
keys and persisted revocation, rolling back data on shutdown. Native listeners and
background reconciliation remain disabled in this fixture; calls are prepared only.

The catalog expectation first failed against the old fixture. Initial expanded
runs found fixture-only assumptions about JSON key order and revoke return shape;
semantic comparison and the real :ok contract corrected them. Final seven groups
passed: all three mounts, three selected official scenarios, and restart/expiry.
Each mount verifies all17 operations, scoped catalogs, denied invocation, strict
arguments, safe result fields, revocation and DELETE. Private failure diagnostics
are suppressed by the runner. Independent review approved. Active resource cleanup
and password/token fault-log assertions remain separate; no live services ran.
