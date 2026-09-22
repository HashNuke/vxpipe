# Handoff binding integration

- Integrate the native agent's coherent closed-gate descriptor repair from
  `1e3d114f`, fixture correction `ebc8287f`, and their evidence through `468a1ab8`.
  Preserve main's later Google work and the parent's queued private-connection-
  DOWN classification repair. Applied only the seven scoped changed files.
- Parent read the production, fixture, owning-child and contract diffs.
  Independent xhigh source review clears the production repair: authoritative
  graph recapture and collector reconciliation occur before release, require
  fresh descriptor evidence and a drained cue, and retain the original deadline.
  Post-release failures stay fatal. The reviewer did not rerun tests.
- Agent owning-child red fails before a fresh cue, then passes after repair;
  the room/collector/barrier group passes 66 tests. Controlled native red proves
  terminal release `binding_changed`. First attempted native green instead found
  a fixture overconstraint during recapture, not a terminal handoff result.
- Parent reviewed the corrected fixture against that evidence: it now demands
  the current published preparing report and exact late-listener descriptor;
  only superseded binding-change notifications may be skipped. Its receive loop
  checks the original deadline even while consuming notifications. Other failures
  and terminal phase outcomes still fail immediately.
- Agent controlled native run at `ebc8287f` is terminal green: one test, zero
  failures, 67 excluded, seed 0, two schedulers, 169.8 seconds. The original
  one-second pause and three-second activation bound are unchanged; final audio
  and conversation checks pass. This proves that controlled defect, not a common
  cause for every earlier no-terminal-result timeout.
- Main focused verification is green: **67 tests, zero failures**, seed 0,
  56.0 seconds. It includes main's queued private-connection-loss regression,
  which remains intact along with its scoped Authority classification repair.
  From the Call Engine child with `ERL_FLAGS='+S 2:2'`:

  ```sh
  mix test test/vxpipe/call_engine/human_web_transfer_room_test.exs \
    test/vxpipe/call_engine/readiness/collector_test.exs \
    test/vxpipe/call_engine/readiness/barrier_test.exs --seed 0
  ```

- Commit this coherent integration before post-commit static/full umbrella gates.
  No native or load worker remains active; finite-recognition implementation is
  isolated in its own worktree. Full milestone acceptance stays open.
