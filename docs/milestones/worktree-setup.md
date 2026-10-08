# Worktree setup and concurrent development

Status: in progress; **1 of 6 checkpoints complete**. Branch-lifetime live-test
ownership is implemented and verified with synthetic commands (2026-10-08). Setup
and concurrent-worktree acceptance remain pending. Research and local specification
review completed 2026-10-08.

Prerequisites: the existing database/configuration contracts from
[Tenant-scoped provider credentials and platform configuration](tenant-provider-credentials-and-platform-configuration.md)
and the runner from [Outgoing calls and two-call live telephony](outgoing-calls-and-live-telephony.md)
with [Outgoing call review fixes](outgoing-call-review-fixes.md).
Sources: [development guide](../development.md), [live telephony harness](../live-telephony-harness.md),
[platform settings](../../env.sample), and
[research labnotes](../../labnotes/20261008-0959-worktree-setup-research.md).
This developer-tooling slice does not depend on unfinished operator onboarding,
the call spec editor, delivery or retention. The index owns its implementation order.

## Runnable outcome and scope

The requested outcome is independent development, builds and ordinary tests in
multiple worktrees on this machine, with **one branch/worktree owning live testing at a time**. Setup alone cannot establish that outcome: the live runner and runtime
configuration also need small changes.

## Existing behavior and isolation gaps

| Resource | Current behavior | Required treatment |
| --- | --- | --- |
| Git checkout | Linked worktrees share repository metadata; each has its own working directory | Support both a `.git` directory and a `.git` file; discover paths with Git |
| Elixir dependencies/builds | Child Mix projects use `../../deps` and `../../_build` | Keep these directories private to each checkout |
| Frontend dependencies/builds | Root workspace, Console assets and Astro have separate npm lockfiles | Install independently in each checkout; keep package `dist` and generated Console assets local |
| Development database | Defaults to `vxpipe_dev` | Give every initialized checkout its own database |
| Test database | Defaults to `vxpipe_test`; root `mix test` creates/migrates it | Give every checkout its own test database, including focused child tests |
| Test temporary files | Some use system temp plus a BEAM-local integer | Replace collision-prone filesystem naming with checkout-local ExUnit temporary directories or atomic random directories |
| Development listeners | Console 4000, Astro 4321, Storybook 6006 | Assign distinct, persistent ports for simultaneous servers |
| Live telephony listener | Defaults to 4600 | Retain one shared live-test port, reserved from development allocation |
| Live tools | Per-machine Tailscale node and carrier resources; shared user-state directory | Reuse these resources; record the owning branch in one shared file |
| Credentials | Development `.env`; separate live-runner credential file | Preserve existing configuration; never copy live credentials into a checkout |
| Lean | Shared installed toolchain, local `verification/.lake` | Reuse installed toolchain; build in each checkout |

The database collision is substantive. The Persistence operator-login durability
tests deliberately leave SQL sandbox transactions, persist rows, restart the Repo,
and delete all login challenges during cleanup. Two independent suites must not
share that database. Separate databases also isolate branch-specific migrations.
See [test configuration](../../config/test.exs), [root aliases](../../mix.exs), and
[durability tests](../../apps/vxpipe_persistence/test/vxpipe/persistence/operator_login_challenge_durability_test.exs).

Temporary-file risks include
[operator task tests](../../apps/vxpipe_persistence/test/vxpipe/persistence/operator_tasks_test.exs)
and [Deepgram fixture tests](../../apps/vxpipe_providers/test/vxpipe/providers/deepgram/live_deepgram_fixture_test.exs).
Their names contain `System.unique_integer/1`, whose uniqueness is scoped to a
runtime, not the host. Independent BEAM processes can select the same path.
Most reviewed local wire servers already bind port zero. Literal port numbers in
configuration assertions are not necessarily actual listeners.

## What is available on this machine

Read-only checks found Ubuntu 24.04, Elixir 1.19.5 / OTP 28, Node 26.8.1,
npm 11.19.0, Rust 1.97.1 and PostgreSQL 18.4. The local PostgreSQL socket accepts
connections; the current database role can log in and create databases without
being a superuser. `max_connections` is 100; nine connections were visible during
the check. This establishes local test-database prerequisites, not authentication
for the development configuration's separate default `postgres` account.

Git, C/C++ compilers, Make, `pkg-config`, OpenSSL development metadata, `flock`,
`jq`, `curl`, Tailscale, `tailscaled`, FFmpeg, elan/Lake and `agent-browser` are
available. CMake is absent from PATH; the current project setup documentation does
not require it. Gateway uses Bundlex/Unifex, precompiled Opus with a `pkg-config`
fallback, and Rust dependencies. Do not make installing CMake an unconditional
requirement without a reproducible native-build need.

The documented development baseline is Elixir 1.19 / OTP 28 and Node 24. The root
npm manifest requires Node >=22.22.0; Astro's manifest requires >=22.12.0.
`verification/lean-toolchain` pins Lean 4.34.1. Runtime version pinning for the
other tools should be a separate deliberate decision, rather than silently
replacing the working machine toolchain.

The machine has four logical CPUs and approximately 7.6 GiB RAM. About 22 GiB of
disk space was available. Existing `_build`, `deps`, the three npm installations
and `.lake` occupy approximately 3.1 GiB in total. That is a planning observation,
not a guaranteed fresh-worktree footprint. Independent worktrees are feasible;
concurrent native builds and large test suites still compete for CPU and memory.
The test pool currently scales to twice the online scheduler count per Repo.

## Setup contract

`bin/setup` should initialize the checkout containing the script, from any
working directory. Creating a worktree remains an explicit Git operation:

```shell
git worktree add -b feature-name ../vxpipe-feature
cd ../vxpipe-feature
bin/setup
```

The initial `bin/setup` now prepares dependencies and isolated databases; complete
asset/configuration bootstrap and concurrent acceptance remain pending. A new
worktree receives committed files, so its branch must contain the setup
implementation. Uncommitted setup changes in another checkout are not inherited.

Setup must preserve existing configuration and database contents, keep credentials
out of output, install dependencies from the checked-in lockfiles and be safe to
rerun after a partial failure. The tasks below specify the implementation sequence.
Any setup concurrency guard is local to the checkout, separate from live-test ownership. Brief port
allocation serialization must not serialize dependency installation, builds or
ordinary test runs across checkouts. Metadata must be declarative and non-secret.

The user-required contracts are independent non-live work and branch-level live-test ownership.
The metadata format, optional flags and allocation strategy below are proposed
implementation choices reviewed locally; they are not claims of separate user
approval. Automatic system package installation, provider provisioning, purchases,
data copying and destructive cleanup are outside this milestone.

## Checkpoint 1 — Reserve live testing for one branch

Prerequisites: the existing live runner; independent of the new setup command.
Owning files: `bin/livetests`, its cleanup library and `test/shell/livetests*_test.sh`.

- [x] Red-test a shared owner file containing a Git branch name: absent file,
  repeated use by the owner, rejection of a different branch and release when the
  branch finishes its work. Cover AI-only, telephony, missing-carrier,
  explicit-public-URL and default all-provider selections with synthetic commands.
- [x] Resolve the current branch through Git. On first live use, create the shared
  file without overwriting an existing claim; write only the branch name. Permit
  the matching branch and report the recorded owner to other branches before
  credentials, provider calls or Mix start. Detached HEAD needs a named branch.
- [x] Keep the claim after success, failure, interruption and between test runs.
  Remove the old run-duration `flock` mechanism rather than building another
  process-lock layer. Preserve test exit status and existing Tailscale teardown.
- [x] Add an explicit owner-checked `bin/livetests release` command to remove the
  file once branch work and its live activity are finished. Document release before
  switching/deleting the branch; interrupted work retains ownership until release.
- [x] Make mutating live-tool commands respect the recorded owner; the owner can
  use hangup for recovery during its work. Keep read-only status available and
  ordinary setup/tests independent. Do not remove the claim in per-run cleanup.
- [x] Test simultaneous first claims without overwrite and isolate synthetic owner
  files from real machine state. Run all four shell suites and update the live
  harness guide with the branch-lifetime ownership workflow.

Exit: one branch retains live-test ownership across multiple runs until explicitly
released. A different worktree's ordinary tests remain runnable throughout. This
is a cooperative branch reservation, not process supervision or a per-run mutex.

Evidence (2026-10-08): `test/shell/livetests_owner_test.sh` first failed because
initial use did not claim ownership, then passed with real temporary Git worktrees,
fake Mix/providers, five competing initial claims, detached HEAD refusal, persistent
ownership after exit 7 and SIGTERM, owner-only release and release/reclaim. All four
existing runner shell suites pass; teardown still stops only tools started by a run.
No real live tests or credential files were used. See
[implementation labnotes](../../labnotes/20261008-1110-worktree-setup-implementation.md).

## Checkpoint 2 — Initialize a checkout with isolated databases

Prerequisites: existing persistence configuration; no dependency on checkpoint 1.
Owning files: new `bin/setup`, a focused metadata reader, runtime/test configuration,
`.gitignore`, shell setup tests and configuration boundary tests.

- [ ] Red-test root/linked worktree discovery from another directory, absent tools,
  unusable PostgreSQL, insufficient DB privileges and actionable non-secret errors.
- [ ] Implement setup preflight for the documented toolchain and the selected DB
  connection. Do not install system packages or change roles/toolchains implicitly.
- [ ] Red-test first initialization, rerun, interrupted write, concurrent setup of
  the same checkout, duplicate copied metadata and malformed/unsupported metadata.
- [ ] Persist an ignored versioned `.vxpipe/worktree.json` with an atomically written
  random lowercase hexadecimal checkout ID and bounded dev/test database names.
  Use a local setup lock; keep IDs stable across reruns and branch switches.
- [ ] Red-test effective dev/test database selection in actual root and child Mix
  invocations, existing environment overrides, no-metadata legacy behavior and
  production ignoring checkout metadata. Implement the runtime defaults described
  below, preserving sandbox settings and test/dev separation.
- [ ] Support this machine's socket/current-role dev connection when no explicit
  URL is supplied. Preserve explicit remote/container URL precedence. Reject
  conflicting shared targets before a setup migration; never log credential URLs.
- [ ] Fetch Mix dependencies and create/migrate only the selected dev and test DBs.
  Red-test partial migration/setup failure and data-preserving reruns. Never reset,
  drop or silently adopt another checkout's DB. Document focused child-test use.

Partial progress (2026-10-08): runtime dev/test defaults and the versioned metadata
reader are implemented. Five new boundary tests (four initially red), plus the six
existing database configuration tests, pass. Socket/current-role development and
explicit URL precedence are covered; production ignores metadata. The initial setup command now passes 17 synthetic checks and real local initialization/
rerun. Actual root/child dev/test startup selects the expected databases, plain child
Persistence tests pass, and marker rows survive rerun in both databases. Two-checkout
database acceptance remains unverified, so checkpoint 2 stays incomplete. See the
[isolation decision](../worktree-isolation.md).

Exit: on the prepared machine, two initialized worktrees can run database-backed
focused tests using plain `mix test`, without shell activation or shared DB state.

## Checkpoint 3 — Complete repeatable local bootstrap

Prerequisite: checkpoint 2. Owning files: `bin/setup`, existing asset aliases,
setup shell tests and the development guide.

- [ ] Red-test preservation of an existing `.env`, first creation, private file
  permissions, no secret output and reruns without key rotation. Generate a fresh
  32-byte credential encryption key/key ID and suitable local `SECRET_KEY_BASE`
  only for a new `.env`; do not copy invalid placeholders from `env.sample`.
- [ ] Run `mix assets.setup` then `mix assets.build` after `mix deps.get`. Reuse the
  existing root npm/package build and Console installation sequence. Detect and
  report unexpected lockfile changes; keep build and installation output local.
- [ ] Red-test failure propagation and successful rerun after dependency, asset and
  database failures. Never report full readiness after an incomplete required step.
- [ ] Detect inherited shared `MIX_BUILD_PATH` / `MIX_DEPS_PATH` and shared/symlinked
  mutable dependency/output directories before claiming isolation. Preserve user
  configuration and explain how to resolve conflicting settings.
- [ ] Print completed steps and exact next commands without credentials. Explain
  that ordinary local startup needs no live credentials, while actual voice samples
  still require separate tenant/provider provisioning.
- [ ] Verify fresh bootstrap on the existing machine and a data-preserving rerun;
  update development instructions without replacing operator onboarding docs.

Exit: one command prepares dependencies, assets, configuration and databases for
local development; a repeat invocation retains all existing data and secrets.

## Checkpoint 4 — Remove cross-process temporary-file collisions

Prerequisite: checkpoint 2 for database-backed fixtures. Owning boundaries:
Persistence operator-task tests and Providers Deepgram fixture tests/support.

- [ ] Red-test the project-owned temporary-file isolation boundary using two
  independent BEAM processes and synchronized overlapping fixture lifetimes.
  Demonstrate that one invocation's cleanup cannot remove the other's files.
- [ ] Replace system-temp names based only on `System.unique_integer/1` with
  checkout-local ExUnit temporary directories or atomically unique directories at
  each owning boundary. Preserve live fixture generation/reuse behavior.
- [ ] Audit remaining filesystem and local-listener fixtures for shared mutable
  paths and fixed bound ports; distinguish assertions from actual listeners.
- [ ] Run the focused owning suites concurrently from two worktrees and record
  evidence. Do not depend on a wrapper exporting `TMPDIR` for plain Mix safety.

Exit: ordinary fixture work and cleanup remain independent across BEAM instances
and checkouts, including focused child test commands.

## Checkpoint 5 — Run development tools side by side

Prerequisites: checkpoints 2 and 3. Owning files: setup metadata/port allocation,
`bin/dev`, `bin/site-dev`, Storybook launch/configuration and optional tooling setup.

- [ ] Red-test distinct port assignment under concurrent setup, stable reruns,
  occupied listeners and explicit reassignment. Use a short shared allocator lock
  and persistent reservations; reserve live-test port 4600. Handle abandoned
  reservations without reclaiming another running checkout's ports.
- [ ] Store Console/Astro/Storybook ports and integrate launchers with explicit
  override precedence and clear bind-collision errors. Keep public origins and
  live-reload URLs consistent with the actual listener.
- [ ] Verify cookie/session behavior for two Consoles on the same hostname; use
  checkout-specific development session cookie names if needed, keeping production
  behavior intact. Add a focused regression for the project-owned isolation.
- [ ] Add `--with-docs` (Astro `npm ci`) and `--with-lean` (pinned Lean build) options
  with missing-tool/failure tests. Tailscale is optional for local setup; never
  start a daemon, Funnel, carrier operation or live test as a setup side effect.
- [ ] Inspect both Consoles and optional Astro/Storybook servers using
  `agent-browser` with headless Chrome. Cover relevant desktop/mobile layouts,
  authentication and live reload. Record any blocked optional HTTPS inspection.
- [ ] Document assigned URLs, overrides, optional tooling, existing-checkout
  adoption and the separate explicit cleanup policy for retired worktrees.

Exit: two prepared checkouts can serve development interfaces simultaneously at
stable distinct URLs, with independent browser sessions and optional tools.

## Checkpoint 6 — Prove the complete worktree workflow

Prerequisites: checkpoints 1–5.

- [ ] Create two independent worktrees containing the implementation; run setup
  concurrently, rerun it, and inspect identities, DB targets and mutable outputs.
  Record commands and results without secrets or machine-specific absolute paths.
- [ ] Run two full default umbrella suites concurrently. Run focused child suites,
  relevant npm tests/builds and optional Lean verification in separate worktrees.
  Record actual overlap and independent state, not just two sequential passes.
- [ ] Claim live testing from one branch; prove another branch is refused for every
  supported selection while default tests and local development remain runnable.
  Verify ownership persists between runs and after exit/failure, then release it
  explicitly and prove the other branch can claim it.
- [ ] Complete rendered multi-server checks and all four runner shell suites.
  Real live-provider execution is not required to prove exclusion; any separately
  requested smoke run must use the owning branch and existing resources.
- [ ] Pass root formatting, warnings-as-errors compilation, strict Credo, default
  tests and unused-dependency checks. Fix project-owned failures and document
  resource limits or unresolved barriers rather than checking off partial work.
- [ ] Synchronize development/live-runner instructions, checkpoint evidence,
  labnotes and this milestone's index entry. Mark the milestone complete only
  after every required exit and acceptance gate passes.

Exit: the documented one-command setup and concurrent non-live workflow have
end-to-end evidence, with the shared branch-name file controlling live-test ownership.

## Configuration must work after setup exits

A subprocess cannot export settings into its parent's shell. Currently only
`bin/dev` loads `.env`; direct `mix` and `bin/site-dev` do not. Writing additional
variables into `.env` therefore does not make plain `mix test` safe.

Recommended implementation: consume the generated non-secret worktree metadata
as development/test defaults from `config/runtime.exs`, resolving its location
relative to the config file, so root and child Mix commands agree. Move the
existing test database environment resolution from `config/test.exs` into the
runtime layer while preserving the sandbox pool configuration and explicit
`VXPIPE_TEST_DATABASE_URL` / `VXPIPE_TEST_DATABASE` overrides. Preserve existing
development URL precedence (`VXPIPE_DB_URL`, then `DATABASE_URL`), using the
worktree default only when neither is supplied. Production must not consume
worktree metadata. Test the actual root/child Mix startup paths before relying on
this design.

On this machine, preserve the working peer-authenticated socket connection for
tests. Development currently supplies `postgres` credentials and a localhost URL;
support a generated local socket/current-role default when no explicit dev URL
is given. Do not assume the default TCP credentials work merely because `psql`
over the socket succeeds. Explicit remote/container URLs remain supported.

Make `bin/dev`, `bin/site-dev` and the Storybook launcher use the assigned ports,
with documented explicit overrides. Storybook currently hardcodes `-p 6006`;
Astro has no worktree port setting. Keep frontend public-origin configuration
consistent with Console's selected port. Browser cookies are not isolated by
port, so simultaneous authenticated Console sessions also need distinct session
cookie names in development or separate browser profiles. Verify this during
implementation rather than equating port isolation with browser-session isolation.

For temporary files, fix the identified test owners to use ExUnit's checkout-local
temporary directory support. Exporting a checkout-local `TMPDIR` from a wrapper is
useful for tools, but cannot be the sole fix when plain root/child `mix test` is a
supported workflow. Keep inherited `MIX_BUILD_PATH` / `MIX_DEPS_PATH` and copied
metadata from defeating isolation: detect conflicting overrides and duplicate IDs
before declaring a checkout ready.

## Live-test ownership lasts for the branch's work

User clarification, 2026-10-08: use a simple shared file containing the Git branch
name and remove it after that branch/worktree finishes its work. This supersedes
the research's proposed process-lock design and per-run release behavior.

Use one file outside the worktrees, for example the calling user's shared
`vxpipe/livetests/owner` state file. Its contents are just the branch name plus a
newline. First live use creates it without overwriting an existing file. A matching
branch may continue; another branch sees the owner name and stops. Use a shared
location independent of the checkout, selected provider, port and Tailscale node.
Only synthetic tests should redirect it to an isolated temporary fixture.

The reservation covers the branch's entire work session, including gaps between
live runs. Test exit, signals and Tailscale cleanup leave it in place. Once the
owner finishes its work and stops any live activity, `bin/livetests release`
checks the branch and removes the file. Manual removal is the recovery procedure
for an abandoned/deleted branch after checking that its live work has ended.
There are no PID records, heartbeat, timeout, auto-expiration or process-lifetime
locks. Do not make `bin/setup` claim or release live ownership.

All `run` selections and mutating live-tool commands obey the same owner file.
Read-only status remains available to everyone. The owning branch may run recovery
hangup commands during its session. Keep the existing rule that a run stops only
Tailscale tools it started; that tool cleanup does not release branch ownership.
Do not provision carrier resources in setup or give each worktree a new node.

The existing runner currently uses `flock` for some telephony paths and bypasses
it for AI-only selections, missing carrier credentials and explicit public URLs.
Replace that mechanism with the branch-file policy rather than extending it.
The historical lock probe below records current behavior, not a requirement to
retain or expand `flock`.

Not every AI-provider test technically needs Tailscale; every live selection still
belongs to the owning branch under the user's workflow. `bin/dev --tailscale`
uses the host certificate/listener, separate from the live harness's dedicated
userspace node/Funnel. Ordinary development and default tests remain unrestricted.

This is cooperative coordination among this user's named Git worktrees. Different
branches are distinguishable; separate clones using the same branch name are not,
and this file does not serialize two invocations within the owning worktree.
Direct `mix test --only live_*` remains unsupported under repository instructions.
Do not expand this milestone into multi-user arbitration, direct-Mix enforcement
or process supervision. Release before switching or deleting the owning branch.

## Alternatives and consequences

- Sharing `deps`, `_build`, `node_modules` or generated assets saves disk but allows
  branches to overwrite each other's compiled/native artifacts and package links.
  Keep them private; reuse package download caches instead.
- A shared database with transactional sandboxing does not cover durability tests
  or divergent migrations. Separate databases are the isolation boundary.
- A separate Tailscale identity and carrier allocation per worktree creates extra
  resources and does not match the requested branch-ownership policy.
- A generated shell activation file is simpler than runtime defaults but depends
  on every terminal, agent and direct child Mix invocation remembering to load it.
  Automatic non-secret defaults better satisfy the requested ordinary workflow.
- Branch-name IDs change when switching branches and can collide after sanitizing.
  Persisted checkout IDs need explicit handling when metadata is copied, but keep
  databases and URLs stable. Worktree deletion/database cleanup should be a future
  explicit operation, not an automatic setup side effect.

## Research evidence

- Read the launchers, runtime/test configuration, Mix/npm manifests, native build
  configuration, database durability tests, live runner and existing shell tests.
- All four existing synthetic shell suites pass: `livetests_test.sh`,
  `livetests_tools_test.sh`, `livetests_telephony_test.sh` and
  `livetests_hangup_test.sh`. Their APIs, credentials and daemons are fixtures.
- An isolated probe held the current lock with `flock`, then ran the unmodified
  runner against an empty synthetic credential file and fake Mix executable.
  Both `--only live_openai` and `--only live_telephony` still started fake Mix and
  exited zero. This confirms the lock bypass; no live service was contacted.
- No actual live credential file was read or modified. No real live tests, carrier
  operations, Tailscale changes, new databases or new worktrees were performed.
  Full concurrent umbrella acceptance remains unverified.

## Specification review

Local design/dependency review, 2026-10-08; separate from implementation progress.
No independent-agent review or implemented acceptance is claimed.

- Confirmed the prerequisites are already implemented database/configuration and
  live-runner capabilities; unfinished onboarding/editor/delivery work is not a
  technical prerequisite. The index places this enabling slice after the existing
  live-runner fixes and before delivery.
- Split the work into six usable checkpoints, each with owning files, red tests,
  implementation tasks and an observable exit. Checkpoint 1 can ship independently;
  the remaining setup integration culminates in concurrent acceptance.
- Closed missing planning contracts for no-metadata compatibility, production
  exclusion, copied IDs, shared build overrides, same-checkout setup concurrency,
  explicit DB-target conflicts and port collisions. Defaults must be effective in
  ordinary root/child commands after setup exits.
- Applied the user's branch-file clarification: ownership persists until branch
  work finishes, success/failure never releases it, and owner recovery commands
  remain available. Removed process-lock, descriptor-lifetime and per-run release
  tasks. Same-branch invocations and cross-user enforcement are outside this policy.
- Retained local browser-session verification and fresh native-build verification;
  current tool availability alone proves neither. Research evidence below the
  contracts does not satisfy any implementation checkbox.

## References

Repository sources: [development guide](../development.md),
[live provider tests](../live-provider-tests.md),
[live telephony harness](../live-telephony-harness.md),
[formal verification](../formal-verification.md), [platform settings](../../env.sample).

External contracts checked during research:
[Git worktree semantics](https://git-scm.com/docs/git-worktree),
[Existing Linux flock behavior (historical research)](https://man7.org/linux/man-pages/man1/flock.1.html),
[Elixir unique integers](https://elixir.hexdocs.pm/System.html#unique_integer/1),
[PostgreSQL identifier limits](https://www.postgresql.org/docs/current/limits.html),
[Tailscale Funnel command](https://tailscale.com/docs/reference/tailscale-cli/funnel).
