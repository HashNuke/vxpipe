# Editor member gaps

## Task
Security: `member_application?/2` admitted platform-owned scoped apps. Functional:
`editor-api.ts` needs providers/models and numbers for members with only
`call_specs.read/write`. Implement Calls safe reads, report Console
RoutePermission changes, no Console edits.

## What worked
- Red: new test `member hides platform-owned scoped app present in both services
  and applications` failed with `platform-app` leaked via applications path.
  Fixed `member_application?/2` with owner guard
  `owner in [nil, {:tenant, tenant}]` plus `validate/1`.
- `list_member_applications/3` now validates all rows against privileged
  superset (`editor_application?(_, _, true)`) then filters to
  `privileged?` visibility, mirroring services directory filtering. Members
  hide platform, privileged see it, foreign/malformed still fail closed.
- Persistence: new test `lists scoped platform applications with ownership and
  no secrets` passes; `AdminStore.list_telephony_applications/2` already
  derived `credential_owner` via `scoped_telnyx_ownership/2`, no secrets.
- ProviderCatalog: red tests for member/privileged failed with `:forbidden`.
  Added `UserPrincipal` clauses requiring exact
  `authorize_tenant(call_specs.read)` tenant authority. Availability filters
  to `source==:tenant` unless `platform_authoring_allowed?`; output only
  public listings + booleans, no credential metadata.
- OperatorPhoneNumbers: red tests failed with `:forbidden`. Added
  `UserPrincipal` clause requiring exact `call_specs.read`, tenant pinning,
  owner allowlist (`nil|{:tenant,key}`, plus `:platform` if privileged),
  strict `validate_page/1` and `validate_assignments/1` projecting only
  `{id,number,name,available,assigned_to}` + `next_page`. Credential payload
  stays in reader closure.
- Updated `user_principal_authorization_test` to assert exact
  `call_specs.read` authority and that `tenant_services.read` alone is
  `:forbidden` for both catalog and numbers. Caller (`Principal :admin`)
  and `InstallationOperator` paths unchanged.

## Tests
- `call_spec_editor_lookups + provider_catalog + operator_phone_numbers +
  user_principal_authorization`: 29 tests pass.
- `apps/vxpipe_calls/test`: 167 tests, 1 flaky `billing_enrichment` failure
  (passes in isolation, unrelated, noted in prior labnotes).
- `admin_store_test`: 10 tests pass.
- `mix format --check-formatted` clean, `mix compile --warnings-as-errors`
  clean, `mix credo --strict` on 3 touched Calls files clean.

## Console RoutePermission adjustments needed (not edited)
- `GET tenants/:tenant/providers` currently
  `{:tenant, "tenant_services.read", tenant}` -> change to
  `{:tenant, "call_specs.read", tenant}`.
- `GET tenants/:tenant/providers/:provider/models` currently
  `tenant_services.read` -> change to `call_specs.read`.
- `GET tenants/:tenant/telephony-services/:service/numbers` currently
  `tenant_services.read` -> change to `call_specs.read`.
- `call-spec-editor-lookups`, `call-specs` GET/POST/PUT already use
  `call_specs.read/write`; no change. Caller `Principal` paths unchanged.
