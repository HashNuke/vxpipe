# Asynchronous call history and variable snapshots

Status: not implemented. Specification review: approved (2026-09-08).
Prerequisites: [Prepared admission](prepared-call-admission.md); [Background tools](background-tool-conversation.md).
Sources: [Incremental facts](../../labnotes/20260905-0405-call-definition-design.md#persist-facts-incrementally-and-derive-the-transcript); [variable snapshots](../../labnotes/20260905-0405-call-definition-design.md#variable-history-snapshots-and-the-latest-pointer--approved-g5-decision); [asynchronous consistency](../../labnotes/20260905-0405-call-definition-design.md#persistence-consistency-levels).

## Runnable outcome

An authorized operator inspects a completed call's transcript, tool history and variable snapshots through Calls. During a simulated database outage, live conversation and local variable updates continue; after recovery, retained queued facts are projected without duplicate history or a regressed latest snapshot.

## Specification

- Add protocol-neutral private room-event subscriptions and a bounded room-scoped EctoStorage subscriber; adapters perform SQL outside RoomAuthority, model/media callbacks, and CallVariables. Calls owns archive workflows, persistence owns schemas/queries/transactions. Subscriber drain/finalization can outlive room shutdown.
- Publish actual accepted-input text facts, final transcription and delivered/generated/interrupted output distinctions; current text start/completion events alone cannot reconstruct user text. Record stable event/operation IDs, occurrence time, call/tenant/incarnation, participant/activation, turn/tool and sequence/provenance where meaningful. Do not invent playback confirmation.
- Archive all observed permitted call lifecycle, turn/tool arguments/results/errors, variables snapshots, and available usage metadata. No tool-history toggle and no coupling to public hidden/metadata/full projections. Exclude credentials/auth headers and forbidden transcript/audio-derived content before subscriber/queue handoff and again at delayed sinks.
- CallVariables emits each exact full accepted snapshot with originating turn/tool and revision, not a later read of live state. EctoStorage atomically inserts a snapshot and conditionally advances calls.latest_variables_snapshot_id. Deduplicate deliveries; older valid history can persist without advancing latest. Initial values have a baseline without fake turn/tool.
- Local reads/update success never wait for SQL; transaction failure rolls back storage attempt only. Bounded queues, explicit lag/loss/error evidence, and documented overflow handling cannot backpressure media or stop a room. In-memory handoff is not durability; process/host loss may lose queued facts.
- Retain source-interval policy provenance so later relaxed policy cannot save previously denied data. First support base policy; later presence changes use the same enforcement boundary. No independent S3 history backup or automatic repair guarantee follows from this subscriber.

## Implementation checklist

- [ ] Red-test immutable event capture, private projection, async snapshot transactions, duplicate/out-of-order delivery, and storage failures.
- [ ] Add missing accepted text and lifecycle facts at the owning engine boundaries with bounded subscriber delivery.
- [ ] Implement EctoStorage through archive ports, exact snapshot histories/latest pointer, and tenant-scoped Calls read projections.
- [ ] Implement bounded shutdown/draining and honest incomplete/lag indicators; document the selected internal overflow behavior without adding a durable queue dependency.
- [ ] Carry policy/retention coordination metadata needed by later recording/publication/cleanup without implementing those features early.

## Acceptance and failure checks

- [ ] Stop/delay PostgreSQL after admission: room speech, tools and variables continue without SQL waits; resume only retained facts, with no lossless claim.
- [ ] Reorder/duplicate snapshots: correct history and latest pointer, no cross-call reference or rollback of newer local state.
- [ ] Hidden tool calls still have permitted private args/results; no secrets or denied transcripts enter queues, logs or archives.
- [ ] Compare typed input, final STT, generated output and actual delivery/interruption facts; preserve modality/source distinctions.
- [ ] End room while storage work drains; no ordinary history depends on a live room PID. Simulated process loss is reported as unavailable/incomplete data, not invented history.
- [ ] Crash EctoStorage and saturate its bounded queue: room/variables continue, no accepted update becomes a database failure, and retained/lost facts are distinguished.
- [ ] Rejected updates create no successful snapshot; late baseline, wrong call/incarnation, and stale delivery cannot corrupt or regress latest state.
- [ ] Bounded draining never treats the later publication reporting window as cancellation of pending archive/upload work or proof of successful completion after loss.

## Manual verification

1. Complete a call with a variable update and background tool; inspect its authorized Calls history projection.
2. Pause the development database after another call starts, continue talking and updating variables, then restore it.
3. Compare live/latest persisted revisions and inspect duplicate delivery handling.
4. Disable transcript storage for a supported interval/fixture and inspect the subscriber boundary—not just the final query—for absence of forbidden text.

## Scope boundaries

No SQS/Oban dependency, synchronous runtime writes, automatic post-incident repair, unbounded mailboxes, or full-room replay. Audio bytes arrive only with the recording milestone; do not duplicate them into PostgreSQL.

## Completion and evidence

- [ ] Demonstrate the runnable outcome and every acceptance/failure check above.
- [ ] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [ ] Update this milestone, the index checkbox, relevant architecture/user docs, and
  implementation labnote with actual test/browser/integration evidence in the implementation commit.

Implementation evidence: none yet. Do not mark this slice complete because its specification
has been reviewed.

## Specification review

Reviewed independently by milestone_review_c on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Added subscriber crash/saturation isolation, rejected/stale baseline snapshot cases and honest draining; re-review approved.
This is specification evidence only; implementation and runtime verification remain unchecked.
