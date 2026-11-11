defmodule Vxpipe.Persistence.OAuth.Client do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:public_id, :binary_id, autogenerate: true}
  schema "oauth_clients" do
    field(:metadata, :map)
    field(:metadata_url, :string)
    field(:metadata_expires_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec)
  end
end
