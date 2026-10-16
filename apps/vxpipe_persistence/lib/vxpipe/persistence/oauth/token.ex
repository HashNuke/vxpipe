defmodule Vxpipe.Persistence.OAuth.Token do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:public_id, :binary_id, autogenerate: true}
  schema "oauth_tokens" do
    field(:grant_id, :binary_id)
    field(:access_digest, :binary, redact: true)
    field(:refresh_digest, :binary, redact: true)
    field(:access_expires_at, :utc_datetime_usec)
    field(:refresh_consumed_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
