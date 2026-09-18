defmodule Vxpipe.Persistence.Repo.Migrations.AddProviderCredentialSecretHints do
  use Ecto.Migration

  def change do
    alter table(:provider_credentials) do
      add(:secret_hints, :map, null: false, default: %{})
    end
  end
end
