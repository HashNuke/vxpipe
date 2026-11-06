defmodule Vxpipe.Persistence.Repo.Migrations.RequireConnectedMcpCiphertext do
  use Ecto.Migration

  # Upgrade checkouts that already applied the original preview migration.
  def up do
    drop(constraint(:tenant_mcp_connections, :mcp_secret_state))

    create(
      constraint(:tenant_mcp_connections, :mcp_secret_state,
        check:
          "(status = 'revoked' AND encrypted_payload IS NULL AND encryption_key_id IS NULL) OR (status = 'connected' AND encrypted_payload IS NOT NULL AND octet_length(encrypted_payload) > 29 AND encryption_key_id IS NOT NULL)"
      )
    )
  end

  # The initial migration now has this invariant too; rolling back this preview
  # compatibility step must not weaken the schema defined by that migration.
  def down, do: :ok
end
