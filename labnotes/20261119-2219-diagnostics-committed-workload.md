# Committed diagnostic workload

## Decision and scope

The existing configured smoke shares one SQL Sandbox transaction. It proves
functional record behavior but omits real commit costs and serializes database
users through that connection. Using it unchanged for the full paired workload
would misrepresent database overhead. Added `--committed-writes` to the existing
smoke runner rather than changing ordinary test isolation.

Each committed case creates its own UUID-named database, migrates before workload
preparation and starts Repo with an ordinary ten-connection pool (the deployment
default). It does not change the application's configured database. A separate
Postgrex connection verifies the call and the expected two/zero diagnostic rows
after room drain. Reports identify committed versus sandbox persistence and the
pool size. The watchdog refuses committed acceptance without evidence from all
four modes. The larger topology/duration/latency matrix remains unimplemented.

Normal ExUnit cleanup drops only a database this invocation successfully created.
The helper refuses an already-running Repo. A forced VM termination can bypass
ExUnit cleanup, so reservation names are reported before creation and a dropped
acknowledgement follows successful deletion. The runner accepts only names scoped
to its run ID, retains unresolved names in `retained_databases`, and cannot pass
while any reservation remains unresolved. This four-case runner reserves at most
four scratch databases. An unresolved reservation may not have been created;
inspect exact names after an invalid run before retrying. No wildcard deletion or
automatic shared-database cleanup is performed. This is explicit bounded retained
evidence on abnormal exit, not a guarantee of deletion after VM termination.

## Red-green evidence and review

- The new independent reader failed all four old sandbox cases: expected one
  committed call, observed zero (`/tmp/vxpipe-committed-workload-red.log`). Those
  runs establish the missing transaction boundary, not performance evidence.
- The disposable database helper began with an undefined-function red test.
  Its focused integration checks prove committed visibility from a distinct
  PostgreSQL backend, refusal to replace an existing Repo and unchanged
  application configuration.
- Astra found a supported database-URL configuration could be re-merged by Ecto,
  overriding the generated database and pool size. A permanent test invokes the
  real option builder and Ecto's configuration resolution without connecting to
  that URL. Root reproduced the wrong configured target in
  `/tmp/vxpipe-diagnostics-database-url-root-red.log`. Explicit `url: nil` now
  overrides the inherited URL while retaining parsed connection settings.
- Focused helper tests pass 2/2. Python tests pass 28/28, including committed-mode
  evidence and retained-database invalidation controls. The latter started red
  with the missing ownership tracking and now rejects foreign names and missing
  drop acknowledgements.

## Workload evidence

The first bounded committed run passed all independent row checks, but two cases
exceeded the unchanged 2 ms generator p95 limit while root was concurrently
running static checks. It remains invalid and retained at
`/tmp/vxpipe-committed-workload-first/`. Static checks are now serialized before
measured runs; no budget was relaxed.

Without that competing root job, `/tmp/vxpipe-committed-workload-serial/` passed
4/4 with 323 samples, peak sampled RSS 885,496 KiB and minimum available memory
2,564,684 KiB. Generator p95 values were 0.164, 0.439, 0.223 and 0.560 ms in
VAD/collection order off/off, off/on, on/off, on/on. This predates the added
reservation protocol and final URL fix; final evidence is recorded below.

No live provider or Telnyx calls, production changes or full-suite run occurred.

Final reviewed-source run at `/tmp/vxpipe-committed-workload-final/` passed all
four cases in 30.2 seconds, with all four database reservations acknowledged as
dropped. Exit was zero; abort was null; cleanup errors and retained databases
were empty. All mode reports identify committed persistence and pool size ten.
Root format, warnings-as-errors compile, strict Credo and unused-dependency checks
passed before this run, with no concurrent root test/static workload during it.

Final Astra review is clean. Independent review verified all eight source/model
hashes, four exact reservation/drop pairs, all four committed/pool-ten reports,
one VM identity and native masks restricted to CPUs 0–1. The final run retained
329 samples, peak RSS 880,492 KiB and minimum available memory 2,553,696 KiB.
Raw-array p95 recomputation matched 0.560, 1.125, 0.439 and 1.321 ms. Independent
Python 28/28 and the real option-builder URL regression passed. Review also
corrected the plan to distinguish omitted commit-time costs from WAL generation
that can still occur inside a subsequently rolled-back transaction.

After the native run, a mechanical AGENTS hygiene correction replaced new keyword
list bracket access with `Keyword.fetch!` in the pool-size report and helper tests.
The helper guarantees those keys. Focused helper tests remained 2/2; the native
artifact hashes therefore identify the immediately preceding equivalent report
expression, not this final mechanical spelling.
