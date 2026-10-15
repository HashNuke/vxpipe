# Product HTTP API

Canonical product operations live under `/api`. Browser UI clients and external
clients use the same handlers, application authorization and response schemas.
This document grows with the [platform MCP milestone](../labnotes/milestones/platform-mcp-endpoint.md);
it describes tenant and call-spec reads, provider catalogs, spec writes,
call creation/join-token operations, account administration, and session-only
API-key management, services, provider credentials, role administration and
password reset, tenant creation and call inspection. The complete migration
inventory is in
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

Operations explicitly documented as session-only are hosted by Console and reject
any Authorization header with 401 `session_required`, even alongside a valid
login cookie. API-key management below is one such operation; having a platform
key does not grant permission to mint or revoke other keys.

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
    {"tenant_key": "AAAAAAAAAAAAAAAA", "name": "Example tenant", "created_at": "2026-10-15T00:00:00Z"}
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

## Create a tenant

```http
POST /api/tenants
Content-Type: application/json

{"name":"Example tenant"}
```

Console hosts this session-only operation. It requires a logged-in browser actor
with installation `tenants.write`, the normal CSRF token and an allowed host.
Any Authorization header is rejected with 401 `session_required`; machine keys
have no tenant-creation grant. Standalone Gateway does not host this write.

The name is trimmed and must contain 1–256 characters of valid text, without NUL.
Success returns 201 with `{tenant:{key,name,dashboard_path,created_at}}`, preserving
the existing creation response. `key` is the generated public tenant key;
`created_at` is an ISO 8601 timestamp. Creation issues no API keys and grants no
implicit membership or resource access to the creator.

Permission denial returns 403 `forbidden`, invalid names return 422
`invalid_tenant_name`, and storage/identifier failures return 503
`tenant_creation_unavailable`, using the standard error envelope. The legacy
`POST /admin/api/tenants` is a compatibility alias with the same handler and
session, CSRF and host requirements. Tenant discovery remains the separately
documented session/key GET operation.

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

## Call inspection and artifacts (Console session only)

These reads use the logged-in actor's tenant-scoped `calls.read` permission.
They accept no machine-key authority or MCP tools. Every canonical route returns
401 `session_required` when no valid session exists or any Authorization header
is supplied, even alongside a valid cookie. Responses are private and no-store.

| Method and path | Result |
| --- | --- |
| `GET /api/tenants/:tenant_key/calls` | Call directory with pagination and filter context |
| `GET /api/tenants/:tenant_key/calls/spec-options` | Paginated spec choices for the call filter |
| `GET /api/tenants/:tenant_key/calls/:call_id` | Tenant/spec metadata and inspection snapshot |
| `GET /api/tenants/:tenant_key/calls/:call_id/inspection` | Inspection snapshot for polling |
| `GET /api/tenants/:tenant_key/calls/:call_id/details/:publication_id` | Exact published JSON attachment |
| `GET /api/tenants/:tenant_key/calls/:call_id/recordings/:artifact_id` | Streamed WAV recording |

The call directory accepts `page` (default 1) and optional `call_spec_id`
(nonempty, at most 256 bytes). Page size is fixed at 25. Its response is
`{tenant,call_specs,call_specs_truncated,selected_call_spec_id,calls,pagination}`.
Pagination contains `{page,page_size,total,total_pages}`. Tenant and filter
visibility apply before results are returned. Spec choices are `{id,name}`.

The spec-options route accepts `q` (trimmed, default empty, at most 256 bytes)
and `page` (default 1), returning `{options:[{id,name}],has_more}` with at most 25 choices
per page. This searches authorized call filters; it does not grant spec-source
access. Invalid directory filters/pages return 422; unavailable directories or
searches return 503 using `{error:{code}}`.

Call detail returns `{tenant,call_spec,call_spec_revision,inspection}`. Polling
returns just the same versioned inspection object (`schema_version: 1`). The
shared query verifies the requested tenant/call and pinned revision before reading
history; it does not silently select the latest spec. Missing calls return 404
`call_not_found`, malformed inspection requests return 400
`invalid_call_inspection`, and unavailable inspection returns 503
`call_inspection_unavailable`.

Publication and recording reads verify that the exact artifact belongs to the
requested call. Published details are an `application/json` attachment with a
safe filename. WAV responses retain streaming and byte-range support: 200 for a
full read, 206 for an accepted range, 416 for an invalid range, and 502 when the
initial artifact read fails. Clients should supply `Accept: audio/wav` when
reading recordings; these endpoints do not require JSON Accept negotiation.

Legacy call-directory/detail aliases under `/admin/api` and inspection/download
aliases under `/tenants` remain thin compatibility routes to the same handlers
and policy. Legacy downloads retain their browser login redirect when no session
exists; explicit Authorization is still rejected before session fallback.
New clients should use the canonical routes above.

## Users and role options

```http
GET /api/users?page=1&page_size=25
GET /api/users/:user_id
POST /api/users
PATCH /api/users/:user_id
POST /api/users/:user_id/disable
GET /api/role-options?page=1&page_size=25
```

These installation-wide operations accept Full Platform Access keys. Tenant keys,
including Full Tenant Access, and legacy operator keys cannot administer users.
Browser sessions use their actual `users.read` and member/admin/superadmin account
write permissions. Supplying a key selects that key's authority without combining
it with the browser's permissions. Browser mutations require CSRF protection.

The user directory accepts `page`, `page_size`, optional `query` (trimmed email
search, at most 120 characters), and optional `role_id` (public UUID). Role options
accept only `page` and `page_size`. Both use page 1 and size 25 by default, with
size at most 50. Unknown filters are rejected. Users sort by normalized email,
then public user UUID; roles sort by name, then public role UUID. Counts and
filtering happen before pagination. Pages are not snapshots across concurrent
writes; empty first pages and out-of-range errors follow the tenant-list rules.

User lists return `{users, pagination}`; detail and mutation responses return
`{user: ...}`. The compatible HTTP user shape is:

```json
{
  "id": "PUBLIC_USER_UUID",
  "email": "person@example.test",
  "roleId": "PUBLIC_ROLE_UUID",
  "enabled": true,
  "memberships": [{"tenantId": "AAAAAAAAAAAAAAAA", "access": "read_write"}]
}
```

`tenantId` in this existing response shape is the public tenant key, never a
database primary key. Canonical request fields use `role_id` and
`memberships[].tenant_key`. The same response schema serves browser and external
HTTP clients. MCP projects the corresponding `user_id`, `role_id` and `tenant_key`
fields. Neither projection returns passwords, hashes, session tokens or grants.

Creation requires `email`, `password`, `password_confirmation`, and `role_id`.
Optional `memberships` is an array of unique `{tenant_key, access}` entries with
access `read` or `read_write`; the chosen role must support tenant assignments.
Passwords must match and satisfy the existing 15–128-character policy. They are
input-only and are not trimmed. Creation returns 201 and an enabled user.

A PATCH contains one or more of `email`, `role_id`, `memberships`, and `enabled`.
Omitted fields remain unchanged. Supplying `memberships: []` explicitly clears
assignments. `enabled: false` disables the user and revokes their login sessions;
`enabled: true` reactivates them but does not revive revoked sessions. Password
fields and explicit null values are unsupported. Updates return 200.

```sh
curl --fail-with-body \
  'https://YOUR-VXPIPE-HOST/api/users/YOUR_USER_UUID' \
  -X PATCH \
  -H 'Authorization: Bearer YOUR_PLATFORM_API_KEY' \
  -H 'Content-Type: application/json' \
  --data '{"enabled":true}'
```

The `/disable` operation takes `{}`, performs the same partial update with
`enabled: false`, and is safe to repeat. It does not delete the user or change
the independent API-key lifecycle. The last enabled superadmin cannot be disabled
or demoted. Changes retain existing current/requested role-category guards.

Role options return `{roles, pagination}`. Each role is `{id, name, kind}`, where
kind is `admin`, `superadmin`, or null for an ordinary role. This endpoint does not
expose or edit role grants. Password reset and role administration are not granted
to API keys by these operations.

Account failures use `{error: {code, message, retryable, details}}`: 401
`invalid_api_key`/`session_required`, 403 `forbidden`, 404 `not_found`, 409
`email_taken`/`last_superadmin`/`stale`, 422 validation or pagination codes, and
503 `account_management_unavailable`. Successful machine writes revalidate the
active platform key inside the transaction and attribute audit to its key ID.
Deployments must apply migration `20261015000300` before enabling these writes.

## API-key management (Console session only)

```http
GET /api/api-keys?q=backend&page=1
GET /api/api-keys/tenants?kind=calls&q=example&page=1
POST /api/api-keys
DELETE /api/api-keys/:id
```

These are the endpoints used by Settings. They require a browser login session;
mutations also require its CSRF token. They are unavailable on standalone Gateway.
Canonical and legacy `/admin/api/api-keys` aliases use the same handlers and
application policy. Any explicit Authorization header is rejected before body
parsing or session fallback. Neither a tenant nor platform API key can delegate
credentials through these endpoints.

Lists accept optional `q` (at most 120 characters, trimmed) and `page` (1 through
1000000, default 1). They use a fixed page size of 25 and the existing pagination
shape `{page, page_size, total, has_next}`. Key lists return
`{keys, pagination, creatable_kinds}`. Each key contains `id`, `name`, `kind`,
`last_four`, `tenant`, `created_at`, and `can_revoke`; `tenant` is null for a
platform key or `{key, name}` for a tenant key. Neither digests nor secrets appear
in listings. Legacy tenant keys have kind `legacy_admin` and may have no suffix.

The issuance-target list requires `kind=calls` or `kind=full` and returns
`{tenants, pagination}` with `{key, name}` tenant rows. Both lists apply the
current user's visibility and delegation limits before pagination. A target in
this list is not a grant to issue a broader key.

Creation accepts `{name, kind, tenant_key}`. The trimmed name must be nonempty
and at most 256 bytes. Kind is `calls`, `full`, or `platform`; tenant kinds require
the public tenant key, while platform creation uses null or omitted `tenant_key`.
Existing permissions and delegation ceilings apply; platform-key issuance remains
Superadmin-only. Success returns 201 `{key, secret}`. Save the secret at this point:
it is not available from subsequent reads. Revocation returns 204 and affects
subsequent authentication without deleting the user's login session.

Failures use `{error: {code}}`: 401 `session_required`, 403 `forbidden`, 404
`not_found`/`tenant_not_found`, 422 `invalid_name`/`invalid_query`/`invalid_key_type`,
or 503 `api_keys_unavailable`. Public non-HTTPS and carrier-only hosts do not expose
these routes. Legacy aliases remain for compatibility; new clients should use
`/api/api-keys`.


## Services and provider credentials (browser sessions)

These Console-owned endpoints accept login sessions only. Explicit Authorization
headers are rejected with 401 `session_required`, including with a valid cookie.
Mutations require the existing CSRF token. Legacy `/admin/api` aliases use the
same handlers, policy and credential rules. These endpoints do not accept machine keys or expose MCP tools. Errors normally use `{error:{code}}`.

### Service directories

- `GET /api/platform/services`: requires `platform_services.read`.
- `GET /api/tenants/:tenant_key/service-bindings`: requires tenant
  `tenant_services.read`, including the existing tenant membership constraint.

Both return `{tenant, bindings, model_catalog, webhook_urls,
provider_capabilities}`. Platform `tenant` is null; tenant scope returns
`{key,name}`. Each binding contains `provider`, `name`, `source` (`platform` or
`tenant`), `status` (`connected`, `invalid`, `unavailable`), nullable
`credential_id`, `platform_available`, `saved_fields` (field names only), and
nullable `last_validated_at`. Effective bindings preserve inherited platform and
tenant overrides. `webhook_urls` has `platform` and nullable `tenant` URLs;
`provider_capabilities` maps provider names to capability lists. `model_catalog`
is the existing local model-catalog object. There is no page/cursor contract for
these binding directories; domain validation caps accepted bindings at 1,500.
Errors: 403 `forbidden`, 404 `tenant_not_found`, 503
`service_directory_unavailable`.

- `GET /api/tenants/:tenant_key/services`: requires `tenant_services.read`;
  returns `{tenant:{key,name},credentials,telephony_services,truncated}`.
- `GET /api/tenants/:tenant_key/credentials`: same authority; returns
  `{tenant:{key,name},credentials,truncated}`.

Credential rows contain `id`, `provider`, `name`, `auth_kind`, `status`,
`credential_preview`, nullable `last_validated_at`, `created_at`, `updated_at`.
Preview entries contain `label`, `format` (`masked` or `last_four`), and
`last_four` only for the latter. Telephony rows contain `id`, `name`, `provider`,
`provider_connection_id`, nullable `credential_id`, and `outbound_number`.
These preserve the existing maximum 100 credentials and 100 telephony rows and
`truncated` signal; there is no new page parameter. Errors match the directories
above. Credential values are never returned.

### Credential validation and mutation

Use either prefix `/api/platform/credentials` or
`/api/tenants/:tenant_key/credentials`. Platform operations require
`platform_services.write`; tenant operations require `tenant_api_keys.write`
and writable membership. Direct Calls credential validation enforces this
same write authority, including before calling the provider validator.

- `POST <prefix>/test`: JSON `{provider,name?,values}`; name defaults to provider.
  Returns 200 `{status:"valid"}`. Does not store the credential.
- `POST <prefix>`: same body; returns 201 `{credential:<safe metadata above>}`.
  Saving does not implicitly call provider validation or claim validation.
- `PATCH <prefix>/:credential_id`: JSON `{provider,values}` replaces the exact
  credential's values while retaining its identity/name; returns 200
  `{credential:<safe metadata>}`.
- `DELETE <prefix>/:credential_id`: no body; returns 204.

Values follow the provider schema: common API-key providers use `{api_key}`;
Telnyx accepts `{api_key,public_key?}`; Twilio uses `{account_sid,auth_token}`.
`auth_kind` is resolved server-side, not provided by the caller. Values are
input-only. The provider schema validates types/formats before validation/storage.

All operations may return 403 `forbidden`. Validation errors: 422
`invalid_credential` or `credential_rejected`; 501
`credential_validation_unsupported`; 503 `credential_validation_unavailable`.
Create errors: 404 `tenant_not_found`; 409 `credential_already_exists`; 422
`invalid_credential`; 503 `credential_store_unavailable`. Update errors: 404
`credential_not_found`; 422 `invalid_credential`; 503
`credential_store_unavailable`. Delete errors: 404 `tenant_not_found` or
`provider_credential_not_found`; 409 `provider_credential_in_use`; 422
`invalid_credential`; 503 `credential_store_unavailable`.

### Tenant telephony applications

- `GET /api/tenants/:tenant_key/telephony-applications`: requires
  `tenant_services.read`; returns `{tenant:{key,name},applications,truncated}`.
  Each application is `{id,name,provider_connection_id,outbound_number,
  published_routes}`. Each published route contains `number`, `call_spec_id`,
  `call_spec_name`, `call_spec_revision`, `participant_ref`, and `ambiguous`.
  Existing bounds are 100 applications and 500 published routes, with truncation
  signalled; no new pagination.
- `POST /api/tenants/:tenant_key/telephony-applications`: requires
  `tenant_services.write`; body `{name,provider_connection_id,outbound_number?}`;
  creates a Telnyx application referencing the effective `telnyx` credential
  binding. Returns 201 `{application:{id,name,provider_connection_id,
  outbound_number}}`.
- `PATCH /api/tenants/:tenant_key/telephony-applications/:service_id`: same write
  authority; nonempty body permitting only `provider_connection_id` and
  `outbound_number`; returns 200 with the same application envelope. Immutable
  name, provider and credential ownership are not caller-editable here.

Errors: 403 `forbidden`; 404 `tenant_not_found` or
`telephony_service_not_found`; 409 `telephony_service_conflict`; 422
`invalid_telephony_service`, `invalid_tenant_key`, or
`provider_credential_unavailable`; 503 `telephony_services_unavailable`.

### Authoring phone-number inventory

`GET /api/tenants/:tenant_key/telephony-services/:service/numbers` requires
`call_specs.write`, not merely service-directory access. Query parameters:
`search` (default empty, max 64 bytes), optional provider cursor `page` (1–256
bytes), optional `call_spec_id` (max 128 bytes, excludes that spec's current
assignment when determining availability). Service names must be URL-encoded.
Returns `{numbers,next_page}`, with at most 50 numbers per provider page. Each
number is `{id,number,name,available,assigned_to}`; `assigned_to` contains spec
names. `next_page` is an opaque provider cursor or null, not a page number.
Credential payloads remain inside the provider reader and are not returned.
Existing domain ownership rules still govern platform service visibility.

Preserve existing CallSpecErrors mapping: 400 `invalid_request`; 403
`authoring_forbidden`; 404 `call_spec_not_found`; domain unavailable failures
map to 503 `call_spec_authoring_unavailable`, and unexpected controller
exceptions map to 503 `phone_numbers_unavailable`.

UI consumers now use these canonical routes, including onboarding's service
binding read. Onboarding demo-tenant/sample mutations remain pending product
workflows for a separate migration; they are not reclassified as helpers.


## Role administration (Console session only)

These routes require a named browser administrator or superadministrator. They
reject every Authorization header with 401 `session_required`; API keys do not
acquire role-management authority. Mutations require the existing CSRF protection.
Canonical `/api` and legacy `/admin/api` routes share the same handlers and Identity
operations. Built-in roles remain immutable, reserved grants remain protected,
and role updates preserve transaction-time actor revalidation and session revocation.

| Method and path | Input | Response |
| --- | --- | --- |
| `GET /api/roles` | `page`, `page_size` | 200 `{roles,pagination}` |
| `GET /api/roles/:id` | Public role ID | 200 `{role,affected_users}` |
| `POST /api/roles` | `{name,grants}` | 201 `{role}` |
| `PATCH /api/roles/:id` | `{name,grants,expected_revision}` | 200 `{role}` |
| `DELETE /api/roles/:id` | Public role ID | 204, no body |

Each role is `{id,name,kind,revision,grants}`. `kind` is `admin`, `superadmin`,
or null for an ordinary role. Each grant contains `permission` and `scope` using
the existing [identity permission contract](console-authentication-and-authorization.md).
The server generates internal custom-role slugs; clients use the public `id`.
`affected_users` counts assigned users and does not expose user records.

The list defaults to page 1 and page size 25; maximum page size is 50. Unknown
query parameters, invalid bounds and out-of-range pages are rejected. Pagination
contains `{page,page_size,total,total_pages}`; an empty first page has zero total
pages. Ordering is by name, then public role ID. The database applies the limit
before projecting full grants. Paging is not a snapshot across concurrent writes.
Legacy role lists now have this same bounded envelope.

Errors use `{error:{code}}`: 403 `forbidden` or `protected_role`; 404 `not_found`;
409 `role_in_use` or `stale`; 422 `invalid_page`, `invalid_pagination`,
`page_out_of_range` or `invalid_role`; 503 `unavailable`. Updates require the
current positive `expected_revision`; stale updates do not overwrite newer grants.
Deletion does not silently reassign users of an in-use role.

The role UI requests one page and loads affected-user counts only for that page.
Account editing fetches full metadata for the selected role on demand; denial of
full role metadata preserves existing memberships. Lightweight `/api/role-options`
retains its separate safe-projection contract and existing selector paging.

## Administrator password reset (Console session only)

`POST /api/users/:id/reset-password` accepts:

```json
{"password":"NEW_PASSWORD","password_confirmation":"NEW_PASSWORD"}
```

The body is input-only. Success returns 204 with no password or user-secret data.
Use an authenticated browser session and CSRF protection; any Authorization header
is rejected with 401 `session_required`. The legacy `/admin/api` alias shares this
handler. Machine-key reset authority and an MCP reset tool are not added.

The shared Identity operation authorizes the actual actor against the target's
account category: `users.members.write`, `users.admins.write` or
`users.superadmins.write`. It preserves the existing password validation,
transaction-time authorization and target-session revocation. Errors use
`{error:{code}}`: 403 `forbidden`, 404 `not_found`, 409 `stale` or
`last_superadmin`, 422 `invalid_account`, or 503 `unavailable`.
