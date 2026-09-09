# Asynchronous call history

## Objective

Implement milestone 8 so live call facts and exact Call Variables snapshots enter
bounded, non-blocking private archival handoffs, persist asynchronously through
Calls-owned workflows and persistence adapters, and remain honestly inspectable
after the room exits or storage temporarily fails.

## Starting point

- Milestone 7 leaves a durable call record and stable call/room/incarnation and
  participant identities before ordinary live history begins.
- `CallVariables` already sends one exact full `UpdateSnapshot` to an optional PID
  after an update is accepted, and ignores storage completion. It does not emit a
  baseline, include the call ID, bound the subscriber mailbox, or persist/query the
  snapshot.
- `RoomAuthority` sends protocol events only to the active client connection. The
  text start/completion pair omits accepted input content, and there is no private
  archive projection or lifecycle stream.
- `vxpipe_calls` has repository-neutral control-plane/admission workflows;
  `vxpipe_persistence` owns the Ecto Repo and current call row. Neither has archive
  models, ports, transactions, or history queries yet.

## Checkpoint plan

1. Red-test and add the Calls archive contract plus Ecto transactions for immutable
   baseline/update snapshots, deduplication, out-of-order history, and a conditional
   latest pointer.
2. Add a strictly bounded room-scoped subscriber handoff, asynchronous Ecto writer,
   outage/saturation evidence, and lifecycle that can drain after room shutdown.
3. Split `RoomAuthority` along its participant, connection, input-turn, agent-output,
   tool-call, and archive responsibilities while preserving one serialized authority
   process and the existing supervision topology. Use an explicit state struct and
   keep extracted modules cohesive rather than moving everything to another catch-all.
4. Add the missing private accepted-input/lifecycle facts and archive all permitted
   turn, transcript, output, tool, interruption, and available usage facts without
   coupling them to client visibility.
5. Add tenant-authorized Calls history projections and incomplete/lag indicators,
   then exercise the full completed-call/outage recovery slice and update durable
   documentation.

The initial slice will store exact snapshots synchronously only inside adapter
tests. Runtime use is not wired until the bounded subscriber owns that call; no
room or variable update will call SQL directly.

## Checkpoint 1: variable-snapshot archive transaction

The first red test added two real-adapter cases to the existing prepared-call
fixture. The focused run executed 11 tests and failed the two new cases at the
missing `VariableSnapshot` and Calls archive APIs, as expected.

The implemented foundation adds:

- an inspect-redacted immutable snapshot contract with distinct `baseline` and
  `update` attribution rules;
- a Calls-owned `ArchiveRepository` port and archive workflow, including
  `:calls` scope authorization and tenant-bound reads;
- a fourth migration for exact full snapshot history and a nullable latest-
  snapshot pointer on the call row;
- an Ecto transaction that locks the call, validates call/room/incarnation,
  inserts or deduplicates the immutable snapshot, and advances the latest pointer
  only for a higher global revision; and
- source-policy metadata on every row so later interval-aware privacy enforcement
  has a stable storage field rather than inferring policy at delayed write time.

Before committing, an additional contract test exposed that atom-key JSON maps
would be stored and reloaded with string keys, making a later identical delivery
appear different. The constructor now canonicalizes section values and source
policy through JSON before the immutable snapshot is assigned. That focused test
failed on the non-canonical value first and then passed; the adapter's duplicate
test remained green.

The adapter accepts history in any delivery order. A revision-two update may land
before revision one or the baseline; all three remain ordered in the read
projection while revision two remains latest. Repeating the identical snapshot
is idempotent. A different identity for the same call/incarnation/revision, a
wrong incarnation, or another call ID fails without changing history or the
pointer. If the lifecycle projection has not yet stored an incarnation, the first
trusted archive row establishes consistency for subsequent facts without setting
`started_at` itself.

Verification:

- Focused green: Calls 20 tests and persistence 19 tests, 0 failures.
- `mix format --check-formatted`, `mix compile --warnings-as-errors`, and
  `mix deps.unlock --check-unused` passed.
- A disposable empty PostgreSQL database migrated through all four migrations and
  ran the 11 focused call-store/archive tests with 0 failures, then was removed.

This checkpoint deliberately does not wire the adapter into a room. The next
checkpoint must add a strictly bounded non-blocking handoff and an asynchronous
writer before any accepted variable update can reach SQL in production.

## Checkpoint 2: bounded room-to-Ecto handoff

The first focused archive-subscriber run had three expected failures because the
archive supervisor and handoff did not exist. The next red cycles failed because
the revision-zero baseline contract was missing, the room did not pass/bind the
handoff, and `EctoStorage` did not exist.

The resulting runtime boundary has four parts:

- `Archive.Handoff` reserves a fixed capacity through atomics and sends facts with
  `:nosuspend`. The count covers the active writer and every queued fact. A full
  handoff rejects the newest fact, while an unavailable or closed subscriber is a
  separate outcome. Both are ignored by `CallVariables` after updating its local
  state, as required.
- `Archive.Subscriber` moves each write into the archive writer task supervisor,
  preserving sequential delivery without executing an adapter in a room process.
  It retries a retained fact in the same capacity slot and exposes accepted,
  pending, retry, overflow, unavailable, discarded, and incomplete counters.
- The global archive dynamic supervisor owns temporary subscribers outside room
  trees. Each subscriber monitors its room-incarnation supervisor. It drains after
  the room exits, or terminates the outstanding writer and counts all remaining
  facts discarded when its finite drain window expires. A subscriber crash is not
  restarted behind the stale handoff; subsequent offers report unavailable.
- `CallVariables` emits a full revision-zero baseline in `handle_continue/2` before
  accepting calls, then emits each exact accepted post-update snapshot. Both have
  stable snapshot/call/room/incarnation IDs and capture source policy at handoff
  time. Only updates carry real command, participant, activation, correlation, tool,
  section, and revision attribution.

`Vxpipe.Persistence.EctoStorage` implements the injected writer contract and maps
both engine fact types into the Calls archive workflow. Database-backed Gateway
admission enables it with 256 pending facts, a 250 ms retry delay, and a five-second
post-room drain. Trusted sample rooms do not enable it because they have no durable
call record.

Focused evidence covered:

- capacity saturation while the writer was blocked, with two accepted slots and a
  distinct newest-fact overflow;
- simulated database unavailability followed by a successful retry of the retained
  fact without double admission;
- subscriber crash isolation and unavailable subsequent offers;
- continued subscriber life after room-source exit until retained work drained;
- forced drain expiry, writer termination, and one honest discarded/incomplete fact;
- local variable success while the baseline occupied the only archive slot;
- exact baseline/update delivery through a definition-driven room; and
- the real asynchronous handoff through `EctoStorage`, its transaction, history,
  and latest pointer.

`mix format --check-formatted`, `mix compile --warnings-as-errors`, and
`mix deps.unlock --check-unused` passed. The first complete umbrella run encountered
an existing real-Jido coordinator test's two-second provider timeout under load;
the exact test passed with the same seed. A second complete run passed: Call Engine
170 tests (2 integration exclusions), Calls 20, Persistence 21, Gateway 66 (4
integration exclusions), and Console 25, all with zero failures.

This checkpoint does not yet archive room lifecycle, accepted text, transcript,
generated/delivered/interrupted output, tool, or usage facts. It also leaves the
handoff's incomplete evidence in memory; the later read-projection checkpoint must
persist and expose that evidence without pretending dropped facts can be recovered.

## Checkpoint 3: RoomAuthority responsibility split (complete)

The private-fact red/green cycle exposed an architectural problem before the work
was committed: `RoomAuthority` already combined participant lifecycle, connection
and STT lifecycle, input turns, agent output/TTS, tool transitions, interruptions,
and failure handling. Adding archive state and fact constructors there would deepen
that violation. The milestone now has an explicit responsibility-split gate with an
owned state struct, cohesive extraction list, unchanged process topology, and focused
regression suites. `Archive.Recorder` is the first extraction; it owns archive identity,
participant activation attribution, lifecycle/input/delivery fact construction, and
delegation to the low-level port.

Credo `1.7.19` was added as a root-only development/test quality dependency after
confirming the current Hex release. Running the stock strict profile produced many
pre-existing low-signal/style findings, so the checked-in profile establishes a
focused baseline instead of normalizing a permanently red gate. It checks unsafe
constructs, consistency, names, unused operations, generous complexity/nesting
ceilings, and a project-owned 800-line emergency module-size ceiling. The initial
strict run failed on the roughly 1,800-line `RoomAuthority`, making the split
observable; line count remains only a regression backstop and does not prove SRP.

The completed extraction leaves the original `RoomAuthority` process as the sole
GenServer and serialization boundary while reducing its module to 288 lines of API,
callback routing, initialization, and snapshot construction. Cohesive modules now
own startup, participant lifecycle, connection/STT attachment lifecycle, accepted
input turns, generated/spoken agent output and interruption, tool-call transitions,
turn state, client/archive event publication, and private archive recording. No new
process or cyclic synchronous call was introduced.

Verification after the extraction:

- `mix test` in `apps/vxpipe_call_engine`: 173 tests, 0 failures, 2 excluded
- `mix compile --warnings-as-errors` in `apps/vxpipe_call_engine`: passed
- `mix credo --strict` at the umbrella root: 233 source files, 0 issues
- `mix format --check-formatted`, umbrella compilation with warnings as errors,
  and `mix deps.unlock --check-unused`: passed
- umbrella-root `mix test`: blocked before test execution because this
  noninteractive shell had no PostgreSQL password; the error exposed no credential
  value and the database-backed suites were not represented as verified

The broader definition-driven test initially exposed a writer-boundary collision:
private facts queued ahead of a deliberately blocked variable-snapshot test writer.
The test writer now accepts private facts immediately under a separate observation
tag while retaining explicit acknowledgement control for variable snapshots. The
full call-engine suite then passed without changing the production handoff ordering.

## Checkpoint 4: private room facts (complete)

The first focused contract failed at compilation because `Archive.Fact` and
`Archive.Port` did not exist. The new port contract then passed and proves a
room-local monotonic archive sequence, inspect-redacted payloads, source-policy
capture, and recursive removal of authorization/API-key material before the
bounded handoff. The test uses a non-blocking collecting writer so writer
acknowledgement mechanics do not obscure fact construction.

The first room-boundary test subsequently timed out waiting for an archived
`agent_turn_completed` fact, as expected: `RoomAuthority` still only projected
events to its attached client. That red test covers configured participant and
room startup, attachment, exact accepted typed input, tool arguments/result,
generated output, and turn completion. It also requires the private archive
sequence to remain contiguous while retaining the separate public event sequence.

After the responsibility split, the client-event publishing boundary was changed
to project each supported event through `Archive.EventProjection`. The private
stream now distinguishes room/participant/connection lifecycle, typed accepted
input, provider-final transcription, generated output, playback start/progress/
completion, turn success/failure/interruption, and tool start/completion/failure/
cancellation. Archive-only accepted-input and delivered-output facts fill gaps
that the public protocol events cannot represent without inventing public events.

Two further focused red cycles found missing departure and interruption facts.
The participant/connection lifecycle owners now record authoritative departures,
including explicit detach command attribution or monitored-process reasons. The
agent-output owner now uses the shared publisher for interruption instead of
sending only to the client. The resulting definition-driven and agent-output
tests passed, including final STT, generated-versus-delivered speech, and exact
interrupter attribution.

Source policy is applied before the queue. For the currently supported base
policy, `save_transcripts: false` removes `content`/`text` from transcript-bearing
facts while retaining non-text lifecycle and delivery metadata. The focused test
first observed both forbidden strings in queued facts, then passed after the
policy projection was added. This does not implement presence-driven policy or
audio recording, which belong to the later media-policy and recording milestones.

## Checkpoint 5: durable facts, projections, and closure evidence

The Calls boundary now owns an immutable `CallFact`, repository-neutral fact
writes/reads, and an authorized `CallHistory` projection. Transcript facts,
complete tool history, exact variable-snapshot history/latest, and the underlying
ordered facts remain distinct. A fact without permitted text remains visible in
the ledger but is absent from the transcript projection. Calls repeats credential
and authorization-header removal after JSON canonicalization, including archived
source policy, so delayed/replayed input does not rely only on the engine check.

The fifth migration adds append-only `call_facts` rows with tenant-bound call
lookup, call/incarnation sequence uniqueness, stable public IDs, participant/
activation/connection/turn/tool attribution, source-policy provenance, and JSON
payloads. `ArchiveStore` inserts or idempotently deduplicates each fact in a
transaction, rejects conflicting IDs/sequences and wrong incarnations, and reads
in private-sequence order. `EctoStorage` maps engine facts through this Calls-owned
workflow instead of exposing Ecto to the engine.

The subscriber now writes an internal `archive_stream_closed` fact after every
retained ordinary item drains. It captures the final accepted/overflow/
unavailable/discarded/retry evidence and source termination reason. Closure work
does not consume a public handoff slot or inflate accepted counts, remains bounded
by the existing final drain deadline, and does not turn a failed closure write
into a false success. Calls reports:

- `complete` only when a terminal closure is present, reports no loss, and the
  private sequence has no gaps;
- `incomplete` when a persisted closure reports loss or sequence gaps; and
- `unconfirmed` when no durable closure exists, including subscriber/process loss
  before the final marker was stored.

Missing-sequence examples are capped at 100 while the exact count remains
available, avoiding an unbounded diagnostic projection. A queue-overflow test
proved that the marker reports known incomplete history; a clean source exit
proved complete closure. A database-backed integration stored exact snapshots and
an accepted-input fact through the bounded subscriber, drained after source exit,
persisted the closure, and returned a complete authorized history.

Final verification:

- Call Engine: 178 tests, 0 failures, 2 integration exclusions.
- Calls: 24 tests, 0 failures.
- Persistence: 22 tests, 0 failures; its 14-test call-store slice also passed
  independently against a disposable PostgreSQL 18 cluster migrated from an empty
  database through all five migrations.
- Gateway: 66 tests, 0 failures, 4 integration exclusions.
- Console: 25 tests, 0 failures.
- `mix credo --strict`: 239 source files, 2,330 modules/functions, no issues.
- `mix format --check-formatted`, `mix compile --warnings-as-errors`, and
  `mix deps.unlock --check-unused`: passed.

The first full-suite run exposed a 100 ms definition-driven test assertion racing
behind newly archived startup facts under umbrella load. The test already controlled
the writer and expected the correct update; only its receive bound was too short.
Changing that project-owned asynchronous bound to two seconds made the exact test
pass with the failing seed, and the complete umbrella rerun then passed all 315
tests. No production timing or queue behavior changed.

The final adapter review added one last red/green boundary check: an invalid room ID
produced a deterministic Ecto changeset failure but `EctoStorage` initially returned
`retry`. It now classifies `call_fact_insert_failed` as terminal and discards it once;
the subscriber's discard/incomplete evidence remains responsible for reporting that
loss. Database availability and transaction failures are still retryable.

The remaining milestone work is the broad outage/saturation acceptance audit and
final documentation/index completion. No lossless durability, S3 repair, audio
storage, presence-policy engine, retention sweep, or public history endpoint is
claimed by this checkpoint.
