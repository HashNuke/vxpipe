defmodule Vxpipe.Providers.ElevenLabs.AgentProtocol do
  @moduledoc "Bounded hosted-agent wire codec; native events do not imply room publication."
  @maximum_message_bytes 262_144
  @maximum_text_bytes 65_536
  @maximum_audio_bytes 65_536
  @message_kinds %{
    "conversation_initiation_metadata" => :metadata,
    "user_transcript" => :user_transcript,
    "agent_response" => :agent_response,
    "agent_response_correction" => :correction,
    "audio" => :audio,
    "agent_response_complete" => :response_complete,
    "interruption" => :interruption,
    "vad_score" => :vad,
    "client_tool_call" => :tool_call,
    "ping" => :ping,
    "queue_status" => :queue_status,
    "client_error" => :provider_error
  }

  def message_kind(payload)
      when is_binary(payload) and byte_size(payload) <= @maximum_message_bytes do
    case JSON.decode(payload) do
      {:ok, %{"type" => type}} -> Map.get(@message_kinds, type, :unknown)
      _invalid -> :unknown
    end
  end

  def message_kind(_invalid), do: :unknown

  defguardp valid_event_id?(id)
            when is_integer(id) and id >= -9_223_372_036_854_775_808 and
                   id <= 9_223_372_036_854_775_807

  def initiation, do: JSON.encode!(%{"type" => "conversation_initiation_client_data"})

  def audio(pcm)
      when is_binary(pcm) and byte_size(pcm) in 2..@maximum_audio_bytes and
             rem(byte_size(pcm), 2) == 0,
      do: {:ok, JSON.encode!(%{"user_audio_chunk" => Base.encode64(pcm)})}

  def audio(_invalid), do: {:error, :invalid_audio}

  def pong(event_id) when valid_event_id?(event_id),
    do: {:ok, JSON.encode!(%{"type" => "pong", "event_id" => event_id})}

  def pong(_invalid), do: {:error, :invalid_message}

  def tool_result(id, text, error?) when is_boolean(error?) do
    if valid_identifier?(id) and valid_text?(text) do
      {:ok,
       JSON.encode!(%{
         "type" => "client_tool_result",
         "tool_call_id" => id,
         "result" => text,
         "is_error" => error?
       })}
    else
      {:error, :invalid_message}
    end
  end

  def tool_result(_id, _text, _error?), do: {:error, :invalid_message}

  def user_message(text), do: text_message("user_message", text)
  def contextual_update(text), do: text_message("contextual_update", text)

  def decode(payload) when is_binary(payload) and byte_size(payload) <= @maximum_message_bytes do
    case JSON.decode(payload) do
      {:ok, %{"type" => type} = message} -> decode_event(type, message)
      _invalid -> {:error, :invalid_message}
    end
  end

  def decode(_invalid), do: {:error, :invalid_message}

  defp decode_event("conversation_initiation_metadata", %{
         "conversation_initiation_metadata_event" => %{
           "conversation_id" => id,
           "agent_output_audio_format" => "pcm_16000",
           "user_input_audio_format" => "pcm_16000"
         }
       }) do
    if valid_identifier?(id), do: {:ok, {:ready, id}}, else: {:error, :invalid_message}
  end

  defp decode_event("user_transcript", %{
         "user_transcription_event" => %{"event_id" => id, "user_transcript" => text}
       })
       when valid_event_id?(id) do
    if valid_text?(text),
      do: {:ok, {:user_transcript, id, text}},
      else: {:error, :invalid_message}
  end

  defp decode_event("agent_response", %{
         "agent_response_event" => %{
           "event_id" => id,
           "response_id" => response_id,
           "agent_response" => text
         }
       })
       when valid_event_id?(id),
       do: response_text(:agent_response, id, response_id, text)

  defp decode_event("agent_response_correction", %{
         "agent_response_correction_event" => %{
           "event_id" => id,
           "response_id" => response_id,
           "original_agent_response" => original,
           "corrected_agent_response" => text
         }
       })
       when valid_event_id?(id) do
    if valid_text?(original),
      do: response_text(:agent_response_correction, id, response_id, text),
      else: {:error, :invalid_message}
  end

  defp decode_event("audio", %{
         "audio_event" => %{"event_id" => id, "audio_base_64" => encoded} = audio
       })
       when valid_event_id?(id) and is_binary(encoded) do
    with {:ok, pcm} <- Base.decode64(encoded),
         true <- byte_size(pcm) <= @maximum_audio_bytes and rem(byte_size(pcm), 2) == 0,
         final? <- Map.get(audio, "is_final", false),
         true <- is_boolean(final?) and (byte_size(pcm) > 0 or final?),
         alignment <- Map.get(audio, "alignment"),
         true <- valid_alignment?(alignment) do
      {:ok, {:audio, id, pcm, final?, public_alignment(alignment)}}
    else
      _invalid -> {:error, :invalid_message}
    end
  end

  defp decode_event("agent_response_complete", %{
         "agent_response_complete_event" => %{"event_id" => id}
       })
       when valid_event_id?(id),
       do: {:ok, {:response_complete, id}}

  defp decode_event("interruption", %{"interruption_event" => %{"event_id" => id}})
       when valid_event_id?(id),
       do: {:ok, {:interrupted, id}}

  defp decode_event("vad_score", %{"vad_score_event" => %{"vad_score" => score}})
       when is_number(score) and score >= 0 and score <= 1,
       do: {:ok, {:vad, score}}

  defp decode_event("client_tool_call", %{
         "client_tool_call" => %{
           "event_id" => id,
           "tool_call_id" => call_id,
           "tool_name" => name,
           "parameters" => arguments,
           "expects_response" => response?
         }
       })
       when valid_event_id?(id) and is_map(arguments) and is_boolean(response?) do
    if valid_identifier?(call_id) and valid_identifier?(name) do
      {:ok,
       {:tool_call, id,
        %{id: call_id, name: name, arguments: arguments, expects_response?: response?}}}
    else
      {:error, :invalid_message}
    end
  end

  # ping_ms is an optional latency estimate, not a scheduling instruction.
  defp decode_event("ping", %{"ping_event" => %{"event_id" => id}})
       when valid_event_id?(id),
       do: {:ok, {:ping, id}}

  defp decode_event("queue_status", %{"queue_status_event" => %{"status" => status}})
       when status in ["waiting", "admitted", "timed_out"],
       do: {:ok, {:queue_status, status}}

  defp decode_event("client_error", %{"error_event" => %{"code" => code}})
       when valid_event_id?(code),
       do: {:ok, {:provider_error, code}}

  defp decode_event(_type, _message), do: {:error, :invalid_message}

  defp response_text(kind, id, response_id, text) do
    if valid_identifier?(response_id) and valid_text?(text),
      do: {:ok, {kind, id, response_id, text}},
      else: {:error, :invalid_message}
  end

  defp text_message(type, text) do
    if valid_text?(text),
      do: {:ok, JSON.encode!(%{"type" => type, "text" => text})},
      else: {:error, :invalid_message}
  end

  defp valid_text?(text) when is_binary(text),
    do: byte_size(text) <= @maximum_text_bytes and String.valid?(text)

  defp valid_text?(_invalid), do: false

  defp valid_identifier?(id) when is_binary(id),
    do: byte_size(id) in 1..256 and String.valid?(id)

  defp valid_identifier?(_invalid), do: false

  defp public_alignment(nil), do: nil

  defp public_alignment(alignment),
    do: Map.take(alignment, ["chars", "char_start_times_ms", "char_durations_ms"])

  defp valid_alignment?(nil), do: true

  defp valid_alignment?(%{
         "chars" => chars,
         "char_start_times_ms" => starts,
         "char_durations_ms" => durations
       })
       when is_list(chars) and is_list(starts) and is_list(durations) do
    length(chars) == length(starts) and length(starts) == length(durations) and
      Enum.all?(chars, &valid_text?/1) and
      Enum.all?(starts, &(is_integer(&1) and &1 >= 0)) and
      Enum.all?(durations, &(is_integer(&1) and &1 >= 0))
  end

  defp valid_alignment?(_invalid), do: false
end
