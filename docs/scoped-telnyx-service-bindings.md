# Scoped Telnyx service bindings

Decision: 2026-09-19. Design and C1 implementation reviewed. C2/C3 remain open under checkpoint C of the
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

## Compatibility and migration

Existing bindings without `credential_name` retain their exact tenant credential ID,
public key, ingress key and foreign-key checks. Do not guess a scoped primary account
from existing rows: multiple legacy keys or application aliases may be ambiguous.
Existing exact bindings are not automatically enrolled in scoped webhook routes.
A new scoped binding remains usable through its explicit ingress during C1; C2/C3
add scoped ingress and its configuration. New nullable columns and conditional constraints preserve
legacy rows and ciphertext without rewriting them. Rolling the schema back while
scoped bindings exist must fail clearly and preserve those rows, rather than discard
configuration or manufacture tenant credentials from a platform account.

Persisted prepared plans predating the new reference fields decode with explicit
legacy defaults. New scoped references pin credential owner, ID and name; replacing
credentials within that ID may refresh a client, but deletion/recreation or scope change
requires fresh preparation. Legacy references preserve their exact tenant credential
semantics. Raw application metadata and a resolved credential snapshot are different
states: never compare an unresolved scoped record's missing credential ID as if it
were a previously authorized selection.

## Delivery order and verification

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
not publish a phone-number route or configure the remote Telnyx application. During C1,
use the existing explicit `/api/telephony/telnyx/:ingress_key/events` ingress. The new
scoped URL and Console configuration arrive in C2/C3.

- [x] C1: store the optional scoped verification key, register a tenant application
  against the effective credential name, authorize call-spec writes, and resolve new
  Gateway clients. Preserve legacy ingress so the intermediate checkpoint is runnable.
  Test two inheriting tenants, tenant override/removal/restore, cross-tenant rejection,
  exact prepared identity and no secret exposure.
- [ ] C2: add route-selected platform/tenant signature verification and explicit
  application routing. A body identifier may locate an initialized owner only within
  the route-selected credential scope; it cannot choose another scope's verifier.
  Authenticate the exact raw bytes before trusting new application routing. Preserve
  initialized owner credentials and duplicate/outage behavior.
- [ ] C3: expose public-key configuration, application bindings and matching webhook
  URLs in the operator Console, with durable metadata and browser verification.
- [ ] D retains public-origin/callback cutover, deliberate legacy migration and final
  restart/rollback/umbrella acceptance from the parent plan.

Design review: keep credentials separate from tenant application identity; reuse the
existing owner/presence resolver rather than introduce another fallback mechanism.
Reject relaxing every legacy ownership constraint, silently copying platform secrets
into tenant rows, and selecting a verification scope from unsigned event fields.
C1 evidence: 24 focused persistence and six Gateway reader tests pass, with disposable
database upgrade/rollback/restart acceptance. The umbrella run covers 1,770 tests;
one obsolete reference-field assertion was corrected and the full 116-test Calls suite
rerun. All other umbrella suites and static gates pass. C2/C3 and live-provider
verification are not claimed complete.

Telnyx documents account-level Ed25519 verification over the original request body
and application-owned webhook configuration. These support the separation above;
the Vxpipe owner/presence and migration decisions are local design choices.
See [webhook verification](https://developers.telnyx.com/docs/development/api-fundamentals/webhooks/receiving-webhooks)
and [Voice API applications](https://developers.telnyx.com/api-reference/call-control-applications/create-a-call-control-application).
