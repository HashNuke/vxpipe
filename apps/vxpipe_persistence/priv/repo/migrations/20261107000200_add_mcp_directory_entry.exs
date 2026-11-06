defmodule Vxpipe.Persistence.Repo.Migrations.AddMcpDirectoryEntry do
  use Ecto.Migration

  def change do
    alter table(:tenant_mcp_connections) do
      add(:directory_entry, :map)
    end
  end
end
