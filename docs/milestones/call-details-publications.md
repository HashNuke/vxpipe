# Versioned call-details publications

Status: not implemented. Specification review: approved (2026-09-08).
Prerequisites: [Streaming recordings](streaming-recordings.md); [Usage/billing observations](usage-and-billing-observations.md).
Sources: [CallDetailsPublisher](../../labnotes/20260905-0405-call-definition-design.md#calldetailspublisher-is-a-final-projector-not-the-live-recorder); [R42/R43](../call-definition-gap-review.md).

## Runnable outcome

After a call ends, an authorized operator gets a call-details JSON object with transcript provenance, tool/transfer/variable history, usage and recording references. Late facts produce a new immutable publication without overwriting the prior object.

## Specification

- Calls owns final publication workflow; persistence supplies permitted recorded facts; artifacts writes objects/checksums/manifests. CallDetailsPublisher is a final projector, not recorder, live variable owner or model summarizer.
- Use a configurable 60-second reporting window from actual call end. Publish early if expected work settles; otherwise publish available permitted facts with explicit pending/failed/missing components. Prohibited/unconfigured/not-produced media differs from accidental missing data; unknown cost is not zero.
- The reporting window neither keeps room alive, changes ended_at/retention, nor cancels uploads or billing/history work. If DB/object storage prevents publication, report pending/failure and retain/retry surviving publication work, never claim published because the window expired.
- Each immutable publication has its own identity and persisted UTC record timestamp. Under a call-owned prefix use details-YYYYMMDDHHMMSSmmm.json, exactly three millisecond digits. Same snapshot retry reuses record/identity/content/filename; changed content creates a new revision/object, not a schema_version change for values alone.
- Keep latest-publication pointer while retaining prior revisions. Timestamp is not identity/uniqueness proof: detect filename collisions before clobbering, use safe object-write semantics, never invent a timestamp or overwrite another revision. Record checksums/completeness and protected access references, not bearer URLs in logs.
- Include pinned call/definition identity, participants/legs/activations, ordered observed transcript and delivery/interruption provenance, tool/transfer summaries, effective usage plus source observations, permitted variables/latest persisted snapshot and artifact references. Do not invent lost queued facts or claim an independent history backup from an export sourced from PG.
- Preserve privacy by source interval and call-owned deletion coordination; late enrichments must not recreate purged data. Future repair/export import is operationally deferred, not a replay feature.

Publication identity/details explicitly include lifecycle timestamps/status, direction, route,
definition revision and resolved-plan digest, not only a generic call identifier.

## Implementation checklist

- [x] Red-test publication projection and fake-clock reporting window with complete, delayed, prohibited and missing components.
- [x] Implement Calls publication state/workers outside room lifecycle with persistence/artifact ports.
- [x] Store immutable publication records, timestamp filenames/checksums and nonregressing latest reference with collision handling.
- [ ] Integrate late usage/artifact/history observations as refreshed immutable publications.
- [ ] Add authorized operator retrieval and document incompleteness/available evidence without exposing private data to ordinary clients.

## Acceptance and failure checks

- [ ] Early complete versus 60-second incomplete publication; no change to ended_at/duration/retention and pending jobs are not cancelled.
- [x] Timestamp 2026-09-08T12:34:56.789Z yields details-20260908123456789.json; retries reuse it, corrected contents get a new record/object.
- [x] Simultaneous timestamp collision cannot overwrite or deduplicate distinct publications; late older completion cannot regress latest pointer.
- [ ] Outage/build/upload failure never reports published/complete or erases underlying history; artifact acceptance isn't remote hearing.
- [ ] Denied transcript/audio intervals remain absent in exports; missing queued observations remain honest, and late publication respects deletion coordination.

## Manual verification

1. End a call containing a tool update, transfer, usage and recording; retrieve its private details JSON.
2. Hold one artifact/billing result past a short configured reporting window and inspect explicit pending state.
3. Release it and compare immutable revision objects/latest pointer/checksums.
4. Retry a publication and inject collision/storage failure; inspect no overwrites or false completion.

## Scope boundaries

No automatic post-call LLM summary/evaluation, cross-store atomic transaction, guaranteed disaster recovery/import, runtime call replay, or timestamp-as-unique-ID assumption. Retention cleanup follows next.

## Completion and evidence

- [ ] Demonstrate the runnable outcome and every acceptance/failure check above.
- [ ] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [ ] Update this milestone, the index checkbox, relevant architecture/user docs, and
  implementation labnote with actual test/browser/integration evidence in the implementation commit.

Implementation evidence:

- Checkpoint A implements Calls-owned, database-neutral component states, a fake-clock reporting
  window, validated permitted source data, canonical JSON snapshots, content/source SHA-256
  digests, and exact millisecond filenames. Focused tests prove early settled publication,
  pre-deadline waiting, deadline publication, intentional absence versus missing/failure, UTC
  record timestamps, and stable bytes independent of map insertion order. Persistence,
  object-store publication, late refresh, and operator retrieval remain pending.
- Checkpoint B adds a Calls-owned publication record/receipt contract and a PostgreSQL adapter.
  Per-call transactions reserve exact canonical bytes, deduplicate by schema-aware source digest,
  reject distinct revisions that collide on the timestamp filename, and retain both pending and
  published revisions. The latest pointer advances only after a protected object receipt commits
  and cannot regress when an older revision completes later. Concurrent collision, idempotent and
  conflicting receipt, tenant isolation, non-terminal call, and call-owned cascade tests pass.
- Checkpoint C1 adds the Artifacts implementation of the Calls-owned write port. It writes exact
  JSON bytes below an encoded call-owned prefix with conditional create semantics, stores the
  SHA-256 checksum as object metadata, verifies an existing object's checksum before treating a
  retry as successful, and rejects same-key/different-content collisions. Returned references
  contain only the protected object key and optional ETag; bearer URLs are never retained.
- Checkpoint C2a adds the Calls-owned supervision and execution boundary. A unique registry
  coalesces concurrent submissions of the same tenant/call/source digest, while short-lived workers
  perform reserve, immutable write, and receipt commit in bounded supervised attempts outside room
  lifetime. Successful and already-published paths stop normally; timeouts and storage failures
  retry only to the configured limit and leave a reserved revision pending on exhaustion.
- Checkpoint C2b adds bounded oldest-first pending-row discovery and a periodic Calls-owned recovery
  child that resumes exact persisted revisions without rebuilding or reserving them. The persistence
  application can supervise recovery after its Repo through explicit OTP settings and injects its
  own repository adapter. Failed scans remain observable and retry later without crashing the room
  or claiming delivery.

## Specification review

Reviewed independently by milestone_review_a on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Approved initial draft; clarified lifecycle/direction/route/plan digest in publication contents.
This is specification evidence only; implementation and runtime verification remain unchecked.
