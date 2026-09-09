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
