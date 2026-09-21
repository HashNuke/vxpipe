defmodule Vxpipe.Providers.Google.STT do
  @moduledoc false

  @endpoint "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
  @model "gemini-3.5-transcribe-live"
  @maximum_message_bytes 262_144
  @maximum_audio_bytes 32_000
  @maximum_text_bytes 65_536

  @enforce_keys [:api_key, :model, :encoding, :sample_rate]
  @derive {Inspect, only: [:model, :encoding, :sample_rate]}
  defstruct @enforce_keys ++ [endpoint: @endpoint]

  def new(options) when is_list(options) do
    with {:ok, public} <- public_options(Keyword.drop(options, [:api_key])),
         api_key when is_binary(api_key) <- Keyword.get(options, :api_key),
         true <- byte_size(api_key) in 1..8_192,
         true <- Regex.match?(~r/\A[\x21-\x7E]+\z/, api_key) do
      {:ok, struct(__MODULE__, Map.put(public, :api_key, api_key))}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def new(_options), do: {:error, :invalid_configuration}

  def public_options(options) when is_list(options) do
    with {:ok, options} <-
           Keyword.validate(options,
             model: @model,
             encoding: :linear16,
             sample_rate: 16_000
           ),
         @model <- Keyword.fetch!(options, :model),
         :linear16 <- Keyword.fetch!(options, :encoding),
         16_000 <- Keyword.fetch!(options, :sample_rate) do
      {:ok, %{model: @model, encoding: :linear16, sample_rate: 16_000}}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def public_options(_options), do: {:error, :invalid_configuration}

  def connection_options(%__MODULE__{} = config),
    do: %{url: config.endpoint, headers: [{"x-goog-api-key", config.api_key}]}

  def setup(%__MODULE__{} = config) do
    %{
      "setup" => %{
        "model" => "models/" <> config.model,
        "generationConfig" => %{"responseModalities" => ["TEXT"]},
        "inputAudioTranscription" => %{}
      }
    }
  end

  def encode_audio(audio)
      when is_binary(audio) and byte_size(audio) > 0 and
             byte_size(audio) <= @maximum_audio_bytes and rem(byte_size(audio), 2) == 0 do
    {:ok,
     JSON.encode!(%{
       "realtimeInput" => %{
         "audio" => %{"data" => Base.encode64(audio), "mimeType" => "audio/pcm;rate=16000"}
       }
     })}
  end

  def encode_audio(_audio), do: {:error, :invalid_audio}

  def decode(payload) when is_binary(payload) and byte_size(payload) <= @maximum_message_bytes do
    case JSON.decode(payload) do
      {:ok, %{"error" => _error}} -> {:error, :provider_failure}
      {:ok, message} when is_map(message) -> decode_message(message)
      _invalid -> {:error, :invalid_message}
    end
  end

  def decode(_payload), do: {:error, :invalid_message}

  defp decode_message(message) do
    with {:ok, activity} <- activity(message),
         {:ok, content} <- content(message) do
      events =
        []
        |> append(Map.has_key?(message, "setupComplete"), :ready)
        |> append(activity != nil, activity)
        |> Kernel.++(content)
        |> append(Map.has_key?(message, "goAway"), :go_away)

      {:ok, events}
    end
  end

  defp append(events, true, value), do: events ++ [value]
  defp append(events, false, _value), do: events

  defp activity(%{"voiceActivity" => %{"type" => "ACTIVITY_START"}}),
    do: {:ok, :activity_start}

  defp activity(%{"voiceActivity" => %{"type" => "ACTIVITY_END"}}),
    do: {:ok, :activity_end}

  defp activity(%{"voiceActivity" => _activity}), do: {:error, :invalid_message}
  defp activity(_message), do: {:ok, nil}

  defp content(%{"serverContent" => content}) when is_map(content) do
    with {:ok, interim} <- transcription(content, "interimInputTranscription", :interim),
         {:ok, final} <- transcription(content, "inputTranscription", :final) do
      {:ok, interim ++ final}
    end
  end

  defp content(%{"serverContent" => _content}), do: {:error, :invalid_message}
  defp content(_message), do: {:ok, []}

  defp transcription(content, key, kind) do
    case Map.fetch(content, key) do
      :error ->
        {:ok, []}

      {:ok, %{"text" => text}}
      when is_binary(text) and byte_size(text) <= @maximum_text_bytes ->
        if String.valid?(text), do: {:ok, [{kind, text}]}, else: {:error, :invalid_message}

      _invalid ->
        {:error, :invalid_message}
    end
  end
end
