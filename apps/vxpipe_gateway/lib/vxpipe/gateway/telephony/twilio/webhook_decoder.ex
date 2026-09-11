defmodule Vxpipe.Gateway.Telephony.Twilio.WebhookDecoder do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.{Event, Webhook}

  alias Vxpipe.Gateway.Telephony.Twilio.{
    CallbackEventDecoder,
    Form,
    IncomingEventDecoder
  }

  @spec decode(keyword(), Webhook.t()) ::
          {:ok, Event.t()} | :ignore | {:error, :invalid_twilio_webhook}
  def decode(options, %Webhook{} = webhook) do
    with {:ok, parameters} <- Form.decode(webhook.body) do
      decode_parameters(options, webhook, parameters)
    else
      _invalid -> invalid()
    end
  end

  defp decode_parameters(options, %Webhook{} = webhook, parameters) do
    case Map.fetch(webhook.route_parameters, "leg_id") do
      {:ok, leg_id} ->
        CallbackEventDecoder.decode(options, webhook.received_at, leg_id, parameters)

      :error ->
        IncomingEventDecoder.decode(options, webhook.received_at, parameters)
    end
  end

  defp invalid, do: {:error, :invalid_twilio_webhook}
end
