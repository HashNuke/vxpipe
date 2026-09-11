defmodule Vxpipe.Persistence.Repo.Migrations.CreateTelephonyRoutes do
  use Ecto.Migration

  def change do
    create table(:telephony_routes) do
      add :tenant_id, references(:tenants, on_delete: :delete_all), null: false

      add :definition_revision_id,
          references(:definition_revisions, on_delete: :delete_all),
          null: false

      add :participant_ref, :string, null: false
      add :service, :string, null: false
      add :number, :string, null: false
      add :published_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:telephony_routes, [:definition_revision_id, :participant_ref])

    create index(:telephony_routes, [:service, :number, :published_at])
    create index(:telephony_routes, [:tenant_id, :service, :number, :published_at])
  end
end
