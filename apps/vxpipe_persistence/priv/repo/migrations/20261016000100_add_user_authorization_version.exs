defmodule Vxpipe.Persistence.Repo.Migrations.AddUserAuthorizationVersion do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:authorization_version, :bigint, null: false, default: 1)
    end

    create(
      constraint(:users, :users_authorization_version_positive,
        check: "authorization_version > 0"
      )
    )
  end
end
