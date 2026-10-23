defmodule Vxpipe.Persistence.Repo.Migrations.IndexTenantApiKeyDigests do
  use Ecto.Migration

  def change do
    create(index(:api_keys, [:digest]))
  end
end
