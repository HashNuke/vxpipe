defmodule Vxpipe.Persistence.Repo.Migrations.CreateOauthCredentials do
  use Ecto.Migration

  def change do
    create table(:oauth_clients, primary_key: false) do
      add(:public_id, :uuid, primary_key: true)
      add(:metadata, :map, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create table(:oauth_grants, primary_key: false) do
      add(:public_id, :uuid, primary_key: true)

      add(
        :client_id,
        references(:oauth_clients, column: :public_id, type: :uuid, on_delete: :delete_all),
        null: false
      )

      add(:user_id, references(:users, on_delete: :delete_all), null: false)
      add(:authorization_version, :bigint, null: false)
      add(:role_public_id, :uuid, null: false)
      add(:role_revision, :integer, null: false)
      add(:authority, :map, null: false)
      add(:resource, :text, null: false)
      add(:expires_at, :utc_datetime_usec, null: false)
      add(:revoked_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec)
    end

    create(index(:oauth_grants, [:user_id, :expires_at]))
    create(index(:oauth_grants, [:client_id]))
    create(index(:oauth_grants, [:expires_at]))

    create table(:oauth_codes, primary_key: false) do
      add(:public_id, :uuid, primary_key: true)

      add(
        :grant_id,
        references(:oauth_grants, column: :public_id, type: :uuid, on_delete: :delete_all),
        null: false
      )

      add(:digest, :binary, null: false)
      add(:redirect_uri, :text, null: false)
      add(:challenge_hash, :string, null: false)
      add(:expires_at, :utc_datetime_usec, null: false)
      add(:consumed_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:oauth_codes, [:digest]))
    create(unique_index(:oauth_codes, [:grant_id]))

    create table(:oauth_tokens, primary_key: false) do
      add(:public_id, :uuid, primary_key: true)

      add(
        :grant_id,
        references(:oauth_grants, column: :public_id, type: :uuid, on_delete: :delete_all),
        null: false
      )

      add(:access_digest, :binary, null: false)
      add(:refresh_digest, :binary, null: false)
      add(:access_expires_at, :utc_datetime_usec, null: false)
      add(:refresh_consumed_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:oauth_tokens, [:access_digest]))
    create(unique_index(:oauth_tokens, [:refresh_digest]))
    create(index(:oauth_tokens, [:grant_id]))
  end
end
