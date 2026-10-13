# Identity auth security fixes

## Scope
Own: apps/vxpipe_identity, identity-related apps/vxpipe_persistence (stores, schemas, migration/seed, identity tests). No Console/Calls/frontend/runtime/docs/lockfile edits. No commits.

## Issues (from task)
1. create_user blocks Admin ordinary creation; authorize target kind only.
2. logout must propagate revoke failure; remove redundant post-txn revocations; atomic revocation; audit failures fail/rollback; bootstrap throttling.
3. Built-in role projections must show effective grants (consistent with Sessions).
4. Write-grant read prerequisite by scope; reject duplicate permission key across scopes before DB.
5. Port fail-closed on missing expected target role; revalidate actor status/session/grants inside write txns; race tests.
6. Seed only 4 roles (Superadmin, Admin, Tenant Manager, Tenant Member); Tenant Manager assigned_tenants call/call_spec read+write; Tenant Member assigned_tenants read only; no users/platform grants.
7. Console user_auth_database_endpoint_test.exs:80 as integration evidence.
8. Local Superadmin recovery: one-time local proof, atomic credential recovery/session revoke, tests, Console exposure report.

## Plan
- C1: create_user target-only + Admin positive/negative tests.
- C2: logout propagate + remove redundant revocations (rely on store atomic).
- C3: effective grants for built-ins in role_port_map + Sessions consistency.
- C4: permission validation by scope + duplicate key rejection (domain + store).
- C5: seed migration to 4 roles with correct grants.
- C6: transactional audit (store-level, rollback on failure).
- C7: bootstrap persisted throttling.
- C8: fail-closed expected role + actor revalidation + race tests.
- C9: recovery proof + atomic recovery.

## Progress
- Baseline: vxpipe_identity 40 tests pass.
- C1 done: require_account_create/2, Admin member-positive/superadmin-negative, 51 identity tests pass.
- C2 done: logout propagates revoke/audit failures, idempotent on not_found/expired/revoked, disabled triggers revoke; removed post-txn revokes in Accounts/Roles; store atomic revocation retained; login compensating revoke on audit failure.
- C3 done: Permission.builtin_grant_defs/1, role_port_map shows effective grants for superadmin/admin, consistent with Sessions.
- C4 done: same-scope read prerequisite + duplicate permission key rejection in Roles + IdentityRoleStore.
- C5 done: migration 20261013000200 narrows to 4 roles, tenant-manager assigned read+write (4), tenant-member assigned read-only (2), removes platform-manager/call-reviewer/directory-reader when unused.
- C6 done: audit transactional via :audit_event in user/role/installation stores; installation audit rollback; IdentityAuditStore hardened for non-UUID placeholders.
- C7 done: Bootstrap throttling via attempts port (rate check + record on proof/complete failures), unit + persisted integration tests.
- C8 done: fail-closed missing current role + role-change without expected (:stale_target); actor revalidation (enabled/session/grants) in user/role write txns; race tests for demotion/revocation/disable.
- C9 done: recovery proof port + store (issue requires complete, consume burns proof, resets superadmin password+enable, revokes all sessions, new session, audit); Bootstrap.recover_with_proof + issue_recovery_proof with throttling; unit + integration tests.
- Evidence: Console user_auth_database_endpoint_test.exs:80 passes (1 test, 0 failures).
- Checks: mix format applied to owned files; compile --warnings-as-errors clean; credo --strict clean (1281 files, no issues); identity 51 tests pass; persistence identity 28+17 tests pass.
