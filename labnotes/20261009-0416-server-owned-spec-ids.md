# Server-owned spec IDs

## Contract and scope

The user clarified that public_id must be internally assigned (UUID), never
chosen or edited through API/UI input. Keep the database's numeric private key
and public identifier separate. No numeric-public-ID migration. Preserve earlier
uncommitted integer precision changes, review tests, and the unrelated cache
repair labnote. This checkout was already prepared with bin/setup during the
milestone. The user subsequently requested an identity-only commit.

POST already accepts only source and generates a UUID; Console update already
checks existence and the editor has no identity input. The gap was Gateway PUT:
its path ID flowed into the trusted upsert workflow, permitting creation with
any supplied string. CLI --call-spec-id had the same behavior.

The shared CallSpecAuthoring boundary now checks revision 1 exists in the same
tenant whenever an ID is supplied, after authenticating/authorizing the caller
and before source processing or writing. No supplied ID means internal UUID
allocation. The trusted CLI enters that same installation-operator boundary.
Neither UUID syntax validation alone nor hiding a UI field would close PUT
allocation. Revision/source data and stored historical IDs are not rewritten.
Trusted internal seeds/fixtures still use their existing host workflow; it is not
an external allocation API. A pre-existing legacy ID `new` is not migrated or
made routable by this change. The review's assumed ability to create it through
the API is now forbidden and its test is replaced with the approved contract.

## Red-green evidence

- Calls authority test failed by returning a newly created revision with ID `new`
  instead of not_found. The preceding attempted edit used the child working
  directory with a root-relative path and did not change the file; corrected
  the path before the actual failing regression run.
- Real Gateway transport + Calls memory repository: two failures, returning 201
  instead of 404 for caller-selected IDs and another tenant's ID. No stubbed save
  outcome is used in these identity regressions.
- Database-backed CLI regression failed because --call-spec-id new created a
  record instead of raising not_found.
- After implementation: Calls 2/2, Gateway identity + existing write tests 12/12,
  Persistence CLI + scoped carrier/voice authoring 29/29 (2 excluded), Console
  endpoint tests 11/11, editor routing tests 8/8. Console tests also reject body
  identity fields and missing update targets. Gateway tests prove generated
  UUID creation, same-ID append and unchanged revision 1.
- Editor routing fixtures now use a UUID returned by the server; creation submits
  only source, exposes no identity control and uses returned identity for routing
  and publication. No rendered UI or production frontend logic changed in this
  follow-up, so browser verification from the integer fix remains the applicable
  visual check. The formerly failing `new` API-authored-spec test no longer
  describes an allowed creation path.

## Verification

Strict Credo passes. Full frontend tests/type/lint and the five required umbrella
gates are running sequentially in a dedicated tmux session. This avoids the
previous tool-session SIGTERM and serializes heavy work. No live tests, live
credentials file access or source-cutover/speech-state-machine changes; Lean is
not required. API guide, CLI guide, editor guide/source decision and milestone
now document POST-only allocation and PUT/CLI existing-target semantics.

## Final verification

All 511 frontend tests pass in 67 files; TypeScript and lint pass. All five root
gates pass, including 3,464 tests with zero failures and 120 exclusions (seed
303191). Gateway took 488.7 seconds, matching its normal baseline. The sequential
tmux runner exited successfully. git diff --check passes. No live test or Lean
lane ran. No commits were made. Earlier integer-preservation work and unrelated
files remain intact.

## Identity checkpoint commit

Staged the server-owned identity implementation, API/CLI/UI contract tests,
identity documentation and this labnote as one checkpoint at the user’s request.
Selected identity-only changes in shared files; the integer-precision changes,
their regression and review labnotes, and the unrelated cache-repair labnote
remain uncommitted. No runtime code changed after the completed verification.
