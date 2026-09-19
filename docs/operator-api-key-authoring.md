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
authenticated status request. The next commit connects call-spec writes to that
authority. Both are runnable vertical steps; A3 remains unchecked until both pass.
The wider bootstrap milestone's demo-tenant and provisioning HTTP operations remain
separate from this bounded authoring flow.

## Verification

- [x] Prove bootstrap, replacement rollback, revocation and hash-only storage using
  PostgreSQL; repeated bootstrap never emits a second secret.
- [x] Prove protected output, failed-output recovery and secret-safe errors.
- [x] Prove operator/tenant key separation and authenticated status through HTTP.
- [ ] Prove operator platform-service writes, tenant rejection and tenant-owned
  updates/publish through the HTTP authoring boundary.
- [ ] Restart with persisted keys and run owning suites plus umbrella gates.

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
files were removed. Call-spec HTTP routes described above are the next step and are
not yet implemented by this key-lifecycle step.

Design review, 2026-09-19: this follows the completed tenant-key and A2 authoring
boundaries. It adds no database dependency to Gateway or Console dependency to Calls.
The two delivery steps avoid combining key lifecycle and all authoring routes into
one review. The checklist records implementation evidence separately from this review.
