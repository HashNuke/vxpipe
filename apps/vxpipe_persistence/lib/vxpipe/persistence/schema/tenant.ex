defmodule Vxpipe.Persistence.Schema.Tenant do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tenants" do
    field :key, :string
    field :name, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(tenant, attributes) do
    tenant
    |> cast(attributes, [:key, :name])
    |> validate_required([:key, :name])
    |> validate_length(:key, is: 16)
    |> validate_format(:key, ~r/\A[A-Za-z0-9_-]+\z/)
    |> validate_length(:name, min: 1, max: 256)
    |> unique_constraint(:key)
  end
end
