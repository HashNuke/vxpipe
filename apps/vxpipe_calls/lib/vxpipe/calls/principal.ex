defmodule Vxpipe.Calls.Principal do
  @moduledoc "The trusted tenant principal established by API-key authentication."

  @enforce_keys [:tenant_key, :api_key_id, :scopes]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tenant_key: String.t(),
          api_key_id: String.t(),
          scopes: MapSet.t(:admin | :calls)
        }
end
