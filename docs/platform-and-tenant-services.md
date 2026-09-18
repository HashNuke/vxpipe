# Platform and tenant services

Status: Storybook prototype implemented and verified, pending user review; backend
plan, not implemented.
Requested 2026-09-19. This extends the previously tenant-only credential decision.
It does not restore environment-based provider credentials or implicit failure fallback.

## User contracts

- Configure a provider once under **Platform services**, or configure a tenant override.
  Use “platform” consistently; “account” could mean an upstream Telnyx account.
- Tenant cards identify exceptions with **Inherited from platform**, **Tenant override**,
  or **Disabled for this tenant**. Ordinary tenant and platform cards omit redundant
  scope labels. Inherited capabilities count toward onboarding readiness. New tenants
  inherit available platform defaults.
- Resolve each provider/named binding using an explicit tenant policy: inherit, override,
  or disabled. A tenant override replaces the whole credential set. Its missing,
  revoked, invalid or unreadable credentials fail; they never trigger platform fallback.
  Named bindings retain their names rather than silently substituting `default`.
- “Use platform service” explicitly removes the override policy; disabling creates a
  durable tenant policy so an inherited provider does not reappear on refresh.
- An inherited service opens a read-only explanation with **Override for this tenant**
  and **Disable for this tenant** actions. Platform credentials are edited at platform
  scope. The operator UI currently has installation-wide authority; future tenant-only
  principals must not acquire platform edit authority from these UI actions.
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

Calls `ProviderCredential` and `ProviderCredentials` currently require a tenant key.
Persistence `Schema.ProviderCredential` requires a tenant foreign key and uses
tenant/provider/name uniqueness; encryption and repository guards assume tenant ownership.
`TelephonyService` stores the public key and enforces a same-tenant credential binding.
Gateway `ServiceRegistry` currently looks up globally unique ingress keys, and
`TelnyxEvents` verifies through a resolved tenant service. Existing initialized legs
retain authentication for callbacks/media/cleanup during storage outages.

Keep responsibilities: Calls owns scoped service policies and safe identities;
Persistence owns encryption, schema, constraints and transactions; Gateway owns
provider protocols and signed webhook dispatch; Console owns operator endpoints and UI.
No Console dependency in the engine or Gateway, and no Repo calls in those applications.

## Implementation sequence

### 1. Storybook review checkpoint

- [x] Show tenant and platform Telnyx URLs in connect/edit states with copy feedback.
- [x] Add Platform services using the existing AI/optional-telephony grids and modals.
- [x] Show inherited, tenant override, disabled and failed-override states; preserve
  independent tenant progress and platform changes across prototype navigation.
- [x] Verify readiness and recipes use effective services, including newly created tenants.
- [x] Inspect desktop/mobile, light/dark, create/edit and clipboard behavior.

This checkpoint uses synthetic state only. It does not enable new providers or implement
remote application provisioning, credential persistence, verification or routing.

### 2. Persist and use an inherited AI provider

- [ ] Define a tagged credential owner (`platform` or tenant key), distinct from the
  consuming tenant. Add scope-aware unique/check constraints, metadata and tenant
  inherit/override/disabled policy records. Never use a fake platform tenant.
- [ ] Migrate existing credentials and references as tenant-owned without changing IDs
  or effective behavior. Version authenticated encryption context where needed;
  test existing decrypt, replacement, re-encryption, interruption and rollback behavior.
- [ ] Add explicit platform operator CRUD/validation endpoints using the current session
  and CSRF protections. Tenant keys cannot write/read platform secrets; effective-list
  responses contain safe source/readiness metadata and URLs only.
- [ ] Implement one shared policy resolver used by save/publish/preparation and every
  fresh model/STT/TTS reader. Preserve current named binding semantics, final transaction
  guards, tenant data isolation and fail-closed behavior.
- [ ] Pin safe selected credential scope/identity at preparation boundaries and reject
  unexpected rebinding. Already-initialized clients retain their owned configuration;
  new preparation uses the current authorized selection. Cache keys include tenant,
  provider, binding and selected scope/identity; never share tenant call data.
- [ ] Wire one reviewed provider flow through Console and prove two tenants inherit a
  platform provider while a third overrides it, with no secret exposure or failure fallback.

### 3. Verify and route scoped Telnyx webhooks

- [ ] Store Telnyx verification configuration beside its scoped service identity, with a
  single selected public key per scope. Keep API credentials encrypted and the verification
  public key non-secret. Update telephony foreign-key constraints without permitting an
  unrelated tenant credential or application to satisfy a binding.
- [ ] Add tenant Voice API application bindings referencing the selected credential scope;
  validate ownership and reject ambiguous mappings. Configure application ID and number
  routing before reporting telephony ready; API/public key alone are insufficient.
- [ ] Mount both approved `/webhooks/...` routes through the existing Phoenix/Gateway
  boundary. Select exactly one verifier from the route; reject unknown tenants, missing
  public keys, malformed signatures, stale events and wrong application ownership.
- [ ] Generate outgoing callback URLs using the same public origin and scope as the UI.
  Preserve call/leg deduplication, exact live-owner dispatch and tenant media-token ownership.
  Review initialized-key lifetime versus a replaced scoped key explicitly; never try the
  other scope's key on a verification failure or change an active leg's ownership.
- [ ] Migrate existing `/api/telephony/telnyx/:ingress/events` callers deliberately. Preserve
  the legacy route only against its exact existing tenant/service binding during transition;
  never redirect signed requests or interpret ingress keys as tenant keys. Document the
  remote URL update and cutover; retain existing media URL/token contracts.
- [ ] Prove signed platform and tenant HTTP requests through persisted encrypted bindings,
  cross-scope key rejection, cross-tenant application rejection, duplicates, storage outage
  and malformed public configuration. Live checks stay in the tagged integration lane.

### 4. Complete Console integration and migration acceptance

- [ ] Wire platform/tenant service pages and onboarding to effective-service metadata.
  Show source, unavailable/invalid/disabled states and explicit restore/override actions.
- [ ] Make service scope changes deliberate and display the resulting webhook URL change.
  Keep secrets write-only and isolate operator/platform authority from tenant administration.
- [ ] Derive progress from durable resources after reload, including telephony application
  and number setup. Preserve existing tenant services and prepared/live-call contracts.
- [ ] Run focused red-green tests per owning boundary, browser inspection, required umbrella
  checks and a migration/restart exercise. Record deferred provider integrations accurately.

## Alternatives and design review

One generic webhook path can work with a trusted lookup, but it hides the explicit verifier
scope selected by the user. Implicit retry with a platform key after tenant failure violates
that contract. Copying platform credentials into each tenant creates divergent records and
unnecessary secret handling. Making every tenant create credentials again defeats inheritance.
Reintroducing the deleted static application fallback would bypass persisted policies.

Local design review, 2026-09-19: separated credential owner from call/application tenant,
limited the initial Telnyx account cardinality, retained named AI bindings, and added legacy
route, encryption migration, initialized-client and media-token gates. Platform provider
management can use the existing operator session; it does not depend on completing
programmatic platform API-key issuance. Application discovery/creation in Telnyx is deferred;
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
This verifies the prototype, not the planned production routes or credential policies.
