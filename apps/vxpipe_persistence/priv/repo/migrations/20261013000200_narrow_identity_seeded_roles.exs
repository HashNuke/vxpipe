defmodule Vxpipe.Persistence.Repo.Migrations.NarrowIdentitySeededRoles do
  use Ecto.Migration
  import Ecto.Query

  @removed_slugs ["platform-manager", "call-reviewer", "directory-reader"]

  def up do
    flush()

    # Remove obsolete seeded templates when unused; custom roles remain supported.
    # Permissions first so role deletion never orphans grant rows.
    for slug <- @removed_slugs do
      case role_id(slug) do
        nil ->
          :ok

        id ->
          repo().delete_all(from(g in "role_permissions", where: g.role_id == ^id))

          # Only delete when no users reference the role; otherwise leave the
          # role in place to avoid breaking existing accounts (reported as blocker).
          unless role_in_use?(id) do
            repo().delete_all(from(r in "roles", where: r.id == ^id))
          end

          :ok
      end
    end

    # Tenant Manager: assigned-tenant call/call-spec read+write only.
    narrow_role!("tenant-manager", "Tenant Manager", [
      {"calls.read", "assigned_tenants"},
      {"calls.write", "assigned_tenants"},
      {"call_specs.read", "assigned_tenants"},
      {"call_specs.write", "assigned_tenants"}
    ])

    # Tenant Member: assigned-tenant call/call-spec read only.
    narrow_role!("tenant-member", "Tenant Member", [
      {"calls.read", "assigned_tenants"},
      {"call_specs.read", "assigned_tenants"}
    ])

    :ok
  end

  def down do
    flush()

    # Restore the broader template grants from the initial seed for reversibility.
    narrow_role!("tenant-manager", "Tenant Manager", [
      {"calls.read", "all_tenants"},
      {"calls.write", "all_tenants"},
      {"call_specs.read", "all_tenants"},
      {"call_specs.write", "all_tenants"},
      {"call_specs.use_platform_services", "installation"},
      {"platform_services.read", "installation"},
      {"tenant_services.read", "installation"},
      {"tenant_services.write", "installation"},
      {"tenant_api_keys.read", "installation"},
      {"tenant_api_keys.write", "installation"},
      {"tenants.read", "installation"},
      {"tenants.write", "installation"}
    ])

    narrow_role!("tenant-member", "Tenant Member", [
      {"calls.read", "assigned_tenants"},
      {"calls.write", "assigned_tenants"},
      {"call_specs.read", "assigned_tenants"},
      {"call_specs.write", "assigned_tenants"}
    ])

    :ok
  end

  defp narrow_role!(slug, _name, grants) do
    case role_id(slug) do
      nil ->
        :ok

      id ->
        repo().delete_all(from(g in "role_permissions", where: g.role_id == ^id))

        rows =
          for {permission, scope} <- grants do
            %{role_id: id, permission_key: permission, scope: scope}
          end

        repo().insert_all("role_permissions", rows, on_conflict: :nothing)
        :ok
    end
  end

  defp role_id(slug) do
    repo().one(from(r in "roles", where: r.slug == ^slug, select: r.id))
  end

  defp role_in_use?(role_id) do
    repo().exists?(from(u in "users", where: u.role_id == ^role_id))
  end
end
