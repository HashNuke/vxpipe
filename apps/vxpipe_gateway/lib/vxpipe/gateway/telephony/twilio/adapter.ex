defmodule Vxpipe.Gateway.Telephony.Twilio.Adapter do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.Telephony.Adapter

  alias Vxpipe.CallEngine.Telephony.{Answer, Dial, EndLeg, SendMedia, Webhook}
  alias Vxpipe.Gateway.Telephony.Twilio.{WebhookDecoder, WebhookVerifier}

  @impl true
  def dial(_options, %Dial{}), do: {:error, :twilio_command_not_supported}

  @impl true
  def answer(_options, %Answer{}), do: {:error, :twilio_command_not_supported}

  @impl true
  def send_media(_options, %SendMedia{}), do: {:error, :twilio_media_not_attached}

  @impl true
  def end_leg(_options, %EndLeg{}), do: {:error, :twilio_command_not_supported}

  @impl true
  def verify_webhook(options, %Webhook{} = webhook) do
    WebhookVerifier.verify(webhook, options)
  end

  @impl true
  def decode_webhook(options, %Webhook{} = webhook) do
    WebhookDecoder.decode(options, webhook)
  end

  @impl true
  def decode_media_message(_options, _message),
    do: {:error, :invalid_twilio_media_message}
end
