# Tenant telephony service storage

Status: trusted Telnyx/Twilio registration, the operator CLI, private credential resolution,
canonical prepared-plan bindings, tenant-scoped incoming claims and call spec
save/publish/web/incoming write guards are implemented. Twilio media authentication retains
the initialized leg configuration. Telnyx now requires a scoped primary credential binding
through the [platform/tenant service contract](scoped-telnyx-service-bindings.md);
Twilio retains exact tenant credentials. The original tenant-reader work is recorded in
[checkpoint 3](milestones/tenant-provider-credentials-and-platform-configuration.md#checkpoint-3--move-telnyx-credential-readers-to-tenant-storage)
and [checkpoint 4](milestones/tenant-provider-credentials-and-platform-configuration.md#checkpoint-4--move-twilio-credential-readers-to-tenant-storage).

## Ownership and identity

Calls owns the data-only `TelephonyService` record, trusted `TelephonyServices` workflow and
repository port. Persistence owns its PostgreSQL schema, constraints and transactions. Gateway
continues to own carrier command/signature protocols. No new dependency crosses these boundaries.

A service stores a canonical public UUID, tenant-local name, globally unique media
ingress key, provider connection ID, optional originating number and carrier options.
The alias is what a call spec names; prepared plans pin the canonical service identity.

Telnyx binds `credential_name: "telnyx"` and resolves that tenant's effective primary
credential. Its API key and optional Ed25519 verification public key are stored together
in the encrypted credential payload. Phone operation requires the public key. A tenant
credential takes precedence by presence; an unusable tenant key never falls back to the
platform. Each scoped Voice API application maps to exactly one consuming tenant.
The old ingress-key webhook is removed. Gateway rejects unscoped Telnyx bindings before
constructing a new live client; stored credentials and historical records are retained.

Twilio references an exact tenant credential UUID. Its foreign key includes credential
ID, tenant and provider. The Account SID is `provider_connection_id`; its encrypted
SID/Auth Token payload must belong to that account. Registration and private resolution
enforce the match. Twilio has no public-key field.

Credentials are provisioned separately through [encrypted provider storage](provider-credential-storage.md).
Service input rejects secrets, adapter modules and public callback/media origins.
Origins remain platform configuration. Machine detection defaults to disabled,
media tokens to 60,000 milliseconds and webhook tolerance to 300 seconds. Timers fit
PostgreSQL integers; webhook tolerance also permits zero.

## Trusted registration and lookup

Run migrations and configure the primary Telnyx API/public-key pair at platform or
tenant scope. Put the application metadata in a JSON object such as `service.json`:

```json
{
  "name": "support-phone",
  "ingress_key": "tenant-support-ingress",
  "provider": "telnyx",
  "provider_connection_id": "TELNYX_CONNECTION_ID",
  "credential_name": "telnyx"
}
```

Replace the connection placeholder with the tenant's dedicated Telnyx Voice API application ID.
The registration command reads this metadata once, validates it and writes the binding to PostgreSQL:

```shell
mix vxpipe.telephony_service.register --tenant TENANT_KEY --file service.json
```

The command limits input to 16 KiB and returns the public service/credential IDs, tenant, provider,
name and ingress key. It accepts no secret flags or secret fields. This file is registration
input; it is not a live runtime configuration source. To inspect the stored metadata or register
from a trusted host session, use the same configured Calls port:

```elixir
Vxpipe.Calls.TelephonyServices.register(tenant_key, %{
  "name" => "support-phone",
  "ingress_key" => "tenant-support-ingress",
  "provider" => "telnyx",
  "provider_connection_id" => telnyx_connection_id,
  "credential_name" => "telnyx"
})

Vxpipe.Calls.TelephonyServices.fetch(tenant_key, "support-phone")
Vxpipe.Calls.TelephonyServices.fetch_by_ingress("tenant-support-ingress")
```

For Twilio, provision `account_sid_auth_token` credentials through the existing protected-input
command, then use the same service registration command with this metadata:

```json
{
  "name": "support-phone",
  "ingress_key": "tenant-twilio-ingress",
  "provider": "twilio",
  "provider_connection_id": "AC_REPLACE_WITH_32_HEX_DIGITS",
  "credential_id": "PROVISIONED_CREDENTIAL_UUID"
}
```

The scoped-service schema leaves existing rows unchanged. It refuses rollback while
scoped bindings exist instead of discarding them or copying platform credentials into tenants.

These are trusted host operations, not tenant-facing management APIs. Registration locks the
matching credential row, verifies active status and decryption using the existing credential
adapter, and inserts the service in that same transaction. A conflicting alias or ingress key
returns an error without replacing a binding. Operator application edits use the separate
installation-authorized boundary below.

`fetch` and `fetch_by_ingress` return metadata without reading or decrypting credential payloads. They can therefore
inspect a registered binding when an encryption key is unavailable. Lookup success does not
authorize a provider request or authenticate a webhook. The live reader resolves current private
authentication and checks the exact pinned service/account at those boundaries. The ingress key
is a locator, not authentication.

## Operator application API

An authenticated installation-operator browser session can manage a tenant's scoped Telnyx
applications at `/admin/api/tenants/:tenant_key/telephony-applications`. Tenant API keys do
not authorize these endpoints. Writes require the session's CSRF token.

- `POST` accepts `name`, `provider_connection_id` (the Telnyx Voice API application ID),
  and optional `outbound_number` (an E.164 number or null). The server supplies the primary
  Telnyx credential binding and a stable generated media ingress key.
- `PATCH /:service_id` accepts only `provider_connection_id` and `outbound_number`.
  It preserves the service UUID, tenant, name, ingress and credential binding. Editing an
  application ID invalidates prepared references to the old ID; initialized legs retain
  their snapshots. Edits use the existing service and effective-credential locks.
- `GET` returns tenant metadata, at most 100 applications and 500 current published number
  routes, and a `truncated` flag. Each application exposes `id`, `name`,
  `provider_connection_id`, `outbound_number` and `published_routes`. Route metadata includes
  number, call-spec ID/name/revision, participant reference and `ambiguous`; ambiguity counts
  include conflicts beyond the display limit. Drafts, superseded publications and foreign
  tenants are excluded. Credentials and verification keys are never returned.

Create returns 201, edit/read return 200. Reading or editing an unknown tenant/service
returns 404, application
conflicts return 409, and invalid input or an unavailable effective credential returns 422.
Repository failures return a bounded 503 error. An unusable tenant credential prevents writes
even when a usable platform credential exists. Metadata remains readable without decryption.

Number authoring stays in the existing authorized call-spec save/publish APIs. These endpoints
configure local bindings only; they neither provision Telnyx resources nor prove live calling.

The tenant's Console service-setup page exposes these operations under **Phone routing**.
Add an existing Voice API application, then edit its application ID or outbound caller number
as needed. The service name remains fixed because call specs reference it. **Connection
details** opens the effective Telnyx credential configuration and its scoped webhook URL.
An API-only tenant override needs its own public key before application writes are available.

After publishing a receiving call spec, reload phone routing to see its current number,
revision and participant. Conflicting published routes are called out even when the directory
is truncated. Saved keys and application metadata are local configuration: assign the number
and matching webhook URL in Telnyx, then verify a live call separately.

## Private resolution and call spec checks

`TelephonyServices.resolve(tenant_key, name)` returns a private snapshot of the service and its
selected credential (effective primary for Telnyx, exact tenant UUID for Twilio).
It locks the relevant rows, checks scope/provider/active status and decrypts
the credential using the existing authenticated store. A same-name credential with a different
public ID is not an equivalent binding. The snapshot's inspection hides private authentication;
call specs and prepared plans never retain its payload.

call spec save, publish and web preparation check every phone service, including later transfer
destinations. Missing, other-tenant, inactive or undecryptable credentials return a safe error at
the participant's service path. The final database write runs under the active service/credential
locks; revocation between preflight and that write prevents persistence. Repositories called by
the guarded operation must share its transaction context. Existing write errors, including
duplicate call IDs, retain their original meaning. credential-free web call specs need no service
repository.

Incoming preparation shares the preflight check and canonical plan binding. Calls supplies its
existing active-credential/reference guard as a mandatory repository callback. Persistence runs
it inside the call/leg insertion transaction, before either write, and retains the service and
credential locks until commit. Only an authorization marker enters the transaction's results.
Revocation, unreadable credentials or a service/account/credential rebind after compilation
prevent both rows. The same final check covers model/speech credentials required by the call spec.

Already stored duplicates skip this new-write callback. If two events race past duplicate lookup,
the losing insert rolls back before the existing duplicate-recovery query runs. Wrapping the whole
claim in a credential transaction would leave that query inside an aborted transaction; placing
the guard in the existing insertion transaction preserves recovery. All participating credential
repositories must use the same Repo/dynamic transaction context as the call store.

This check authorizes the database write. Fresh live-leg construction and hosted startup also
check the pinned references, as described below.

## Incoming identity and duplicate lookup

An incoming claim carries the canonical service UUID alongside its alias. Before lookup or
insertion, its tenant, service, provider and account must match the prepared entry participant's
reference. Lifecycle writes also validate that reference and target the same tenant/service leg.
The database's event and leg uniqueness keys include tenant, service UUID and provider, so two
tenants with matching aliases and carrier IDs cannot return or update each other's calls.

Retries compare account, call-control, leg and session identity. A new event ID for the same leg
returns the original claim; a changed control/session identity returns `:telephony_leg_conflict`.
Freshly generated call and participant IDs do not participate in duplicate identity.

The identity migration adds nullable `telephony_legs.service_id` and replaces the old global
alias indexes. Historical rows retain `NULL`: current aliases cannot establish which service
originally admitted them. A collision with an unbound historical event or leg in the same
tenant/provider/account returns `:legacy_telephony_claim` without admitting another call or
adopting the old row. Stored calls remain inspectable. There is no foreign key to the current
service row, so historical identity does not depend on service retention.

Stop the old application writers before applying this migration, then start the new version.
Mixed-version writes are unsupported: an old writer can insert a nullable identity outside the
new uniqueness rules. New admission changesets require the UUID. Rolling back the migration
requires resolving any cross-tenant or cross-service IDs that conflict with the old global
indexes first; the migration never deletes calls to make rollback succeed.

Gateway's live registry also includes tenant and canonical service identity. This boundary adds
no new carrier workflows or authentication modes.

## Prepared service references

The Calls compiler resolves each distinct tenant-local service alias once and projects its
tenant, canonical service UUID, alias, provider, account/connection identity and credential UUID
into an Engine-owned `Telephony.ServiceReference`. Participants sharing an alias use the same
reference. The existing prepared-plan digest includes this metadata; neither a credential value,
credential version nor encryption-key ID is pinned.

The final web-preparation and incoming-admission writes compare every participant's reference
with the currently locked service. A service/account/credential rebind between compile and insertion rejects the write.
Repeated aliases reuse one locked snapshot, but every reference is compared before the callback;
a differing second reference cannot disappear through deduplication. Missing or wrong-tenant
references also reject before a write.

Public connection JSON still accepts only the existing intent fields; callers cannot supply
canonical pins. Raw embedded Engine compilation remains independent of the host's database and
leaves the optional reference empty. Historical serialized plans lacking the field remain
decodable for inspection without silently inserting a new binding. The new write guard rejects
such unbound phone plans. Hosted startup rejects unbound or stale phone references, including
later destinations in a web-entry plan. Outbound requests carry the complete reference and
resolve it freshly before a leg or provider request is created.

Cold-process verification exposed an existing safe-decoding dependency on previously loaded plan
atoms. The codec now asks the Engine plan type to load its fixed data and enum owners before
using the unchanged safe decoder. The list includes existing prepared-audio, transfer and
call-variable validator data. Stored bytes never select a module to load. A fresh subprocess
test covers a pinned plan with bounded call variables and rejects unknown external atoms without
interning them. A disposable DB fetch also passes before any call spec compilation or service
lookup in the reader process; both current and legacy plan representations remain readable.

Keeping only an alias would permit account changes after preparation. Storing private snapshots
would leak credentials into immutable history, and pinning encryption-key IDs would couple calls
to platform re-encryption. Stable non-secret identity avoids those problems while leaving fresh
credential resolution at the owning live-reader boundary.

## Live readers and platform callback origin

Public `APP_HOST` defaults the callback origin to HTTPS. Optional
`VXPIPE_TELEPHONY_PUBLIC_BASE_URL` overrides that origin and its mounted path,
for example `https://voice.example.test/voice`. A resolved HTTPS origin enables telephony routes;
local HTTP URLs are previews. The existing Console/Gateway listener still serves the routes.
Use the externally visible URL because
Twilio signatures include the exact URL. The setting rejects userinfo, query strings, fragments
and non-HTTPS URLs. It contains no provider credentials. `env.sample` documents it.

New incoming legs resolve the stored ingress binding, then its exact tenant service and encrypted
credential. The reader compares the canonical reference and ingress across both reads. Outbound
legs resolve the prepared participant's reference before starting. Lookup time consumes the
existing connection deadline. Missing, inactive, unreadable or changed bindings fail before dial.

The incoming HTTP boundary passes the verified private configuration to the same leg and its
activation. It does not reread credentials between verification and answer. Existing incoming and
outgoing owners retain this configuration in private, owner-bound registry entries, available even
while admission or dial is busy. Registry ownership retires those entries with the leg.

A webhook's untrusted account/leg identifiers may only locate an existing owner. The normal
raw-body/signature/timestamp/account checks still authenticate the request. Dispatch uses that
same PID; retirement cannot redirect an authenticated event to a replacement. Existing-owner
signature failure never retries with DB credentials. Callbacks, media authentication and cleanup
continue with initialized credentials during storage loss. New legs require fresh resolution.

Embedding uses the Calls repository port plus `public_base_url`; the removed `services:` option
is rejected with a sanitized configuration error. Gateway owns carrier protocols, while Persistence
owns database and encryption access. No Repo dependency is added to Gateway.

## Initialized Twilio media authentication

Incoming activation and outbound reservation retain the private initialized Twilio configuration
in the existing media admission entry. WSS authentication reads that exact configuration without
consuming the token, installing a waiting consumer or extending expiry. It verifies the existing
signature against the retained public WSS URL before consuming with the same configuration.
Missing or conflicting registry configuration cannot supply or replace authentication at this
boundary. The WebSocket receives the binding and clock, not the private configuration.

Protected Twilio admissions require an explicit tenant scope. Application-scoped configuration
cannot establish tenant ownership and is rejected by construction, activation, dial and media
admission. Calls also rejects application-wide carrier route lookup. Binding compares
tenant, provider, service alias, ingress and account; the token remains owned by its exact leg.
Repeated issue/reserve inputs reuse a token only when the retained configuration is identical.

The unsigned Telnyx media route cannot consume a protected Twilio token. A generic pending
reservation also cannot later deliver a Twilio binding to an unsigned waiting consumer. Expired,
revoked and replaced tokens cannot select a later leg. Loss of the admission process during lookup
or consumption returns a sanitized 503 response.

Initial leg construction supplies this configuration from the tenant DB reader. This adds no
credential refresh protocol, provider or authentication mode.
The existing admission entry owns this state; a separate authentication lease would duplicate
its token, expiry and leg lifecycle.

The [media-auth evidence](../labnotes/20260916-0401-retain-leg-media-auth.md) records 39 passing
focused admission, HTTP, activation and outgoing-leg checks, including two-tenant isolation,
pending authorization, conflicting registry settings and admission-process loss.

## Alternatives and verification

- Referencing only a credential name could silently select a replacement binding. Store the
  stable ID and enforce ownership in PostgreSQL.
- Storing secrets in services would duplicate encrypted credential ownership and expose them to
  metadata readers. Services contain no private payload.
- Reusing global carrier configuration would retain the source this milestone must remove.
  The live registry no longer accepts static credential lists or application-scope fallback.
- A new carrier policy or authentication-lease subsystem is unnecessary. Retain existing options
  and leg/reservation ownership when migrating the readers.

The [checkpoint labnotes](../labnotes/20260916-0000-tenant-telephony-services.md) record focused
red/green tests, direct database ownership checks, runtime composition and independent review.
The 11 focused checks and 98-test Persistence suite pass. Full umbrella acceptance remains open:
one existing native WebRTC Morse-decoding case failed in the 1,543-test run and reproduced in isolation.
The existing Telnyx call-flow milestone remains the owner of full carrier/audio acceptance.

The [call-spec guard evidence](../labnotes/20260916-0057-telephony-credential-gates.md) records
13 passing focused database tests, 81 Calls tests and 106 Persistence tests (6 excluded), plus
independent implementation review. Format, warnings-as-errors compilation and strict Credo pass.

The [incoming-guard evidence](../labnotes/20260916-0249-guard-incoming-credentials.md) records
four focused database tests and two tagged real-connection checks. They cover post-compile service
rebinding, revoked/unreadable carrier credentials, revoked model credentials, lock lifetime through
commit, and concurrent duplicate recovery after a losing insertion rolls back.

The [carrier-reader evidence](../labnotes/20260916-0424-migrate-carrier-readers.md) records
the final live cutover, two-tenant encoded REST requests, real encrypted DB-to-HTTP signature
checks, retained callbacks during storage outage, owner retirement and hosted startup guards.
