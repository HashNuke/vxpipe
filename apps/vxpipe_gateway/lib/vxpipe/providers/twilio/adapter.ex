defmodule Vxpipe.Providers.Twilio.Adapter do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.Telephony.Adapter

  alias Vxpipe.CallEngine.Telephony.{Answer, Dial, EndLeg, SendMedia, Webhook}

  alias Vxpipe.Providers.Twilio.{
    DialCommand,
    EndCallCommand,
    IncomingAnswer,
    MediaDecoder,
    WebhookDecoder,
    WebhookVerifier
  }

  @impl true
  def dial(options, %Dial{} = request), do: DialCommand.submit(options, request)

  @impl true
  def answer(options, %Answer{} = request), do: IncomingAnswer.prepare(options, request)

  @impl true
  def send_media(_options, %SendMedia{}), do: {:error, :twilio_media_not_attached}

  @impl true
  def end_leg(options, %EndLeg{} = request), do: EndCallCommand.submit(options, request)

  @impl true
  def verify_webhook(options, %Webhook{} = webhook) do
    WebhookVerifier.verify(webhook, options)
  end

  @impl true
  def decode_webhook(options, %Webhook{} = webhook) do
    WebhookDecoder.decode(options, webhook)
  end

  @impl true
  def decode_media_message(options, message) do
    case MediaDecoder.decode(options, message) do
      {:ok, {:playback_mark, _, _}} -> :ignore
      result -> result
    end
  end
end
