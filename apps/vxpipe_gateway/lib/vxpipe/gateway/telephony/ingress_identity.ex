defmodule Vxpipe.Gateway.Telephony.IngressIdentity do
  @moduledoc "Safe configured-service identity passed to telephony ingress handlers."

  @enforce_keys [:service_id, :ingress_key, :scope, :provider, :provider_connection_id]
  defstruct @enforce_keys

  @type scope :: :application | {:tenant, String.t()}

  @type t :: %__MODULE__{
          service_id: String.t(),
          ingress_key: String.t(),
          scope: scope(),
          provider: :telnyx | :twilio,
          provider_connection_id: String.t()
        }
end
