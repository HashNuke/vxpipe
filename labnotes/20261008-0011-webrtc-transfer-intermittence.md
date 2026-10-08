# WebRTC transfer intermittence

## Approved scope

2026-10-08: Continue from 842aad6b. The user defers investigation of the
five-participant listener-reconnection scenario. Investigate and fix the two
other recorded failures: missing terminal progress after a human handoff release
deadline, and room-audio output loss during repeated AI transfers. Gemini's
ten-minute live acceptance must wait until these WebRTC issues are resolved.
Retain existing coverage while reducing reproductions to their owning boundaries.
Do not increase deadlines or add timing delays to make failures disappear.

The worktree initially contains only the unrelated Wrangler labnote. Preserve it.
Never read or modify the private live-provider env file. Use local boundary tests
first; new behavior must have a confirmed red before implementation. Prior commit
authorization remains in effect for a verified coherent checkpoint.

## Initial evidence and investigation

Final scope clarification: the caller is human, the other party may be an agent
or a human, and transfers may target either type. Preserve that full two-party
path. Additional listeners and the five-person reconnection scenario remain
deferred. Gemini's long acceptance follows the WebRTC transfer repairs.
The user explicitly limits this to test prioritization: add no participant-count
or participant-kind restrictions to runtime code, and retain existing coverage.

The earlier full runs failed different native transfer cases, while an isolated
67-case handoff suite and the final 3,269-case default run passed. Neither green
run established a cause or a fix. The release-deadline capture shows the expected
handoff_release_failed room shutdown but no client terminal sideband event. The
repeated-AI capture shows an egress shutdown followed by policy-authority failure
and a policy_changed transfer result before model preparation.

Start with terminal publication/connection teardown ordering and with the egress
take/push boundary. Preserve privacy fencing and exact monitored shutdown checks;
do not infer that all egress failures share one cause.

The isolated native release-deadline case passes, seed 44264 (one test, zero
failures). Code inspection finds a separate deterministic closing defect: a held
handoff and ordinary room attachment both monitor RoomAuthority, but the former
DOWN stops Connection immediately while the latter uses the existing 250 ms
peer-left grace. That bypass can tear down a datachannel with queued terminal
progress. The owning Connection regression first fails at the immediate stop
(one test, one failure, seed 944956). A fixture compile error was corrected before
that meaningful red; it is not behavior evidence.

Reuse the existing peer-left path for handoff-owner loss. During that already
bounded closing state, subsequent dependency DOWN messages must not shorten or
restart its grace. A dead peer still stops immediately, and the held gate is
retained. No timer duration or new grace is introduced. The regression checks
terminal progress, one peer-left notification, duplicate owner loss, the exact
existing timeout token and actual transport death.

The connection/source/audio group passes 10/0 (seed 999120), and the native
release-deadline case passes after the change (one test, zero failures, seed
44264). A new caller-with-agent repeated-transfer test omits extra listeners and
retains audio, transcript, wait/cue privacy and recording checks through billing,
reception and billing again. Its initial run passes (one test, zero failures,
seed 44264), so it is regression coverage, not a reproduced output-loss cause.

The old output-loss shutdown lacks its take/push cause. Add focused red tests for
bounded stage/reason telemetry before changing diagnostics; preserve the exact
terminal failure and owner notification. That instrumentation is for diagnosis,
not itself a claimed repair of audio loss.

Diagnostics red: the egress suite has 10 tests with two expected missing-event
failures (take and push). The privacy check separately fails because the new
bounded diagnostic API is absent. Implement stage/reason events before ending
the same boundary; retain original owner failure reasons and exact shutdown.
Reuse the existing bounded failure classifier; no payload, actor identity,
authorization or arbitrary exception detail is logged. Pipeline and release
failures have their own stage labels. Run the owning egress/policy/telemetry group
before new native repetitions.

The egress/policy/telemetry/connection group passes 22/0. Replace a generated-test
constant comparison with a test helper to remove an Elixir typing warning; this
changes only fault injection. Start five repetitions of the two prioritized
native cases in one VM, using Mix's documented repeat-until-failure option. Keep
the first failing selection, if any, with its newly categorized egress reason.

The repeat option performs an initial selection plus five repeats: six passing
selections, 12 native checks, zero failures, seed 44264. Every selection tests
the release-deadline notification and caller-only repeated agent transfers;
none reproduces egress loss. This establishes scoped regression evidence, not
the cause of the old listener-re-entry failure. Run all six completion commands
serially, retaining broad-suite failures with the new diagnostics rather than
silently excluding existing tests.

Format, warnings-as-errors compile and strict Credo pass. The full run exposes a
pre-existing Call Engine fixture race: external STT-replacement activity is nil
after 200 tight room-state polls. Replace that polling with its already-published
ParticipantTurnStarted acknowledgement before reading the activity binding.
Retain caller identity, current generation and stale-end rejection assertions;
no runtime behavior or timer is changed. Verify the four owning variants after
the active root run completes so Mix writers remain serialized.

The complete Gateway default lane passes 577/0, including the unchanged larger
native cases. Root acceptance stops only on the recorded STT fixture race.
The onset acknowledgement must be retained for the later correlation assertions;
an initial helper edit consumed it twice, and a subsequent edit mistakenly used
the assert_receive tuple instead of the bound event. Both fixture mistakes were
corrected before acceptance. A repetition then exposed a second fixture race in
transcript-only STT rotation: the replacement input was read before provider
initialization completed. Synchronize on the old capability's monitored DOWN,
acknowledge admission, monitor initialization tasks, then acknowledge channel,
capability and room processing. This replaces its short state polling loop, adds
no timing delay, and changes no runtime behavior. An assumed shutdown reason was
removed from this setup acknowledgement because existing hold retirement can
report unsafe_hold. The replacement identity, input epoch, caller publication
and audio output remain asserted. The final owning suite passes six selections,
222 checks, zero failures, seed 44264.

The original repeated-transfer/listener-re-entry case passes an initial run plus
ten repetitions: 11/0, seed 44264. It produces no output-failure diagnostic. Keep
the earlier loss unresolved rather than claiming that a green repetition or
instrumentation repaired it. Final root completion checks are running serially.

The user reiterates that live provider tests should run only for provider-specific
issues because they cost money. No live provider or carrier tests have run in
this task; all new evidence uses local boundary/native WebRTC checks. Gemini's
long-session acceptance remains deferred.

## Verified checkpoint

All final completion commands pass: formatting, warnings-as-errors compilation,
strict Credo, default tests, unused-dependency validation and Lean. The final
umbrella run has 3,274 tests, zero failures, 114 excluded (seed 44264), including
1,943 Call Engine and 577 Gateway tests. Lean builds its four jobs, detects no
oracle drift and passes its Elixir conformance replay. Documentation targets and
the follow-up anchor are verified; git diff --check passes.

The closing bypass is repaired, repeated caller/counterpart transfer coverage is
retained, and bounded diagnostics preserve the original audio failure behavior.
No runtime participation limit, deadline increase, timing delay or hosted test
was introduced. The earlier listener-re-entry output-loss cause is not established;
it remains unchecked in the owning milestone. Five-participant investigation and
Gemini's ten-minute acceptance remain deferred. Preserve the unrelated Wrangler
labnote when staging this checkpoint.
