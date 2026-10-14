defmodule Vxpipe.Persistence.Repo.Migrations.MergePlatformAuthoringIntoRead do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE roles SET revision = revision + 1, updated_at = now()
    WHERE id IN (
      SELECT role_id FROM role_permissions
      WHERE permission_key = 'call_specs.use_platform_services'
    )
    """)

    execute("""
    INSERT INTO role_permissions (role_id, permission_key, scope)
    SELECT role_id, 'platform_services.read', 'installation'
    FROM role_permissions WHERE permission_key = 'call_specs.use_platform_services'
    ON CONFLICT (role_id, permission_key) DO NOTHING
    """)

    execute(
      "DELETE FROM role_permissions WHERE permission_key = 'call_specs.use_platform_services'"
    )

    execute("DELETE FROM permissions WHERE key = 'call_specs.use_platform_services'")
  end

  def down do
    raise Ecto.MigrationError,
          "merged platform read and authoring grants cannot be split without losing custom grants"
  end
end
