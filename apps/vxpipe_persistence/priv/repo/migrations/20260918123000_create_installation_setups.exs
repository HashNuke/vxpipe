defmodule Vxpipe.Persistence.Repo.Migrations.CreateInstallationSetups do
  use Ecto.Migration

  def change do
    create table(:installation_setups, primary_key: false) do
      add(:key, :string, primary_key: true)
      add(:demo_tenant_id, references(:tenants, on_delete: :restrict), null: false)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:installation_setups, [:demo_tenant_id]))
  end
end
