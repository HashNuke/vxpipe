# Worktree setup research

## Scope and decisions

- Collect requirements for a future `bin/setup`; do not implement the script.
- Existing call-spec milestone/review edits and the unrelated cache-repair labnote
  were present at the start and are outside this task. The user subsequently
  requested a commit of this task's documentation changes.
- Wrote `docs/milestones/worktree-setup.md` with observed behavior, proposed setup/configuration
  contracts, alternatives, implementation acceptance gates and source references.
- Recommend independent checkout databases, build outputs, temporary files and
  development ports, plus one shared live-run exclusion boundary.
- Recommend automatically loaded non-secret worktree defaults, because `bin/dev`
  alone loads `.env` and a setup subprocess cannot configure its parent's shell.

## Findings and barriers

- Existing telephony locking is shared across default same-user worktrees, but
  AI-only runs, runs without carrier credentials and explicit public URLs bypass it.
  Provisioning and hangup commands also require an explicit concurrency policy.
- Persistence durability tests use committed data and table-wide cleanup; the
  shared `vxpipe_test` default is unsafe for concurrent independent suites.
- Some filesystem test fixtures use VM-local integer suffixes under shared system
  temp. They need checkout-local or atomically unique paths.
- Machine toolchain and PostgreSQL socket are available. Current DB role can create
  databases. Development's separate default TCP authentication was not tested.
- Existing dependency/build trees total approximately 3.1 GiB; about 22 GiB free
  disk, four CPUs and 7.6 GiB RAM bound practical concurrent build capacity.
- CMake is absent, but existing project prerequisites do not establish a need for
  it. Native fallbacks remain a fresh-build verification item.
- No setup/runtime implementation or simultaneous worktree suites were attempted.

## Evidence

- Read project launchers, runtime/test config, manifests, test fixtures and guides.
  Consulted official Git, PostgreSQL, Elixir, Tailscale and Linux flock documentation.
- All four existing `test/shell/livetests*_test.sh` suites passed with synthetic
  credentials, fake APIs and fake daemons. No real provisioning or calls occurred.
- Reproduced lock bypass with a temporary held lock, an empty synthetic credential
  file and a fake Mix binary: `live_openai` and `live_telephony` both started Mix
  despite the lock. Temporary probe files were removed automatically.
- Never read or modified the real live-provider credential file. No `.env` secrets
  were inspected. No real live service, database or Tailscale configuration changed.
- Documentation links and whitespace checked after writing. Implementation gates
  remain unchecked in the research document; no milestone progress was changed.

## Milestone conversion

- User requested that the research become an implementation milestone with tasks.
  Moved it to `docs/milestones/worktree-setup.md`; the standalone document is removed.
- Added six unchecked checkpoints: live-run serialization, checkout/database
  initialization, repeatable bootstrap, temporary-file isolation, concurrent dev
  tools and full workflow acceptance. Each names prerequisites, ownership, focused
  red tests and an observable exit condition.
- Added a separate local specification review covering dependency order and gaps;
  no independent review or implementation completion is claimed.
- Inserted the milestone after outgoing-call review fixes and before delivery in
  the index, updating its totals to 43 specifications / 31 complete / 12 incomplete.
  Existing user changes to the call-spec editor milestone remain untouched.
- Updated moved relative links and verified link targets, checklist counts,
  specification-review placement and whitespace. No runtime changes or new test
  execution were needed for this documentation restructuring.

## User correction: branch ownership file

- The user rejected the proposed live process lock in favor of a shared file
  containing the owning Git branch, removed after the branch/worktree finishes work.
- Revised checkpoint 1, final acceptance, detailed contracts, specification review
  and index summary accordingly. The claim persists across runs, failures and
  interrupts; release is explicit. The owner's recovery commands remain usable.
- Historical `flock` inspection/probe evidence is retained as a current-code
  observation, not a requested implementation. No process lock, PID/heartbeat or
  expiry mechanism is planned; the file coordinates named worktrees cooperatively.
