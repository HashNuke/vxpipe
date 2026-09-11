defmodule Vxpipe.Gateway.Telephony.Telnyx.Adapter do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.Telephony.Adapter

  alias Vxpipe.CallEngine.Telephony.{
    Answer,
    Dial,
    EndLeg,
    SendMedia,
    Submission,
    Webhook
  }

  alias Vxpipe.Gateway.Telephony.Telnyx.{
    MediaSettings,
    VoiceClient,
    WebhookDecoder,
    WebhookVerifier
  }

  @impl true
  def dial(options, %Dial{} = request) do
    with {:ok, _api_key} <- required_option(options, :api_key),
         {:ok, connection_id} <- required_option(options, :provider_connection_id) do
      payload =
        request.media_url
        |> MediaSettings.bidirectional()
        |> Map.merge(%{
          "connection_id" => connection_id,
          "from" => request.from,
          "to" => request.to,
          "webhook_url" => request.callback_url,
          "webhook_url_method" => "POST",
          "command_id" => request.leg_id,
          "client_state" => client_state(request.leg_id)
        })
        |> put_answering_machine_detection(request.answering_machine_detection)

      VoiceClient.dial(options, payload)
      |> submission(nil)
    end
  end

  @impl true
  def answer(options, %Answer{} = request) do
    with {:ok, _api_key} <- required_option(options, :api_key) do
      payload =
        request.media_url
        |> MediaSettings.bidirectional()
        |> Map.merge(%{
          "command_id" => "answer-#{request.leg.leg_id}",
          "client_state" => client_state(request.leg.leg_id)
        })

      VoiceClient.answer(options, request.leg.provider_call_control_id, payload)
      |> submission(request.leg.provider_call_control_id)
    end
  end

  @impl true
  def end_leg(options, %EndLeg{} = request) do
    with {:ok, _api_key} <- required_option(options, :api_key) do
      payload = %{"command_id" => "hangup-#{request.leg.leg_id}"}

      VoiceClient.hangup(options, request.leg.provider_call_control_id, payload)
      |> submission(request.leg.provider_call_control_id)
    end
  end

  @impl true
  def send_media(_options, %SendMedia{}), do: {:error, :telnyx_media_not_attached}

  @impl true
  def verify_webhook(options, %Webhook{} = webhook) do
    WebhookVerifier.verify(webhook, Keyword.get(options, :verifier_options, []))
  end

  @impl true
  def decode_webhook(_options, %Webhook{} = webhook), do: WebhookDecoder.decode(webhook)

  @impl true
  def decode_media_message(_options, _message), do: {:error, :telnyx_media_not_attached}

  defp submission({:accepted, body}, nil) do
    case get_in(body, ["data", "call_control_id"]) do
      value when is_binary(value) and byte_size(value) > 0 ->
        {:ok, %Submission{status: :accepted, provider_call_control_id: value}}

      _missing ->
        {:error, :invalid_telnyx_command_response}
    end
  end

  defp submission({:accepted, _body}, call_control_id) do
    {:ok, %Submission{status: :accepted, provider_call_control_id: call_control_id}}
  end

  defp submission({:rejected, status}, _call_control_id),
    do: {:error, {:telnyx_command_rejected, status}}

  defp submission(:unknown, call_control_id) do
    {:ok, %Submission{status: :unknown, provider_call_control_id: call_control_id}}
  end

  defp required_option(options, key) do
    case Keyword.get(options, key) do
      value when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
      _missing -> {:error, {:missing_telnyx_option, key}}
    end
  end

  defp client_state(leg_id), do: Base.encode64(JSON.encode!(%{"vxpipe_leg_id" => leg_id}))

  defp put_answering_machine_detection(payload, :detect),
    do: Map.put(payload, "answering_machine_detection", "detect")

  defp put_answering_machine_detection(payload, :disabled), do: payload
end
