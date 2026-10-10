# Platform bootstrap and demo tenant

Status: in progress. Requested 2026-09-16; first-run Storybook states completed 2026-09-18.
Prerequisites: [Tenant administration](tenant-call-specs-and-api-keys.md),
[Tenant credentials/platform configuration](tenant-provider-credentials-and-platform-configuration.md), and
[Operator login/admin dashboard](operator-login-and-admin-dashboard.md).
The index delivers this after the [debug console](call-debug-console.md) so the first provisioned
call has a usable destination; its storage/auth implementation does not depend on UI internals.
Sources: [Developer console design](developer-console-and-onboarding.md),
[Tenant control plane](../../docs/tenant-control-plane.md), [Provider storage](../../docs/provider-credential-storage.md).

The 2026-09-19 [platform and tenant services plan](platform-and-tenant-services.md)
extends the tenant-only contracts below with explicit platform inheritance and tenant
overrides. Its Storybook work and all 13 implementation checkpoints are accepted:
scoped credential storage/readers, principal-aware operator/tenant authoring, Console
management, inherited onboarding, scoped Telnyx verification/application routing,
legacy webhook removal and final migration/restart acceptance.

Credential presence supersedes the earlier disabled/dormant policy: a tenant credential
takes precedence; removing it restores platform inheritance. Tenant API-key authors
still require tenant-owned services even when an operator used platform services in
the existing spec. Runtime resolves the selected tenant's effective credentials.

The final combined suite passes 1,798 tests with zero failures and 40 exclusions,
plus 187 frontend tests, all root static checks, desktop/mobile Chrome, restart,
re-encryption and guarded schema rollback. No live-provider call is claimed.
The platform-key and demo-bootstrap gates below remain independently tracked;
the services follow-up does not establish a durable installation/demo identity.
A3 implements trusted key bootstrap/replacement/revocation, authenticated platform
status and operator/tenant call-spec HTTP writes. See the
[operator-key contract](../../docs/operator-api-key-authoring.md).

## Consolidated planning sources — 2026-10-09

Supporting records: [accepted platform/tenant services](platform-and-tenant-services.md),
[shared tenant onboarding](tenant-setup-experience.md) and
[Console/first-use design](developer-console-and-onboarding.md). They preserve scope
clarifications, prototype review and the separately accepted 13-checkpoint services
follow-up. This parent retains its independent platform-key/demo-identity gates.

The accepted service contract selects the exact tenant provider/name credential when
present, otherwise its platform counterpart; invalid or unreadable tenant credentials
fail closed. Tenant writers require tenant-owned references across the complete resulting
call spec and final transaction guards; installation operators may author platform-backed
specs. Running an authorized publication is a separate permission. Prepared reads pin
selected owner/credential identity. Tenant Services exposes tenant-owned credentials only;
retired setup-services bookmarks redirect there. Provider testing is ephemeral and separate
from locally validated encrypted Save.

Scoped Telnyx ingress chooses the verifier from `/webhooks/platform/telnyx` or
`/webhooks/tenants/:tenant_key/telnyx` before authenticated application-to-tenant dispatch,
with no attempt to use another scope's key after failure. The accepted follow-up includes
application/number setup, one configured public origin, legacy webhook removal and
migration/restart/rotation checks. Remote provisioning/reachability and live carrier
acceptance remain separate. Earlier disabled/dormant, inherited-tenant-UI and prototype-only
statements in the companion retain historical context, not active policy.

## Runnable outcome

A trusted developer issues a platform-level API key once and authenticates a platform API operation.
An authenticated operator creates or adopts one demo tenant and provisions the existing speech/model
credentials for that tenant through the React admin application.
Repeating setup or restarting the process retains the same tenant and saved setup state. The
existing published-call-spec/prepared-call workflow can then run through the debug console.

## Contracts

- Platform keys are distinct from existing tenant `admin`/`calls` keys and participant admission.
  Use an explicit platform principal, hash-only high-entropy key storage and a closed platform
  administrator grant. No wildcard tenant and no implicit promotion of a tenant key.
- First issuance is a trusted local command, not an anonymous HTTP bootstrap route. No default
  key or credential in `env.sample`; show newly issued plaintext once through protected output.
  Subsequent invocations do not silently issue keys. Explicit trusted replacement is available
  if that one-time value is lost; do not require a periodic rotation policy or key-management UI.
- Platform HTTP operations live at a clearly separate Gateway boundary, proposed `/api/platform`.
  Initially expose only the operations needed for setup: authenticated status, demo-tenant
  create/adopt/lookup, provider provisioning metadata/write, and delegation to the existing
  call spec publication/preparation workflows. Select the target tenant explicitly every time.
  Do not expose raw provider-secret reads, arbitrary internal Calls methods or a general CRUD API.
- Platform keys authenticate programmatic `/api/platform` operations only. They are not accepted by
  the operator login page and are never exchanged for a browser session. The existing operator
  session authorizes Console setup actions; protect cookie-authenticated writes against CSRF.
  No key appears in query strings, client configuration, local storage, diagnostics or RTVI.
- Calls owns platform workflows and ports; Persistence owns schema/digest validation and atomic
  setup records. Gateway/Console receive public workflow results and never query Repo directly.
  The engine and tenant-only Gateway embedding acquire no Console/platform-setup dependency.
- Demo identity is durably associated with this installation/setup record, not found by an
  untrusted display name. Concurrent creation converges on one tenant. An explicit adoption of
  configured `VXPIPE_DEV_TENANT` retains its exact identity and existing data.
- Setup progress is derived from durable resources. An interrupted sequence resumes; a key,
  credential or call spec is never recreated solely because a browser progress flag was lost.
  A DB/keyring failure is a blocked step, not a fresh install or credential-free fallback.
- Keep recoverable provider credentials in the existing encrypted tenant store. First-use input
  supports Google/Deepgram and the existing Zenmux alternative; one Deepgram credential can
  cover STT and TTS. Preserve provider/name binding semantics and safe metadata responses.
- Offer a separate read-only credential test against a provider-owned, bounded authentication
  endpoint. Saving performs local schema validation and encrypted persistence without requiring an
  upstream probe, and remains available when testing is unsupported. Never return raw secrets.
  Default tests use controlled adapters; live-provider checks remain in the tagged integration lane.
- Add provider setup as React components in the Console admin application. Build small field,
  provider-configuration and error components and complete mocked Storybook states before connecting
  operator-authenticated writes. The login/code-entry page remains the only server-rendered UI.
- Do not silently replace an existing provider credential. Report the existing binding and let
  the operator resolve any deliberate change through an explicit supported operation. This
  milestone adds neither third-party key rotation nor authentication for unsupported providers.

## Checkpoint 1 — Establish platform authority

- [x] Specify the new principal/key storage and public operation contracts separately from the
  existing tenant principal; review owner/dependency and first-bootstrap trust boundaries.
- [ ] Red-test trusted first issuance, one-time secret output, hash-only persistence and restart,
  incorrect/tenant/participant keys, expired/inactive key rejection and database failure.
- [x] Implement the trusted bootstrap command plus authenticated platform status/tenant operation.
  Confirm an ordinary tenant key still authenticates only within its existing scope.
- [ ] Authorize the matching Console setup actions through the existing operator session while
  keeping platform API-key authentication confined to `/api/platform`; verify CSRF and secret filtering.
- [x] Document a source-development path from migrations/keyring to one issued key and one
  authenticated operation. Existing keys and setup state survive repeat startup.

Exit: the developer can perform a real authenticated platform operation without broadening tenant keys.

## Checkpoint 2 — Resume demo setup and provision a first call

- [x] Build and review the demo-workspace and provider-setup components and complete page states in
  Console Storybook before adding production endpoint calls.
- [ ] Red-test create/adopt, concurrent/retried setup, name collisions, missing resources and restart.
  Include existing configured demo tenants and interrupted credential setup.
- [ ] Implement durable demo binding and narrow platform-to-tenant workflow delegation using
  existing tenant provisioning, encrypted credential, call spec and call-preparation boundaries.
- [ ] Report locally provisioned STT/TTS/LLM requirements from metadata. Permit the same Deepgram
  binding for speech; return no secret on status/read. Upstream success is not inferred from save.
- [ ] Prove a platform operator provisions the intended tenant, then uses a current inline
  call spec and the debug console's ordinary preparation path with exact tenant credentials.
  Another tenant's binding must not satisfy missing requirements.
- [ ] Verify a restart/retry creates no duplicate demo tenant or unintended key/binding; failed
  steps have safe actionable results. Record migration and operator-command evidence.

Exit: platform-authenticated source setup yields one stable, tenant-bound runnable demo workspace.

## Acceptance and completion

- [x] Trusted bootstrap, platform API authentication and operator browser sessions use explicit,
  distinct authorities.
- [x] First issue is one-time output; existing/lost keys follow documented explicit local actions.
- [ ] Two tabs, retry after response loss and fresh application processes converge on one demo
  identity; adoption preserves existing call specs and credentials.
- [ ] Missing/wrong platform authority and cross-tenant substitutions cause no mutation or disclosure.
- [ ] Database/keyring failures preserve prior progress and never fall through to old provider env.
- [ ] Focused Calls/Persistence/Gateway/Console checks and all common umbrella gates pass.
- [ ] Inspect any changed sign-in/setup UI in a rendered browser using `agent-browser`.
- [ ] Commit each passing checkpoint with migration/tests/docs/labnotes, then synchronize the index.

## Scope boundaries

No general IAM, billing, organization model, third-party key lifecycle, provider
expansion, mandatory cloud credentials, packaging or live-carrier acceptance is included.

## Specification review

Local review, 2026-09-16: existing keys require a tenant, so a separate platform authority is
necessary; bootstrap is trusted, public mutations are guarded, and existing tenant workflows
retain their boundaries. Idempotent demo binding prevents duplicate first-use resources. The
later onboarding milestone owns example catalog installation and its UI, avoiding duplicate seeds.
Specification only: no implementation, migration, independent-agent review or acceptance is claimed.

Amendment review, 2026-09-17: operator browser login is now owned by the preceding independently
reviewed milestone. Platform keys remain programmatic credentials; Console setup actions use the
separate operator session. Provider setup is React and must reach a complete mocked Storybook page
before production integration. The original demo identity and credential-storage contracts remain.

Implementation note, 2026-09-18: `vxpipe_console/Onboarding` now covers automatic Demo
creation, provider selection, credential entry, credential progress/failure, historical validation
timestamps, optional three-example installation, completion, unavailability, light theme and narrow
layout. Google Vertex AI is intentionally absent from the chooser until its project/service-account
credential shape is implemented; presenting it as an API-key provider would be misleading.

Amendment review, 2026-09-21: **Test credentials** and **Save** are independent actions. Testing is
ephemeral and saving does not depend on provider availability. This supersedes this milestone's
earlier coupled validation-before-save and new validation-timestamp contract.

Storybook refinement, 2026-09-18: the [tenant setup decision](tenant-setup-experience.md)
adds credential modals, three-capability coverage, a separate recipe screen and resumable
tenant-directory entry points. Stories cover partial, ready, failure, provider
choice and responsive/theme states. New demo tenants use the display name `Demo`;
existing names are preserved. These revised pages remain prototypes pending user review
and production integration. The platform-authority and durable readiness gates above
remain incomplete; browser simulation is not evidence of those backend contracts.

The user's follow-up makes this shared setup flow apply to every new tenant. The
directory's name-only creation dialog proceeds directly to that tenant's services;
incomplete tenants can resume it. Telephony is optional for WebRTC call specs.
The creation/redirect behavior is prototyped in Storybook, with production wiring pending.

Three-step refinement, 2026-09-18: shared tenant copy and navigation now separate
Setup services, Create API Keys and Setup Call Specs. The API-key prototype offers
`calls` or `admin` + `calls`, matching the independent grants in Administration.
It shows a nonfunctional key once and retains tenant-specific metadata afterward.
This is a reviewed-code permission mapping and frontend prototype, not a new
issuance endpoint or completed platform-authority milestone.

Service-picker refinement, 2026-09-18: compact AI provider cards, an optional
Telephony section, connected-service management and a full-catalog service dropdown
replace the capability checklist. Speech-to-speech readiness is demonstrated only
in dedicated future-capability stories; the normal catalog and runtime integrations
are unchanged. Local design review preserves credential ownership, tenant isolation,
and the production implementation order. Per-recipe compatibility remains separate
from overall service readiness. Verification is recorded in the
[checkpoint labnotes](../20260918-2022-compact-service-picker.md).

The follow-up makes Telephony always visible and explicitly optional. Connect a
service uses a dropdown with inline provider-specific fields, replacing the earlier
search/list picker. Switching services discards the previous credential draft.

Service-picker review, 2026-09-18: onboarding now offers Deepgram, Rime, Google AI
Studio and Telnyx. Other providers are deferred from this prototype UI. Telnyx uses
one connection across AI and telephony sections; its public key is optional for
AI use and required for the telephony credential state. Rime/Telnyx AI execution,
production credential persistence and number routing remain unimplemented gates;
see the [tenant setup decision](tenant-setup-experience.md).

Follow-up, 2026-09-21: the service picker now takes installed capabilities from the provider
registry through the authenticated binding-directory response. Current provider choices and badges
are recorded in the [tenant setup decision](tenant-setup-experience.md); the earlier prototype
speech-to-speech preview and future capability labels were removed.

### Consolidation design review — 2026-10-09

The documentation consolidation received a read-only parallel review of source contracts,
owner requirements and dependency order. Detailed sources remain linked companions;
the existing milestone/index identities, order and completion flags are unchanged.
Historical/proposed obligations are qualified above and in companion provenance banners.
This is specification organization review, separate from runtime implementation progress.
Migration checks and reviewer findings are recorded in the
[consolidation labnote](../20261009-1439-consolidate-doc-history.md).
