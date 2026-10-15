# Product HTTP API

Canonical product operations live under `/api`. Browser UI clients and external
clients use the same handlers, application authorization and response schemas.
This document grows with the [platform MCP milestone](../labnotes/milestones/platform-mcp-endpoint.md);
it describes the implemented tenant read routes and links the existing spec-write
contract. The complete migration inventory is in [product API inventory](product-api-inventory.md).

## Authentication

External clients send a Settings API key in the HTTP header:

```http
Authorization: Bearer <Vxpipe API key>
```

On a Console host, a browser can instead use its existing login-session cookie.
It does not need a Vxpipe API key. Supplying Authorization selects key
authentication: invalid, duplicate or unsupported credentials never fall back to
the browser session. Standalone Gateway accepts keys only. Keys are not query
parameters or request body fields. Use HTTPS outside local development.

The tenant read routes accept Create & Join Calls, Full Tenant Access and Full
Platform Access keys. A tenant key can discover only its own tenant. A platform
key can discover all tenants. Existing tenant administration keys retain their
own-tenant read access. Legacy installation operator (`vxop_`) keys are not
accepted by these new directory routes. Browser users retain their actual tenant
visibility and permissions; authentication does not create additional grants.

Responses use `Cache-Control: no-store`. API-key revocation affects subsequent
requests, including requests from already configured clients.

## List tenants

```http
GET /api/tenants
```

| Query parameter | Contract |
| --- | --- |
| `q` | Optional case-insensitive substring of the tenant name or public key. Trimmed; at most 120 characters. Defaults to empty. |
| `page` | Positive integer; defaults to 1, maximum 2147483647. |
| `page_size` | Integer from 1 through 50; defaults to 25. |

Unknown query parameters are rejected. Authorization and the search filter apply
before totals and pagination. Results sort by case-insensitive name, then public
tenant key. Pagination is not a snapshot across concurrent writes.

```sh
curl --fail-with-body \
  'https://YOUR-VXPIPE-HOST/api/tenants?page=1&page_size=25' \
  -H 'Authorization: Bearer YOUR_VXPIPE_API_KEY'
```

Example response:

```json
{
  "items": [
    {"tenant_key": "AAAAAAAAAAAAAAAA", "name": "Example tenant"}
  ],
  "pagination": {
    "page": 1,
    "page_size": 25,
    "total": 1,
    "total_pages": 1
  }
}
```

An empty first page returns `items: []`, `total: 0`, and `total_pages: 0`.
Requesting a page above `max(total_pages, 1)` returns `page_out_of_range`.
Tenant keys are public resource identifiers, not API credentials or database IDs.

## Get tenant information

```http
GET /api/tenants/:tenant_key
```

```sh
curl --fail-with-body \
  'https://YOUR-VXPIPE-HOST/api/tenants/AAAAAAAAAAAAAAAA' \
  -H 'Authorization: Bearer YOUR_VXPIPE_API_KEY'
```

Example response:

```json
{
  "tenant_key": "AAAAAAAAAAAAAAAA",
  "name": "Example tenant",
  "created_at": "2026-10-15T00:00:00Z"
}
```

The detail route returns the UTC creation timestamp in addition to the list
fields. Missing, invalid and foreign tenant identifiers all return the same
`tenant_not_found` response. There is no `tenant_id` alias.

## Tenant read errors

Failures have a bounded JSON envelope:

```json
{"error":{"code":"tenant_not_found"}}
```

| HTTP status | Code | Meaning |
| --- | --- | --- |
| 401 | `invalid_api_key` | Missing, malformed, unsupported, unknown, ambiguous or revoked key. |
| 401 | `session_required` | Console session authentication was selected, but no valid login session exists. |
| 403 | `forbidden` | Authenticated actor lacks directory access. |
| 404 | `tenant_not_found` | Tenant lookup is not visible or has no matching tenant. |
| 422 | `invalid_tenant_page_request` | Invalid query, page, page size or unsupported query parameter. |
| 422 | `page_out_of_range` | Requested page exceeds the filtered result range. |
| 503 | `tenant_directory_unavailable` | Authentication storage, directory storage or a required operation is unavailable. |

Backend exceptions, credential material and internal database IDs are not returned.
When the tenant directory feature is disabled, these routes return 404.

## Existing call-spec writes

The canonical routes are `POST /api/tenants/:tenant_key/call-specs`,
`PUT /api/tenants/:tenant_key/call-specs/:id`, and
`POST /api/tenants/:tenant_key/call-specs/:id/revisions/:revision/publish`.
They accept the existing `source` schema, preserve immutable revisions, and support
the configured browser session adapter as well as API keys. Browser writes retain
CSRF protection. See the [authoring contract](operator-api-key-authoring.md) for
request bodies, publication behavior and compatible installation-authoring routes.

During migration, legacy Console `/admin/api` routes retain their original response
envelopes. They are not alternate canonical schemas. The tenant directory UI cutover
is tracked separately in the milestone; this API addition does not claim that all
existing UI requests have migrated yet.
