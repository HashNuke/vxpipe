defmodule Vxpipe.Persistence.OAuth.Client do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:public_id, :binary_id, autogenerate: true}
  schema "oauth_clients" do
    field(:metadata, :map)
    timestamps(type: :utc_datetime_usec)
  end
end
