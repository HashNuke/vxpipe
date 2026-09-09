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
- Removed the startup rejection for non-empty Call Variables and placed the owner
  beside RoomAuthority under the room-incarnation supervisor. It is a significant,
  temporary child: loss of authoritative variable state ends the incarnation instead
  of silently restarting with initial values. A focused integration test suspends
  RoomAuthority and confirms variable reads still complete.
- Added a private, non-blocking archival port. Each accepted update sends an exact
  full snapshot and trusted turn/tool attribution to an optional local subscriber;
  the default explicitly drops the handoff because persistence is a later milestone.
  Tests also confirm snapshots/process-state inspection redact values, competing
  revisions serialize to one winner, and queued work completes after its caller dies.
- Verification after supervision and archival integration: format and
  warnings-as-errors compilation pass; the umbrella has 146 Call Engine tests
  (one excluded), 46 Gateway tests (four excluded), and 20 Console tests passing;
  the unused-dependency check is clean.
- Added the finite application-owned Jido Actions `read_variables`,
  `update_variables`, and `update_variable`. Plan startup derives the applicable
  action set from the receiver's grants and binds them through the activation's
  dispatcher; definitions do not generate modules or list these tools explicitly.
- The dispatcher owns the private binding. Host actions continue receiving only
  the existing redacted `Tool.Context`; neither that struct nor Jido runtime
  context contains the variables PID, grants, schemas, or resolved plan. The
  dispatcher state redacts the binding and pending variable-tool correlations.
- Jido's preflight guardrail callback supplies exact provider tool-call IDs before
  action execution. This fixed the first implementation's request-ID approximation
  and makes private update attribution agree with public tool lifecycle events.
- The request transformer asks the dispatcher for a fresh grant-filtered projection
  on every provider round and inserts it as a transient engine system message after
  the agent prompt. A focused test replaces the projection between transformations
  and confirms the old value is absent and the original Jido context is unchanged.
- A complete definition-driven Jido test reads a prefilled order section, merges an
  intake section, observes exact tool results and archival attribution, and completes
  the agent turn. The focused agent/tool/transformer/runtime group is green with 41
  tests.
- Full checkpoint verification passes: format, warnings-as-errors compilation,
  148 Call Engine tests (one excluded), 46 Gateway tests (four excluded), 20
  Console tests, and the unused-dependency check.
