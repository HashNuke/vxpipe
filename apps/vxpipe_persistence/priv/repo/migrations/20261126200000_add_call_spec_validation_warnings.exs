defmodule Vxpipe.Persistence.Repo.Migrations.AddCallSpecValidationWarnings do
  use Ecto.Migration

  def change do
    alter table(:call_spec_revisions) do
      add(:validation_warnings, {:array, :map}, null: false, default: [])
    end
  end
end
