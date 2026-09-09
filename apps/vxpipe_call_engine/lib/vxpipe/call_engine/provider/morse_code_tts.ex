defmodule Vxpipe.CallEngine.Provider.MorseCodeTTS do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.Provider.TextToSpeech

  alias Vxpipe.CallEngine.Provider.MorseCode.Config
  alias Vxpipe.CallEngine.Provider.TextToSpeech.Signal

  @maximum_audio_bytes 65_536
  @maximum_identifier_bytes 128
  @maximum_message_bytes 65_536
  @maximum_text_bytes 4_096

  @impl true
  def new(options) when is_list(options), do: Config.new(options)
  def new(_options), do: {:error, :invalid_configuration}

  @impl true
  def connection_options(%Config{} = config), do: %{config: config}

  @impl true
  def media_format(%Config{} = config) do
    %{codec: :linear16, sample_rate: config.sample_rate, channels: 1, byte_order: :little}
  end

  @impl true
  def encode_speak(text) when is_binary(text) do
    JSON.encode!(%{"type" => "Speak", "text" => text})
  end

  @impl true
  def encode_flush, do: JSON.encode!(%{"type" => "Flush"})

  @impl true
  def encode_interrupt(playback_offset_ms)
      when is_integer(playback_offset_ms) and playback_offset_ms >= 0 do
    JSON.encode!(%{"type" => "Interrupt", "playback_offset_ms" => playback_offset_ms})
  end

  @impl true
  def decode(payload) when is_binary(payload) do
    if byte_size(payload) > @maximum_message_bytes do
      {:error, :message_too_large}
    else
      case JSON.decode(payload) do
        {:ok, message} when is_map(message) -> decode_message(message)
        {:ok, _other} -> {:error, :invalid_message}
        {:error, _reason} -> {:error, :invalid_json}
      end
    end
  end

  @impl true
  def decode_audio(payload) when is_binary(payload) do
    cond do
      byte_size(payload) == 0 -> {:error, :empty_audio}
      byte_size(payload) > @maximum_audio_bytes -> {:error, :audio_too_large}
      true -> {:audio, payload}
    end
  end

  defp decode_message(%{"type" => "SpeechStarted", "speech_id" => speech_id}) do
    signal(:speech_started, speech_id)
  end

  defp decode_message(%{"type" => "SpeechMetadata", "speech_id" => speech_id}) do
    signal(:speech_completed, speech_id)
  end

  defp decode_message(%{
         "type" => "SpeechInterrupted",
         "speech_id" => speech_id,
         "audio_played_ms" => audio_played_ms,
         "text_spoken" => text_spoken,
         "text_remaining" => text_remaining
       }) do
    with {:ok, signal} <- signal(:speech_interrupted, speech_id),
         true <- is_integer(audio_played_ms) and audio_played_ms >= 0,
         true <- valid_text?(text_spoken),
         true <- valid_text?(text_remaining) do
      {:ok,
       %{
         signal
         | audio_played_ms: audio_played_ms,
           text_spoken: text_spoken,
           text_remaining: text_remaining
       }}
    else
      _invalid -> {:error, :invalid_message}
    end
  end

  defp decode_message(%{"type" => "Error", "code" => code}) do
    if valid_identifier?(code) do
      {:ok, %Signal{kind: :failed, provider_code: code}}
    else
      {:error, :invalid_message}
    end
  end

  defp decode_message(%{"type" => type})
       when type in ["SpeechStarted", "SpeechMetadata", "SpeechInterrupted", "Error"],
       do: {:error, :invalid_message}

  defp decode_message(%{"type" => _type}), do: {:ignore, :unknown_message}
  defp decode_message(_message), do: {:error, :invalid_message}

  defp signal(kind, speech_id) do
    if valid_identifier?(speech_id) do
      {:ok, %Signal{kind: kind, provider_speech_id: speech_id}}
    else
      {:error, :invalid_message}
    end
  end

  defp valid_identifier?(value) do
    is_binary(value) and byte_size(value) > 0 and
      byte_size(value) <= @maximum_identifier_bytes and String.valid?(value)
  end

  defp valid_text?(value) do
    is_binary(value) and byte_size(value) <= @maximum_text_bytes and String.valid?(value)
  end
end
