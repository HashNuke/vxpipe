# Platform bootstrap and demo tenant

Status: planned, not implemented. Requested 2026-09-16; local specification review recorded below.
Prerequisites: [Tenant administration](tenant-definitions-and-api-keys.md),
[Tenant credentials/platform configuration](tenant-provider-credentials-and-platform-configuration.md), and
[Operator login/admin dashboard](operator-login-and-admin-dashboard.md).
The index delivers this after the [debug console](call-debug-console.md) so the first provisioned
call has a usable destination; its storage/auth implementation does not depend on UI internals.
Sources: [Developer console design](../developer-console-and-onboarding.md),
[Tenant control plane](../tenant-control-plane.md), [Provider storage](../provider-credential-storage.md).

## Runnable outcome

A trusted developer issues a platform-level API key once and authenticates a platform API operation.
An authenticated operator creates or adopts one demo tenant and provisions the existing speech/model
credentials for that tenant through the React admin application.
Repeating setup or restarting the process retains the same tenant and saved setup state. The
existing published-definition/prepared-call workflow can then run through the debug console.

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
  definition publication/preparation workflows. Select the target tenant explicitly every time.
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
  credential or definition is never recreated solely because a browser progress flag was lost.
  A DB/keyring failure is a blocked step, not a fresh install or credential-free fallback.
- Keep recoverable provider credentials in the existing encrypted tenant store. First-use input
  supports Google/Deepgram and the existing Zenmux alternative; one Deepgram credential can
  cover STT and TTS. Preserve provider/name binding semantics and safe metadata responses.
- Add provider setup as React components in the Console admin application. Build small field,
  capability-status and error components and complete mocked Storybook states before connecting
  operator-authenticated writes. The login/code-entry page remains the only server-rendered UI.
- Do not silently replace an existing provider credential. Report the existing binding and let
  the operator resolve any deliberate change through an explicit supported operation. This
  milestone adds neither third-party key rotation nor authentication for unsupported providers.

## Checkpoint 1 — Establish platform authority

- [ ] Specify the new principal/key storage and public operation contracts separately from the
  existing tenant principal; review owner/dependency and first-bootstrap trust boundaries.
- [ ] Red-test trusted first issuance, one-time secret output, hash-only persistence and restart,
  incorrect/tenant/participant keys, expired/inactive key rejection and database failure.
- [ ] Implement the trusted bootstrap command plus authenticated platform status/tenant operation.
  Confirm an ordinary tenant key still authenticates only within its existing scope.
- [ ] Authorize the matching Console setup actions through the existing operator session while
  keeping platform API-key authentication confined to `/api/platform`; verify CSRF and secret filtering.
- [ ] Document a source-development path from migrations/keyring to one issued key and one
  authenticated operation. Existing keys and setup state survive repeat startup.

Exit: the developer can perform a real authenticated platform operation without broadening tenant keys.

## Checkpoint 2 — Resume demo setup and provision a first call

- [ ] Build and review the demo-workspace and provider-setup components and complete page states in
  Console Storybook before adding production endpoint calls.
- [ ] Red-test create/adopt, concurrent/retried setup, name collisions, missing resources and restart.
  Include existing configured demo tenants and interrupted credential setup.
- [ ] Implement durable demo binding and narrow platform-to-tenant workflow delegation using
  existing tenant provisioning, encrypted credential, definition and call-preparation boundaries.
- [ ] Report locally provisioned STT/TTS/LLM requirements from metadata. Permit the same Deepgram
  binding for speech; return no secret on status/read. Upstream success is not inferred from save.
- [ ] Prove a platform operator provisions the intended tenant, then uses a current inline
  definition and the debug console's ordinary preparation path with exact tenant credentials.
  Another tenant's binding must not satisfy missing requirements.
- [ ] Verify a restart/retry creates no duplicate demo tenant or unintended key/binding; failed
  steps have safe actionable results. Record migration and operator-command evidence.

Exit: platform-authenticated source setup yields one stable, tenant-bound runnable demo workspace.

## Acceptance and completion

- [ ] Trusted bootstrap, platform API authentication and operator browser sessions use explicit,
  distinct authorities.
- [ ] First issue is one-time output; existing/lost keys follow documented explicit local actions.
- [ ] Two tabs, retry after response loss and fresh application processes converge on one demo
  identity; adoption preserves existing definitions and credentials.
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
