defmodule Vxpipe.Persistence.Repo.Migrations.MergeCredentialReadIntoServices do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE roles SET revision = revision + 1, updated_at = now()
    WHERE id IN (SELECT role_id FROM role_permissions WHERE permission_key = 'tenant_api_keys.read')
    """)

    execute("""
    INSERT INTO role_permissions (role_id, permission_key, scope)
    SELECT role_id, 'tenant_services.read', scope
    FROM role_permissions WHERE permission_key = 'tenant_api_keys.read'
    ON CONFLICT (role_id, permission_key) DO UPDATE SET scope =
      CASE WHEN role_permissions.scope = 'all_tenants' OR EXCLUDED.scope = 'all_tenants'
        THEN 'all_tenants' ELSE 'assigned_tenants' END
    """)

    execute("DELETE FROM role_permissions WHERE permission_key = 'tenant_api_keys.read'")

    execute(
      "UPDATE permissions SET requires_read = 'tenant_services.read' WHERE key = 'tenant_api_keys.write'"
    )

    execute("DELETE FROM permissions WHERE key = 'tenant_api_keys.read'")
  end

  def down do
    raise Ecto.MigrationError,
          "merged service and credential read scopes cannot be split without losing custom grants"
  end
end
