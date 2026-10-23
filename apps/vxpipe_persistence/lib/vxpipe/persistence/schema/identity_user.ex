defmodule Vxpipe.Persistence.Schema.IdentityUser do
  use Ecto.Schema
  import Ecto.Changeset

  alias Vxpipe.Persistence.Schema.IdentityRole

  schema "users" do
    field(:public_id, Ecto.UUID, autogenerate: true)
    field(:email, :string)
    field(:normalized_email, :string)
    field(:password_hash, :string, redact: true)
    field(:disabled_at, :utc_datetime_usec)
    field(:authorization_version, :integer, default: 1)

    belongs_to(:role, IdentityRole)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(user, attributes) do
    user
    |> cast(attributes, [
      :public_id,
      :email,
      :normalized_email,
      :password_hash,
      :role_id,
      :disabled_at,
      :authorization_version
    ])
    |> validate_required([:public_id, :email, :normalized_email, :password_hash, :role_id])
    |> validate_length(:email, min: 3, max: 320)
    |> validate_length(:normalized_email, min: 3, max: 320)
    |> validate_number(:authorization_version, greater_than: 0)
    |> unique_constraint(:public_id)
    |> unique_constraint(:normalized_email)
    |> foreign_key_constraint(:role_id)
  end
end
