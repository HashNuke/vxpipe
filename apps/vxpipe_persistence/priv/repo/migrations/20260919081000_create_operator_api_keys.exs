defmodule Vxpipe.Persistence.Repo.Migrations.CreateOperatorApiKeys do
  use Ecto.Migration

  def change do
    create table(:operator_api_keys) do
      add(:public_id, :uuid, null: false)
      add(:digest, :binary, null: false)
      add(:revoked_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:operator_api_keys, [:public_id]))
    create(unique_index(:operator_api_keys, [:digest]))

    create(
      unique_index(:operator_api_keys, ["(true)"],
        name: :operator_api_keys_one_active,
        where: "revoked_at IS NULL"
      )
    )

    create(
      constraint(:operator_api_keys, :operator_api_key_digest_length,
        check: "octet_length(digest) = 32"
      )
    )
  end
end
