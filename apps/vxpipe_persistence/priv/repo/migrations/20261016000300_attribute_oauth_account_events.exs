defmodule Vxpipe.Persistence.Repo.Migrations.AttributeOauthAccountEvents do
  use Ecto.Migration

  def change do
    alter table(:user_access_events) do
      # Historical provenance survives expiry and cleanup of credential records.
      add(:actor_oauth_grant_public_id, :uuid)
    end

    create(
      constraint(:user_access_events, :user_access_events_oauth_actor,
        check:
          "actor_oauth_grant_public_id IS NULL OR (actor_user_id IS NOT NULL AND actor_api_key_id IS NULL)"
      )
    )
  end
end
