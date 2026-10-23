defmodule Vxpipe.Persistence.Repo.Migrations.CreateOauthAuthorizationRequests do
  use Ecto.Migration

  def change do
    create table(:oauth_authorization_requests, primary_key: false) do
      add(:digest, :binary, primary_key: true)
      add(:binding_digest, :binary, null: false)

      add(
        :client_id,
        references(:oauth_clients, column: :public_id, type: :uuid, on_delete: :delete_all),
        null: false
      )

      add(:params, :map, null: false)
      add(:resource, :text, null: false)
      add(:session_public_id, :uuid)
      add(:snapshot, :map)
      add(:expires_at, :utc_datetime_usec, null: false)
    end

    create(index(:oauth_authorization_requests, [:expires_at]))
    create(index(:oauth_authorization_requests, [:binding_digest]))
    create(index(:oauth_authorization_requests, [:client_id]))
  end
end
