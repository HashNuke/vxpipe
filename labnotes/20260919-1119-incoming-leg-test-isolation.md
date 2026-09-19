# Incoming leg test isolation

The C3a umbrella run completed 1,785 tests with one failure: an incoming leg was
unavailable during admission. This test does not exercise the new URL generation.
The same failure recurred on iteration 19 of a focused repeated run (11 tests:
eight CallIngress lifecycle checks plus three public-origin checks).

Every CallIngress test previously reused the same service ID and ingress alias.
Tests now create one unique service/ingress identity in setup, pass that exact
service through each assertion, and stop its owned leg during cleanup. This avoids
looking up another test's retiring owner. No runtime dispatch/retry behavior or
failure assertions were relaxed; no sleeps or increased timeouts were added.

The focused group passed the initial run and all 50 requested reruns after isolation.
The combined C3a worktree passes 1,786 umbrella tests (zero failures, 40 excluded),
format, warnings-as-errors compilation, strict Credo and unused-dependency checks.
Review: identity generation
happens once per test; cleanup captures that instance rather than constructing a
new identity; expected admission operations pin the fixture's exact service name.
