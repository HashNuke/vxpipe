# Asynchronous call history and variable snapshots

Status: complete (2026-09-09). Specification review: approved (2026-09-08).
Forward-runtime note (2026-09-10): the [ReqLLM agent-runtime milestone](reqllm-agent-runtime.md)
must preserve this slice's archived model/tool/usage facts and attribution while replacing
the Jido-backed inference mechanism recorded in its implementation evidence.
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

- [x] Red-test immutable event capture, private projection, async snapshot transactions, duplicate/out-of-order delivery, and storage failures.
- [x] Add missing accepted text and lifecycle facts at the owning engine boundaries with bounded subscriber delivery.
- [x] Implement EctoStorage through archive ports, exact snapshot histories/latest pointer, and tenant-scoped Calls read projections.
- [x] Implement bounded shutdown/draining and honest incomplete/lag indicators; document the selected internal overflow behavior without adding a durable queue dependency.
- [x] Carry policy/retention coordination metadata needed by later recording/publication/cleanup without implementing those features early.

### RoomAuthority responsibility-split checkpoint

Complete this checkpoint before the private room-fact implementation is considered
finished. It is a structural gate for this milestone, not deferred cleanup:

- [x] Introduce an explicit `RoomAuthority.State` struct that names the state owned
  by the serializer and prevents extracted modules from depending on an anonymous,
  open-ended map.
- [x] Keep `RoomAuthority` as the single GenServer/callback router and room-level
  serialization boundary; do not add another competing authority process or change
  the supervision topology merely to split source files.
- [x] Move private fact construction, credential removal, archive sequencing, and
  bounded handoff into a cohesive archive recorder. Room callbacks may report an
  authoritative occurrence, but must not assemble persistence envelopes.
- [x] Extract participant admission/removal and connection attach/detach/STT-binding
  lifecycle into cohesive modules with explicit inputs and returned state.
- [x] Extract typed/audio input-turn normalization and accepted-input dispatch from
  agent output/TTS handling; neither module may own the other's callback family.
- [x] Extract active/background tool-call transitions from agent text/audio output
  and interruption transitions.
- [x] Leave authorization and ordering decisions at one clearly named owning
  boundary. Avoid cyclic synchronous process calls and do not let extracted modules
  reach through another umbrella application's private implementation.
- [x] Run the existing participant, text, audio, TTS, tool, definition-driven call,
  and archive suites during each extraction. Add focused tests only where an
  extracted project-owned contract is not already characterized.
- [x] Finish with no callback-family implementation merely copied into another
  catch-all module: each extracted module must have one cohesive reason to change,
  and `RoomAuthority` must read as orchestration rather than the implementation of
  every room concern.
- [x] Make the repository Credo gate green. The checked-in profile includes an
  800-line emergency ceiling for module files; this is a regression backstop, not
  proof of SRP or a substitute for the responsibility checks above.

## Acceptance and failure checks

- [x] Stop/delay PostgreSQL after admission: room speech, tools and variables continue without SQL waits; resume only retained facts, with no lossless claim.
- [x] Reorder/duplicate snapshots: correct history and latest pointer, no cross-call reference or rollback of newer local state.
- [x] Hidden tool calls still have permitted private args/results; no secrets or denied transcripts enter queues, logs or archives.
- [x] Compare typed input, final STT, generated output and actual delivery/interruption facts; preserve modality/source distinctions.
- [x] End room while storage work drains; no ordinary history depends on a live room PID. Simulated process loss is reported as unavailable/incomplete data, not invented history.
- [x] Crash EctoStorage and saturate its bounded queue: room/variables continue, no accepted update becomes a database failure, and retained/lost facts are distinguished.
- [x] Rejected updates create no successful snapshot; late baseline, wrong call/incarnation, and stale delivery cannot corrupt or regress latest state.
- [x] Bounded draining never treats the later publication reporting window as cancellation of pending archive/upload work or proof of successful completion after loss.

## Manual verification

1. Complete a call with a variable update and background tool; inspect its authorized Calls history projection.
2. Pause the development database after another call starts, continue talking and updating variables, then restore it.
3. Compare live/latest persisted revisions and inspect duplicate delivery handling.
4. Disable transcript storage for a supported interval/fixture and inspect the subscriber boundary—not just the final query—for absence of forbidden text.

## Scope boundaries

No SQS/Oban dependency, synchronous runtime writes, automatic post-incident repair, unbounded mailboxes, or full-room replay. Audio bytes arrive only with the recording milestone; do not duplicate them into PostgreSQL.

## Completion and evidence

- [x] Demonstrate the runnable outcome and every acceptance/failure check above.
- [x] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [x] Update this milestone, the index checkbox, relevant architecture/user docs, and
  implementation labnote with actual test/browser/integration evidence in the implementation commit.

Implementation checkpoint 1 adds the database-neutral `ArchiveRepository` and Calls workflows
for private variable-snapshot writes and calls-scoped, tenant-bound reads. A new immutable
snapshot contract distinguishes unattributed revision-zero baselines from fully attributed
accepted updates and excludes its private sections from inspection.

The Ecto adapter and fourth migration store exact full snapshots, deduplicate identical
delivery, reject conflicting identities/revisions and wrong call incarnations, and update
`calls.latest_variables_snapshot_id` in the same transaction only when the incoming global
revision is newer. Archival JSON is canonicalized before identity/deduplication comparisons.
Older and late-baseline facts remain queryable history without regressing that pointer.
Focused red evidence was 11 call-store tests with 2 expected failures at the missing
snapshot/archive APIs, followed by one focused JSON-canonicalization failure. Green evidence
is 20 Calls and 19 persistence tests, plus an empty-database four-migration run and 11 focused
adapter tests, all with 0 failures. Runtime subscriber wiring and non-variable call facts
remain open, so no implementation checklist or acceptance box is complete yet.

Implementation checkpoint 2 adds the bounded live-to-storage path for Call Variables. An
engine-owned global supervisor creates one temporary subscriber per durable room. Its handoff
uses atomics to reserve a fixed number of facts and a non-suspending message send; capacity
includes both the active sequential writer task and queued facts. A full queue drops the newest
offer while the local update remains successful. Retained failures retry without consuming a
second slot. The subscriber monitors the room-incarnation supervisor, drains independently
after that tree exits, and terminates an outstanding writer at the configured drain deadline.
Overflow, unavailable, retry, pending, discard and incomplete evidence remain distinct. A
crashed subscriber is intentionally not restarted behind the stale handoff.

`CallVariables` now emits an exact unattributed baseline before serving commands and gives both
baseline and update facts stable snapshot/call/room/incarnation identity plus source-policy
provenance. `EctoStorage` maps those facts to the Calls workflow added in checkpoint 1. The
database-backed Gateway admission configuration enables a 256-fact queue, 250 ms retry delay,
and five-second final drain; legacy trusted rooms remain unarchived. Red evidence included 3
missing-subscriber failures, a missing-baseline compile failure, a room-wiring baseline timeout,
and a missing-EctoStorage failure. Focused engine, persistence, and Gateway suites passed. The
full umbrella rerun passed with Call Engine 170, Calls 20, Persistence 21, Gateway 66, and
Console 25 tests (0 failures; 6 integration exclusions). An initial full run hit the existing
real-Jido coordinator's two-second timeout under load; that exact test passed with the same seed
and the complete rerun was green. Broader lifecycle/turn/transcript/tool/usage facts and durable
incomplete projections remain open, so the milestone is not complete.

Implementation checkpoints 3–5 first split the roughly 1,800-line `RoomAuthority`
into cohesive state, startup, participant, connection, input, output, tool, turn,
event-publication and archive modules while retaining one GenServer serialization
boundary. Credo is now a required repository gate, with a focused profile and an
800-line emergency module ceiling as a regression backstop rather than an SRP
substitute.

The engine now publishes ordered private facts for the lifecycle, typed and audio
input, final STT, generated and delivered/interrupted output, and tool transitions
it actually observes. The base source policy removes transcript content before
handoff when `save_transcripts` is false. Calls performs a second credential and
source-policy check, persists append-only facts through the fifth migration, and
returns tenant/scopes-authorized transcript, tool, variable and underlying fact
projections.

After ordinary retained facts drain, the bounded subscriber attempts a private
`archive_stream_closed` marker containing overflow/unavailable/discard/retry and
source-exit evidence. History is `complete` only with a loss-free terminal marker
and contiguous private sequence, `incomplete` with a marker plus known loss/gaps,
and `unconfirmed` without durable closure. Failed marker storage therefore never
becomes invented completion. Missing-sequence samples are capped while their total
count remains exact. A database-backed integration exercised the actual subscriber,
Ecto transaction, closure, and authorized history against an empty, disposable
PostgreSQL cluster. Presence-driven media policy, recording, retention cleanup and
public inspection remain later milestones.

The final acceptance checkpoint drives a definition-based Jido tool conversation and
a Call Variables update while the injected archive adapter repeatedly raises. Public
tool/output/turn events and local variable reads remain responsive; the bounded handoff
reports retained work and retries. After recovery, the room is stopped and the subscriber
drains to an explicit closure. Every retained snapshot/fact ID is written once, including
accepted input, tool completion and the variable update. A persistence-owned companion
test runs an engine fact through `EctoStorage` while its repository raises, then proves
retry, recovery, ordered storage and clean closure. Real Ecto migration, transaction,
deduplication and latest-pointer behavior remain covered against PostgreSQL separately.

The queue-saturation test proves newest-item loss does not change locally accepted Call
Variables, and the closure tests distinguish that known loss from a clean drain. The drain
deadline owns only the archive subscriber and its current writer task; it neither creates
nor controls the later call-details publication window. A timed-out/failed closure therefore
leaves history unconfirmed rather than claiming completion or cancelling unrelated future
publication/upload work.

Final root verification passed `mix format --check-formatted`, `mix credo --strict`
(239 source files, no issues), `mix compile --warnings-as-errors`, `mix test`, and
`mix deps.unlock --check-unused`. The 317-test umbrella run passed with Call Engine 179,
Calls 24, Persistence 23, Gateway 66, and Console 25 tests; six network/provider
integration cases remained explicitly excluded. The database was a disposable PostgreSQL
18 cluster created empty, migrated through all five migrations, and removed afterward.

Pre-delivery review checkpoint (2026-09-12): a browser hangup exposed that the engine emitted its
terminal archive fact but Ecto could not apply its millisecond timestamp directly to the
microsecond-precision `calls.ended_at` field. The writer retried until the bounded drain expired,
correctly leaving history unconfirmed but incorrectly preventing an ordinary call from reaching its
durable ended state. A persistence-owned integration now drives a real agent hangup through Call
Engine, the bounded subscriber and EctoStorage. The terminal projection normalizes the valid engine
timestamp at the database boundary; the test proves clean subscriber drain, a stored closure and an
atomically ended call with six-digit timestamp precision. The repeat rendered-browser flow stored
the terminal fact as sequence 14 and marked the exact Gemini-backed sample call `ended`, confirming
the fix outside the deterministic test boundary.

## Specification review

Reviewed independently by milestone_review_c on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Added subscriber crash/saturation isolation, rejected/stale baseline snapshot cases and honest draining; re-review approved.
This is specification evidence only; implementation and runtime verification remain unchecked.
