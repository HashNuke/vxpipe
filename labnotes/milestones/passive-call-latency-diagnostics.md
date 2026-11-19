# Passive call latency diagnostics and readable timelines

Status: records/replay extension implemented; room-service migration pending, 2026-11-19.
A, B and existing D functionality are implemented. C must migrate from agent-selected
background discovery to participant-owned observation managed by a room service.
The new D segment/participant extensions, C migration, E and F remain incomplete.
The index owns implementation order. Earlier checkpoint notes describe the old path.

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
no live measurements or deployment are claimed by the offline foundation.

User scope correction, 2026-11-19: do not use real Telnyx numbers, run live Telnyx
provider tests, or change Telnyx code for this milestone. Live acceptance is limited
to the VAD/Scribe browser path. Existing local Telnyx fixtures may run as part of the
unchanged umbrella suite; they are not real calls or evidence of live Telnyx support.

## Architecture revision — participant-owned VAD, 2026-11-19

This revision follows the user's request to rethink the milestone. It supersedes
agent-selected source discovery and agent-owned acoustic runs in the earlier
implementation notes. Those notes remain historical evidence, not acceptance of
the revised architecture. This is a specification change; the runtime migration
has not reached room-service cutover. Implementation resumed after the user reviewed and
updated this plan; the migration order below now governs the next checkpoints.

### Local VAD and provider endpointing are different signals

**Operational VAD means local Silero already running on the human participant's
accepted STT input.** It does not mean ElevenLabs/provider-side VAD, transcript
commits, provider turn markers or the agent's speech-to-speech capability.

Observe local acoustic speech-start and speech-end boundaries, sample positions,
confirmation times and reset/gap evidence. These are acoustic segments: a pause
can create multiple segments inside one provider/canonical conversational turn.
Do not make local VAD decide when STT commits or the room ends a turn. Retain the
existing separate provider/adapter/room landmarks to measure their delays against
local acoustic evidence. Missing local end evidence remains missing even when the
provider has emitted an end marker.

### Target ownership and mode selection

One optional **room diagnostics service**, owned by the room incarnation, manages
observation for its STT-using human participants. It selects each input independently:

| Participant input | Diagnostic behavior while collection is enabled |
| --- | --- |
| STT with local operational Silero | Subscribe to existing Silero evidence; no second model execution. |
| STT without local operational Silero | Room service owns one passive Silero observer for this participant's accepted input stream. |
| No STT input, including native speech-to-speech-only input | No observer and no model work. |

The rule is the human's STT input, whatever the response side is. A human whose STT
also drives an STS agent's `external`/`hybrid` turn control (`activity_agent_id`
set) is still an STT-using participant and is observed like any other; the STS
model's own audio is never observed. For these sessions, routing changes can
replace the STT session (`SpeechToTextDemand.activity_authority_changed?/4`); that
is a real STT replacement and ends the run with an explicit boundary, so transfer
continuity is only claimed when the STT session survives. Input rows exist for
completed canonical STT turns; response stages stay nullable.

Two humans with separate STT streams have two independent VAD states. One human
routed to multiple agents still has one VAD state for that accepted STT stream.
Key ownership by room incarnation, participant, accepted connection/source and STT
allocation; never by selected response agent. Preserve existing source-policy
permissions before observing audio. Do not combine participants or run VAD over
mixed room output, agent audio or the TTS playback stream. If a participant has
multiple simultaneous independently admitted STT sources, each needs its own
source identity and detector state; never merge their PCM or recurrent state.

A response-agent transfer alone does not restart VAD, detach observation or create
an acoustic run. Actual input/STT replacement, clock discontinuity, local VAD mode
change, revocation or participant departure does create an explicit boundary.
Response correlation remains per canonical input and output command; a turn may
have no response or multiple destinations without changing input ownership.

Continuity also requires input-scoped policy authority. The current audio tap closes
on any global room-policy revision, even when STT preserves its allocation and the
source remains permitted. Replace that blanket revision fence with the
participant-scoped intervals STT already tracks: fence on the tuple (STT allocation
generation, the source's `Snapshot.interval/3` for `:speech_to_text`, and for
`:audio_input`), reusing the helpers behind `State.delivery_intervals_current?/5`.
Apply the same tuple to `AudioTap` guard/offer/policy_change, the `SourceDiscovery`
arm/probe/validate path and `SpeechToText.attach_diagnostics/5`, which all compare
the global `policy.revision` today. Unrelated presence/routing changes must not
reset the stream. An interval change, source replacement or an unprovable authority
change must fail closed. Snapshots with `intervals: nil` fall back to the global
revision and therefore stay fail-closed. Never preserve continuity merely by
ignoring policy updates.

The room service owns subscriptions and per-source lifecycle, not inference inside
RoomAuthority. `RoomIncarnationSupervisor` is `one_for_one` with default intensity
and `auto_shutdown: :any_significant`, so add exactly one `restart: :temporary`,
non-significant diagnostics child supervisor with its own explicit restart
intensity. Inside it the service may restart and reconcile; once its own intensity
is exhausted the subtree stays down and the rest of the call reports incomplete
coverage. Initialization must be cheap and asynchronous: model/DB readiness is
never a room readiness resource. One VAD instance means independent stream state,
not one model-weight copy or operating-system process per participant.

Per-source `SourceWorker` processes start inside that room diagnostics subtree so
room teardown bounds their lifetime. Admission stays node-wide: every worker,
including reuse-mode workers that run no inference, takes a slot from the existing
`AttachmentLease.gate` sized by `maximum_sources` (default 16, at most 32);
benchmark-only workers also take `InferenceAdmission` from the shared inference
pool, and model loading stays outside the room. When no slot is available, record
an explicit `capacity_unavailable` coverage reason; bounded reconciliation may
attach the source later when a slot frees, with the late start shown as partial
coverage. Two rooms contending at the cap must both remain correct; add a per-room
share only if that test shows one room can starve the others.

Umbrella dependency direction is preserved: the collector factory and node source
pool are composed by `vxpipe_calls` (`Calls.Diagnostics.Supervisor`), which depends
on the call engine, so the room service must not reference Calls. It resolves the
node-level `SourceSupervisor` (with its injected collector) by registered name at
reconciliation time. When that port is absent or down, the service reports
`unavailable` coverage and does nothing else.

Use room-local lifecycle notifications plus a bounded current-source snapshot to
handle startup, enable on an existing room, join/leave and reconnect races. Reconcile
on service restart against authoritative accepted sources. Retire the node-wide
room-scanning coordinator after cutover; do not keep two competing owners. A
settings projection may remain shared infrastructure. Normal call lifecycle events
must not synchronously wait for diagnostic attachment, inference or persistence.

For local Silero reuse, existing `InferenceTap` already exports probabilities,
sample mapping and resets. Reuse that work and derive both boundaries without
re-running inference; publishing already-computed local boundary evidence is also
acceptable if it preserves sample/epoch provenance. Preserve operational resets
and failures. Provider settlement currently resets operational Silero, so complete
local endpoints are not always available; never fill these gaps with a duplicate
fallback detector. If local Silero fails while configured, diagnostics reports the
gap rather than silently switching modes or changing operational failure handling.

Acoustic segments are attached to the canonical turn whose source interval contains
them, bounded per turn with an omitted count. Segments outside every turn (noise,
uncommitted or dropped speech) go into a bounded per-run unattached-segment record
with its own omitted count; they are never dropped silently or promoted to turns.

The fallback observer runs continuously across provider turn settlements. Its
acoustic state belongs to the input stream until a real source/lifecycle boundary.
When the local Silero mode changes, fence the old subscription/work before selecting
the new mode; permit no overlap of duplicate inference for the same input.

Retain the existing default-off installation setting and authorization as the
collection gate. Existing operational Silero continues independently while debug
collection is off. This revision does not authorize always-on debug persistence,
provider configuration changes, a new provider, or speech-to-speech integration.
Eligibility is determined by the human's accepted STT input, not by requiring a
selected LLM/TTS agent or rejecting an entire mixed room because it contains STS.
No speech-to-speech model, input or output is ever a diagnostic source.

### Review of implemented work and required changes

Source review covers the A–F checkpoints and the committed implementation through
`f46267e4`; the uncommitted configured crash/hang tests are unfinished work, not
accepted milestone evidence. No existing implementation changes were discarded.

| Area and source evidence | Disposition and required work |
| --- | --- |
| A: Console presenter, shared core/react technical-event filtering and rendered host fixtures | Keep. Readable timelines and opt-in technical events are independent of observer ownership. |
| B: `AudioTimeline`, `SampleClock`, `ActivityBoundary`, replay/correlation, Calls diagnostic records and Persistence adapters | Keep clock, revision, isolation and storage contracts. Current report emphasizes acoustic end; explicitly carry speech-start/end segment evidence through durable records and authorized reads. Add a versioned additive representation with bounded segment count, omitted-count/loss reasons and old-row compatibility; reopening this extension does not erase existing B evidence. |
| C: `InferenceTap`, `AudioTap`, `SourceWorker`, `InferenceAdmission`, `CaptureHandoff` | Keep local reuse, per-stream state, bounded handoff and shared inference admission. Adapt lifecycle to the room service. `AudioTap` guard/offer/policy_change, `SourceDiscovery` and `attach_diagnostics/5` currently fence on global policy revision; replace this with the source's STT/audio-input interval tuple before claiming transfer continuity. Keep reset/late-result fences and no-duplicate-inference tests. |
| C: `SourceCoordinator`, `SourceAttachment`, `SourceDiscovery`, `RoomAuthority.DiagnosticSources`, `SourceSupervisor.eligible_agent?/1` | Replace global room discovery/agent admission with room-owned STT source registration/reconciliation. `DiagnosticSources` currently requires a selected text agent and rejects room-level STS; `SourceAttachment.current?/1` compares agent identity. Remove those as acoustic eligibility/lifetime conditions. Retain useful source proofs and attachment fencing only where the room-local path needs them. |
| C: `RoomIncarnationSupervisor` and Calls diagnostics composition | Add one temporary, non-significant room diagnostics subtree hosting the service and its source workers; keep node-wide admission gate, bounded inference/settings and asynchronous Calls collector/writer infrastructure, reached by registered name. Compose the room service and stop starting the old coordinator in the same checkpoint. No generic room-service framework is required. |
| C: `ProviderTiming`, `InputTurns.observe_completion/3`, `ResponseTiming`, `LiveReport` | Keep distinct provider and response landmarks. Remove the diagnostic completion gate requiring a text capability and excluding room-level STS: `LiveReport` currently creates rows only from completion packets. Persist accepted canonical STT input timing even without an LLM response; leave response stages nullable. Preserve actual dispatch/control eligibility. Correlate late responses to participant-owned runs rather than making agent identity own the stream. |
| C: installation settings/API/projection and bounded polling UI | Keep default-off, roles, saved revisions, fail-closed leases and finite polling. Room service consumes changes. Effective distributed status remains unresolved; do not add a new cluster-membership system solely for this migration or claim applied from a saved value. |
| C: configured matrix and transfer tests | Preserve provider-byte, no-extra-commit, reuse, pending/late, playback-ack and drain assertions. Replace the latest transfer test's expected diagnostic retirement/rediscovery with continuous same-input observation across transfer. Add two-STT-participant and STT-without-selected-agent cases. The uncommitted crash/hang parity tests use `discover_with_audio`/`SourceCoordinator.status`: keep them as old-path evidence until cutover, then port them with their provider-byte and turn/output assertions unchanged. |
| D: authorized report APIs, core paging, collapsed diagnostics and browser stories | Keep. Extend contracts/stories for acoustic starts/ends, participant-owned run continuity and two distinct STT participants; do not create per-agent STT rows. Existing rendering evidence does not verify these new states. |
| E: isolation, accuracy and overhead acceptance | Still open. Measure the new room-service path, both reuse and fallback, multiple participants and operational-reset gaps. Prior bounded-worker tests remain component evidence, not measured end-to-end overhead. |
| F: live acceptance, handbook and final gates | Still open. Run Scribe/browser only, local Silero off/on, after migration. Update ownership docs and run full gates only after milestone implementation; no Telnyx changes/live tests or early deployment. |

### Migration order and acceptance gates

These requirements govern the revised implementation; completion is tracked below.
Keep A and unaffected B/D checks as historical successes, with affected C checks
and explicit B/D extensions tracked separately. Do not restart finished unrelated UI/storage work.

The order keeps exactly one owner per input at every checkpoint: the room service
is exercised directly in tests and is never composed beside the old coordinator.

1. Input-scoped fence. Replace the global-revision fence in `AudioTap`,
   `SourceDiscovery` and `attach_diagnostics/5` with the STT/audio-input interval
   tuple. Red-test that an unrelated presence/routing revision preserves the tap and
   that an STT or audio-input interval change closes it; keep `intervals: nil`
   fail-closed. This is safe under the current coordinator, which still retires on
   agent change.
2. Segment representation. Red-test bounded acoustic start/end evidence: multiple
   segments in one canonical turn, unattached noise segments in a per-run record,
   omitted counts/loss reasons and legacy rows.
3. Room service, tested directly. Build the temporary diagnostics subtree, the
   service, room-local notifications plus bounded snapshot reconciliation, workers
   inside the subtree, node-wide gate admission with `capacity_unavailable`, and
   registered-name resolution of the node pool. Test reuse and fallback, all local
   Silero/collection combinations, mid-call mode changes, join/leave, reconnect,
   service crash and intensity exhaustion with the call still open,
   disable/re-enable, stale work, absent Calls pool and two rooms at the cap. No
   duplicate inference or operational reset/control changes.
4. Cutover in one checkpoint. Compose the room service into
   `RoomIncarnationSupervisor`, stop starting `SourceCoordinator`, then delete the
   scan/discovery-by-agent path (`SourceCoordinator`, agent checks in
   `SourceAttachment`, `DiagnosticSources` and `SourceSupervisor.eligible_agent?/1`).
   Port the configured tests, including the crash/hang parity tests.
5. Eligibility and continuity on the new path. Derive eligibility from accepted
   human STT sources, including STT that drives STS turn control. Remove the
   diagnostic-only gate in `InputTurns.observe_completion/3`; require persisted
   canonical STT input rows with nullable response stages in no-agent and
   mixed-room tests, not merely worker startup. Prove two humans are isolated and
   no-STT sources allocate nothing. Preserve acoustic continuity through
   response-agent transfer with input continuing during the transfer, matching late
   output, missing endpoints after operational resets and bounded teardown. Re-run
   configured failure parity. Do not change model dispatch or operational turn
   acceptance to make diagnostic tests pass.
6. Persistence/API/UI. Extend authorized reads and both hosts' fixtures for
   participant-owned runs, segments and two STT participants; inspect both hosts.
7. Complete the existing E/F accuracy, load, browser/live, handbook and final gates
   against the new path. Review each checkpoint; only then consider deployment.

Design review: the selected architecture makes room lifecycle and participant STT
identity authoritative. Rejected alternatives are agent-owned observers (unnecessary
transfer resets), a second Silero beside operational Silero (duplicate work),
provider markers standing in for acoustic VAD (different evidence), and inference
inside RoomAuthority (call-blocking risk). Existing bounded queues and async writers
remain necessary; a room service changes ownership, not permission to block calls.

Independent scoped Astra design review is clean after adding the source-proven
policy-revision and input-completion instrumentation dependencies. This is design
acceptance only; no reopened implementation task is checked by this review.

A follow-up source review of this revision
([labnotes](../20261119-1452-latency-plan-review.md)) added the concrete fence
tuple, supervision shape, worker placement and capacity, Calls port resolution,
STT-for-STS-turn-control boundaries, unattached segments, the single-owner migration
order and the split of retained versus reopened C checks. Design changes only; no
implementation task is checked by it.

## Prerequisites and design sources

The current ownership decision is recorded in
[Participant VAD observation owned by the room](../../docs/design/participant-vad-room-service.md).
It supersedes conflicting ownership language in the earlier design/evidence below.

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
- [Implemented runtime limits](../../docs/design/latency-diagnostics-runtime-limits.md): authority expiry, resource bounds and verification limits.
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

Eligibility follows each human participant's accepted STT input, as specified in
the architecture revision above. A selected LLM/TTS agent is not a prerequisite.
Native speech-to-speech-only inputs have no STT source to observe; mixed rooms do
not suppress otherwise eligible STT participants. Never observe agent output audio.

First supported live profile: human ElevenLabs Scribe v2 realtime input over browser
WebRTC. Live Telnyx acceptance is excluded by the user's scope correction. Exercise
operational local VAD both off and on without changing it. Manual/historical Scribe
is covered by protocol fixtures; label unsupported
profiles explicitly. Native speech-to-speech-only input is outside this scope. Do not claim a new live
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
| Acoustic speech start | Local Silero onset sample and mapped receipt-time estimate, with confirmation time and segment identity. |
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

When no operational Silero exists, the room diagnostics service owns one isolated
benchmark-only stream per accepted STT participant/source while
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
| C — Passive configured call | Room-owned, per-STT-participant observation produces stored timing without control effects. | B; timing correlation fixtures. |
| D — Latency details UI | An authorized live or ended call exposes a truthful collapsed timing report. | A–C; fixtures may start after B. |
| E — Isolation and accuracy | Failure/load tests and labelled replay establish honest error and overhead bounds. | B–D. |
| F — Live acceptance and handbook | Scribe/browser evidence plus documentation and root gates. | A–E. |

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

- [x] Extend the existing versioned records/replay with bounded acoustic speech-start
  and speech-end segment evidence, confirmation provenance and reset/loss reasons;
  preserve old rows and null/partial semantics without conflating segments with turns.
  Bound segments per turn with an omitted count, and keep segments outside every
  turn in a bounded per-run unattached record with its own omitted count.

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

Migration tasks (revised architecture; ordered as in the migration steps above):

- [x] Replace the global policy-revision fence in `AudioTap`, `SourceDiscovery` and
  `attach_diagnostics/5` with the source's STT allocation generation plus
  `:speech_to_text`/`:audio_input` intervals. Unrelated revisions preserve the tap;
  interval change or `intervals: nil` authority change closes it.
- [ ] Build the temporary, non-significant room diagnostics subtree with its own
  restart intensity, the room service and room-local notification plus bounded
  snapshot reconciliation. Intensity exhaustion leaves the call open with
  incomplete coverage.
- [ ] Start source workers inside that subtree, admitted through the node-wide
  `AttachmentLease.gate` and `InferenceAdmission`; record `capacity_unavailable`
  and attach late as partial coverage when a slot frees. Test two rooms at the cap.
- [ ] Resolve the Calls-composed node pool and collector by registered name; with
  the port absent or down, report `unavailable` coverage and do no work.
- [ ] Re-prove reuse/fallback through the room service: one inference execution per
  eligible frame, all local Silero/collection combinations, mid-call mode change,
  join/leave, reconnect, disable/re-enable and stale/late work.
- [ ] Cut over in one checkpoint: compose the room service, stop starting
  `SourceCoordinator`, then remove scan and agent-identity checks from
  `SourceAttachment`, `DiagnosticSources` and `SourceSupervisor.eligible_agent?/1`.
  Port the configured tests, including the crash/hang parity tests.
- [ ] Derive eligibility from accepted human STT sources, including two participants,
  no selected agent and mixed-room cases; no work for sources without STT. STT that
  drives STS `external`/`hybrid` turn control is observed, and its session
  replacement on routing change produces an explicit run boundary.
- [ ] Decouple diagnostic room-completion instrumentation from selected text/STS
  agent gates; prove durable canonical input timing with nullable response stages
  for no-agent and mixed-room STT without changing operational dispatch.
- [ ] Preserve acoustic observation across agent-only transfers with input
  continuing during the transfer; isolate real source, mode and settings
  transitions and fence late results without duplicate inference.

Retained component evidence (from the earlier path; still valid, see the dated
evidence sections):

- [x] Instrument socket receipt and actual adapter settlement with monotonic
  timestamps, distinguishing committed text from provider end evidence. Record
  effective acknowledged settings and optional manual-commit send evidence.
- [x] Accepted-audio observation inside the STT capability preserves per-source
  sample identity and transport receipt mapping and normalizes only the observer
  copy. Its fence is replaced by the first migration task.
- [x] `InferenceTap` reuse of operational Silero probabilities/samples/resets and
  the isolated benchmark-only `SourceWorker`, with reset/failure gaps and inference
  provenance. Lifecycle ownership moves to the room service above.
- [x] Component proofs of one inference execution per eligible source frame,
  on/off matrix, source replacement, model/epoch compatibility and late results;
  disabling diagnostics leaves operational VAD and its control trace unchanged.
  End-to-end re-proof on the room-service path is the reuse/fallback task above.
- [x] Add durable default-off app setting, dedicated admin/superadmin authorization,
  revision conflict handling and update audit. Test member/custom-role/machine denial
  through direct requests and preserve superadmin-only installation URL controls.
- [x] Versioned settings projection, fail-closed leases, byte/count limits,
  inference timeouts and retry/drain deadlines; no resource initialization gates
  calls. Supervision and capacity move to the migration tasks above.

Open tasks (unchanged in scope; verify on the room-service path):

- [ ] Build the Installation Diagnostics section and Benchmark using Silero VAD toggle with saved/applying/error states and
  role-appropriate navigation. Verify persistence across reload, failed saves,
  stale concurrent edits and desktop/mobile keyboard operation in rendered Chrome.
- [ ] Specify bounded cross-node settings propagation and effective-status reporting
  without a new cluster-membership system; never report applied from a saved value.
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

- [ ] Extend authorized reads and both hosts' fixtures for participant-owned runs,
  acoustic start/end evidence and two STT participants; preserve collapsed defaults
  and verify transfer continuity and legacy-row display in rendered Chrome.

- [x] Add Calls-backed authorized diagnostic reads to Console and typed core report
  state; lazy fetch when opened, bounded refresh while live, cursor paging and
  revision-safe updates. Diagnostic read failure must not fail the conversation.
- [x] Build the collapsed section and per-turn breakdown with quality explanations,
  partial stages and existing authorized transcript links. No raw benchmark timeline events.
- [x] Cover old calls, disabled/unsupported capture, pending/late rows, incomplete
  coverage, denied reads, storage outage/retry and zero valid samples in fixtures/tests.
- [x] Verify summaries use all report rows, exclude invalid durations, and preserve
  units/provenance; prevent pure-inference or remote-hearing labels.
- [x] Inspect desktop/mobile Chrome, keyboard/focus, loading/error and large report
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
  Scribe/browser with ordinary local VAD off/on; do not run live Telnyx tests. Keep
  credentials in the established runner and never read or modify its prohibited env file.
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

## Historical implementation evidence

The following dated checkpoints record what passed before the participant-owned
architecture revision. They do not override the revised contracts or reopened
checklist above. Keep their component evidence and replace old ownership assertions
as the migration lands.

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

## Checkpoint C Installation UI evidence — 2026-11-19

Installation now contains Diagnostics and the exact Benchmark using Silero VAD
control. Admins/superadmins have production and fixture navigation; admins see no
URL controls and never fetch URL settings. The production React route saves with
CSRF and revision and rereads on remount. Errors preserve last-confirmed state;
conflicts and uncertain save outcomes require reload before another write.

A reviewer-proven lost-response case was fixed: a committed write with a lost
response is no longer falsely described as unchanged. The regression is retained.
Affected frontend tests37/0 and typecheck pass; navigation endpoint22/0; Astra
xhigh review is clean. Desktop/mobile Chrome fixtures cover role separation,
keyboard toggle/reload and failed-save layouts. The full frontend fixed-source
rerun is pending. These browser fixtures do not establish real call capture.

The component can render applying/applied status but the API does not yet produce
runtime status. It truthfully shows collection status unavailable in that case.
Projection-backed status and bounded live refresh remain pending, so the combined
C Installation UI acceptance task stays unchecked until that integration passes.

Installation UI checkpoint final evidence: full frontend suite1169/0, affected
lint/type checks pass, and Astra cleanup re-review clean. Runtime-backed applying
status/refresh remains explicitly pending; the combined C UI task is still open.

## Checkpoint C runtime projection evidence — 2026-11-19

Database-backed startup now composes one isolated asynchronous settings reader
with a direct local ETS projection. Polling is at most once per second; read
results expire after one second and enabled leases after three seconds from read
start. A blocked read retains its sole IO slot until completion. Result handling
checks elapsed time independently of deadline-message order. Coalesced invalidation
fences old results; exhausted pool restarts leave diagnostics unavailable.

Focused projection/lease13tests, application/projection12tests and actual store
integration8tests pass. The store integration follows durable off/on/off revisions.
Full Engine diagnostic subset51/0; root static gates pass. Astra xhigh review is
clean, including startup/configuration and snapshot integration. Full umbrella
verification is in progress. Cross-node hints, audio consumers, queue revocation
and truthful UI effective status remain pending; the combined C task stays open.

The broader run has reported an existing idle-room expiry-test failure (nil idle
state), while the same focused test/seed passes alone. Independent review has
reproduced a distinct idle-admission ordering race. This run is not passing root
acceptance evidence; investigation is recorded in the implementation labnotes.

The run finished with only that Engine failure; all other applications passed,
including Persistence575 and Console591 tests. The manually driven expiry test
now establishes idle admission before acknowledgment and avoids its competing
short timer. The isolated full idle-file rerun passes18/0; independent review and
static gates pass. A separate, reproduced production admission race remains
[unresolved](../issues/idle-admission-after-silent-acknowledgment.md). No production
idle behavior was changed. A complete current-source root pass remains a final
acceptance gate; the earlier failed run is not relabelled as passing.

## Checkpoint C capture-admission evidence — 2026-11-19

Capture grants carry a publication epoch and consumers retain a finite lease
deadline; a saved revision or publication epoch alone cannot prove continuity. The
bounded capture handoff reserves count and bytes before detached copying, keeps
in-flight reservations, and rechecks authority at receipt. Its fixed packet
allowlist excludes transcripts and unrestricted metadata. Focused diagnostics59/0
and database snapshot integration8/0 pass; static gates pass, review is pending.

This is not live capture acceptance. Source-policy association, actual workers,
queue draining, reuse taps and provider/response correlation remain open. The
combined C tasks stay unchecked until their runnable configured-call gates pass.

Capture-admission review follow-up: retained malformed-frame and delayed-publication
regressions failed before fixes. Frame admission validates its exact key set.
Observed expiry irreversibly retires the publication epoch; each handoff also
retains and renews its own deadline, preventing queued work from resuming after
unobserved expiry during delayed publication. Checks linearize at their clock
sample, and consumers must recheck before work/results. Diagnostic tests pass62/0;
Astra xhigh re-review is clean (independent focused selection17/0), and root static
gates pass. The active umbrella run has an MCP startup-ack timeout and cannot be
counted as passing. These primitive tests do not complete configured-call C gates.

## Checkpoint C partial Scribe timing evidence — 2026-11-19

Optional internal capture handles now carry socket-callback receipt stamps through
the real continuous Scribe adapter. Nonblank transcript commits remain separate
from provider end evidence; actual canonical turn-end emission has a distinct
stamp. Only fixed bounded metadata reaches the capture handoff. Revocation and
saturation tests preserve ordinary recognition; affected suite82/0 (4excluded).
Astra xhigh review is clean (independent85/0 including additional semantics probes);
root static gates and Lean verification pass. Automatic subscription, manual Scribe,
manual commit sent, room/response correlation and report persistence remain open;
the combined C instrumentation task is not yet complete.

## Checkpoint C partial accepted-audio evidence — 2026-11-19

The STT capability now has an internal allocation/policy/source-fenced observation
attachment. Raw PCM reaches it only after successful provider admission. Policy
changes, source mismatch and capability death revoke old queued evidence; capture
saturation leaves the provider result intact. Automatic observer admission,
decoded-Opus/normalized mapping and operational inference reuse remain pending.
Affected suite99/0, static root gates and Lean verification pass. Astra xhigh
re-review is clean, including retained preparation/discard and rejected-policy
regressions. The combined task stays open pending the complete observer lifecycle.

## Checkpoint C partial operational-reuse evidence — 2026-11-19

Existing ConversationalSTT inference now supports a prospective bounded diagnostic
consumer. It mirrors computed probabilities with per-epoch sample cursors and
reset/failure notices; warmup is excluded and no second inference runs. Revocation
leaves operational onset intact. Mid-stream subscriptions report partial coverage
until a fresh operational epoch, excluding prior in-flight/pending work. Affected
suite88/0; Astra xhigh re-review clean (independent34/0), final static gates pass
and Lean behavior verification passes. Retained adoption, source-admission race
and odd-byte coverage regressions are fixed. Standalone workers, automatic
admission, complete source mapping and the full on/off/source matrix remain open.

## Checkpoint C asynchronous inference admission — 2026-11-19

An explicitly configured diagnostic runtime now supports bounded non-suspending
inference offers. Queued/in-flight jobs share capacity; actual task termination
releases it. Capture authority fences admission, loading, inference and delivery;
revocation polling retires diagnostic jobs without changing the synchronous
operational API. Nested binary views are detached, and the real pinned model
preserves recurrent state across successive offers. Unknown interrupted offers
conservatively retain capacity until runtime restart.

Affected tests95/0; Astra xhigh re-review clean (18focused plus5 lifecycle probes).
Static root gates and Lean pass; the full umbrella suite is running. This supplies
admission for the isolated worker lifecycle; production pool composition,
automatic source workers and transport mapping remain open. Combined C tasks are
still unchecked pending their configured-call acceptance gates.

## Checkpoint C accepted-audio mapping — 2026-11-19

A bounded observer-only timeline now normalizes accepted PCM and verified decoded
Opus copies, preserving original source continuity before resampling. It converts
transport milliseconds to run-relative microseconds, rejects identity/rate and
ordering changes, deduplicates identical PCM, and carries receipt/quantization
uncertainty. Gaps retire prior mappings without assigning expired endpoints new
timestamps; original clock uncertainty survives normalized rounding.

Two reviewer-proved gap/uncertainty regressions and an additional rounding case
are retained green. Affected suite95/0; Astra xhigh re-review clean (independent91/0),
static root gates and Lean pass. The existing umbrella run predates this change.
Automatic source workers, raw Opus decode without an existing decoded copy and
configured-call transport acceptance remain pending; the combined C task stays open.

## Checkpoint C benchmark-only worker — 2026-11-19

A separately supervised source worker now combines bounded capture, accepted-audio
mapping, sequential async model work and private acoustic boundary state. It emits
bounded diagnostic tuples, keeps input reservations through inference, preserves
standalone recurrence across provider settlement, and retires on revocation or
collector saturation. Its first endpoint remains partial; uncertain/missing timing
is nullable. The real packaged model preserves fixture onset4096/end34816 across
partial model windows. Graceful cleanup and crash fencing are separately tested.

Affected suite109/0; Astra xhigh review clean (19independent tests/probes), static
root gates and Lean pass. The preceding umbrella run finished with Cartesia startup
close-reason and Twilio media-harness failures; those remain unresolved acceptance
evidence. Automatic call/source attachment, operational-reuse consumption, raw
Opus decode and collector persistence/correlation remain open. The combined C
worker/isolation and on/off tasks are not yet complete.


LLM-only admission follow-up: the source factory now rejects speech-to-speech,
mixed LLM/STS, human and unknown agent declarations before consulting diagnostic
resources. Eligible LLM capacity and real-model correspondence tests remain green
(11/0); Astra xhigh review is clean and static root gates pass. Automatic capture
and reuse attachment are still pending and must retain this eligibility boundary.


## Checkpoint C reused-inference source correspondence — 2026-11-19

Operational inference evidence now includes its absolute normalized source sample
alongside reset-relative position. Accepted frame continuity is checked without
copying audio or running another detector. Gaps and raw byte input leave mapping
unavailable until a fresh operational epoch; late results retain their original
submission epoch and source position. Provider resets and control remain unchanged.
Affected tests111/0, static gates and Lean pass. Astra xhigh review is clean with
five additional buffering/resampling/reset probes. The earlier umbrella run is
still in progress and does not verify this newer source state. Reuse consumption,
automatic source attachment and report correlation remain open; C is incomplete.


## Checkpoint C reused boundary consumer — 2026-11-19

The existing source worker can now consume operational probabilities without a
model runtime. It waits for matching accepted audio under bounded capture charges,
requires full retained window coverage, and invalidates gaps/missing windows.
Provider resets discard pending old evidence; late retired results cannot enter a
new epoch. Input loss and output saturation retire observation. LLM-only admission
selects reuse without consulting diagnostic inference resources. Actual adapter
integration proves one inference produces operational and diagnostic onset, and
revocation leaves subsequent operational inference running.

A reviewer-proven uncaptured-prefix error is fixed with a retained regression.
Affected tests119/0; static gates and Lean pass. Astra xhigh final re-review is
clean (19focused plus2additional probes). The previous root run finished with
an independently reproduced OAuth repository-shutdown race, now fixed/reviewed
with33focused tests. A new umbrella run is active. Automatic source attachment,
provider/response correlation, report persistence and full configured-call on/off
acceptance remain pending; combined C tasks stay unchecked.


## Checkpoint C running Scribe subscription — 2026-11-19

The existing speech-channel observer request now reaches already-running direct
Scribe sessions and recognizers behind the optional VAD wrapper. Forwarding keeps
the original capture owner/lease; readiness, consumer and generation checks remain.
Sockets update only their optional handoff from their owner. Replacement revokes
old capture without restarting recognition. Fixture wires execute the real receipt
callback with their current subscription state. Inner provider identity is retained;
canonical-turn correlation is not yet implemented.

Affected tests288/0 (5excluded), static gates and Lean pass. Astra xhigh review is
clean (13independent tests/probes). Automatic source discovery/attachment, manual
instrumentation and report correlation remain pending. The prior umbrella run has
a live-inspection projection timeout under investigation and is not passing root
acceptance evidence for this checkpoint. Combined C tasks remain unchecked.


## Checkpoint C provider-to-canonical turn links — 2026-11-19

The optional wrapper now emits reference-only associations from inner provider
allocation/turn to outer canonical allocation/turn, using its existing coordinator
mapping. It covers queued turn drains and both VAD/native-hint orderings, retains
original capture authority, and resets its bounded deduplication on subscription
replacement. Source workers forward these links independently of acoustic work.
Identical transcript text never participates in this association.

Two retained VAD ordering regressions were red before correction. Affected suite
678/0 (9excluded), static gates and Lean pass. Astra xhigh final re-review is clean
(76focused tests and3independent probes). The prior umbrella failure was the now-
corrected live baseline test barrier; a new run predates the final VAD correction.
Room-turn and response association, collector persistence and automatic source
attachment remain incomplete, so the combined C correlation tasks stay unchecked.


## Checkpoint C accepted room-turn timing — 2026-11-19

STT completion now carries its current source capture to the owning room. After
existing identity and active-turn validation, the room records its accepted turn
and command IDs alongside canonical speech references and a monotonic timestamp
before response dispatch. Bounded packets detach identifiers and preserve the
original time through source forwarding. Missing/revoked/full observation does
not alter completion; non-LLM and STS paths emit no room diagnostic evidence.

Focused tests121/0 and broader room tests386/0 pass, as do static gates and Lean.
Astra xhigh review is clean (eight independent probes). The preceding full umbrella
run passed but predates this checkpoint and the final provider-link correction.
Response association, automatic source attachment and collector persistence remain
open; the combined C correlation tasks remain unchecked.


## Checkpoint C response timing association — 2026-11-19

Accepted audio input carries its observation into the existing agent turn. The first
nonempty text actually published to recipients and first authorized playback-start
acknowledgement emit bounded command/correlation/output IDs with monotonic times.
The latter is the room's receipt of acknowledged server egress, not remote hearing.
Observations retire with the turn; unrelated commands/continuations do not inherit
them. Revocation, saturation and stale callbacks cannot borrow a later output.

The initial regression was red for missing response evidence, then green. Broader
room/diagnostic tests passed391/0 on a same-seed rerun after one STS source-arm
timeout (also passing1/0 in isolation). Static gates and Lean pass. Astra xhigh
review is clean with27 independent tests. A full umbrella run is still in progress.
Collector correlation/persistence, automatic attachment and configured-call
acceptance remain open; combined C tasks are not yet complete.


## Checkpoint C prospective source discovery — 2026-11-19

An LLM-only coordinator request can now discover the next provider-accepted source
without copying its audio. Each capability retains one request for at most250ms;
settings, ownership, allocation and global-policy fences precede a bounded source
announcement. The packet carries exact track/epoch, media format and known-wrapper
inference mode. Discovery does not wait for worker/model readiness or change audio
admission. Prepared sessions do not inherit requests; successful retirement cancels
them, failed retirement preserves their expiry, and discarded preparation preserves
active discovery. Both reviewer-proved lifecycle regressions are retained.

Affected tests156/0, static gates and Lean pass. Astra xhigh final re-review is clean
(six independent probes). The earlier umbrella run has passed through Persistence
but predates this checkpoint. Automatic room enumeration/attachment, collection,
persistence and configured-call acceptance remain open; C is still incomplete.


## Checkpoint C current room candidates and policy-fenced attachment — 2026-11-19

A coordinator-only query now pages current main-admission human STT bindings for
the selected, present LLM agent. It excludes native STS, held/private/absent sources
and unready rooms, and returns bounded identity/eligibility data without prompts
or provider configuration. The new attachment overload requires the policy revision
reported by source discovery to remain installed before existing allocation/source
and settings checks run. Snapshot construction moved mechanically to Room.Snapshot
to keep RoomAuthority within the repository's module-size limit.

Focused23/0 and final broader403/0 pass, as do static root gates and Lean. Astra
xhigh review is clean: seven independent probes exercised a real configured room,
67-source pagination, privacy, selected-agent identity, attachment fences and
snapshot parity. The prior full umbrella run is still active and predates these
edits. Automatic scheduling, collection/persistence and configured-call acceptance
remain open; C tasks stay incomplete.


## Checkpoint C automatic source attachment — 2026-11-19

An optional coordinator in the isolated diagnostic pool now discovers and attaches
current eligible sources prospectively, with one pending probe and bounded active
workers. Active eligibility is audited even at capacity. Exact connection lookup
prevents pagination movement from retiring healthy sources. Capability-owned,
one-use source proofs fence allocation, policy, grant and transport epoch; delayed
readiness and attachment time out without changing operational speech. Coordinator
failure retires its workers and output grants. The injected collector port is not
yet connected to production persistence.

Retained review regressions cover stale sources, collector races, timeouts, output
retirement and pagination. Affected tests142/0, root static gates and Lean pass.
Astra xhigh final re-review is clean with13 independent probes. The preceding full
umbrella run passed but predates this checkpoint; current-source root acceptance
remains required. Live collection/persistence, configured-call acceptance and
production composition remain open, so the combined C tasks stay unchecked.


## Checkpoint C live correlation and durable collector — 2026-11-19

The live source-run builder joins provider/canonical references with accepted room
turns and response commands. Revisions preserve late confirmation; uncertainty,
resumed speech, gaps and ambiguous provider identities cannot yield fabricated
durations. Provider/source sample alignment is now an explicit required contract;
its packet/consumer exist but actual adapter emission remains pending.

Calls has a bounded collector pool using the existing asynchronous writer. It
waits for admitted writes before terminal coverage, with finite shutdown deadlines;
lost revisions and known audio gaps remain incomplete. An actual database test
writes a pending row, revises it after late confirmation, drains both processes,
and rereads durable evidence. Current affected Engine135/0, Calls32/0 and
Persistence16/0 pass. Builder and collector Astra xhigh final reviews are clean;
root static gates and Lean pass. Explicit writer acknowledgments fence final
coverage against a reproduced settlement-counter race.

The prior umbrella run was not frozen: it exposed two independently reproduced
fixture races now fixed, an unreproduced briefing-voice recovery deadline, and a
new persistence fixture using an old loaded capture-packet module. It is not root
acceptance evidence. Production profile/mapping/wiring and configured-call
acceptance remain open; combined C tasks are intentionally still unchecked.

Frozen collector-baseline follow-up: root mix test at e260bee4 finished with exit0
and every application passing, including Engine2715, Calls434, Gateway891,
Persistence579 and Console591. The prior briefing-voice timeout did not recur.
This is baseline evidence before subsequent sample-mapping changes; C remains open.


## Checkpoint C continuous Scribe source anchors — 2026-11-19

Continuous Scribe now produces verified prospective provider/source sample anchors
after complete frame acceptance, directly and through the conversational wrapper.
An explicit STT frame-input capability preserves manual/other-provider raw fallback.
Capture enabled mid-call accounts for the existing provider sample prefix. Gaps,
invalid optional metadata and changed sources retire diagnostics, preserving
accepted audio. Replacement handoffs establish fresh correspondence.

Retained red/green regressions cover missing mapping and missing identity metadata.
Affected tests762/0 (9 excluded), root static gates and Lean pass. Astra xhigh
review is clean with22 review cases, including seven additional probes. The frozen collector baseline
passed the full umbrella suite; a full root run for this new checkpoint remains
required. Acknowledged provider profiles, application wiring and configured-call
acceptance remain open, so combined C tasks stay unchecked.

Frozen sample-mapping umbrella verification completed at3bb91f18 (docs-only
8ec197f3 followed during the run): exit0, all applications pass. Engine2731/0,
Calls434/0, Gateway891/0, Persistence579/0, Console591/0; other applications
106/222/35/567/20. No runtime/test/build files changed during the run. This closes
that checkpoint's root-suite gate, not the remaining milestone acceptance gates.


## Checkpoint C acknowledged Scribe profile — 2026-11-19

The socket preserves a bounded allowlist of acknowledged settings without inventing
omitted echoes or changing speech readiness. Authorized asynchronous direct/wrapped
queries retain canonical and provider generation identity and preserve existing
observation. The coordinator pairs this profile with its accepted source proof
before collector creation, rejecting unknown/unsupported/conflicting evidence.
Manual Scribe returns unsupported promptly. Calls/Persistence can store the closed
provider acknowledgement separately from observer configuration as immutable run
identity; legacy profiles remain readable.

Retained red/green review regressions cover audio arriving between discovery and
profile request, missing manual replies, and an incorrectly accepted floating
sample rate. Engine752/0, Calls39/0 and Persistence17/0 pass; root static gates and
Lean pass. Both Engine and Calls/Persistence Astra final reviews are clean
after the reproduced fixes. Production application/collector wiring, configured-call acceptance and
manual commit timing remain open, so the combined C checklist stays unchecked.

## Checkpoint C live factory and startup leases — 2026-11-19

The Calls-owned factory now constructs immutable runs from acknowledged Scribe
profiles and source context, including the UTC anchor and pinned observer metadata.
A mandatory bounded startup lease prevents unclaimed factory collectors from
remaining active indefinitely. Collector and source worker initialization use the
remaining startup budget; cancelled/expired provisional consumers reject handoffs
and evidence. Unresolved nested supervisor admission retains its capacity debt
rather than allowing repeated timed-out starts to accumulate queued work.

Retained red/green regressions cover stale handoffs, expired workers, blocked writer
startup, discarded packet accounting, absent factory leases and cancellation during
writer handoff. Calls diagnostics42/0; Engine lease/worker Astra review is clean.
Collector Astra re-review is also clean (16 independent tests/probes), final static
checks and Lean pass; the full root suite remains pending. Production composition,
coordinator helper/adoption and configured-call acceptance remain unimplemented;
this checkpoint does not close any combined C acceptance item.

Frozen startup-factory root verification at fb21396f completed with exit0:
Engine2752/0, Calls445/0, Gateway891/0, Persistence580/0, Console591/0, and the
remaining applications106/222/35/567/20 all pass. No runtime/test/build files changed
during that run. Coordinator and production composition work follows this baseline.

## Checkpoint C bounded coordinator attachment — 2026-11-19

The source coordinator now runs attachment in one locally owned helper, keeping
status and revocation responsive when collector or worker admission stalls. It
cancels before terminating timed-out work, adopts only current results, and owns
active worker monitors itself. Normal shutdown and abrupt failure retire helpers;
a source subtree restart preserves its parent-supplied unresolved admission gate.

Retained tests first reproduced blocked startup and missing helper ownership.
Engine diagnostics149/0 pass; Astra xhigh review is clean with20 independent cases,
including late results and gate debt across failure. Static root gates and Lean
pass. The full root suite cited above predates this coordinator change. Calls parent
and Application wiring, configured-call acceptance and combined C gates remain open.

## Checkpoint C production diagnostics composition — 2026-11-19

Database-backed hosts now install the Calls diagnostics parent through the normal
Application tree. It supplies the real immutable-run collector factory, repository
and persistence pools to the Engine source subtree. One parent-owned startup gate
survives child restarts; replacing the whole parent replaces its gate and all old
destinations together. Off/unknown settings start no collectors or model work.
There is no new configuration switch that can override the durable setting.

Parent/Application and runtime configuration regressions were red before wiring.
Calls diagnostics46/0 and Console runtime12/0 pass. Astra xhigh runtime-inclusive
review is clean, including independent restart/factory/capacity probes. Static root
gates pass and Engine Lean verification remains current. A new frozen full root suite is
running for this composition. Actual configured Scribe call persistence, full
on/off/transport acceptance and combined C checklist items remain open.

## Checkpoint C finalized acoustic coverage prerequisite — 2026-11-19

The configured Scribe fixture exposed delayed provider timing behind diagnostic
inference. A detector-owned finalized sample position now excludes pending onset
and silence candidates, whose eventual boundaries can be backdated. The bounded
capture protocol accepts an epoch and contiguous finalized interval. Worker
emission and report consumption remain to be implemented before timing can safely
overtake inference; no combined acceptance task is newly complete.

Both contracts were red before implementation and pass8/0 focused tests. Astra
xhigh review is clean, including20 reachable detector states and60 transitions.
Static root checks and Lean pass; the frozen full suite remains in progress.

Frozen finalized-coverage prerequisite40168099 completed the full root suite with
exit0: Engine2760/0, Calls449/0, Gateway891/0, Persistence580/0, Console592/0,
and remaining applications106/222/35/567/20. No runtime/test/build edits occurred
during that run. This is baseline evidence before the delayed-timing integration.

## Checkpoint C delayed observer timing — 2026-11-19

Timing metadata can now reach the collector during acoustic inference. Finalized
sample coverage gates acoustic fields, so an earlier endpoint cannot transiently
produce a valid duration before resumed speech is inspected. Progress is bounded
and coalesced by epoch; resets freeze old intervals, and sample bounds prevent
uncertainty from unrelated earlier/later audio poisoning a turn. Queued gaps retain
original receipt/observation timestamps. All reviewer findings were reproduced
before correction; independent report13/0 and worker32/0 reviews are clean.

The configured LLM/Scribe fixture now persists the prospective partial first turn
before held Silero inference completes, revises it afterward, records a second
fully observed turn with available latency and response-text timing, then rereads
both rows after collector/writer shutdown. Calls46/0, Persistence17/0 and this
configured fixture1/0 pass, as do Engine178/0, static root checks and Lean. The
current-source frozen full root suite is running; its acceptance remains pending. Response audio, manual
commit timing, full on/off/transport acceptance and per-turn finalization remain
open; no combined C checklist item is newly complete.

## Checkpoint C manual commit timing and configured shutdown — 2026-11-19

Successful explicit Scribe draft-flush commits now carry socket-send receipts,
separate from provider transcript commits. The unchanged wire payload is sent once;
failed sends, revoked observations, capture replacement and legacy transports retain
existing operational behavior without fabricated evidence. Independent Astra xhigh
review is clean; integrated focused timing/socket/report tests pass21/0 and the
broader diagnostics/reuse selection passes205/0.

The configured two-turn fixture now holds its terminal database write: room and
collector termination complete while the persisted run is still running, then the
writer is released and both turns are reread durably. Discovery supplies paced
silence until this source subscribes, replacing the one-frame startup assumption
that failed in the prior root suite. Focused test and independent review each pass1/0.
The instrumentation and configured fixture tasks above are now complete; broader
on/off, response-audio and final milestone acceptance remain open.

Format, compile warnings-as-errors, strict Credo and unused-lock checks pass.
Full-suite runs are deferred until milestone implementation is complete per user
instruction. The prior f5a20d3b root run ended with two failures (a local Telnyx
startup fixture and this corrected discovery fixture); it is not a passing gate.
No Telnyx code or live-provider tests were used for this checkpoint.

## Checkpoint D authorized report read boundary — 2026-11-19

Calls now exposes separate tenant-authorized report and run-turn reads through the
existing diagnostic repository port. Run pages carry honest freshness/loss coverage;
summary queries cover the entire authorized call independently of pagination.
Turn pages retain revisions, default to50 and cap at100 rows. A full last turn page
may have an empty successor. No Console route or core/UI consumer is claimed yet;
D acceptance stays open until those pieces and their checks are implemented.

## Checkpoint D Console report API — 2026-11-19

The authorized Calls reads now have session-only Console routes and a configured
Persistence read port on database-backed hosts. Versioned private JSON preserves
nullable microsecond stages, revisions, run coverage and bounded profile/clock
provenance. Missing scope and unavailable storage have separate generic errors.
Endpoint/runtime tests pass20/0; Astra xhigh source review is clean. Local Chrome
confirmed signed-out401 and signed-in200 report/turn reads with private/no-store.
Core state, lazy report UI and live refresh still remain; D tasks stay unchecked.

## Checkpoint D Storybook-first shared latency view — 2026-11-19

The shared Metrics view accepts an optional diagnostic loader and starts its section
collapsed. Typed core pages retain newer turn revisions; the view fetches lazily,
polls serially only while open/live, aborts on close, times out and exposes retry.
Synthetic Storybook states show complete/partial evidence, absent collection and
loading/outage. Technical rows and whole-call profile summaries stay opt-in.
Astra paging findings were reproduced and fixed, with four independent probes now
green. Desktop/mobile Chrome and keyboard disclosure were inspected. Real HTTP
loader/decoder composition, transcript links and remaining D acceptance are open;
this preview is not a claim of production diagnostic presentation.

## Checkpoint D real HTTP host composition — 2026-11-19

Both authorized call-inspection hosts now compose the lazy diagnostics loader.
The decoder validates response version, requested call/run identity, bounded pages,
raw nullable timings and profile provenance. Active session expiry is propagated;
aborted responses cannot trigger a stale redirect. Three real server profile
compatibility failures found by Astra were reproduced, fixed and retained as
regressions; re-review is clean. Focused frontend checks passed 42 tests and
endpoint checks passed 8 tests. A rendered local browser using dummy identity and
repository fixtures verified zero diagnostic requests while collapsed, then both
real authenticated endpoints returning HTTP 200 and displaying 20 ms dispatch
values after expansion. Asset build and static checks passed. Transcript references
and remaining D acceptance remain open; full-suite and deployment gates are deferred
until milestone implementation is complete.

## Checkpoint D authorized transcript references — 2026-11-19

Inspection messages now retain their canonical turn reference. Diagnostic rows link
only to existing authorized messages matching both turn and observed participant;
legacy/missing references do not fabricate links. The action opens the corresponding
100-item conversation page, restores Messages and moves keyboard focus to the target.
Presenter/decoder/UI red tests were observed before implementation. Focused checks
passed 16 presenter, 13 decoder and 23 shared UI tests. Astra's independent review
returned no findings. Desktop and mobile Chrome verified pointer/keyboard navigation
and target focus in the admin preview, with no mobile document overflow. Static
checks passed. The first two D tasks are now complete; remaining fixture/summary
and both-host acceptance gates stay open, as do C/E/F and final deployment.

## Checkpoint D summary metrics and evidence states — 2026-11-19

All returned timing definitions now appear as labelled profile-specific aggregates;
missing percentiles remain unavailable. Focused storage verification (17 tests)
proved full-report counts/percentiles independent of page size, missing-evidence
exclusion and profile separation. The UI has pending, unsupported, denied,
zero-valid and 200-turn fixtures; focused UI checks passed 21 tests. Review findings
about unstable summary disclosure keys and contradictory pending fixture reasons
were reproduced and fixed with retained regressions. Rendered desktop/mobile Chrome
confirmed unavailable percentiles, evidence states and a bounded 100-row page at
390px width. Static checks passed. The summary acceptance task is complete;
absence-of-collection provenance and the remaining both-host matrix stay open.

## Checkpoint C accepted-audio and inference-mode acceptance audit — 2026-11-19

Current source and focused tests complete the accepted-audio observation and
operational-reuse/standalone implementation tasks. The verification selection
passed 84 capability/source/clock/worker tests, and the configured Scribe persistence
and shutdown fixture passed. A focused audit found an inference-failure coverage
gap: paired observer-absent/present tests now prove the operational session failure
is unchanged, only one inference runs, and the observer gets timestamped failure
rather than an invented endpoint. All 14 reuse tests pass. These two C tasks are
checked; the separate full on/off/configured matrix, distributed effective status,
revocation/load/accuracy gates and final deployment remain unchecked. Earlier
partial-checkpoint notes are historical evidence, not the current task status.

## Checkpoint C configured VAD/diagnostics matrix — 2026-11-19

The local configured Scribe fixture now covers all four initial VAD/diagnostics
combinations, plus active-call enable and disable/re-enable. Classifier probes
verify the selected inference path and exact continuous operational sample cursor;
provider bytes remain identical and no extra commit is emitted. Disabled cases
have no diagnostic worker/report. Re-enable records a distinct source epoch while
retaining the prior run. Negative checks follow complete diagnostic drain.
The focused configured selection passed 5 tests, including the original actual
Silero late-confirmation/durable-shutdown fixture. These are offline acceptance
tests, not live-provider evidence. The combined matrix checkbox remains open until
source/model compatibility, replacement and late-result coverage are consolidated;
distributed status and the later load/accuracy/deployment gates also remain open.

Review additionally strengthened provider-delivery uniqueness: injected duplicate
marker delivery fails all four cases. Final serial configured run passed 5/5;
Astra scoped re-review and static checks are clean. Concurrent DB review execution
is excluded from acceptance because it caused settings setup contention.

## Checkpoint C source/model/epoch matrix completion — 2026-11-19

The configured fixture now also replaces the accepted source epoch while the call
remains active. All four combinations retain old reports with closed_at set,
create a distinct new epoch, deliver each marker once and preserve the exact
operational sample cursor. Configured acceptance passed 5/5. Separately, the
source/coordinator/reused-result/inference/Silero selection passed 49/49, covering
replacement races, retired-epoch late results, revocation and fixed model behavior.
Earlier 14/14 reuse tests cover operational failure and speech-event preservation.
Both production modes use the same checksum-pinned 16 kHz/512-sample Silero model;
there is no supported alternative-model negotiation path. Mid-stream reuse stays
partial until a clean inference epoch. Astra's final scoped acceptance review found
no gap, so the combined C matrix task is checked. Distributed status, settings
failure transitions, load/accuracy and live acceptance remain separate open gates.

## Checkpoint C settings status and runtime bounds — 2026-11-19

Status now rejects a pending invalidation even while its projection is stalled.
Astra also reproduced an old-lease/cleared-flag interleaving in status and grant
reads. Both now read the invalidation flag before the lease; the two deterministic
scheduler probes pass after the fix. Two isolated BEAM peers with independent
controlled clocks prove immediate hint rejection, missed-hint expiry at 3,000 ms,
stale-revision rejection and later valid re-enable. Their loader snapshots are
controlled fixtures, not a database/network propagation measurement.

Focused Engine checks passed 38/38 and Calls writer/supervision checks 21/21.
The runtime-limits design note records actual defaults, authority semantics,
rejected alternatives and verification boundaries; Astra reviewed that document
separately from the implementation and found no mismatch. The final code review
is clean. The C supervision/projection/limits task is checked. Effective-status UI,
broader settings failure transitions, measured load/accuracy and live acceptance
remain open; no deployment or live provider use occurred.

## Checkpoint C settings recovery authority — 2026-11-19

Focused loader-boundary acceptance now queues PCM before a settings read failure
or reader/projection crash, then verifies that new handoffs are denied while the
setting is unavailable/unknown. Recovery at the same saved revision admits fresh
capture but cannot revive pre-failure queued audio; rejected audio releases its
retained count/byte charge. The projection/handoff/peer selection passes 21 tests.
These fixtures establish local recovery and capture fencing, not a real database
outage or full configured-call parity. The broader settings-failure task stays open.
Astra's review is clean, with an independent 13-test projection run. Recovery is
before the old lease deadline, isolating failure/restart fencing from expiry.

## Checkpoint D evidence-state acceptance — 2026-11-19

The fixture/test matrix now includes late revision of an existing incomplete turn
and explicit retry after a temporary outage. Live refresh retains the expanded,
focused row while revision 1 advances to revision 2 with acoustic evidence.
Turn-read 401/403/404 clears loaded rows and summaries; 503 preserves labelled
previous evidence until retry. Existing cases cover absent collection (without
inventing old/disabled provenance), unsupported capture, incomplete coverage,
pending counts and zero valid samples.

Frontend/core checks passed 30/30; Console loader checks passed 8/8. TypeScript and
root static gates pass. Astra reproduced two fixture issues, both corrected with
passing independent probes (2/2); final review is clean. Chrome confirmed late
revision on desktop and outage/retry plus keyboard expansion on mobile. The D
fixture/test task is checked; comprehensive both-host rendered acceptance remains
open. Storybook exposes Late Evidence and Retry After Outage through its existing
Tailscale preview. No production deployment or provider use occurred.

## Checkpoint D both-host rendered acceptance — 2026-11-19

Both production wrappers now have bounded Chrome evidence at desktop 1440x1000
and mobile 390x844. Admin CallDetailsPage and shared CallConsole Storybook states
passed 12 loading/retry/large-report cases; the real CallInspectionApp with its own
host CSS and height passed another six cases through a temporary local fixture.
Standards mode, exact viewport width, no page overflow, 100-row page limits,
next/first paging, keyboard expansion, full focused-row visibility and return to
ordinary conversation were checked. Existing technical-event opt-in and transcript
checks remain recorded in earlier checkpoints.

Added reusable host stories for loading, outage/retry and large reports. Focused
React checks passed 27/27 and Console wrapper/loader checks 16/16; both TypeScript
checks and root static gates passed. Astra reviewed the fixture wiring and final
browser evidence, required correction of the temporary document mode/focus proof,
and returned clean. The temporary harness and server were removed. All D tasks
are now checked; C settings UI/failure/landmark acceptance, E and F remain open.
No deployment or live provider use occurred.

## Checkpoint C bounded settings-status refresh — 2026-11-19

The UI now refreshes explicit applying responses with a finite budget: ten
sequential checks, one-second spacing and a ten-second response deadline. Newer
pending revisions do not reset that budget. Save/load generations reject obsolete
responses; uncertain saves invalidate the prior applied label without changing the
last confirmed toggle. Errors/timeouts preserve the saved value and offer reload.
Twelve focused tests pass, including the three reviewer-reproduced edge cases.
Chrome Storybook explicitly shows applying then simulated applied on desktop and
mobile; keyboard save works. TypeScript, scoped lint and root static gates pass.

The production API still needs a sound effective-disable proof; C's combined UI
task remains open. Design review rejected treating one API node's elapsed time as
unconditional global lease expiry. The runtime-limits note records fresh-read,
revision and clock-progress requirements and acknowledgement alternatives without
claiming that an unimplemented proof exists. No production capture was enabled.

## Checkpoint C response boundary acceptance — 2026-11-19

Silent and tool-only completions publish their normal events without fabricated
response landmarks. A retired text capability cannot contribute a replacement
agent's first response; valid replacement output retains the accepted input IDs.
Interruption rejects late text and the exact previously registered speech request
after cancellation acknowledgement. Full diagnostic queues do not suppress text
or relabel a later sentence as the first response.

The focused room/input, live-report and timing selection passes 29/29. Astra's
independent positive-control playback probe passes and its final review is clean.
Root static gates pass. These are boundary fixtures for existing behavior; the
combined C landmark task remains open for actual configured routing through
matching text/audio. No runtime implementation, live provider or deployment changed.

## Checkpoint C configured routing acceptance — 2026-11-19

A persisted configured call now exercises synthetic Scribe input, an actual model
transfer tool call, the specialist's response text, synthetic TTS and acknowledged
playback. The caller keeps its STT session; the agent-scoped diagnostic run retires
and normal discovery attaches a new run while caller audio continues. The second
input's correlation and response command match its persisted text/audio landmarks.
Audio start remains absent before egress acknowledgement, and the tool-only source
turn has no fabricated response landmarks after shutdown drain.

All six configured diagnostic tests and root static gates pass. Independent Astra
review also passes the routing case and reproduces an expected failure when a
mutation emits playback-start before acknowledgement. Together with the prior
response-boundary checkpoint this completes the C matching-landmarks task.
This checkpoint changes tests and documentation only. No live provider, Telnyx
code or deployment changed.

## Retained configured failure parity — 2026-11-19

Before room-service cutover, four synthetic configured cases verify collection
on/off with diagnostic inference crashing or held while two conversational turns
complete. Provider marker bytes arrive once; responses keep input correlation;
disable drains diagnostic work without extra commits or connection failure.
An owned acknowledgement proves inference remains held through both turns.

The full configured selection passes 10/10. Astra reproduced duplicate delivery
passing the initial assertions; the corrected checks reject that mutation in all
four cases, and independent baseline is 4/4. Final scoped review and root static
gates are clean. This is retained old-coordinator evidence to port at cutover,
not completion of any new room-service task or full failure/load acceptance.

## Migration step 1 — participant input intervals, 2026-11-19

Diagnostic capture, source announcement/profile proof, attachment and canonical
completion forwarding now use the participant's STT/audio-input interval pair,
with the STT allocation generation checked separately. Unrelated room revisions
preserve observation. Either relevant permission interval changing invalidates it;
legacy snapshots without scoped intervals fall back to their global revision.
The bounded internal source-ready message carries the pair, not a global revision.

Two regressions failed before implementation (existing tap closure and missing
source announcement after unrelated presence changes). The focused selection now
passes 54/54 and configured Scribe selection 10/10. Independent Astra review is
clean, with two extra probes for completion continuity and pre-next-frame rejection
of stale profile/attachment proof after same-allocation revocation. Root format,
compile warnings-as-errors, strict Credo, unused-lock and Lean checks pass.

This completes only the input-fence migration task. The current coordinator still
retires on agent changes; room ownership, segment persistence, cutover and later
acceptance remain open. No operational STT policy, provider behavior, Telnyx code
or deployment changed. Full umbrella testing remains deferred until implementation
of the milestone is complete.

## Migration step 2 record foundation — 2026-11-19

Calls turn/run records now accept independently versioned acoustic segment
collections (32 entries maximum) with explicit omitted counts/reasons. Each entry
retains inference epoch, start/end samples, nullable mapped estimates, separate
confirmation times and uncertainty. Missing legacy fields remain nil; an empty
observed list is distinct. Partial segments require reasons. Repeated boundaries,
same-epoch overlap, reversed ordering, unknown fields and arbitrary payloads fail
validation. Different epochs may reuse sample positions.

The existing JSON storage round-trips turn and unattached run evidence, revisions,
and legacy records without a table migration. Domain/diagnostics tests pass 62/62;
storage tests pass 18/18. Astra reproduced two contradictory-history validation
cases, now rejected by retained tests and independent green probes (2/2); final
scoped review and root static gates are clean.

This is a record/storage foundation only. LiveReport/Collector segment production,
canonical-turn assignment, bounded unattached retention and API/UI presentation
are not implemented by this checkpoint. Step 2 and B/D extension checkboxes remain
open. No live provider, Telnyx code, source state machine or deployment changed.


## Migration step 2 live segment correlation — 2026-11-19

LiveReport now projects multiple acoustic segments onto uniquely proven canonical
source-sample intervals. Missing mappings and partial/outside segments stay in the
bounded run collection; conflicting intervals retain explicit ambiguity. Late
mapping or canonical evidence can reassign retained segments. Per-turn and run
collections both carry omitted counts; their bytes are included in report capacity.
Collector writes segment revisions before scalar coverage is necessarily complete,
and writes unattached evidence on heartbeat/final drain.

No acoustic observation remains nil. Incomplete finalized coverage remains pending;
resets close partial segments without fabricating endpoints. Conflicting transition
or clock evidence is rejected before replacing accepted state, and the collector
drains valid evidence with a clock-uncertain incomplete run. Closed epochs reject
late progress and report gap reasons, without contaminating adjacent intervals.
Engine diagnostics pass 192/192, Calls domain/diagnostics 64/64, final Collector
9/9 and configured synthetic calls 10/10. Root static gates pass. Final scoped Astra
review is clean with ten independent regression probes passing; details are in
[the checkpoint labnotes](../20261119-1543-acoustic-segment-correlation.md).

The offline ReplayReport extension remains pending, so the B extension checkbox
stays open. Room-service ownership/cutover and API/UI extensions remain separate
unfinished tasks. No live provider, Telnyx behavior or deployment changed.


## Migration step 2 replay completion — 2026-11-19

AcousticReplay now emits source/clock-scoped boundary, reset and finalized-progress
metadata. The interval-aware ReplayReport entry point validates it through
LiveReport and uses the shared segment projection. Explicit admitted sample ranges
constrain both segment assignment and scalar endpoints; pending/gap/omitted
coverage cannot produce a valid scalar latency. The legacy scalar-only entry point
remains compatible.

The existing replay command now writes turn segments and run unattached evidence
through the bounded writer, then reads both in a fresh BEAM process. Final artifact
`vxpipe_latency_replay_1795104392_18023.json` contains the complete pair with separate
confirmation times, preserved 300 ms fixture latency, and the missing-audio
scenario's unattached partial onset/gap with null acoustic delay. Ordinary call
facts remain zero. A pre-extension fixture database still reads with nil segment
fields. These are synthetic offline timings, not live provider measurements.

Engine diagnostics pass 195/195 and root static gates pass. Astra reproduced a
scalar/segment interval mismatch, fixed with retained red/green coverage tests;
final review is clean and two independent probes pass. See
[checkpoint labnotes](../20261119-1559-acoustic-replay-segments.md).
Together with the preceding storage and live-correlation checkpoints, this closes
B's records/replay extension and migration step 2. Room-service work, D extensions,
E/F and deployment remain incomplete; the milestone index stays unchecked.
