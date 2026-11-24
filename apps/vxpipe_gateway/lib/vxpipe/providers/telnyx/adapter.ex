defmodule Vxpipe.Providers.Telnyx.Adapter do
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

  alias Vxpipe.Providers.Telnyx.{
    ClientState,
    MediaDecoder,
    MediaSettings,
    VoiceClient,
    WebhookDecoder,
    WebhookVerifier
  }

  @doc "Lists existing account voice numbers through the provider's inventory adapter."
  def list_phone_numbers(connection, credentials, search, page, options \\ []) do
    Vxpipe.Providers.Telnyx.PhoneNumberCatalog.list(
      connection,
      credentials,
      search,
      page,
      options
    )
  end

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
  def dial_recovery_peer(options, request) do
    with {:ok, connection} <- required_option(options, :provider_connection_id) do
      payload = %{
        "connection_id" => connection,
        "from" => request.from,
        "to" => request.to,
        "link_to" => request.caller,
        "bridge_on_answer" => true,
        "prevent_double_bridge" => true,
        "retry_on_timeout" => false,
        "timeout_secs" => request.timeout_secs,
        "webhook_url" => request.callback_url,
        "webhook_url_method" => "POST",
        "command_id" => request.id,
        "client_state" => client_state(request.id)
      }

      VoiceClient.dial(options, payload) |> submission(nil)
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
  def play_recovery_prompt(options, control_id, command_id),
    do: play_recovery_prompt(options, control_id, command_id, :callback)

  @impl true
  def play_recovery_prompt(options, control_id, command_id, kind)
      when kind in [:callback, :transfer] do
    file = Application.app_dir(:vxpipe_gateway, "priv/telephony/#{kind}.wav")

    with {:ok, audio} <- File.read(file) do
      payload = %{
        "command_id" => command_id,
        "client_state" => Base.encode64(command_id),
        "audio_type" => "wav",
        "target_legs" => "self",
        "playback_content" => Base.encode64(audio)
      }

      VoiceClient.start_playback(options, control_id, payload) |> submission(control_id)
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
  def decode_media_message(options, message) do
    case MediaDecoder.decode(options, message) do
      {:ok, {:playback_mark, _, _}} -> :ignore
      {:ok, {:stream_stopped, _}} -> :ignore
      result -> result
    end
  end

  defp submission({:accepted, body}, nil) do
    with %{} = data <- Map.get(body, "data"),
         {:ok, call_control_id} <- response_identifier(data, "call_control_id"),
         {:ok, call_leg_id} <- response_identifier(data, "call_leg_id"),
         {:ok, call_session_id} <- response_identifier(data, "call_session_id") do
      {:ok,
       %Submission{
         status: :accepted,
         provider_call_control_id: call_control_id,
         provider_call_leg_id: call_leg_id,
         provider_call_session_id: call_session_id
       }}
    else
      _missing -> {:error, :invalid_telnyx_command_response}
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

  defp response_identifier(data, key) do
    case Map.get(data, key) do
      value when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
      _missing -> :error
    end
  end

  defp client_state(leg_id), do: ClientState.encode(leg_id)

  defp put_answering_machine_detection(payload, :detect),
    do: Map.put(payload, "answering_machine_detection", "detect")

  defp put_answering_machine_detection(payload, :disabled), do: payload
end
