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
