defmodule Vxpipe.Persistence.OAuth.Code do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:public_id, :binary_id, autogenerate: true}
  schema "oauth_codes" do
    field(:grant_id, :binary_id)
    field(:digest, :binary, redact: true)
    field(:redirect_uri, :string)
    field(:challenge_hash, :string, redact: true)
    field(:expires_at, :utc_datetime_usec)
    field(:consumed_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
