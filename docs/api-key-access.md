# API-key access and Settings management

## Approved contract

API Keys belongs in Settings, without selected-tenant context. The list has Name,
API key (masked suffix), Type, Tenant and Created columns. Tenant-scoped creation
requires a remotely searchable tenant picker. Platform keys show All tenants.

Key types: Create & Join Calls (one tenant, existing calls scope), Full Tenant
Access (one tenant, existing admin + calls scopes), Full Platform Access
(installation authority). Full platform key issuance is Superadmin-only.

Management permissions are distinct from provider credentials:
- access_keys.read/write: all_tenants or assigned_tenants, capped by membership.
- platform_api_keys.read/write: installation; write is reserved to Superadmins.
- Existing tenant_api_keys.write continues to govern provider credentials; its
  UI label becomes Provider credentials to remove the naming ambiguity.

A writer may issue only access they possess: calls keys also require calls.write;
full tenant keys require every operational tenant read/write permission. Read
permissions never reveal secrets. Creation returns the secret once. Revocation
is immediate on subsequent authentication. Listing/search use authorized DB
queries and bounded pagination, never browser-only filtering.

## Persistence and compatibility

Extend existing API-key storage with an optional tenant for platform keys and a
masked suffix. Enforce the tenant/scope relationship in PostgreSQL. Keep existing
keys usable; old suffixes cannot be recovered from their hashes and display a dash.
Do not repurpose or rotate trusted bootstrap/operator keys. New platform keys use
a distinct prefix and existing installation-operator authority on machine APIs.
The browser session remains independent of machine API credentials.

## MCP direction

Use one /mcp endpoint with credential-derived authorization and tenant parameters
for cross-tenant operations by platform credentials. MCP server implementation is
separate from this API-key management slice; existing vxpipe_mcp is outbound.
No claim of a working inbound MCP endpoint is made by this change.

## Rejected alternatives

Separate tenant MCP URLs duplicate tenant selection without replacing permission
checks. Reusing provider-credential grants for Vxpipe access-key management would
conflate two responsibilities. Creating keys solely from key-write permission
would allow a restricted user to delegate permissions they do not possess.

## Verification

Tracked in the Settings API-key checklist and implementation labnotes: scoped
listing/search, creation ceilings, cross-tenant denial, platform-only restrictions,
one-time secret handling, revocation and rendered desktop/mobile states.
