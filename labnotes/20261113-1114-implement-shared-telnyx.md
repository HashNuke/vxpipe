# Implement shared Telnyx applications

## Scope

- Implement the simplified milestone end to end. The user explicitly removed
  legacy fallback requirements: migrate data where needed and use one current
  runtime contract, since the application is still in development.
- The initial credentials-only/shared-application assumption is superseded by the
  explicit user decision recorded below.
- Preserve earlier uncommitted modal, alphanumeric-key and planning work. No
  commits are requested. Setup already completed in this checkout earlier in the
  conversation; local PostgreSQL is running with passwordless prompts disabled.

## Application defaults checkpoint

- Red: the two new persistence cases failed because platform application operations
  were absent and a tenant binding could not omit its application ID.
- Added one nonsecret singleton platform setting and allowed absent application IDs
  only on scoped Telnyx bindings. Existing explicit bindings are left intact.
- Resolve effective application ownership separately from credential ownership and
  include it in the pinned service reference. Focused verification is in progress.

## Approved override behavior and atomic saves

- User clarified: either tenant override displays a tenant URL. Editing tenant
  credentials clears the application input and requires an explicit application.
  Application-only overrides may inherit platform credentials. The platform
  endpoint must also route tenant applications by their event application ID and
  verify the selected tenant key, tolerating an unchanged remote webhook setting.
- Updated the milestone/design/index. This explicit decision replaces the prior
  credentials-only shared-application assumption; no URL decision remains open.
- Added a Telnyx configuration operation using existing authorized credential and
  application writes in one repository transaction. Read responses contain safe
  effective/source metadata, and named bindings require an explicit selection
  when multiple exist. Omitted masked fields merge only with the same owner's data.
- Red/green: original save tests failed for absent operations, then passed. Two
  additional tests exposed incomplete new credentials and malformed selection
  editing the sole binding; fixed both. Persistence regression: 29 tests, zero
  failures before applying the user's latest coupling rule.
- Added canonical session-only GET/PATCH platform/tenant telnyx-connection endpoints,
  safe errors and public-origin URLs. HTTP red: three missing-route failures.
  HTTP regression green: 10 tests, zero failures, including existing services.
- Next tests apply the newly approved credential/application coupling before any
  runtime or UI integration can be considered accepted.

## Verified configuration and initial routing

- New rule red: three cases failed because credential edits did not require an
  application and inherited bindings still resolved tenant credentials. Added
  input validation and store-level pairing validation. Persistence group now
  passes 30 tests (seed 114854); the HTTP group passes three tests after the change.
- Added the published application + number query to the existing service store.
  It returns safe candidate metadata only, with a tenant restriction when present
  and exactly one match. Two red tests failed for the missing operation; both now
  pass (seed 297364), including draft/ambiguous rejection.
- Webhook selection uses unsigned identifiers only to locate one candidate and
  select its effective public key. Raw-body authentication precedes dispatch, and
  the resolved credential identity/version and stricter service freshness are
  checked before use. Tenant applications work on either URL; tenant URLs remain
  tenant-scoped. Later events require their retained leg, not a new number lookup.
- Live leg lookup now keys Telnyx legs by application + provider leg, independent
  of endpoint URL, so repeated delivery to both URLs finds the same live owner.
  Durable duplicate-event protection across tenants is still pending.
- Callback URLs now follow application ownership. A red regression also exposed
  an earlier comparison that masked explicit application changes; fixed it so
  only an inherited null application is normalized during metadata comparison.
- Focused webhook/callback group: 17 tests, zero failures. The broader Gateway group
  initially exposed three obsolete scope/fixture expectations. Updated fixtures
  to the new contract: an ignored later event has an existing owner; wrong tenant
  remains rejected; the outgoing shared-app fixture explicitly owns the platform
  application. Rerun: 242 tests, zero failures (42.6 seconds).
- Database-to-Phoenix tests now publish real number routes and cover shared app
  routing plus tenant-key verification at the platform URL. Combined with the new
  configuration endpoint: five tests, zero failures (4.1 seconds).
- Current root format, compilation with warnings as errors, strict Credo and unused
  dependency checks pass. The full umbrella test run is in progress; final feature
  acceptance remains incomplete and no live-provider call was made.

## Remaining work at the earlier checkpoint

Completed in the acceptance section below.

- Reject a dedicated application ID also being used as the platform default.
  Prevent shared-number conflicts at publication and settings changes; coordinate
  their database locks with existing service/credential admission transactions.
- Extend existing durable leg/event uniqueness and lookup to application scope,
  covering replays after a number moves between tenants.
- Migrate persisted call-plan ServiceReference values to include application_owner;
  existing scoped Telnyx applications were explicit tenant applications. Do not add
  a runtime decoder fallback for this field. Verify populated migration behavior.
- Connect the production modal to the new canonical GET/PATCH telnyx-connection
  API. Reuse the reviewed component; editing tenant credentials clears/requires
  the application field. Update API parsing for nullable stored application IDs,
  safe named-binding selection, and saved masked fields.
- Browser inspection through agent-browser, usage docs and final root gates remain.

### Next routing guard implementation

- Since explicit application IDs remain unique and may not equal the platform
  default, only inherited (null-ID) bindings can share an application. Cross-tenant
  number conflict checks can therefore target published routes on those bindings;
  no materialized effective-application column or new binding mode is necessary.
- Proposed lock order to verify with concurrency tests: resolve/admission takes a
  `FOR KEY SHARE` lock on the singleton setting before service/credential locks;
  publication takes `FOR NO KEY UPDATE` on that row before its existing tenant
  publication lock; configuration changes take `FOR UPDATE` before service/tenant
  locks. KEY SHARE permits serialized publication without lock upgrades deadlocking
  against other readers, while FOR UPDATE prevents a concurrent default/override
  change. Apply the same order to direct application writes and the aggregate save.
- This is an implementation note, not verified behavior. Required conflict and
  concurrency tests must be red before adding the guards.

### Interim umbrella run

- The full umbrella run (seed 112854) exposed the Calls plan-binding test's exact
  field inventory missing application_owner. Updated that assertion; its focused
  file passes three tests.
- The same run also reported STSTransferRoomTest's failed-transfer resume assertion
  returning `{:error, :held}`. Its entire six-test file passes when rerun with the
  same seed. No speech implementation was changed; final umbrella acceptance must
  still establish a clean run after the remaining feature work.
- The original umbrella process is still running as of this checkpoint. Poll its
  existing tool session 17913 or inspect `shared-telnyx-root-tests.log`; do not start
  a replacement merely because this turn ends. Format/compile/Credo/unused checks
  passed before the assertion and documentation-only corrections above.

## Shared routing, migration and production modal acceptance

- Three initial guard tests failed because publication, inheritance reset and
  platform/default overlap were accepted. All now pass. Explicit app uniqueness
  remains; inherited rows store null. Shared-number checks reuse published routes.
- Settings locks precede service/credential locks: KEY SHARE for readers, NO KEY
  UPDATE for publication, UPDATE for configuration. Telephony checks wrap capability
  checks so publication/configuration races keep the same lock order. No separate
  routing subsystem or configuration version was introduced.
- Independent PostgreSQL clients passed three integration races: two publishers for
  one shared number; publication against another tenant's inheritance reset; and two
  duplicate admissions. Exactly one publication/claim wins (seed 849627).
- Durable Telnyx event/leg identity now uses application ID across tenant bindings.
  The replay-after-number-movement test was red (a second call was inserted), then
  green. Existing Twilio scope is retained. New partial unique indexes enforce the
  same rule under concurrent inserts.
- Added a one-off stored-plan migration for application_owner and its plan digest;
  no decoder fallback was added. Populated plan backfill is idempotent. A disposable
  database migrated from before this milestone with a dedicated binding and published
  route, preserving both and accepting null inherited IDs. Initial fixture omitted
  a required updated_at; fixed the fixture. Acceptance: one test, zero failures,
  seed 481117. Development and test databases have all three migrations applied.
- The Persistence focused group passes 19 tests (seed 85713). A later named-binding
  test exposed a credential edit leaving another binding inherited. Added final
  transactional pairing validation; all eight configuration tests pass (seed 904821).
  Oversized/truncated inventories fail closed instead of making a partial selection.
- Extracted the reviewed modal into a shared production component. The live host
  reads/saves the canonical Telnyx endpoint, selects existing named applications,
  preserves drafts on errors, and reloads on reopen. Credential editing clears and
  requires the application; unchanged masked keys are omitted. No new provider calls
  are made by saving. Updated Storybook expectations to this approved rule.
- UI red: four dialog cases and two live host cases failed. Green: 55 focused tests;
  full Console frontend suite: 144 files, 1,106 tests, zero failures. TypeScript and
  changed-file ESLint pass. The live save integration tests use API fixtures; real
  PostgreSQL/Phoenix endpoint tests separately verify persistence and authorization.
- Headless Chrome inspection via agent-browser covered platform, inherited,
  application override and credential-edit states at 1440x1000 and 390x844. The
  tenant webhook appears immediately and credential editing clears the application.
  No horizontal page overflow; controls and fixed footer remain usable. The same
  component renders in production and the inspected Storybook. No visual changes
  were needed. The local Console was started but is at first-run setup, so it was
  not used to create a new administrator merely for inspection.
- Usage docs now describe shared routing, override/reset behavior, both webhook
  endpoints, and the atomic API. Final format, warnings-as-errors compile, strict
  Credo and unused-dependency checks pass. Full umbrella run is still active in
  session 83901; Call Engine and Calls have passed without the earlier failures.
  The milestone has eight accepted tasks and one pending root acceptance task.

### Final regression reconciliation

- The root run in session 83901 completed with four Persistence failures. Three
  asserted the former tenant/service-only Telnyx duplicate contract; updated them
  to prove that different applications remain independent, replacing a binding
  cannot recreate an old leg, and historical unbound legs cannot be admitted for
  another tenant. The fourth run started before final named-binding validation
  changed and observed the earlier behavior. The fresh focused identity/config
  group passes all 15 tests (seed 23206).
- A new complete root run is active in session 95819, logging to
  shared-telnyx-accepted-root-tests.log. No implementation changes followed its
  start until the publication-order correction recorded below. Every application
  except Persistence passed the preceding run, including
  Call Engine (2,431), Gateway (880) and Console (564).
- Browser evidence is retained under the ignored
  .impeccable/review/telnyx-refresh/backend-*.png paths. Storybook hot reload reset
  one interaction while documentation changed; used fresh snapshots afterward.
  A guessed platform story URL was unavailable; the actual PlatformTelnyx story
  rendered correctly. These were inspection-tool/fixture navigation issues, not
  product failures.
- Current Telnyx documentation confirms connection_id and to are in the call
  event payload, and application webhook settings are the default delivery
  configuration. No provider dashboard configuration or live call was made.

### Publication-order correction

- Diff review found that moving revision selection before the tenant publication
  lock could leave a stale published-revision pointer when a waiting publisher
  republished the earlier revision. Added a deterministic two-connection regression
  using PostgreSQL blocking-state acknowledgement (no sleeps); it failed with
  revision 2 retained instead of the requested revision 1.
- Kept the new shared-routing lock ahead of the tenant lock, but restored the
  existing fresh revision selection after the tenant lock. The preliminary check
  only decides whether a telephony publication needs the shared lock; it does not
  carry a stale CallSpec struct into the write. This is a correction to this
  milestone's lock ordering, not a wider publication redesign.

## Completion evidence

- Final umbrella run completed successfully (session 95819, seed 589797): 5,262
  tests reported, zero failures, 381 excluded. Identity 101, MCP 222, Providers 35,
  Agent Runtime 108, Call Engine 2,431, Calls 374, Gateway 880, Web 20,
  Persistence 527, Console 564. Full output: shared-telnyx-accepted-root-tests.log.
- The publication-order regression plus existing routing/publication checks pass
  all 15 tests (seed 659315), including four independent-connection cases. This
  final store correction was compiled/tested while the umbrella was in Gateway;
  Persistence and Console subsequently completed successfully.
- Preserved the existing production Test credentials action through the current
  credential-test endpoint. Red: the button was absent; green: 17 modal/live-host
  tests pass, proving a test request does not save. Final TypeScript and ESLint
  pass. Updated the obsolete credentials-only Storybook fixture to include its
  required dedicated application; the scoped story suite passes again.
- All five root gates pass: format, warnings-as-errors compilation, strict Credo,
  full tests and unused-dependency check. Diff whitespace and changed-document
  local links pass. No source-cutover or speech state machine changed, so the Lean
  lane was not required. No live provider call or external configuration change
  was performed. Development/test migrations are applied; no commit was created.
- Milestone and index now agree: nine of nine tasks complete; the index contains
  62 milestones, 49 complete and 13 incomplete. PRODUCT.md/DESIGN.md need no change:
  this reuses the reviewed visual system and existing product purpose.
