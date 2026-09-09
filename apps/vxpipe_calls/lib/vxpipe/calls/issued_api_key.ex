defmodule Vxpipe.Calls.IssuedApiKey do
  @moduledoc "An API key returned once at issuance. Its inspection is always redacted."

  @enforce_keys [:id, :tenant_key, :name, :scopes, :secret, :inserted_at]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: String.t(),
          tenant_key: String.t(),
          name: String.t(),
          scopes: MapSet.t(:admin | :calls),
          secret: String.t(),
          inserted_at: DateTime.t()
        }
end
