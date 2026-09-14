# Startup failure cleanup

## Reproduced gaps

After independent opening playback was committed, the next startup pass found that silent waits
have no player to report output loss, and unexpected player death bypasses its playback callback.
The existing CallLifecycle.ready response also accepted calls after readiness had expired.

- The initial focused run was red in four places: late readiness returned success, explicit
  detachment and process death left silent startup/model preparation running, and a killed wait
  player left startup running (`vxpipe-startup-cleanup-red.log`).
- Added lifecycle rejection after expiration/failure, cancellation of removed connection waits
  and probes, last-entry-caller startup failure, and wait-player monitors. The 11 focused lifecycle
  tests now pass (`vxpipe-startup-cleanup-green.log`), including termination of blocked model work.
- Next boundary checks cover clearing queued audio after explicit detachment and preserving
  startup when another connection still belongs to the caller. Startup failure/clock/diagnostic
  acceptance remains open until the complete scope is verified.

## Audio cleanup and clock evidence

- Explicit detachment still left the output fixture's queued callback after its player stopped;
  that focused assertion was red (`vxpipe-startup-detach-red.log`). Removing a startup connection
  now clears its output, cancels its exact probe/player and invalidates the whole-room probe.
  A prepared room restarts that probe for remaining connections. Another connection belonging
  to the entry caller keeps startup alive and reaches ready after the same model preparation.
- Readiness and maximum-duration tests hold both model construction and the opening fetch while
  actual wait PCM is queued, fire the original lifecycle timer, and observe termination of all
  three workers and RoomAuthority. Attaching and preparing do not reschedule the original clocks.
- A lifecycle-only test reproduced success from ready after the maximum-duration event had
  already fired (`vxpipe-startup-deadline-red.log`). Expiration now fences late ready calls,
  including maximum-duration expiry; ready remains idempotent only for a ready lifecycle.
- The 31 focused lifecycle/opening tests pass (`vxpipe-startup-cleanup-focused.log`). The generic
  process-monitor dispatch moved intact to RoomAuthority.ProcessDown after green; RoomAuthority
  was at its configured module-length limit. Startup-specific player loss now joins that dispatch.
  This is a callback ownership extraction, not a new supervision layer.

Native startup failures are being checked next for terminal signalling on the actual data channel.

## Native terminal-signalling detour

The native failure checks reproduced a Gateway ordering defect for readiness expiry,
maximum-duration expiry and failed model construction: RoomAuthority sent connection_unavailable
before exiting, and that handler closed the connection immediately. This bypassed the existing
RoomAuthority-DOWN peerLeft/grace path, so the native caller received no terminal signalling.
All three cases were red (`vxpipe-startup-native-failure-red.log`). Gateway now reuses the existing
peerLeft path for the explicit unavailable event and ignores duplicate termination triggers once
the grace token is set. No new protocol or UI component was added. The three cases pass, then
also check Gateway connection termination and absence of duplicate/late channel messages.

## Verification and next boundary

- The combined focused engine run passes 31 lifecycle/opening tests.
- The combined native startup/transfer and RTVI files pass 29 tests, zero failures
  (`vxpipe-startup-cleanup-native.log`), including terminal signalling and connection teardown.
- All five root checks pass: `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix credo --strict`, `mix test --max-cases 4`, and `mix deps.unlock --check-unused`.
  The umbrella reports 1,322 tests, zero failures and 15 integration exclusions (seed 879358).
  Per-app counts: MCP 37, agent runtime 91, engine 610, Calls 81, Gateway 342, persistence 19,
  ingress 49, Console 93. Logs/results use `vxpipe-startup-cleanup-gates-*`.
  No UI files changed and the user's dev server was not restarted.
- Remaining startup work includes safe readiness-blocker/timing diagnostics, deterministic phone
  clock/failure acceptance, and release freshness. StartupProbe currently returns a completed
  observation and stops its collector; its successful result must not serve as indefinite proof
  through a long opening announcement or later policy/resource change. Revalidate that exact
  required graph before initial conversation release in the next focused pass.
