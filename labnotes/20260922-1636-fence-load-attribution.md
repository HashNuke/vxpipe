# Fence comparative-load timing attribution

Parent review of `962c98d4` identified a race: input origin was captured after
feeder creation, and second sink audio could allow barge-in before second public
agent/caller onset arrived. Those delayed events then inherited input three's time.
Recorded a milestone repair task before tests or implementation.

The deterministic reordered-onset regression failed first with the missing
attribution module, then passed. It binds second sink audio, finishes second
input, and proves third input cannot start until both caller and public onsets
arrive. After third input starts, second caller/public/sink IDs still measure from
their immutable second origin. Additional coverage checks late caller onset,
separate namespaces, duplicate/extra IDs, unknown IDs and mismatched input completion.

Runner now captures origin before launching the feeder and uses the attribution
gate for all input transitions. Timing on completion/acknowledgement resolves the
bound namespace/ID. Public onset/completion/interruption validates exact room,
incarnation, connection and participant. Interruption must identify input two's
known public turn; its latency uses input three's pre-spawn origin.

The test DynamicSupervisor and Task.Supervisor now use explicit unique Registry
names scoped by a reference, with no dynamically created atoms. No production
runtime changes or measured load are included.

Verification: seven focused harness contracts pass (including the two deterministic
reordering checks), zero failures. `bin/sts-call-load smoke` passes all three
two-call modes, zero failures, seed 0, two schedulers, about 25 seconds. Each mode
retains five completions, two interruptions, one post-fault survivor and two clean
room teardowns, with no input drops or output rejection. Targeted formatting,
`git diff --check` and child test-environment warnings-as-errors compilation pass.
Reproduction commands are in `docs/development/sts-comparative-call-load.md`.

No measured lane, production fix, or umbrella suite was run. Final integrated
acceptance remains parent-owned and awaits the quiet window.

Additional parent review found scheduler-sensitive sink assertions: after a 30 ms
negative receive the test assumed interrupt/clear would still precede a 200 ms
finish. Recorded the follow-up in F before revising its regression. The new test
failed first because the sink did not supply its captured scheduled token.
Test support now accepts optional clock/scheduling callbacks; defaults remain
the real monotonic clock and `Process.send_after`. The test advances controlled
PCM time, captures the exact finish tokens, injects old tokens after interruption
and clear (including during a replacement output), and uses `:sys.get_state`
acknowledgements plus `assert_received`/`refute_received`. A current token still
completes with the exact consumed duration. No wall-clock upper-bound assertion
or widened timeout remains. Seven focused tests pass with this deterministic
version. The final actual-paced smoke rerun also passes all three modes, zero
failures, seed 0, two schedulers, 25.0 seconds. Targeted formatting and child
warnings-as-errors compilation pass on the final source. The measured lane
remains unrun.
