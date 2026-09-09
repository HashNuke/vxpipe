# Call inspection and debugging

## 2026-09-09 — checkpoint started

- Milestone 8 left an authorized, tenant-scoped private-history read, but no bounded
  call list or inspection-specific timeline projection.
- Keep inspection history in `vxpipe_calls`; Console must consume public APIs rather
  than query Ecto or inspect room process state.
- First checkpoint: project persisted facts and variable snapshots onto one honest
  source-timestamp timeline with participant, activation, turn and tool correlation.
  Only calculate a duration when matching start and terminal facts are present.
- Later checkpoints will add bounded repository reads, a deliberately projected live
  source, and the Console workflow. Browser work will be inspected separately.

### Result

- Added `CallTimeline` as the correlation/order owner and `CallTimelineEntry` as the
  private, inspect-safe projection value. `CallHistory` now includes that timeline.
- Tool terminal entries receive an observed duration only when their archived start
  fact is present. The basis is explicitly `source_timestamps`; incomplete history
  leaves both duration and basis unset.
- A Call Variables snapshot is its own timeline entry and retains the command,
  participant, activation, source participant, turn, tool call, global revision and
  section revision that attributed the update.
- Red evidence: the focused Calls test failed because `CallHistory` had no `timeline`.
- Green evidence: focused Calls tests: 8 tests, 0 failures. Root format, warnings-as-errors
  compile, strict Credo (241 files / 2,340 functions), unused-dependency check, and the
  full migrated umbrella suite passed: 318 tests, 0 failures, 6 integration exclusions.

## 2026-09-09 — bounded call index

- Added an inspection-specific repository port rather than expanding the prepared-call
  write/admission repository or letting Console see Ecto.
- `Calls.list_calls/2` requires the existing trusted principal with `:calls` scope,
  supplies only non-payload call summaries, caps pages at 100, and rejects malformed
  cursors before repository access. A query asks for one extra row solely to decide
  whether a continuation cursor exists.
- The cursor contains the stable `(created_at, public call ID)` boundary in URL-safe
  encoded form. It is opaque pagination state, not a credential or authorization token.
- Red evidence: the new focused test failed to compile because `CallSummary` and the
  inspection repository contract did not exist.
- Green evidence: focused inspection tests: 2 tests, 0 failures. Root format,
  warnings-as-errors compile, strict Credo (246 files / 2,357 functions), and the
  unused-dependency check passed. The first full-suite attempt hit an existing
  timing-sensitive archive assertion in `DefinitionDrivenCallTest`; its isolated
  rerun passed, and a subsequent full migrated run passed with 320 tests, 0 failures,
  and 6 integration exclusions.

### Persistence adapter

- `InspectionStore` applies the tenant predicate, newest-first `(created_at, public ID)`
  ordering, cursor boundary and caller-supplied row bound in SQL. It selects only the
  fields needed for `CallSummary`; resolved plans and initial variables are not decoded.
- Runtime configuration selects this adapter only when Vxpipe persistence is enabled.
- Red evidence: the focused persisted-list test reached the new Calls boundary and
  failed because `InspectionStore.list_calls/4` was absent.
- Green evidence: the focused Ecto test passed, as did format, warnings-as-errors
  compile, strict Credo (247 files / 2,362 functions), unused-dependency validation,
  and the full migrated umbrella suite: 321 tests, 0 failures, 6 integration exclusions.

## 2026-09-09 — bounded call detail

- Added `Calls.inspect_call/3` over the inspection port. It authorizes and validates
  the history cursor before fetching the tenant-scoped call, then requests at most one
  extra record for continuation detection.
- Facts and variable snapshots share a stable, URL-safe history cursor based on source
  timestamp, a fixed source rank, source sequence/revision, and public record ID. The
  Ecto adapter runs one bounded query per record type, merges at most twice the query
  limit, and never exposes database primary keys.
- Detail pages are newest-first. If a tool terminal record is on a page without its
  start, duration stays unavailable; page boundaries are not treated as evidence.
- Extracted `ArchiveRecordCodec` so archival writes/reads and inspection reads share
  one domain conversion rather than duplicating private-record reconstruction.
- Red evidence: the Calls contract initially lacked `HistoryCursor` and
  `inspect_call/3`; the persisted acceptance then failed at the absent
  `InspectionStore.fetch_call/3` boundary.
- Green evidence: 12 focused Calls tests and the focused Ecto detail test passed.
  Root format, warnings-as-errors compile, strict Credo (250 files / 2,401 functions),
  unused-dependency validation, and the full migrated umbrella suite passed with
  324 tests, 0 failures, and 6 integration exclusions.

## 2026-09-09 — archive completeness metadata

- Detail pages now include the latest persisted Call Variables revision plus archive
  closure state, last source sequence, bounded missing-sequence samples and duplicate
  provenance. The in-memory projection detects duplicate IDs and source sequences.
- PostgreSQL computes the last/distinct sequence metadata with aggregates and fetches
  at most 100 missing sequence samples with `generate_series`; it does not load the
  entire history to describe gaps. Stored duplicate IDs/sequences are prevented by the
  archive constraints and therefore report zero at this boundary.
- Reproducing the full suite under load exposed two unrelated timing-sensitive tests.
  The Call Variables queued-call test now observes the actual GenServer call send via
  tracing rather than exhausting a scheduler-yield loop. The real Jido fixture and the
  blocked archive-writer assertion now share the existing five-second bounded operation
  window instead of racing a two-second assertion.
- Red evidence: new tests failed on absent archive fields/callbacks; full-suite runs also
  reproduced the two timing failures before their synchronization/timeout corrections.
- Green evidence: 13 focused Calls tests, the focused Ecto inspection test, and the three
  affected engine tests passed. A full migrated umbrella run passed with 325 tests,
  0 failures, and 6 integration exclusions.
