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
