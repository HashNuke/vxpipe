defmodule Vxpipe.CallEngine.Provider.Deepgram.FluxTextToSpeech do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.Provider.TextToSpeech

  alias Vxpipe.CallEngine.Provider.TextToSpeech.Signal

  @endpoint "wss://api.deepgram.com/v2/speak"
  @maximum_audio_bytes 1_048_576
  @maximum_code_bytes 128
  @maximum_identifier_bytes 128
  @maximum_message_bytes 262_144
  @maximum_text_bytes 65_536
  @sample_rates [8_000, 16_000, 24_000, 32_000, 44_100, 48_000]

  @derive {Inspect, only: [:model, :encoding, :sample_rate]}
  @enforce_keys [:api_key, :model, :encoding, :sample_rate]
  defstruct @enforce_keys ++ [endpoint: @endpoint]

  @type t :: %__MODULE__{
          api_key: String.t(),
          endpoint: String.t(),
          model: String.t(),
          encoding: :linear16,
          sample_rate: pos_integer()
        }

  @impl true
  def new(options) when is_list(options) do
    api_key = Keyword.get(options, :api_key)
    model = Keyword.get(options, :model, "flux-haley-en")
    encoding = Keyword.get(options, :encoding, :linear16)
    sample_rate = Keyword.get(options, :sample_rate, 48_000)

    if valid_api_key?(api_key) and valid_model?(model) and encoding == :linear16 and
         sample_rate in @sample_rates do
      {:ok,
       %__MODULE__{
         api_key: api_key,
         model: model,
         encoding: encoding,
         sample_rate: sample_rate
       }}
    else
      {:error, :invalid_configuration}
    end
  end

  def new!(options) do
    case new(options) do
      {:ok, provider} -> provider
      {:error, reason} -> raise ArgumentError, "invalid Flux TTS configuration: #{reason}"
    end
  end

  @impl true
  def connection_options(%__MODULE__{} = config) do
    query =
      URI.encode_query(%{
        "encoding" => "linear16",
        "model" => config.model,
        "sample_rate" => Integer.to_string(config.sample_rate)
      })

    %{
      url: config.endpoint <> "?" <> query,
      headers: [{"Authorization", "Token " <> config.api_key}]
    }
  end

  @impl true
  def media_format(%__MODULE__{} = config) do
    %{codec: :linear16, sample_rate: config.sample_rate, channels: 1, byte_order: :little}
  end

  @impl true
  def asset_cache_identity(%__MODULE__{} = config) do
    %{
      "provider" => "deepgram_flux",
      "model" => config.model,
      "encoding" => Atom.to_string(config.encoding),
      "sample_rate" => config.sample_rate
    }
  end

  @impl true
  def usage_identity(%__MODULE__{} = config) do
    [name: "deepgram", model: config.model]
  end

  @impl true
  def encode_speak(text) when is_binary(text) and byte_size(text) <= @maximum_text_bytes do
    JSON.encode!(%{"type" => "Speak", "text" => text})
  end

  @impl true
  def encode_flush, do: JSON.encode!(%{"type" => "Flush"})

  @impl true
  def encode_interrupt(playback_offset_ms)
      when is_integer(playback_offset_ms) and playback_offset_ms >= 0 do
    JSON.encode!(%{
      "type" => "Interrupt",
      "playback_offset" => %{"type" => "time_ms", "value" => playback_offset_ms}
    })
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

  def maximum_audio_bytes, do: @maximum_audio_bytes
  def maximum_message_bytes, do: @maximum_message_bytes

  defp decode_message(%{"type" => "Connected", "request_id" => request_id}) do
    signal(:connected, request_id, nil, nil)
  end

  defp decode_message(%{"type" => "SpeechStarted", "speech_id" => speech_id} = message) do
    signal(:speech_started, Map.get(message, "request_id"), speech_id, nil)
  end

  defp decode_message(%{"type" => "Flushed", "speech_id" => speech_id} = message) do
    signal(:flushed, Map.get(message, "request_id"), speech_id, nil)
  end

  defp decode_message(%{"type" => "SpeechMetadata", "speech_id" => speech_id} = message) do
    signal(:speech_completed, Map.get(message, "request_id"), speech_id, nil)
  end

  defp decode_message(%{"type" => "SpeechInterrupted", "metadata" => metadata} = message)
       when is_map(metadata) do
    with {:ok, signal} <-
           signal(
             :speech_interrupted,
             Map.get(message, "request_id"),
             Map.get(metadata, "speech_id"),
             nil
           ),
         audio_played_ms when is_integer(audio_played_ms) and audio_played_ms >= 0 <-
           Map.get(message, "audio_played_ms"),
         text_spoken when is_binary(text_spoken) <- Map.get(message, "text_spoken"),
         text_remaining when is_binary(text_remaining) <- Map.get(message, "text_remaining") do
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

  defp decode_message(%{"type" => "Warning", "code" => code} = message) do
    signal(:warning, Map.get(message, "request_id"), nil, code)
  end

  defp decode_message(%{"type" => "Error", "code" => code} = message) do
    signal(:failed, Map.get(message, "request_id"), nil, code)
  end

  defp decode_message(%{"type" => type})
       when type in [
              "Connected",
              "SpeechStarted",
              "Flushed",
              "SpeechMetadata",
              "SpeechInterrupted",
              "Warning",
              "Error"
            ],
       do: {:error, :invalid_message}

  defp decode_message(%{"type" => type})
       when type in ["SessionMetadata", "ConfigureSuccess", "ConfigureFailure"],
       do: {:ignore, :session_message}

  defp decode_message(%{"type" => _type}), do: {:ignore, :unknown_message}
  defp decode_message(_message), do: {:error, :invalid_message}

  defp signal(kind, request_id, speech_id, code) do
    if valid_optional_identifier?(request_id) and valid_optional_identifier?(speech_id) and
         valid_optional_code?(code) do
      {:ok,
       %Signal{
         kind: kind,
         request_id: request_id,
         provider_speech_id: speech_id,
         provider_code: code
       }}
    else
      {:error, :invalid_message}
    end
  end

  defp valid_api_key?(value), do: is_binary(value) and byte_size(String.trim(value)) > 0

  defp valid_model?("flux-" <> model) do
    byte_size(model) > 0 and byte_size(model) <= 120
  end

  defp valid_model?(_model), do: false

  defp valid_identifier?(value) do
    is_binary(value) and byte_size(value) > 0 and byte_size(value) <= @maximum_identifier_bytes
  end

  defp valid_optional_identifier?(nil), do: true
  defp valid_optional_identifier?(value), do: valid_identifier?(value)

  defp valid_optional_code?(nil), do: true

  defp valid_optional_code?(value) do
    is_binary(value) and byte_size(value) > 0 and byte_size(value) <= @maximum_code_bytes
  end
end
