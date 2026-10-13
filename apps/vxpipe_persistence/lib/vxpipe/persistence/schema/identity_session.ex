defmodule Vxpipe.Persistence.Schema.IdentitySession do
  use Ecto.Schema
  import Ecto.Changeset

  alias Vxpipe.Persistence.Schema.IdentityUser

  schema "user_sessions" do
    field(:public_id, Ecto.UUID, autogenerate: true)
    field(:token_digest, :string, redact: true)
    field(:issued_at, :utc_datetime_usec)
    field(:expires_at, :utc_datetime_usec)
    field(:revoked_at, :utc_datetime_usec)

    belongs_to(:user, IdentityUser)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(session, attributes) do
    session
    |> cast(attributes, [
      :public_id,
      :user_id,
      :token_digest,
      :issued_at,
      :expires_at,
      :revoked_at
    ])
    |> validate_required([:public_id, :user_id, :token_digest, :issued_at, :expires_at])
    |> validate_length(:token_digest, is: 64)
    |> unique_constraint(:public_id)
    |> unique_constraint(:token_digest)
    |> foreign_key_constraint(:user_id)
    |> check_constraint(:expires_at, name: :user_sessions_expiry)
  end
end
