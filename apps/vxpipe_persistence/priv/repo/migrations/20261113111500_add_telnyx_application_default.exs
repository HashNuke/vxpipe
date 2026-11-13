defmodule Vxpipe.Persistence.Repo.Migrations.AddTelnyxApplicationDefault do
  use Ecto.Migration

  def change do
    create table(:telnyx_settings, primary_key: false) do
      add(:id, :integer, primary_key: true)
      add(:application_id, :string)
    end

    create(constraint(:telnyx_settings, :telnyx_settings_singleton, check: "id = 1"))
    execute("INSERT INTO telnyx_settings (id) VALUES (1)", "DELETE FROM telnyx_settings")

    alter table(:telephony_services) do
      modify(:provider_connection_id, :string, null: true, from: {:string, null: false})
    end

    create(
      constraint(:telephony_services, :telephony_services_application_required,
        check:
          "provider_connection_id IS NOT NULL OR (provider = 'telnyx' AND credential_name = 'telnyx')"
      )
    )
  end
end
