defmodule Vxpipe.Gateway.Telephony.WebhookService do
  @moduledoc false

  alias Vxpipe.Gateway.Telephony.{ConfiguredService, ServiceRegistry}
  alias Vxpipe.Gateway.Telephony.Telnyx.ClientState
  alias Vxpipe.Gateway.Telephony.Twilio.Form

  # Identifiers locate a candidate only. The caller must verify the original body and dispatch
  # to the returned owner without looking up a replacement after authentication.
  def select(registry, provider, ingress, body, local_id \\ nil)
  def select(%{enabled?: false}, _provider, _ingress, _body, _local_id), do: {:error, :disabled}

  def select(registry, provider, ingress, body, local_id) do
    {account, provider_leg, body_leg} = identifiers(provider, body)
    local_id = bounded(local_id) || body_leg

    case owner(provider, ingress, account, provider_leg, local_id) do
      {:ok, %ConfiguredService{} = service, owner} ->
        identity = service.identity

        if identity.provider == provider and identity.ingress_key == ingress and
             identity.provider_connection_id == account,
           do: {:ok, service, owner},
           else: {:error, :service_not_found}

      :not_found ->
        with {:ok, service} <- ServiceRegistry.fetch(registry, ingress) do
          if service.identity.provider == provider,
            do: {:ok, service, nil},
            else: {:error, :wrong_provider}
        end
    end
  rescue
    _exception -> {:error, :service_not_found}
  end

  defp owner(provider, ingress, account, provider_leg, local_id) do
    case lookup({:outgoing, local_id}) do
      :not_found -> lookup({:ingress, provider, ingress, account, provider_leg})
      found -> found
    end
  end

  defp lookup(key) do
    case Registry.lookup(Vxpipe.Gateway.Telephony.LegRegistry, key) do
      [{owner, {kind, %ConfiguredService{} = service}}] -> {:ok, service, {kind, owner}}
      [] -> :not_found
    end
  end

  defp identifiers(:twilio, body) do
    case Form.decode(body) do
      {:ok, parameters} ->
        {bounded(Map.get(parameters, "AccountSid")), bounded(Map.get(parameters, "CallSid")), nil}

      _invalid ->
        {nil, nil, nil}
    end
  end

  defp identifiers(:telnyx, body) do
    case JSON.decode(body) do
      {:ok, %{"data" => %{"payload" => payload}}} when is_map(payload) ->
        local_id =
          case ClientState.decode(Map.get(payload, "client_state")) do
            {:ok, local_id} -> local_id
            _invalid -> nil
          end

        {bounded(Map.get(payload, "connection_id")), bounded(Map.get(payload, "call_leg_id")),
         local_id}

      _invalid ->
        {nil, nil, nil}
    end
  end

  defp bounded(value) when is_binary(value) and byte_size(value) in 1..128, do: value
  defp bounded(_invalid), do: nil
end
