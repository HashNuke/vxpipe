# Tenant Services Authz (Calls domain)

## Goal
Tenant Manager starter role: ALL operations within assigned tenants (calls/specs +
tenant service config, tenant API keys/provider credentials, telephony apps).
Platform services + user management remain Admin/Superadmin only. Member stays
calls/specs read-only. Scope: `apps/vxpipe_calls` + Calls-specific
`apps/vxpipe_persistence`; no Identity/Console/frontend/docs edits, no commits.

## Findings
- `UserAuthorization.authorize_credential_read/write` used `authorize_installation`
  for all owners, even `{:tenant, key}` — tenant keys behaved installation-wide.
- `OperatorAdministration.list_services`, `OperatorTelephonyApplications.create/update/list`,
  `OperatorServiceBindings.list(tenant)` all required installation
  `tenant_services.read/write`. Assigned managers got `:forbidden`.
- `ProviderCatalog.authorize(UserPrincipal)` required installation
  `tenant_services.read` (dead for member-safe path, but inconsistent).
- Identity `Permission` in worktree already scopes `tenant_services.*` /
  `tenant_api_keys.*` to `[:all_tenants, :assigned_tenants]` (teammate change,
  untracked `apps/vxpipe_identity/`). `:installation` checks for those actions
  now always deny — Calls must use per-tenant checks.
- Console `RoutePermission` (untracked, teammate) already maps tenant
  services/bindings/apps/credentials to `{:tenant, perm, tenant}`. `RequireUserAPI`
  already authorizes `{:tenant, ...}` via `Authorization.authorize/4`. Only
  `RequireUser` page gate for services still uses `installed?`.

## Changes (owning boundaries only)
- `apps/vxpipe_calls/lib/vxpipe/calls/user_authorization.ex`:
  - Added `authorize_tenant_service_read/write/3` + reworked
    `authorize_credential_read/write` to route `:platform` → installation
    `platform_services.*`, tenant owners (bare/`{:tenant,key}`) →
    `authorize_tenant_scoped` with `tenant_api_keys.*`.
  - `authorize_tenant_scoped/4` tries `Authorization.authorize(grants, action,
    {:tenant, key}, ctx)` (covers admins + future assigned scopes), then
    built-in Admin/Superadmin grants fallback, then explicit assigned-membership
    fallback (grants + level cap: read allows `:read`/`:read_write`, write
    requires `:read_write`). Cross-tenant/platform denied for members.
  - Preserved `platform_authoring_allowed?` (`call_specs.use_platform_services`
    installation check) unchanged.
- `operator_administration.ex`: `list_services` → `authorize_tenant_service_read`.
  Credential CRUD/validate inherit tenant-scoped `authorize_credential_*`;
  `validate_created/updated_credential` already pins resolved owner to requested
  owner (fail-closed on mismatch); store scoping fail-closes deletes.
- `operator_telephony_applications.ex`: create/update → tenant write, list →
  tenant read. Projections unchanged (`@application_fields` + `@route_fields`
  only — no ingress/credential ids/secrets).
- `operator_service_bindings.ex`: tenant path → tenant read; `:platform` path
  stays installation `platform_services.read` (managers denied platform).
- `provider_catalog.ex`: `authorize(UserPrincipal)` → `authorize_tenant_service_read`
  (consistency; member-safe `providers/models` still require `call_specs.read`).
- No `apps/vxpipe_persistence` changes needed: stores are trusted, metadata-only
  (no payload in `AdminStore.list_services`, `EffectiveServiceBindings`;
  `ProviderCredentialStore` never logs payload). Telephony `ingress_key` /
  `credential_id` reach Console but `AdminServicesController.telephony_json/1`
  strips to id/name/provider/connection/credential_id/outbound — no secrets.

## Tests (red-green)
- Red: added `tenant_manager_principal` / `tenant_member_read_principal` helpers
  + 4 new tests (services list scoped, telephony apps scoped, bindings scoped,
  platform/tenant credentials scoped, member read-only). Initial run: 5 failures
  (cross-tenant allowed via installation grants, member paths).
- Green after impl: updated 3 pre-existing installation-only tests to assigned
  model (`service reads`, `telephony grants`, `bindings`, `credential` reader/
  writer use assigned; added cross-tenant `:forbidden` + superadmin global
  assertions).
- Evidence: `mix test apps/vxpipe_calls/test` → 172 tests, 0 failures.
  Focused files (authz, bindings, telephony apps, editor lookups, catalog,
  phone numbers, admin): 57 tests, 0 failures.
- `mix compile --warnings-as-errors` clean; `mix credo --strict` on 5 changed
  lib files no issues; `mix format --check-formatted` on changed files clean.
- Did not re-enable `InstallationOperator` authority; did not touch Identity/
  Console/frontend/docs; no stash/reset; no commits.

## Console RoutePermission report (no edits made)
- `RoutePermission.for_request` already tenant-scoped (teammate worktree):
  `GET services/service-bindings/telephony-applications` →
  `{:tenant, "tenant_services.read", tenant}`; `POST/PATCH telephony-applications`
  → `{:tenant, "tenant_services.write", tenant}`; `POST credentials[/test]` +
  `PATCH/DELETE credentials/:id` → `{:tenant, "tenant_api_keys.write", tenant}`.
  No changes needed there — keep as-is.
- One change still needed (Console owner): `RequireUser.permitted?` for
  `["admin", "tenants", _tenant, "services" | _]` currently
  `installed?(principal, "tenant_services.read")` — change to
  `tenant?(principal, "tenant_services.read", tenant)` (bind tenant segment
  instead of `_tenant`) so assigned managers can open the tenant Services page.
  `RequireUserAPI` needs no change (already handles `{:tenant, ...}`).
- Frontend `access.ts` already gates on `tenant_services`/`tenant_api_keys`
  grants; no report beyond keeping tenant-scoped checks.
