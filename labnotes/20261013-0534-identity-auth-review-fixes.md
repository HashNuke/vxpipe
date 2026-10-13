# Identity/Persistence authentication review fixes

Scope: `apps/vxpipe_identity` and Identity-related `apps/vxpipe_persistence` files only.
No commits. Console/Calls/frontend/runtime/docs/lockfile untouched.

## What worked

- Red-green per fix: new `apps/vxpipe_identity/test/vxpipe/identity/authorization_review_test.exs`
  (13 tests, all failed first for the expected reason) and new
  `apps/vxpipe_persistence/test/vxpipe/persistence/identity_auth_review_test.exs`
  (10 tests, 7 failed first for the expected reason).
- `Authorization.authorize_entry/4` now exact-matches `users.*` keys (`users.read`
  never authorizes writes; one users-write never authorizes another). Tenant path
  generalized from a hardcoded calls/specs cap to the entry `mutating` flag, with
  assigned-scope gating on `:assigned_tenants` and all-tenant gating that also honors
  installation-scoped operational grants (tenant services/keys checked per-tenant).
- `Permission.builtin_grants/1` covers all operational Console route keys for both
  built-ins (calls, call_specs + use_platform_services, platform_services,
  tenant_services, tenant_api_keys, tenants, diagnostics + the four users keys).
  `Sessions` builtin grants/all-tenant actions mirror this; ordinary installation
  tenant-service/key grants count as all-tenant authority for per-tenant checks.
- Stale-role protection: `Accounts.update_user` auto-stamps
  `expected_current_role_public_id` (plus fail-fast precheck) and maps
  `:stale_target` to `:forbidden`; `reset_password/6` takes optional opts
  (map or keyword, default `%{}` so `/5` callers unaffected). `IdentityUserStore`
  rechecks expected role + expected password hash against the `FOR UPDATE` row.
- Atomic revocation: `IdentityUserStore.apply_update` revokes the user's sessions
  in the same transaction on role/membership/disabled/password changes
  (idempotent; domain layer may repeat). `IdentityRoleStore` already revoked
  role-wide in-transaction; kept.
- Membership fix: `update_user` with unchanged role now validates against the
  fetched current role instead of empty grants.
- New `Accounts.change_own_details/6` (email and/or password atomically, current
  password required, stale hash maps to `:invalid_credentials`, revokes on password
  change, fail-closed when no session store). `change_own_password/email` also pass
  `expected_current_password_hash`.
- `Roles.update_role` requires integer `expected_revision >= 1` (nil invalid);
  store enforces the same. New `Ports.Roles.count_users/1`, `IdentityRoleStore`
  implementation, and `Roles.affected_user_count/2` (tolerates adapters without it).
- One-module-per-file splits: `ports.ex` into six `ports/*.ex` files,
  `NoopAudit`/`Argon2Hasher`/`Clock`/`Uuid` into own files, `fakes.ex` into five
  `fake_*.ex` files. `Roles` scope parsing uses a fixed mapping (no
  `String.to_existing_atom`); no `String.to_atom` on DB values remains in scope.
- No temp/debug tests or `IO.inspect`/`dbg` in scope.

## What did not / barriers

- Worktree is shared and dirty (parallel Console/Calls work in progress); a transient
  `vxpipe_calls` compile break from another agent briefly blocked the persistence
  suite, then cleared. Left their files alone.
- A parallel agent also touched `accounts.ex` (fail-fast `check_expected_role`) and
  added `test/support/fake_member_users.ex`; both are coherent and the suite is green.

## Verification evidence

- `apps/vxpipe_identity`: 40 tests, 0 failures.
- Persistence identity trio (store + workflows + review): 26 tests, 0 failures.
- Calls `user_principal_authorization` + `call_spec_editor_lookups`: 19 tests, 0 failures.
- `mix format --check-formatted` on all touched paths: clean.
- `mix compile --warnings-as-errors --force` for identity and persistence: clean.
- `mix credo --strict` (umbrella): no issues. `mix deps.unlock --check-unused`: clean.

## Decisions and rationale

- `:stale_target` (store) maps to `:forbidden` for admin paths (no existence/kind
  leak) and `:invalid_credentials` for self-service (concurrent reset looks like a
  wrong current password).
- Directory reads now require exact `users.read` (writes no longer imply read),
  matching the exact-match rule; all built-ins carry `users.read` so no matrix change.
- kept `apply_update` return shape; affected-user count is a separate retrievable
  query rather than a shape change.

## APIs added

- `Accounts.change_own_details(deps, user_id, current_password, email, new_password, confirmation)`
- `Accounts.reset_password/6` (opts: `:expected_current_role_public_id`)
- `Roles.affected_user_count(deps, role_public_id)` + `Ports.Roles.count_users/1`
- `Permission.operational_grants/0`
- `apply_update` honors `:expected_current_role_public_id`,
  `:expected_current_password_hash` (user store) and requires `:expected_revision`
  (role store).

## Limitations / follow-ups for Console owners (out of scope)

- `RoleManagementController` maps `:stale` to 409 but Identity returns
  `:stale_revision`; a missing `expected_revision` currently surfaces as 422
  `invalid_role`. One-line mapping alignment needed on the Console side.
- `UserManagementController.update/reset_password` do not send
  `expected_current_role_public_id`; protection still holds because the domain
  auto-stamps the precheck-observed role, but UI stale-edit conflicts cannot show a
  distinct message until the controller forwards the observed role.
- Permission seeds/migration not touched: templates already seed the operational
  keys; no catalog migration was required.
