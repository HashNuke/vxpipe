# Product HTTP API

Canonical product operations live under `/api`. Browser UI clients and external
clients use the same handlers, application authorization and response schemas.
This document grows with the [platform MCP milestone](../labnotes/milestones/platform-mcp-endpoint.md);
it describes tenant and call-spec reads, provider catalogs, and the existing
spec-write contract. The complete migration inventory is in
[product API inventory](product-api-inventory.md).

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

## List call specs

```http
GET /api/tenants/:tenant_key/call-specs?page=1&page_size=25
```

Call-spec reads, writes and provider catalogs accept Full Tenant Access and Full
Platform Access keys. Create & Join Calls keys cannot read source or catalogs.
Tenant credentials are restricted to their own tenant. Browser users need
`call_specs.read` for reads/catalogs and `call_specs.write` for writes, within the
requested tenant; being signed in does not grant those permissions.

The list accepts only `page` and `page_size`, with the same defaults and bounds
as the tenant directory. Rows are ordered by latest revision timestamp descending,
then public spec ID descending. It preserves the browser directory's rich summary
schema and does not return source or compiled metadata:

```json
{
  "tenant": {"key": "AAAAAAAAAAAAAAAA", "name": "Example tenant"},
  "call_specs": [
    {
      "id": "example-spec",
      "name": "Example spec",
      "latest_revision": 3,
      "published_revision": 2,
      "call_count": 4,
      "updated_at": "2026-10-15T00:00:00Z"
    }
  ],
  "pagination": {"page": 1, "page_size": 25, "total": 1, "total_pages": 1}
}
```

`published_revision` is null when no revision is published. The empty-first-page
and out-of-range behavior matches tenant pagination. The canonical page-size
maximum is 50; this does not change older Elixir/legacy directory limits.

## Read a call spec

```http
GET /api/tenants/:tenant_key/call-specs/:call_spec_id
GET /api/tenants/:tenant_key/call-specs/:call_spec_id?revision=2
```

Omitting `revision` selects the latest saved revision, which may be a draft.
An explicit revision must be an integer from 1 through 2147483647. Unknown query
parameters are rejected. The `{call_spec: ...}` response contains:

- `call_spec_id`, selected `revision`, `schema_version`, and `source_digest`.
- Portable `source`, ready to edit and submit to the existing write endpoints.
- Current `latest_revision` and `published_revision`, even when reading history.
- Selected-revision `published`, `published_at`, safe `validation_errors`, and
  participant `routes` with `participant_key`, `participant_ref`, and `published`.

Reading never publishes or starts a call. Responses exclude compiled metadata and
database IDs. The public source field remains `source`; MCP maps its separate
`call_spec_definition` argument/result at the protocol boundary.

Spec read failures use the same `{error: {code: ...}}` envelope: 401
`invalid_api_key`/`session_required`, 403 `authoring_forbidden`, 404
`tenant_not_found`/`call_spec_not_found`, 400 `invalid_request`, 422
`invalid_page`/`page_out_of_range`, or 503 `call_spec_directory_unavailable`.
Invalid, unauthorized or unavailable reads never return backend error details.

## Provider and model catalogs

```http
GET /api/tenants/:tenant_key/providers?capability=text_to_speech
GET /api/tenants/:tenant_key/providers/:provider/models?capability=text_to_speech
```

`capability` is required. The catalog accepts the supported capability identifiers,
including `text_to_speech`, `speech_to_text`, `speech_to_speech`, and
`model_inference`. These are local catalog queries and do not call a live provider.
Provider rows include safe credential availability booleans; model rows retain
their voice and option metadata. Credentials themselves are never returned.

With neither pagination parameter, existing clients receive the unchanged
`{providers: [...]}` or `{models: [...]}` envelope. Supplying `page` or `page_size`
opts into the bounded public list projection:

```json
{
  "items": [],
  "pagination": {"page": 1, "page_size": 25, "total": 0, "total_pages": 0}
}
```

Pagination uses the same defaults and bounds as tenant lists and preserves catalog
order. Invalid pagination returns 422 `invalid_page`; an excessive page returns
422 `page_out_of_range`. Other catalog errors include 403 `authoring_forbidden`,
422 `invalid_capability`, 404 `provider_not_found`/`tenant_not_found`, and 503
`provider_catalog_unavailable`, alongside the authentication errors above.

## Call-spec writes

The canonical routes are `POST /api/tenants/:tenant_key/call-specs`,
`PUT /api/tenants/:tenant_key/call-specs/:id`, and
`POST /api/tenants/:tenant_key/call-specs/:id/revisions/:revision/publish`.
They accept the existing `source` schema, preserve immutable revisions, and support
the configured browser session adapter as well as API keys. Browser writes retain
CSRF protection. See the [authoring contract](operator-api-key-authoring.md) for
request bodies, publication behavior and compatible installation-authoring routes.

During migration, legacy Console `/admin/api` routes retain their original response
envelopes. UI callers are migrated in subsequent milestone checkpoints; these API
additions do not claim that all existing UI requests have migrated yet.
