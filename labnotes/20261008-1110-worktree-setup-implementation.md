# Worktree setup implementation

## Scope and starting state

- Implement all six worktree-setup checkpoints in coherent commits. Do not run
  live tests or read/modify the real live-provider credential file.
- Baseline `806f7c7e`; the unrelated cache-repair labnote was already untracked
  and is preserved. Existing milestone research/prerequisites were read first.
- Progress notifications use the requested `pushnotify` CLI.

## Checkpoint 1: branch ownership

- Red: new synthetic ownership suite failed with "first use did not claim ownership".
- Green: resolve the calling checkout's named branch, atomically link a completely
  written candidate into shared owner state, compare existing ownership and refuse
  other branches before credential loading or live side effects.
- Removed per-node run-duration flock. Success, failed Mix, interruption and normal
  Tailscale cleanup retain ownership. Explicit owner-only release ends the reservation.
- Temporary real Git worktrees exercise selection bypasses, competing claims,
  persistence, release/reclaim and detached HEAD. External commands and credentials
  are synthetic; every shell suite redirects shared state into its own scratch area.
- Existing tool suite now checks retained ownership and absence of obsolete locks.
  Its teardown, borrowed tools and child-status coverage remains intact.
- All four existing runner suites and the new owner suite pass. No provider contacted.
- Cooperative reservation intentionally does not serialize same-branch invocations;
  manual recovery after confirming abandoned live work is documented.


## Common validation after checkpoint 1

- Root formatting, warnings-as-errors compilation, strict Credo and unused-dependency
  checks pass. The default umbrella run (seed 658333) reports one Gateway failure:
  the five-participant handoff/reconnection test. Gateway reports 585 tests, one
  failure, eight excluded; no live test was selected. Remaining observed suites pass.
- Its isolated child invocation at line 485, seed 658333, passes one test with
  68 exclusions in 171.8 seconds. This does not explain or resolve the full-run
  failure; final concurrent/root acceptance must establish a passing complete gate.
- Initial unredirected full-run output was too verbose and truncated the failure
  detail; ExUnit's failure manifest identifies the case. Subsequent commands retain
  local logs and print bounded summaries. No runtime/state-machine fix is claimed.

## Checkpoint 2: runtime defaults (partial)

- New Console-owned boundary tests first fail four of five cases: metadata is
  ignored, test database settings are compile-time, and malformed metadata is accepted.
- Move test connection resolution to runtime while retaining compile-time sandbox
  pool settings. A dependency-free config reader validates version, random hex ID,
  checkout root and derived database names. Only dev/test load it; production ignores it.
- Initialized development uses socket/current-role defaults, clearing legacy postgres
  credentials. Explicit dev URLs retain precedence; test URLs/names remain separate.
  No-metadata development/test keep their legacy database defaults.
- Preserve persistence enablement and all credential/publication/operator wiring when
  development uses a socket instead of a URL. Existing default-configuration tests
  use copied config fixtures so future checkout initialization cannot change their
  no-metadata assumptions.
- The 11 focused database/runtime tests and broader 26-test configuration group pass;
  formatting, compilation and strict Credo pass. Actual root/child Mix startup with generated metadata and isolated
  databases remains a setup acceptance requirement, not proven by Config.Reader tests.


## Checkpoint 2: setup orchestration (partial)

- Added Python standard-library orchestration with focused responsibilities for
  preflight, metadata, DB selection/ownership and local build steps. Python 3.10+
  is documented; no third-party Python package or implicit system installation.
- Red/green progression: five initial preflight failures (missing setup), four
  missing initialization failures, three missing migration/URL/conflict failures,
  and one undetected lockfile mutation. The expanded synthetic suite passes 17 tests.
- PostgreSQL markers and creation locks reject another checkout's or unmarked DB
  before migration. Development/test target conflicts fail; creation never drops
  data. A narrow interrupted create/comment gap fails closed and requires explicit
  ownership recovery rather than silently adopting a database.
- New initialized-URL test exposed legacy `postgres` credential inheritance only
  after merging the development config (an initial runtime-only probe was too weak).
  Fixed current-role defaults while preserving full explicit URL credentials.
- First real `bin/setup` and a rerun pass on the existing checkout: dependencies,
  isolated dev DB migration and isolated test DB migration. Lockfiles unchanged.
  Inserted project-owned probe rows in both DBs, verified them after rerun, then
  removed only the probe tables. Identity and application data remain intact.
- Actual `mix run --no-start` from umbrella and Persistence child, in dev and test,
  selects metadata database names. Plain child operator-task tests pass 2 tests;
  root database/runtime configuration selection passes 12 tests, seed 908011.
- Two-worktree proof and complete fresh bootstrap remain pending; checkpoint 2
  stays incomplete. No real live credentials, provider commands or daemon changes.
