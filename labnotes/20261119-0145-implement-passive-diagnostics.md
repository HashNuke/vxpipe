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

## Checkpoint B — asynchronous storage in progress

- Storage checkpoint committed/pushed as `974995bc`; full persistence child suite
  passed 565 tests, zero failures (68 excluded).
- Earlier root foundation run ended exit 2: existing MCP cancellation test timed
  out, agent-idle acknowledgment test timed out, and later-discovered storage tests
  ran against an already-loaded older LatencyRun module. This mixed-source run is
  not acceptance evidence. Focused rechecks pass: MCP 3 tests, IdleRoom 18 tests;
  current persistence suite includes the UTC regression and passes. Run final root
  verification against a fixed source state after B is implemented.
- Added separately owned diagnostics writer, validated write envelopes, count/byte
  admission handoff, and bounded Task/Dynamic supervisors (not yet wired to app).
  Six tests red then green; abrupt writer death reproduced an orphaned unlinked
  task, fixed using a linked supervised task and trap_exit. Saturated task capacity
  also reproduced a writer crash; now finite retry/discard handles launch failure.
- All 11 async writer/supervision tests pass: blocked DB, byte/count saturation,
  retries retaining reservations, task timeout/crash, concurrent producers, bounded
  drain and abrupt owner death. Strict Credo passes. Astra xhigh review is running.
- Byte budget charges serialized validated payload three times plus envelope overhead
  for message, queued original and task copy; it is a retained-payload accounting
  bound, not a claim about total VM/driver heap memory.
- Future live wiring still needs dedicated settings ownership and collectors. Existing
  ConversationalSTT.push_frame retains AudioFrame metadata and normalizes via
  STTActivityPCM; provider settlement resets its operational inference epoch. Reuse
  must tap probability/sample evidence while preserving those resets. Installation
  currently has a whole-page superadmin guard, which must become section-specific.
- Astra xhigh proved retained sub-binary backing storage bypassed byte limits and
  Task.Supervisor.async startup could block drain indefinitely. Retained red tests;
  accepted strings are now copied, and a linked admission helper keeps writer
  responsive under an attempt deadline covering startup and execution.
- Follow-up review proved expired helpers left unbounded startup requests in a
  suspended task supervisor mailbox. Added a shared admission gate injected by
  the owning DynamicSupervisor; unresolved startup retains its permit across
  writer lifetimes until full pool restart. A regression spans five replacement
  writers with capacity one. No late repository write occurs after resume.
- Byte charge now covers four copies plus 512 bytes, superseding the earlier
  three-copy note. Unexpected success responses must equal the queued record.
  Final focused suite is 16 tests, zero failures; review of gate is ongoing.
- Current async writer is not registered in the application or used by live calls.
  It will be owned by enabled diagnostics lifecycle in C. Unknown admission debt
  intentionally degrades diagnostics until that dedicated pool resets.
- Final Astra xhigh review returned no remaining async-writer findings; all 16
  diagnostics tests pass. Final format, warnings-as-errors compile, strict Credo
  and unused-lock checks pass. Whole Calls suite had one existing 100ms billing
  lookup assertion timeout while concurrent static checks ran; rerunning it alone
  in `/tmp/vxpipe-B-calls-writer-suite-final.log` before claiming the child gate.
- Isolated Calls rerun exposed a new timeout-test assumption: a 20ms whole-attempt
  deadline can expire during admission before the repository receives work. The
  implementation correctly discarded it, but the test required repository startup.
  Corrected the assertion to verify discard and capacity release for either timing
  path; task teardown remains covered separately by drain/owner-death tests.
  Full Calls rerun: `/tmp/vxpipe-B-calls-writer-suite-final2.log`.
- Final Calls suite passes 418 tests, zero failures. Astra xhigh approved the
  timeout-test correction and returned no new findings. Async writer subcheckpoint
  is ready to commit; full B coverage/replay/live wiring remains unfinished.

## Checkpoint B — coverage and replay in progress

- Coverage: six red/green tests distinguish absent collection, fresh/pending capture,
  stale/future clocks, closed row-count mismatch and explicit loss. Completion means
  a selected capture window, not whole-call coverage. Run pages aggregate all durable
  turn counts independently of turn-page size; storage suite now passes 15 tests.
- ScribeReplay drives the real ContinuousSTT adapter through an isolated in-memory
  transport. Supplied logical fixture offsets are not actual network latency.
  Four red/green tests cover segments/drafts, forced flush acknowledgment and duplicate
  empty partials without duplicating endpoint rules. Review reproduced a queued manual
  flush from a prior turn being misattributed; transport notifications now carry the
  actual semantic turn reference and startup has a unique replay token. Five tests pass.
- AcousticObserver combines the existing ActivityBoundary with SampleClock and keeps
  confirmed callback time separate from backdated sample endpoints. Four red/green
  tests cover gaps, conflicting duplicates, foreign sources and expired mappings.
- Real Silero PCM replay passes against the existing synthetic short-answer fixture;
  no new audio artifact created. Missing frames remain explicit. ReplayReport correlates
  the final pre-provider boundary, rejects resumed-speech ambiguity and cross-clock/source
  evidence, and preserves useful provider stages during acoustic loss (4 red/green tests).
- Persisted offline demonstration/command and final review remain in progress. No
  live benchmark capture or app setting has been enabled or deployed.

- Reviewer reproduced duplicate PCM retransmission being re-inferred after a reset.
  Exact repeated metadata/PCM now returns the unchanged replay before inference;
  conflicting duplicates remain rejected. Retained regression passes (2 PCM tests).
- `bin/replay-latency-diagnostics` completed against an isolated local fixture DB.
  A fresh BEAM read returned two stored scenarios, zero ordinary call facts,
  complete synthetic 300000 us endpoint delay and missing-audio null delay with
  incomplete coverage. Evidence: `/tmp/vxpipe-B-replay-command.log`. This is not
  live provider latency. The command prints a repeat-read invocation and JSON artifact.
- Combined engine diagnostics: 38 tests, zero failures in
  `/tmp/vxpipe-B-engine-diagnostics-final.log`. Final independent review and full
  root verification remain pending; no live capture or deployment claimed.

- Final Astra xhigh replay/coverage review returned no remaining findings. Reviewer
  independently read the fixture DB in a fresh BEAM, verified remote-host rejection,
  and passed 11 replay tests (`/tmp/vxpipe-review-replay-final.log`).
- Final focused checks: Calls diagnostic/record tests 32/0; persistence storage15/0.
  Root format, compile warnings-as-errors, strict Credo and unused-lock checks pass.
  Full root test rerun is running in tmux `vxdiag-b-final` against fixed source:
  `/tmp/vxpipe-B-root-final.log`, completion code `/tmp/vxpipe-B-root-final.exit`.
