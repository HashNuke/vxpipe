# Passive call latency diagnostics and readable timelines

Status: implementation in progress, 2026-11-19. Checkpoint A code, focused tests,
rendered checks, Astra xhigh review and all root gates pass. Checkpoint B now has a reviewed, durable offline replay and passing root gates.
C settings foundations are in progress; C–F acceptance remains open. The index owns implementation order.

## Runnable outcome

An authorized operator opens a live or ended call and sees a readable conversation.
Routine usage, playback and turn bookkeeping is available through an explicit
Technical events control, off by default in both admin call details and the debug
view. An opt-in, passive benchmark persists one timing summary per human turn and
exposes a collapsed Latency diagnostics section. It distinguishes estimated speech
end, provider turn-end evidence, application dispatch, response text and audio start.
Observer or database failure never controls speech, delays admission, or ends a call.

User-approved scope: separate durable diagnostic records; asynchronous bounded
writes; optional call-details presentation; hide the seven named noisy event types
by default while retaining their diagnostic/accounting value. Implementation is
authorized. Deploy `vxpipe.service` only after the complete milestone passes;
o live measurements or deployment are claimed by the offline foundation.

## Prerequisites and design sources

Read these completed foundations before implementation:

- [Asynchronous call history](asynchronous-call-history.md): non-suspending bounded
  handoff, shutdown drain, source-policy and honest loss evidence.
- [Call inspection](call-inspection-and-debugging.md): Calls-owned tenant-scoped
  reads; Console-owned authentication and presentation; no direct Repo browser reads.
- [Usage observations](usage-and-billing-observations.md): preserve accounting
  and aggregation when individual usage events are hidden.
- [Call-details publications](call-details-publications.md): immutable documents
  and completeness remain independent of this optional diagnostic producer.
- [Transcript start and optional VAD](transcript-start-and-optional-vad.md): the
  existing VAD switch changes operational onset; do not reuse it as benchmark opt-in.
- [Structured messages](structured-agent-messages.md) and
  [universal replies](universal-agent-replies.md): retain correlation and generated
  text meaning; published text is not necessarily the first model token.
- [Passive benchmark design](../../docs/design/shadow-vad-latency-benchmark.md),
  [speech runtime](../../docs/en/development/speech-runtime.md),
  [testing guidance](../../docs/en/development/testing.md), and the
  [completed Scribe endpoint correction](provider-turn-detection-and-contextual-barge-in.md#scoped-checkpoint--remove-scribes-local-endpoint-wait).

This milestone does not wait for the unimplemented
[voice turns/listening milestone](voice-agent-turns-and-listening.md). Its measured
results can support that milestone's latency acceptance, but do not implement its
classifier, listening cues, word alignment or one-second target. Packaging and
retention remain separate; new tables must already participate in call-owned deletion.

## Research findings that constrain implementation

- `Speech.Silero` already wraps pinned ONNX inference, 512 samples at 16 kHz
  (32 ms). `ActivityBoundary` confirms end after 16 silent frames and returns
  the earlier silence-start sample. This is a baseline estimate, not ground truth.
- `ConversationalSTT` uses local onset operationally, discards acoustic end/sample
  timestamps, resets at provider settlement, and can fail on detector errors.
  Its runtime has synchronous admission and readiness coupling. Reuse primitives,
  not that lifecycle or its operational `vad` flag.
- Scribe `ContinuousSTT.recognition/3` accumulates committed segments; it settles
  on an empty provider partial after committed text with no outstanding draft.
  A committed transcript alone is not its turn-end signal. Instrument receipt of
  the exact signal consumed by settlement, not merely the last nonempty transcript.
- WebRTC and telephony populate `AudioFrame.received_at` in monotonic milliseconds;
  media sample timestamps are a different clock. Each transport/resampling path
  still needs mapping and discontinuity verification.
- The Console presenter sends ordinary archive entries as activities. Shared React
  filters default `events: true`, displaying every activity. Existing `logs` means
  RTVI protocol events, not these archive facts. A separate typed classification is
  needed; logger levels and label string matching will not solve the problem.
- Existing `Archive.Handoff` demonstrates bounded non-suspending offers. Benchmark
  traffic must have separate capacity and cannot consume ordinary history slots.

## Approved contracts and implementation choices

### Ownership and scope

Engine owns capture, sample correlation and optional observer supervision; provider
adapters supply receipt/boundary evidence; Gateway supplies transport receipt/sample
mapping. Calls owns database-neutral diagnostic records, validation and read/write
ports. Persistence owns migrations, adapters and queries. Console and core/react
packages own authorized presentation and browser state. Preserve Mix dependency
direction; no Ecto or Phoenix dependency in engine measurement code.

First supported live profile: human ElevenLabs Scribe v2 realtime input over browser
WebRTC and Telnyx. Exercise operational local VAD both off and on without changing
it. Manual/historical Scribe is covered by protocol fixtures; label unsupported
profiles explicitly, including native speech-to-speech. Do not claim a new live
provider/transport is supported from common fixtures alone.

Benchmarking defaults off and runs only while the durable installation-wide
**Installation → Diagnostics → Benchmark using Silero VAD** setting is enabled.
Only authenticated built-in admin and superadmin browser-session principals may
read/change this setting; enforce this at the server route and domain boundary,
not only by hiding the toggle. Members, custom roles, call participants, join
credentials and machine/API credentials cannot change it. Existing tenant-scoped
inspection rights still govern who may view previously collected results.

Place Diagnostics as a section on the existing Installation page, with the setting
label exactly **Benchmark using Silero VAD**. Use a dedicated diagnostics settings
operation. Admins can reach this page/section; existing installation URL controls
and their API remain superadmin-only. Replace the current whole-page superadmin
guard with section-level authorization without exposing unrelated settings. Persist a boolean, monotonic settings revision, updater
identity and update time; audit changes and reject conflicting stale saves. Reload
must reflect saved state, not an optimistic local toggle after a failed save.

The app setting is the sole enable authority. Environment options, embedding options,
call specs, the operational VAD flag, and opening a diagnostics panel cannot enable
capture when it is off. Resource limits may restrict eligible capture while on;
they cannot override the setting. All eligible supported calls are considered while
on, subject to explicit capacity/coverage reporting, not a hidden pilot allowlist.
Runtime code consumes a versioned local setting projection without per-frame DB
reads. Unknown/unavailable authority or an expired projection fails closed for
benchmarking only; calls continue normally. Define and test bounded propagation,
lease expiry and cross-node invalidation before live activation; a stale enabled
cache must not remain authoritative indefinitely.

Enabling starts fresh observation epochs for active eligible calls and new calls;
never infer prior audio. A turn already in progress is marked partial/unavailable
until a fully observed boundary is established. Disabling revokes new audio offers,
stops observers and discards queued audio on every worker. Show applying/pending
until revocation acknowledgements or lease expiry establish effective disable;
do not claim an immediate distributed stop from a DB write alone. Only summaries
of evidence captured while enabled may finish their bounded persistence drain.
Retain historical reports; turning off collection does not delete them. Re-enable
creates a new run/epoch and must not merge across the disabled interval. Record
settings revision on each run. Do not modify provider settings or call control.
Checkpoint C must record concrete propagation, lease, capacity and timeout limits
before enabling any live trial.

### Timing semantics

Keep these nullable landmarks, each with provenance and clock/session identity:

| Landmark | Meaning |
| --- | --- |
| Acoustic end estimate | Backdated media-sample boundary, mapped to server receipt-time basis. |
| Observer confirmation | When the observer confirmed that boundary; includes silence window and observer lag. |
| Provider text commit | Receipt of committed transcript segment(s); not necessarily end of turn. |
| Provider end evidence | Socket-callback receipt of the signal actually used to end this provider turn. |
| Adapter end emission | Adapter emits canonical turn end. |
| Room turn completion | Room accepts the completed human turn. |
| First response text | First published agent text linked to this input; not first-token inference latency. |
| First audio start | First matching acknowledged server egress; not proof of remote hearing. |
| Manual commit sent | Optional, where that provider path explicitly commits. |

Primary duration is provider-end-evidence receipt minus acoustic-end estimate.
Show commit-to-end, provider-to-room, room-to-first-text, text-to-first-audio and
speech-end-to-first-audio separately when valid. Observer confirmation is never
the subtraction baseline. Network and silence detection are included; no metric
is labelled pure provider compute. Tool-only, silent, interrupted and no-response
turns may have no text/audio milestones; never borrow the next unrelated output.

Compute same-clock durations in integer microseconds; expose integer milliseconds
for display with the actual precision/uncertainty. Keep media offsets/sample rate,
monotonic offsets relative to an identified run clock origin, an informational UTC
anchor and algorithm/version. Never compare raw monotonic values across VM boots
or hosts. Separate resampler delay, media gaps and arrival jitter from inference
queue time. Estimate server-received acoustic end, not microphone capture time.

For a standalone benchmark stream, keep observer state independent of provider
settlements. For reused operational inference, preserve its existing resets and
mark missing/cross-reset endpoint evidence incomplete rather than changing them. Resolve multiple acoustic
segments within a provider turn, forced commits, resumed speech, delayed results,
overlapping people, source replacement and repeated identical transcripts by IDs
and audio coverage, not text equality or nearest wall-clock timestamp alone.
Uncertain mappings yield null durations plus a reason; negative/inconsistent
durations are invalid evidence, never clamped to zero.

### Reuse operational Silero without duplicate inference

There is one Silero inference stream per accepted participant/source audio stream,
not one per consumer. When the call already runs local Silero, attach a bounded,
non-suspending diagnostic consumer to its existing probability/sample evidence.
The benchmark owns its own correlation/boundary accounting, not another model
execution. Reuse requires the same admitted audio, pinned model, sample mapping
and inference epoch; do not share recurrent state across participants or sources.
Record `operational_reuse` versus `benchmark_only` as provenance.

Current operational code resets/discards pending detector data on provider settlement
and ignores acoustic end events. Add timestamped observation of already computed
probabilities and reset/gap notices before those are discarded, without changing
control events, input admission, readiness, resets or error behavior. If existing
inference does not cover a complete endpoint, show incomplete evidence; do not run
a hidden duplicate to fill the gap or prolong operational inference after shutdown.
These measurements share operational VAD evidence and must not be described as an
independent detector evaluation. They still compare acoustic evidence to provider
turn-end timing.

When no operational Silero exists, create one isolated benchmark-only stream while
the Installation setting is enabled. With the setting off, no benchmark consumer,
benchmark-only model work or new diagnostic collection exists, but call-spec VAD
continues normally. Disabling detaches only diagnostics; it must never cancel or
reset an operational detector. Enabling mid-call subscribes prospectively, with
partial coverage until a complete boundary is observed. Source changes retire the
old diagnostic association and select reuse/standalone exactly once for the new
source; no overlap of duplicate inference streams during transition. In-flight
work retired by a setting/source change is fenced from the new run.

### Durable records and lifecycle

Use separate call-owned `call_latency_runs` and `call_turn_diagnostics` tables
(proposed names), never new ordinary `call_facts` for per-frame benchmark output.

- Run record: schema/config/model/algorithm versions, tenant/call/incarnation,
  measurement clock, selected coverage, started/closed state, observed/dropped/
  unmatched counts and incompleteness reasons. No run on an old/disabled call means
  not collected, not zero latency. A stale running record after a crash becomes
  unconfirmed/incomplete on read; do not fabricate a graceful close.
- Turn record: stable run and turn identity, participant/connection/source generation,
  STT allocation/provider-turn correlation, effective provider/model/commit profile,
  bounded landmarks and quality metadata, derived durations, monotonic revision.
  One logical row per run/canonical human turn; response references may be absent.
- Initial pending row can be revised as late observer/playback evidence arrives.
  Idempotent same-revision retries succeed; conflicting same revision is rejected;
  stale revisions cannot regress data. Updates never synthesize missing parent calls.
  Finalization deadline and bounded post-call drain leave incomplete evidence visible.
- Scope every operation to verified call ownership and incarnation. Store no audio,
  transcript, prompt, credentials, raw provider messages or unrestricted settings.
  Use bounded allowlisted configuration/provenance. Honor source observation/privacy
  policy before copying audio; timing metadata is not permission to inspect denied audio.
- Bound queues by both count and retained bytes, including in-flight work and retries.
  Reserve capacity before sending. Drop diagnostic work on saturation; mark affected
  intervals invalid and restart acoustic continuity. No synchronous DB fallback,
  unbounded mailbox, or retry loop in an audio/provider callback.
- Cascade on call deletion; reject late writes after deletion or incarnation retirement. After disable,
  accept only bounded finalization of evidence captured under the prior valid
  enabled revision; never accept new capture under that revoked revision. Retention uses existing call ownership/timestamps. No new retention clock.
  If DB outage prevents recording loss counters, report coverage unconfirmed rather
  than claiming those counters are complete or guaranteed durable.
- Keep v1 immutable details publications and their completion gates unchanged.
  Diagnostics are read through a separate authorized report; exporting them in
  immutable publications is explicitly deferred. Do not block publication on diagnostics.

Queries are bounded and cursor-paginated (default 50, max 100 turns), with stable
ordering and summary aggregates over the full authorized filtered report, not
only the current page. Report valid sample count and excluded/incomplete counts;
do not pool different profiles/metric definitions into a misleading provider score.

### Presentation and event policy

Preserve the current Console visual system. Default conversation shows messages,
tools, transfers, joins/leaves, interruptions and failures. Classify by canonical
event kind, with an additive typed metadata field preserved through JSON/core/live
updates. Unknown historical kinds remain visible; missing metadata never silently
hides failure or lifecycle evidence. Do not change backend archive retention.

| Hidden by default; available under Technical events | Value retained |
| --- | --- |
| `usage_observed` | Usage and billing observations; aggregate Usage view remains. |
| `agent_output_delivery_progressed` | Playback position and interruption diagnostics. |
| `agent_output_delivered` | Individual output completion, separate from entire turn. |
| `agent_output_delivery_started` (user calls this “Agent output started”) | Server playback-start evidence. |
| `participant_transcription_final` | Final recognizer text; accepted message remains visible once. |
| `participant_turn_started` | Human turn/onset evidence. |
| `agent_turn_completed` | Overall response completion. |

Technical events is off by default on admin details and debug view in production
and development; access follows existing authorized inspection, not a build-time
development gate. Existing protocol Logs remain distinguishable. Preserve original
IDs, timestamps and ordering when toggled; no duplicates or lost pagination records.
Filtering all loaded rows must not falsely imply the conversation is empty when
later permitted messages exist. Ensure both the default and technical history paths
remain bounded; virtualize or page large technical views as needed.

Latency diagnostics starts collapsed. Expanded: compact per-turn rows with readable
participant/turn references and stage durations; expand a row for technical evidence.
Use permitted existing transcript references only, not a second stored transcript.
Show Estimated speech end, STT turn ended, Response text ready and Audio started
with clear units. Do not imply transcript commit equals turn completion. Display
pending, not collected, unsupported, incomplete, denied and temporarily unavailable
states explicitly. Partial row stages remain useful. Loading/errors have retry,
and later revisions do not reset expansion/focus or overwrite newer values.
Use keyboard-operable disclosures, labelled controls, readable mobile rows and
non-colour-only quality indicators. Ordinary call participants gain no new access.

## Checkpoint order and exits

| Checkpoint | Runnable result | Depends on |
| --- | --- | --- |
| A — Readable conversation | Both existing views hide routine facts by default; operators can reveal them. | Completed inspection/UI foundations only. |
| B — Durable timing report | Deterministic replay produces a stored, tenant-safe per-turn report across restart. | Existing Calls/Persistence; independent of A. |
| C — Passive configured call | Selected Scribe calls produce real stored timing records without control effects. | B; timing correlation fixtures. |
| D — Latency details UI | An authorized live or ended call exposes a truthful collapsed timing report. | A–C; fixtures may start after B. |
| E — Isolation and accuracy | Failure/load tests and labelled replay establish honest error and overhead bounds. | B–D. |
| F — Live acceptance and handbook | Browser and telephone pilot evidence plus documentation and root gates. | A–E. |

### A — Readable conversation

- [x] Red-test the seven kinds hidden by default and visible on opt-in, preserving
  messages, tools, failures, interruptions and unknown kinds in both consumers.
- [x] Carry typed classification through presenter, core decoder/store and live
  updates; add Technical events without reinterpreting RTVI Logs or deleting facts.
- [x] Verify legacy snapshots, reconnects, pagination through technical-only pages,
  large histories, ordering, filter toggles and unchanged Usage totals.
- [x] Add realistic shared fixtures; inspect admin and debug views with headless
  Chrome via `agent-browser`, desktop/mobile, keyboard and empty/filter states.
- [x] Document filter meanings and retain focused tests with this usable checkpoint.

### B — Durable timing report

- [x] Red-test acoustic/confirmation separation and exact Scribe end evidence;
  fixtures include committed segment before empty partial, outstanding draft,
  forced commit, duplicate empty partial and manual commit acknowledgement.
- [x] Define typed observations, run/turn schema, clock mapping, correlation and
  quality reasons. Replay timestamped PCM plus provider events into one report;
  cover end receipt arriving before the observer confirms the boundary.
- [x] Implement Calls ports and Persistence migration, constraints/indexes and
  revision/idempotency rules; test fresh and populated migration paths.
- [x] Add separately bounded asynchronous persistence, restart-readable reports,
  run coverage, cursor reads and valid-only aggregates. Keep publication independent.
- [x] Prove two-tenant denial, wrong incarnation, late revisions, call deletion,
  duplicate/conflicting delivery, missing run and DB outage behavior.
- [x] Provide a reproducible fixture/replay command and document clock assumptions;
  demonstrate one complete and one intentionally incomplete stored report.

### C — Passive configured call

- [ ] Instrument socket receipt and actual adapter settlement with monotonic
  timestamps, distinguishing committed text from provider end evidence. Record
  effective acknowledged settings and optional manual-commit send evidence.
- [ ] Add independent accepted-audio observation preserving per-source sample
  identity and transport receipt mapping; normalize only the observer copy.
- [ ] Reuse timestamped probability/sample evidence from existing operational Silero
  when present; otherwise start one isolated benchmark-only stream. Preserve
  operational reset/failure semantics, report gaps and record inference provenance.
- [ ] Prove exactly one inference execution per eligible source frame with call-spec
  VAD on and benchmarking on. Cover the full on/off matrix, mid-call enable/disable,
  source replacement, model/epoch compatibility and late results. Disabling diagnostics
  must not cancel/reset operational VAD or alter its control trace.
- [x] Add durable default-off app setting, dedicated admin/superadmin authorization,
  revision conflict handling and update audit. Test member/custom-role/machine denial
  through direct requests and preserve superadmin-only installation URL controls.
- [ ] Build the Installation Diagnostics section and Benchmark using Silero VAD toggle with saved/applying/error states and
  role-appropriate navigation. Verify persistence across reload, failed saves,
  stale concurrent edits and desktop/mobile keyboard operation in rendered Chrome.
- [ ] Add isolated supervision/capacity and versioned settings projection. Specify
  bounded cross-node propagation/leases, byte/count limits, concurrency, inference
  timeouts and retry/drain deadlines. No resource initialization gates calls.
- [ ] Prove on/off transitions for active/new calls, unknown settings, DB outage,
  stale enabled cache, restart, worker disconnect and re-enable. Environment/call
  options cannot bypass off; stop observation and queued audio on revocation;
  preserve only pre-disable summaries and distinguish partially observed turns.
- [ ] Red-test saturation, observer crash/hang, absent model, DB failure and teardown;
  compare identical provider bytes, commits and production control traces on/off.
- [ ] Capture matching text/audio landmarks without intercepting output or delaying
  model dispatch; handle silent/tool-only responses, interruption and multi-agent routing.
- [ ] Demonstrate a configured Scribe fixture call persists the report, including
  late confirmation after turn end and call termination while diagnostics drain.

### D — Latency details UI

- [ ] Add Calls-backed authorized diagnostic reads to Console and typed core report
  state; lazy fetch when opened, bounded refresh while live, cursor paging and
  revision-safe updates. Diagnostic read failure must not fail the conversation.
- [ ] Build the collapsed section and per-turn breakdown with quality explanations,
  partial stages and existing authorized transcript links. No raw benchmark timeline events.
- [ ] Cover old calls, disabled/unsupported capture, pending/late rows, incomplete
  coverage, denied reads, storage outage/retry and zero valid samples in fixtures/tests.
- [ ] Verify summaries use all report rows, exclude invalid durations, and preserve
  units/provenance; prevent pure-inference or remote-hearing labels.
- [ ] Inspect desktop/mobile Chrome, keyboard/focus, loading/error and large report
  states in both hosts; keep technical detail opt-in and ordinary messages readable.

### E — Isolation and accuracy

- [ ] Replay labelled caller-only audio with pauses, quiet tails, noise, echo,
  overlapping agent speech and resumed speech. Quantify signed/absolute endpoint
  error and incomplete rate; model frame size is not an accuracy guarantee.
- [ ] Verify loss/reordering, resampling and source/clock resets for WebRTC/Telnyx;
  uncertain segments remain invalid, not stitched into plausible timing values.
- [ ] Stress deterministic on/off calls with slow inference, full queues, writer
  crashes, blocked storage and repeated settings revocation/re-enable/teardown. Check bounded retained
  bytes, tasks, mailboxes, retries and absence of call-control differences.
- [ ] Establish before running load: hardware, concurrency, duration, warm/cold
  runs and numerical CPU/memory/p95 latency regression budgets. Run repeated
  paired on/off measurements; publish measured results and limits. Any missed
  budget blocks enabling the pilot; revise architecture or reduce supported capacity.
- [ ] Record the isolation choice (dedicated BEAM worker versus external inference
  process), native failure limits and evidence. Do not promise protection from
  VM-wide native faults or zero overhead from an in-process task.

### F — Live acceptance and handbook

- [ ] Run tagged existing-runner live acceptance through `bin/livetests run` for
  Scribe/browser and Scribe/Telnyx with ordinary local VAD off/on; keep credentials
  in the established runner and never read or modify its prohibited env file.
- [ ] Include several normal turns, a pause/resume, interruption, tool-only end
  and final hangup. Compare permitted recording/listening evidence with stored
  endpoints, provider evidence and UI; report coverage and error, not universal accuracy.
- [ ] Demonstrate admin and superadmin app-settings enable/disable on active/new
  calls, persisted state after reload, denied member requests, and no collection
  while off. A supported disabled call has unchanged behavior;
  confirm technical events remain hidden by default but inspectable in production UI.
- [ ] Update relevant usage/development handbook pages with configuration, supported
  profiles, timing meanings, privacy, failure/loss semantics and troubleshooting.
- [ ] Pass root format, compile warnings-as-errors, strict Credo, default tests and
  unused-lock checks; run Lean if speech/source state machines change. Run relevant
  frontend/core checks and finish rendered verification. Required unavailable live
  or browser evidence leaves the checkpoint open with a recorded blocker.
- [ ] Synchronize milestone tasks, acceptance evidence, labnotes and index. Commit
  only when requested; deployment is a separate operation, not this milestone's exit.

## Verification discipline

Run `bin/setup` before implementation in each checkout. Each behavior task starts
with the smallest failing project-owned contract test from its owning child, then
implementation and focused green checks. Keep each checkpoint's tests, code and
documentation together. Use controlled clocks/acknowledgements, supervised processes
and monitors, not sleeps/liveness probes. Network tests stay in the tagged lane.
Run the repository's five root completion commands for code/dependency changes;
source-cutover/speech state-machine changes also require `bin/verify-lean`.

## Design review — separate from implementation

Local source/dependency review completed 2026-11-19; no independent-agent review
or implementation acceptance claimed. Resolutions:

- Corrected earlier proposal's conflation of transcript commit with provider end.
- Split timeline filtering (A) from benchmarking so a useful fix can ship early.
- Kept event data, Usage and immutable publications intact; filtering is presentation.
- Added run-level coverage because absent rows cannot distinguish disabled capture
  from observer/storage loss; no promise that outage counters always persist.
- Added revision/deletion/tenant contracts, clock provenance, late correlation,
  byte-bounded independent queues and explicit unsupported/legacy behavior.
- Placed this milestone before pending voice features: it consumes completed
  foundations and can supply latency evidence without a circular dependency.
- User clarification: Installation → Diagnostics → Benchmark using Silero VAD
  is the sole enable authority; reuse operational inference without duplicate model
  execution, preserving resets and reporting incomplete evidence. Editable by
  admin/superadmin only. Replaced the earlier host-option/pilot-allowlist proposal;
  added active-call revocation, partial-start and cache-expiry contracts without
  widening existing superadmin-only installation URL authority.
- Explicitly left exports, cross-provider leaderboards, automatic tuning,
  microphone capture timing, full native STS and guaranteed delivery out of scope.

No code, migrations, runtime configuration or UI behavior changed during planning.
All implementation boxes above remain unchecked until their evidence exists.

## Implementation evidence — checkpoint A

Canonical archive kind now survives Console JSON decoding into shared core/react
views. Technical events defaults off for the seven specified kinds; records and
Usage remain unchanged. Unknown/legacy activities stay visible. Filtered DOM pages
contain at most 100 items; the existing full-history endpoint is unchanged.
Canonical source ordering survives timestamp ties. Live views follow newest pages
unless the operator explicitly browses earlier history.

Red/green evidence covers presentation, decoding, classification, pagination and
equal-timestamp ordering. Astra xhigh reproduced initially-connected and
ready-to-connected pagination failures with failing tests; both are fixed and
retained. Re-review returned no remaining findings. Shared UI suite: 50 passing;
Console frontend suite: 1,163 passing; final affected frontend tests: 22 passing;
presenter suite: 16 passing. Workspace and Console typechecks pass.

Headless Chrome via agent-browser verified Workbench/debug and admin call details
on desktop/mobile, default-hidden/technical-enabled states, keyboard filters and
page controls. Format, warnings-as-errors compile and strict Credo pass. Initial
umbrella run exited 143 without a result; the persistent rerun completed with
zero failures (exit 0), followed by a passing unused-lock gate (exit 0).
Checkpoint A is complete; deployment waits for B–F.
See [implementation labnotes](../20261119-0145-implement-passive-diagnostics.md).

## Checkpoint B partial storage evidence — 2026-11-19

Timing foundations and the durable storage adapter are implemented and independently
reviewed by Astra xhigh. The full runnable B slice remains incomplete: bounded async
writes, coverage classification, exact Scribe replay and the fixture command are open.

Storage passes 14 focused tests, including real two-tenant denial, wrong room/source/
incarnation, missing parent, stale/conflicting revisions, call-deletion cascade,
terminal run reopening, bounded cursor pages and full-report profile-separated
aggregates. An unavailable Postgres connection returns a diagnostic error. Neutral
records pass 10 focused tests. Reviewer regressions for 256-byte identifiers and
second-precision UTC timestamps were reproduced red and retained green; non-UTC
anchors are rejected before persistence. Final storage review returned no findings.

The final migration passed fresh and populated-upgrade checks in isolated test
databases; separate-process verification preserved the existing admitted call.
Root format, compile and Credo pass; full umbrella verification remains in progress.
No runtime capture, settings UI, async storage or deployment is claimed by these checks.

## Checkpoint B partial asynchronous-writer evidence — 2026-11-19

The separate writer reserves count and retained-payload bytes before non-suspending
admission. In-flight work and retries retain reservations; execution and drain
have finite deadlines. Linked helpers bound dependency startup waits, and a shared
pool admission gate prevents unresolved starts accumulating across writer lifetimes.
Unknown startup permits remain reserved until full pool restart. This deliberately
degrades diagnostics without changing calls.

Sixteen diagnostics tests pass, including reviewer-proven backing-binary retention,
blocked admission, and cross-writer queued-admission regressions. Astra xhigh final
review is clean. Full Calls suite: 418 tests, zero failures. Format, compile, Credo
and unused-lock checks pass. The pool is not
yet wired to live settings/capture. Coverage classification and deterministic replay
remain open, so the combined asynchronous-report checklist item stays unchecked.

## Checkpoint B replay and coverage evidence — 2026-11-19

The offline vertical slice now writes complete and intentionally incomplete reports
through the separate bounded writer and reads them in a fresh BEAM. Run
`bin/replay-latency-diagnostics`; the printed `--read DATABASE` invocation reproduces
the durable read. The synthetic complete result is 300000 us; missing audio produces
a null acoustic duration and incomplete coverage. Both retain independent provider
stages. The fixture creates zero ordinary call facts and uses an isolated local
test database, real pinned Silero inference, and an in-memory Scribe transport.
These logical fixture offsets are not measurements of live provider latency.

Combined engine diagnostics: 38 tests, zero failures. Calls diagnostics/records:
32 tests, zero failures. Persistence storage: 15 tests, zero failures. Format,
warnings-as-errors compile, strict Credo and unused-lock checks pass. Astra xhigh
reproduced stale manual-flush correlation and duplicate PCM inference errors; both
regressions are retained and green. Final review is clean and independently verified
the fresh-process stored report and remote-host rejection. The final umbrella test
rerun is pending; earlier runs are not claimed as acceptance for this source state.

The B tasks above describe the completed offline report contracts. Live capture,
settings, production transport timing, output correlation and live accuracy remain
C–F work. No setting has been enabled and no deployment has occurred.

## Checkpoint C partial settings-boundary evidence — 2026-11-19

The isolated Identity settings domain accepts only admin/superadmin browser
sessions, validates boolean and revision inputs, and preserves stale-save conflicts.
Five focused tests pass and Astra review is clean. The dedicated persistence port
requires current stored role/session validation; that adapter, migration, routes
and Installation UI remain unimplemented, so the settings checklist stays open.

The isolated Engine settings lease expires three seconds after an authoritative
read starts. Seven tests cover expiration, stalled/reordered reads, revision
conflicts and clock mismatch. A reviewer-proven conflict-history regression was
fixed and retained. The projection, cross-node invalidation and audio admission
checks remain unimplemented; no live collection can be enabled by these modules.

## Checkpoint C partial durable-settings evidence — 2026-11-19

A dedicated default-off singleton now persists the boolean, revision, updater
public identity and timestamp. The adapter revalidates current stored built-in
roles and browser sessions on reads and writes and atomically includes an audit
event. Current-revision no-ops are idempotent; stale no-ops conflict. Failed audit
insertion rolls back the setting and revision. Missing singleton rows fail closed.

Eight focused tests pass, including a reviewer-proven session-expiry race under
real row-lock contention. Expiry is rechecked after all locks. Fresh and upgrade
migration paths were exercised in isolated local databases. Final review and
full Persistence checks are in progress. Console routes, runtime projection and
Installation UI remain unwired, so C's combined settings task remains unchecked.

## Checkpoint B root completion evidence — 2026-11-19

The fixed-source B umbrella run completed with exit 0. All application suites
passed, including Engine2562, Calls424, Gateway891, Persistence566 and Console585
tests (their tagged integration/live exclusions remain in place). Together with
the passing format, compile, Credo and unused-lock checks, this closes B's root
verification. The subsequent isolated C settings code has its own focused review
and checks; this run does not establish live settings or capture acceptance.

Durable settings final evidence: Astra xhigh re-review clean; full Persistence
suite574tests/0failures (68excluded); format, compile warnings-as-errors, strict
Credo and unused-lock checks pass. The local worktree test database migration
completed after B's umbrella run. No runtime enable authority is wired yet.

## Checkpoint C settings API evidence — 2026-11-19

The configured Console API now exposes session-only GET/PATCH
`/api/installation/diagnostics`. An exact route guard, domain validation and current
stored authority protect it. Explicit Authorization headers are rejected by the
existing product-session pipeline; custom roles cannot read or write. Saved values
survive subsequent requests, stale revisions return409, invalid values422, and
unavailable storage503. Installation page server access admits admins/superadmins;
URL APIs retain their superadmin-only route and domain guards.

Five new endpoint tests pass with the existing six setup/URL/account tests. Full
Console suite590tests/0failures (127excluded); static root gates pass. Astra xhigh
review is clean. This completes the durable settings/API task, not the frontend
section or live projection. No frontend/browser acceptance or active capture is
claimed; those separate C tasks remain unchecked.
