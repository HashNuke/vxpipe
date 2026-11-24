# Room shutdown monitor ordering

The room-shutdown test failed at umbrella seed 652242. Its participant monitor returned `:noproc`; the assertion required `:shutdown`. The unchanged case, selected alone with that seed and repeated in one VM, passed 490 times and failed on execution 491 with the same monitor result. Each execution creates fresh room and participant IDs, and the fixture's cleanup targets its own incarnation.

The test sent the monitor request to the participant and the kill signal to a different process, the room authority. The test had no acknowledgement from the participant between those operations. It now reads the snapshot from the exact monitored PID and matches it to the admission result before triggering shutdown. The synchronous reply orders observation before the supervisor tears down the room. The test still requires the shutdown reason from the exact monitor and PID.

The corrected case passed 3,001 consecutive executions at seed 652242. The trace confirmed selection of the shutdown case. Both the participant and opening-audio room modules passed together (43 tests). Formatting, warnings-as-errors compilation, strict Credo and the unused-dependency check passed.
