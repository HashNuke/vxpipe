defmodule Vxpipe.Providers.Twilio.MediaControlDecoder do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Providers.Twilio.{Identifier, MediaFields}

  @spec connected(map()) :: :ignore | {:error, :invalid_twilio_media_message}
  def connected(%{"protocol" => "Call", "version" => version}) when is_binary(version),
    do: :ignore

  def connected(_message), do: invalid()

  @spec dtmf(keyword(), map()) :: {:ok, Event.t()} | {:error, :invalid_twilio_media_message}
  def dtmf(options, %{"dtmf" => dtmf} = message) when is_map(dtmf) do
    with {:ok, stream_id} <- expected_stream(options, message),
         {:ok, provider_sequence} <- MediaFields.integer(message, "sequenceNumber"),
         "inbound_track" <- Map.get(dtmf, "track"),
         {:ok, digit} <- MediaFields.string(dtmf, "digit"),
         {:ok, occurred_at} <- MediaFields.observed_at(options),
         {:ok, identity} <- MediaFields.identity(options) do
      event =
        struct!(
          Event,
          Map.merge(identity, %{
            kind: :dtmf,
            provider_event_id: "#{stream_id}:#{provider_sequence}",
            occurred_at: occurred_at,
            stream_id: stream_id,
            digit: digit
          })
        )

      if Event.valid?(event), do: {:ok, event}, else: invalid()
    else
      _invalid -> invalid()
    end
  end

  def dtmf(_options, _message), do: invalid()

  @spec mark(keyword(), map()) ::
          {:ok, {:playback_mark, String.t(), String.t()}}
          | {:error, :invalid_twilio_media_message}
  def mark(options, %{"mark" => mark} = message) when is_map(mark) do
    with {:ok, stream_id} <- expected_stream(options, message),
         {:ok, _sequence} <- MediaFields.integer(message, "sequenceNumber"),
         {:ok, name} <- MediaFields.string(mark, "name"),
         true <- byte_size(name) <= 128 do
      {:ok, {:playback_mark, stream_id, name}}
    else
      _invalid -> invalid()
    end
  end

  def mark(_options, _message), do: invalid()

  @spec stop(keyword(), map()) :: :ignore | {:error, :invalid_twilio_media_message}
  def stop(options, %{"stop" => stop} = message) when is_map(stop) do
    with {:ok, _stream_id} <- expected_stream(options, message),
         {:ok, _sequence} <- MediaFields.integer(message, "sequenceNumber"),
         {:ok, account_sid} <- MediaFields.string(stop, "accountSid"),
         :ok <- MediaFields.required_expected(options, :provider_connection_id, account_sid),
         {:ok, call_sid} <- MediaFields.string(stop, "callSid"),
         :ok <- MediaFields.required_expected(options, :provider_call_control_id, call_sid) do
      :ignore
    else
      _invalid -> invalid()
    end
  end

  def stop(_options, _message), do: invalid()

  defp expected_stream(options, message) do
    with {:ok, stream_id} <- MediaFields.string(message, "streamSid"),
         true <- Identifier.stream_sid?(stream_id),
         :ok <- MediaFields.required_expected(options, :stream_id, stream_id) do
      {:ok, stream_id}
    else
      _invalid -> :error
    end
  end

  defp invalid, do: {:error, :invalid_twilio_media_message}
end
