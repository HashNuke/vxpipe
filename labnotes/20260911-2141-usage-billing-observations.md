# Usage and billing observations

## 2026-09-11: first checkpoint scope

Milestone 20 starts with a provider-neutral typed observation and settlement boundary in Call
Engine. The existing agent runtime already preserves bounded raw model usage and provider metadata,
but Call Engine does not yet translate its usage event. Hosted speech, tools, and carrier adapters
also do not share one typed contract.

The first red test specifies separate value objects for attribution, provider context, one measured
component, one call-scoped observation, and derived effective amounts. A settlement groups by
provider attempt, component, unit/currency, provenance, and honest attribution. It deduplicates only
a repeated delivery identity; equal independent deltas remain distinct. Cumulative ordering uses
source sequence, while final and correction status are independent from delta/cumulative mode.
Included subcategories remain inspectable without being added to their declared aggregate.

The focused test first ran with five failures because none of the typed usage modules existed. This
was the expected red state; the failures occurred at the new public constructors rather than in
unrelated runtime setup.

## 2026-09-11: typed contract green

Call Engine now owns small typed values for attribution, provider context, measurement,
observation, and effective amount. The public settlement module delegates replay detection,
amount derivation, and component-inclusion validation to separate modules so those policies have
independent reasons to change. The largest implementation module in this checkpoint is the
focused amount reducer rather than a combined validation/aggregation/logging module.

Counts use non-negative integers in canonical token, character, millisecond, or request units.
Money uses a currency tuple and an exact `Decimal` parsed from a plain decimal string; floats are
rejected. The owning application now declares `decimal` directly instead of relying on a
transitive dependency. Totals do not cross provenance unless the caller selects a provenance.
This keeps a library estimate from being silently added to provider-reported cost.

Replay detection needed a second red/green pass. A delivery can be proven by stable observation
ID, transport delivery ID, or source sequence, so the implementation checks all three rather than
choosing just one. Equal values with no shared identity still add. Reusing an identity for
different semantic content is rejected as conflicting evidence.

Verification so far:

- Focused red: five missing-contract failures, followed by two deliberate replay/provenance
  failures after expanding the contract.
- Focused green: 6 tests, 0 failures.
- Call Engine: 363 tests, 0 failures, 1 existing integration exclusion.
- Strict Credo: 671 source files, no issues.
- Umbrella: formatting, warnings-as-errors compilation, all 851 tests across eight apps, and the
  unused-dependency check pass.

No adapter capture, persistence, operator projection, or billing lookup has been implemented yet.

## 2026-09-11: completed model-round capture

The next red/green pass exposed four separate boundaries rather than putting translation,
correlation, authorization, and serialization into the coordinator or room process:

- `ModelProjection` accepts only non-negative integer input/output/total token evidence and safe
  provider identity. Arbitrary metadata and ambiguous floating-point cost fields do not cross the
  boundary.
- `UsageRounds` tracks each Agent Runtime request until its terminal event. This is intentionally
  separate from the coordinator's current task because usage and task-result messages have
  different senders and may reach the mailbox in either order.
- `UsageObservations` authenticates the emitting capability and pinned identities before changing
  the room's archive recorder.
- `ArchiveProjection` produces explicit JSON-safe private facts rather than relying on generic
  struct serialization.

An observation can now omit its measurement. This retains genuine request/session identity when a
provider returns no supported usage or price, and settlement then has no effective amount for that
operation. It reports the unit as unknown rather than inventing zero.

Each successful model response creates one distinct attempt per model round, including intermediate
tool rounds. Input and output tokens are marked as included in total tokens only when total tokens
were actually supplied. Provider request/response/session IDs remain private; local attempt IDs are
never substituted for them. The room accepts the active agent capability and a source capability
awaiting teardown after a committed transfer so incurred usage is not lost solely because authority
has moved.

Red evidence:

- The measurement-less operation was rejected as `:invalid_observation`.
- The projector calls failed because no projector module existed.
- The first coordinator usage test failed startup because call/provider usage identity was not part
  of its configuration.
- The full-room test hit the missing `RoomAuthority.handle_info/2` clause and then timed out waiting
  for a private usage fact.

Focused green evidence so far:

- Settlement and projector: 9 tests, 0 failures.
- Coordinator: 20 tests, 0 failures, including two model rounds around an asynchronous tool.
- Definition-driven private archive case: 1 test, 0 failures.
- Activation supervisor: 5 tests, 0 failures.
- Formatting, warnings-as-errors compilation, and strict Credo over 676 source files pass.

The first complete Call Engine run found four direct activation-supervisor test fixtures that
bypassed call-plan startup and therefore lacked the new explicit call/provider usage identity.
Those fixtures now provide the same internal contract and their focused tests pass. The complete
Call Engine suite passes 369 tests with one existing integration exclusion. All 857 tests across
the eight umbrella apps pass, as do the formatting, warnings-as-errors compilation, strict Credo,
and unused-dependency gates. Failed/interrupted model attempt capture, hosted speech, tools,
carriers, operator totals, and billing lookup remain.
