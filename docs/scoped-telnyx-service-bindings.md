# Scoped Telnyx service bindings

Decision: 2026-09-19. Design, implementation and final C/D acceptance complete under the
[platform and tenant services plan](platform-and-tenant-services.md).

## Credential ownership and application identity

Keep the existing encrypted provider binding as the credential owner. Telnyx's
optional `public_key` joins `api_key` in that binding's encrypted payload; validate
its base64 Ed25519 representation locally. An API-key authentication check does not
prove that the supplied public key belongs to that upstream account. Incoming signed
requests provide verification evidence; do not label a save as a working phone route.
The directory exposes only whether the public-key field is configured.

An explicit `credential_name: "telnyx"` on a tenant telephony service opts into the
shared presence resolver. Its stored application record has no credential ID or public
key copy. Resolve the consuming tenant's exact primary Telnyx binding under the same
locks used for AI/speech. The resolved snapshot supplies credential owner, ID and
public key; prepared references pin owner/ID while initialized clients retain their
private snapshot. Missing tenant credentials inherit platform credentials; existing
invalid or unreadable tenant credentials fail closed. Missing credentials at both scopes are unavailable.
Operator authoring may use either scope; tenant authoring requires the selected owner
to be that tenant, including unchanged references in an edited spec.

Each new scoped application belongs to one tenant. Enforce uniqueness of its Telnyx
application ID among scoped bindings. The new scope URLs select only the primary
`telnyx` credential name; alternate named accounts do not become additional verifiers.
Shared Voice API applications and number-based tenant selection remain deferred.

## Webhook routes and stored identities

The user removed the legacy webhook compatibility requirement on 2026-09-19.
Only the explicit platform and tenant URLs are supported. The old ingress-key events
route, its verifier-selection branch and outgoing callback fallback are removed.
A signed request to the removed path cannot dispatch. Telnyx live-owner lookup uses
only scope/application/provider-leg identity (or exact client state within that scope).
Media/token and Twilio contracts remain separate.

Gateway rejects unscoped Telnyx bindings before constructing a fresh live client. This
change does not rewrite or delete stored credentials, application metadata or historical
calls. Configure an explicit primary scoped binding and use its matching webhook URL.
There is no inference from an old credential ID or public key to the new primary scope.
The existing schema rollback guard still refuses to discard scoped bindings.

Persisted prepared plans predating the new reference fields decode with explicit
legacy defaults. New scoped references pin credential owner, ID and name; replacing
credentials within that ID may refresh a client, but deletion/recreation or scope change
requires fresh preparation. Legacy references preserve their exact tenant credential
semantics. Raw application metadata and a resolved credential snapshot are different
states: never compare an unresolved scoped record's missing credential ID as if it
were a previously authorized selection.

## Delivery order and verification

Scoped ingress is implemented and verified in C2. For a
fresh call, the URL selects the primary credential before any application lookup.
After verifying the raw bytes in the standard 300-second window, lookup the explicit
application mapping and compare its effective credential owner, ID and version with
the verified selection. Also enforce a stricter application freshness setting when
configured. A concurrent credential/scope change rejects the request; it never retries
another key. Tenant URLs cannot inherit the platform verifier.

An initialized incoming or outgoing Telnyx leg registers a scope/application/provider-leg
locator. Twilio retains its separate ingress locator. Only an owner within the URL-selected
scope may provide its retained verifier. This preserves callbacks and incoming
duplicate handling during storage outages or credential replacement, including
callbacks without client state. The exact authenticated owner receives dispatch;
owner death does not trigger a new lookup. Initialized owners retain their configured
freshness window. C3a supplies outgoing URL generation and the common public origin;
D verifies removal and final acceptance.

C1 configuration uses the trusted `ProviderCredentials.provision/6` host API to store
the primary `telnyx` credential with `api_key` and optional `public_key`. The existing
`mix vxpipe.telephony_service.register --tenant TENANT_KEY --file service.json` command
accepts scoped application metadata:

```json
{
  "name": "support",
  "provider": "telnyx",
  "credential_name": "telnyx",
  "provider_connection_id": "VOICE_API_APPLICATION_ID",
  "ingress_key": "support-tenant-ingress"
}
```

Registration requires an effective credential with a valid verification key. It does
not publish a phone-number route or configure the remote Telnyx application. Use the
scope URL shown by Console in the Voice API application. C3a configures credentials
and URLs; C3b supplies application configuration and published number progress.

- [x] C1: store the optional scoped verification key, register a tenant application
  against the effective credential name, authorize call-spec writes, and resolve new
  Gateway clients. Preserve legacy ingress so the intermediate checkpoint is runnable.
  Test two inheriting tenants, tenant override/removal/restore, cross-tenant rejection,
  exact prepared identity and no secret exposure.
- [x] C2: add route-selected platform/tenant signature verification and explicit
  application routing. A body identifier may locate an initialized owner only within
  the route-selected credential scope; it cannot choose another scope's verifier.
  Authenticate the exact raw bytes before trusting new application routing. Preserve
  initialized owner credentials and duplicate/outage behavior.
- [x] C3: expose public-key configuration, application bindings and matching webhook
  URLs in the operator Console, with durable metadata and browser verification.
- [x] C3a: production credential form, configured-field metadata, shared public origin
  and matching UI/outgoing scoped URLs. Browser/restart and all required checks pass.
- [x] C3b: tenant application configuration and published number-route progress.
- [x] C3b1: operator application create/update API and bounded, durable published-route metadata.
  API implementation, owning application suites and final umbrella acceptance pass.
- [x] C3b2: Console application form, progress, recovery and browser/restart verification.
  Implementation, all 187 frontend tests, desktop/mobile/restart checks and independent
  finish review pass, together with final combined umbrella acceptance.
- [x] D removes the legacy Telnyx webhook path and callback generation, then completes
  restart/rollback/re-encryption and final umbrella acceptance from the parent plan.
- [x] D1: remove the old route, verifier selection and callback generation; reject
  unscoped fresh Telnyx clients and preserve media/Twilio behavior.
- [x] D2: final combined application/number setup, restart, re-encryption and rollback acceptance.

Design review: keep credentials separate from tenant application identity; reuse the
existing owner/presence resolver rather than introduce another fallback mechanism.
Reject relaxing every legacy ownership constraint, silently copying platform secrets
into tenant rows, and selecting a verification scope from unsigned event fields.
C1 evidence: 24 focused persistence and six Gateway reader tests pass, with disposable
database upgrade/rollback/restart acceptance. The umbrella run covers 1,770 tests;
one obsolete reference-field assertion was corrected and the full 116-test Calls suite
rerun. C2's full umbrella passes 1,781 tests with zero failures and 40 exclusions;
all static gates pass. C3a now passes 1,786 umbrella tests, 183 frontend tests, all
static checks and desktop/mobile/restart verification. C3b passes its owning suites,
187 frontend tests and rendered/restart checks. D2's final full umbrella passes
1,798 tests with zero failures and 40 exclusions, plus all root static gates.
The earlier native handoff timeout did not recur in five isolated runs or the final
full suite. Live-provider verification is not claimed.

Console dependency review, 2026-09-19: move D's common public-origin and outgoing
scope-URL generation into C3a so the displayed URL and newly initialized callbacks
agree when the form ships. Preserve the explicit telephony-origin override, including
path prefixes, and default public APP_HOST to HTTPS. Local HTTP is a configuration
preview, not phone readiness. C3b follows the verified binding/ingress boundaries and
keeps application identity separate from credential edits. The latest user correction
replaces deliberate legacy cutover with webhook deletion.
D owns final restart/re-encryption/rollback acceptance. C3b and D are implemented and
accepted; their evidence remains distinct from live-provider verification.

Telnyx documents account-level Ed25519 verification over the original request body
and application-owned webhook configuration. These support the separation above;
the Vxpipe owner/presence and migration decisions are local design choices.
See [webhook verification](https://developers.telnyx.com/docs/development/api-fundamentals/webhooks/receiving-webhooks)
and [Voice API applications](https://developers.telnyx.com/api-reference/call-control-applications/create-a-call-control-application).

Legacy-removal design review: D1 depends on C1/C2/C3a and can run before C3b because
it changes neither Console application management nor stored credential ownership.
Remove both routing and callback generation together; reject unsupported live bindings
before dialing rather than send callbacks to a removed URL. Do not silently reinterpret
legacy IDs as primary credentials. Preserve protocol/body-limit, retained-owner, media
and Twilio tests by moving Telnyx fixtures onto scoped credentials and webhook URLs.
D1 is implemented and reviewed. Two red regressions pass, the encrypted two-carrier
signature check passes, and both carrier harnesses pass six combined runs. Final
umbrella: 1,788 tests, zero failures, 40 excluded; all root static gates pass.

## Console application configuration design review

C3b follows the verified C1/C2/C3a/D1 boundaries. Split its operator API and persistence
work (C3b1) from the rendered Console workflow (C3b2) to keep both commits reviewable.
Neither checkbox is complete merely because this design is recorded.

The installation operator can add a tenant-local service name, Voice API application
ID and optional outbound caller number. The server fixes the provider and primary
credential name to Telnyx, and generates the stable media ingress key. Editing changes
only the application ID and outbound number; tenant, service UUID, name, credential
binding and ingress key remain stable. Reuse effective credential locks and existing
application uniqueness constraints. A changed application ID invalidates an old prepared
reference; already initialized legs retain their exact configuration.

Expose these operations through the existing installation-session and CSRF boundary.
Reject caller-supplied credential IDs, scope, keys, ingress paths and carrier options.
No remote application discovery or provisioning occurs. Credentials remain configured
separately. A missing or unusable effective verification key prevents application writes.

A bounded operator read lists this tenant's scoped applications and only number routes
belonging to current published call-spec revisions. Report duplicate service/number
mappings as ambiguous, including conflicts beyond the display limit. Drafts, superseded
revisions and other tenants cannot count toward progress. The Console combines this
durable metadata with effective credential/public-key and origin metadata. Saved keys
alone do not establish phone readiness; local configuration is distinct from remote
Telnyx setup and a successful live call.

Number routing continues through the existing authorized call-spec save/publish boundary;
this slice adds its progress view, not a second call-spec editor or separate routing store.
Reject copying platform keys into applications, deriving tenant identity from phone numbers,
or weakening the older tenant-credential inventory contract to accommodate applications.
Application metadata has its own operator view and never masquerades as a credential.

Acceptance checks pass for explicit operator authority, CSRF, input allowlists,
two tenants' mappings with inheritance and overrides, duplicate application rejection,
foreign edits, unusable credentials, prepared/live identity rules, current published
routes, conflicts, bounds and secret-safe responses. C3b2 verifies desktop/mobile,
reload/restart, missing-key and request-failure states. D2 verifies combined
replacement/re-encryption/rollback acceptance. See the
[final labnotes](../labnotes/20260919-1304-scoped-services-acceptance.md).
