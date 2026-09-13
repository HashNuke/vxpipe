defmodule Vxpipe.Gateway.Telephony.Telnyx.MediaDecoder do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.{Event, MediaPacket}
  alias Vxpipe.Gateway.Telephony.Telnyx.ClientState

  @maximum_message_bytes 131_072

  @spec decode(keyword(), binary()) ::
          {:ok, Event.t() | {:playback_mark, String.t(), String.t()}}
          | :ignore
          | {:error, :invalid_telnyx_media_message}
  def decode(options, message)
      when is_list(options) and is_binary(message) and
             byte_size(message) <= @maximum_message_bytes do
    with {:ok, decoded} <- JSON.decode(message) do
      decode_event(options, decoded)
    else
      _invalid -> invalid()
    end
  end

  def decode(_options, _message), do: invalid()

  defp decode_event(_options, %{"event" => "connected", "version" => version})
       when is_binary(version),
       do: :ignore

  defp decode_event(options, %{"event" => "start"} = message) do
    start = Map.get(message, "start")

    with true <- is_map(start),
         {:ok, stream_id} <- present_string(message, "stream_id"),
         :ok <- expected(options, :stream_id, stream_id),
         {:ok, call_control_id} <- present_string(start, "call_control_id"),
         :ok <- required_expected(options, :provider_call_control_id, call_control_id),
         {:ok, call_session_id} <- present_string(start, "call_session_id"),
         :ok <- required_expected(options, :provider_call_session_id, call_session_id),
         :ok <- matching_client_state(options, Map.get(start, "client_state")),
         :ok <- media_format(Map.get(start, "media_format")) do
      {:ok,
       %Event{
         kind: :media_started,
         provider: :telnyx,
         provider_connection_id: Keyword.get(options, :provider_connection_id),
         provider_call_control_id: call_control_id,
         provider_call_leg_id: Keyword.get(options, :provider_call_leg_id),
         provider_call_session_id: call_session_id,
         stream_id: stream_id
       }}
    else
      _invalid -> invalid()
    end
  end

  defp decode_event(options, %{"event" => "media"} = message) do
    media = Map.get(message, "media")

    with true <- is_map(media),
         {:ok, stream_id} <- present_string(message, "stream_id"),
         :ok <- required_expected(options, :stream_id, stream_id),
         {:ok, provider_sequence} <- non_negative_integer(message, "sequence_number"),
         {:ok, sequence_number} <- non_negative_integer(media, "chunk"),
         {:ok, timestamp} <- non_negative_integer(media, "timestamp"),
         "inbound" <- Map.get(media, "track"),
         {:ok, payload} <- decode_payload(Map.get(media, "payload")),
         {:ok, call_control_id} <- required_option(options, :provider_call_control_id) do
      packet = %MediaPacket{
        codec: :opus,
        sample_rate: 16_000,
        channels: 1,
        sequence_number: sequence_number,
        timestamp: timestamp,
        payload: payload
      }

      {:ok,
       %Event{
         kind: :media,
         provider: :telnyx,
         provider_event_id: event_id(stream_id, provider_sequence),
         provider_connection_id: Keyword.get(options, :provider_connection_id),
         provider_call_control_id: call_control_id,
         provider_call_leg_id: Keyword.get(options, :provider_call_leg_id),
         provider_call_session_id: Keyword.get(options, :provider_call_session_id),
         stream_id: stream_id,
         sequence_number: sequence_number,
         media: packet
       }}
    else
      _invalid -> invalid()
    end
  end

  defp decode_event(options, %{"event" => "dtmf"} = message) do
    dtmf = Map.get(message, "dtmf")

    with true <- is_map(dtmf),
         {:ok, stream_id} <- present_string(message, "stream_id"),
         :ok <- required_expected(options, :stream_id, stream_id),
         {:ok, provider_sequence} <- non_negative_integer(message, "sequence_number"),
         {:ok, occurred_at} <- timestamp(Map.get(message, "occurred_at")),
         {:ok, call_control_id} <- required_option(options, :provider_call_control_id),
         {:ok, call_leg_id} <- required_option(options, :provider_call_leg_id),
         {:ok, call_session_id} <- required_option(options, :provider_call_session_id),
         {:ok, digit} <- present_string(dtmf, "digit") do
      {:ok,
       %Event{
         kind: :dtmf,
         provider: :telnyx,
         provider_event_id: event_id(stream_id, provider_sequence),
         provider_connection_id: Keyword.get(options, :provider_connection_id),
         provider_call_control_id: call_control_id,
         provider_call_leg_id: call_leg_id,
         provider_call_session_id: call_session_id,
         occurred_at: occurred_at,
         stream_id: stream_id,
         digit: digit
       }}
    else
      _invalid -> invalid()
    end
  end

  defp decode_event(options, %{"event" => "mark", "mark" => mark} = message) when is_map(mark) do
    with {:ok, stream_id} <- present_string(message, "stream_id"),
         :ok <- required_expected(options, :stream_id, stream_id),
         {:ok, _sequence} <- non_negative_integer(message, "sequence_number"),
         {:ok, name} <- present_string(mark, "name"),
         true <- byte_size(name) <= 128 do
      {:ok, {:playback_mark, stream_id, name}}
    else
      _invalid -> invalid()
    end
  end

  defp decode_event(_options, %{"event" => "mark"}), do: invalid()

  defp decode_event(options, %{"event" => "stop"} = message) do
    stop = Map.get(message, "stop")

    with true <- is_map(stop),
         {:ok, stream_id} <- present_string(message, "stream_id"),
         :ok <- required_expected(options, :stream_id, stream_id),
         {:ok, call_control_id} <- present_string(stop, "call_control_id"),
         :ok <- required_expected(options, :provider_call_control_id, call_control_id) do
      :ignore
    else
      _invalid -> invalid()
    end
  end

  defp decode_event(_options, %{"event" => "error"}), do: invalid()
  defp decode_event(_options, %{"event" => event}) when is_binary(event), do: :ignore
  defp decode_event(_options, _message), do: invalid()

  defp media_format(%{
         "encoding" => "OPUS",
         "sample_rate" => 16_000,
         "channels" => 1
       }),
       do: :ok

  defp media_format(_invalid), do: :error

  defp matching_client_state(options, encoded) when is_binary(encoded) do
    with {:ok, leg_id} <- ClientState.decode(encoded),
         :ok <- required_expected(options, :leg_id, leg_id) do
      :ok
    else
      _invalid -> :error
    end
  end

  defp matching_client_state(_options, _invalid), do: :error

  defp expected(options, key, value) do
    case Keyword.get(options, key) do
      nil -> :ok
      ^value -> :ok
      _other -> :error
    end
  end

  defp required_expected(options, key, value) do
    case Keyword.get(options, key) do
      ^value when is_binary(value) and byte_size(value) > 0 -> :ok
      _other -> :error
    end
  end

  defp required_option(options, key) do
    case Keyword.get(options, key) do
      value when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
      _missing -> :error
    end
  end

  defp present_string(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
      _missing -> :error
    end
  end

  defp non_negative_integer(map, key) do
    case Map.get(map, key) do
      value when is_integer(value) and value >= 0 -> {:ok, value}
      value when is_binary(value) -> parse_non_negative_integer(value)
      _invalid -> :error
    end
  end

  defp parse_non_negative_integer(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed >= 0 -> {:ok, parsed}
      _invalid -> :error
    end
  end

  defp decode_payload(payload) when is_binary(payload) and byte_size(payload) > 0 do
    case Base.decode64(payload) do
      {:ok, decoded} when byte_size(decoded) > 0 -> {:ok, decoded}
      _invalid -> :error
    end
  end

  defp decode_payload(_invalid), do: :error

  defp timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, occurred_at, 0} -> {:ok, occurred_at}
      _invalid -> :error
    end
  end

  defp timestamp(_invalid), do: :error

  defp event_id(stream_id, sequence_number), do: "#{stream_id}:#{sequence_number}"
  defp invalid, do: {:error, :invalid_telnyx_media_message}
end
