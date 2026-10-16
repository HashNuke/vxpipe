defmodule Vxpipe.Persistence.OAuth.AuthorizationRequest do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:digest, :binary, autogenerate: false}
  schema "oauth_authorization_requests" do
    field(:binding_digest, :binary)
    field(:client_id, :binary_id)
    field(:params, :map)
    field(:resource, :string)
    field(:session_public_id, :binary_id)
    field(:snapshot, :map)
    field(:expires_at, :utc_datetime_usec)
  end
end
