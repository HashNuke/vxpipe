# Stabilize test delivery

- Preserve the earlier milestone's focused test-only repairs as their own checkpoint;
  no runtime provider, telephony, media or source-cutover behavior changes here.
- Earlier full-suite Google STS failure queried a wire after goAway had legitimately
  retired it. Replace cast-then-wire-query barriers with a fixture-owned synchronous
  delivery acknowledgement, retaining downstream provider/capability barriers and
  deliberately asynchronous late-message cases. This tests project protocol ordering,
  not GenServer implementation behavior.
- Earlier ingress cancellation/error loop reused a retiring call identity within one
  setup. Generate two tests so each receives a fresh supervised setup and normal
  cleanup; retain both outcomes and all existing usage/gate assertions.
- Historical failure and focused red/green evidence is recorded in the implementation
  log and milestone. Current unchanged worktree passed all 4,887 umbrella tests,
  zero failures, 201 exclusions, seed 825059, plus root format, warnings-as-errors
  compilation, strict Credo and unused-dependency gates. No sleep-based synchronization
  or production timeout change was added. This does not claim to repair the separate
  Gateway media timeouts observed during overlapping suite runs.
- Independent adversarial exact-index review found no actionable issues in the
  test changes, evidence or milestone projection; whitespace checks pass.
