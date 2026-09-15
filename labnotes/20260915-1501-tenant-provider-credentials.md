# Tenant provider credentials

## 2026-09-15 — initial checkpoint

### Request

Create a checkpoint-driver milestone for replacing provider credentials in runtime TOML/env
configuration with tenant-scoped database credentials, while keeping provider/model selection in
call definitions and platform infrastructure settings in deployment environment variables.

### Code review evidence

- `Vxpipe.Calls.Definitions.save/3` currently validates a tenant, parses a call definition, runs
  support compilation, and inserts a revision. It does not currently validate provider
  credential availability before persistence.
- `Vxpipe.CallEngine.CallDefinition` currently stores capability-profile references as strings.
  `Vxpipe.CallEngine.DefinitionCompiler` resolves provider modules and model/options from the
  application-owned `capability_profiles` registry. Therefore the requested definition-owned
  provider/model contract requires a definition schema checkpoint, not just a new database table.
- Speech activation currently merges definition public options with application-owned private
  `provider_options` in `PlanStartup.resolve_provider/3`; ReqLLM model activation similarly uses
  `AgentModelProfile.resolve/2` and runtime settings. These are the provider credential resolver
  seams identified in the milestone.
- `Vxpipe.Calls.CredentialRepository` and the Ecto `ApiKey` schema are for Vxpipe-issued API keys
  and persist only SHA-256 digests. They cannot be reused for recoverable provider credentials.
- Prepared calls persist an encoded `ResolvedCallPlan`, so provider secret exclusion must cover
  plan encoding and reload in addition to definitions and revisions.
- The current dirty worktree contains a TOML loader that reads provider and platform settings.
  The new milestone explicitly supersedes that runtime direction and schedules its removal; no
  runtime code was changed in this planning checkpoint.

### Decisions recorded

- Provider credentials are tenant-scoped, encrypted/reversible for runtime use, and separate
  from hash-only Vxpipe API keys.
- Provider/model/non-secret options belong to a new definition-owned capability representation.
- Missing, revoked, malformed, or wrong-tenant credentials are hard save failures with no
  revision persisted, then are rechecked at prepare/activation.
- Platform database, object storage, HTTP/TLS, and encryption-key-provider settings remain in
  deployment environment configuration. No provider API-key environment fallback or `vxpipe.toml`
  runtime path is retained.
- A fixed provider catalog and database-neutral Calls repository port preserve dependency
  direction: persistence implements storage; Call Engine and Gateway do not query Repo directly.

### Verification

- Reviewed the current milestone index, tenant control-plane specification, definition workflow,
  provider startup, prepared-call persistence, API-key schema/store, runtime configuration, and
  S3 configuration boundaries.
- Created `docs/milestones/tenant-provider-credentials-and-platform-configuration.md` with
  runnable checkpoints, approved contracts, acceptance/failure checks, manual verification, and
  scope boundaries.
- Updated the milestone index from 25 to 26 entries, inserting this unchecked milestone before
  container packaging and retention.
- Full tests were intentionally not run for this documentation-only planning checkpoint.

## 2026-09-15 — remove profiles and keep adapters internal

- The user confirmed removing capability profiles and requested actual provider names such as
  `google`, regardless of the library used internally. Revised the milestone's earlier
  `provider: "req_llm"` draft to `provider: "google"` with a provider-local model identifier.
- Added a source-linked change map covering capability parsing, independent opening TTS,
  compiler registries, `CapabilitySelection.profile`, startup, usage/cache identity, trusted
  Gateway input, Console sample provisioning, and persisted-plan migration.
- Retained definition defaults and whole-selection participant overrides. They provide reuse
  without a separate profile registry; host-tool and MCP registries retain their responsibilities.
- Specified internal model translation, preserved router model paths, and separate non-secret
  common/provider option objects. Upstream provider identity determines credential ownership.
- Changed the proposed credential reference key to `credential_name` because current
  `PrivateMaterial` explicitly rejects `credential`; omitted names select the tenant/provider
  default. This is a reference only, with no model/options preset semantics.
- Recorded explicit conversion to new immutable revisions and prepared-call drain/cancel
  requirements. Existing term-encoded plans do not migrate automatically when structs change.
- Updated the index contract and kept all implementation tasks unchecked. Runtime implementation
  is outside this planning checkpoint.

## 2026-09-15 — include tenant telephony and use vertical checkpoints

- The user added Telnyx/Twilio credentials and explicitly requested vertical implementation slices.
  Reorganized the milestone into seven provision-to-call/operator flows: initial voice call,
  opening/transfers, Telnyx, Twilio, remaining providers, live rotation/revocation, and platform
  restart/cutover. Each includes its own storage/configuration/runtime work, focused checks,
  operator documentation and runnable exit; no isolated database-only completion checkpoint.
- Reviewed `ServiceRegistry` and `ConfiguredService`: carrier configurations currently retain
  private adapter/verifier options, and tenant outbound lookup falls back to application services.
  The target replaces hosted lookup with tenant DB service bindings and removes that fallback.
- Reviewed Telnyx/Twilio `ServiceProfile` modules. They are internal carrier input validators,
  not the capability-profile feature being removed. Telnyx requires an API key/connection and
  webhook public key; Twilio uses account SID/auth token for commands and verification.
- Traced `TelnyxEvents`, `TwilioWebhookRequest` and `TwilioMedia`. The ingress URL key must locate
  an exact registered tenant/service before signature verification; unsigned event account/phone
  fields must not select credentials. Twilio WSS authentication must remain before media-token
  consumption, not just before event dispatch.
- Traced `OutgoingLegConnector` and `TelephonyAdmissions`. Outbound requests already have tenant
  identity; incoming definition routing occurs only after normalized authenticated ingress.
  Retained `connection.service` as account/routing intent, with DB-backed same-tenant/provider
  credential references and pinned account identity, rather than introducing carrier models.
- Added explicit live-leg credential snapshots and bounded verification leases for callbacks,
  media completion and cleanup during DB outages. New admissions/legs fail closed; no scan across
  tenant keys, application fallback, speculative redial or account switching.
- Kept the original Twilio live-provider audibility gate open. Synthetic parity evidence does
  not complete it. Container boot remains with the held delivery milestone, avoiding a circular
  prerequisite for this plan's source-development acceptance.
- Synchronized the index scope and separate specification-review row. Requested independent
  review of the rewritten source-based plan; implementation remains not started.
- Documentation verification passed: 128 relative links/anchors across milestone/index, one JSON
  example, seven sequential checkpoints with runnable exits, 53 unchecked tasks, and 26 index
  entries with 21 implemented. `git diff --check` passed. No full tests were run for this
  documentation-only change.

### Specification review corrections

- Clarified that telephony service records reference a stable credential identity while each leg
  privately pins the resolved version. Rotation must not require republishing definitions.
- Clarified rollout ordering: isolated checkpoint demos use provisioned state; incompatible
  runtime changes are not deployed over old prepared plans before explicit revision conversion
  and drain. Converted paths do not retain a legacy dual-read fallback.
- Reviewer Lorentz identified three additional telephony contracts. Added each to the owning
  carrier checkpoint and acceptance matrix, and requested a bounded follow-up review:
  - `TelephonyCallStore.fetch_claim/5` and the telephony-leg unique indexes omit tenant scope.
    Durable queries/constraints and backfill must use tenant/canonical service identity, with
    cross-tenant alias/event/leg-ID replay and restart tests, not just live-registry isolation.
  - `MediaAdmission.consume_entry/6` either consumes or installs a waiter; it cannot safely find
    a pinned Twilio auth version before verification. Specify non-consuming bounded auth-lease
    discovery for bound/pending reservations, then verification and same-lease atomic consumption.
  - Existing carrier harness admission-store failure is not credential-source failure. Require
    distinct failure injection: credential outage prevents new dialing and preserves the source,
    while admitted media/callbacks/cleanup use their private lease. Admission-store-only behavior
    remains intact when credentials are independently available.
- These are planning corrections, not findings claimed fixed in runtime code. The original
  Twilio live-provider acceptance remains open and all new implementation tasks remain unchecked.
- Lorentz's bounded follow-up reported all three findings resolved at specification level and
  no remaining vertical-order blocker. Recorded that result separately from implementation in
  the milestone and index; it does not claim runtime implementation approval.
- Final documentation verification passed: 131 relative links/anchors, one JSON example, seven
  sequential runnable checkpoints, 57 unchecked tasks, and unchanged index completion counts
  (26 entries/21 complete). `git diff --check` passed. No runtime edits, commits or full-suite runs
  were made for this planning update.

## 2026-09-15 — delete alternate configuration paths, not just disable them

- The user reiterated that old provider configuration must not remain available as a fallback.
  Made deletion of readers, merges and branches explicit, including global model/options,
  `provider_api_key_environment`, application-scope carrier configuration and implicit SDK
  credential discovery. No precedence mode, feature flag or dormant compatibility path qualifies.
- Added checkpoint 7 tasks for a source/configuration audit and conflicting-old-settings tests:
  missing tenant DB credentials must fail without requests; valid credentials and definition
  options must not be overridden by env/application/file inputs. Migration tooling remains
  explicitly invoked and cannot be a live fallback. Platform infrastructure env remains supported.
- Synchronized the index and added an explicit no-alternate-configuration acceptance row.
  This clarifies the existing approved contract; no runtime implementation was changed.
- Lorentz reviewed the bounded delta and reported no blocking findings or checkpoint-order
  contradiction. Documentation checks passed: 131 relative links/anchors, one parsed JSON example,
  seven runnable checkpoints, 59 unchecked tasks, 26 index entries/21 complete, and
  `git diff --check`. No full suite or runtime changes for this documentation-only clarification.

## 2026-09-15 — database aliases and env-free development

- The user specified `VXPIPE_DB_URL` before `DATABASE_URL`, and `VXPIPE_DB_POOL_SIZE` before
  `DB_POOL_SIZE`, with development using `vxpipe_dev` and the default pool without env setup.
- Reviewed `config/runtime.exs`: current URL uses `VXPIPE_DATABASE_URL`; pool defaults to 10
  through the temporary TOML loader. `config/dev.exs` supplies `postgres://localhost/vxpipe_dev`.
  `Vxpipe.Persistence.CLI` still mentions the old variable in its not-configured diagnostic.
- Added the exact platform contract and checkpoint 7 implementation/verification tasks. Unset or
  blank aliases are absent; a selected invalid value fails rather than trying a lower-priority
  alias. Remove the old URL name, update CLI/docs/examples/tests, and never print a secret URL.
- Reviewed `config/test.exs`: the dedicated test URL/database and Sandbox pool are separate.
  Added explicit isolation tests so the new common `DATABASE_URL`/pool aliases cannot redirect
  tests to a development/production database or replace the test pool configuration.
- Env-free development here means no database env requirement, not a default encryption key,
  automatic PostgreSQL provisioning or bypass of tenant provider credentials. Non-development
  hosted DB-backed operation must not silently connect to `vxpipe_dev`.
- Synchronized the milestone index. No runtime configuration changes or full tests were made;
  this is an addition to the requested implementation plan.
- Lorentz's bounded review found no blockers or vertical-order contradiction and confirmed the
  development defaults against source. Documentation checks passed: 131 links/anchors, one JSON
  example, seven runnable checkpoints, 61 unchecked tasks, 26 index entries/21 complete, exact
  alias/default table checks, and `git diff --check`.
