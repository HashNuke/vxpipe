# Transcript event fixture deadline

- The candidate recording-tap checkpoint's umbrella run failed in the existing event publisher
  test, before transcript projection: its initial policy application returned `{:error, :unavailable}`.
  The fixture passed a 100 ms acknowledgement deadline. The enforcer maps call exits to unavailable;
  no router termination was logged for this failure. The unchanged two-test file passed on its
  focused rerun. This supports a scheduling-sensitive fixture timeout, not a demonstrated transcript
  routing defect. Evidence: `vxpipe-tap-policy-verified-root-test.log` and
  `vxpipe-transcript-fixture-focused.log` in the local temporary log directory.
- Use a bounded one-second deadline for this fixture's policy setup, consistent with the earlier
  mixer/router fixture correction. These tests exercise transcript provenance and fail-closed
  delivery, not a 100 ms response-time guarantee. No runtime deadline or assertion changes.
- The same two focused tests pass after the adjustment (`vxpipe-transcript-fixture-green.log`).
  This configuration-only test correction adds no new behavior test. Full umbrella verification
  follows together with the recording-tap work, and this fixture change will be committed separately.
- Final combined-worktree verification passes all five root gates: formatting, warnings-as-errors
  compilation, strict Credo, 1,248 tests with zero failures and 15 integration exclusions, and unused
  dependencies. Every entry in `vxpipe-tap-policy-final-root-results.json` is exit zero. Commit this
  fixture deadline and its note separately from the recording implementation. `git diff --check`
  passes; no browser or provider acceptance is claimed by this fixture correction.
