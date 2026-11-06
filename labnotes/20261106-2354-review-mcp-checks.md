# Review MCP checks

- Independent source review found loopback admission, cancellation during blocking
  client initialization, possible OTP credential reporting and missing explicit
  session DELETE. All remain acceptance requirements before this checkpoint ships.
- Red tests reproduced production loopback admission and a client remaining alive
  after its owner was cancelled during initialization. The production profile now
  rejects literal loopback/localhost before trusting an origin; transport DNS
  validation and address pinning stay in place.
- Lifecycle design: acknowledge supervised wrapper startup before performing
  network initialization; a separate lifetime process owns the absolute deadline
  and directly terminates the client on cancellation. Supervisor arguments contain
  only identity/deadline references. Check-only POST mode avoids unlinked dependency
  workers created for the optional persistent GET stream.
- All 26 scoped tests pass, including four tagged local HTTP cases. Held
  initialize/tools-list POSTs close their actual sockets on owner cancellation;
  a stalled DELETE closes after bounded cleanup. Eight held initializations reject
  a ninth promptly while an independent successful check remains responsive.
- The initial failed-start log fixture did not reproduce the source-suspected
  exposure. The wrapper now keeps raw options out of supervisor MFA arguments and
  normalizes callback failures. Post-start failure tests verify both formatted
  logs and raw structured events for synthetic bearer, Basic, header and URL-query
  markers. Do not describe the original startup-log hypothesis as confirmed.
- A deterministic suspended-lifetime test verifies that a success queued before
  the deadline but processed afterwards loses to expiry. Expired admission cannot
  accept configuration or register a client. Only the lifetime controller is
  significant; it observes client DOWN before delivering the correlated result.
- Added session DELETE support to the existing FaultServer fixture after the new
  cleanup path exposed its missing DELETE handler. No production error was hidden.
- Full MCP suite: 137 tests, zero failures, seven integration/live exclusions.
  Format, warnings-as-errors compile, strict Credo and unused-dependency checks
  pass. Independent source re-review found no blocking findings. Completion
  acceptance is explicitly before the network deadline; the caller has 100 ms
  result-delivery grace and a separate 250 ms supervisor-shutdown call budget.
  These are local budgets, not a hard wall-clock return guarantee.
- Exact 24-file staged adversarial review is clean. The latest full umbrella run
  passes all applications (4,805 tests, zero failures), including MCP 137, Calls
  304, CallEngine 2,292, Gateway 870, Persistence 467 and Console 476. Evidence:
  `vxpipe-static-check-root-suite.log`. No source changes followed that run.
