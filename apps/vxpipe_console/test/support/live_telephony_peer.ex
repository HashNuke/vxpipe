defmodule Vxpipe.Console.Test.LiveTelephonyPeer do
  @moduledoc false

  alias Vxpipe.Console.Test.ConfiguredTelephonyFixture
  alias Vxpipe.Gateway.Telephony.MediaBinding

  @derive {Inspect, only: [:call_id]}
  @enforce_keys [:call_id, :control_id, :api_key]
  defstruct @enforce_keys

  def new(
        %ConfiguredTelephonyFixture{} = fixture,
        call,
        %MediaBinding{provider: :telnyx} = binding
      ) do
    human = Map.fetch!(call.plan.participants, call.plan.entry_caller)
    service = human.telephony_service

    if MediaBinding.valid?(binding) and binding.tenant_id == fixture.tenant.key and
         binding.call_id == call.id and binding.room_id == call.room_id and
         binding.incarnation_id == call.incarnation_id and
         binding.participant_id == human.participant_id and
         binding.service_id == service.name and service.provider == "telnyx" and
         binding.provider_connection_id == service.provider_connection_id and
         binding.provider_connection_id == fixture.settings.application_id do
      {:ok,
       %__MODULE__{
         call_id: call.id,
         control_id: binding.provider_call_control_id,
         api_key: fixture.settings.telnyx_key
       }}
    else
      {:error, :unbound_peer}
    end
  end

  def new(%ConfiguredTelephonyFixture{}, _call, %MediaBinding{}), do: {:error, :unbound_peer}

  def press_one(%__MODULE__{} = peer, options \\ []),
    do: command(peer, "send_dtmf", %{digits: "1", duration_millis: 250}, options)

  def hangup(%__MODULE__{} = peer, options \\ []), do: command(peer, "hangup", %{}, options)

  defp command(peer, action, payload, options) do
    control_id = URI.encode(peer.control_id, &URI.char_unreserved?/1)
    command_id = "vxp-peer-" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)

    options
    |> Keyword.merge(
      method: :post,
      url: "https://api.telnyx.com/v2/calls/#{control_id}/actions/#{action}",
      auth: {:bearer, peer.api_key},
      json: Map.put(payload, :command_id, command_id),
      retry: false,
      redirect: false,
      receive_timeout: 5_000
    )
    |> Req.request()
    |> result()
  end

  defp result({:ok, %Req.Response{status: 200, body: %{"data" => %{"result" => "ok"}}}}), do: :ok

  defp result({:ok, %Req.Response{status: status}}),
    do: {:error, {:peer_command_rejected, status}}

  defp result({:error, _reason}), do: {:error, :peer_command_unavailable}
end
