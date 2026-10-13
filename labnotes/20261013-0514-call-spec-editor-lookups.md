# Call spec editor lookups - member fix

## Task
Assigned-tenant member with call_specs.read (+ calls rights, no tenant_services.read)
could not load CallSpecEditorLookups due to tenant_services.read gate in
OperatorAdministration.list_services / OperatorTelephonyApplications.list.

## What worked
- Red test reproduced: member with only call_specs.read got {:error, :forbidden}.
- Fixed in apps/vxpipe_calls only: new UserPrincipal path in CallSpecEditorLookups
  uses tenant-pinned safe readers (admin_repository directly) instead of
  tenant_services.read-gated operators.
- Safe projection: credential_names filtered to source==:tenant; telephony
  filtered to tenant-owned (credential_owner nil | {:tenant, key}); output only
  %{key,name,provider}; credentials/ingress_keys never returned.
- Foreign tenant rows fail closed; platform-owned telephony hidden (filtered);
  platform bindings hidden.

## Tests
- New: apps/vxpipe_calls/test/vxpipe/calls/call_spec_editor_lookups_test.exs (4 tests)
  - member loads without tenant_services.read, tenant-owned only, no secrets
  - auth/tenant pinning/key format enforced, crossed tenant fails
  - operator path preserved
  - platform-owned service hidden
- Evidence: focused file 4/4 pass; related (lookups+user_auth+admin+apps) 34/34 pass;
  full apps/vxpipe_calls/test 159/159 pass.
- mix format --check-formatted clean for edited files; mix compile --warnings-as-errors clean.

## Remaining limitations
- Member path always tenant-owned only; privileged use_platform_services authors
  do not see platform bindings/services in lookups (can still author by name).
- Requires admin_repository to implement list_telephony_applications; else
  :telephony_services_unavailable (fail-closed).
- Identity Sessions map-vs-Principal mismatch and built-in grants untouched per scope.
