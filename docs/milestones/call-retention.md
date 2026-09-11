# Whole-call retention and deletion

Status: not implemented. Specification review: approved (2026-09-08).
Prerequisites: [Call-details publications](call-details-publications.md), including all persisted history/artifact owners; [Embedded/container delivery](embedded-and-container-delivery.md). This is intentionally the final implementation milestone.
Sources: [Retention](../../labnotes/20260905-0405-call-definition-design.md#retention-periods--approved-application-and-tenant-policy); [R19–R21](../call-definition-gap-review.md).

## Runnable outcome

A periodic sweep removes an expired completed call's objects first, then all database data. Changing tenant/application retention affects already-ended calls too, while active and unstarted calls remain untouched.

## Specification

- call_retention is application/tenant configuration only: forever string or finite seconds object; application omission defaults forever, tenant omission inherits, explicit tenant value wins. No per-call period/version/fixed-expiry copy or new invocation override.
- Evaluate current policy against ended_at plus period on each sweep. Never use created_at, started_at, snapshot/publication/billing times as fallback. Active/unstarted/missing-ended_at calls are excluded; later writes do not reset retention.
- Select work periodically, not exact threshold timers. Choose/document a configurable deployment cadence at implementation; no preapproved hourly default or deletion SLA.
- Delete every managed call-owned external object/copy first: tracks, mixes, manifests, all publication revisions/derivatives and temporary owned uploads. Definitive not-found means absent; timeout/auth/network/unknown is not success. Keep DB references until all external objects are absent.
- Then delete all call-owned SQL data including call/plan copies, participant/leg/admission/token rows, events/transcripts/tools/usage, baseline/all/latest variables, artifacts/publications and jobs. No retained summary/tombstone/soft-delete/latest snapshot. Shared definitions/tenant config/reusable opening assets remain.
- Sweep failures retain existing records for retry; repeated missing-object deletion is safe. Coordinate existing publishers, recorders, billing/history workers and concurrent sweeps so no late writer can recreate deleted objects/rows. External-first ordering alone is not coordination; select/test a bounded implementation using existing ownership/records, not a new permanent journal/recovery feature.
- Internal cleanup retries are not tool/MCP retries. Only Vxpipe-managed copies are in scope; do not claim deletion of independent provider/client data.

## Implementation checklist

- [ ] Red-test retention resolution/current-policy changes, eligibility and external-first ordering with fake clock/storage.
- [ ] Implement bounded periodic sweep through Calls/Persistence/Artifacts boundaries and current tenant settings.
- [ ] Coordinate call-owned writers with deletion and repeated sweeps using existing records/ownership.
- [ ] Cover all call-owned tables/object prefixes and distinguish reusable assets.
- [ ] Document operational cadence, failures and manual verification without advertising instant deletion.

## Acceptance and failure checks

- [ ] App/tenant forever/inheritance/finite settings apply to old and new calls; policy extension cannot restore deleted data.
- [ ] Only ended_at starts age; active/unstarted/missing-ended_at and forever records remain, even with old created_at.
- [ ] Missing object permits progress; unknown/error retains DB references. Crash between external and DB deletion safely resumes next sweep.
- [ ] Concurrent late snapshot/billing/upload/publication and sweeps cannot resurrect rows/objects; DB failure retains retryable records.
- [ ] Every call-owned table/object/revision is absent after success, including latest pointers; shared definition/opening assets remain.
- [ ] Two tenants with different policies and adjacent/similar object keys remain isolated:
  sweep deletes only the eligible call. App policy edits affect inheriting tenants, not explicit overrides.

## Manual verification

1. Create ended, active and unstarted synthetic calls with recording/publication artifacts.
2. Set a short finite tenant retention and run the documented sweep; inspect external-before-DB deletion and exclusions.
3. Fail object deletion, retry with definitive not-found, then fail SQL cleanup and retry again.
4. Change retention for previously ended records and race a controlled late publication; confirm no resurrection or retained call summary.

## Scope boundaries

No per-call retention settings, prepared-record expiry, permanent tombstones, exact deletion SLA, provider-copy deletion promise, or separate reconciliation subsystem. Deferred redaction is not implemented by deleting expired calls.

## Completion and evidence

- [ ] Demonstrate the runnable outcome and every acceptance/failure check above.
- [ ] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [ ] Update this milestone, the index checkbox, relevant architecture/user docs, and
  implementation labnote with actual test/browser/integration evidence in the implementation commit.

Implementation evidence: none yet. Do not mark this slice complete because its specification
has been reviewed.

## Specification review

Reviewed independently by milestone_review_b on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Added tenant/call object deletion isolation and inherited vs explicit policy-change checks; re-review approved.
This is specification evidence only; implementation and runtime verification remain unchecked.
