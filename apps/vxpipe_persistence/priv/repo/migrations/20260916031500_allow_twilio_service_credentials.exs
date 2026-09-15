defmodule Vxpipe.Persistence.Repo.Migrations.AllowTwilioServiceCredentials do
  use Ecto.Migration

  def change do
    alter table(:telephony_services) do
      modify(:public_key, :string, null: true, from: {:string, null: false})
    end

    create(
      constraint(:telephony_services, :telephony_services_provider_public_key,
        check:
          "(provider = 'telnyx' AND public_key IS NOT NULL) OR (provider = 'twilio' AND public_key IS NULL)"
      )
    )
  end
end
