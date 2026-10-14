defmodule Vxpipe.Persistence.Repo.Migrations.RemoveRoleDescriptions do
  use Ecto.Migration

  def change do
    alter table(:roles) do
      remove(:description, :text)
    end
  end
end
