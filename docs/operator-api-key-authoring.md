# Operator API keys and call-spec authoring

This implements A3 of [platform and tenant services](platform-and-tenant-services.md).
Calls owns authentication and authority; Persistence owns hash-only storage and trusted
issuance commands; Gateway owns the HTTP protocol. Browser operator sessions remain
independent credentials.

## Decisions

- Bootstrap one installation administrator key through a trusted local command.
  Repeating bootstrap fails even after revocation. Explicit replacement atomically
  revokes the old key and issues a new one; historical records remain revoked.
  There is at most one active installation key in this first slice. Multiple
  independently managed operator keys and granular operator roles are deferred.
- Generate 32 random bytes with a distinct `vxop_` prefix. Store only SHA-256 plus
  public identity and timestamps in a separate table, never a wildcard tenant row.
  Authentication returns explicit installation authority carrying its public key ID.
  Tenant keys cannot authenticate as operators; operator keys cannot authenticate
  against tenant-only endpoints or the operator browser login.
- Write a newly issued secret once to a newly created owner-only output file. Never
  overwrite an existing output file. No anonymous bootstrap endpoint, configured
  default key, plaintext recovery, browser storage or secret query parameters.
- Authenticate each new request. Revocation affects subsequent authentication, not
  previously admitted calls or requests whose authority was already established.
- Expose authenticated `GET /api/platform/status`, then bounded call-spec writes at
  `/api/platform/tenants/:tenant_key/call-specs` and
  `/api/tenants/:tenant_key/call-specs`. The tenant path requires an `admin` tenant
  key; the platform path requires an installation key. Every operation identifies
  its consuming tenant explicitly.
- `POST` saves a new draft, `PUT /:call_spec_id` saves another immutable revision,
  and `POST /:call_spec_id/revisions/:revision/publish` explicitly publishes it.
  Bodies may supply portable source, never authority, repository options or private
  provider credentials. Responses project revision metadata without source or secrets.
  All writes call the principal-aware Calls boundary added in A2, including its
  transaction-time ownership guards. Carrier scope support remains C's prerequisite.

## Alternatives and implications

Extending tenant scopes or inventing a platform tenant would blur the resource owner
and caller authority. Reusing the browser login challenge would merge incompatible
credential lifecycles. Recoverable API-key encryption is unnecessary because only
verification is needed. Silent repeated issuance could turn a retry into untracked
authority; explicit replacement keeps recovery deliberate.

The first key commit delivers trusted bootstrap/replacement/revocation and an
authenticated status request. The second connects call-spec writes to that
authority. Both runnable vertical steps pass focused and combined umbrella gates.
The wider bootstrap milestone's demo-tenant and provisioning HTTP operations remain
separate from this bounded authoring flow.

## Verification

- [x] Prove bootstrap, replacement rollback, revocation and hash-only storage using
  PostgreSQL; repeated bootstrap never emits a second secret.
- [x] Prove protected output, failed-output recovery and secret-safe errors.
- [x] Prove operator/tenant key separation and authenticated status through HTTP.
- [x] Prove operator platform-service writes, tenant rejection and tenant-owned
  updates/publish through the HTTP authoring boundary.
- [x] Restart with persisted keys and run owning suites plus umbrella gates.

## Use the key lifecycle step

Run migrations, compile the application, then bootstrap to a new file in a trusted
directory outside version control:

```shell
mix ecto.migrate
mix compile
mix vxpipe.operator_key.bootstrap --output path/to/protected-operator-key.json
```

The file has mode `0600` and contains `api_key_id` and the one-time `api_key`.
Terminal output contains only public metadata. Use that key as the bearer
Authorization header for `GET /api/platform/status`; the response reports
`authority: "installation_operator"` and its public key ID. This endpoint is enabled
when hosted persistence is configured, in development and production. An explicitly
embedded Gateway leaves it disabled unless `operator_api: [enabled: true]` is supplied.

For a lost key, explicitly replace it using a different output file:

```shell
mix vxpipe.operator_key.replace --output path/to/replacement-operator-key.json
mix vxpipe.operator_key.revoke --key-id PUBLIC_KEY_ID
```

Replacement revokes the prior key atomically; already authenticated requests may
finish. Existing output files are never overwritten, and a bootstrap retry never
returns stored plaintext or issues another key. Failed output writes trigger
best-effort revocation of the newly issued key and removal of the incomplete file.
A process crash or storage failure can prevent that cleanup; explicit replacement
is the recovery path. Migration rollback removes this new key table and its history;
tenant keys and provider ciphertext remain unchanged.

The first step passed a disposable-database exercise with two concurrent bootstrap
processes, actual authenticated Gateway HTTP requests, fresh-process restart,
replacement/revocation and authority separation. The fixture and its private output
files were removed. The key-lifecycle step is committed as `c6b83d9`.

## Call-spec HTTP requests

New sources use the [call direction schema](call-spec-direction.md): version `20261004.01`
with exactly one `incoming_call` or `outgoing_call` block. Historical `20260915.01`
sources keep their entry fields and remain accepted. Save/publication does not place calls.

The authoring step implements the three operations for both URL scopes:

| Method and suffix | Body | Result |
| --- | --- | --- |
| `POST /call-specs` | `{"source": PORTABLE_CALL_SPEC}` | `201`, a new generated spec ID and draft revision |
| `PUT /call-specs/:call_spec_id` | `{"source": PORTABLE_CALL_SPEC}` | `201`, append a revision under that ID (or create it if absent) |
| `POST /call-specs/:call_spec_id/revisions/:revision/publish` | `{}` | `200`, explicitly publish that revision |

Prepend `/api/platform/tenants/:tenant_key` when using an operator key, or
`/api/tenants/:tenant_key` when using that tenant's `admin` key. Send the key as a
bearer Authorization header and use `application/json`. Body fields other than the
ones above are rejected. IDs remain bounded to 128 bytes; revision numbers must be
positive database integers. Requests cannot select authority, repositories or
service-owner options.

Responses contain a `call_spec` metadata object with its ID, revision, schema,
source digest, publication state and public participant routes. Source and compiled
configuration are omitted. Unsupported configuration produces a bounded
`validation_errors` entry with its code, field path and reason.
Draft routes remain unavailable until publication.

`401` rejects missing, invalid or wrong-scope keys; `403` rejects insufficient author
authority, including `provider_service_forbidden` for tenant writes referencing
platform-only services. Malformed requests return `400`; invalid source or unavailable
provider credentials return `422`; an unpublishable draft returns `409`; missing
resources return `404`; an unavailable backend returns `503` without raw reasons.
Responses use `Cache-Control: no-store`.

Hosted persistence enables these routes in both environments. An embedded Gateway
must explicitly enable `call_spec_authoring` and configure its Calls repositories;
it remains disabled by default. This does not enable anonymous tenant administration.

A second disposable-database HTTP exercise proved operator create/update/publish with
platform services, tenant create/edit/publish rejection, successful tenant writes
after configuring tenant services, and immutable revision continuity across restart.
Rejected tenant edits allocated no revisions. The 41-test Gateway HTTP group passes;
the combined A3 umbrella run passes 1,754 tests with 40 exclusions
(`--max-cases 1 --seed 772211`). Root format, warnings-as-errors compile, strict Credo
and unused-dependency checks pass. Review found no remaining authoring issue; scoped
Telnyx caller support remains checkpoint C.

Design review, 2026-09-19: this follows the completed tenant-key and A2 authoring
boundaries. It adds no database dependency to Gateway or Console dependency to Calls.
The two delivery steps avoid combining key lifecycle and all authoring routes into
one review. The checklist records implementation evidence separately from this review.

## Field-level authoring errors

Rejected sources return one fail-fast error with a JSON field path (an array of
strings) and a value-free reason. Create, append and publish use the same Calls-owned
projection. For example, a missing agent prompt returns `422`:

```json
{"error":{"code":"invalid_call_spec","path":["participants","assistant","prompt"],"reason":"is required"}}
```

| Status | Code | Meaning |
| --- | --- | --- |
| 422 | `invalid_call_spec` | The portable source fails validation; `path` and `reason` locate the first problem. |
| 422 | `private_call_spec_material` | Remove credentials or secrets at the returned path. |
| 422 | `invalid_telephony_route` | The selected phone route is invalid. |
| 422 | `provider_credential_unavailable` | The selected provider has no usable credential. |
| 422 | `telephony_caller_id_missing` | The callee's service has no outbound caller ID. |
| 403 | `provider_service_forbidden` | The author's authority does not allow the selected service. |
| 409 | `revision_conflict` | Revision allocation conflicted, including exhausted bounded retries; reload before retrying. |
| 409 | `call_spec_not_publishable` | The saved draft has a compiler error; `path` and `reason` describe the first error. |

An empty path means the error applies to the document or the failing backend did
not provide a field location. A successful draft response's `validation_errors`
contains at most one `{code, path, reason}` compiler error, rather than an opaque
summary. Older stored errors without structured details receive a fixed explanation.
Authentication, malformed-request, not-found and unavailable errors retain their
existing status and code. Reasons never include submitted values, provider payloads
or exception messages; paths redact non-identifier source keys. These changes add
no separate validation endpoint and do not change immutable revision behavior.

## Starting an outgoing call

Publish a spec with an `outgoing_call` block, then send a tenant API key with the `calls`
scope. An `admin` key alone cannot start calls. This endpoint has no browser CORS grant.

```http
POST /api/tenants/:tenant_key/call-specs/:call_spec_id/calls
Authorization: Bearer <tenant calls key>
Idempotency-Key: <opaque client request key>
Content-Type: application/json

{"to": "+14155550123", "variables": {"customer": {"name": "Dana"}}}
```

The body accepts only `to` and `variables`; any other field, including the former
`initial_variables` name, returns `400`.

- `to` is the E.164 number to dial (`+` and up to 15 digits, for example `+14155550123`). It
  is required when the callee connection has no fixed `number` (`422 to_required`), must be
  E.164 (`422 invalid_to`), and is rejected when the spec fixes the number
  (`422 to_not_allowed`). A non-string `to` returns `400`.
- `variables` is optional context for the call (stored as its initial Call Variables), validated against the spec's declared
  sections. It never selects the destination.

The request cannot override provider credentials or the originating number. A callee service
without an outbound caller ID returns `422 telephony_caller_id_missing`. The call record stores
the dialed number (`to_number`) and the service caller ID it was admitted with (`from_number`);
neither appears in the response or in logs.

`201` confirms creation and dial submission acknowledgement. The `call` object contains
`id`, `call_spec_id`, pinned `revision`, `state` and `outgoing_outcome`. A prompt terminal
event can end the room before the response. Call details and inspection expose the bounded
`outgoing_outcome` and nullable `dial_submitted_at`, `answered_at`, and `dial_ended_at`.
Outcomes are `answered`, `no_answer`, `busy`, `rejected`, `failed`, `machine`, or `unknown`.
An answer remains `answered` after hangup. These timestamps describe locally observed
lifecycle evidence; `dial_submitted_at` marks the one submission attempt, not proof that the
carrier accepted it. Failed preparation has no dial timestamps. An interrupted submitted
dial without answer evidence becomes `unknown`. Archive projection is asynchronous, so an
immediate inspection may still contain null fields. The metadata contains no request keys,
initial variables, credentials or provider payloads. Carrier acceptance remains checkpoint E.

The optional `Idempotency-Key` is a nonblank UTF-8 value of 1–256 bytes, unique per tenant.
Keep it for lost-response retries: the same spec ID, `to` and variables return the original call
with `200` while admitting, running, or ended and never dial again. A failed start replays its original `503` error and body, including `outgoing_submission_unknown` when applicable.
Changing the request under the same key returns `409`. Without a key, each request creates
a separate call. Starting another attempt requires a new key.

Missing/invalid credentials return `401`; insufficient scope returns `403`; unknown or
foreign specs return `404`; draft-only or incoming specs return `422`; invalid body/key
returns `400`. Start/submission failures return `503` with a bounded public error. A
failed attempt has `retryable: false`: replaying the same key cannot create another attempt.
Replay the original key after a lost response to discover its result. A new key explicitly
starts a new attempt; after `outgoing_submission_unknown`, first inspect the existing call
because submission could have succeeded.

Hosted persistence uses the existing enabled `call_admission` configuration. Embedded
hosts must configure that backend and its Calls repositories. The nine focused HTTP tests
pass, and all root gates passed after D6: 3,121 tests, zero failures, 98 excluded, seed 219668. Native
STS opening and live carrier acceptance remain open. See the
[outgoing example](../examples/call-specs/outgoing-morse.json) and
[lifecycle projection contract](outgoing-call-runtime.md#outgoing-lifecycle-projection).

## Provider and model catalog

Tenant clients with an `admin` API key can discover installed capabilities and
locally supported models through the same authenticated tenant boundary:

```http
GET /api/tenants/:tenant_key/providers?capability=text_to_speech
GET /api/tenants/:tenant_key/providers/deepgram/models?capability=text_to_speech
Authorization: Bearer TENANT_ADMIN_KEY
```

Capabilities are `speech_to_text`, `output_speech_to_text`, `text_to_speech`,
`speech_to_speech`, and `model_inference`. A provider listing returns:

```json
{
  "providers": [
    {
      "id": "deepgram",
      "name": "Deepgram",
      "credential_required": true,
      "credential_available": true
    }
  ]
}
```

This is an abbreviated response. Unavailable implementations are omitted.
`credential_available` means at least one effective named binding is connected,
including an inherited platform binding. An invalid tenant override does not fall
back to its platform binding. Local Morse requires no credential and is available.
Availability describes runtime configuration; it does not grant a tenant API key
permission to author references to platform-owned services. Existing save/publish
ownership checks still apply. No credential values or private metadata are returned.

The model response for Deepgram TTS is:

```json
{
  "models": [
    {
      "id": "flux",
      "name": "Flux",
      "default": true,
      "voices": {"type": "free_text", "default": "hannah", "parameter": "voice"}
    }
  ]
}
```

Use `model: "flux"` and `options: {"voice": "hannah"}` in the call spec; the
adapter constructs its concrete model ID. Opening an existing source preserves its
model and voice. Every listing has exactly one recommended model. An optional public `options` object supplies
required adapter defaults, such as Deepgram STT encoding and sample rate. Copy
those into a new selection, then set its separate voice option when declared. `voices` is null,
a free-text descriptor, or `{"type":"list","parameter":"voice","values":[...]}`
whose entries have `id`, `name`, and one `default: true`. The parameter identifies
the source option (`voice`, or `speaker` for Rime). LLM models also have
`tool_support: true` and `context_limit` (null when unknown). Listings use the
bundled database and local adapters; they do not contact providers or guarantee
remote account access.

| Failure | HTTP status | Error code |
| --- | --- | --- |
| Missing/invalid key | 401 | `invalid_api_key` |
| Insufficient scope | 403 | `authoring_forbidden` |
| Unknown tenant | 404 | `tenant_not_found` |
| Unknown provider, unsupported pair, or missing implementation | 404 | `provider_not_found` |
| Missing/unknown capability | 422 | `invalid_capability` |
| Unavailable catalog or credential repository | 503 | `provider_catalog_unavailable` |

Errors have `{"error":{"code":"..."}}`; backend messages are never included.
Responses disable caching. Embedded hosts enable these endpoints with the existing
`call_spec_authoring: [enabled: true]` setting and configured Calls repositories.

The Console mirrors these routes at `/admin/api/tenants/:tenant_key/providers`
and `/admin/api/tenants/:tenant_key/providers/:provider/models`, protected by the
installation-operator browser session. Its existing platform/tenant service
inventory also includes `model_catalog`, grouped by capability then provider,
with these same model descriptors. Onboarding therefore loads recommendations
before a tenant exists, without keeping a separate frontend model inventory.
