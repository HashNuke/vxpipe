defmodule Vxpipe.Persistence.Repo.Migrations.VerifyCallIncarnationBindings do
  use Ecto.Migration

  def change do
    alter table(:calls) do
      add(:incarnation_binding_verified, :boolean, null: false, default: false)
    end
  end
end
