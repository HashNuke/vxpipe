# Identity final review — independent findings

## Scope
- Only `apps/vxpipe_identity` and `apps/vxpipe_persistence`. No Console/Calls/frontend/docs/config edits. No commits.

## Finding 1 — actor/session enforcement
- Red: `apps/vxpipe_identity/test/vxpipe/identity/actor_enforcement_test.exs` (5 tests) failed before fix (placeholder/missing session returned `:ok`); `apps/vxpipe_persistence/test/vxpipe/persistence/identity_final_review_test.exs` actor tests failed before fix.
- Fix:
  - `Authorization.require_actor_identity/1` (UUID-shaped `user_public_id` + `session_public_id`) enforced at start of `Accounts.create/update/reset` and `Roles.create/update/delete`.
  - `IdentityRecord.revalidate_actor/2` now requires both IDs as UUIDs, enabled actor, live session (nil/malformed/non-UUID → `:forbidden`); `check_actor_session/2` rejects missing/malformed/revoked/expired/foreign sessions.
  - `IdentityRoleStore.revalidate_role_actor/1` same strictness + admin/superadmin kind check.
  - `IdentityUserStore.revalidate_updater/3` allows self-service password-proof path (`expected_current_password_hash` + only email/password fields, no role/disabled/membership/actor keys) without privileged actor; all other updates require live actor. `create` always privileged.
- Fixtures: identity unit fixtures now use fixed UUID actor+session; persistence `identity_*_test.exs` use `real_actor!` (login+authenticate) instead of `"setup"` placeholder; direct store privileged updates now include actor IDs; concurrent-demotion race now uses second privileged actor instead of actor-less store bypass.
- Green: `apps/vxpipe_identity` 57 tests pass; persistence identity files 43 tests pass.

## Finding 2 — bootstrap audit atomicity
- Red: `bootstrap_audit_test.exs` (FailingAudit still reported success) failed before fix; persistence `identity_final_review_test.exs` outer-audit test showed false failure (`:unavailable` after commit).
- Fix: removed outer `audit.append` from `Bootstrap.complete_first_run/complete_with_proof/recover_with_proof`; durable audit stays inside atomic `IdentityInstallationStore` transaction (`setup_completed`/`recovery_used`). Added optional `:audit_event` override in installation store to test atomic rollback (invalid overlong action → rollback).
- Tests: unit no-false-failure; persistence outer-audit success + durable event count; user-create audit rollback; installation setup audit rollback.
- Green as above.

## Finding 3 — proof purpose separation
- Red: `issue_setup_proof` succeeded after complete; setup proof usable for recovery and vice versa.
- Fix:
  - Migration `20261013000300_add_proof_purpose.exs`: adds `purpose` (`setup`/`recovery`, not-null, check constraint); backfills NULL → `setup` (old recovery proofs fail closed, must re-issue).
  - Schema validates inclusion.
  - `issue_setup_proof` now locks installation and requires pending `operator_required` (`:already_completed` if complete, `:not_required` if fresh `first_run`); inserts `purpose="setup"`. `issue_recovery_proof` inserts `purpose="recovery"` (requires complete, unchanged).
  - `lock_and_burn_proof/2` checks purpose equality, else `:invalid_proof`; pre-purpose NULL rows fail closed.
- Tests: `issue_setup_proof` fails once complete; cross-use across persisted DB (leftover setup → recovery rejected; recovery → setup rejected).
- Green as above.

## Verification
- `apps/vxpipe_identity`: `mix test` 57 pass.
- `apps/vxpipe_persistence` identity files: `identity_store/workflow/auth_review/final_review` 43 pass.
- `mix compile --warnings-as-errors`: clean.
- `mix credo --strict`: no issues (1282 files).
- `mix format` applied to touched identity/persistence files; full-repo `format --check` still has pre-existing unrelated diffs (untouched).
- Seeded-role migrations `20261013000100/20261013000200` untouched.

## Console API/contract changes (report, not implemented)
- `issue_setup_proof` now fails when complete (`:already_completed`) or fresh (`:not_required`); Console `UserIdentity.issue_setup_proof/0` and `mix vxpipe.login` must handle these.
- Privileged writes now require UUID actor + live session; Console already passes real `Principal`, no code change, but fabricated test actors (`test-owner`) routed through real domain/stores get `:forbidden`.
- Bootstrap setup/recover no longer surface outer audit-sink failures; audit durability via DB events. Callers monitoring outer audit errors should check `user_access_events`.
- Proofs are purpose-bound; cross-use is `:invalid_proof`. Old unused recovery proofs from before migration must be re-issued.

## Remaining blockers
- Old pre-migration recovery proofs backfilled as `setup` and will fail recovery use; operators must re-issue after deploy.
- Full umbrella `mix test` / `mix format --check-formatted` not run to green due to pre-existing dirty worktree outside scope.
