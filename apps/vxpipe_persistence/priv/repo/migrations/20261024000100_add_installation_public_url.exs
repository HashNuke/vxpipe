defmodule Vxpipe.Persistence.Repo.Migrations.AddInstallationPublicUrl do
  use Ecto.Migration

  def change do
    alter table(:authentication_installations) do
      add(:public_url, :text)
      add(:public_url_revision, :bigint, null: false, default: 0)
    end

    create(
      constraint(:authentication_installations, :public_url_revision_nonnegative,
        check: "public_url_revision >= 0"
      )
    )
  end
end
