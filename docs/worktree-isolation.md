# Checkout isolation

The setup command assigns a checkout identity independently of its Git branch.
`config/runtime.exs` reads the ignored `.vxpipe/worktree.json` for dev/test defaults,
so ordinary root and child Mix commands retain isolation after setup exits.
Production does not load this file. Uninitialized checkouts retain legacy defaults.

## Identity and database ownership

Metadata version 1 contains `version`, a random 32-character lowercase hexadecimal
`id`, the canonical checkout `root`, and `databases` with derived `dev` and `test`
names. The names are `vxpipe_<id>_dev` and `vxpipe_<id>_test`, below PostgreSQL's
identifier limit. A branch switch retains the identity. Copied, malformed or
unsupported metadata fails closed; copying an existing checkout's ignored files
is not a way to initialize a new checkout. Preserve suspect metadata for recovery
and initialize a fresh identity rather than editing its root field.

Python 3.10+ standard-library tooling handles Git discovery, JSON, random identity,
atomic file publication, and a checkout-local setup lock. This adds no package
installation dependency. The runtime reader uses Elixir's standard JSON support,
without requiring a running Repo or an external process. Sharing build directories
or depending on shell activation would not satisfy plain child Mix invocations.

Setup checks tools and PostgreSQL privileges without installing packages, changing
roles or printing connection URLs. Explicit development URL precedence remains
`VXPIPE_DB_URL`, then `DATABASE_URL`; tests use `VXPIPE_TEST_DATABASE_URL`, then
`VXPIPE_TEST_DATABASE`. Without a URL, initialized development and tests prefer
local PostgreSQL sockets and the current role (or `PGHOST` / `PGUSER`). An initialized
development URL also uses current-role defaults unless the URL supplies credentials;
uninitialized development retains its old connection defaults.

Before migration, both selected databases must be absent or already marked with
this checkout's ID and environment. PostgreSQL database comments hold that marker.
An advisory lock around creation and marker publication prevents competing setups
from adopting each other's database. It is separate from live branch ownership and
does not cover ordinary tests or builds. Development and test cannot select the
same target. Setup never resets, drops, copies data into or adopts an unmarked DB.

Database creation and its ownership comment cannot be one PostgreSQL transaction.
If the process is interrupted in that narrow interval, rerun refuses the unmarked
DB. Inspect that database and the checkout identity before explicitly repairing
its ownership comment; setup cannot infer ownership safely. Interrupted metadata
publication leaves no half-written identity; migration failures retain identity
and already committed database data for retry. No automatic retired-checkout or
abandoned-database deletion occurs.

## Repeatable bootstrap

Setup preserves an existing `.env` byte for byte. A new `.env` is atomically
published with mode 0600, a fresh base64 32-byte credential key, a checkout-specific
key ID and a random `SECRET_KEY_BASE`. Reruns never rotate these secrets. No invalid
sample placeholders or live provider credentials enter the generated file.

After `mix deps.get`, setup runs the existing `mix assets.setup` and
`mix assets.build` aliases, then both database migrations. Every required step must
succeed before readiness is reported. Unexpected lockfile changes stop setup and
remain available for review. Build output stays in the private, redacted
`.vxpipe/setup.log`. Interruptions stop the active build process group and retain
checkout identity, secrets and data for a later retry.

Mutable dependency/output directories must remain private. Setup rejects inherited
Mix build/dependency paths outside the checkout and symlinked mutable directories,
including frontend outputs and Lean's `.lake`. Nested npm workspace links inside
an ordinary local `node_modules` directory remain supported. Setup does not change
user overrides, install toolchains, start daemons or contact live providers.

## Temporary fixtures and listeners

Persistence operator-task files and Providers fixture-test roots use ExUnit's
checkout-local temporary directories. The Deepgram fixture generator creates an
atomically unique scratch directory under its selected root's `tmp/deepgram-fixtures`.
Its existing PCM/Opus paths and generation/reuse semantics remain unchanged. Keeping
scratch and output under the same root also avoids a cross-filesystem rename.

A synchronized two-BEAM test holds both transcodes open, finishes one invocation
and verifies the other's scratch PCM survives cleanup before letting it finish.
The test redirects system temp only to contain the old failing behavior; the fix
itself does not rely on `TMPDIR` or a wrapper around plain Mix commands.

The filesystem/listener audit found remaining writable fixtures already use
ExUnit temp directories or checkout-relative paths. Console's fixed missing-file
probes only read nonexistent names. Fixed ports in configuration assertions do not
start listeners; reviewed default-suite wire servers bind port zero. The explicit
live telephony lane retains its separately reserved listener and remains excluded.

## Verification and limits

The synthetic setup suite covers missing tools, unsupported versions, unavailable
PostgreSQL, insufficient privileges, root/linked discovery, concurrent initialization,
stable reruns/branch changes, interrupted publication, malformed/copied metadata,
URL selection, conflicting or unowned DB targets, dependency/migration failures and
unexpected lockfile changes. All external commands in that suite are fixtures.

Real local acceptance has initialized and rerun one checkout, verified separate
dev/test targets through actual root/child Mix startup, preserved marker rows across
rerun, and passed plain child database tests. This is partial milestone evidence;
fresh concurrent checkout bootstrap, port/session isolation
and complete simultaneous suites remain required in the
[worktree setup milestone](milestones/worktree-setup.md).
