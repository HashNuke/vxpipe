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

## Checkpoint C — settings authority foundations

- Added the Identity diagnostics-settings domain and dedicated port. Five focused
  tests first failed because the module did not exist, then passed: built-in admin/
  superadmin browser sessions, denied member/custom/delegated/OAuth authority, strict
  boolean/revision validation, conflict propagation and absent-port unavailability.
  Astra xhigh review is clean. This does not replace adapter-level current stored
  session/role validation, which remains to implement with persistence.
- Added a pure Engine settings lease with a fixed 3000 ms lifetime measured from
  the start of the authoritative read, not its completion. Six tests first failed
  for the missing module, then passed. Covers negative monotonic timestamps, exact
  expiry, slow reads, reordered replies, conflicting revision contents, clock
  mismatch and malformed authority. It is not connected to live audio or startup.
- The B umbrella run remains active (tmux vxdiag-b-final; actual BEAM process
  confirmed). Identity and engine tests were already loaded before these new,
  unreferenced modules/tests were added. No existing runtime modules or remaining
  suite inputs have changed. Its result applies to B; C has separate focused
  evidence and will need integrated/root gates after wiring.

- Astra reproduced a lease bug: a malformed response overwrote the error reason
  that remembered an earlier same-revision conflict, allowing the old enabled
  revision to refresh. The failing regression is retained. Conflict revision now
  has independent state that survives other errors and clears only on a valid
  higher revision. Seven lease tests pass; review recheck requested.

- Final Astra xhigh settings/lease review is clean; independent lease rerun7/0.
  Whole Identity suite106/0; all Engine diagnostics45/0. Root format, compile
  warnings-as-errors, strict Credo and unused-lock gates pass. Milestone/index
  retain C unchecked because durable settings, UI and runtime are not wired.

## Checkpoint C — durable installation setting in progress

- Added a dedicated singleton table and Persistence adapter; the migration seeds
  disabled revision zero, with constraints tying revisions to updater/time metadata.
  URL settings remain untouched. Updater public identity is retained as attribution
  without storing email or session credentials in the setting.
- Reads/writes revalidate the stored enabled user, current built-in admin/superadmin
  role, matching unrevoked/unexpired browser session under row locks. The app-domain
  guard is repeated at this adapter boundary. A snapshot read is internal-only and
  currently unwired; no unauthenticated route was added.
- The new tests were first run from a scratch path in the owning Persistence child
  against a separate local test database to avoid injecting them into the still-live
  B umbrella run. Five tests failed for the missing adapter, then passed. Two more
  checks pass: database-enforced audit failure rolls back the setting/revision, and
  a missing singleton remains unavailable instead of being silently recreated.
  Evidence: `/tmp/vxpipe-C-settings-store-{red,green,atomic}.log`. Tests will move
  into the owning application before commit.
- Domain validation is shared with the adapter; it strictly rejects nonboolean
  inputs and invalid/overflow revisions. No-op saves at the current revision return
  the same state and create no duplicate audit; stale no-ops still conflict.
- Isolated upgrade migration succeeded. Fresh-database verification and independent
  Astra review are in progress. No configured runtime, Console route or UI added.

- Review deterministically reproduced session expiry during an authority-row lock
  wait: the pre-query timestamp authorized a session that had expired before the
  lock was obtained. The retained regression coordinates two database connections
  with `pg_blocking_pids`, without sleeps, rolls back the attempted settings write
  and cleans up its synthetic user/session. The adapter now checks expiry against
  fresh UTC after both authority and settings locks. Eight focused tests pass.
- B's Persistence tests were already loaded/running before the new tests moved
  into the owning application. Final paths: `diagnostics_settings_store_test.exs`
  and `diagnostics_settings_session_test.exs`. All C database work remains on the
  isolated settings database; default test DB has not been changed during B.
- Fresh migration default-off read passes (one selected test) in
  `/tmp/vxpipe-C-settings-fresh-migration.log`. Full Persistence suite on the new
  schema is running; final Astra re-review requested.

- B umbrella run finished exit0 (`/tmp/vxpipe-B-root-final.exit`); its tmux session
  is terminal. All app suites passed, including Engine2562, Calls424, Gateway891,
  Persistence566 and Console585. B root evidence is complete; C changes still need
  their own integrated acceptance.
- Final Astra durable-settings review is clean, independent eight-test rerun green
  (`/tmp/vxpipe-review-settings-store-final.log`). Static root checks and changed
  Markdown local links pass. Local default test database migration starts only
  after the B run completed. Full C Persistence suite remains in progress.

- Full Persistence suite passes574tests/0failures (68excluded), using the isolated
  settings database: `/tmp/vxpipe-C-persistence-suite.log`. Default worktree test
  migration also completed successfully after B. Durable-settings checkpoint is
  reviewed and ready to commit; runtime configuration and UI remain separate work.

## Checkpoint C — Console diagnostics API in progress

- Added dedicated session-only GET/PATCH `/api/installation/diagnostics`, configured
  the durable Identity port, and introduced the exact diagnostics-settings route
  requirement. Admin/superadmin browser principals pass the route guard; the domain
  and storage independently enforce authority. URL operations remain superadmin-only.
- Expanded the Installation page's server-side guard to admit admins for the future
  Diagnostics section. Frontend navigation, section and toggle are not changed yet;
  rendered UI acceptance is explicitly deferred, not claimed by these API tests.
- Five database-backed endpoint tests started red (missing routes), then exposed
  the default-deny route permission and whole-page guard, which are now updated.
  Combined with the existing URL/setup/auth tests:11tests/0failures. Covers reload
  reads, stale revision conflict, invalid boolean, custom-role denial, anonymous/
  explicit bearer denial, and missing-storage503. Existing tests preserve admin
  denial of URL reads and writes. Initial scratch generation command used the wrong
  cwd and created no files; corrected before the meaningful red test run.
- Full Console suite and static gates are running; Astra API review requested.
  Runtime projection and actual capture remain unwired, and nothing is deployed.

- Final API review is clean; reviewer independently passed11endpoint/route tests.
  Full Console suite590tests/0failures (127excluded), static gates all pass. Evidence:
  `/tmp/vxpipe-C-console-api-suite.log`, `/tmp/vxpipe-review-settings-api.log`.
  Durable settings/API task marked complete; UI and runtime tasks remain open.

## Checkpoint C — Installation Diagnostics UI in progress

- Added the exact Diagnostics section and Benchmark using Silero VAD control. Admin
  presentation excludes the URL form; both production navigation projection and
  Storybook navigation now offer Installation to admin/superadmin only.
- Production route calls the dedicated session API with CSRF and saved revision;
  admin route never requests URL settings. React integration verifies a save and
  remount reread. URL settings load independently without remounting Diagnostics.
- Loading, unavailable/retry, saving and conflict/reload states are explicit. The
  checkbox retains the last confirmed value until persistence responds. Optional
  applying/applied evidence is presentation-ready, but the backend currently emits
  neither; actual application displays collection status unavailable. Runtime
  status refresh/propagation is still pending and C UI acceptance stays open.
- Red/green: component/role, production route and prototype navigation tests;
  backend navigation endpoint failed for missing admin destination then passed22/0.
  Initial frontend focused checks42/0 and typecheck pass.
- Astra reproduced a committed PATCH followed by a lost response being falsely
  described as unchanged. Fixed with uncertain-result wording, last-confirmed
  state, and mandatory reload before further writes. Retained regression and
  affected frontend tests37/0 pass; typecheck passes. Full frontend run overlapped
  reviewer-added red regression and reported that one failure (1168passed), so
  a fixed-source full rerun is now active.
- Bounded Chrome fixture inspection:1440x1000 desktop and390x844 mobile default;
  admin mobile without URL controls, keyboard Space toggle; failed save retains
  unchecked last-confirmed value and readable error. Initial browser selector
  raced Storybook loading; waiting for the checkbox resolved it. Astra independently
  checked admin desktop/mobile and superadmin mobile without horizontal overflow.
  Browser checks are simulated fixtures, not live call/runtime acceptance.

- Final Astra UI re-review clean;37focusedtests/0 independently. Second bounded
  Chrome pass confirms uncertain-save error, disabled checkbox and Reload on
  desktop/mobile; keyboard Enter reload restores editable confirmed state. No
  horizontal overflow. Evidence `/tmp/vxpipe-review-settings-ui-final.log`.
  Current source typecheck and root static gates pass. Full frontend rerun pending.

- Fixed-source full frontend rerun passes1169tests across149files:
  `/tmp/vxpipe-C-settings-frontend-suite-final.log`. New control/fixture lint exposed
  captured async fixture reassignment and a cleanup-ref warning; replaced fixture
  storage with a ref and extracted stable invalidation callback. Lint then passed,
  control tests5/0, independent affected suite37/0. These nonvisual changes do not
  alter production request invalidation; fixture saved state now survives knobs.
- Final UI cleanup review is clean. Typecheck rerun before commit. No additional
  browser polishing was needed after the bounded second pass. Production runtime
  status/polling and actual capture are still unimplemented; no deployment.

## Checkpoint C — runtime settings projection in progress

- Added an isolated named settings supervisor, permanent reader IO slot and
  direct-ETS projection. Reader initialization does not touch the database. The
  projector polls at1s intervals with at most one outstanding read and a1s result
  deadline; enabled authority still expires3s after read start. Status reads never
  call a GenServer or database and expire even while the projector is suspended.
- A timed-out operation retains the sole reader slot until actual completion,
  preventing refresh jobs from accumulating behind a stalled dependency. Late
  results are discarded. The pool is temporary at its parent boundary so exhausted
  internal restarts can degrade diagnostics without restarting unrelated children.
  Production startup wiring is not added yet.
- Invalidation uses a coalescing atomics flag before sending; a suspended projector
  receives one hint even after1000calls. Handling invalidation revokes local
  authority and fences any earlier read. Only a new durable read can enable again.
- Six projection tests were added red/green. A separate red case reproduced a late
  response beating its queued deadline message; result handling now checks elapsed
  time explicitly. Combined projection/lease13tests/0failures:
  `/tmp/vxpipe-C-settings-projection-final.log`.
- Full diagnostic subset, static gates and Astra review are in progress. No audio
  capture, distributed invalidation, application startup wiring or model work yet.

- Follow-up: database-enabled startup now injects the internal snapshot loader;
  no IO occurs in child composition or reader initialization. Startup contract
  test was red for the missing child, then green. Application/projection12/0;
  actual Persistence snapshot integration8/0 covers off0/on1/off2 revisions.
  Engine owns no Persistence dependency. Cross-node hints, consumers and effective
  status remain pending; startup alone does not enable audio collection.
- Astra xhigh independently reviewed the projection and startup/integration:
  no findings,13lease/projectiontests,12application/projectiontests and8storetests
  passing. Full diagnostics subset51/0. Root format, compile warnings-as-errors,
  Credo strict and unused-lock checks pass. Full fixed-source umbrella run is
  active at `/tmp/vxpipe-C-projection-root.log`; do not claim its result yet.

### Next capture integration research

- `Capability.SpeechToText.State.send_audio/2` validates frame identity and
  format, and returns successful provider admission. Its state already knows
  tenant/room/incarnation/participant/connection and allocation generation;
  policy interval validation lives in the same boundary. This is a candidate
  accepted-frame hook, not permission to bypass source observation policy.
- `ConversationalSTT` preserves the frame only until normalization, drops its
  sample timestamp, and sends accepted PCM through one operational inference
  stream. Reuse needs metadata alongside pending/inflight PCM and explicit
  recognition-epoch reset notices. Do not infer sample continuity from the
  probability count alone or alter existing discarded-result behavior.
- Browser and telephony frames retain monotonic-ms receipts. WebRTC's
  `SpeechInput` also carries decoded activity PCM for Opus, while the supported
  Scribe profile is linear16. Normalize the diagnostic copy in its worker;
  existing `STTActivityPCM` caps normalized chunks at96000bytes.
- Scribe socket messages presently have no receipt field. ContinuousSTT knows
  the actual settlement branch and provider turn reference. Any timed envelope
  must retain ordinary fixture/transport behavior and distinguish unavailable
  receipt evidence from a fabricated later callback timestamp. No production
  receipt/audio/correlation code was changed during this inspection.

### Root verification investigation

- The fixed-source root run reported one Engine failure in the existing
  `IdleRoomTest` expiry case: `idle_wait` was nil before its manually injected
  deadline (seed52109). The same focused test/seed passed in isolation. Engine
  completed2576tests/1failure; this root run is not passing acceptance evidence.
- Astra reproduced a separate pre-existing cross-sender ordering race: delaying
  the idle Task's room request until after silent acknowledgment completion causes
  authorization to reject the now-missing origin turn. The reproduction uses300s
  idle duration, so it is independent of the test's competing1s timer. The root
  failure alone does not establish which ordering occurred. Diagnostics settings
  are unconfigured in default test startup and no speech control code changed.
- Preserve that production race separately; any narrowed expiry-test setup must
  explicitly establish admission before testing expiry. Do not report a test-only
  synchronization change as fixing the production admission race.
