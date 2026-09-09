# Tenant definitions and API-key administration

Status: not implemented. Specification review: approved (2026-09-08).
Prerequisites: [Definition-driven call](definition-driven-call.md).
Sources: [Admission credentials](../../labnotes/20260905-0405-call-definition-design.md#initial-variables-and-api-key-admission--approved-g2-decisions); [routes](../../labnotes/20260905-0405-call-definition-design.md#web-participant-admission-routes--approved-g2-routing); [application boundaries](../../labnotes/20260905-0405-call-definition-design.md#umbrella-application-and-ecto-boundaries).

## Runnable outcome

An operator bootstraps a tenant/API key through trusted OTP/CLI administration, saves and publishes a definition, and reads it back after restart. Draft definitions remain unavailable for call initiation; publication makes a tenant-scoped participant route resolvable.

## Specification

- Add database-neutral definition/deployment and credential repository ports, Calls application workflows, and a separate Ecto-owning persistence application. Gateway authenticates through a port; engine/gateway never own Repo queries. Add dependencies only to their owning child.
- Store immutable definition revisions and validated/compiled reusable metadata. Resolve and pin each call's actual plan at preparation/admission using the then-selected tenant profiles/integrations/catalogs; private credential leases are not reusable persisted definition state. Draft saving can allocate route metadata but only explicit publish/enable exposes it. Route keys live in deployment metadata, not portable JSON; resolution is indexed rather than scanning definitions.
- Public tenant keys are 16 unpadded-base64url characters from 12 random bytes; participant route keys are UUIDs; future public call IDs are UUIDs. Enforce uniqueness separately from internal SQL primary keys.
- Generate high-entropy tenant-bound API keys once, persist only one-way digest plus metadata. Never return stored digests as credentials or retrieve lost plaintext. Bootstrap needs no preexisting key; lost keys require replacement.
- Support independent admin/calls scopes and multiple independently revocable keys without assuming admin implies calls. Key revocation stops further authentication, not already-issued tokens or established sessions. API-key management starts with authorized OTP/CLI; an admin HTTP API is not implied.
- Keep recoverable upstream provider/MCP secrets separate from hash-only Vxpipe keys. Initial administration can reference existing runtime secret stores; encrypted DB storage, if introduced, has a key outside the DB.

## Implementation checklist

- [ ] Write red repository/workflow tests for immutable revisions, draft/publication routing, tenant isolation, IDs, key issuance/verification/revocation.
- [ ] Introduce Calls ports and Ecto schemas/migrations/constraints in the correct applications with no reverse engine dependency.
- [ ] Implement trusted OTP/CLI tenant and first-key bootstrap plus authorized key rotation/revocation.
- [ ] Implement save/publish/read definition workflows through ports and record supported-feature errors before publication.
- [ ] Document migration/bootstrap commands and safe one-time key handling without committing actual credentials.

## Acceptance and failure checks

- [ ] Restart configured persistence/authentication: the original key verifies, but its stored digest, a wrong key, or another tenant's key does not.
- [ ] Revoke one of two keys: the other remains valid; no new dependency from existing tokens/sessions to the revoked key.
- [ ] Admin-only versus calls-only checks use explicit grants, not implicit hierarchy or per-definition ACLs.
- [ ] Draft routes cannot initiate; publication resolves the correct tenant/participant/revision; editing creates a new revision rather than mutating the old one.
- [ ] Public identifiers never disclose SQL primary keys; simulate uniqueness conflicts safely.
- [ ] Embedded engine still runs without starting Ecto or PostgreSQL.
- [ ] Definition revisions and route records contain no provider credentials or private lease material; separate calls can pin different later configuration revisions without mutating the reusable definition.

## Manual verification

1. Run migrations and trusted bootstrap against a disposable development database.
2. Save a synthetic definition as draft, inspect its non-callable route, then publish and resolve it through Calls.
3. Restart the app and verify the revision and key remain usable.
4. Rotate and revoke a key; inspect redacted management output and database records without printing secret values.

## Scope boundaries

No room startup/token endpoints until prepared-call admission, no transcript/archive yet, no admin web UI, per-operation permission framework, HMAC payload signing, or reversible Vxpipe API keys.

## Completion and evidence

- [ ] Demonstrate the runnable outcome and every acceptance/failure check above.
- [ ] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [ ] Update this milestone, the index checkbox, relevant architecture/user docs, and
  implementation labnote with actual test/browser/integration evidence in the implementation commit.

Implementation evidence (partial, 2026-09-09): the new database-neutral
`vxpipe_calls` child owns credential/definition repository behaviours and tested
administration/definition workflows. Focused red-green evidence covers one-time
hash-only API-key issuance, explicit scopes, independent revocation, immutable
revision editing, tenant-isolated draft/publication routing, and publication
rejection for unsupported features. PostgreSQL adapters, restart evidence, and
operator CLI workflows remain, so no implementation checkbox is complete yet.

## Specification review

Reviewed independently by milestone_review_a on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Separated reusable revision metadata from per-call plan/credential resolution; excluded credentials and leases from revisions/routes; focused re-review approved.
This is specification evidence only; implementation and runtime verification remain unchecked.
