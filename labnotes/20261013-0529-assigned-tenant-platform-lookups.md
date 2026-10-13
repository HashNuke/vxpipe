# Assigned tenant platform lookups

## Task
Fix two reviewed integration gaps without touching Identity, Console, root config/docs/lock:
1. `list_operator_tenants` required `tenants.read`, denying assigned members with only
   `calls`/`call_specs` grants.
2. Privileged call-spec editor lookup saw platform refs in fake Calls tests, but real
   `AdminStore.list_services/2` filtered out platform-backed services and lacked
   `credential_owner`.

## What worked
- Red-green for gap 1 in `apps/vxpipe_calls`:
  - New test `assigned member without tenants.read lists only assigned tenants` failed with
    `{:error, :forbidden}` before fix, passes after.
  - `UserAuthorization.authorize_assigned_tenant_list/1`, `listable_assigned_keys/1`,
    `assigned_keys/1`, `scoped_assigned_list/4` allow nonempty assigned grants permitting
    any of `calls.read/write`, `call_specs.read/write` (cap-aware via `Authorization`).
  - `OperatorAdministration.list_tenants/2` keeps `tenants.read` path unchanged, falls back
    to assigned-only `list_tenants_scoped({:keys, keys})` so filtering/count stays in storage
    before pagination; foreign rows still fail via `validate_listed_tenants/2`.
- Red-green for gap 2:
  - Calls: new test `privileged lookup sees scoped platform binding with nil ids` failed on
    `TelephonyService.validate/1` before fix, passes after. Member still hides platform,
    output stays `%{key,name,provider}` with no ingress/credential ids.
  - Persistence: new test `lists scoped platform service names with ownership and no secrets`
    failed with `services == []` before fix, passes after. Provisions `:platform`
    `telnyx/telnyx`, registers scoped `credential_name=telnyx` app, asserts
    `credential_owner == :platform` then `{:tenant, key}` after tenant override, and asserts
    no private `api_key`/`public_key` in inspect. Credentials list stays tenant-only.
  - `TelephonyService.validate/1` now allows scoped `telnyx/telnyx` nil-id rows with owner
    `nil | :platform | {:tenant, key}`.
  - `AdminStore.list_services/2` now selects `credential_name`, fetches all tenant services
    (not just `credential_id in tenant_ids`), derives scoped owner via
    `scoped_telnyx_ownership/2` (tenant override wins, else platform). Same derivation added
    to `list_telephony_applications/2`. No encrypted payloads or platform credential rows
    returned.
  - `CallSpecEditorLookups.filter_member_service_directory/5` and
    `OperatorAdministration.validate_service_directory/4` accept scoped nil-id tenant rows
    and platform rows via `validate/1`, still pin `tenant_key` and filter by
    `allowed_owners`.

## Tests
- `mix test apps/vxpipe_calls/test/vxpipe/calls/user_principal_authorization_test.exs
  apps/vxpipe_calls/test/vxpipe/calls/call_spec_editor_lookups_test.exs
  apps/vxpipe_persistence/test/vxpipe/persistence/admin_store_test.exs`: 18 + 9 tests pass
  (27 total across runs, 12+6+9 in combined focused run).
- `mix test apps/vxpipe_calls/test/vxpipe/calls/user_principal_authorization_test.exs
  apps/vxpipe_calls/test/vxpipe/calls/call_spec_editor_lookups_test.exs
  apps/vxpipe_calls/test/vxpipe/calls/operator_administration_test.exs`: 36 tests pass.
- `mix test apps/vxpipe_persistence/.../admin_store_test.exs
  .../scoped_telnyx_service_test.exs .../operator_telephony_applications_test.exs`: 21 pass.
- `mix format` on touched files clean, `mix compile --warnings-as-errors` clean,
  `mix credo --strict` on touched files clean.
- Full `apps/vxpipe_calls/test` (162 tests) shows 1 flaky async failure per run in unrelated
  `billing_enrichment` / `publication_worker` (passes in isolation); no failures in owning
  boundaries.

## Remaining gaps
- `AdminStore` scoped ownership uses existence checks for `telnyx/telnyx` only; other providers
  with future scoped bindings would need extension.
- Orphaned scoped rows (no tenant override and no platform credential) return `nil` owner and
  remain visible as tenant-owned; fail-closed would require explicit error.
- `visible_tenant_scope(:all)` via `all_tenant_actions` still requires `tenants.read` for full
  listing; fallback is assigned-only by design. Admins without `tenants.read` but with
  `all_tenants` useful grants see only assigned, not all.
- Twilio platform-owned UUID rows are accepted by validation only for telnyx scoped shape;
  twilio platform via `credential_id` remains impossible due to FK (`tenant_id` match).
- Full umbrella `mix test` and Lean lane not run per scope (Console/Identity untouched).
