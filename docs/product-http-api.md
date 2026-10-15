# Product HTTP API

Canonical product operations live under `/api`. Browser UI clients and external
clients use the same handlers, application authorization and response schemas.
This document grows with the [platform MCP milestone](../labnotes/milestones/platform-mcp-endpoint.md);
it describes tenant and call-spec reads, provider catalogs, spec writes,
and call creation/join-token operations. The complete migration inventory is in
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


## Create a call

```http
POST /api/tenants/:tenant_key/call-specs/:call_spec_id/calls
Idempotency-Key: client-generated-request-id
```

Create & Join Calls and Full Tenant Access keys can create calls in their tenant;
Full Platform Access keys can select any tenant. Browser users need `calls.write`
for that tenant and a valid CSRF token. Admin-only tenant keys cannot create calls.

The body accepts only optional `variables` (an object, default `{}`) and `to`
(an E.164 destination when the outgoing spec requires one). Supplied variable
sections must satisfy the published spec's schemas; values are not coerced.
Omitted sections retain their existing absent value rather than gaining defaults.

```sh
curl --fail-with-body \
  'https://YOUR-VXPIPE-HOST/api/tenants/AAAAAAAAAAAAAAAA/call-specs/YOUR_SPEC_ID/calls' \
  -H 'Authorization: Bearer YOUR_VXPIPE_API_KEY' \
  -H 'Content-Type: application/json' \
  -H 'Idempotency-Key: example-call-attempt-1' \
  --data '{"variables":{}}'
```

A new call returns 201 with the existing response shape:

```json
{
  "call": {
    "id": "CREATED_CALL_ID",
    "call_spec_id": "YOUR_SPEC_ID",
    "revision": 1,
    "state": "prepared",
    "outgoing_outcome": null
  }
}
```

Creation pins one published revision. A web-entry spec produces a prepared call;
it does not issue a token or start media. An outgoing spec starts its admission
workflow and waits for dial-submission acknowledgement. This does not establish
that the destination answered. Carrier-only incoming specs cannot be started by
this operation and return 422 `unsupported_call_entry`.

`Idempotency-Key` is optional, nonblank UTF-8, and at most 256 bytes. Reusing it
for the same tenant, spec, variables and destination returns the same call with
200, including after republication. Changed input returns 409
`idempotency_conflict`. Without a key, each request is a separate attempt. Failed
or uncertain outgoing replays preserve their failure and never dial again.
After a lost response, retry with the original key and exactly the same input;
do not automatically create another attempt with a new key.

Other failures include 400 `invalid_request`, 403 `not_authorized`, 404
`call_spec_not_found`, 422 `call_spec_not_published`, destination validation or
variable-resolution errors, and 503 `call_management_unavailable`.
`outgoing_call_start_failed` and `outgoing_submission_unknown` are 503 failures
with `retryable: false`. Errors use `{error: {code, message, retryable, details}}`;
responses never contain the pinned plan, initial variables or provider credentials.

## Issue a join token

```http
POST /api/tenants/:tenant_key/calls/:call_id/join-tokens
```

This operation has the same call-management authority as creation. Its JSON body
accepts optional `participant_key` and `join_token_ttl_seconds` (integer, default
300, minimum 300, maximum 86400). Omit the participant only when the call has an
eligible pinned web entry; otherwise select an eligible web participant explicitly.
The participant is resolved against the call's pinned revision, never the latest
published spec. Explicit null values and unknown fields are rejected.

```sh
curl --fail-with-body \
  'https://YOUR-VXPIPE-HOST/api/tenants/AAAAAAAAAAAAAAAA/calls/YOUR_CALL_ID/join-tokens' \
  -H 'Authorization: Bearer YOUR_VXPIPE_API_KEY' \
  -H 'Content-Type: application/json' \
  --data '{"join_token_ttl_seconds":300}'
```

A successful response is 201:

```json
{
  "call_id": "YOUR_CALL_ID",
  "participant_key": "RESOLVED_PARTICIPANT_KEY",
  "join_token": {
    "token": "SINGLE_USE_JOIN_TOKEN",
    "expires_at": "2026-10-15T12:05:00Z"
  }
}
```

Keep this bearer token secret. It authorizes one scoped participant admission;
it is not an API key. Existing participant-scoped issuance remains available at
`POST /api/tenants/:tenant_key/calls/:call_id/participants/:participant_key/join-tokens`
and uses the same policy and issuer. That route accepts only the optional TTL.
Token redemption retains existing single-use admission behavior. Ended or failed
calls cannot issue usable new tokens. Errors include 400 `participant_required`
or `invalid_request`, 404 `call_route_not_found`, 409 `call_unavailable`, and the
same authentication/unavailable errors as call creation.
