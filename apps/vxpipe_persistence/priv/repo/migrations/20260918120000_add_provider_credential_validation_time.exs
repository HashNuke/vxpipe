defmodule Vxpipe.Persistence.Repo.Migrations.AddProviderCredentialValidationTime do
  use Ecto.Migration

  def change do
    alter table(:provider_credentials) do
      add(:last_validated_at, :utc_datetime_usec)
    end
  end
end
