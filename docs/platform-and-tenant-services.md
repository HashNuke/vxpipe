# Platform and tenant services

Status: implemented and accepted 2026-09-19. Storybook and all 13 implementation
checkpoints are delivered, including the credential-presence correction, scoped
Telnyx ingress, Console application/number setup and legacy webhook removal.
Final verification passes 1,798 umbrella tests with zero failures and 40 exclusions,
187 frontend tests, all root static gates, browser/restart, re-encryption and rollback
checks. Live Telnyx verification remains a deployment check, not claimed here.
Requested 2026-09-19. This extends the previously tenant-only credential decision.
It does not restore environment-based provider credentials or implicit failure fallback.

## User contracts

- Configure a provider once under **Platform services**, or configure a tenant override.
  Use “platform” consistently; “account” could mean an upstream Telnyx account.
- **Authoring authority (user clarification, 2026-09-19):** platform configuration
  does not grant tenant API keys permission to reference that service. An authenticated
  installation operator may create/update a tenant call spec using platform services.
  A tenant administrator may reference only services configured for that tenant.
  Validate the complete resulting spec on every create, update and publish, including
  unchanged references in an operator-authored spec. An operator's earlier write does
  not transfer editing authority to the tenant. Reject unauthorized writes before
  committing a revision or route; repeat ownership checks under the final transaction
  locks. This includes AI/speech selections and telephony caller/destination services.
- Execution of an already authorized, published spec remains a separate permission:
  tenant call keys can run that tenant's published routes. They cannot author a new
  platform-backed spec. Operator API keys establish installation authority separately
  from tenant `admin`/`calls` keys and browser login sessions.
- **Credential presence (latest user clarification, 2026-09-19):** credentials either
  exist at tenant scope or do not; the same applies at platform scope. There is no
  separate inherit/override/disabled policy or credential disable action.
- Runtime uses the tenant credential for the exact provider/name whenever it exists,
  regardless of who authored the spec. Otherwise use the platform credential; absence
  at both scopes is unavailable. Existing invalid or unreadable tenant credentials
  fail closed. They never trigger fallback to platform. An override replaces the
  whole credential set; named bindings never silently substitute `default`.
- Tenant cards show **Inherited from platform** or **Tenant override** where applicable.
  Ordinary tenant/platform cards omit redundant scope labels. Inherited capabilities
  count toward onboarding readiness, including newly created tenants.
- **Use platform service** deletes the tenant credential. **Remove service** deletes
  the credential at its own scope. There are no dormant tenant credentials: adding
  a credential again creates a new identity, requiring fresh preparation for readers
  pinned to the deleted identity. Existing legacy telephony references prevent deletion
  until their application binding is removed. API-key revocation is a separate concern.
- An inherited service opens a read-only explanation with **Override for this tenant**
  and **Manage platform services**. Platform credentials are edited at platform scope.
  The operator UI has installation-wide authority; tenant API keys do not gain that
  authority through inheritance or UI actions.
- The first UI supports Deepgram, Rime, Google AI Studio and Telnyx, as already selected
  by the user. Provider labels and defaults do not establish live runtime support.

## Telnyx credentials, verification and routing

The public origin plus an explicit credential-scope path forms the webhook URL:

| Configuration used | Path | Verification key |
| --- | --- | --- |
| Platform Telnyx | `/webhooks/platform/telnyx` | Platform Telnyx public key |
| Tenant Telnyx | `/webhooks/tenants/:tenant_key/telnyx` | That tenant's Telnyx public key |

An inheriting tenant uses the platform URL, even when it owns a dedicated Voice API
application. A tenant override uses its tenant URL. Switching scope requires updating
the Voice API application's webhook setting; changing the local UI cannot do that for
the user. Do not claim remote configuration succeeded solely because credentials saved.

Display a selectable, read-only, single-line **Webhook URL** near the end of Telnyx's connect and
edit modals, above the actions, with Copy and clipboard success/failure feedback.
Copy: “Use this URL in your Telnyx Voice API application to receive call events.”
The field follows the credential inputs and is absent for other providers.
An inherited Telnyx detail shows the platform URL; beginning an override shows the
tenant URL. The override never inherits the platform public-key-configured flag.

Telnyx's API key is sufficient for the AI credential form. The public key is optional
until telephony is enabled. Actual telephony readiness also requires application and
number/call-spec routing, and a publicly reachable origin. The existing Storybook
Connected state represents saved credentials, not proven phone-call readiness.
Both copies of the Telnyx card use the same double-check connection icon and pencil
edit button. A missing public key places a yellow warning in the Telephony capability
badge, with accessible and hover text. Editing shows masked placeholders only for
fields with saved values; actual credential values remain absent from the form.

The first backend slice should support one Telnyx credential set per scope, consistent
with these URLs. Named alternate Telnyx accounts within one scope cannot choose keys
from webhook-body fields; supporting them would require a separately reviewed route
contract. Multiple Voice API applications may use the scope's same credential set.

The route selects the verifier before event dispatch. Verify the exact raw body and
timestamp with that scope's public key, then match the authenticated application ID
to a tenant binding. Tenant URLs must reject other tenants' applications. For the
platform route, keep an explicit application-to-tenant mapping; default to a dedicated
Voice API application per tenant. Shared applications require explicit number routing
and are deferred from the first slice. Never guess a tenant from the first matching
credential or use an unverified body field to choose a different scope's key.

Telnyx applications own webhook, inbound SIP and outbound voice-profile settings;
custom recording storage is also configured per application. These remain application
bindings, separate from the credential scope. References:
[Telnyx application settings](https://support.telnyx.com/en/articles/4374050-configuring-call-control-texml-applications-voice-api),
[application API](https://developers.telnyx.com/api-reference/call-control-applications/create-a-call-control-application),
[recording storage](https://developers.telnyx.com/docs/voice/programmable-voice/storing-call-recordings).

## Public origin

- Build URLs from application configuration, never the browser's current origin.
  Storybook's port 6006 is not the application's webhook port.
- Local development defaults to `http://localhost:4000`, respecting `PORT`.
  A public `APP_HOST` uses HTTPS behind the normal public proxy. Direct development
  HTTP and Phoenix TLS respect `VXPIPE_DEV_TLS` and the configured application port.
- Storybook reads the allowlisted public settings in its Node configuration and injects
  only the resulting origin. No environment map or provider credentials reach the browser.
- Production must derive one authoritative public origin in `config/runtime.exs` and
  expose safe URL metadata through Console responses. The current
  `VXPIPE_TELEPHONY_PUBLIC_BASE_URL` compatibility path must be explicit: preserve it as
  an override during migration, default to the `APP_HOST` public origin, and generate
  both displayed and outgoing callback URLs from the same resolved value.
- A localhost URL previews local routing only. Live Telnyx acceptance needs a public
  endpoint; the UI preview is not evidence of remote reachability.

## Existing boundaries that must change

The original Calls/Persistence credential boundary required a tenant key and tenant
foreign key. Checkpoint A now separates tagged ownership from the consuming tenant,
adds platform uniqueness, and shares presence-based resolution between
private reads and final write guards. Existing tenant ciphertext keeps its version-1
authenticated context; platform ciphertext uses a distinct version-2 context.

The carrier boundary supports effective primary Telnyx bindings through an explicit
credential name. Gateway supports only the two explicit Telnyx scope URLs and rejects
unscoped Telnyx bindings before constructing a fresh live client. Stored legacy metadata
remains readable; media ingress keys and Twilio's exact tenant bindings are preserved.
Fresh scoped requests authenticate before application lookup; initialized legs retain
authentication for callbacks/media/cleanup during storage outages.

Keep responsibilities: Calls owns scoped service resolution and safe identities;
Persistence owns encryption, schema, constraints and transactions; Gateway owns
provider protocols and signed webhook dispatch; Console owns operator endpoints and UI.
No Console dependency in the engine or Gateway, and no Repo calls in those applications.

## Implementation sequence

### Runnable delivery checkpoints

The user authorized implementation of the full plan on 2026-09-19. Delivery follows
these vertical slices; each includes the owning tests, documentation and applicable
browser checks. A checked design task does not count as a delivered slice.

- [x] **A — Use an inherited provider in a tenant call.** Migrate credential ownership
  and scoped bindings, provision a platform provider through the operator
  boundary, and resolve it through call-spec save/publish/preparation and fresh runtime
  readers. Prove two inheriting tenants, one override, named bindings, failed
  tenant credentials and transaction-time guards. Preserve existing tenant ciphertext and IDs.
- [x] **A2 — Authorize service references by the writing principal.** Add explicit
  principal-aware create/update/publish workflows. Prove operator writes can use
  platform services while tenant writes require tenant ownership, including edits
  to an operator-created spec and transaction-time scope changes. Existing trusted
  host entry points remain explicitly trusted; runtime admission is separate.
- [x] **A3 — Write call specs with operator API keys.** Persist hash-only installation
  keys, issue them through a trusted local command, authenticate an explicit operator
  principal, and expose authenticated operator/tenant call-spec writes. Prove no
  tenant-key promotion, rejected/revoked keys, reload and secret-safe responses.
- [x] **B1 — Connect an inherited provider in the Console.** Connect the reviewed
  platform and tenant pages to authenticated APIs. Save and edit a platform service,
  show its effective source/readiness to tenants and reload durable progress. Prove
  CSRF, authority boundaries, no secret disclosure and desktop/mobile behavior.
- [x] **B2 — Manage tenant service exceptions in the Console.** Override and
  restore an inherited service through the reviewed UI and durable APIs. Preserve
  exact named bindings, show failed overrides without fallback, and
  verify reload, onboarding readiness and desktop/mobile recovery paths.
- [x] **B3 — Resume demo onboarding with effective services.** Replace the older
  onboarding and sample installer's tenant-only inventory reads with the effective
  directory. Count only usable exact named bindings, show inherited states,
  route credential management through the scoped setup page, and prove inherited
  sample publication plus reload and failure recovery. Preserve edited samples.
- [x] **C — Receive a scoped Telnyx call.** Bind a tenant Voice API application to its
  selected service scope, verify the route-selected key, then dispatch to that tenant.
  Exercise both routes with persisted credentials, wrong-scope/tenant rejection and
  duplicate/outage behavior. Expose the matching URL and configuration in Console.
- [x] **D — Remove legacy Telnyx webhooks and complete acceptance.** Use only the explicit
  platform and tenant webhook paths. Remove the legacy events route and callback generation
  in a reviewed checkpoint, preserving media/token and Twilio contracts. Verify replacement,
  re-encryption, restart, schema rollback boundaries and final umbrella gates. Document
  required remote application configuration without claiming live-provider evidence.
- [x] **D1 — Remove legacy Telnyx webhook routing and generation.** The old events URL
  cannot dispatch, and fresh clients require a scoped primary binding. Media/token and
  Twilio behavior remain verified. This checkpoint follows C3a and precedes C3b.
- [x] **D2 — Complete final acceptance.** Verify replacement, re-encryption, restart,
  schema rollback and the final combined application/number-setup flow after C3b.

Checkpoint design review, 2026-09-19: A establishes the shared scoped resolver before
the operator UI and scoped carrier readers use it; B1/B2 provide the durable management
surface used by C. C establishes exact verifier/application ownership before D changes
outgoing URLs. The user's subsequent authoring-authority clarification inserts A2/A3
for programmatic writes: operator API-key issuance is now required for this flow. New AI
adapters remain outside this dependency chain. The detailed acceptance requirements
below remain authoritative. A2/A3 provide programmatic authoring while B1 uses the
separate operator browser session. B2's implementation is committed; B3 connects the
remaining onboarding consumers before carrier work.
The user's subsequent review/commit instruction requires reviewing and committing
each runnable checkpoint before starting the next implementation. Unresolved
verification stays explicit and leaves the acceptance checkbox open. B was split into B1/B2 to keep
both Console commits runnable and small enough to review independently.
Integration review, 2026-09-19: B2 verification found that the older
`/admin/onboarding` entry and `DemoSamples` installer still read tenant-only inventory.
B3 separates that required effective-service integration into another runnable
checkpoint before carrier work; it does not add a new provider or recipe catalog.

Carrier design review, 2026-09-19: C will be delivered in reviewed C1/C2/C3 commits for
effective application bindings, scoped ingress, and Console configuration respectively.
The [scoped Telnyx binding decision](scoped-telnyx-service-bindings.md) records the
legacy compatibility boundary, selected-owner identity and acceptance order.
C3 is split into credential/URL setup (C3a) and tenant application configuration
(C3b). C3b is delivered as an operator API/durable-route checkpoint (C3b1), then its
Console form and browser acceptance (C3b2). Both are implemented and accepted by
their owning suites, rendered checks and the final combined umbrella run. An earlier
native WebRTC timeout did not recur in five isolated runs or that final full run.
The binding decision
records their input, authority, identity and published-route contracts separately
from implementation progress. C3a includes D's shared-origin and outgoing scope-URL generation so displayed
and outgoing URLs agree; D owns legacy webhook deletion and final acceptance, per
the latest user clarification.

User scope correction, 2026-09-19: legacy Telnyx webhooks are no longer required.
Remove their routes and callback generation instead of delivering a compatibility
window. This supersedes earlier legacy webhook preservation requirements; historical
C1/C2 evidence below describes what those checkpoints delivered. C3a finishes its
reviewed credential/URL slice before the separate removal checkpoint. Stored credentials,
media authentication and Twilio routing are not deleted by that change.

Current evidence: [checkpoint A labnotes](../labnotes/20260919-0611-scoped-provider-inheritance.md).

Checkpoint A implementation details:

- Owning application suites, focused transaction integration tests, and disposable
  database migration/restart checks pass. The A3 combined umbrella run passed
  1,754 tests with 40 exclusions (`--max-cases 1 --seed 772211`). Earlier runs had
  intermittent native-media failures; this result does not establish their cause.
  Format, compile, strict Credo and unused-dependency checks pass.
- Installation operators can create a named platform binding with
  `POST /admin/api/platform/credentials`, using the existing session and CSRF token.
  Inputs are `provider`, optional `name` (defaults to the provider ID), and `values`.
  Responses contain credential metadata only. Tenant credential endpoints keep
  their existing names and authority contract; Console listings/editing follow in B1.
- A call's `credential_name` selects exactly that provider/name. Migrated tenant
  credentials retain their ownership. The presence correction supersedes the original
  policy resolver: tenant records take precedence; missing tenant records inherit.
- Newly prepared plans pin owner and credential ID, not credential version. Rotation
  within that identity is visible to fresh readers; an owner/ID switch requires new
  preparation. Speech asset cache keys also include credential version. Legacy stored
  plans without the field retain their previous lookup behavior; the decoder supplies
  the compatibility default rather than inventing a historical credential identity.
- The migration does not rewrite tenant IDs or ciphertext. Its down migration works
  for unchanged tenant-only configuration and rejects scoped configuration requiring
  deliberate cutover. D records the final Telnyx migration and callback acceptance.

Checkpoint A2 is reviewed and committed as `5a0b407`. Explicit authorized save/publish
boundaries distinguish installation operators from tenant principals and recheck the
owner inside final write guards. Persisted tests prove an operator can author a shared
service reference, tenant edits/publish fail until that tenant supplies the required
services, and fresh runtime preparation prefers the active tenant configuration.
Existing tenant-key-only host functions remain trusted host APIs. A3 exposes the
new authorization boundary through real operator/tenant API-key HTTP writes.
The persisted positive cases cover AI/speech services and, in C1, a platform-backed
Telnyx caller. Tenant edits and publication require tenant credentials in both cases.

Checkpoint B1 implementation and browser evidence:

- `/admin/platform/services` saves and edits platform credentials;
  `/admin/tenants/:tenant_key/setup-services` displays effective source, readiness and
  exact named bindings. The older tenant service inventory remains available.
- Operator-session directory endpoints are `GET /admin/api/platform/services` and
  `GET /admin/api/tenants/:tenant_key/service-bindings`. Platform replacement uses
  `PATCH /admin/api/platform/credentials/:credential_id` with real CSRF enforcement.
  Responses contain safe metadata only; credentials remain write-only.
- Inherited details link to platform management. Tenant override/restore
  actions follow in B2. Telnyx public-key and webhook configuration follow in C;
  the production form does not display fields that cannot yet be persisted.
- Rime credentials can be stored and validated with its authenticated dictionary
  coverage endpoint. This does not implement a Rime runtime adapter. Voice-sample
  readiness still uses supported runtime capabilities, not the marketed capability list.
- Chrome verified desktop/mobile save/edit, rejected-key recovery, two inheriting
  tenants and reload after server restart with encrypted PostgreSQL storage and a
  synthetic provider validator. No live upstream validation is claimed. The frontend
  suite passes 173 tests and the serial umbrella run passes. A final tagged-owner
  directory correction passed a red-green regression and the full 114-test Calls
  suite afterward. See the
  [B1 labnotes](../labnotes/20260919-0715-console-platform-services.md).

Checkpoint A3 passes in two runnable commits to keep review bounded. The
first adds trusted operator-key bootstrap/replacement/revocation and authenticated
`GET /api/platform/status`; the second adds operator/tenant call-spec HTTP writes.
Key storage, protected output, authority separation and disposable-database
HTTP/restart exercises pass. The authoring routes now reject tenant writes using
platform-only services and accept them once the tenant configures its own services;
the combined umbrella suite passes 1,754 tests with 40 exclusions. All root static
gates pass. See the [key and authoring contract](operator-api-key-authoring.md),
[key lifecycle labnotes](../labnotes/20260919-0803-operator-key-authoring.md) and
[HTTP authoring labnotes](../labnotes/20260919-0821-authorize-http-spec-writes.md).

Checkpoint B2 originally shipped explicit tenant policies in `4c2bd75`. Its disable
and dormant-row semantics are superseded by the credential-presence correction below.
Historical tests/browser evidence and unresolved native audio failures are retained in
[B2 labnotes](../labnotes/20260919-0840-tenant-service-exceptions.md).

Credential-presence correction (implemented and reviewed before C):

- [x] Select tenant credentials by exact provider/name presence; otherwise inherit.
  Remove the policy workflow/schema from readers and writes. Keep failed credentials
  fail-closed and preserve transaction locks around authoring and runtime selection.
- [x] Add installation-only, CSRF-protected deletion at
  `DELETE /admin/api/tenants/:tenant_key/credentials/:credential_id` and
  `DELETE /admin/api/platform/credentials/:credential_id`. No fallback lookup in deletion.
  Existing telephony references return 409; missing owned credentials return 404.
- [x] Remove policy/dormant-credential metadata and all credential disable UI. Restore
  platform use by deleting the exact tenant credential and reloading the directory.
  Failed mutation/reload stays actionable; inherited secrets remain read-only.
- [x] Verify migration, restart, rendered desktop/mobile flows and root gates; review
  the complete checkpoint before committing. All 1,763 umbrella tests pass (40 excluded),
  alongside 181 frontend tests and the focused real-transaction lane. See
  [presence labnotes](../labnotes/20260919-0934-credential-presence-resolution.md).

The new migration drops only `tenant_service_policies`, preserving all credential IDs
and encrypted payloads. Previously dormant tenant records now take precedence because
they exist; explicitly remove them to inherit. Rollback recreates override policies for
all tenant records, preserving presence-based selection with the older resolver. It does
not restore retired disable policies or recover credentials intentionally deleted later.
Deploy the code and migration together; old application processes still query the retired
policy table and must be restarted on this version.

Checkpoint B3 implementation (accepted by the presence-correction umbrella run):

- Demo onboarding and the sample installer read the same effective directory as
  scoped setup. Only connected exact primary names satisfy the fixed sample bindings;
  alternate names and failed tenant credentials do not borrow platform readiness.
- The production onboarding entry labels inherited services and sends edits
  to the scoped services page. It never asks for inherited credentials. Directory
  failures remain unavailable and offer Retry setup; optional unavailable providers do
  not invalidate usable sample prerequisites.
- Focused tests now cover inherited publication, unreadable tenant credentials/removal,
  idempotent installation and preservation of an edited sample's draft and earlier publication. Frontend
  tests cover the effective-directory boundary, source labels, scoped navigation,
  optional services and recovery. All 181 frontend tests, TypeScript, ESLint, assets
  and root static checks pass. The umbrella run completed 1,759 tests, one failure,
  40 exclusions: the unchanged native `after_speech_adoption` handoff test timed out
  waiting for preparation progress. All 180 Console tests passed. The later presence
  correction passes the complete suite and closes B3 acceptance.
- Chrome at 1440×1000 and 390×844 verified inherited readiness, sample installation,
  the then-current disable/restore flow (superseded), scoped management and retry after
  a failed directory read. A fresh server process retained the same Demo tenant, inherited credentials
  and all three revision-1 publications. Reinstalling remains idempotent; the older
  entry's sample labels are refreshed by the explicit install action, while service
  readiness is read on page load. No live provider request was made.
  See [B3 labnotes](../labnotes/20260919-0905-inherited-demo-onboarding.md).

Checkpoint C1 implementation:

- Scoped Telnyx credentials accept an optional verification public key. A tenant
  application with `credential_name: "telnyx"` resolves its effective whole credential;
  an existing tenant credential without a public key fails without platform fallback.
- Dedicated application IDs are unique across scoped bindings. Operator-authored
  callers may use platform credentials; tenant updates and publication require tenant
  ownership. Prepared references pin the selected owner, credential ID and name.
- Legacy exact-ID bindings, ingress and Twilio remain supported. The binary plan
  decoder supplies explicit legacy defaults for the added fields. Migration preserves
  legacy IDs/ciphertext and refuses rollback while scoped bindings exist. Fresh-VM
  resolution and upgrade/down/re-upgrade checks pass.
- Focused persistence (24) and Gateway reader (6) tests pass. The full umbrella run
  covers 1,770 tests with one obsolete field-set assertion; its correction passes the
  complete 116-test Calls suite. All remaining umbrella applications pass, including
  the 700 engine and 446 Gateway tests. Root static gates pass. No UI changed in C1.
  See [binding configuration](scoped-telnyx-service-bindings.md) and
  [C1 evidence](../labnotes/20260919-0930-scoped-telnyx-bindings.md).

Checkpoint C2 implementation:

- Both approved scope routes pass through the production Phoenix/Gateway mount,
  preserving the raw body for signature verification. Tenant URLs require that
  tenant's own primary credential; a platform credential cannot satisfy that route.
- After authentication, explicit application lookup and effective owner/ID/version
  checks reject unknown, cross-tenant and changed bindings. Existing exact-ID services
  remain available through legacy ingress and are excluded from scoped lookup.
- Incoming/outgoing owners retain their verifier and register scoped lookup aliases.
  Duplicate admission and callbacks without client state work without another storage
  read. Verification failure never retries a replacement owner or another scope's key.
- Forty-seven focused Gateway checks and a real PostgreSQL/Phoenix signed-request test
  pass. The full umbrella passes 1,781 tests, zero failures, 40 excluded; static gates
  pass. No UI or live-provider claim is included. See
  [C2 evidence](../labnotes/20260919-1030-scoped-telnyx-ingress.md).

Checkpoint C3a implementation:

- Production Telnyx forms accept the optional public key with the API key. Directory
  responses expose configured-field names only, from the exact selected credential.
  Unreadable tenant rows do not inherit a platform public-key flag. Whole-payload
  replacement remains explicit: leaving a saved public key blank removes it.
- Runtime resolves one public origin from allowlisted configuration; the explicit
  telephony override preserves path prefixes. Console returns platform/tenant URLs
  built by the same Gateway helper used for newly initialized scoped callbacks.
  Public APP_HOST defaults to HTTPS; local HTTP remains a preview. Legacy callbacks
  remain temporarily in this checkpoint, pending the approved deletion next.
- Chrome at desktop/mobile sizes verified save/edit, inherited details, override URL
  changes, clipboard success/failure, rejected-key recovery and persisted state after
  restart with encrypted PostgreSQL and synthetic validation. No live Telnyx claim.
- Review caught malformed URL ports being silently normalized and a repeated
  CallIngress test identity collision. Focused regressions and 50 test-isolation reruns
  pass; the final umbrella passes 1,786 tests, zero failures, 40 excluded. All 183
  frontend tests, assets, TypeScript, ESLint and root static gates pass. See
  [C3a evidence](../labnotes/20260919-1052-telnyx-console-configuration.md).

Checkpoint D1 implementation:

- Removed the old Telnyx HTTP route, verifier-selection branch, live ingress alias
  and outgoing callback fallback. Only explicit platform/tenant webhook URLs remain.
  Gateway rejects unscoped Telnyx snapshots before constructing a fresh live client;
  stored credentials, application records and historical call identities are preserved.
- Two red regressions now pass: signed requests to the old path return 404 without
  dispatch, and an unscoped binding cannot create a live client. Updated Telnyx
  protocol/call-flow fixtures use scoped bindings and URLs; Twilio/media contracts pass.
- The encrypted PostgreSQL two-tenant/two-carrier integration check passes. Review
  corrected an incomplete synthetic speech acknowledgement in a separate fixture
  checkpoint; six combined carrier harness runs pass. Final umbrella: 1,788 tests,
  zero failures, 40 excluded, with all root static gates passing. No UI or live-provider
  acceptance is claimed here. See [D1 evidence](../labnotes/20260919-1131-remove-legacy-webhooks.md).

Checkpoint C3b1 implementation:

- Installation operators can create/edit a tenant's scoped Telnyx application through
  session/CSRF-protected endpoints. Inputs exclude credential ownership, keys and ingress;
  the server supplies the primary binding and stable media identity. Edits preserve the
  service UUID/name and reject stale prepared references through existing locked checks.
- The application directory reads current published number routes from existing call-spec
  storage. Drafts, superseded revisions and foreign tenants are excluded. Bounds are
  100 applications/500 routes, with ambiguity counted before truncation.
- Calls (117), Persistence (184) and Console (185) suites pass, along with all static
  gates. The first 1,798-test umbrella run had one native WebRTC handoff timeout;
  five isolated reruns and D2's final full umbrella run passed unchanged. See
  [C3b1 evidence](../labnotes/20260919-1208-tenant-phone-application-api.md).

Checkpoint C3b2 implementation:

- Tenant service setup now exposes an inline application create/edit form and reads
  current published number routes. Service names stay fixed; edits change only the
  application ID and optional outbound caller. Credentials remain in their existing form.
- Missing tenant public keys, duplicate IDs, failed reads/writes and saved-but-reload-failed
  states preserve the credential-scope contract and provide explicit recovery. The page
  distinguishes local configuration, remote Telnyx settings and live call verification.
- All 187 frontend tests, TypeScript, ESLint, Prettier and asset builds pass. Chrome
  at 1440px and 390px verifies both credential sources, real create/edit, persisted
  published routes, errors, retry and restart. Independent finish review returns `ship`;
  no new design-system rule is needed. D2 closes final umbrella acceptance. See
  [C3b2 evidence](../labnotes/20260919-1225-tenant-phone-configuration.md).

Checkpoint D2 acceptance:

- Both inherited and tenant-owned credentials support durable application/number
  setup. Replacement, server restart and encryption-key rotation preserve the expected
  credential identities/owners, application mappings and published routes. Fresh rendered
  navigation after rotation confirms each tenant's source and routing metadata.
- Disposable schema upgrade/rollback/re-upgrade preserves legacy IDs and ciphertext.
  Rollback rejects live scoped bindings atomically; a fresh VM still resolves the same
  application and verifier afterward. Owned browser/server/database fixtures are removed.
- The final root run passes 1,798 tests, zero failures, 40 excluded. Format, compile with
  warnings as errors, strict Credo, unused-dependency checks and asset builds pass;
  all 187 frontend tests, TypeScript, ESLint and Prettier pass. The prior native handoff
  timeout is recorded without claiming its cause or changing its timeout.
- All 13 implementation checkpoints are accepted: A, A2, A3, B1, B2, B3, C1, C2, C3a,
  C3b1, C3b2, D1 and D2. Parent C/D entries summarize those slices. Remote Telnyx
  provisioning, shared applications, alternate named Telnyx accounts and new AI adapters
  remain outside this plan. No live-provider call is claimed. See
  [final acceptance evidence](../labnotes/20260919-1304-scoped-services-acceptance.md).

### 1. Storybook review checkpoint

- [x] Show tenant and platform Telnyx URLs in connect/edit states with copy feedback.
- [x] Add Platform services using the existing AI/optional-telephony grids and modals.
- [x] Show inherited, tenant override and failed-credential states; preserve
  independent tenant progress and platform changes across prototype navigation.
- [x] Verify readiness and recipes use effective services, including newly created tenants.
- [x] Inspect desktop/mobile, light/dark, create/edit and clipboard behavior.

This checkpoint uses synthetic state only. It does not enable new providers or implement
remote application provisioning, credential persistence, verification or routing.

### 2. Persist and use an inherited AI provider

- [x] Define a tagged credential owner (`platform` or tenant key), distinct from the
  consuming tenant. Add scope-aware unique/check constraints and metadata.
  Never use a fake platform tenant.
- [x] Migrate existing credentials and references as tenant-owned without changing IDs
  or effective behavior. Version authenticated encryption context where needed;
  test existing decrypt, replacement, re-encryption, interruption and rollback behavior.
- [x] Add explicit platform operator CRUD/validation endpoints using the current session
  and CSRF protections. Tenant keys cannot write/read platform secrets; effective-list
  responses contain safe source/readiness metadata and URLs only.
- [x] Implement one shared presence resolver used by save/publish/preparation and every
  fresh model/STT/TTS reader. Preserve current named binding semantics, final transaction
  guards, tenant data isolation and fail-closed behavior.
- [x] Pin safe selected credential scope/identity at preparation boundaries and reject
  unexpected rebinding. Already-initialized clients retain their owned configuration;
  new preparation uses the current authorized selection. Cache keys include tenant,
  provider, binding and selected scope/identity; never share tenant call data.
- [x] Wire one reviewed provider flow through Console and prove two tenants inherit a
  platform provider while a third overrides it, with no secret exposure or failure fallback.

### 3. Verify and route scoped Telnyx webhooks

- [x] Store Telnyx verification configuration beside its scoped service identity, with a
  single selected public key per scope. Keep API credentials encrypted and the verification
  public key non-secret. Update telephony foreign-key constraints without permitting an
  unrelated tenant credential or application to satisfy a binding.
- [x] Add tenant Voice API application bindings referencing the selected credential scope;
  validate ownership and reject ambiguous mappings. Configure application ID and number
  routing before reporting telephony ready; API/public key alone are insufficient.
- [x] Mount both approved `/webhooks/...` routes through the existing Phoenix/Gateway
  boundary. Select exactly one verifier from the route; reject unknown tenants, missing
  public keys, malformed signatures, stale events and wrong application ownership.
- [x] Generate outgoing callback URLs using the same public origin and scope as the UI.
  Preserve call/leg deduplication, exact live-owner dispatch and tenant media-token ownership.
  Review initialized-key lifetime versus a replaced scoped key explicitly; never try the
  other scope's key on a verification failure or change an active leg's ownership.
- [x] Remove `/api/telephony/telnyx/:ingress/events`, its verifier-selection path and
  legacy callback generation. Only explicit platform/tenant webhook paths remain. Update
  callers and tests; requests to removed paths must fail without dispatch. Retain media
  URL/token and Twilio contracts. Do not delete stored credentials as part of route removal.
- [x] Prove signed platform and tenant HTTP requests through persisted encrypted bindings,
  cross-scope key rejection, cross-tenant application rejection, duplicates, storage outage
  and malformed public configuration. Live checks stay in the tagged integration lane.

### 4. Complete Console integration and migration acceptance

- [x] Wire platform/tenant service pages and onboarding to effective-service metadata.
  Show source and unavailable/invalid states and explicit restore/override actions.
- [x] Make service scope changes deliberate and display the resulting webhook URL change.
  Keep secrets write-only and isolate operator/platform authority from tenant administration.
- [x] Derive progress from durable resources after reload, including telephony application
  and number setup. Preserve existing tenant services and prepared/live-call contracts.
- [x] Run focused red-green tests per owning boundary, browser inspection, required umbrella
  checks and a migration/restart exercise. Record deferred provider integrations accurately.

## Alternatives and design review

One generic webhook path can work with a trusted lookup, but it hides the explicit verifier
scope selected by the user. Implicit retry with a platform key after tenant failure violates
that contract. Copying platform credentials into each tenant creates divergent records and
unnecessary secret handling. Making every tenant create credentials again defeats inheritance.
Reintroducing the deleted static application fallback would bypass persisted credentials.

Local design review, 2026-09-19: separated credential owner from call/application tenant,
limited the initial Telnyx account cardinality, retained named AI bindings, and added legacy
route, encryption migration, initialized-client and media-token gates. Platform provider
management uses the existing operator session. The subsequent user clarification adds
programmatic operator API-key issuance for principal-aware call-spec writes; this is
now an explicit dependency in A3. Application discovery/creation in Telnyx is deferred;
the first production binding flow can accept an application ID. This is a plan review,
not evidence that the backend checkpoints are implemented.

## Storybook verification

The scope and URL tests failed before implementation. The final Console frontend
suite passes 169 tests across 28 files; TypeScript and ESLint pass, and the scoped
Storybook build passed. Chrome verified desktop/mobile connect/edit,
platform/inherited/override states, clipboard feedback and URL presentation in both
themes. Root static checks pass. An earlier umbrella run passed; the latest run has
two backend timing failures in participant shutdown and room audio egress, whose
affected test files pass independently. See the [initial checkpoint labnotes](../labnotes/20260919-0036-scoped-service-onboarding.md)
and [final review evidence](../labnotes/20260919-0205-saved-credential-placeholders.md).
This verifies the prototype, not the planned production routes or credential ownership.
