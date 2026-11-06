# Historical Integrations implementation checkpoints

This chronological research/work log records intermediate states and ephemeral
command session IDs. Statements that a process was running or a boundary was pending
apply to that entry, not the current implementation. Artifact names below refer to
local ephemeral files, not committed evidence. Use the current
[milestone](milestones/integrations-directory-and-tenant-mcps.md) and focused
checkpoint labnotes for current status and remaining acceptance gates.

# Implement integrations directory

- User authorized the full Integrations milestone implementation, replacing Services for built-in provider integrations and tenant MCPs. Work begins with T1; this is not a reduced milestone or a completed release.
- Preserved the existing uncommitted Storybook and specification changes. `bin/setup` completed dependencies, assets and both database migrations. No commits created.
- Added a Console-owned request boundary: compiled OTP application version from root VERSION, a closed public query parameter set, normalized global search, opaque cursors and HTTPS-origin validation. Runtime override is `VXPIPE_INTEGRATIONS_DIRECTORY_ORIGIN`; invalid values fail without echoing them.
- Added bounded anonymous HTTP transport, no redirects/retries, 1 MiB streaming cap, finite connection/pool/receive/request timeouts, conditional ETags and redacted errors. Compressed responses are rejected rather than decompressed without a bound.
- Added schema and semantic page validation: shipped schema compiled into the module (no runtime docs dependency), exact resource/version/query identity, pagination consistency, unique IDs, installed credential adapters and compatibility bounds. Invalid rows reject the whole page rather than corrupting server totals by filtering it locally.
- Console now directly declares existing umbrella dependency JSV; no dependency version or lockfile change was necessary. Initially suspected escaped version patterns, but decoded-regex checks and schema example tests proved the existing schema correct; left it unchanged.
- Red/green evidence: Request 4 missing-module failures then green; Transport 4 missing-module failures then green; Page missing-module failures then green; unavailable adapter regression failed against accepted page then passed; Client 3 missing-module failures then green. Combined focused suite: 14 tests pass (seed 811529).
- Corrected initial test fixture/path creation mistakes before interpreting behavior failures. The first real HTTP check revealed a Req configuration conflict that Plug mocks bypassed (`finch` and `connect_options` cannot coexist); moved connection options into Finch pool configuration before retrying.
- Read-only hosted API inspection for version 0.1.0 returned three MCPs and no native providers. External native catalog release requirement remains open. Live setup metadata uses singular `setup_note`, while the local proposal has `setup_notes`/`setup_url`; resolve normalization explicitly before UI consumption.
- Production facade/cache, browser version exposure, replacement routes/UI, tenant MCP persistence/preflight/OAuth/runtime cutover and release gates remain pending. Existing production Services routes are unchanged in this checkpoint.
- Root format, warnings-as-errors compilation, strict Credo and unused-dependency checks passed before the final transport configuration correction; repeat final checks. Full umbrella test session 8233 is running with seed 67304 and output in vxpipe-integrations-root-test.log; CallEngine passed 2292 tests, do not assume the remaining suite finished.

- Actual client live read succeeded after the Finch configuration correction: integrations total 3, all kind MCP. Added a tagged local Bandit/Finch regression covering the real HTTP adapter; combined focused plus local integration lane passed 15 tests (seed 935346). No third-party credentials or tool calls used.
- Next implementation seams verified: Console.Application currently supervises PubSub, telemetry and Endpoint (add a named directory cache/task supervisor here); Calls.OperatorServiceBindings.list owns permission-filtered effective native state; AdminServicesController.bindings attaches provider capabilities and webhook URLs. Production frontend is assets/src/App.tsx -> admin/TenantServicesPage.tsx, with canonical /platform/services and /t/:tenant_key/services routes. Replace this production path, not only Storybook NavigationServices.
- Initial root run ended with one Gateway cancellation failure and five directory errors due to mixed module versions: runtime config had loaded Request before its resource field was added, while later tests used the new Page module. Do not use that run as current-state acceptance. Starting the full suite before finishing edits was a verification mistake.
- Gateway child rerun exposed a real configuration boundary bug: shared runtime.exs cannot call a Console-only module. Replaced the startup check with standard-library URI validation so independently run umbrella children need not load Console. Gateway CallIngress whole-file rerun then passed 26 tests with original seed 67304.
- Started a fresh full umbrella run against the frozen implementation: session 15980, vxpipe-integrations-root-test-final.log. Poll this handle; do not restart on observation timeout. Final root format/compile/Credo/unused checks session 8913; no UI changes in this production-backend checkpoint, so no new rendered UI acceptance claim.
- Final focused/local HTTP lane passed 15 tests (seed 299631). Final format, warnings-as-errors compile, strict Credo and unused-dependency checks all passed. Fresh full-suite result remains pending; continue with session 15980 before asserting acceptance.

## Public cache and initial inventory facade

- Added a bounded public cache keyed by the full validated request (origin, immutable version, resource, normalized query/scope/pagination). It coalesces misses, expires/revalidates ETags, retries a bodyless 304 once without a validator, evicts old entries, and removes stale entries after failed refresh. Limits: 128 entries / 16 MiB serialized-term budget, 8 fetches, 64 waiters per key, 12-second worker deadline versus 15-second caller bound.
- Cache and Task.Supervisor share a named one-for-all restart boundary under Console. Worker-capacity exhaustion returns busy rather than crashing the cache. Initial tests caught and fixed a positive-only monotonic timestamp assumption; monotonic timestamps may be negative.
- Red/green: initial four cache tests failed without module; coalescing/hit test then exposed negative-clock bug; Console ownership test failed before supervision wiring; worker-capacity test failed with Task.Supervisor RuntimeError before recovery. Six cache tests now pass.
- Added NativeCatalog projection from the existing setup metadata intersected with Registry-resolved credential adapters. Credential-free Morse is excluded. Added Inventory with Calls authorization/status lookup before any public request, local Connected inventory, per-binding editing permission, independent public page/status join, no secret material, and separate native fallback rows (no invented remote pagination).
- Inventory red/green: five missing-module failures then five passes. Coverage includes forbidden access, unavailable local status failing closed, invalid tenant override preserved, public-parameter-only fetch and installed-native outage fallback. MCP rows cannot connect yet; T4/T4a own that gate and future MCP status joins.
- Added session-only /api/platform/integrations and /api/tenants/:tenant_key/integrations with exact route permissions and private/no-store responses. Endpoint test failed 404 before route implementation then passed authenticated Connected response, immutable version and anonymous 401 checks. Existing credential operations remain available; frontend replacement has not started.
- Verified all ten child Mix projects and root read the shared VERSION. Reconciled the original proposal's directory override spelling with implemented VXPIPE_INTEGRATIONS_DIRECTORY_ORIGIN.
- Important ongoing verification: session 15980 began before this cache/facade checkpoint, although Console tests execute late; report its result with that scope limitation. Focused cache/inventory/endpoint/native-services/local-HTTP suite is session 54824, output vxpipe-integrations-cache-focused.log. No frontend files changed in this checkpoint.
- Combined focused directory/inventory/endpoint/native-services/tagged local HTTP suite passed 40 tests. Root format, compile warnings-as-errors, strict Credo and unused dependencies passed. Full current Console suite from umbrella root passed 423 tests (22 excluded), seed/result in vxpipe-integrations-console-checkpoint.log.
- Prior root session 15980 finished: all non-Console apps passed, including Gateway 868 tests; two Console failures came from supervisor/router modules loaded before this checkpoint's edits (new default supervisor absent and route404). Current full Console rerun proves both fixed in current state; do not describe the older run as all green.
- Starting full umbrella verification after this checkpoint is frozen: vxpipe-integrations-cache-root.log. Do not change runtime code while that process is active; read-only planning/browser inspection is safe. Poll its returned tool session before proceeding with edits so new tests cannot race previously loaded modules again.
- Frozen-checkpoint full umbrella run handle: session 4879 (started after the 423-test Console pass). The implementation goal remains active; cache/facade are intermediate work, not the replacement UI or custom MCP end state.
- Frozen backend full umbrella session 4879 completed successfully (seed 369158), including 423 Console tests. No Elixir runtime files were edited during that run; new frontend work was independent of its loaded modules.
- User added explicit final requirements: keep milestone completion statuses maintained; independent GPT-6 Astra xhigh agent review after implementation; record every required fix as a milestone task; after implementation/review/fixes send pushnotify. CLI discovered at ~/.local/bin/pushnotify, not invoked for sending yet. No final review has occurred.
- Frontend in progress: strict inventory parser, debounced browser search and category/cursor URLs, preserved results/retry on paging failures, local/fallback rendering, and optional inventory slot reusing existing provider credential dialogs. Initial missing-module/import tests failed before implementation; six directory/parser tests and the credential slot interaction pass. Not yet mounted as the production Services replacement.

- Production routes now mount IntegrationsApp with category routes, authorized navigation, native credential composition and category facade. T3 is in progress, not accepted. Initial full frontend run had 22 failures from old Services assumptions; migrating them against production UI, not reverting the replacement.
- Found lost removal functionality in the new rows. Added an exact named-binding DELETE regression (failed due to missing control), restored removal with CSRF, permission/source checks and pending state, then passed focused tests. Read-only and inherited connections do not expose Remove. Existing native lifecycle tests now use explicit fixture responses for the inventory API and the real production route.
- Rendered production component fixtures in headless Chrome at desktop and 390×844. Verified successful removal empties Connected and an in-use failure retains the row with an error notification. Screenshots: vxpipe-integrations-production-desktop.png and vxpipe-integrations-production-mobile.png (local artifacts, not committed). Real Console at localhost:4001 redirects to installation setup; this fixture inspection does not establish authenticated backend/browser acceptance.
- Visual inspection found native row badges used the broad prototype capabilities. Added failing Google LLM-only badge regression, then supplied installed provider/model capabilities from the credential directory; focused tests, TypeScript and changed-file lint passed.
- Navigation label assertions migrated to Integrations. Combined inventory/parser/production composition/auth/navigation checks passed 46 tests. Remaining legacy App/onboarding coverage is still being migrated; no full frontend green claim.
- Root completion attempt first stopped on formatting in the category endpoint test. Formatted that exact file and restarted the five root gates (session 22772). No Elixir runtime edits while the suite runs.
- Native route migration now passes all 10 ScopedServicesApp tests against Integrations, including test/save separation, masked edits, exact binding mutation, failed removal, unsupported testing and expired-session retry. Onboarding migration passes all 8 tests and now verifies inherited Google/Deepgram rows are visible without removal controls.
- Full frontend run begun before the onboarding fixture update completed with 936 passed / 9 failed (124 files); eight failures are legacy App.test.tsx Services fixtures, and the ninth onboarding case subsequently passed in its focused rerun. Do not report the full suite green. Latest root run remains live in session 22772 (seed 698627); format/compile/Credo passed, tests are still executing.
- Completed migration of all remaining tenant route tests. New fixtures exercise the binding and integration facades. Named credentials retain their exact binding on PATCH, stored values stay masked, cross-tenant responses fail closed, and navigation ignores obsolete writes. Native dialogs prohibit closing during pending save; its test now asserts that established behavior and clears the draft on completion instead of assuming the retired dialog's close-while-saving behavior.
- Full frontend acceptance at this checkpoint: 124 files, 945 tests passed (vxpipe-integrations-frontend-green.log). TypeScript passed. T3 real Console authentication/outage/history acceptance and full milestone MCP support remain pending.
- T4 started with isolated MCP secret envelopes using the existing CredentialKeyring. Red: three undefined-module tests. Green: three focused tests (seed 685729) bind tenant/connection/generation/method/purpose, permit staged key rotation and reject platform/malformed/oversized input. Initial local function name conflicted with Kernel.binding/1; renamed before the passing run. No application supervisor or existing cipher behavior changed. Durable records and rotation batch integration remain pending.

- Added tenant_mcp_connections migration/schema, Calls MCPConnectionRepository port and encrypted Persistence.MCP.ConnectionStore. Private queries disable bound-data logs/telemetry. Tenant-row locking plus DB unique constraints serializes directory/endpoint identity. Replacement/revocation checks generation; revocation deletes ciphertext and catalogs. Re-encryption uses bounded SKIP LOCKED batches with old-key remaining counts and preserves generation.
- Database red/green: four undefined-module failures, then a stale-generation regression caught updating only the struct (Ecto did not persist generation). Fixed through changeset values. Added red tests for inspection leakage, caller-supplied initial generation and two conflicting duplicate identities; all now green. Nine cipher/store tests pass, seed 280737. Runtime snapshot inspection hides secrets. Invalid replacement preserves prior secrets/configuration.
- Test database migration 20261106000100 applied successfully. Storage is a trusted port, not yet an authorized public operation: endpoint canonicalization/network policy, static MCP probe, API/UI wiring, concurrency/restart acceptance and operational rotation command integration remain pending. The migration and storage task are partial progress toward T4, not full acceptance.
- Earlier root session 22772 ended exit 2 during evolving work; large output was truncated and cannot support a precise failure inventory or acceptance claim. A new frozen backend checkpoint is running in session 25939. Format/compile/Credo had passed immediately before the final storage edge-case fixes and are being rerun. Preserve the current backend until this run finishes; frontend full suite already passed 945 tests.

- Added docs/development/tenant-mcp-storage.md for ownership, identity/locking, envelope separation, rotation, rejected provider-row reuse and explicit incomplete gates. Added an open fix task to verify tenant override/restore controls remain available in Integrations; platform Edit authority remains separate.
- Current frozen root run: session 25939, seed 401294. Format, warnings-as-errors compile and strict Credo passed; umbrella tests remain running. Later tool chunks are saved as vxpipe-root-25939-part-*.log; the initial captured chunk is available in the tool-session store. Do not restart just because a poll has no new output. Backend source has stayed unchanged since this run started.

- Revalidated the previously running HTTP check from its terminal log: one tagged
  integration test passed, seed 806205; no test process remained live. It initializes
  and reads tools through real loopback HTTP without invoking any tool.
- The prior goal turn only located/reported documentation; resumed concrete T4 work.
- Added red/green saved-credential edit coverage. Both new tests failed as expected:
  omitted credentials were rejected and stale edits reached the probe. Calls now
  resolves the exact tenant/ID, checks generation before probing, and reuses secrets
  only for unchanged endpoint/auth method. Full replacement still goes through the
  repository generation check. Seven focused tests pass, seed 790565.
- Initial focused command used the root-relative test path incorrectly; reran from
  the owning Calls child before implementation. No test evidence claimed from that run.
- Updated milestone and storage documentation to distinguish implemented authorized
  static checks/API from outstanding modal, interop, rotation and OAuth acceptance.

- Continued T4a after revalidating root gate session 26423 was still live; did not
  restart it. Format/compile/Credo passed; full tests remain running in that session.
- Inspected installed ExMCP metadata primitives against the approved 2025-11-25
  authorization specification. ProtectedResourceMetadata drops resource identity
  and its challenge parser does not expose resource_metadata; OIDCDiscovery tries
  appended OIDC before the profile's OAuth insertion order. These combined discovery
  helpers cannot directly implement the required preflight contract.
- Added OAuthMetadata as a read-only adapter reusing MetadataFetcher (DNS/public-IP
  checks, address pinning, redirect/byte/time limits) and OIDC endpoint validation.
  It enforces exact issuer equality and OAuth insertion → OIDC insertion → OIDC
  appending. No registration/token call is present. Only supported metadata fields
  are projected; unknown/raw bodies never enter errors.
- Red: three tests failed for missing module. Green: three pass, seed 9885, covering
  issuer path sequence, terminal issuer mismatch and private-address rejection.
  An initial file-write command had an incorrect child-relative path and created
  no file; corrected before the red test. Complete resource preflight, total-operation
  lifetime/concurrency and UI integration remain open.

- T4a resource metadata adapter: wrote three failing tests (undefined module), then
  implemented credentialless endpoint/metadata GETs through ExMCP MetadataFetcher.
  Green: three tests pass, seed 61435. Covers challenge precedence, quoted commas
  in a separate challenge, authoritative challenge scope, path/root fallback,
  missing versus anonymous distinction, substituted resource and duplicate params.
- Added direct cowlib dependency in the owning MCP child (already locked at 2.20.0)
  to reuse its HTTP challenge parser instead of writing another grammar. No lockfile
  resolution change was needed. Metadata has exact resource equality, <=8 distinct
  validated HTTPS issuers and bounded scopes; raw body/provider errors are redacted.
- The module intentionally returns multiple issuers for the upcoming selection
  contract; it does not accidentally select the first or perform OAuth registration.
  Whole-operation lifecycle/concurrency, preflight authorization and UI remain open.
- Root session 26423 remains live at the latest poll; a focused full MCP suite was
  started separately after these new isolated metadata modules were added.
- Resource checkpoint verification: full MCP default suite passed, 51 tests with
  four integration exclusions. Formatting, warnings-as-errors compilation, strict
  Credo and unused-dependency checks passed; git diff --check is clean. These do
  not substitute for the still-running full umbrella suite or T4a acceptance.

- Preflight composition red/green: four tests failed for undefined module, then
  passed (seed 725389). Endpoint/revision accompany all outcomes. Multiple issuers
  produce issuer_required; supplied issuer must be advertised. Missing metadata
  triggers a no-auth initialization check; only its success suggests none. Failed
  initialization remains unknown; issuer-metadata failure is partial. No save,
  registration, token exchange or invocation occurs in this composition.
- Calls preflight boundary red/green: new test failed for missing operation, then
  eight management tests passed (seed 108438). Write permission and tenant existence
  precede probe; credentials are rejected; current session authority is rechecked
  before returning. Adapter results must match requested endpoint/revision.
- Root gate session 26423 still live. Call Engine (2292) and Calls (254) passed in
  that run, but Calls preflight was added after its Calls checkpoint. Do not use
  the eventual run as coverage for code it did not load; new focused checks apply.
- Whole-operation cancellation/concurrency/rate controls and Console routing remain
  required before exposing preflight. Module composition alone is not T4a completion.

- PreflightRunner red/green: three missing-module failures then three passing tests
  (seed 111782), covering capacity rejection, deadline and caller-death cancellation.
  Production bounds: eight jobs, 15 seconds, 500 ms tenant admission interval and
  at most 1024 recent tenants. Runner and Task.Supervisor share one_for_all ownership
  so a runner restart cannot leave its old task population unaccounted for.
- Found that ExMCP MetadataFetcher uses independent monitored DNS/HTTP workers.
  Added DiscoveryIO ownership wrapper; two missing-module failures became green.
  Combined runner/composition/IO tests: nine pass, seed 26478. Linked I/O workers
  monitor the preflight owner, so cancellation closes in-flight DNS/HTTP work.
- Added Console adapter and POST /api/tenants/:tenant_key/mcp-discovery, configured
  through the Calls port. API red was expected missing-route 404; green four tests
  cover session/CSRF, no platform route, private/no-store, revision and no save.
  Production UI is not yet wired to this route.
- Root session 26423 finished with exit 0. All five gates completed; app counts include
  Call Engine 2292, Calls 254, Gateway 868, Persistence 436 and Console 430. This run
  began before later preflight additions; it is checkpoint evidence, not full coverage
  of the final worktree. New modules/API have separate focused results above.

- Production frontend discovery adapter/hook red/green: missing-module import failed,
  then three tests passed. Requests debounce 350 ms, carry CSRF/session credentials
  only to the installation tenant API, and contain endpoint/revision/optional issuer,
  never MCP credentials. URL/revision changes abort and clear results immediately;
  late responses and mismatched backend revisions cannot prefill the new draft.
- Result parsing rejects unknown outcomes/methods and cannot suggest none from a
  non-anonymous result. Invalid HTTPS URLs and closed dialogs do not send requests;
  session expiry invokes the existing session callback. Retry increments request context.
- TypeScript passed initially; lint caught a control-character regex and unused mock
  arguments. Replaced the regex with character-code checks and typed the mock callable.
- This is an unmounted production hook foundation, not a visible UI change or browser
  acceptance claim. Modal integration, manual-field precedence, enabled custom CTA
  and rendered checks remain outstanding. Existing Storybook simulation is unchanged.

- CustomMcpDialog red/green: missing-module test failed, then three interaction tests
  passed. It uses production discovery/create APIs, validates active static credentials,
  clears credentials on URL/auth changes, preserves manual authentication through
  discovery, retains failed drafts, and only reports a validated successful response.
- Production static methods are bearer/custom headers/Basic/none. OAuth is explicitly
  pending T5/T6, with discovered OAuth messaging; the full approved OAuth workflow
  remains required. This component is not yet mounted by the live inventory CTA.
- Added a no-network Storybook fixture for the actual production component. Initial
  rendered inspection found missing workspace theme context in the fixture; wrapped
  it in StoryWorkspace and confirmed desktop 1280x900/mobile 390x844. Screenshots:
  vxpipe-custom-mcp-desktop-final.png and vxpipe-custom-mcp-mobile-final.png.
  Browser confirmed custom headers → Basic clears X-API-Key, and fixture anonymous
  Connect closes successfully with zero-tools status. Browser session closed.
- TypeScript and focused lint passed. No real remote HTTP, credentials or backend
  storage were exercised by Storybook; authenticated live Console acceptance is open.

- Confirmed previous full frontend run ended successfully: 951 tests / 126 files.
- Inventory MCP join red/green: two new tests failed before implementation, then
  inventory/endpoint suite passed nine tests after updating the endpoint fixture to
  provide its now-required local MCP repository. Connected stays local, directory
  results match directory identity/canonical endpoint, and outage retains top-level
  saved MCP metadata. Missing local MCP status fails closed before public fetching.
- Platform inventory explicitly skips tenant MCP loading. Public directory requests
  remain unchanged; tenant connection metadata is joined only after the public fetch.
- Frontend parser red/green: new test failed because MCP projections were absent;
  five parser tests now pass. Tenant ownership, required per-MCP status, generation,
  permission and tool count are validated. TypeScript passes. Row management UI is
  the next required step; this data boundary alone does not complete the UI gate.

- Saved MCP details red/green: storage and Calls tests each failed on the missing
  get operation. Added repository metadata get without decrypting the envelope;
  it excludes revoked connections and scopes the lookup by tenant/ID. Store suite
  passes seven tests; Calls suite passes nine, including reader permission and
  private-field exclusion. Catalog tools are projected only by the details operation.
- Console details route red/green: missing GET route failed, then five endpoint
  tests passed. GET /api/tenants/:tenant_key/mcp-connections/:id requires tenant read
  authority/session and returns the cached tools without network validation or secrets.
- Started full Console suite in session 36234 and format/compile/Credo/unused-deps
  checks in session 39965. Management dialog integration remains the next step;
  details API completion does not claim tools refresh or runtime integration is done.

- Full Console suite completed successfully: 434 tests, 22 excluded. This verifies
  the inventory/details checkpoint, before this turn's frontend management changes.
- Management dialog red/green: three tests failed for absent management controls;
  extending the production dialog made six create/manage tests pass. Saved credentials
  are never loaded into browser inputs, edits omit credentials unless replacement is
  selected, mutation generation follows successful responses, and stale saves retain
  the dialog with recovery instructions. Read-only mode omits mutation controls.
- Added cached Tools tab/search and refresh through the validated replacement path.
  Refresh rechecks initialization/catalog with saved credentials and advances the
  generation atomically. No success toast/message is added. A new regression failed
  when an invalid unsaved URL blocked refresh; fixed refresh to use the saved snapshot
  and preserve unsaved credential values. Seven combined tests now pass.
- Rendered actual management component fixtures at desktop 1280x900 and mobile
  390x844. Authentication/Tools tabs, masked saved-secret state and stable footer
  fit both viewports. Screenshots vxpipe-manage-auth-desktop.png and
  vxpipe-manage-tools-mobile.png. Added the shared Disconnect alignment class.
- TypeScript and focused lint passed. Live inventory button/row mounting and
  authenticated-backend browser acceptance remain required; this is fixture evidence.
- A final browser refresh click used a stale element reference during Storybook HMR
  and did not execute; the session was closed. No browser refresh-interaction success
  is claimed. The automated refresh regression passed; earlier rendered captures
  establish layout only.

- Live inventory mounting red/green: two tests failed before controls existed; six
  inventory tests now pass, covering create → local row → manage → disconnect,
  inventory refresh and read-only inspection with no create/disconnect controls.
  Platform remains MCP-free. Dialog state is tenant-bound so changing tenant unmounts
  the previous tenant's credential draft. Native-provider credential controls remain.
- IntegrationsApp passes the actual CSRF token and write authority into inventory.
  Saved MCP rows use Manage, never a disabled duplicate Connect. Closing management
  refreshes status/generation; successful create/disconnect closes and reloads.
- Added full production tenant inventory Storybook fixtures with in-memory APIs.
  Browser pass (desktop 1280x900/mobile 390x844) completed connect, local row, Tools,
  Refresh tools and Disconnect to empty inventory. Screenshots:
  vxpipe-tenant-mcp-desktop.png and vxpipe-tenant-mcp-mobile.png. Session closed.
- Fixed two test/fixture typing issues (unsupported role-query exact option and
  missing tenantName). TypeScript and focused ESLint pass. Full frontend suite is
  running in session 97704; await its terminal result before claiming success.
- Static MCP is now mounted in production routes. OAuth stays explicitly gated to
  T5/T6, listed-MCP recipe connection and authenticated backend/browser acceptance
  remain open. Fixture completion is not full milestone/release completion.
- Session 97704 completed successfully: full frontend suite 958 tests across 127
  files, plus TypeScript and focused lint. No frontend tests remain failing at this
  static-MCP wiring checkpoint.

- T5 research: inspected installed FullOAuthFlow/OAuthFlow/OAuthTransactionStore,
  PKCE, registration policy, HTTPClient/SecureHTTP and existing ClientMetadata.
  Monolithic flow starts its own listener and node-local transaction state cannot
  satisfy Console cross-node durable callback ownership. Recorded ownership,
  rejected alternatives and pending lifecycle contract in tenant-mcp-oauth.md.
- OAuthAuthorization red/green: three undefined-module failures then three passes,
  seed 627127. Reuses ExMCP PKCE/endpoint validation; requires S256/code capability,
  fixed installation callback, resource and bounded scopes. Random state/verifier
  remain opaque to inspection. Reserved/duplicate endpoint query keys fail closed.
- No OAuth route, registration or grant is exposed yet. Builder success is not
  attempt persistence or OAuth interoperability. Durable encrypted attempts and
  atomic claim before token redemption are the next T5 implementation step.

- Durable OAuth attempts: added migration/schema, opaque resolved result and
  transactional store. Tenant lock bounds pending attempts to eight; SHA-256 state
  lookup, row locking, expiry and authority checks protect single claims. Encrypted
  payload includes the immutable binding; successful claim erases its ciphertext.
- Verified migration terminal success and original three tests (seed 932241).
  Added missing-key/expiry/cross-tenant regressions. Missing-key test failed with
  invalid_oauth_attempt instead of credential_key_unavailable (seed 113148), then
  fixed transaction rollback to preserve the operational error. All 15 persistence
  MCP tests pass (seed 229875). Initial edit used wrong cwd and changed no files;
  reran with child-relative path before observing the red test.
- Root gates started in session 63141; results pending. OAuth callback, registration,
  grant lifecycle and cross-node/retention acceptance are still incomplete.

- Added MCPOAuthAttempts authorized issue/claim boundary and repository behaviour.
  Principal identity overrides supplied user/session fields; current session and
  write permission are refreshed before repository calls. Tests first failed with
  the absent module (3 failures), then 12 focused Calls tests passed (seed 271194).
- Format, warnings-as-errors compilation, strict Credo and unused-dependency check
  passed (session 97203). Root suite session 63141 remains live; it began before
  the Calls boundary edit, so its result alone will not establish final coverage.
- Updated outbound OAuth documentation and milestone to distinguish implemented
  storage/authorization foundations from pending callback and token lifecycle.

- Reviewed RFC 9207 issuer response requirements. Added metadata capability
  preservation/type checking and opaque raw-query callback parser with duplicate
  rejection, bounded state/code/error and exact issuer checks. Errors are projected
  to fixed atoms; provider descriptions are discarded. Red: eight tests/five
  expected failures. Green: complete MCP suite 68 tests, zero failures, four excluded.
- Callback parser does not prove route integration or mix-up protection for servers
  lacking iss support. Recorded that remaining policy explicitly in OAuth docs.
  Root suite session 63141 still live; current static checks session 86914 pending.

- Added code redemption adapter using ExMCP HTTPClient and SecureHTTP. Rejects
  unknown fields/auth methods and malformed PKCE before network; fixes resource,
  redirect and grant fields; pins public destination and bounds HTTP. Returns
  opaque validated bearer token data and fixed errors, with no code retry.
- Red: four missing-module failures. Green: four focused tests (seed 59518), then
  entire MCP suite 72 tests, zero failures, four excluded. Removed deprecated test
  charlists. Format/compile/Credo/unused-deps passed (session 81697).
- Root suite 63141 remains live; Call Engine 2292 and Calls 259 tests have passed,
  but remaining app results are not yet final. Registration, callback orchestration,
  encrypted grants/refresh and full browser interoperability remain pending.

- Added explicit CIMD/DCR registration adapter. Uses existing ClientMetadata and
  ExMCP build_request with pinned SecureHTTP to support per-request initial token
  and fixed network policy. Server response cannot replace callback or silently
  change requested client authentication. CIMD performs no registration HTTP.
- Red: four absent-module failures. Green: four tests (seed 613951), then 76 MCP
  tests, zero failures, four excluded. Root format/compile/Credo/unused-dependency
  checks passed (session 95329). Full suite 63141 still running: Gateway 868 and
  the subsequent 20-test application have completed without failures.
- Connect wiring, durable registration reuse/expiry and real authorization-server
  interoperability remain pending; adapter tests are not end-to-end acceptance.

- Root gate session 63141 completed with exit 0. Full suite results include Calls
  259, Call Engine 2292, Gateway 868, Persistence 442 and Console 434, all passing.
  This run began before the later protocol adapters; their changed application
  suite has been rerun separately rather than claiming the old run covers them.
- Added OAuthPreparation composing actual metadata discovery, selected issuer,
  pre-registration capability checks, CIMD/DCR and authorization construction.
  Rejects browser endpoint overrides and unadvertised issuers. Red: four missing
  module failures. Green: four focused tests (seed 52335), full MCP 80 tests,
  zero failures/four excluded. Format/compile/Credo/unused-deps pass (session 3409).
- Remaining: bind this preparation through Calls/Console to durable attempts before
  browser handoff, then callback/grant persistence and runtime integration.

- Added Calls OAuth start sequence and private neutral PreparedMCPOAuth result.
  Current browser authority and tenant existence precede remote preparation;
  installation identity is resolved before/after remote work. Changed identity
  rejects persistence; fresh principal check precedes issue. Browser handoff occurs
  only after issue succeeds. Unknown preparation errors are redacted.
- Red: six tests/three expected missing-start failures. Green: full Calls suite
  263 tests, zero failures (seed 67439), including installation-change rejection.
  Format, compilation, Credo and unused-dependency checks pass (session 44366).
- Still no Console protocol adapter/start route: next checkpoint must bind the real
  preparation result to encrypted attempt attributes/secrets and installation source.

- Wired tenant-only POST mcp-oauth start controller, exact tenant write route mapping,
  fresh installation identity read and runtime encrypted attempt/preparation ports.
  Port now receives tenant so protocol work uses bounded per-tenant runner. Console
  adapter projects all redemption inputs into private encrypted secrets, not JSON.
- Endpoint red: six tests/one absent-route failure. Green: six endpoint tests; seven
  Calls start tests (seed 556492). Format/compile/Credo/unused-deps passed (78389).
  Added actual protocol-composition projection coverage and started full Console
  suite 78045. Await terminal result before claiming that broader lane passed.
- UI OAuth remains gated. Callback route, grant persistence/refresh and runtime
  integration are still required; start endpoint alone is not a usable OAuth flow.
- Console suite 78045 completed: 436 tests, zero failures, 22 excluded. Includes
  real protocol preparation projection and start endpoint session/CSRF coverage.

- Added durable callback scope lookup: hashed state, current user/session, unexpired
  and unclaimed rows only. Does not decrypt or consume. Added Calls claim_callback
  to authorize the resolved tenant and claim against fresh installation identity.
  Production identity source now returns exact callback alongside origin/revision.
- Persistence red: seven tests/two missing-locate failures; green: all 17 MCP tests.
  Calls red: nine tests/two missing-claim_callback failures; green: full 265 tests.
  Format/compile/Credo/unused-dependency gates passed (session 49944).
- Callback controller/token redemption and grant completion are still pending.

- Added private Console completion adapter: issuer validation, single code exchange,
  then MCP initialization/catalog check. Failed issuer/check cannot produce connected
  metadata. Three missing-module failures became three passing focused tests.
- Added create_oauth persistence preserving the attempt UUID and encrypted initial
  OAuth credentials. Red: eight tests/one missing-function failure. Green: 18 tests
  across Persistence MCP lane. Format/compile/Credo/unused-deps passed (54578).
- Full Console completion suite started; callback orchestration, grant revisions,
  refresh coordination and OAuth connection replacement remain unfinished.

- Added Calls completion sequence with post-network identity/permission rechecks and
  UUID-bound encrypted initial connection save. Red: eleven tests/two missing-method
  failures; green: eleven focused tests, then full Calls suite 267 tests passing.
- Wired session-only callback GET, raw query parsing before claim, fixed errors and
  no-referrer/private-no-store redirect to tenant Integrations without credentials.
  Endpoint red: eight tests/two missing-route failures; green: eight endpoint tests.
  Format/compile/Credo/unused-deps passed (41506). Previous Console completion suite
  also ended successfully: 439 tests, zero failures, 22 excluded.
- UI remains gated pending refresh, mix-up policy for non-iss servers, real OAuth
  interoperability and runtime integration. Callback route is not full milestone
  completion, and independent final review/pushnotify are not yet due.
- Latest Console suite 51071 finished: 441 tests, zero failures, 22 excluded.

- Added OAuthGrantStore with encrypted durable refresh claim and independent grant
  revision. Database row lock serializes admission/rotation; current configuration
  generation and claim ID fence stale workers. Expired claims are not retried.
  No schema migration needed: grant state remains authenticated in the connection
  envelope, and existing key rotation preserves it.
- Three missing-module failures became three focused passes (seed 970001); broader
  persistence MCP lane 21 tests passed. Added token-field/omitted-refresh regression
  coverage afterward. Format/compile/Credo/unused-deps passed (54558).
- Cross-connection/node race acceptance and network refresh orchestration remain
  pending. Root callback suite 89694 is still live, not restarted.

- Added refresh grant HTTP request with closed saved resource/client/token fields;
  no retries. Added permanent failure fence in grant store. Both focused additions
  failed before implementation; green MCP suite 81 tests, persistence lane 23 tests.
- Added trusted Calls refresh coordinator and Console token projection, configured
  runtime ports. Two missing-module failures became two passing coordinator tests;
  adapter projection check verifies absent refresh token is omitted rather than
  erasing the current token. Static gates pass (85951).
- Runtime credential resolver has not yet invoked this coordinator. Multi-node race
  and real provider interoperability remain required acceptance work. Root suite
  89694 remains running; no completion/review/notification claimed.

- Inspected runtime ConfiguredNames/ApplicationConfiguration/IntegrationCatalog,
  editor lookups, IntegrationOwner/Executor and ExMCP HTTP auth-provider behavior.
  Existing hook retains old headers on get_token failure and can challenge-retry;
  documented why direct hook wiring cannot satisfy fail-closed invocation policy.
- Added pinned runtime resolver with one refresh/reread and access-token-only OAuth
  result; rejects foreign/stale/revoked configuration and ambiguous claims. Four
  missing-module failures became full Calls suite green: 273 tests. Static gates
  pass (25756). Transport/catalog/picker cutover still pending.
- Root run 89694 is invalidated by concurrent edits: it loaded older MCP modules
  before later-added refresh tests (undefined refresh/2), and earlier Inspect
  consolidation before the new opaque refresh struct. Fresh focused suites pass;
  do not count that mixed-version run as current umbrella verification. Finish
  observing its terminal state, then rerun root only on a stable code checkpoint.

- Investigated custom transport/provider extension points. Added RuntimeAuthProvider
  guard: fixed exit before submission on resolution failure, method/token validation,
  no auth-challenge retry. Red: three missing-module failures; green: three focused
  tests and MCP suite 84 tests, zero failures/four excluded. Test uses actual ExMCP
  HTTP send_message with stale headers and confirms no DNS on resolver failure.
- Deferred SSE uses separate transport headers; provider token updates do not fully
  propagate there. Recorded this gap and left provider disabled in ClientOptions.
  Disabling streams would narrow the approved scope and is not the chosen fix.
- Format/compile/Credo/unused-deps passed (92950). Root mixed-version suite 89694
  ended exit 2 with one Persistence and one Console failure, both previously
  identified loaded-version/test mismatch. Fresh full root remains required at a
  stable checkpoint; do not treat this run as verification of current work.

- Further stream inspection confirmed SSEClient receives static headers only; no
  per-reconnect provider hook exists. Kept this pending rather than disabling SSE
  or claiming the guarded POST hook resolves all runtime authorization.
- Added SavedMCPCatalog and switched EditorToolCatalog default to tenant repository
  metadata/cached tools. Stable IDs, tenant/status/generation and descriptor checks;
  repository outage keeps native tools without application MCP fallback. Explicit
  embedded catalog injection preserves host-boundary tests.
- Red: four picker tests/two failures; green: full Calls suite 275 tests. Static
  checks started in 8886 and full Console suite in 23691. ConfiguredNames/publication/
  invocation are not yet cut over, so this is not complete T7 acceptance.
- Static gates 8886 passed; Console 23691 finished with 442 tests, zero failures,
  22 excluded. No rendered browser acceptance is claimed for the source cutover.

- Removed ConfiguredNames from packaged CallSpecEditorLookups for both member and
  installation-operator branches. Saved connection IDs include zero-tool servers;
  MCP read failure yields empty choices with tool_catalog.mcp_available false, while
  retaining native editor data. Shared test options now provide explicit empty MCP
  repository rather than touching application-config/global defaults.
- Red: eight lookup tests/one expected saved-ID mismatch. Green: full Calls suite
  276 tests. Root static gates 81891 and Console suite 74834 started.
- Traced next cutover: CallEngine.compile_call_spec and runtime_options both replace
  supplied registries with global CatalogStore snapshots. Tenant-specific snapshots
  must flow through both compilation/publication and call startup, not only picker.

- Prior Console suite 74834 completed: 442 tests, zero failures, 22 excluded.
- Added immutable catalog injection at the shared CatalogStore snapshot boundary,
  allowing compilation and startup to receive a tenant-specific catalog without a
  global publication. Red: compiler and live-call tests both failed at GenServer
  lookup for a snapshot. Green: 37 focused remote MCP/compiler tests pass.
- Initial parity assertion compared whole generated plans; participant activation
  IDs are intentionally fresh. Corrected it to compare resolved tool bindings.
  Live-call acceptance still executes the remote tool through the supplied catalog.
- This is a runtime cutover prerequisite, not the completed saved-record wiring or
  resolution of the outstanding SSE/token refresh boundary.
- Snapshot checkpoint static gates passed: format, warnings-as-errors compilation,
  strict Credo and unused dependency check. Diff whitespace check passed.
- Full umbrella suite started in session 37011, output at
  vxpipe-snapshot-root-suite.log. Poll to terminal before further source edits
  to avoid invalidating the run with mixed loaded-module versions.

- Runtime cutover audit while root suite 37011 runs: compilation is centralized in
  Calls.CallPlanCompiler, used by publication and PreparedCallFactory. Packaged
  startup is separately owned by Gateway.CallAdmission.CallEngineOptions.build/2
  for browser/incoming/outgoing admissions; legacy start_incoming/3 calls build/1.
  TrustedCall directly starts CallEngine and needs explicit embedded-host treatment.
- Added concrete T7 tasks for those startup paths and saved-record end-to-end
  acceptance. Compilation must remain secret-free and avoid token refresh; startup
  must recheck saved identity/generation so preparation cannot authorize a subsequently
  revoked connection. No source edits made while the umbrella run is active.
- Revalidated umbrella run 37011 as live (including a 50-second poll); it has
  completed Call Engine 2292 tests and Calls 276 tests with zero failures and is
  running Gateway. Identity 96, MCP 84, Providers 35 and Agent Runtime 108 also
  passed. This remains partial evidence until the process exits successfully.
- Confirmed CallSpec.ToolSelection persists explicit integration/tool choices;
  the compiler resolves each selection separately. The upcoming compilation
  snapshot can use metadata-only records without decrypting credentials or
  refreshing tokens. Native-only compilation must not acquire an MCP storage
  dependency. Preserve that boundary in the focused tests.

- While the Elixir umbrella suite continued, fixed an independent frontend-only
  regression: IntegrationsApp intercepted inherited native Edit and navigated to
  Platform, bypassing ScopedServicesApp's existing override flow. Red regression
  could not find Override for this tenant; removing that redirect restores the
  existing tenant-scoped modal and preserves named-binding selection.
- Green: IntegrationsApp and ScopedServicesApp 14 tests; TypeScript passes after
  correcting the new test's required tenantName fixture. Added InheritedNative
  Storybook state; initially missing last_validated_at was rejected by the real
  binding parser, corrected to null before browser acceptance.
- agent-browser desktop 1280x577 and mobile 390x844 inspection: inherited modal
  offers override/platform management, override opens an empty API-key field and
  tenant-owned credential notice. Screenshots vxpipe-inherited-desktop.png
  and vxpipe-inherited-mobile.png were visually reviewed. This does not claim
  real backend save/restore acceptance. No Elixir source changed during run 37011.

- Umbrella run 37011 exited zero: Identity 96, MCP 84, Providers 35, AgentRuntime
  108, CallEngine 2292, Calls 276, Gateway 868, Audit 20, Persistence 450 and
  Console 442 tests passed (normal excluded integration lanes). This covers the
  immutable-snapshot checkpoint before the subsequent compilation wiring.
- Fixed tenant-only permission edge: inherited rows report platform can_edit false,
  but tenant-write users must still open the existing override modal. Regression
  failed with a disabled Edit action, then passed after allowing that tenant-scoped
  action. Platform removal remains excluded. Twenty focused UI tests and TypeScript
  passed; extra named-restore acceptance then passed in the five-test app suite.
  Restore deletes only /api/tenants/demo/credentials/tenant-google and reloads the
  inherited binding. Mobile Chrome screenshot vxpipe-tenant-override-permissions.png
  visually confirms the tenant-owned empty credential form. Real backend save/restore
  remains unverified.
- Added SavedMCPCompilationCatalog metadata-only builder. Four red missing-module
  tests now pass: tenant isolation/no credential resolution, empty/zero-tool rows,
  invalid/duplicate identities and stale configuration/schema checkout. Snapshots
  intentionally have empty client_config and cannot open an authenticated session.
- Wired CallPlanCompiler for specs selecting MCP tools; publication and preparation
  share this boundary. Native-only specs avoid storage reads; explicit embedded
  catalog option is retained. Red publication test failed unresolved tool; green
  full Calls suite 281 tests. Missing saved selections cannot publish. Gateway
  startup and runtime credential wiring remain pending.
- Static gates 89959 passed (format, compile warnings-as-errors, strict Credo,
  unused dependency check); git diff --check passed. Console suite 56240 is still
  running at vxpipe-saved-catalog-console.log. No new umbrella run started;
  the prior successful run predates the saved-record compiler wiring.

- Console suite 56240 passed: 442 tests, zero failures, 22 excluded, covering the
  saved-record compiler change. Added MCPRuntimeCatalog as a private static-auth
  startup builder, not yet connected to Gateway. It validates prepared tenant scope
  before repository lookup, deduplicates selected connection generations, verifies
  resolved identity/status/generation, reconstructs the cached schema pin, and
  retains authentication only in opaque Integration.client_config.
- Red: four missing-builder tests. Green: scope isolation, metadata-only native
  plan, one private lookup for repeated selections, and stale schema/configuration
  rejection. A fifth test exposed an unwanted OAuth refresh when using the generic
  runtime resolver before static-method validation; replaced that path with the
  trusted repository read plus explicit identity checks and static validation.
  Unsupported OAuth now fails without refreshing. Full Calls suite: 286 pass.
- This builder is not active admission or per-request authorization. Gateway
  binding, active revocation and OAuth/SSE refresh remain open T7 requirements;
  no runtime completion claim is made from these startup-boundary tests.
- Runtime builder checkpoint static gates 45278 passed: format, warnings-as-errors
  compile, strict Credo and unused dependencies. Diff whitespace check passed.

- Transport investigation: inspected pinned ExMCP HTTP/SSE implementations and
  fetched upstream HEAD 56880c686404082d5340ff42d5295f12e08eff73 without changing
  checkout or lockfile. That HEAD is an ancestor of the pinned commit, not an
  available fix. SSEClient still builds reconnect headers from static state;
  Client pattern matches HTTP-specific state in several paths, so a generic wrapper
  is not enough evidence of preserved streaming semantics. No dependency edit made.
- Added operator MCP re-encryption task using configured ConnectionStore and shared
  CLI readiness/output. Red: three missing-task failures. Green: 26 MCP persistence
  tests including resumable static/OAuth grant rotation with unchanged identity and
  grant revision, rejected flags with no secret echo, and missing keys/store errors.
  Updated key-retirement docs to require both provider and MCP stores plus expiry
  or claim of outstanding OAuth attempts. Cross-node/retention gates remain open.
- Rotation static gates 94699 passed: format, warnings-as-errors compile, strict
  Credo, unused dependencies. The first Mix help lookup preceded development
  compilation and could not find the new task; after compilation, the same help
  command resolves and documents the intended CLI successfully. Diff check passes.
- Full persistence suite 71064 is running; output is
  vxpipe-mcp-rotation-persistence.log. Do not treat the focused 26-test pass as
  proof of the full suite until that process completes.
- Persistence suite 71064 completed successfully: 453 tests, zero failures,
  36 excluded. MCP rotation command checkpoint is green.

- Added bounded OAuthAttemptStore.prune: terminal rows are expired at/before one
  captured now or already claimed; select IDs FOR UPDATE SKIP LOCKED and delete
  only those rows in one transaction. No keyring/decryption required. Reports
  processed/remaining terminal counts and live pending-by-key counts.
- Red two missing-prune tests; green nine store tests. Added CLI red test (missing
  task), then mix vxpipe.mcp_oauth.prune using configured attempt storage and safe
  arguments/output. Retention is explicitly operator-scheduled; no automatic
  worker is implied. Documented why deleting terminal rows preserves replay
  rejection and why all credential stores must be considered before key retirement.
- Full persistence suite 30453 started at vxpipe-attempt-prune-persistence.log.
- Prune checkpoint verification: full persistence suite 30453 passed 456 tests,
  zero failures, 36 excluded. Static gates 8975 passed format, compile warnings as
  errors, strict Credo and unused dependency checks. Mix help resolves the new
  prune task after compilation; diff whitespace check passes.

- Added tagged MCP OAuth concurrency lane with committed isolated tenant data and
  separate Sandbox checkout(sandbox: false) workers. Each worker reports PostgreSQL
  backend PID; test asserts distinct sessions before releasing the message barrier.
  Workers are supervised and monitored; fixture tenant cleanup cascades records.
- Existing behavior acceptance (no implementation-first change): three attempt
  races pass (one-time claim, cleanup/live claim, pending cap); expanded to five
  tests with one refresh claim and refresh completion versus revocation. Final
  connection remains revoked regardless of serialization order. Invocation
  mix test --include integration test/integration/mcp_oauth_concurrency_test.exs
  passes five tests. This is multi-connection database evidence, not separate-node
  acceptance. No test uses sleep-based synchronization or live external services.
- Concurrency checkpoint static gates 14197 passed: format, compile warnings as
  errors, strict Credo and unused dependencies. Diff whitespace check passed.

- Directory Retry-After gap: transport previously discarded 429 headers and cache
  immediately allowed another public request. Added red transport/cache tests;
  both failed as expected. Transport now uses Req's date/seconds parser behind
  bounded input and exception handling, with 60-second invalid/missing fallback
  and 24-hour cap. Cache normalizes the external result to rate_limited and keeps
  one origin/deadline cooldown across queries and categories, preserving valid
  cached entries. Negative monotonic time is covered by the clock-controlled test.
- Green: 32 directory tests. Grouped decode_response clauses after the compiler
  flagged the new helper's initial placement. Full Console suite 22881 is running
  at vxpipe-directory-retry-console.log. No frontend rendering claim is made
  for these backend-only changes; the UI recovery acceptance remains pending.

- Full Console suite 22881 passed 444 tests, zero failures, 22 excluded; static
  gates 24688 passed. Added an overlap regression: two already in-flight responses
  returned long then short Retry-After; cache shortened the deadline and incorrectly
  started another request. Red test timed out awaiting the expected immediate
  rate-limit result. Fixed by retaining the maximum deadline for the same origin.
  Focused directory suite now passes 33 tests. No frontend source changed.
- Overlap fix static gates 9759 and diff whitespace check passed. Full Console
  evidence above predates only this final maximum-deadline adjustment, which is
  covered by the 33-test directory rerun.

- Reviewed RFC 6749 section 4.4 and the approved MCP authorization profile for Own
  client machine grants. Implemented OAuthTokenExchange.client_credentials as a
  distinct closed request shape: supported confidential Basic/POST methods,
  explicitly advertised grant, matching metadata endpoint, valid bounded scopes
  and fixed resource/client fields. No browser callback/code fields are accepted.
- Red: two missing-operation tests. Green: full MCP suite 86 tests, zero failures,
  four excluded. Tests observe both authentication shapes through the pinned HTTP
  request seam and prove invalid grants/public clients/endpoint mismatches/extra
  fields fail before HTTP. Result inspection is opaque; returned refresh tokens
  are discarded to avoid mixing this grant with delegated refresh semantics.
- Protocol foundation only: this does not enable the production form or claim
  full local-server interop, renewal, private-key JWT or persistence acceptance.
- Client-credentials static gates 39557 passed: format, compile warnings as errors,
  strict Credo and unused dependencies. Diff whitespace check passed.

- Transport credential checkpoint: the pinned ExMCP POST path already resolves
  providers, but GET/SSE reconnect and DELETE captured stale headers. Added a
  tracked narrow patch with revision/source/patch checksums, applied by setup and
  CI; no dependency revision or lockfile change. Rejected disabling streaming or
  wrapping a transport whose client paths depend on its concrete module/struct.
- Red tests reproduced skipped provider resolution on DELETE and SSE. Green:
  revoked credentials stop before DNS, DELETE remains best-effort so stream cleanup
  continues, and real loopback HTTP observes fresh tokens on initial SSE, reconnect
  and DELETE. MCP suite: 89 tests, zero failures, four excluded.
- Patch preparation tests: three pass against clean temporary local clones,
  including idempotence and refusal to overwrite unknown source/tampered patches.
  Setup tests initially failed because their fake dependencies lacked the new
  preparation step; added an isolated stub plus failure/compile-order assertions.
  Also normalized temporary paths for macOS symlink resolution. All 33 pass.
- Patched ExMCP compiled in dev and test. Production runtime provider/startup
  wiring is still pending; this evidence does not claim active cross-node
  revocation or full milestone acceptance. Build/release patch requirements and
  upgrade policy are recorded in docs/development/tenant-mcp-oauth.md.
- Static gates 27759 passed: format, compile warnings as errors, strict Credo and
  unused dependencies. CI now runs patch/setup tests and includes the patch in its
  dependency cache key, preventing reuse of a previous patched source state.
- Reconciled the still-unchecked compilation snapshot requirement against source,
  its four dedicated tests and saved-selection publication test: it is fulfilled
  by the earlier compilation checkpoint. Marked it complete with evidence rather
  than leaving a duplicate open task. Runtime startup remains unchecked.
- Full frontend verification: 127 files / 960 tests pass (session 98650,
  vxpipe-integrations-frontend-suite.log). Root suite session 31318 is still
  running against unchanged Elixir sources; seed 588816 has one MCP failure so far:
  cancellation test's default 100 ms startup acknowledgement timed out. Added an
  open milestone fix task. Let this run finish to collect other failures before
  changing Elixir code or rerunning; vxpipe-auth-patch-root-suite.log is the
  authoritative output. Do not treat focused green evidence as a root-suite pass.
- Stopped failed root run 31318 with SIGTERM after confirming its process and
  recorded MCP failure; its exit code is not a successful test result. Increased
  only the asynchronous check-client startup acknowledgement to 1 second; kept
  monitor-based cancellation/cleanup assertions. MCP suite now passes 90 tests,
  four excluded. Full root rerun remains required.
- Added red/green fixed-profile runtime-provider propagation and Calls transport
  projection. The client accepts only a validated RuntimeAuthProvider struct;
  construction performs no credential read. Calls returns only current OAuth
  access tokens or static method identity, preserving per-request generation/status
  checks. Both layers retain opaque inspection for provider state.
- Bound this provider privately into saved startup catalogs. OAuth uses no initial
  token header; refresh occurs at submission after schema checkout, so catalog
  construction cannot refresh a stale selection. Red/green tests verify runtime
  revocation and refreshed-token projection. Calls full suite: 288 tests pass.
- Gateway CallEngineOptions now attaches fresh tenant snapshots for packaged
  browser/incoming/outgoing starts; legacy incoming also uses build/2. Rejects
  mismatched call/plan tenant. Native-only startup gets an empty snapshot, preventing
  application catalog fallback. Focused red test reproduced missing startup binding;
  Gateway full suite session 16103 is running in vxpipe-gateway-mcp-suite.log.
- Static gates 47672 passed after runtime wiring: format, compile warnings as
  errors, strict Credo and unused dependencies. No frontend source changed.
- Gateway suite 16103 completed successfully: 869 tests, zero failures, 13 excluded.
- Found T1's HTTP 400 responses collapsed invalid_version/invalid_cursor/
  cursor_mismatch into invalid_query. Red transport test reproduced this. Added
  fixed string-to-atom mappings with no upstream diagnostics; invalid version uses
  native fallback and cursor errors preserve typed 400 responses through Console.
- Added invalid-page recovery to the production directory hook/view. Red UI tests
  reproduced the missing recovery action; eight component tests now pass, including
  both cursor errors and query preservation. Directory backend suite: 34 pass;
  TypeScript check passes. Fixed a missing can_connect field in the recovery
  Storybook fixture discovered during rendered verification.
- Chrome via agent-browser verified 1280x900 and 390x844 error states, then clicked
  recovery and confirmed results plus the original search. Screenshots are
  vxpipe-cursor-desktop.png, vxpipe-cursor-mobile.png and
  vxpipe-cursor-recovered.png. Browser session closed. Production components
  use in-memory responses in this Storybook; no external directory calls occurred.
- Static gates 69521 and diff whitespace check pass. Started full root rerun 62366
  against unchanged sources; output vxpipe-runtime-directory-root-suite.log.
  Poll that session before starting another umbrella run; no full-root pass claimed.
- Reviewed the remaining optional callback issuer behavior against RFC 9700
  sections 2.1 / 4.4.2, fetched from the RFC Editor. The current shared callback
  accepts missing iss if discovery did not advertise support. State and PKCE do
  not independently solve this multi-issuer mix-up boundary.
- Recorded a compatibility/security decision in outbound OAuth docs: require RFC
  9207 capability before registration/consent and exact callback issuer before
  redemption. Distinct issuer-hashed callbacks alone were rejected because the RFC
  describes their dynamic-registration bypass. Own-client authorization code uses
  the same requirement; machine grants do not have a browser callback. Enforcement,
  unsupported-capability preflight and regression tests are an open milestone fix.
- Root session 62366 remains live; its MCP lane passed 90 tests including the
  corrected cancellation acknowledgement. No Elixir source edits during that run.
- User asked whether existing Services/directory APIs should be repurposed. Inspected
  router, IntegrationsApp and ScopedServicesApp: native credential operations and
  modals are reused, and remote browsing uses the existing hosted API. Found a
  duplicate local inventory read: ScopedServicesApp loads services/service-bindings
  while IntegrationsDirectory fetches its joined inventory. Added a consolidation
  task rather than treating the new facade as a second native-management backend.
- Root suite 62366 completed with zero failures: Identity 96, MCP 90, Providers
  35, AgentRuntime 108, CallEngine 2292, Calls 288, Gateway 869, Audit 20,
  Persistence 456, Console 446. Normal tagged exclusions remain. The previously
  failing cancellation startup acknowledgement now passes in the root run.
- Implemented native API reuse by removing the eager Services settings request
  from Integrations browsing. On explicit native manage/remove, load the existing
  binding/settings API and use the existing modal and credential handlers. On
  mutation success refresh only joined inventory. Telephony retains its settings
  request for the existing application-management controls. No backend contracts
  or credential routes changed in this checkpoint.
- Red initial-load test caught the duplicate settings request. Focused 15 native
  UI tests pass after awaiting the newly asynchronous editor load; exact named
  removal, tenant override and restore remain covered. Whole frontend run exposed
  six more immediate-form assertions in App tests; updated them to await loaded
  fields without weakening credential/CSRF/inertness assertions. Final full run
  98848 is in vxpipe-native-lazy-frontend-final.log; TypeScript 6694 is pending.
- Browser desktop/mobile inspected the inherited native override form through the
  actual production wrapper; images vxpipe-native-on-demand-desktop.png and
  vxpipe-native-on-demand-mobile.png. Corrected the inherited Storybook's
  category response so it no longer produces a fixture-only outage notice.
- Final frontend suite 98848 passed: 127 files / 962 tests, zero failures.
  TypeScript 6694 passed. Chrome confirmation after the fixture correction shows
  no false outage notice and the inherited editor still loads; final mobile image
  vxpipe-native-on-demand-mobile-final.png. Closed the browser session.
  Root/static evidence above remains current for unchanged backend sources.
- Shared callback issuer checkpoint: red tests reproduced acceptance of missing
  issuer capability, registration before safe capability validation, legacy callback
  missing iss, and preflight suggesting OAuth for unsupported metadata. Fixed all
  with a shared authorization-code capability validator and unconditional exact
  callback issuer matching. Existing attempt boolean is accepted for compatibility
  but can no longer relax the issuer check.
- Preflight returns unsupported_oauth with no suggested method; production dialog
  exposes the unsupported state without anonymous fallback or browser handoff.
  Added a local UnsupportedOAuth Storybook. MCP suite 93 tests and Console suite
  446 tests pass; seven frontend discovery/dialog tests and TypeScript pass. Static
  checks 47996 pass. Root run 54822 is active in vxpipe-issuer-root-suite.log.
- Browser inspection is pending: agent-browser oauth-issuer open session 38379
  and snapshot session 33727 are still live but have not returned output. Storybook
  index confirms the requested unsupported-o-auth story ID. Poll these handles;
  do not infer browser verification from DOM unit tests or recreate a live session.
- Browser handles 38379 and 33727 terminated with daemon-unresponsive OS error 35;
  started scoped close 18471 and a fresh oauth-issuer-check browser session. Original
  session was not restarted merely because a poll timed out.
- Root 54822 has a GoogleSTSControllerTest IDLE-resumption failure: sys.get_state
  found the provider gone when delivering goAway (test line 502). Added an open
  milestone fix; the unrelated prior full-root pass is not proof of this run.
  Keep sources unchanged until the run completes, then inspect/reproduce the case.
- Full frontend run 21149 is active at vxpipe-issuer-frontend-suite.log.
- Frontend run 21149 completed: 127 files / 963 tests pass. Fresh Chrome session
  oauth-issuer-check loaded successfully; inspected unsupported OAuth at 1280x900
  and 390x844, with method unselected and Connect disabled. Images:
  vxpipe-issuer-desktop.png and vxpipe-issuer-mobile.png. Closed that
  session. The original daemon remained unresponsive to scoped close; identified
  its exact PID from oauth-issuer.pid, verified the agent-browser executable and
  sent SIGTERM only to that owned daemon (46905).
- Correction to the root-run failure diagnosis: the failed state query targets the
  old transport (`context.wire`), not the provider. goAway may legitimately retire
  that transport before the helper's separate query. Same-seed focused IDLE/BUSY
  cases pass; planned fix is synchronous fixture delivery acknowledgement, retaining
  provider/capability barriers and all resumption assertions. Root 54822 is still
  live, so source changes are waiting for its terminal result.
- Corrected the consumption document's stale status paragraph: production pages,
  static persistence and OAuth foundations are already wired; remaining acceptance
  and OAuth UI enablement are not complete. Existing Services operations are reused.
- Root 54822 completed with only the identified transport-helper failure; Gateway
  869, Persistence 456 and Console 446 passed. Making all fixture deliveries
  synchronous exposed intentional late-message cases plus the same unsafe barrier
  in STSSessionTest. Kept async delivery for those cases and added explicit
  deliver_sync for the two acknowledgement helpers. All 193 tests across the three
  fixture consumers now pass with seed 182445. No production state machine changed.
- Format, warnings-as-errors compilation, strict Credo and unused dependencies pass
  (89688). Full umbrella rerun 20722 is active at
  vxpipe-sts-delivery-root-suite.log; do not edit Elixir sources during it.
- Directory logo acceptance: the red test reproduced a broken image remaining after
  load failure. Added a neutral-icon fallback with state keyed to the image URL so
  a replacement URL retries. Nine directory tests pass; TypeScript caught an
  optional-property mismatch, which was corrected before starting full frontend
  run 61362. A BrokenLogo story uses a browser-blocked local port to simulate the
  image failure without contacting an external image host. Browser inspection is
  active in the integrations-logo session.
- Logo checkpoint verified in Chrome at desktop 1280x577 and mobile 390x844;
  neutral icon replaces the failed image, row text/actions remain intact.
  Screenshots: vxpipe-logo-desktop.png and vxpipe-logo-mobile.png.
  Closed integrations-logo. TypeScript and full frontend run 61362 pass.
- Updated the OAuth document's old optional-issuer wording to match the already
  implemented strict shared-callback policy. Documentation diff whitespace checks
  pass. No commits or completion notification made; milestone remains incomplete.
- Full frontend evidence: 127 files / 964 tests pass (61362). Root rerun 20722
  has passed Identity 96, MCP 93, Providers 35, AgentRuntime 108, CallEngine
  2292 (including the formerly failing helper) and Calls 288. Gateway and later
  applications are still running; keep the root acceptance task unchecked until
  the handle terminates successfully. Log: vxpipe-sts-delivery-root-suite.log.
- Root rerun 20722 finished successfully across all umbrella applications; marked
  the transport-helper fix complete. DCR expiry research then identified discarded
  RFC 7591 client_secret_expires_at metadata. Recorded the policy and alternatives
  in docs/development/tenant-mcp-oauth.md before implementing.
- DCR expiry red tests: two registration cases failed for discarded expiry and
  acceptance of missing expiry; Console completion/refresh reached DNS with expired
  secrets; token adapter rejected valid new expiry metadata. Preparation initially
  collided with its sibling test's per-tenant concurrency gate; assigned a distinct
  fixture tenant, then confirmed the intended nil-versus-zero projection failure
  before restoring the implementation field.
- Added strict issued-secret expiry validation (integer, zero or future timestamp),
  private projection into attempts/grants, and validation on all confidential
  token-grant paths. The expiry is excluded from token HTTP form bodies. Legacy or
  manual absence remains unknown and is not eligible evidence for future DCR reuse.
- Focused tests: MCP registration/token 14, Console preparation/completion/refresh
  9, persistence MCP 29 all pass. Persistence tests prove expiry survives rotation
  and cannot be overridden by refresh token fields. Static gates 45752 pass.
  Full MCP run 29229 passed; full Console run 51630 is still being checked.
  No production UI change in this checkpoint, so prior browser evidence is unchanged.
- Full MCP run 29229: 96 tests, zero failures (4 excluded). Full Console 51630:
  450 tests, zero failures (22 excluded), terminal exit 0. DCR expiry checkpoint
  is documented and checked; full umbrella run 22171 is active at
  vxpipe-dcr-expiry-root-suite.log. Do not edit Elixir sources during it.
  Registration reuse, reconnect replacement, Own-client workflow and final
  interoperability gates remain open; no final review or pushnotify yet.
- Expiry umbrella run 22171 completed with zero failures in every application.
  Reconnect/reuse tests were drafted outside the source tree while it ran and only
  applied after termination. Red evidence: repeated DCR instead of saved reuse,
  missing reconnect function/route, missing private registration provenance and
  discarded/unvalidated attempt operation. Logs: vxpipe-registration-reuse-red.log,
  vxpipe-oauth-reconnect-{calls,console,store}-red.log.
- Implemented backend reconnect on the existing generation-checked replace port.
  Calls reauthorizes, resolves only the tenant's OAuth record, strips tokens from
  registration input, checks the target after preparation and before redemption,
  and preserves directory identity on CAS replacement after token/MCP validation.
  Durable attempts authenticate operation as well as connection/generation; old
  absent-operation bindings remain create-only. No schema migration was needed.
- Added strict same-issuer/resource/callback registration reuse with current auth
  support and known confidential-secret expiry. Explicit initial token forces fresh
  DCR; mismatch/legacy metadata falls back to explicit fresh registration. CIMD is
  still installation-derived without registration HTTP. Provenance is encrypted.
- Session/CSRF reconnect route: POST /api/tenants/:tenant_key/mcp-connections/:id/oauth.
  Stale generations return 409. A red test found authentication changes during
  consent returned the wrong error; reordered target generation validation so that
  the callback stops as stale before redemption. Recorded the fix in the milestone.
- Focused lanes passed, then full Calls 296, MCP 99 and Console 451 passed. Persistence
  MCP lane 32 passed, including encrypted operation tamper rejection and an actual
  DB replacement fencing a previously claimed refresh while allowing the new grant.
  Static gates 40413 passed. Full umbrella rerun still required for this checkpoint.
- Local design/dependency review is recorded in docs/development/tenant-mcp-oauth.md:
  T4 storage and T5 attempts/expiry precede reconnect; no new credential store;
  preserve working credentials; no browser registration overrides; generation CAS
  fences callback races. This is not the requested final independent Astra review.
- Final static pass 29673 succeeded; git diff --check is clean. Full umbrella run
  99699 is active at vxpipe-reconnect-root-suite.log. Preserve its source snapshot
  until terminal output. No frontend behavior changed in this backend checkpoint;
  production OAuth choices remain gated pending interoperability and Own-client work.
  Milestone remains incomplete; final Astra review and pushnotify are not yet due.
- Reconnect umbrella run 99699 completed with zero failures: Calls 296, MCP 99,
  Persistence 459, Console 451 and all remaining umbrella applications passed.
- Return-context checkpoint: audited the callback's hardcoded root redirect and
  existing login return-path logic. OAuth needs a same-tenant Integrations allowlist
  and per-attempt context, so a global session "last page" is unsuitable. Recorded
  the ownership/dependency design in docs/development/tenant-mcp-oauth.md.
- Drafted tests while root 99699 was live, then applied them after termination.
  Red evidence: missing location validator, missing Calls/claim return_to field and
  no controller validation before preparation. Logs: vxpipe-oauth-return-*-red.log.
- Implemented bounded category/search/cursor validation, protocol-input stripping,
  trusted workflow propagation, authenticated attempt binding and success redirect
  restoration. Callback query parameters cannot replace the bound destination.
  Revalidate at redirect and fall back safely for absent/invalid legacy context.
  Added return_to to Phoenix parameter filtering; logs confirm [FILTERED].
- Focused tests: Console 12, Calls 19, persistence MCP 33 pass. Full Calls 296 and
  Console 454 pass; persistence MCP 33 passed again after configuration change.
  Format, compile warnings-as-errors, strict Credo and unused deps passed (37195).
  No frontend changes in this checkpoint. UI submission of current location,
  failure recovery UX and full browser/HTTP/database acceptance remain open.
- Full umbrella run 50822 is now active at vxpipe-oauth-return-root-suite.log.
  Preserve its source snapshot until terminal output. Milestone remains incomplete;
  no final independent review, completion notification or commits have been made.
- Return-context root run 50822 finished with one Gateway failure; all other
  applications passed, including Persistence 460 and Console 454. The failing
  CallIngressTest reused one call identity for cancel/error iterations while the
  previous owner could still retire. The same-seed focused rerun passed before
  changes, confirming intermittency rather than a deterministic regression.
  Generated separate cases now receive distinct setup identities and cleanup;
  all 27 focused tests pass with seed 228952. No runtime telephony change.
- Added a controlled local OAuth/MCP HTTP peer and three tagged Console integration
  cases backed by actual encrypted PostgreSQL stores. First harness run used the
  metadata transport address argument as headers; corrected that fixture mistake.
  The next run exposed the real shared-limiter busy result being collapsed to 503.
  Dedicated red tests prove 503 instead of 429 and ignored injected runner options
  (logs vxpipe-oauth-busy-red.log and vxpipe-oauth-runner-red.log).
- Preserve busy results through Calls and map OAuth start/reconnect to 429. Console
  adapters now accept a trusted runner option; default production limits stay
  unchanged. Workflow tests use a supervised, bounded runner without cooldown,
  avoiding sleeps or repeated side-effecting OAuth calls. Temporary diagnostics
  that repeated preparation were removed before verification.
- The 17-test endpoint/preparation/integration lane passes, including CIMD and
  confidential DCR actual local HTTP authorization/token/MCP initialization,
  encrypted persistence, refresh rotation, reconnect reuse, replay prevention,
  consent denial, failed initialization and revocation during consent. Fixture
  identity, routed loopback HTTP and a single BEAM are explicit limitations;
  no real-browser or cross-node acceptance is claimed. Milestone and durable
  OAuth document record this scope. Root static checks and umbrella rerun follow.
- Root static checks 91862 pass. Umbrella run 56503 also passes every application:
  MCP 99, Calls 296, Gateway 870, Persistence 460 and Console 456, with zero failures.
  Console's three new HTTP/database cases remain separately tagged and pass in the
  explicit 17-test lane. No source changes were made while the root run was active.
- Drafted Own-client assertion tests outside the source tree during run 56503.
  Red logs prove missing assertion adapter, JWT rejection by token exchange and
  dropped/unvalidated signing-algorithm metadata. Temporary isolated loading
  exercised ExMCP signing with RS256/PS256/ES256, fixed client/audience/lifetime,
  fresh IDs, key constraints and all three token grants. Applied those sources only
  after root termination; normal compiled verification now checks protocol opacity
  as well. Durable OAuth document records the T6 ownership/profile decision;
  encrypted key lifecycle, real HTTP interop and Own-client workflow remain pending.
- Compiled signing lane passes all 20 tests, including opaque inspection and
  public/weak/mismatched-curve PEM rejection. Full MCP: 107 tests, zero failures
  (4 excluded). Console adapter plus tagged local HTTP/database lane: 13 pass.
  Static gates 35580 pass. No dependency changes and no production UI changes;
  managed CIMD/DCR flows remain green after token-body construction was shared.
  Marked only the bounded assertion/token adapter milestone task complete;
  encrypted key storage/rotation and Own-client end-to-end support remain open.
- Added Own-client literal provider parameter validation and separate audience
  support at authorization/token boundaries. Red logs: vxpipe-oauth-parameters-red.log,
  vxpipe-oauth-parameters-protocol-red.log. Additional red tests exposed
  request-object indirection and endpoint-query overrides/conflicts; evidence in
  vxpipe-oauth-parameter-indirection-red.log and vxpipe-oauth-query-parameters-red.log.
- Reject managed/indirect fields and bound counts/names/values/aggregate bytes.
  Share validation across authorization, code exchange, refresh and machine grants.
  Endpoint query conflicts fail before token HTTP. Strengthened negative callback
  tests with observed messages: raising inside a rescued adapter can falsely look
  like successful rejection. No UI fields or managed preparation inputs changed.
- Focused parameter/token lane: 21 pass. Full MCP 114 pass (4 excluded), Console
  adapter plus HTTP/database lane 13 pass. Static gates 31088 pass. The milestone
  records only the adapter checkpoint and query-override fix as complete; the
  Own-client configuration, persistence and frontend workflow remain open.
- Root run 22396 finished successfully before newer Own-client sources were
  applied: MCP 114, Calls 296, Gateway 870, Persistence 460 and Console 456 pass,
  with zero failures in all applications. Log: vxpipe-own-client-adapters-root-suite.log.
- Added strict Own-client configuration and fresh discovery composition, including
  active-field selection, endpoint/issuer/resource binding, scope/parameter/header
  validation and JSON-safe opaque key configuration. Red logs document missing
  composition and endpoint/multiple-issuer boundaries. Normal compiled tests prove
  Inspect opacity (isolated loading could not change consolidated protocols).
  Configuration/metadata lane: 10 pass; preparation lane: 12 pass.
- Machine-only OAuth metadata no longer requires a browser authorization endpoint
  when its explicit grant list excludes browser grants. Delegated capability checks
  remain unchanged. Full machine connect/renewal is still pending.
- Wired Own-client code preparation into the encrypted attempt, callback, refresh
  and reconnect lifecycle. Shared private token projection reconstructs JWT signing
  configuration; extra MCP headers go only to MCP validation/runtime. Projection,
  completion, runtime-header and error-code tests failed before fixes. Evidence:
  vxpipe-own-projection-red.log, vxpipe-own-completion-red.log,
  vxpipe-own-runtime-headers-red.log, vxpipe-own-errors-red.log.
- Runtime catalog tests: eight pass; focused Console endpoint/adapter lane: 24 pass.
  Extended the real local HTTP/database lane to seven cases, covering public/basic/
  post/JWT registered clients, encrypted private-key persistence, fresh assertions,
  refresh, successful rotation and failed replacement preserving the saved record.
  All seven pass; vxpipe-own-http-db.log. This is routed loopback and a fixture
  identity backend, not browser/external TLS or independent-node acceptance.
- Reviewed scope selection against the approved MCP profile. A red test showed
  managed OAuth ignored challenge scopes. Shared challenge-first selection now
  preserves a challenged scope even outside scopes_supported; explicit Own-client
  scopes remain an override. Log: vxpipe-managed-challenge-scope-red.log.
  Durable OAuth doc and milestone record backend completion separately from UI,
  machine-grant and final interoperability acceptance.
- Own-client code checkpoint: all 125 MCP tests pass. Static gates 64313 pass.
  Umbrella run 86663 passes every application: MCP 125, Calls 298, Call Engine
  2292, Gateway 870, Persistence 460 and Console 459, zero failures throughout.
  Source snapshot stayed unchanged until terminal success; only documentation
  and next-checkpoint tests outside the checkout were drafted while it ran.
  Log: vxpipe-own-code-root-suite.log. Local documentation links are valid.
- New machine-flow red tests prove missing direct-connect support, incorrect
  refresh-token renewal, refusal to claim a machine grant and misleading unsupported
  discovery. Red logs: vxpipe-machine-{console,mcp,calls,persistence}-red.log.
  Reuse existing connection/probe and durable grant-claim boundaries. Keep the
  approved 2025-11-25 wire profile; current 2026-07-28 extension conformance is
  separate from explicit RFC 6749 compatible-server support, recorded in docs.
- Machine-flow focused tests are green: Console six, MCP seven, Calls 12 and
  Persistence seven, including existing delegated coverage. Added non-interactive
  Own-client composition to the existing connection probe; no new create/update
  route or credential store. Fresh discovery validates supported grant/method before
  one token request and MCP tools validation. Grant claims now distinguish renewal
  eligibility from refresh-token presence; machine results cannot add refresh tokens.
- Extended controlled HTTP/database acceptance to ten cases. All pass in
  vxpipe-machine-http-db.log, including automatic runtime renewal, no browser
  attempts/registration, three confidential methods, failed and successful key/
  secret replacement, generation fencing and revocation. Strict Credo 8015 passes.
  Production UI and independent-node interoperability remain open.
- Full affected application suites after the machine checkpoint pass: MCP 127,
  Calls 301, Persistence 461, Console 462. The full umbrella was last green at
  the preceding Own-client code checkpoint; another root run will cover the new
  machine and Manage backend changes together.
- Manage review found no safe OAuth tools-refresh path and no saved authentication
  labels in details. Added red storage/Calls/endpoint tests, then catalog-only
  persistence that leaves ciphertext and configuration generation unchanged.
  OAuth credentials resolve through runtime renewal before transient tool discovery;
  final authority and generation checks still gate the write. Existing PATCH route
  accepts only generation/refresh_tools for this operation. Public details remain
  readable without a key; optional decryption projects only three fixed labels.
  Preflight returns validated public installation callback metadata for Own-client.
- Focused Manage lanes pass: Calls 20, Persistence 10, Console endpoints 14.
  Red logs: vxpipe-mcp-management-store-red.log,
  vxpipe-mcp-tools-calls-red.log, vxpipe-mcp-management-console-red.log.
  The new HTTP tools-refresh acceptance first failed because the static probe did
  not honor the controlled loopback connection-check adapter. Added that trusted
  test-composition option; default production checks and limits are unchanged.
  Evidence: vxpipe-oauth-tools-http-red.log. Strict Credo 12258 passes.
- OAuth tools-refresh HTTP/database lane passes all ten cases; static gates
  71018 pass. Root run 41749 completed with zero failures in every application:
  MCP 127, Calls 304, Call Engine 2292, Gateway 870, Persistence 463 and Console
  464. Source snapshot stayed unchanged during the run. Local logs:
  vxpipe-oauth-tools-http-green.log and vxpipe-machine-management-root-suite.log.
- User now requests small commits with adversarial review before every commit.
  Started with the independent Storybook checkpoint and documented its review
  fixes/evidence in 20261106-2316-review-mcp-prototype.md. Production changes
  remain uncommitted pending their respective coherent checkpoint reviews.
