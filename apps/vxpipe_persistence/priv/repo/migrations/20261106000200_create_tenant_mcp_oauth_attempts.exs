defmodule Vxpipe.Persistence.Repo.Migrations.CreateTenantMcpOauthAttempts do
  use Ecto.Migration

  def change do
    create table(:tenant_mcp_oauth_attempts) do
      add(:public_id, :uuid, null: false)
      add(:tenant_id, references(:tenants, on_delete: :delete_all), null: false)
      add(:state_digest, :binary, null: false)
      add(:binding, :map, null: false)
      add(:expires_at, :utc_datetime_usec, null: false)
      add(:claimed_at, :utc_datetime_usec)
      add(:encrypted_payload, :binary)
      add(:encryption_key_id, :string)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:tenant_mcp_oauth_attempts, [:public_id]))
    create(unique_index(:tenant_mcp_oauth_attempts, [:state_digest]))
    create(index(:tenant_mcp_oauth_attempts, [:tenant_id, :expires_at]))

    create(
      constraint(:tenant_mcp_oauth_attempts, :mcp_attempt_digest_size,
        check: "octet_length(state_digest) = 32"
      )
    )

    create(
      constraint(:tenant_mcp_oauth_attempts, :mcp_attempt_secret_state,
        check:
          "(claimed_at IS NULL AND encrypted_payload IS NOT NULL AND encryption_key_id IS NOT NULL) OR (claimed_at IS NOT NULL AND encrypted_payload IS NULL AND encryption_key_id IS NULL)"
      )
    )
  end
end
