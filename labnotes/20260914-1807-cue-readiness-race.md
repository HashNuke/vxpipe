# Cue completion during readiness rechecks

- The human wait/conversation verification reproduced the existing cue-drain completion failure
  in the full umbrella suite (`vxpipe-wait-conversation-test.log`, seed 56228). The new four WebRTC
  wait configurations passed; the failure was in the engine's existing cue scenario.
- A cue player sends `:completed` and exits after its output drain acknowledgement. During the
  periodic readiness refresh, `await_ready` selectively received the player's `:DOWN`, skipping
  the queued completion. It incorrectly returned `:playback_unavailable`, initiating recovery
  even though the cue had finished. The original drain fixture could then exhaust recovery because
  its output deliberately deferred another drain.
- Added a controlled case that defers a connection readiness reply, completes cue playback, observes
  the player's normal exit, then releases readiness. It and the ordinary drain case failed before
  the change (`vxpipe-cue-recheck-completion-red.log`: five checks, two failures).
- When a monitored player exits during collection, check for its already-queued completion. Preserve
  that message for the playback barrier and remove the completed player from the recheck's pending
  list. An exit without completion still fails; actual provider/player failures and deadlines retain
  their existing behavior. No timeout or readiness requirement changed.
- All five focused cue scenarios pass after the change (`vxpipe-cue-recheck-completion-green.log`),
  including provider loss, cue-player loss and expiry with unusable recovery output. Full root gates
  are being rerun with the failing seed and the pending WebRTC verification changes present.
- Final joint-worktree verification passes all five required root gates with seed 56228 and four
  concurrent cases: 1,289 tests, zero failures and 15 integration exclusions. All 594 engine and
  325 Gateway tests pass (`vxpipe-cue-conversation-final-results.json` and its five logs). This
  includes the four ordinary WebRTC wait/conversation cases being committed separately; it is not
  a separately measured test count for this isolated fix. No dependency or UI change was needed.
