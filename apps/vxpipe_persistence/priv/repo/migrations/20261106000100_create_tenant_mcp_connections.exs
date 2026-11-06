defmodule Vxpipe.Persistence.Repo.Migrations.CreateTenantMcpConnections do
  use Ecto.Migration

  def change do
    create table(:tenant_mcp_connections) do
      add(:public_id, :uuid, null: false)
      add(:tenant_id, references(:tenants, on_delete: :delete_all), null: false)
      add(:endpoint, :text, null: false)
      add(:endpoint_identity, :text, null: false)
      add(:directory_id, :string)
      add(:server_name, :string, null: false)
      add(:auth_method, :string, null: false)
      add(:generation, :bigint, null: false)
      add(:status, :string, null: false)
      add(:catalog, :map, null: false)
      add(:encrypted_payload, :binary)
      add(:encryption_key_id, :string)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:tenant_mcp_connections, [:public_id]))
    create(unique_index(:tenant_mcp_connections, [:tenant_id, :endpoint_identity]))

    create(
      unique_index(:tenant_mcp_connections, [:tenant_id, :directory_id],
        where: "directory_id IS NOT NULL"
      )
    )

    create(constraint(:tenant_mcp_connections, :mcp_generation_positive, check: "generation > 0"))

    create(
      constraint(:tenant_mcp_connections, :mcp_status,
        check: "status IN ('connected', 'revoked')"
      )
    )

    create(
      constraint(:tenant_mcp_connections, :mcp_auth_method,
        check: "auth_method IN ('none', 'bearer', 'headers', 'basic', 'oauth')"
      )
    )

    create(
      constraint(:tenant_mcp_connections, :mcp_secret_state,
        check:
          "(status = 'revoked' AND encrypted_payload IS NULL AND encryption_key_id IS NULL) OR (status = 'connected' AND encrypted_payload IS NOT NULL AND octet_length(encrypted_payload) > 29 AND encryption_key_id IS NOT NULL)"
      )
    )
  end
end
