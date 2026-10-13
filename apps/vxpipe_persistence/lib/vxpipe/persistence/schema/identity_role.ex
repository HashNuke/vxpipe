defmodule Vxpipe.Persistence.Schema.IdentityRole do
  use Ecto.Schema
  import Ecto.Changeset

  schema "roles" do
    field(:public_id, Ecto.UUID, autogenerate: true)
    field(:slug, :string)
    field(:name, :string)
    field(:description, :string)
    field(:kind, :string)
    field(:revision, :integer, default: 1)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(role, attributes) do
    role
    |> cast(attributes, [:public_id, :slug, :name, :description, :kind, :revision])
    |> validate_required([:public_id, :slug, :name])
    |> validate_format(:slug, ~r/\A[a-z0-9][a-z0-9_-]{1,62}\z/)
    |> validate_inclusion(:kind, ["superadmin", "admin"])
    |> validate_number(:revision, greater_than: 0)
    |> unique_constraint(:public_id)
    |> unique_constraint(:slug)
  end

  def ordinary_changeset(role, attributes) do
    role
    |> cast(attributes, [:public_id, :slug, :name, :description, :revision])
    |> validate_required([:public_id, :slug, :name])
    |> validate_format(:slug, ~r/\A[a-z0-9][a-z0-9_-]{1,62}\z/)
    |> validate_number(:revision, greater_than: 0)
    |> unique_constraint(:public_id)
    |> unique_constraint(:slug)
  end
end
