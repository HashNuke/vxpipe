defmodule Vxpipe.Gateway.Telephony.IngressRegistration do
  @moduledoc false

  alias Vxpipe.Gateway.Telephony.IngressIdentity

  @registry Vxpipe.Gateway.Telephony.LegRegistry

  def register(service, provider_leg, kind) do
    legacy = IngressIdentity.ingress_key(service.identity, provider_leg)

    keys =
      case service.identity do
        %{
          provider: :telnyx,
          service_reference: %{credential_name: "telnyx", credential_owner: owner}
        } ->
          [legacy, {:scoped_telnyx, owner, service.identity.provider_connection_id, provider_leg}]

        _legacy ->
          [legacy]
      end

    Enum.reduce_while(keys, {:ok, []}, fn key, {:ok, registered} ->
      case Registry.register(@registry, key, {kind, service}) do
        {:ok, _owner} ->
          {:cont, {:ok, [key | registered]}}

        {:error, _reason} ->
          Enum.each(registered, &Registry.unregister(@registry, &1))
          {:halt, {:error, :telephony_leg_already_owned}}
      end
    end)
  end
end
