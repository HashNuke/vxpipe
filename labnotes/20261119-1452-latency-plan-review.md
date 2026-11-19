# Latency plan review

Review of the revised [passive call latency diagnostics milestone](milestones/passive-call-latency-diagnostics.md)
against the committed implementation through `f46267e4`, 2026-11-19.

Source-only review of the revision above against the committed implementation.
No code was changed and no tests were run. Findings are recommendations for the
plan; none of them checks or unchecks an implementation task by itself.

**Confirmed by source.** `DiagnosticSources.candidates/3` requires a
`text_capability` agent and rejects any room-level STS; `SourceSupervisor.eligible_agent?/1`
repeats the agent check. `SourceAttachment.current_candidate?/1` compares agent
identity, and the configured transfer test expects retirement/rediscovery while
the caller's STT session is retained. `AudioTap` fences on the global
`policy.revision`. `InputTurns.observe_completion/3` carries the text-agent/no-STS
gate and `LiveReport` builds rows only from its packets. `ActivityBoundary` already
emits `:speech_started`, `SourceWorker` forwards it and `LiveReport` already
receives it, so the B/D extension is persistence and presentation, not new
detection. Operational Silero resets its stream and boundary on provider
settlement (`ConversationalSTT`), so reuse-mode endpoint gaps are real. Diagnostic
records are JSON `record` maps, so segment evidence needs no table migration.

**Findings and recommendations.**

1. **Policy fence: narrower fix, wider footprint.** STT already tracks
   participant-scoped intervals: `State.policy_revision` is
   `Snapshot.interval(snapshot, :speech_to_text, participant)`, and
   `State.delivery_intervals_current?/5` checks STT/audio-input/audio-output
   intervals. `SourceDiscovery` (arm, probe and validate) and
   `SpeechToText.attach_diagnostics/5` also compare the global `policy.revision`.
   *Recommendation:* fence the tap, discovery probe and attach on the tuple
   (allocation generation, source STT interval, source audio-input interval),
   reusing the existing interval helpers rather than adding a new permission
   check. Snapshots with `intervals: nil` fall back to the global revision and
   stay fail-closed; record that explicitly. Red-test: unrelated presence/routing
   revision preserves the tap; STT or audio-input interval change closes it.

2. **Composition must respect umbrella dependency direction.** The collector
   factory (`Calls.Diagnostics.Attachment.start/2`) and the source pool are
   composed in `vxpipe_calls` (`Calls.Diagnostics.Supervisor`), which depends on
   `vxpipe_call_engine`. A room-owned service under `RoomIncarnationSupervisor`
   cannot reference Calls. *Recommendation:* keep the node-level
   `SourceSupervisor` (with its injected collector) as the registered port; the
   room service resolves it by its registered name at reconciliation time. When
   the port is absent or down, report `unavailable` coverage and do nothing
   else. Add a test with Calls diagnostics not started.

3. **Worker placement and shared capacity are unspecified.** Workers currently
   live in one node-wide `DynamicSupervisor` with `max_children` from
   `maximum_sources` (default 16, max 32) and `max_jobs: 1`. Reuse-mode workers
   occupy a slot without running inference. Per-participant observation whenever
   collection is on makes the cap a real admission policy. *Recommendation:*
   start each `SourceWorker` in the room's optional diagnostics subtree so room
   teardown bounds its lifetime, and admit it through the existing node-wide
   `AttachmentLease.gate` plus `InferenceAdmission` for benchmark-only inference.
   On exhaustion, record an explicit `capacity_unavailable` coverage reason, and
   let bounded reconciliation retry when a slot frees. Decide whether a per-room
   share is needed so one room cannot take every slot; at minimum test two rooms
   contending at the cap.

4. **Restart intensity needs a concrete supervision shape.**
   `RoomIncarnationSupervisor` is `one_for_one` with default intensity and
   `auto_shutdown: :any_significant`; a permanent optional child in a crash loop
   would end the room. *Recommendation:* add one `restart: :temporary`,
   non-significant child supervisor for room diagnostics with its own explicit
   intensity. Inside it, the service restarts and reconciles. When its own
   intensity is exhausted it stays down, and coverage for the rest of the call is
   marked incomplete. Test: repeated service crashes leave the call open and
   finish with incomplete coverage.

5. **STT that drives STS turn control is unaddressed.**
   `SpeechToTextActivitySource.controller_agent_id/2` binds a caller's STT to an
   STS receiver with `turn_control` `external` or `hybrid`. The new eligibility
   rule makes these inputs eligible. For them, `activity_authority_changed?/4`
   replaces the STT session on routing changes, so transfer continuity does not
   hold, and no text dispatch happens. *Recommendation:* decide explicitly. The
   smaller option is to exclude STT sessions with an `activity_agent_id` for this
   milestone and label them unsupported. If included, treat session replacement
   as a real source boundary and define what the input row means without a text
   response.
   *Revised:* exclusion contradicts the user's direction that eligibility is the
   human's STT audio, independent of the response side. The milestone now observes
   these inputs and treats STT session replacement as a real run boundary.

6. **Segments outside canonical turns have no home.** Noise, uncommitted speech
   and dropped input produce acoustic segments without a turn row.
   *Recommendation:* attach segments that fall inside a turn's source interval to
   that turn (bounded, with omitted count), and keep a bounded per-run record of
   unattached segments with an omitted count, rather than dropping them silently.
   Fixture: one turn with two segments around a pause, plus one noise-only segment.

7. **Migration order lets two owners coexist.** Step 2 builds the room service
   while step 5 removes the global coordinator, so both could own one input in
   between. *Recommendation:* reorder:
   1. input-scoped fence fix (finding 1), which is independent, small and safe
      under today's coordinator;
   2. start/end segment representation and legacy rows;
   3. room service and worker placement, driven directly in tests, not composed
      into production;
   4. one checkpoint that composes the room service and stops starting
      `SourceCoordinator`, then deletes the coordinator/discovery-by-scan path;
   5. eligibility/completion gate removal, transfer continuity, multi-participant
      and failure parity on the new path;
   6. D extensions, then E/F.

8. **Reopened checkboxes mix retained and new work.** Items such as "isolated
   supervision/capacity and versioned settings projection" and the reuse/fallback
   no-duplicate-inference items were unchecked as a whole, although the settings
   projection and inference-reuse proofs remain valid component evidence.
   *Recommendation:* split each into a retained `[x]` item citing its existing
   evidence and a new `[ ]` migration item, so a resumer can see exactly what
   remains.

9. **Uncommitted crash/hang parity tests use the old path.** They depend on
   `discover_with_audio` and `SourceCoordinator.status`, so "re-run failure
   parity" means rewriting them. *Recommendation:* commit them now as old-path
   evidence (with the existing labnote), then port them in the composition
   checkpoint; the provider-byte and turn/output assertions carry over unchanged.

## Milestone updates applied

- Ownership contract: concrete interval-tuple fence (`AudioTap`, `SourceDiscovery`,
  `attach_diagnostics/5`); temporary non-significant room diagnostics subtree with
  its own intensity; workers in that subtree admitted by the node-wide gate with
  `capacity_unavailable`; Calls pool resolved by registered name; unattached
  segments in a bounded per-run record.
- Migration order rewritten to seven steps with a single owner per input at every
  checkpoint: fence first, segments, room service tested directly, one-checkpoint
  cutover, eligibility/continuity, persistence/UI, then E/F.
- C checklist split into migration tasks, retained `[x]` component evidence and
  unchanged open tasks; B segment task extended with unattached segments.
- Review section moved here from the milestone; the milestone links to this file.

## Check against the user's direction

The user's direction: if the participant runs operational Silero, use it for start
and end markers (not provider-side VAD/turn markers); otherwise run Silero as a room
service, one per STT-using participant; speech-to-speech models are irrelevant
because the observed audio is the human's STT input.

- Reuse of operational Silero via `InferenceTap`, fallback per STT participant in
  the room service, and provider markers as separate evidence all match.
- Recommendation 5 initially excluded STT that drives STS turn control. That
  conflicted with "eligibility is the human's STT audio"; the milestone now
  includes those inputs and treats STT session replacement as a run boundary.
- Start/end markers are recorded as acoustic segments attached to canonical turns,
  because one spoken turn can contain several local VAD segments.

Verification: documentation-only; `git diff --check` clean. No code or tests run.
