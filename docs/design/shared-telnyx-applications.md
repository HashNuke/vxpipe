# Shared Telnyx applications and tenant overrides

Status: implemented and verified on 2026-11-13. The
[milestone](../../labnotes/milestones/shared-telnyx-applications.md) owns requirements
and progress. This note records the minimal design and approved URL behavior.

## Configuration

Reuse encrypted credentials and tenant telephony bindings. Add one platform
application ID. A tenant binding with no application ID inherits that value;
an explicit ID is a dedicated override. Credentials resolve independently using
the existing tenant-first lookup. Tenant credentials require an explicit tenant
application. An invalid override does not fall back.

The modal saves changed sections in one transaction using existing permissions.
Resetting credentials retains the application override. Resetting the application
requires platform credentials. Reads return effective values and their source
with secrets masked. Existing service names and call-spec references remain.
Migrate data where needed and use one current runtime contract, without legacy
fallbacks or an operator adoption workflow.

## Routing

After verifying the signature, resolve a new incoming call using the effective
application ID and called number to exactly one published tenant route. Tenant
webhooks additionally restrict the search to their tenant. Extend existing number
conflict checks to shared applications, including when configuration changes.
Reuse stored event/leg identity to prevent duplicate admission after number moves;
later events continue to the original call. No separate routing or deduplication
subsystem is needed.

Keep the unique index on explicit application IDs. Inheriting bindings store null,
so they can already share a platform default without removing this constraint.
A dedicated override must not also serve as the shared platform default; handle
that in ordinary configuration validation. Both the modal and outgoing callbacks
use the existing public-origin helper and the same application-scope decision.

The existing configuration/admission transactions lock the singleton setting before
service and credential rows. Publication serializes shared-number checks, then
reads the selected revision after taking the tenant publication lock. New partial
Telnyx indexes make event/leg identity unique within an application across tenants.
A one-off migration adds application ownership to stored plans and updates their
digests; normal decoding uses the current contract.

## Approved webhook behavior

The user selected this rule on 2026-11-13:

- Inherit both credentials and application: display the platform URL.
- Override only the application: retain platform credentials and display the tenant URL.
- Configure or edit tenant credentials: clear the application input and require a
  tenant application alongside the credentials, then display the tenant URL.
- Accept tenant applications at the platform endpoint too, to tolerate a user
  leaving the old webhook configured in Telnyx. This is ordinary verified routing,
  not a persisted compatibility mode or a second fallback implementation.

Telnyx sends the application as `connection_id` and the called number as `to`.
These unverified fields may locate a candidate; they do not authorize it. A
candidate's effective public key must verify the event before any call starts.
The platform URL can locate a dedicated tenant binding by application ID; shared
applications also require the number. A tenant URL never searches another tenant.
Later events still use the original call identity.

For example, Acme moves from shared application A to its own B and credentials.
Vxpipe displays Acme's tenant URL. If B still sends events to the platform URL,
Vxpipe locates Acme from B and verifies with Acme's public key. Bravo remains on A,
where the called number selects its call spec. Pointing shared A at Acme's tenant
URL would still be incorrect because that endpoint is restricted to Acme.

See Telnyx's [webhook payload and configuration](https://developers.telnyx.com/docs/voice/programmable-voice/voice-api-webhooks)
and [application settings](https://developers.telnyx.com/api-reference/call-control-applications/update-a-call-control-application).
Saving Vxpipe configuration does not change Telnyx's remote settings.

## Review evidence

Source review confirmed the existing application-ID-only lookup must become a
number-aware route lookup. The earlier recommendation to remove the explicit-ID
unique index was unnecessary once inheritance uses null. Configuration versioning,
extra binding modes, automatic account discovery and endpoint-wide redesign are
not required. See the
[review labnote](../../labnotes/20261113-1123-simplify-telnyx-milestone.md) for evidence
and implementation status; this document review does not establish runtime acceptance.
