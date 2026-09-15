defmodule Vxpipe.Gateway.Telephony.IngressIdentity do
  @moduledoc "Safe configured-service identity passed to telephony ingress handlers."

  @enforce_keys [:service_id, :ingress_key, :scope, :provider, :provider_connection_id]
  defstruct @enforce_keys ++ [service_reference: nil]

  @type scope :: {:tenant, String.t()}

  @type t :: %__MODULE__{
          service_id: String.t(),
          ingress_key: String.t(),
          scope: scope(),
          provider: :telnyx | :twilio,
          provider_connection_id: String.t(),
          service_reference: Vxpipe.CallEngine.Telephony.ServiceReference.t() | nil
        }

  def leg_key(%__MODULE__{} = identity, provider_leg_id) do
    {identity.scope, identity.service_reference, identity.provider, provider_leg_id}
  end

  def ingress_key(%__MODULE__{} = identity, provider_leg_id) do
    {:ingress, identity.provider, identity.ingress_key, identity.provider_connection_id,
     provider_leg_id}
  end
end
