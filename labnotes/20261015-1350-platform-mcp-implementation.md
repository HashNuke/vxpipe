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
