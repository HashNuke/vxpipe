defmodule Vxpipe.Persistence.Repo.Migrations.AddMcpCatalogFreshness do
  use Ecto.Migration

  def change do
    alter table(:tenant_mcp_connections) do
      add(:refresh_scheduled_at, :utc_datetime_usec)
      add(:refreshed_at, :utc_datetime_usec)
    end

    create(
      index(:tenant_mcp_connections, [:refreshed_at, :refresh_scheduled_at, :id],
        where: "status = 'connected'",
        name: :tenant_mcp_catalog_refresh_due_index
      )
    )
  end
end
