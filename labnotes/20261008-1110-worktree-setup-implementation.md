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


## Checkpoint 3: complete bootstrap (partial)

- Four initial synthetic failures covered absent `.env`, omitted asset steps,
  accepted shared Mix paths and accepted symlinked mutable directories. The green
  implementation creates secrets once with private atomic publication, preserves
  existing files and uses the existing asset aliases in order.
- A synchronized FIFO/child-process test then reproduced SIGTERM leaving the build
  running (parent exit -15). Signal forwarding now stops/waits for the active build
  group and exits 143; rerun retains identity. No timing sleep is used in the probe.
- All 24 synthetic setup tests pass. Existing private log redaction and unexpected
  lockfile-change coverage remain green. Shared overrides are refused, not rewritten.
- Full bootstrap on the current checkout passes dependencies, asset installation,
  asset checks/build, dev migration and test migration with unchanged lockfiles.
  Existing `.env` was preserved. Fresh checkout builds and a complete rerun remain
  the acceptance gates before completing this checkpoint.


## Fresh acceptance and checkpoint 4 (in progress)

- Committed bootstrap as `3026a23a`, then created branches
  `worktree-setup-acceptance-a` and `worktree-setup-acceptance-b` in sibling checkouts.
  Both run `ERL_FLAGS='+S 2:2' CARGO_BUILD_JOBS=2 bin/setup` concurrently, keeping
  each checkout's own dependencies/builds. No user worktree was changed or pruned.
- Both assigned distinct IDs and databases, generated private `.env` files and
  fetched dependencies. Fresh frontend/native dependency builds remain running;
  full completion is not yet claimed. The existing-checkout complete rerun is also
  being checked for unchanged identity and `.env`.
- New Providers test launches two independent BEAMs with synchronized transcode
  lifetimes. Red: scratch was outside the requested checkout root. Green: random
  names plus atomic directory creation under the fixture root; one invocation's
  cleanup leaves the other's PCM readable. Tests inject PCM/transcoding, never TTS.
- Replaced system-temp integer-based test paths in operator tasks and Deepgram
  fixtures with ExUnit checkout-local directories. Existing generation/reuse tests
  retain their assertions. Six Providers fixture tests and two operator-task tests
  pass; formatting, warnings-as-errors compilation and strict Credo pass.
- Audited filesystem mutations and listener construction throughout child tests and
  support. Other writers use ExUnit/checkouts; missing-file probes are read-only;
  ordinary wire servers bind zero. Fixed ports in configuration assertions do not
  create listeners. Cross-worktree concurrent owning-suite acceptance remains open.


## Fresh concurrent acceptance completed

- Both sibling acceptance worktrees finish fresh setup and rerun successfully.
  `.env` and metadata hashes remain unchanged; lockfiles remain clean. PostgreSQL
  has four distinct marked databases with migrations. Mutable dependency and
  frontend output directories have distinct inodes and no shared symlinks.
- Both reruns start at 12:02:17 UTC. Providers: 30 tests each, no failures.
  Persistence: 214 tests each, no failures, 12 live cases excluded. Persistence
  overlaps from 12:03:27 through 12:03:53 UTC. Checkpoints 2–4 now meet their exits.

## Checkpoint 5 in progress

- Allocator regression tests first failed on missing port metadata, then passed
  concurrent distinct assignments, stable reruns, occupied ports, reassignment and
  conservative stale reservation reclamation. Live port 4600 is always excluded.
- Cookie regression first failed because login wrote the shared cookie key. Runtime
  session options now give initialized development checkouts separate cookie names;
  the same browser retains both sessions. Production uses the existing cookie key.
- Launcher regressions reproduced absent exports, ignored collisions and shell
  override precedence; fixes pass. Astro uses the assigned port with strict binding.
  Storybook delegates to a checkout-aware launcher with exact-port behavior.
- Optional setup tests cover missing tools and failed builds. Elan shorthand was
  rejected after inspecting its help: it implicitly installs missing toolchains.
  Explicit `elan run` uses the pinned installed toolchain without `--install`.
- 32 synthetic setup tests, launcher shell checks, three Astro config tests and
  27 Console runtime/login/origin tests pass. Browser and full concurrent gates
  remain open. No live-provider commands or credential files were used.
- Added a focused red/green connection test after review found runtime ignored
  setup's `PGPORT` and test `PGPASSWORD`. Runtime now uses the same explicit port,
  socket search and password. Nine configuration tests pass; formatting,
  warnings-as-errors compilation and strict Credo remain green.


## Fresh verification correction

- Both optional setup runs pass docs installation and the pinned installed Lean
  library build. Running `bin/verify-lean` in the fresh second worktree then fails:
  the oracle executable is absent. The default Lake targets only named the library,
  so prior cached executable output hid the omission. Added the existing oracle
  executable to default targets; this is a build configuration correction.
- Both Consoles start on distinct reserved ports. Concurrent same-checkout package
  rebuilding briefly invalidates watcher inputs, then recovers when package outputs
  return; browser inspection waits for builds to finish. An initial Chrome launch
  fails on this host's user-namespace restrictions; doctor passes and inspection
  uses the documented local `--no-sandbox` launch flag.


## Acceptance test synchronization

- Root default suite seed 774165 reproduced an outgoing ring-deadline test race:
  the test observed connector entry and fired the deadline before the authority
  had processed the connector's accepted handle. It terminated with no handle to
  disconnect. The test now uses the existing outgoing-admission acknowledgement
  before firing its synthetic deadline. No production lifecycle behavior changed.
- The focused original seed passes, then all 28 outgoing-call boundary tests pass.
  The final full concurrent suites will cover the corrected test under load.
- Fresh Lean build, oracle drift check and Elixir replay pass in the second
  worktree. First worktree frontend verification passes: 40 workspace tests, 219
  Console frontend tests, three Astro tests, TypeScript/build and Astro build.
- Rendered login checked at 1440×1000 and 390×844. Console A authenticates while B
  remains logged out; after authenticating B both session endpoints return 200.
  Signing out of B leaves A authenticated. A's live reload fires on a watched
  asset change and retains its session. No provider configuration was submitted.
