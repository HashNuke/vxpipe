defmodule Vxpipe.Persistence.Repo.Migrations.ScopeTenantOperations do
  use Ecto.Migration
  import Ecto.Query

  @tenant_keys [
    "tenant_services.read",
    "tenant_services.write",
    "tenant_api_keys.read",
    "tenant_api_keys.write"
  ]

  def up do
    flush()

    repo().update_all(
      from(p in "permissions", where: p.key in ^@tenant_keys),
      set: [scopes: ["all_tenants", "assigned_tenants"]]
    )

    # Existing installation grants conferred all-tenant authority. Preserve
    # that authority explicitly when these keys become tenant-scoped.
    repo().update_all(
      from(g in "role_permissions",
        where: g.permission_key in ^@tenant_keys and g.scope == "installation"
      ),
      set: [scope: "all_tenants"]
    )

    manager_id =
      repo().one(from(r in "roles", where: r.slug == "tenant-manager", select: r.id))

    # Only expand the untouched four-grant template. An installation that
    # edited this ordinary role between migrations keeps its chosen grants.
    if manager_id && original_manager_template?(manager_id) do
      grants =
        Enum.map(@tenant_keys, &{&1, "assigned_tenants"}) ++
          [{"call_specs.use_platform_services", "installation"}]

      rows =
        Enum.map(grants, fn {permission, scope} ->
          %{role_id: manager_id, permission_key: permission, scope: scope}
        end)

      repo().insert_all("role_permissions", rows, on_conflict: :nothing)
    end
  end

  def down do
    raise Ecto.MigrationError,
          "tenant operation scopes cannot be automatically rolled back without losing custom grants"
  end

  defp original_manager_template?(manager_id) do
    expected = MapSet.new(["calls.read", "calls.write", "call_specs.read", "call_specs.write"])

    actual =
      repo().all(from(g in "role_permissions", where: g.role_id == ^manager_id,
        select: {g.permission_key, g.scope}))

    length(actual) == 4 and
      MapSet.new(actual) == MapSet.new(Enum.map(expected, &{&1, "assigned_tenants"}))
  end
end
