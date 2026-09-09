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
3. Add the missing private accepted-input/lifecycle facts and archive all permitted
   turn, transcript, output, tool, interruption, and available usage facts without
   coupling them to client visibility.
4. Add tenant-authorized Calls history projections and incomplete/lag indicators,
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
