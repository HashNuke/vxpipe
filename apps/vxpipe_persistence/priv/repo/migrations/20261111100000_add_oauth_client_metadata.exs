defmodule Vxpipe.Persistence.Repo.Migrations.AddOauthClientMetadata do
  use Ecto.Migration

  def change do
    alter table(:oauth_clients) do
      add(:metadata_url, :text)
      add(:metadata_expires_at, :utc_datetime_usec)
    end

    create(unique_index(:oauth_clients, [:metadata_url]))

    alter table(:oauth_authorization_requests) do
      add(:client_metadata_digest, :binary)
    end
  end
end
