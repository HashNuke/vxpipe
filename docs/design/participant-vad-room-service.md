# Participant VAD observation owned by the room

Status: input-interval fence implemented; room-service migration pending. 2026-11-19.

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
- `InputTurns.observe_completion/3` also requires a text capability and excludes
  room-level STS, while `LiveReport` builds rows from its completion packets. Remove
  this diagnostic gate without changing dispatch/control rules; assert persisted
  canonical STT input timing with nullable responses for no-agent and mixed rooms.
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
