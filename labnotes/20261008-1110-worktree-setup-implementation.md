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
