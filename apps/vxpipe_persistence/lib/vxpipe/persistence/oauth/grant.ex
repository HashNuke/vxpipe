defmodule Vxpipe.Persistence.OAuth.Grant do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:public_id, :binary_id, autogenerate: true}
  schema "oauth_grants" do
    field(:client_id, :binary_id)
    field(:user_id, :integer)
    field(:authorization_version, :integer)
    field(:role_public_id, :binary_id)
    field(:role_revision, :integer)
    field(:authority, :map)
    field(:resource, :string)
    field(:expires_at, :utc_datetime_usec)
    field(:revoked_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec)
  end
end
