defmodule Vxpipe.CallEngine.Telephony.ServiceReference do
  @moduledoc "Non-secret tenant carrier identity pinned by the host before call preparation."

  @enforce_keys [
    :tenant_id,
    :service_id,
    :name,
    :provider,
    :provider_connection_id,
    :credential_id
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          service_id: String.t(),
          name: String.t(),
          provider: String.t(),
          provider_connection_id: String.t(),
          credential_id: String.t()
        }
end
