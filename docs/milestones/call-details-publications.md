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

- [ ] Red-test publication projection and fake-clock reporting window with complete, delayed, prohibited and missing components.
- [ ] Implement Calls publication state/workers outside room lifecycle with persistence/artifact ports.
- [ ] Store immutable publication records, timestamp filenames/checksums and nonregressing latest reference with collision handling.
- [ ] Integrate late usage/artifact/history observations as refreshed immutable publications.
- [ ] Add authorized operator retrieval and document incompleteness/available evidence without exposing private data to ordinary clients.

## Acceptance and failure checks

- [ ] Early complete versus 60-second incomplete publication; no change to ended_at/duration/retention and pending jobs are not cancelled.
- [ ] Timestamp 2026-09-08T12:34:56.789Z yields details-20260908123456789.json; retries reuse it, corrected contents get a new record/object.
- [ ] Simultaneous timestamp collision cannot overwrite or deduplicate distinct publications; late older completion cannot regress latest pointer.
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

Implementation evidence: none yet. Do not mark this slice complete because its specification
has been reviewed.

## Specification review

Reviewed independently by milestone_review_a on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Approved initial draft; clarified lifecycle/direction/route/plan digest in publication contents.
This is specification evidence only; implementation and runtime verification remain unchecked.
