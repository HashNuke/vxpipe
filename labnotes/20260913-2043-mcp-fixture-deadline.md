# Fixture setup boundaries

- The full umbrella run at seed 633343 failed `WireLimitTest` while opening its loopback
  connection, before invoking the fault tool. The expected assertion concerns an unknown outcome
  after a dispatched tool call times out or disconnects.
- `FaultClient` reused the 100 ms invocation deadline as the HTTP timeout for connection setup
  and discovery. Host scheduling delay could therefore fail an unrelated prerequisite.
- Keep connection/setup requests on the fixture's existing bounded 5-second default. Preserve the
  explicit 100 ms `Invocation.call` deadline and the assertion that exactly one tool call reaches
  the server. No production timeout changes.
- The recording fixture also repeatedly exhausted an arbitrary 100 ms policy-setup deadline under
  full-suite load. Use the room's existing 1-second enforcement budget for this test of recording
  contents and permission boundaries; its assertions do not concern enforcement speed. The test
  passed alone and in one full run before the change. An earlier concurrent-browser run also
  exceeded a 1-second mixer call; that production timeout remains unchanged. A later default-16
  concurrency run still hit that mixer timeout and a billing fixture's 1-second acknowledgement.
  With host load above 10, final verification reduces ExUnit concurrency to four modules instead
  of relaxing production calls or unrelated billing assertions.
- A reduced-concurrency run passed recording/billing but exposed a lifecycle monitor race:
  the policy-authority exit test observed `:noproc` rather than `:shutdown`. Synchronize with the
  room after installing its monitor and before killing the significant child, so cross-process
  shutdown cannot overtake monitor establishment. Apply the same acknowledgement to the adjacent
  mixer/router shutdown checks. This changes only fixture synchronization.
- The three focused wire-limit checks and four lifecycle/recording checks pass. Final umbrella
  verification passes 1,007 tests with zero failures and 15 integration exclusions at seed 633343
  and four concurrent modules. Formatting, warnings-as-errors compilation, strict Credo, and
  unused dependency checking also pass.
