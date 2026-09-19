# Native handoff verification

- Started after reviewed service checkpoint `a7585f2`. Service/Console suites pass;
  full-root acceptance remains open after two different native handoff failures.
- B2 serial run (seed 772211) failed the five-participant reconnect wait tone at
  line 518; isolated run failed later at ordered cue/conversation audio. B3's same
  serial seed passed that case but failed `after_speech_adoption` preparation at
  line 2251 while waiting for `transfer.progress preparing` with a speech blocker.
- Running only the existing `preparation:after_speech_adoption` tagged case from
  Gateway, with the same seed and no browser/server fixture. No implementation,
  assertion or timeout change yet. Inspecting readiness reporting and the native
  gate fixture to distinguish a product race from test synchronization.
- Read-only investigation: the fixture's native gate auto-releases after one second;
  the test also explicitly releases it in `after`. This could weaken the intended
  ordering under delay, but it is only a hypothesis. ICE gathers every host interface
  and only the first candidate is trickled; no evidence currently ties that to failure.
- Isolated command completed: one test, zero failures, 67 excluded, seed 772211.
  No fix is claimed. The full-suite failure remains an acceptance concern; changing
  native synchronization or ICE configuration without a reproducible failure would
  be speculative. Continue independent scoped Telnyx work and retain the final full
  umbrella gate, with this evidence available if the failure recurs.
- Later presence-correction umbrella run passed all 1,763 tests with 40 exclusions,
  including all 445 Gateway tests. Same serial seed 772211, no native code change.
  This closes the current acceptance gate without claiming a root cause or flake fix.
