# Diagnostics registry cleanup

- The room-egress preparation root run passed every other suite but failed the diagnostics
  read-only test: RoomRegistry count fell from 1,027 to 1,007 while mounting the page. The assertion
  required equality, so removal of unrelated bindings failed a test whose contract is that the
  page creates no rooms, participants or call-path observations.
- Capture the actual registry key/PID pairs and room-supervisor child PIDs. Assert that the sets
  after mounting are subsets of the original sets, preserving rejection of any newly added binding
  or room while allowing existing resources to disappear. A smaller count alone would hide a new
  binding if another disappeared, so replacing equality with a numeric comparison was rejected.
- No application behavior, production timer, UI code or telemetry assertion changes. The existing
  whole-root failure is the red evidence for the fixture correction. Focused diagnostics and final
  root verification now pass: eight focused diagnostics tests; formatting, warnings-as-errors
  compilation, strict Credo, 1,223 umbrella tests with zero failures and 15 integration exclusions,
  and unused dependencies. Retained logs are `vxpipe-diagnostics-registry-focused.log` and those
  with prefix `vxpipe-egress-policy-verified-root-`. The unused-dependency check was additionally
  confirmed with exit zero after recovery of the completed job's logs.
- Commit this fixture separately from prepared room output, with a cross-reference in the
  [main transfer labnote](20260914-0032-transfer-readiness-implementation.md). This test correction
  does not establish transfer readiness or rendered UI acceptance.
