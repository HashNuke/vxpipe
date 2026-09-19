defmodule Vxpipe.Persistence.Schema.OperatorApiKey do
  use Ecto.Schema
  import Ecto.Changeset

  schema "operator_api_keys" do
    field(:public_id, Ecto.UUID)
    field(:digest, :binary, redact: true)
    field(:revoked_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(record, attributes) do
    record
    |> cast(attributes, [:public_id, :digest, :revoked_at, :inserted_at])
    |> validate_required([:public_id, :digest, :inserted_at])
    |> validate_change(:digest, fn :digest, digest ->
      if byte_size(digest) == 32, do: [], else: [digest: "must contain 32 bytes"]
    end)
    |> unique_constraint(:public_id)
    |> unique_constraint(:digest)
    |> unique_constraint(:revoked_at, name: :operator_api_keys_one_active)
  end
end
