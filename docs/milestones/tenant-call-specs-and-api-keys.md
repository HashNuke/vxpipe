# Tenant Call Specs and API-Key Administration

Status: complete (2026-09-09). Specification review: approved (2026-09-08).
Prerequisites: [Call-Spec-driven call](call-spec-driven-call.md).
Sources: [Admission credentials](../../labnotes/20260905-0405-call-definition-design.md#initial-variables-and-api-key-admission--approved-g2-decisions); [routes](../../labnotes/20260905-0405-call-definition-design.md#web-participant-admission-routes--approved-g2-routing); [application boundaries](../../labnotes/20260905-0405-call-definition-design.md#umbrella-application-and-ecto-boundaries).

## Runnable outcome

An operator bootstraps a tenant/API key through trusted OTP/CLI administration, saves and publishes a call spec, and reads it back after restart. Draft call specs remain unavailable for call initiation; publication makes a tenant-scoped participant route resolvable.

## Specification

- Add database-neutral call spec/deployment and credential repository ports, Calls application workflows, and a separate Ecto-owning persistence application. Gateway authenticates through a port; engine/gateway never own Repo queries. Add dependencies only to their owning child.
- Store immutable call spec revisions and validated/compiled reusable metadata. Resolve and pin each call's actual plan at preparation/admission using the then-selected tenant profiles/integrations/catalogs; private credential leases are not reusable persisted call spec state. Draft saving can allocate route metadata but only explicit publish/enable exposes it. Route keys live in deployment metadata, not portable JSON; resolution is indexed rather than scanning call specs.
- Public tenant keys are 16 unpadded-base64url characters from 12 random bytes; participant route keys are UUIDs; future public call IDs are UUIDs. Enforce uniqueness separately from internal SQL primary keys.
- Generate high-entropy tenant-bound API keys once, persist only one-way digest plus metadata. Never return stored digests as credentials or retrieve lost plaintext. Bootstrap needs no preexisting key; lost keys require replacement.
- Support independent admin/calls scopes and multiple independently revocable keys without assuming admin implies calls. Key revocation stops further authentication, not already-issued tokens or established sessions. API-key management starts with authorized OTP/CLI; an admin HTTP API is not implied.
- Keep recoverable upstream provider/MCP secrets separate from hash-only Vxpipe keys. Initial administration can reference existing runtime secret stores; encrypted DB storage, if introduced, has a key outside the DB.

## Implementation checklist

- [x] Write red repository/workflow tests for immutable revisions, draft/publication routing, tenant isolation, IDs, key issuance/verification/revocation.
- [x] Introduce Calls ports and Ecto schemas/migrations/constraints in the correct applications with no reverse engine dependency.
- [x] Implement trusted OTP/CLI tenant and first-key bootstrap plus authorized key rotation/revocation.
- [x] Implement save/publish/read call spec workflows through ports and record supported-feature errors before publication.
- [x] Document migration/bootstrap commands and safe one-time key handling without committing actual credentials.

## Acceptance and failure checks

- [x] Restart configured persistence/authentication: the original key verifies, but its stored digest, a wrong key, or another tenant's key does not.
- [x] Revoke one of two keys: the other remains valid; no new dependency from existing tokens/sessions to the revoked key.
- [x] Admin-only versus calls-only checks use explicit grants, not implicit hierarchy or per-call-spec ACLs.
- [x] Draft routes cannot initiate; publication resolves the correct tenant/participant/revision; editing creates a new revision rather than mutating the old one.
- [x] Public identifiers never disclose SQL primary keys; simulate uniqueness conflicts safely.
- [x] Embedded engine still runs without starting Ecto or PostgreSQL.
- [x] Call Spec revisions and route records contain no provider credentials or private lease material; separate calls can pin different later configuration revisions without mutating the reusable call spec.

## Manual verification

1. Run migrations and trusted bootstrap against a disposable development database.
2. Save a synthetic call spec as draft, inspect its non-callable route, then publish and resolve it through Calls.
3. Restart the app and verify the revision and key remain usable.
4. Rotate and revoke a key; inspect redacted management output and database records without printing secret values.

## Scope boundaries

No room startup/token endpoints until prepared-call admission, no transcript/archive yet, no admin web UI, per-operation permission framework, HMAC payload signing, or reversible Vxpipe API keys.

## Completion and evidence

- [x] Demonstrate the runnable outcome and every acceptance/failure check above.
- [x] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [x] Update this milestone, the index checkbox, relevant architecture/user docs, and
  implementation labnote with actual test/browser/integration evidence in the implementation commit.

Implementation evidence (2026-09-09): the new database-neutral
`vxpipe_calls` child owns credential/call spec repository behaviours and tested
administration/call spec workflows. The separate `vxpipe_persistence` child now
owns its Repo, five control-plane tables, constraints, transactions, and both
Ecto port adapters. Focused red-green evidence covers one-time
hash-only API-key issuance, explicit scopes, independent revocation, immutable
revision editing, tenant-isolated draft/publication routing, and publication
rejection for unsupported features. `mix test apps/vxpipe_calls/test` passes 7
tests; `mix test apps/vxpipe_persistence/test` passes 8 tests, including a real
Repo restart. `mix deps.unlock --check-unused` passes. Running `mix test` from
the `vxpipe_call_engine` child passes 164 tests (2 excluded) without starting
Ecto or PostgreSQL.

The trusted operator suite passes 2 command-flow tests and covers tenant
bootstrap, key rotation/revocation, and call spec save/publish/show while
capturing the one-time key. A separate disposable PostgreSQL run executed those
documented commands across fresh BEAM invocations, authenticated before and
after key revocation, proved draft versus published route resolution, read the
call spec after restart, and removed the disposable database without printing
keys or digests. Final umbrella gates passed: formatted, warnings-as-errors
compile, 164 Call Engine tests (2 excluded), 7 Calls tests, 8 Persistence tests,
52 Gateway tests (4 excluded), 20 Console tests, and no unused dependencies.
No sample UI changed, so browser inspection was not applicable to this slice.

## Specification review

Reviewed independently by milestone_review_a on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Separated reusable revision metadata from per-call plan/credential resolution; excluded credentials and leases from revisions/routes; focused re-review approved.
The review remains specification evidence; the separate implementation evidence
above now establishes the completed runtime slice.
