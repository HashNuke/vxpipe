defmodule Vxpipe.Persistence.Repo.Migrations.AddAccountApiKeyAuditActor do
  use Ecto.Migration

  def change do
    alter table(:user_access_events) do
      add(:actor_api_key_id, references(:api_keys, on_delete: :restrict))
    end

    create(index(:user_access_events, [:actor_api_key_id]))

    create(
      constraint(:user_access_events, :user_access_events_single_actor,
        check: "actor_user_id IS NULL OR actor_api_key_id IS NULL"
      )
    )
  end
end
