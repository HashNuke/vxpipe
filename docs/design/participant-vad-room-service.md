# Participant VAD observation owned by the room

Status: room-service cutover implemented; broader eligibility and acceptance pending. 2026-11-19.

The implementation and acceptance plan is in
[Passive call latency diagnostics and readable timelines](../../labnotes/milestones/passive-call-latency-diagnostics.md#architecture-revision--participant-owned-vad-2026-11-19).
This decision supersedes the prior agent-selected discovery/attachment ownership,
not the existing timing, storage, authorization or bounded-work contracts.

## Decision

A room-incarnation-owned optional diagnostics service manages one acoustic
observation state per human participant's accepted STT source. With collection
enabled, it subscribes to already-running local Silero evidence, or owns one
fallback Silero stream if local Silero is absent. Local operational Silero is
explicitly distinct from provider VAD and provider turn markers.

The local stream supplies speech-start and speech-end segments, sample/epoch
identity, confirmation times and gaps. A segment is not necessarily a canonical
conversation turn. Existing provider, adapter, room and response evidence remains
separate and is correlated to those segments. Operational detector resets can
leave incomplete endpoints; the observer must report them rather than run a
second model or change call control.

The observation belongs to the human STT input, not the selected agent. An agent
transfer with an unchanged input preserves acoustic state. Input replacement,
revocation or detector-mode changes fence old work and create explicit boundaries.
Two STT participants have independent recurrent state. STS-only inputs have no STT
source; an unrelated STS participant does not exclude another human's STT source.

Room ownership does not put inference in RoomAuthority. Keep shared bounded
inference/model infrastructure and asynchronous Calls persistence. The optional
service must not gate room readiness, block call callbacks, or cause room shutdown
through restart intensity exhaustion. No generic service framework is required.
The existing installation setting remains the collection gate; operational Silero
continues normally when diagnostic collection is disabled.

## Current evidence and migration implications

- `RoomAuthority.DiagnosticSources` currently requires a selected text agent and
  rejects room-level STS. Replace this with accepted human STT source eligibility.
- Migration step 1 now fences `AudioTap`, discovery, attachment and completion
  forwarding on the STT/audio-input interval pair plus allocation generation.
  Unrelated revisions preserve observation; relevant interval changes invalidate
  it. Legacy snapshots use global-revision fallback. Focused and configured tests,
  independent review and Lean pass; agent-dependent lifecycle still needs migration.
- `SourceAttachment.current?/1` compares agent identity; the configured transfer
  test currently expects retirement/rediscovery. Replace both with input continuity.
- `SourceCoordinator` scans rooms from a node-owned subtree. Replace its ownership
  role with room-local registration and bounded reconciliation, then remove the old
  composition. Do not keep parallel owners of the same input.
- `InferenceTap` already supplies local probabilities/sample/reset evidence;
  `SourceWorker` already supports reuse and fallback. Adapt these, preserve their
  no-duplicate-inference and bounded-work guarantees, and avoid rewriting them
  without a demonstrated need.
- Canonical completion observation now has no response-agent gate; `LiveReport`
  builds rows from accepted STT completion packets. Configured human-only calls
  persist canonical input timing with nullable responses for two humans. Configured
  mixed-room STT/STS completion is also verified; routing-induced replacement
  acceptance remains pending.
- `ActivityBoundary` identifies starts and ends. `LiveReport` uses starts for
  ambiguity checks but the durable report emphasizes end timing. Add bounded,
  versioned start/end segment evidence through records, API and fixtures, preserving
  legacy reports and incomplete-state semantics.
- Existing Calls/Persistence authorization, revisions, writers, technical-event
  filtering and collapsed metrics/latency UI remain useful. Their old test results
  do not establish the revised service lifecycle or new evidence representation.

## Alternatives and verification

Reject one detector per agent, duplicated inference beside local Silero, provider
markers as a replacement for acoustic evidence, and synchronous inference in the
room process. Keep shared model weights with independent participant stream state.

Acceptance must cover two STT participants, an STT participant without a selected
LLM agent, mixed STT/STS rooms, transfer continuity while audio continues, all local
Silero/collection combinations, source/mode changes, crash isolation and teardown.
Then repeat configured failure parity, measured accuracy/load and Scribe/browser
live acceptance. No live Telnyx tests or Telnyx implementation changes are required.

This revision is based on source review, not a new runtime validation. The existing
node-level limits remain implementation evidence until migrated and reverified.
Global effective-settings status remains an explicit open acceptance item; room
ownership alone does not resolve it.

## Segment record contract

The record extension uses `TurnDiagnostic.acoustic_segments` and
`LatencyRun.unattached_segments`. Both default to `nil` for legacy/unavailable
segment evidence. A version-1 collection has exactly `version`, `entries`,
`omitted_count` and `reasons`; at most 32 entries are retained per collection.
A positive omitted count requires `segment_limit`. An empty collection means the
producer supplied an observed empty set; it must not be substituted for legacy nil.

Each segment records an inference `epoch`, nullable `start_sample`/`end_sample`,
nullable `start_us`/`end_us`, separate `start_confirmed_us`/`end_confirmed_us`,
`uncertainty_us` and explicit `reasons`. Sample positions use the enclosing run's
normalized 16 kHz source; microsecond offsets use its clock origin. These are local
acoustic observations, never provider turn markers or wall-clock timestamps.
Missing boundaries have all three corresponding fields null. A retained boundary
requires a sample and confirmation; its mapped estimate can be absent with a
quality reason. Complete unqualified segments require both mapped boundaries and
uncertainty. Reversed estimates/confirmation order, repeated boundary identities, overlapping
same-epoch intervals and unknown fields/reasons are invalid. Separate inference
epochs may reuse sample positions. No audio or text is accepted.

The envelope is independently versioned and additive in the existing JSON records;
no table migration or replacement of legacy timing fields is needed. Existing
scalar timing quality continues to describe those metrics; segment reasons describe
the segment evidence separately.

LiveReport projects accepted boundary packets into these collections. A pair is
assigned only when exactly one canonical provider source-sample interval contains
both boundaries. Missing mappings, partial pairs and segments outside all intervals
remain on the run; competing intervals add `ambiguous_boundary`. Late canonical
links/mappings can reassign retained evidence without inventing turns. Inference
epochs never pair across resets. Repeated transition kinds and reversed acoustic
clocks are rejected before replacing accepted evidence; the collector drains that
valid evidence with an explicit incomplete run.

No observed boundary or finalized progress means unavailable (`nil`). A turn's
collection remains `pending` until finalized coverage spans its source interval;
a closed overlapping epoch instead records its gap/reset reason. Earlier adjacent
epochs do not mark the next interval lost. Observed segments can be persisted before a scalar latency estimate becomes valid.
Both per-turn and unattached collections retain 32 segments with omitted counts,
and are charged inside LiveReport's existing packet/byte limits. Collector
heartbeats and final drain persist the unattached collection.

Offline PCM replay emits the same boundary/reset/progress packets, including one
final progress record per inference epoch. The interval-aware replay entry point
validates that journal through LiveReport and uses its segment projection. Callers
must supply admitted source-sample intervals; provider receipt times are not source
positions. Scalar endpoints are selected from the same assigned evidence and are
withheld for pending, lost or omitted coverage. The legacy scalar-only replay entry
point remains compatible.

The replay command admits its full synthetic PCM before the sole provider turn,
uses that exact sample range, and writes both segment collections through the
existing bounded writer. Fresh-process reads expose complete pairs and unattached
partial/gap evidence. Authorized API/UI presentation remains pending; these
records/replay checks do not accept the room-service migration.


## Room worker admission lifetime

The old node-owned worker DynamicSupervisor supplies the live-worker limit;
AttachmentLease's gate alone bounds unresolved startup, because `finish/1` releases
a successfully adopted lease. Moving workers into separate room subtrees therefore
requires a node admission owner that retains each reservation through worker DOWN.
`SourceAdmission` provides that primitive and is tested directly before composition.
It uses the existing injected gate, claims each worker start once, tracks the
returned worker before binding/adoption, and retains tracked capacity through
cancellation or owner death. Cancellation revokes the lease before contacting the
tracker; failed or timed-out adoption also revokes atomically so a queued request
cannot later grant authority. Failed tracking kills that newly started worker and
waits for DOWN while the startup operation still holds its charge. Unknown startup
outcomes retain bounded debt rather than guessing that no worker exists.

Tracker restart must reuse its gate. Lost monitor ownership leaves conservative
debt; it cannot reclaim capacity merely because a replacement tracker has an empty
map. A fresh gate requires a confirmed teardown barrier for old room-owned workers,
including operational-reuse workers and unresolved starts. That replacement barrier
and node-pool/room-service wiring remain prerequisites for cutover. Rejected
alternatives are using `finish/1` immediately after adoption (releases too early),
counting only per-room supervisor children (multiplies the node cap), and creating
a fresh gate on tracker restart (can admit over surviving old workers). No running
coordinator or room composition changes in the admission primitive checkpoint.


## Room-local accepted input snapshot

`RoomAuthority.DiagnosticInputs` exposes bounded pages and exact connection reads
for accepted human STT bindings. It requires an open, ready room with matching
plan/snapshot ownership, main admission, present human membership and a
local STT capability binding. It returns only room/call/incarnation identity,
participant/connection identity and the bound capability; no agent, prompt or
provider configuration is returned. Selected response agents and room-level STS
capabilities do not affect this input snapshot. An STT replacement changes the
binding; an agent-only transfer leaves the same input identity intact.

Dispatch holds are not source revocation: agent preparation temporarily holds
connected participants while their accepted STT sessions survive. Such a hold does
not remove a candidate or retire its acoustic run. Removing the binding, losing
membership or changing accepted source authority still invalidates observation.

This query is candidate evidence, not permission to inspect audio. Source policy
intervals, current allocation, setting grants and source/profile proof still gate
attachment. The old coordinator keeps its old query until the single-owner cutover;
new snapshots alone do not start observers or enable no-agent turn persistence.

Gate-lifetime design review selected allocation in the Engine root's retained
child-spec arguments, outside Calls/source-pool and optional tracker restarts. The
admission subtree must be temporary/non-significant with its own restart intensity.
Missing admission ports fail closed; the composed path must not manufacture a new
fallback gate. A fresh Engine-root gate is safe only after confirmed teardown of
old room subtrees and unresolved starts. The root composition/restart tests remain
pending; the query checkpoint is not evidence of that lifetime property.


## Engine admission subtree

The Engine application now allocates the node gate once while constructing its
root child specifications, before RoomSupervisor. AdmissionSupervisor receives
that gate explicitly; neither its init nor the tracker creates a replacement.
The node hard ceiling is 32; SourceAdmission defaults each reservation to the
approved 16-source limit and accepts an explicit configured limit from 1 to 32,
always against the same node counter. Room wiring must pass the current Calls
source-pool limit, never a participant-supplied value.

The subtree is temporary/non-significant with a two-restarts-in-five-seconds
budget. Tracker restarts reuse the gate and preserve lost-monitor debt. Exhaustion
removes the temporary subtree and leaves admission unavailable; there is no
automatic subtree recreation. Any explicit re-add must retain the original gate
and must not reconstruct Application.child_specs to manufacture fresh capacity.
Controlled Engine-root teardown stops room workers before allocating a fresh root
gate. The composition harness verifies worker DOWN before that reallocation;
unresolved-start teardown with the real room diagnostics subtree remains a cutover
gate. No Calls/source path uses this new admission port until room-service wiring.


## Participant input attachment

The directly exercised `SourceAttachment.start_input/3` path revalidates the exact
accepted human STT binding through DiagnosticInputs before collector allocation,
after it returns, and before binding capture. Its context has no agent owner.
Source discovery still requires accepted source audio, current input-policy
intervals, allocation generation, collection authority and provider profile proof.
The new discovery wrapper removes only the selected-agent precondition.

The whole input attachment attempt holds a lease operation, including collector
allocation, so cancellation cannot release capacity while a collector callback is
still unresolved. Input workers start in the supplied room worker supervisor through SourceAdmission;
reuse workers also consume a node slot but never request inference admission.
Fallback workers use the shared ActivityRuntime admission. Successful attachment
still requires explicit adoption by the future room service; it must not finish
the lease after adoption. Retirement closes capture and leaves capacity charged
until worker termination. Missing admission fails closed.

The old coordinator retains its original discovery and agent checks until cutover.
These attachment primitives do not create a room service, start two owners, change
operational turn dispatch or enable no-agent canonical-turn persistence.


## Room service and attachment runner

RoomService now exists as a directly exercised component. Its temporary,
non-significant RoomSupervisor isolates a two-restarts-in-five-seconds budget and
owns both source workers and one fixed AttachmentRunner. One-for-all recovery
tears down old observation before restarting reconciliation. Exhausting this
optional subtree leaves speech and the room authority running. Production room
composition remains pending.

The service reconciles only its own room through bounded snapshots, exact active
source checks, asynchronous notifications and periodic retries. It holds at most
one discovery or attachment attempt. Both rooms use the same Engine admission
counter; capacity loss is explicit, and a waiting room can attach after a source
retires. Agent selection does not own these attachments.

SourcePort is a named Engine-defined injection boundary for the Calls-owned source
pool's collector factory, shared inference runtime, settings projection and limit.
Cutover must compose that port under the existing Calls-owned SourceSupervisor.
Missing ports are unavailable. Each candidate captures the resolved port PID;
attachment checks it and workers independently monitor/check it, so a stalled room
service cannot keep observing through dependency loss.

AttachmentRunner is a single fixed supervised IO slot, following SettingsReader's
existing pattern. RoomService sends an asynchronous request and installs its
500 ms lease deadline without waiting for task-supervisor startup. Timeout,
disable and dependency loss revoke the lease but retain the busy reference until
the runner replies. This prevents an unresponsive callback from accumulating
queued replacements. A late queued request checks the revoked lease before doing
collector work. The runner uses explicit brutal-kill shutdown because startup
work needs no terminate callback; room teardown cannot wait for a trapped exit
inside a collector. Unresolved capacity remains conservatively charged.

Rejected implementation: starting a supervised Task synchronously from the service
callback. A suspended Task.Supervisor reproduced a blocked service after lease
expiry; exception handling for task-capacity errors did not bound that wait.
No additional startup layer or generic room-service framework is needed.

These direct synthetic tests establish component lifecycle and two-room admission,
not production cutover, the full operational-Silero matrix, distributed settings
acceptance, measured overhead or live provider acceptance.


## Composed room ownership

Planned RoomIncarnationSupervisor children now include the optional diagnostics
subtree after RoomAuthority. The default port is the Calls-composed SourcePort;
missing Calls infrastructure leaves the room available without observation.
RoomAuthority sends asynchronous lifecycle hints through DiagnosticNotifications.
The shared node pool owns model/inference and the injected collector boundary,
while workers and the single attachment runner belong to the room. The old global
coordinator and agent-selected query are removed; there is one observation owner.

Real planned-room tests establish that room completion waits for admitted worker
termination and retains its slot until DOWN. Exhausting diagnostic restarts leaves
the authority open. The full fresh-Engine-root unresolved-start replacement proof
and broader participant/turn acceptance remain separate open milestone checks.


## Canonical input completion independent of response selection

Diagnostic completion no longer requires a selected text agent or the absence of
an STS response capability. An accepted STT turn carries its allocation, reference
and canonical room IDs into the existing report pipeline. Ownership, current-source
and turn matching still precede this observation. Normal dispatch retains its
separate eligibility rules; no response is synthesized to obtain diagnostic rows.
A human-only configured call persists two independent input runs/rows with missing
response landmarks in both reuse and fallback modes. Configured Scribe-to-Morse
external/hybrid STS control also preserves canonical human diagnostic rows, with
real activity-start/completion checks and no diagnostic ownership of agent audio.
Native STS-only admitted input allocates no observer. Routing-induced STT replacement
and run-boundary integration are covered below.


## Diagnostic source-boundary provenance

A routing change that replaces the human STT allocation retires its acoustic run,
even when participant, connection and capability PID survive. The two capture
handoffs share a first-closure provenance atomic while retaining independent
bounded queues, tokens and open gates. A source retirement records
`source_changed`; expired or revoked settings authority records `lease_expired`.
Later cleanup cannot overwrite that first observed cause. Explicit retirement
checks the existing settings deadline before classifying the closure.

SourceAttachment closes capture before cancelling its attachment lease. SourceWorker
shares the collector handoff's provenance with its input, so a producer-side source
boundary remains visible even if the worker is killed before `terminate/2`.
Collector uses this evidence when draining an invalidated source. Unclassified
attachment cancellation retains the existing lease-expiry fallback.

Rejected alternatives were labelling every closed capture as lease expiry (loses
real source boundaries), relying on worker termination to forward a reason (lost
on kill), and sharing queue/open state (unnecessary change to independent drains).
Focused regressions exercise both closure orders, expiry before explicit close,
queued evidence discard and input closure while a worker is suspended. Configured
external/hybrid routing cases exercise a real fresh STT generation and durable run
boundary with local Silero enabled and disabled.
