# Transfer lifecycle observations

## Scope and decisions

Finish the human-handoff diagnostics item after the bounded protocol reasons committed in
`85c26a1`. Reuse existing phase telemetry and the Console reporter. No additional process,
supervisor, deadline, call configuration or UI component is required.

Briefing timing covers its successful playback request through acknowledged playback.
Acceptance starts after private briefing TTS retirement and ends on authenticated acceptance,
failure or timeout. The pending attempt owns these timestamps and clears them on observation,
so stale playback and duplicate controls do not create another duration. Finite cue players
measure their actual lifetime through final output drain; repeated cues are separate episodes.
Looping waits do not produce cue durations.

Keep normally returned audience/prepare/release/recover worker timings at their existing boundary.
Moving that boundary would also break tests that pause a real worker before it returns. Forced
termination is observed by the surviving supervisor/authority: count a confirmed cancellation
only when the supervisor terminates a child, and count an unexpected exit from the exact pending
task monitor. A missing child does not prove a cancellation. No timing relies on `terminate/2`.

The existing player has one pending output slot per sink. Sample the first frame and every 50
frames, plus drain and terminal transitions. At normal 20 ms pacing this adds about one periodic
sample per second. Depth reports occupied slots in the current frame/drain batch; it is not an
RTP packet count or a count of only the acknowledgements still missing. Console keeps finite
aggregates of sample counts and peak depth/capacity, not per-listener histories or current queues.

Gateway counts frame submissions rejected or discarded by its existing output arbiter, using
closed room/direct and busy/held/cleared/clearing/stale/invalid/unavailable categories. These
counts do not claim to measure network packet loss or partially played audio. All new event data
is sanitized before entering the reporter mailbox; no audio, IDs or private payloads are retained.

## Red-green evidence and barriers

- The real human handoff first failed on its missing briefing observation. An initial syntax
  error in the player state edit was corrected; the focused handoff then passed. The same flow
  now covers acceptance, actual deadline handling and a killed phase, with one distinct
  acceptance outcome, ordered recovery cue and retained source TTS: three cases pass.
- Existing worker-cancellation and two-sink playback checks failed on missing worker/pressure
  events. Their engine batch passed all 44 tests before the two extra acceptance outcomes.
- Gateway's real busy/held/stale submission checks failed on missing drop observations; all 22
  output-arbiter tests pass after adding observations at those existing rejection boundaries.
- Console's lifecycle/pressure test failed on missing aggregation. All ten reporter tests pass,
  including private sentinel removal before mailbox admission and bounded unknown categories.
- No dependency workaround or native media change was required. Earlier intermittent recovery
  concerns remain tracked by the human failure-cleanup item; this work does not claim to fix them.

Focused logs: `vxpipe-transfer-lifecycle-red.log`, `vxpipe-transfer-wait-timing-outcomes.log`,
`vxpipe-transfer-observations-engine.log`, `vxpipe-transfer-drops-red.log`,
`vxpipe-transfer-drops-green.log`, `vxpipe-transfer-reporting-red.log`, and
`vxpipe-transfer-reporting-green.log`. These are local execution artifacts, not repository files.

## Completion verification

All five root gates pass: `mix format --check-formatted`,
`mix compile --warnings-as-errors`, `mix credo --strict`,
`mix test --max-cases 4 --seed 235296`, and `mix deps.unlock --check-unused`.
The full suite reports 1,401 tests, zero failures and 16 integration exclusions. Engine has 641
tests, Gateway 388 and Console 95. The root runner's
`vxpipe-transfer-observations-gates-results.json` records zero for every gate. No UI code changed.

Mark the human diagnostics item complete; 20 checkpoint tasks remain: human 3, AI 3, phone 6,
changing/multiple listeners 6 and final audit 2. Remaining failure cleanup and resource-policy
acceptance retain their open checkboxes. The broader milestone remains incomplete.
