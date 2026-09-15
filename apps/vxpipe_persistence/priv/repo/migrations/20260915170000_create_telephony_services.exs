defmodule Vxpipe.Persistence.Repo.Migrations.CreateTelephonyServices do
  use Ecto.Migration

  def change do
    create(unique_index(:provider_credentials, [:public_id, :tenant_id, :provider]))

    create table(:telephony_services) do
      add(:public_id, :uuid, null: false)
      add(:tenant_id, references(:tenants, on_delete: :delete_all), null: false)
      add(:name, :string, null: false)
      add(:ingress_key, :string, null: false)
      add(:provider, :string, null: false)
      add(:provider_connection_id, :string, null: false)

      add(
        :credential_id,
        references(:provider_credentials,
          column: :public_id,
          type: :uuid,
          with: [tenant_id: :tenant_id, provider: :provider],
          name: :telephony_services_credential_owner_fkey
        ),
        null: false
      )

      add(:public_key, :string, null: false)
      add(:outbound_number, :string)
      add(:answering_machine_detection, :string, null: false)
      add(:media_token_ttl_ms, :integer, null: false)
      add(:webhook_tolerance_seconds, :integer, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:telephony_services, [:public_id]))
    create(unique_index(:telephony_services, [:tenant_id, :name]))
    create(unique_index(:telephony_services, [:ingress_key]))
    create(index(:telephony_services, [:credential_id, :tenant_id, :provider]))

    create(
      constraint(:telephony_services, :telephony_services_valid_timing,
        check: "media_token_ttl_ms > 0 AND webhook_tolerance_seconds >= 0"
      )
    )
  end
end
