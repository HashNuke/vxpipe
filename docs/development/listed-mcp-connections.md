# Listed MCP discovery and accepted configuration

Status: directory reference resolution, credentialless discovery, accepted
snapshot storage, static and browser OAuth connection management, locked listed
forms and saved-registration discovery advice implemented; authenticated browser
and retained-ID recovery acceptance remain open in
[T6a](../../labnotes/milestones/integrations-directory-and-tenant-mcps.md#t6a--listed-template-connection-identity-and-forms).

## Reuse the directory and management boundaries

The hosted directory currently exposes paginated `/v1/integrations` and
`/v1/categories` reads, without an entry-detail route. Console reuses its existing
validated page cache for listing lookup. It does not add another catalog, scan
every directory page, or accept a browser-supplied endpoint as a listed entry.
Native providers continue using the existing Services credential operations.

Each remote MCP inventory row includes a `listing` reference:

```json
{
  "directory_id": "example-directory",
  "integration_id": "example-calendar",
  "entry_revision": 1,
  "page": {"category": "calendar", "scope": "tenant", "limit": 20}
}
```

`page` is the normalized public request that produced the row. Search references
retain `q` without a category. Continuation references retain their opaque cursor
and any explicitly requested catalog revision. The reference never contains the
directory origin, installation version, credentials or tenant identity. Reject
unknown fields and platform scope before fetching; the installation owns the
origin and compiled version. References are bounded to 8 KiB of encoded JSON.

`IntegrationsDirectory.Listing.resolve/2` fetches exactly that page through the
existing cache, revalidates the page/request/version contract, and requires an MCP
entry with matching directory ID, entry ID and entry revision. Missing, retired,
incompatible or malformed entries fail closed. The accepted projection contains
only the directory and entry identities, revision, name, canonical endpoint,
supported authentication recipe, and independently optional setup notes/links.
Unknown extension fields are excluded; API-key transport headers and malformed
OAuth scope tokens are rejected. Setup links must be HTTPS with a host, a valid
port and no userinfo. Notes remain plain text for the eventual form.

The normal cache freshness contract still applies: a fresh cached page may be
used until expiry. This does not guarantee immediate awareness of retirement in
the upstream directory. A failed refresh never falls back to an expired template.
An expired cursor, missing entry or changed revision requires a fresh browse
selection; there is no silent substitution of another recipe or endpoint.

## Discovery on the existing tenant route

`POST /api/tenants/:tenant/mcp-discovery` accepts either the existing custom input
or `{listing, revision, issuer?}`. The listed form rejects endpoint/authentication
overrides and credentials. Calls checks current tenant write authority before the
adapter runs and refreshes authority before returning its result. The adapter
resolves the listing inside the existing bounded preflight runner, then performs
ordinary credentialless discovery against the resolved endpoint. It never starts
registration, consent, token exchange or connection persistence.

The response adds `discovery.listing` containing the accepted public projection.
Calls verifies its directory/entry/revision identity, endpoint and draft revision
against the proposal before returning it. The listing recipe and live discovery
result remain distinct: an unknown/failed probe cannot turn an OAuth or static
recipe into anonymous access. Unsupported live capabilities must block the
eventual listed connection form; directory hints do not grant protocol support.

Invalid outer proposals (including non-map or oversized references) return
`422 invalid_mcp_preflight`. Structurally invalid references reaching the resolver
return `422 invalid_mcp_listing`; unavailable or changed listings return
`503 mcp_listing_unavailable`. Errors contain no upstream bodies.
The complete `listing` input is filtered from Phoenix request logs, including
malformed references that contain unexpected private fields.

Saved listed OAuth discovery uses the same route with
`{connection_id, generation, revision, issuer?}`. It rejects endpoint, listing,
snapshot and credential overrides. Calls checks current tenant write authority,
loads the accepted saved snapshot and reads only the current connected record's
registration identity. Revoked records never decrypt their old credentials;
unreadable registration keys fall back to fresh supported methods.

The bounded credentialless probe shares Connect-time selection: a compatible
stored DCR client can remain reusable when the server stops offering new
registrations. Advice checks issuer, resource, scope subset, exact installation
callback, live authentication capability and secret expiry. The response binds
`connection_id`, `generation` and draft `revision`, and adds only
`oauth_registration: {method, reusable}` alongside public metadata. Callback/client
metadata comes from the same checked installation. Calls rechecks authority,
generation, lifecycle and installation before returning. No directory read,
registration, token exchange, connection write or attempt creation occurs.
Connect repeats the checks; this advice is never authority to reuse credentials.

Listed forms keep URL and authentication fixed. Managed registration exposes only
the optional DCR initial token when a new registration is needed; reusable DCR
shows no credential fields. Preregistered clients require an explicit registered
authentication method, client ID and applicable secret/key, plus the exact callback.
Partial and multi-issuer discovery retain recovery controls without anonymous
fallback. Failed consent restores a validated public listing reference in the
existing actor/tenant/attempt-scoped session draft (bounded to 24,576 characters);
retry resolves the listing again and requires reentry of secrets.

## Static connections on the existing tenant routes

The discovery response is display data when sent through a browser. A new static
`POST /api/tenants/:tenant/mcp-connections` accepts `{listing, credentials}` and
resolves the reference again before using credentials. It rejects a browser
snapshot and extra credential fields. Optional browser `endpoint` and
`auth_method` fields are ignored: the resolved recipe owns both. Lookup and
connection checking share the bounded preflight lifetime. Calls verifies the
returned directory/entry/revision and endpoint before persistence.

Supported recipes are explicit anonymous access, bearer token, HTTP Basic and one
API-key header. Anonymous access accepts empty credentials; bearer accepts only
`token`; Basic accepts only `username` and `password`. API-key input uses
`headers: [{value, name?}]`, but the accepted recipe supplies the header name.
Only the user-provided value is used. Stored credentials keep the existing static
runtime format; this adds no credential store or transport implementation.

The backend binds the accepted name, endpoint, recipe and compound
`directory_id/integration_id` identity into saved configuration. The repository
supports a closed, immutable public snapshot alongside encrypted credentials;
see the
[storage contract](tenant-mcp-storage.md#accepted-directory-configuration).
GET/list responses expose that public snapshot, never saved credentials.

Replacement and retained-ID reconnect use a separate `check_saved` port supplied
with the authorized tenant record's snapshot. They never fetch the directory.
Calls checks the record's generation and lifecycle state before credential use,
and verifies the probe preserves its endpoint, method and directory identity.
Replacement may retain existing credentials when omitted; reconnect requires fresh
credentials after revocation erased the old ones. Catalog refresh, disconnect and
reconnect preserve the accepted name, snapshot, ID and namespace even during an
upstream outage or after retirement. Inventory matches compound directory identity
as well as canonical endpoint, so a later directory revision does not hide the
saved connection or confuse identically named entries from different directories.

## Listed static forms

The production Integrations directory enables static MCP Connect only when local
status is known, no connection matches, the entry is available/preview and the
current tenant user can write MCP settings. Platform scope never enables MCPs.
Listed OAuth uses the same eligibility checks and its registration-specific form.

The existing MCP dialog shows the directory name and fixed endpoint/authentication
recipe. API-key setup has one masked value field labelled with the recipe's header;
bearer and Basic show only their required credentials; anonymous access has none.
The new request sends the listing reference and active credentials, without a
browser snapshot, endpoint or authentication override. A changed/missing listing
asks the user to close and browse again. Saved forms instead use the accepted
snapshot and existing connection route, with explicit credential replacement.

Notes remain plain text. Setup and Documentation links are independently optional,
validated HTTPS URLs, and open without an opener or referrer. Client parsing checks
reference/revision consistency and saved endpoint/name/method/compound identity;
these checks support presentation and do not replace backend validation.

The shared dialog supplies its own existing MCP style scope, so its controls and
viewport bounds work in production as well as Storybook. Desktop/mobile fixture
inspection covers creation, saved replacement, tools during directory outage and
read-only access; it does not establish authenticated backend browser acceptance.

## OAuth on the existing tenant routes

`POST /api/tenants/:tenant/mcp-oauth` accepts a listing reference, draft `revision`,
optional selected `issuer`, and only the credentials needed by the selected live
registration mechanism. Optional browser endpoint/method overrides are ignored.
Arbitrary snapshots, OAuth endpoint/scope overrides, request parameters and MCP
headers are rejected. The accepted directory scopes are display hints; the existing
resource/challenge scope rules determine the requested grant.

Preparation resolves the new reference inside the existing bounded preflight
runner. It performs credentialless capability selection, then uses the existing
OAuth protocol preparation to revalidate metadata before registration and consent.
Both reads share one bounded operation. If required capabilities disappear between
passes, preparation fails before registration/handoff rather than changing modes.

Preregistered recipes use Own client: client ID and the actual registered client
authentication method, with its required secret or private key/algorithm/key ID.
The backend checks that method against live supported capabilities; it cannot
infer a client's registration from the authorization server's list of methods.
Listed V1 recipes use the authorization-code grant. Managed recipes first reuse a
compatible saved DCR registration, then honor a supported DCR preference or select
supported CIMD, DCR and finally Own client. CIMD has no user credentials; DCR only
accepts its optional initial access token. Missing resource metadata with an
explicit issuer retains the existing Own-client fallback. Invalid metadata does
not create an anonymous or managed fallback.

Calls verifies the prepared snapshot against the proposed directory/entry/revision,
resource and draft. The existing encrypted, authenticated OAuth attempt payload
carries the accepted snapshot through consent. Completion validates its resource
and OAuth recipe before redemption, then projects its directory identity, name and
configuration into the connection record. The public snapshot is removed from the
saved credential payload. Calls rejects a completion result that changes the
accepted snapshot, directory identity, name or resource.

Saved `POST /api/tenants/:tenant/mcp-connections/:id/oauth` uses generation-bound
accepted configuration, never a browser listing or a fresh directory lookup.
Connected replacements can reuse compatible DCR registration; revocation erased
those credentials, so retained-ID reconnection prepares fresh registration. Current
tenant/session authority, installation identity, single-use state and generation
checks remain in their existing owners. Callback, replacement, tool refresh and
reconnect work during a public directory outage. Invalid references return 422;
changed/unavailable listings return `503 mcp_listing_unavailable`; invalid issuer
input returns `422 invalid_oauth_issuer` before directory or protocol reads.

## Retained connection recovery

An existing static create conflict supplies only a bounded connected ID or revoked
ID/generation. The modal offers Manage existing connection or Review reconnect;
it performs no automatic reconnect. Review reads the existing tenant detail route
with `?retained_generation=N`. This branch requires current write permission,
strict positive generation syntax and the exact tenant/ID/generation/revoked state.
It returns public accepted configuration without decrypting credentials. Ordinary
GET continues to hide revoked records and now includes `can_edit` for management.

The parent remounts the form with fresh credentials, fixed endpoint and saved
listed recipe. An explicit Reconnect uses the existing static/machine reconnect
or browser OAuth route and preserves the original identity and namespace. Connected
duplicates can open authorized read-only management; revoked setup requires write
permission. Cancelled/failed consent restores a retained form only from a matching
actor/tenant/attempt public draft and a fresh metadata read. Temporary lookup
failure offers retry with a five-minute in-memory draft; scope/navigation changes
abort stale responses and discard unfinished recovery. No callback query grants
connection authority.

## Remaining connection work

Early duplicate detection before static authentication/OAuth preparation remains
open, including changed listed recipes whose new preparation cannot succeed. The
required internal target-resolution contract must precede authentication side
effects, reuse the deterministic tenant endpoint-or-directory lookup and keep
atomic create authoritative against races. Authenticated rendered-browser and
full workflow acceptance also remain open.

Rejected alternatives: adding a parallel directory API, accepting the entire
browser listing as authority, unbounded catalog scans, and re-reading the public
directory during management of an existing connection. The existing lookup and
cache contract supplies the required public data while keeping tenant state local.

## Verification

Focused red/green coverage exercises exact reference lookup, request identity,
revision/version changes, retired entries, optional setup fields, recipe
validation, unsafe links, bounded input, sanitized failures and request logging.
Calls tests verify tenant authority, authority refresh and mismatched draft/entry
responses. Endpoint tests exercise the existing authenticated route with the real
Console adapters and in-memory network fixtures. Static lifecycle coverage uses
real encrypted persistence and session/CSRF routes for creation, replacement,
refresh, disconnect and retained-ID reconnect while the directory is offline;
it verifies header-name ownership, stale generations and cross-tenant isolation.
The static-form checkpoint adds red/green parser, payload, permission and inventory
eligibility coverage. Real provider interoperability and authenticated production
browser acceptance remain separate gates.
Listed OAuth coverage adds all registration recipes, private-override rejection,
missing-metadata fallback, capability loss between discovery passes, accepted
snapshot binding and callback preservation. Session/CSRF endpoint tests use real
encrypted repositories and synthetic network responses to exercise create,
single-use callback, DCR reuse, refresh, disconnect and retained-ID reconnect
during directory outage, including stale-generation and cross-tenant rejection.
