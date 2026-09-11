defmodule Vxpipe.Gateway.Telephony.Twilio.Adapter do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.Telephony.Adapter

  alias Vxpipe.CallEngine.Telephony.{Answer, Dial, EndLeg, SendMedia, Submission, Webhook}
  alias Vxpipe.Gateway.Telephony.Twilio.{WebhookDecoder, WebhookVerifier}

  @impl true
  def dial(_options, %Dial{}), do: {:error, :twilio_command_not_supported}

  @impl true
  def answer(options, %Answer{} = request) do
    with {:ok, _account_sid} <- required_option(options, :account_sid),
         {:ok, _auth_token} <- required_option(options, :auth_token),
         {:ok, call_sid} <- present(request.leg.provider_call_control_id),
         :ok <- secure_media_url(request.media_url) do
      {:ok,
       %Submission{
         status: :accepted,
         provider_call_control_id: call_sid,
         provider_call_leg_id: call_sid,
         provider_call_session_id: nil
       }}
    else
      _invalid -> {:error, :invalid_twilio_answer}
    end
  end

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

  defp required_option(options, key), do: options |> Keyword.get(key) |> present()

  defp present(value) when is_binary(value) and value != "", do: {:ok, value}
  defp present(_missing), do: :error

  defp secure_media_url(url) do
    case URI.parse(url) do
      %URI{scheme: "wss", host: host} when is_binary(host) and host != "" -> :ok
      _invalid -> :error
    end
  end
end
