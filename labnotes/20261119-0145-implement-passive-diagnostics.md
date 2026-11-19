# Implement passive diagnostics

## Checkpoint A — readable conversation

- Ran `bin/setup` successfully. Planning milestone/design committed and pushed as
  `6777cda4`; implementation follows its six checkpoints.
- Red evidence: React test showed usage observations visible by default; presenter
  test showed all canonical kinds missing; decoder test showed kind lost at JSON
  boundary. Added canonical `event_kind`/`eventKind` without inferring from labels.
- Shared admin/debug React UI has Technical events off by default; all seven kinds
  remain archived and available on demand. Unknown/legacy kinds remain visible;
  Usage accounting and protocol Logs are unchanged.
- Added 100-item rendered pages after filtering. This bounds DOM rows, not the
  unchanged full-history API response. The loader already loads full history,
  so technical-only server cursor pages do not occur on this surface.
- Additional red/green test caught equal-timestamp ID sorting; carry canonical
  details-store order through the derived view instead.
- Astra xhigh review used `gpt-6-astra` as explicitly requested. Reviewer reproduced
  two live-pagination failures (already connected and ready→connected, message 101
  missing). Retained regression tests in conversationPagination.test.tsx; follow
  newest page unless the user explicitly browses older history. Re-review returned
  no remaining checkpoint A findings; focused review suite 12 passing tests.
- Verification so far: presenter 16/16; core/react full suite 50/50; Console assets
  full suite 1163/1163; workspace build/typecheck and Console typecheck pass.
  Root format, warning-free compilation and strict Credo pass. First umbrella test
  process exited 143 before summary; not counted as a pass. Persistent tmux rerun
  is tracked separately until a terminal result exists.
- Rendered headless Chrome with agent-browser against real Storybook components:
  Workbench technical fixture and admin ended-call fixture, desktop and 390x844.
  Confirmed default-hidden versus opt-in records, mobile filter menu, readable
  rows, no desktop overflow, filter keyboard operation and page controls. Chrome
  required `--no-sandbox` on this host. Screenshots are temporary evidence only.
- Sent concise progress through pushnotify at start and during review/fix cycle.
- No runtime deployment yet; checkpoint B onward remain unimplemented.

## Resumption handles

- Umbrella verification runs in tmux session `vxdiag-checks` (shell writes terminal
  results to `/tmp/vxpipe-A-test-final.exit` and `/tmp/vxpipe-A-unlock.exit`). Inspect
  those and the matching logs; do not restart a still-running suite. First run
  `/tmp/vxpipe-A-test.log` was interrupted and is not acceptance evidence.
- Browser fixture server runs in tmux `vxdiag-browser` on assigned Storybook port.
- Checkpoint A review agent `review_checkpoint_a` returned no remaining issues.
  Implementation remains uncommitted until root gates finish; planning commit
  `6777cda4` already pushed to origin/qa. After gates pass, finalize milestone/labnote,
  stage exact A paths, inspect cached diff, commit and push, then start checkpoint B.
- Final affected Console frontend run passes 22 tests and typecheck. Latest shared
  UI run passes 50 tests including all reviewer reproductions. No runtime code has
  changed since root verification started; later changes are frontend/docs only.

## Checkpoint B — timing foundations in progress

- Checkpoint A code committed/pushed as `10d9c4a8`, with its final umbrella gate
  explicitly pending. This supersedes the earlier uncommitted resumption note.
- Added isolated engine timing/sample-clock primitives after the running A suite
  had already loaded its engine tests. That suite does not count as B verification.
- TurnTiming red: seven undefined-module failures; green: all seven pass. Keeps
  text commits distinct from actual provider-end receipt; calculates from acoustic
  sample time, rejects cross-clock input and invalid order, and preserves valid
  response-stage durations when acoustic coverage is invalid.
- SampleClock red: six undefined-module failures; green: six pass. Bounded sample
  mapping records receipt jitter, flags gaps, rejects reorder/source mismatch and
  conflicting duplicate input, never extrapolates through missing audio, and
  keeps pre-run/expired endpoints unavailable. Existing five diagnostic tests also
  pass: combined diagnostics directory 18 tests, zero failures.
- Both are pure measurement primitives; no provider/audio runtime integration or
  setting activation exists yet. Persistence, replay and async storage remain B work.

## Checkpoint A gate completion and B review

- Persistent A umbrella run completed with zero failures and exit 0; unused-lock
  check also exited 0. Milestone/index now record A complete. No deployment yet.
- Astra xhigh reproduced four timing defects: compressed-arrival reversal, shared
  boundary remapping after eviction, multiple acoustic endpoints selecting an early
  pause, and adapter/room causal inversion. Retained regression tests fail before
  fixes and pass afterward; diagnostics directory passes 22 tests.
- Distinct endpoints now invalidate acoustic timing as ambiguous; compressed frame
  mappings return clock_uncertain. Exclusive boundary ownership expires old mappings
  rather than silently changing timestamps. Causal inversion invalidates affected stages.
- Further review reproduced unbounded integer retention. Added signed-64-bit bounds
  for sample timestamp and sequence after confirming the failing test.
- Calls LatencyRun: 5 red then green tests. TurnDiagnostic: 4 red then green tests;
  combined records suite passes 9. Records reject unrestricted fields and derive
  durations from allowlisted landmarks, preserving partial/incomplete evidence.
- B remains partial: no migration, repository, async writer, replay or live capture.
- Final Astra xhigh foundation review returned no remaining findings: 23 timing
  tests and 9 neutral-record tests pass independently. Root format, warnings-as-errors
  compile and strict Credo pass. Fresh root tests run in tmux `vxdiag-foundations`;
  terminal evidence: `/tmp/vxpipe-B-foundation-test.exit` and
  `/tmp/vxpipe-B-foundation-unlock.exit`. Pending at this foundation commit.
- This is a reviewed partial B checkpoint, not completion of the durable-report
  vertical slice. B checklist remains unchecked until persistence/replay gates pass.

## Checkpoint B — durable storage in progress

- Added tenant-scoped diagnostics storage and separate run/turn tables. Seven storage
  tests failed with the missing adapter after correcting the fixture's admission
  return shape, then passed. Two additional red tests exposed forged-input encoding
  before validation and the missing full-report aggregate; all nine now pass.
- Call locks serialize diagnostic writes with deletion and incarnation changes.
  Existing bound call identity is required; diagnostics never bind or recreate a call.
  Revision conflicts/stale writes, immutable run profile, terminal reopening,
  cross-source turns, cursor bounds and cascading call deletion are covered.
- Aggregates are SQL over the full call report (not the page), exclude null durations,
  and group by complete provider/model/algorithm configuration. Timing data is
  bounded allowlisted JSON; no transcript or audio fields are accepted.
- Migration checks passed on two new isolated test databases: full fresh migration,
  and upgrade from the previous schema after persisting one admitted/bound call.
  Separate-process verification confirms the existing call is preserved and both
  new tables are empty. Logs `/tmp/vxpipe-B-migration-{fresh,populated}.log`, exit 0.
- Strict Credo passes; Astra xhigh storage review is ongoing. Async storage, run
  coverage, replay, settings and runtime capture remain open; no B acceptance box checked.

- Astra xhigh reproduced constructor-valid 256-byte IDs exceeding varchar(255) and
  second-precision UTC timestamps rejected by Ecto's microsecond column. Tests
  retained red/green; final migration uses text with byte-length constraints, and
  the indexed heartbeat expands precision without changing its time value.
- Independently reproduced non-UTC anchors accepted before persistence and rejected
  by Ecto; neutral constructor now enforces UTC. Actual unavailable PostgreSQL
  connection returns diagnostics_unavailable. Two-tenant test now uses a real second
  tenant for read/write denial. Final storage suite 14 tests and records suite 10
  tests pass; Astra xhigh re-review returned no remaining findings.
- Final migration reverified fresh/populated with logs ending `-r2`, both exit 0.
  A local test-schema alignment changed only the new tables' column types/constraints
  after modifying the uncommitted migration; no tables or existing calls were dropped.
- B migration/revision and isolation-test tasks are now checked; B overall remains
  open for async storage, coverage and exact replay. Full persistence child suite
  `/tmp/vxpipe-B-persistence-suite.log` is running; earlier root foundation suite
  remains live in tmux `vxdiag-foundations`. Do not mistake either for completion.
