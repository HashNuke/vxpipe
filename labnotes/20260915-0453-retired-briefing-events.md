# Retired briefing events

## Reproduced failure

The existing private-resource retirement checks delivered late briefing events while the pending
attempt still retained its `HumanPreparation` struct with a nil TTS handle. During source recovery,
the preparation itself is nil. `HumanBriefing.matches?/3` had no matching clause for that state.
A delayed completion notification therefore crashed RoomAuthority during otherwise valid recovery.

Extend the real timeout and phase-loss handoff cases: complete and retire the private briefing,
fail the attempt, pause the actual recovery cue at its final output drain, and deliver the retired
resource's playback, unavailable and monitor notifications. Both cases fail with
`FunctionClauseError` in `HumanBriefing.matches?/3` before the recovery can finish. This is a
specific reproducible stale-event defect; it does not establish the cause of the historical native
recovery result `{:error, :unavailable}`.

## Change

Treat a pending attempt without a matching human preparation as unrelated to the old briefing
request. Keep exact capability and request matching for live private preparation. No resource
restart, new owner, public field, UI change or deadline adjustment is required. After the mailbox
barrier, the pending recovery must be unchanged; releasing the actual output drain must finish
recovery with the retained source TTS and no duplicate briefing/acceptance observation.

## Evidence

- Red: two real handoff cases fail at the missing match clause, not at test setup or timing
  (`vxpipe-retired-briefing-events-red.log`: two tests, two failures, 34 excluded).
- Green: all three briefing/acceptance/recovery cases pass after the matching fallback
  (`vxpipe-retired-briefing-events-green.log`: three tests, zero failures, 33 excluded).
- The complete owning human-handoff file passes: 36 tests, zero failures, in 33 seconds
  (`vxpipe-retired-briefing-events-engine.log`).

## Completion checks

All five umbrella gates pass: `mix format --check-formatted`,
`mix compile --warnings-as-errors`, `mix credo --strict`,
`mix test --max-cases 4 --seed 235296`, and `mix deps.unlock --check-unused`.
The suite reports 1,405 tests, zero failures and 16 integration exclusions; the runner's
`vxpipe-retired-briefing-gates-results.json` records zero for every gate. The full run includes
641 engine tests and 392 Gateway tests, with 58 default native startup/transfer cases.

Documentation links resolve and whitespace checks pass. Preserve the unrelated site/visual work.
Keep the broader private-resource and failure-cleanup tasks open: this fixes the reproduced stale
event crash, and does not claim to explain the historical native `unavailable` recovery result.
The milestone and index still report 20 remaining checkpoint tasks.
