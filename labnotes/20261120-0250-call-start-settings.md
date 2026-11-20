# Call-start diagnostics settings

The approved behavior is one persisted settings read per new call. An existing call keeps its initial enabled or disabled choice, including when its diagnostics observer restarts. A missing, failed, malformed, or stalled startup read disables diagnostics for that call without failing the call.

`RoomIncarnationSupervisor.child_spec/1` prepares the diagnostic children in the requesting process, before submitting startup to the shared room supervisor. `RoomSupervisor.options/3` captures the immutable `CallSettings` value during that preparation. The same value follows discovery, input attachment, source worker and collector handoffs. Capture checks remain pure; there is no per-frame settings process or database access. The read uses a monitored per-call worker with a 250 ms timeout and kill timer. Loader errors or untrappable worker death disable diagnostics; the timer also bounds stalled work if its caller dies. No shared task-supervisor admission occurs on this path.

Removed the settings projection, reader, supervisor, lease, application children and settings lease renewal/expiry. Cross-worker polling and revocation are deliberately not retained. Source admission leases, attachment deadlines, source ownership, port-loss teardown, bounded capture queues and optional-observer failure isolation remain distinct and required.

Verification:

- Red: new call-start contract tests failed as expected (3 tests, 3 failures: missing immutable snapshot implementation).
- Green: initial call-start and application composition tests passed (10 tests, seed 683632).
- Final focused owner run: CallSettings, application composition, RoomService and InputAttachment passed (49 tests, seed 38897), including observer restart and malformed-read failure isolation. Removed an unused setup binding reported by that run; InputAttachment was rechecked separately.
- Formatted changed Engine, Calls and Persistence Elixir implementation/tests. Obsolete settings module references are absent from application source and test trees.

No live provider, Telnyx, model inference coverage, database CPU check, full-suite run or commit was performed for this checkpoint.

Root checkpoint checks pass: format, compile with warnings-as-errors, strict
Credo, unused dependency check and Lean model/replay lane (one test). Full suite
remains deferred until milestone implementation is complete, per user instruction.

## Review correction: startup read boundary

Astra reproduced that suspending ReadinessTaskSupervisor delayed the prior supervised-task admission beyond the 250 ms read bound (still waiting after 600 ms), and a stalled read inside RoomIncarnationSupervisor.init blocked unrelated node-wide room-supervisor queries for 276 ms. The snapshot now happens in child-spec construction before shared startup, and uses a directly monitored worker rather than shared task admission. Prepared diagnostic children retain the same snapshot through observer restarts.

Red evidence: 7 focused settings tests, 2 expected failures (no snapshot during child-spec construction; suspended task supervisor blocked capture). Added an untrappable loader-death assertion to retain optional-feature failure isolation. Green: CallSettings, RoomService, room completion and participant joining passed together (45 tests, seed 36879).

Independent GPT-6.2 Astra xhigh final review is clean. Reviewer reran both
startup reproductions against the corrected build: suspended readiness supervisor
did not delay the enabled read, and a stalled loader did not delay an unrelated
shared room-supervisor query (both 0 ms at millisecond resolution).
