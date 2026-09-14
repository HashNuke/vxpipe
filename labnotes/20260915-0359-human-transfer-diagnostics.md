# Human transfer diagnostics

## Scope and inspection

Finish the existing human-handoff diagnostics contract without a new UI component. Inspection
found that public progress carries phase/blockers/elapsed time but no bounded failure cause.
The existing worker timing event covers normally returned audience/prepare/release/recover work,
not briefing/acceptance/cue spans or killed workers. Player queue/drop observations remain absent.

Start with caller/destination reason delivery through the existing RTVI and transfer sideband
channels. The native recorded-recovery case requires the recorded failure category in the caller's
recovered event. Both Gateway codec boundaries must preserve that engine-owned reason and omit
unrelated private details. Keep the timing and queue work explicitly open until implemented.

## First checkpoint: protocol failure reasons

Red: the native recorded-recovery caller received `recovered` without a reason. Both protocol
codec cases also omitted the reason. Progress now maps internal causes to a closed public code;
unknown causes become `unavailable` instead of reflecting their contents. Existing RTVI and
transfer-sideband codecs retain that optional field and strip unrelated private fields. Healthy
transfer messages keep their existing shape. The outer transfer tool error remains generic.

Recovery progress is now published before discarding the private destination. The same code
reaches the caller after restored conversation, and terminal release failures expose timeout or
speech loss. No waiting/resource/deadline behavior changes. Nineteen Gateway codec tests pass;
native checks require the connected desk's pre-cleanup reason, the caller's recovered reason,
and distinct terminal release reasons. Full verification follows.

Keep the diagnostics checklist item and task count unchanged until separate lifecycle timings,
forced-worker observations and queue/drop measurements are also implemented. The normally
returning-worker timing event cannot establish those missing observations.

The first three-case native run passed terminal release timeout and STT-loss reporting. The
recovery case received `media_unavailable` before the speech owner reported its more specific
loss: the readiness collector can observe the failed binding first. Both are existing valid
engine failure causes. The assertion now checks the known category and requires the caller's
recovered reason to equal the connected desk's earlier reason. It does not invent a provider
diagnosis from a generic readiness failure. The public field is limited to the category supplied
by that engine path; this checkpoint does not add a more detailed readiness-failure taxonomy.

## Boundaries for the remaining diagnostics

- `HumanHandoff.progress/2` starts the private briefing only after destination media is usable.
  `HumanBriefing.complete/2` runs after acknowledged playback; this is the start of acceptance
  waiting. Authenticated `apply_control(:accept, pending)` ends that window. Duplicate controls
  and stale playback must not duplicate observations.
- `HumanMediaHandoff.cue_release/4` and `await_players/5` own cue ordering and final drain.
  Readiness retries can repeat cues under the same deadline; measure each actual episode.
- Existing `transfer.phase.stop` measures normally returned worker spans. Engine tests use this
  event in `pause_handoff_result` to pause a real worker before returning its result. Preserve
  that boundary when adding lifecycle timing.
- Nested handoff workers link to the phase process. A killed worker/phase cannot emit a reliable
  terminal event itself. The surviving authority's exact task-monitor path (`worker_down/3`)
  observes unexpected termination; normal results and cancellation already settle that monitor.
- Wait players hold one pending frame per output sink and advance after acknowledged completion.
  Their pending map is the queue-pressure boundary; per-frame events should not become unbounded
  diagnostic traffic. Actual discarded frames need evidence from their output/ingress owner.

The recovered-call reason check passes in 47.9 seconds. The full root runner is now checking
this checkpoint; no timing/player implementation is included yet.

## Completed protocol checkpoint

All five umbrella checks pass: `mix format --check-formatted`,
`mix compile --warnings-as-errors`, `mix credo --strict`,
`mix test --max-cases 4 --seed 235296`, and `mix deps.unlock --check-unused`.
The full suite reports 1,398 tests, zero failures and 16 integration exclusions. Gateway reports
388 tests; its 54 default native cases include the updated recovery and terminal-release checks.
The runner results file `vxpipe-transfer-reasons-gates-results.json` records zero for every gate.
The milestone and index retain 21 remaining tasks; the diagnostics item stays unchecked.

This checkpoint changes engine-to-client protocol data and no rendered UI. The current sample
components continue to own their presentation; a reason is available to native clients and
protocol consumers without exposing provider responses. No dependency or deadline change was needed.
