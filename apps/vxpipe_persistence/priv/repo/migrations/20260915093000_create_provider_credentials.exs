defmodule Vxpipe.Persistence.Repo.Migrations.CreateProviderCredentials do
  use Ecto.Migration

  def change do
    create table(:provider_credentials) do
      add(:public_id, :uuid, null: false)
      add(:tenant_id, references(:tenants, on_delete: :delete_all), null: false)
      add(:provider, :string, null: false)
      add(:name, :string, null: false)
      add(:auth_kind, :string, null: false)
      add(:encrypted_payload, :binary, null: false)
      add(:encryption_key_id, :string, null: false)
      add(:payload_schema_version, :integer, null: false)
      add(:version, :integer, null: false)
      add(:status, :string, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:provider_credentials, [:public_id]))
    create(unique_index(:provider_credentials, [:tenant_id, :provider, :name]))

    create(
      constraint(:provider_credentials, :provider_credentials_positive_versions,
        check: "version > 0 AND payload_schema_version > 0"
      )
    )

    create(
      constraint(:provider_credentials, :provider_credentials_status,
        check: "status IN ('active', 'revoked')"
      )
    )

    create(
      constraint(:provider_credentials, :provider_credentials_ciphertext,
        check: "octet_length(encrypted_payload) > 29"
      )
    )
  end
end
