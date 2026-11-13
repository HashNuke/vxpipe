# Gateway test deadlines

- Broad call-cleanup verification exposed two existing test timing assumptions.
- The room-audio policy test awaited a Task-started pipeline shutdown with the
  default 100 ms receive timeout. It passed in the main umbrella run but missed
  that acknowledgement in a concurrent run. Retain the same owned message and
  give it a bounded one-second window; do not sleep or change the runtime.
- The MCP deadline test configured 20 ms for session initialization as well as
  the blocked request under test. A nonconcurrent Gateway run timed out during
  initialization and returned no session header. Initialize with the normal
  timeout, then apply 20 ms to the blocked request. Await its owned notification
  for up to one second; keep the handler-timeout response and termination checks.
- Focused regression run: 13 tests, zero failures. Final formatting and strict
  Credo pass. Full Gateway verification passes: 886 tests, zero failures,
  17 integration exclusions, 321.7 seconds.
