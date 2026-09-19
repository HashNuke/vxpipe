defmodule Vxpipe.CallEngine.ProviderCredential do
  @moduledoc "Private authentication snapshot for one capability activation. Never serialize in a plan."

  @derive {Inspect, only: [:id, :tenant_id, :provider, :name, :version, :auth_kind]}
  @enforce_keys [:id, :tenant_id, :provider, :name, :version, :auth_kind, :payload]
  defstruct @enforce_keys ++ [owner: nil]

  @type t :: %__MODULE__{
          id: String.t(),
          tenant_id: String.t(),
          owner: :platform | {:tenant, String.t()} | nil,
          provider: String.t(),
          name: String.t(),
          version: pos_integer(),
          auth_kind: String.t(),
          payload: map()
        }

  def binding_identity(%__MODULE__{owner: :platform, id: id}),
    do: %{"id" => id, "scope" => "platform", "tenant_key" => nil}

  def binding_identity(%__MODULE__{owner: {:tenant, key}, id: id}),
    do: %{"id" => id, "scope" => "tenant", "tenant_key" => key}

  def binding_identity(%__MODULE__{owner: nil, tenant_id: key, id: id}),
    do: %{"id" => id, "scope" => "tenant", "tenant_key" => key}
end
