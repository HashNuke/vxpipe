# Listed MCP discovery and accepted configuration

Status: directory reference resolution and credentialless discovery implemented;
connection/attempt persistence and locked listed forms remain open in
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

## Remaining connection work

The discovery response is display data when sent through a browser. A future
Connect request must resolve its reference again on the backend before side
effects; it must not trust a returned snapshot submitted by the client. The
backend will bind the accepted name/endpoint/recipe and directory/entry identity
into saved configuration and OAuth attempts. In-flight attempts and subsequent
management must use that saved configuration, including after retirement,
directory outage, disappearance or disconnect. This checkpoint does not yet
implement that persistence or enable the listed Connect action.

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
Console preflight adapter and in-memory network fixtures. No UI changes or real
provider interoperability are claimed by this checkpoint.
