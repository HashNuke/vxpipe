# Call Variables runtime

## Objective

Implement milestone 4 from the approved definition/runtime contracts: one room-scoped
CallVariables owner, generated agent tools and transient projections, private snapshot handoff,
and independently filtered public tool events.

## Baseline

The definition compiler already validates section schemas, relaxes `required` recursively for
incremental population, resolves supplied initial values, and pins per-participant read or
read+write grants. Runtime startup still rejects every non-empty Call Variables plan. There is no
mutable owner, read/update command, variable Action, transient model projection, archival port,
or call-level gateway tool-visibility policy.

The first checkpoint establishes serialized transaction semantics at the dedicated process
boundary: typed internal read/update commands plus redacted process state that validates trusted
room identity, participant grants, deadlines, revisions, encoded limits and the full merged
candidate. It returns only grant-safe results and keeps all failure paths non-mutating.

## Progress

- Added the focused process-boundary tests first and confirmed the expected red
  state: all five cases failed because `CallVariables` and its command modules did
  not exist yet. The test cases cover authorization without value leakage,
  missing-value reads, recursive merge/array replacement/null clearing, literal
  direct updates, revision conflicts, schema failure atomicity, deadlines, and
  encoded update bounds.
- Implemented the bounded commands and room-incarnation-owned GenServer. The focused
  suite is green with five tests. The full umbrella gates are also green: format,
  warnings-as-errors compilation, 142 Call Engine tests (one excluded), 46 Gateway
  tests (four excluded), 20 Console tests, and the unused-dependency check.
