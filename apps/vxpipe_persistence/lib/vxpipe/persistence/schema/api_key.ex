defmodule Vxpipe.Persistence.Schema.ApiKey do
  use Ecto.Schema
  import Ecto.Changeset

  alias Vxpipe.Persistence.Schema.Tenant

  schema "api_keys" do
    field :public_id, Ecto.UUID
    field :name, :string
    field :scopes, {:array, :string}
    field :digest, :binary
    field :revoked_at, :utc_datetime_usec

    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(api_key, attributes) do
    api_key
    |> cast(attributes, [:public_id, :name, :scopes, :digest, :revoked_at, :tenant_id])
    |> validate_required([:public_id, :name, :scopes, :digest, :tenant_id])
    |> validate_length(:name, min: 1, max: 256)
    |> validate_change(:digest, fn :digest, digest ->
      if byte_size(digest) == 32, do: [], else: [digest: "must contain 32 bytes"]
    end)
    |> validate_subset(:scopes, ["admin", "calls"])
    |> validate_length(:scopes, min: 1)
    |> foreign_key_constraint(:tenant_id)
    |> unique_constraint(:public_id)
    |> unique_constraint(:digest, name: :api_keys_tenant_id_digest_index)
  end
end
