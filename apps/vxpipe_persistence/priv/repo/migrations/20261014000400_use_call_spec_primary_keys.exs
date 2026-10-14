defmodule Vxpipe.Persistence.Repo.Migrations.UseCallSpecPrimaryKeys do
  use Ecto.Migration

  def up do
    drop(unique_index(:call_specs, [:tenant_id, :public_id]))

    alter table(:call_specs) do
      remove(:public_id)
    end
  end

  def down do
    alter table(:call_specs) do
      add(:public_id, :string)
    end

    execute("UPDATE call_specs SET public_id = id::text")

    alter table(:call_specs) do
      modify(:public_id, :string, null: false)
    end

    create(unique_index(:call_specs, [:tenant_id, :public_id]))
  end
end
