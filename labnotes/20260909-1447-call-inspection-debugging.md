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

## 2026-09-09 — bounded engine live projection

- Added one `LiveInspection.Buffer` beneath each planned room incarnation, before Call
  Variables and room authority startup. It has application-level finite limits (64
  pending and 256 retained by default), and producers use a non-suspending port rather
  than a synchronous GenServer call.
- Existing archive fact construction remains the single policy-filtering and sequencing
  path. That path now fans the resulting fact independently to archival storage and the
  live buffer, so a full or unavailable archive cannot suppress live inspection. Call
  Variables similarly offers each baseline/update snapshot independently after accepting
  it in memory.
- The buffer is a non-significant `:temporary` child. Losing it leaves the room and
  participant processes running and makes the live read explicitly return
  `:call_not_live`; it is not restarted as an empty buffer that would imply continuous
  history. Retention overflow counts dropped oldest records, and rejected producer work
  is exposed separately.
- Red evidence: the room-level test timed out because planned rooms did not start a live
  buffer. A supervision test then failed against a deliberately permanent child because
  it restarted with an empty snapshot after being killed.
- Green evidence: the live-buffer tests pass with 2 tests and 0 failures. Focused archive,
  Call Variables, definition-driven room and live-inspection tests pass with 30 tests and
  0 failures. The full call-engine suite passes with 181 tests, 0 failures and 2
  integration exclusions. Strict Credo reports no issues across 254 source files and
  2,456 modules/functions. Root format, warnings-as-errors compile and unused-dependency
  validation pass. The complete migrated umbrella suite passes against a fresh isolated
  PostgreSQL cluster with 327 tests, 0 failures and 6 integration exclusions.

## 2026-09-09 — authorized live timeline boundary

- Added a Calls-owned live inspection source port and a default adapter that reads only
  the engine's bounded public projection. Tests can replace the source without starting
  a room, while production configuration names the engine adapter explicitly.
- `Calls.inspect_live_call/3` validates the existing trusted principal and `:calls` scope
  before touching the source. It supplies the principal's tenant key rather than trusting
  a caller-selected tenant and returns `:call_not_live` for another tenant's call.
- Added `EngineArchiveProjection` as the single conversion from engine facts/variable
  snapshots to Calls-owned validated values. Both live inspection and `EctoStorage` now
  use it; the persistence adapter no longer maintains a parallel conversion.
- `LiveCallInspection` validates the outer snapshot and every record's tenant, call, room
  and incarnation identity before projecting a descending correlated timeline. Timeline
  entries now carry either `persisted` or `live` explicitly. Raw engine records do not
  escape, and private timeline payloads remain excluded from `Inspect`.
- Red evidence: focused tests failed because `Calls.inspect_live_call/3` did not exist.
- Green evidence: the full Calls suite passes with 34 tests and 0 failures, including
  scope, malformed-ID, cross-tenant, record-identity, source-adapter, source-label and
  tool-duration checks. Root format, warnings-as-errors compile, strict Credo (258 files /
  2,481 modules/functions), and unused-dependency checks pass. The complete migrated
  umbrella suite passes against a fresh isolated PostgreSQL cluster with 331 tests,
  0 failures and 6 integration exclusions.

## 2026-09-09 — operator authentication and session foundation

- Selected a Console-owned browser login for call inspection only. It submits an existing
  tenant API key to the server, delegates verification to the public Calls authentication
  workflow with the existing `:calls` scope, and does not alter caller join-token semantics.
  Sample, diagnostics, and LiveDashboard routes remain outside this access boundary.
- Split the boundary into an authenticator contract, a Calls-backed adapter, an
  authentication workflow, and a session codec. This keeps credential verification,
  adapter selection, and browser identity serialization out of future page controllers.
- The signed session contains only the tenant key, API-key ID, closed scope names, and an
  expiry. It never contains the API-key secret. Malformed identities, unknown scope names,
  missing `:calls` scope, and expiry fail closed. The base setting gives sessions a one-hour
  maximum age; route/form integration remains a later checkpoint.
- Red evidence: six focused tests first failed on the absent authentication/session modules;
  the expiry test then failed on the absent option-aware session functions.
- Green evidence: the six focused tests pass. The complete Console child suite passes with
  31 tests and no failures. Root format, warnings-as-errors compilation, strict Credo
  (262 files / 2,502 modules and functions), and unused-dependency validation pass. The
  complete migrated umbrella suite passes against a fresh isolated PostgreSQL cluster with
  337 tests, no failures, and six integration exclusions.

## 2026-09-09 — Console inspection read boundary

- Added one Console-owned adapter contract covering bounded call lists, persisted detail,
  and live detail. The production adapter delegates to public Calls workflows and never
  imports Repo schemas, queries engine process state, or reimplements authorization.
- `CallInspection` removes its adapter-selection option before delegation, validates the
  three expected Calls-owned response structs, preserves explicit backend errors, and fails
  closed on malformed results. Trusted configured backend options override page request
  options, preventing a presentation caller from replacing repository/live-source wiring.
- The seam is deliberately narrower than a generic data service: it exists to make delayed,
  failed, live-unavailable, and ended-call Console fixtures deterministic while retaining the
  same page contract as production.
- Red evidence: the two focused tests failed on the absent `CallInspection` module.
- Two initial full-suite runs reproduced an unrelated timing-sensitive STT test: its owner
  received a process failure notification after ExUnit's implicit 100 ms mailbox timeout
  under umbrella load. The test already allowed 500 ms for the subsequent monitor event;
  all three failure-path messages now use that same finite test window. No runtime behavior
  changed, and the focused failure test passed after the correction.
- Green evidence: the two focused inspection-boundary tests and complete Console child suite
  pass (33 tests). Root format, warnings-as-errors compilation, strict Credo (265 files /
  2,515 modules and functions), and unused-dependency validation pass. The complete migrated
  umbrella suite passes against a fresh isolated PostgreSQL cluster with 339 tests, no
  failures, and six integration exclusions.

## 2026-09-09 — Console operator workflow

- Implemented the separate `/operator/sign-in`, `/calls`, and `/calls/:call_id` workflow.
  Only call-inspection routes require the signed operator session; the existing sample,
  diagnostics, and LiveDashboard behavior remains unchanged.
- Kept the browser session non-secret and added Phoenix request filtering for API-key,
  password, token, and secret parameters. Red evidence: the request-log sentinel test
  initially captured the submitted API key. Green evidence: debug output contains
  `[FILTERED]` and not the sentinel.
- Split presentation by responsibility: the call matrix, detailed event evidence,
  formatting, sourced-timeline projection, and variable-diff projection are independent
  modules. The route processes coordinate only bounded reads, URL state, and live refresh.
- The list is capped at 25 calls and persisted detail at 50 events. Call and history
  cursors are independent. Selecting an event is represented in the URL and does not
  refetch list, persisted detail, or live detail. Red evidence: the focused LiveView test
  observed an unexpected `list_calls` request after selection. Green evidence: selection
  updates with no backend reads.
- One tokenized one-second timer refreshes only a running call's bounded live projection.
  A refresh does not reread persisted history or the call list, and stale timer messages
  cannot refresh a different or ended selection.
- Rendered `agent-browser` review used a synthetic tenant-safe backend at desktop 1440px
  and mobile 390px. It verified exact persisted/live event selection, preserved call and
  history pagination URLs, the `r2` to `r3` variable diff, all nine mobile events, a 390px
  document width, and no browser errors. The final UI reviewer returned `ship` after the
  six material findings were resolved.
- Focused authentication and endpoint tests pass with 20 tests and no failures. The full
  Console child suite passes with 49 tests and no failures.
- Root format, warnings-as-errors compilation, strict Credo (278 source files / 2,691
  modules and functions), and unused-dependency validation pass. The first umbrella test
  command stopped before executing tests because the machine's default PostgreSQL required
  an unavailable password. A fresh temporary trust-authenticated PostgreSQL 18 cluster on
  loopback supplied the test database without using external credentials; the complete
  suite then passed with 355 tests, no failures, and six integration exclusions.
- Work is isolated on `milestone/call-inspection-console`. Presentation and route behavior
  were committed and pushed as small checkpoints before updating milestone evidence.

The milestone remains in progress. Controlled delayed-storage/tool fixtures and the
remaining end-to-end failure checks have not been demonstrated yet.

## 2026-09-09 — live-only inspection during repository outage

- Persisted list/detail reads and the engine-owned live projection now load independently.
  An unavailable repository no longer prevents an authorized direct call-detail request
  from reading the bounded live source.
- The resulting page labels persisted fields unavailable instead of inventing archived
  state. It continues to show the permitted live timeline, live variable revision and loss,
  and an unknown tool outcome; its status explains that calls in progress are unaffected.
- Red evidence: the new repository-unavailable endpoint fixture rendered only the
  unavailable state and never issued the live inspection read.
- Green evidence: the focused endpoint file passes 14 tests, and the complete Console
  suite passes 50 tests.
- Rendered `agent-browser` verification at 390px showed the live-only/tool-failure state,
  retained a 390px document width, and reported no browser errors.
- This checkpoint is commit `669f14d`. It covers honest live-only presentation during a
  repository outage.

### End-to-end outage verification

- The existing definition-driven archive-recovery test already runs a real call while its
  bounded writer repeatedly raises: the host tool completes, model response continues, and
  a Call Variables update is accepted/read locally before storage recovers.
- Extended that scenario to read the actual room-owned live inspection buffer at the outage
  point. It contains the completed tool and variable snapshot at global revision 1 with the
  original participant, turn, and tool-call identities. No polling sleep was added; the
  inspection buffer's own GenServer acknowledgement orders earlier offers before the read.
- Storage recovery still drains retained facts exactly once and writes the archive closure.
  Focused evidence: the definition-driven archive-recovery test passes with 1 test and no
  failures. The verification-only checkpoint is commit `6c6b66f`.
- Together with the independently tested Console live-only state, this proves the storage-
  outage acceptance path across the owning boundaries. The remaining milestone failure and
  lifecycle checks are still pending.

## 2026-09-09 — explicit archive-gap evidence

- Calls already supplied bounded missing-sequence samples and duplicate ID/sequence counts.
  The Console hid the duplicate counts and reduced the missing evidence to a generic count,
  which prevented an operator from distinguishing those archive-integrity signals.
- The Console now displays all three bounded counts in its archive-gap notice.
- Red evidence: the focused endpoint assertion for the exact archive notice failed because
  only the generic missing count was rendered.
- Green evidence: the focused endpoint file passes 15 tests, the complete Console suite
  passes 51 tests, and root format, warnings-as-errors compilation and strict Credo checks
  pass.
- Rendered `agent-browser` verification at 390px showed the exact notice `Archive gap: 2
  missing sequences · 1 duplicate ID · 1 duplicate sequence`, kept the unknown tool payload
  visible, retained `scrollWidth = innerWidth = 390`, and reported no browser errors.
- This presentation checkpoint is commit `e1dfa09`. It does not complete the remaining
  subscription, lifecycle or safe missing/denied/purged acceptance checks, so the milestone
  remains in progress.

## 2026-09-09 — failure and page-lifecycle edges

- Added deterministic coverage for a failed tool event whose permitted payload reports an
  unknown outcome. The payload is rendered as inert inspection evidence rather than hidden
  or converted into a successful result.
- A call absent from both persisted and live sources now presents the same generic not-found
  state appropriate for missing or purged data. Internal `call_not_found` and `call_not_live`
  atoms do not reach the rendered response.
- Closing the detail LiveView terminates its inspection process and produces no further live
  source reads after more than one polling interval. The test observes process termination
  with a monitor and does not use a synchronization sleep.
- Green evidence: the focused endpoint file passes 17 tests, the complete Console suite
  passes 53 tests, and root format, warnings-as-errors compilation and strict Credo checks
  pass.
- Checkpoint `bcb75d2`, combined with the earlier end-to-end archive-outage and ended-call
  fixtures, completes the deterministic delayed-storage, failed/unknown-outcome and
  terminated-room implementation task. It also completes the correlated variable/slow-tool
  timeline check. Reconnection, stale purge-cache behavior, and other remaining acceptance
  checks keep the milestone in progress.
