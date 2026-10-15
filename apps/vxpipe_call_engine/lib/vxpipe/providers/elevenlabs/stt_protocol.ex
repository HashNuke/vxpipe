defmodule Vxpipe.Providers.ElevenLabs.STTProtocol do
  @moduledoc false
  @errors ~w(auth_error quota_exceeded transcriber_error input_error invalid_request error
    commit_throttled unaccepted_terms rate_limited queue_overflow resource_exhausted
    session_time_limit_exceeded chunk_size_exceeded insufficient_audio_activity)

  def encode_audio(audio)
      when is_binary(audio) and byte_size(audio) in 2..32_000 and rem(byte_size(audio), 2) == 0,
      do: {:ok, input_message(audio, false)}

  def encode_audio(_audio), do: {:error, :invalid_audio}
  def commit, do: input_message("", true)
  def keepalive, do: input_message("", false)

  # Interpretation of the acknowledgement and committed segments belongs to
  # each provider's explicit model and endpoint profile, not the JSON codec.
  def decode(payload) when is_binary(payload) and byte_size(payload) <= 262_144 do
    case JSON.decode(payload) do
      {:ok, %{"message_type" => type} = message} -> decode_message(type, message)
      _invalid -> {:error, :invalid_message}
    end
  end

  def decode(_payload), do: {:error, :invalid_message}

  defp decode_message(
         "session_started",
         %{"session_id" => session_id, "config" => config}
       )
       when is_binary(session_id) and byte_size(session_id) in 1..256 and is_map(config) do
    if String.valid?(session_id),
      do: {:ok, {:ready, session_id, config}},
      else: {:error, :invalid_message}
  end

  defp decode_message(type, %{"text" => text})
       when type in ["partial_transcript", "committed_transcript"] and is_binary(text) and
              byte_size(text) <= 65_536 do
    if String.valid?(text) do
      kind = if type == "partial_transcript", do: :partial, else: :segment
      {:ok, {kind, text}}
    else
      {:error, :invalid_message}
    end
  end

  defp decode_message(type, _message) when type in @errors,
    do: {:error, :provider_failure}

  defp decode_message(_type, _message), do: {:error, :invalid_message}

  defp input_message(audio, commit?) do
    JSON.encode!(%{
      "message_type" => "input_audio_chunk",
      "audio_base_64" => Base.encode64(audio),
      "commit" => commit?,
      "sample_rate" => 16_000
    })
  end
end
