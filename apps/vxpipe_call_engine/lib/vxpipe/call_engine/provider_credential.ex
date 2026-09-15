defmodule Vxpipe.CallEngine.ProviderCredential do
  @moduledoc "Private authentication snapshot for one capability activation. Never serialize in a plan."

  @derive {Inspect, only: [:id, :tenant_id, :provider, :name, :version, :auth_kind]}
  @enforce_keys [:id, :tenant_id, :provider, :name, :version, :auth_kind, :payload]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: String.t(),
          tenant_id: String.t(),
          provider: String.t(),
          name: String.t(),
          version: pos_integer(),
          auth_kind: String.t(),
          payload: map()
        }
end
