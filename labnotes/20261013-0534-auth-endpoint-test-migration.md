# Auth endpoint test migration

## Red (2026-10-13)
- `mix test apps/vxpipe_console/test/vxpipe/console/admin_tenants_endpoint_test.exs` → 3 tests, 3 failures. `authenticate()` GETs `/auth/login-token/:token` (removed route) so `csrf_token/1` gets nil from Regex (`MatchError`).
- Full Console dir: 278 tests, 93 failures (later 269/1 after migration). Failures are login-token form POSTs and `InstallationOperatorSession.put()` helpers; anonymous JSON expects `operator_session_required` but new `RequireUserAPI` returns `session_required`.
- Excluded auth tests (`user_auth_endpoint`, `require_user*`, `route_permission`, `user_session`, `user_management_payload`, `user_identity`) already use `/auth/api/login` + `Backend` fakes and pass. Left untouched.
- Identity source broke compilation mid-run (`Accounts.reset_password/update_user` undefined fns, ~05:36 UTC). Used `touch _build/test/lib/vxpipe_identity/ebin/*.beam` to skip Identity recompile for Console verification (build artifact only, no source edit). Later Identity work fixed it; final `mix compile --warnings-as-errors` passes.

## Green
- Created `apps/vxpipe_console/test/support/fake_user_identity.ex` (`Vxpipe.Console.Test.FakeUserIdentity`): fixed email/password/token, `principal()` returns real `%Vxpipe.Identity.Principal{}` (superadmin, grants = full `Permission.catalog()`, `all_tenant_actions` = same set so tenant + installation checks pass), `login/setup/authenticate/logout/status/session_details` + `update_account/5` matching `AccountController`, other directory/role calls fail closed with `:forbidden`, `issue_setup_proof` returns `:unavailable`.
- Per-test `setup`/`on_exit` puts/restores `:user_identity_backend` (never global). Removed `:operator_login_secret` + `OperatorLoginChallengeRepository` config from endpoint tests. Preserved Calls `admin_repository`/credential/validator/backend configs and DB sandboxes.
- Migrated `authenticate()` to `POST https://localhost/auth/api/login` with fake credentials; `authenticated_conn` (endpoint/diagnostics) to `init_test_session(%{"vxpipe_user_session" => FakeUserIdentity.token()})`; anonymous JSON code to `session_required`; preserved pagination/JSON/error-code substance.
- Files migrated: admin_tenants, admin_onboarding, admin_calls, admin_provider_catalog, call_details, call_recording, call_inspection_json, admin_services, admin_telephony_applications, admin_call_specs (missing-tenant key changed "missing"→"BBBBBBBBBBBBBBBB" to satisfy 16-char `ProviderAuth.tenant_key` while keeping 404 intent), endpoint, diagnostics_live, legacy_operator_routes (kept `vxpipe_operator` legacy_session helpers for clearing/410 assertions).
- Rewrote `operator_login_flow_test.exs`: legacy `/auth/login-token` → 404, legacy `vxpipe_installation_operator` session cannot auth, anonymous HTML→`/auth/login` + JSON 401 `session_required`, named session reaches `/admin` + `/admin/api/session`, sign-out drops session.
- Rewrote `operator_login_task_test.exs`: task issues only local setup proof via `:user_identity_backend`, never operator URL/code/challenge repo; covers pending-proof, fresh-install, complete, persistence-failure. Complements supplied `setup_proof_task_test.exs`.
- Left passing non-endpoint tests untouched: `installation_operator_session`, `operator_authentication`, `operator_login_configuration`, `*_runtime_configuration`, `demo_samples` (Calls-domain `InstallationOperator.authority` setup), `scoped_telnyx`, `public_telephony`, `sample_call`, etc.

## Verification
- `mix test apps/vxpipe_console/test/vxpipe/console` → 269 tests, 1 failure (legacy `vxpipe_operator` clearing on GET /admin; needs source fix, see findings file).
- Excluded/new auth tests: user_auth/require_user*/route_permission/user_session/user_management_payload/user_identity/setup_proof/user_auth_database → 33 tests, 0 failures.
- `mix format --check-formatted` on touched files passes. `mix compile --warnings-as-errors` passes. `mix credo --strict` on new/rewritten files: no issues.
- No commits. Findings: `vxpipe-auth-test-migration-findings.txt (temporary review output)`.
