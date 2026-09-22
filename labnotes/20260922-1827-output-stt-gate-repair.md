# Output STT gate repair

- Post-commit root gates at `9bf245a5`: format and warnings-as-errors compile
  pass; strict Credo fails because PlanStartup grew to 806 lines (limit 800).
  The command stopped there; unused-lock and full tests had not run.
- Recorded the repair task before editing. Keep participant-format admission
  and its sanitized error construction together in the existing OutputSTTFormat
  helper; PlanStartup delegates at the same two boundaries in the same order.
  No behavior or validation policy changes, so existing focused contracts are
  the regression evidence; the strict design check is the red gate.
- Preserve the exact error code, message, path and reason, and independent human
  STT/private configuration behavior. No provider, runtime lifecycle or native
  transfer change belongs to this refactor.
- PlanStartup is now 789 lines. The unchanged focused startup/selection/room
  transcript group passes **54 tests, zero failures**, seed 0, with two schedulers.
  Exact source formatting and diff inspection pass. Commit this refactor before
  restarting the four static gates and full umbrella suite.
