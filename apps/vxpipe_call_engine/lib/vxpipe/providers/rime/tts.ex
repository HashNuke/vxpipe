defmodule Vxpipe.Providers.Rime.TTS do
  @moduledoc false

  @endpoint "wss://users-ws.rime.ai/ws3"
  @sample_rates [8_000, 16_000, 24_000, 48_000]
  @maximum_text_bytes 4_000
  @maximum_message_bytes 1_400_000
  @maximum_audio_bytes 1_048_576

  @enforce_keys [:api_key, :model, :speaker, :sample_rate]
  @derive {Inspect, only: [:model, :speaker, :sample_rate]}
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
           Keyword.validate(options, model: "coda", speaker: "astra", sample_rate: 24_000),
         "coda" <- Keyword.fetch!(options, :model),
         speaker when is_binary(speaker) <- Keyword.fetch!(options, :speaker),
         true <- byte_size(speaker) in 1..128,
         true <- Regex.match?(~r/\A[A-Za-z0-9][A-Za-z0-9_-]*\z/, speaker),
         sample_rate when sample_rate in @sample_rates <- Keyword.fetch!(options, :sample_rate) do
      {:ok, %{model: "coda", speaker: speaker, sample_rate: sample_rate}}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def public_options(_options), do: {:error, :invalid_configuration}

  def connection_options(%__MODULE__{} = config) do
    query =
      URI.encode_query(%{
        "speaker" => config.speaker,
        "modelId" => config.model,
        "audioFormat" => "pcm",
        "samplingRate" => Integer.to_string(config.sample_rate),
        "segment" => "never"
      })

    %{
      url: config.endpoint <> "?" <> query,
      headers: [{"Authorization", "Bearer " <> config.api_key}]
    }
  end

  def encode_text(text) when is_binary(text) do
    if String.valid?(text) and String.trim(text) != "" and
         byte_size(text) <= @maximum_text_bytes and String.length(text) <= 1_000 do
      {:ok, JSON.encode!(%{"text" => text})}
    else
      {:error, :invalid_text}
    end
  end

  def encode_text(_text), do: {:error, :invalid_text}
  def encode_flush, do: JSON.encode!(%{"operation" => "flush"})
  def encode_clear, do: JSON.encode!(%{"operation" => "clear"})

  def decode(payload) when is_binary(payload) and byte_size(payload) <= @maximum_message_bytes do
    case JSON.decode(payload) do
      {:ok, %{"type" => "chunk", "data" => data}} when is_binary(data) ->
        case Base.decode64(data) do
          {:ok, audio} -> validate_audio(audio)
          :error -> {:error, :invalid_message}
        end

      {:ok, %{"type" => "done"}} ->
        :done

      {:ok, %{"type" => "timestamps"}} ->
        :ignore

      {:ok, %{"type" => "error"}} ->
        {:error, :provider_failure}

      _other ->
        {:error, :invalid_message}
    end
  end

  def decode(_payload), do: {:error, :invalid_message}

  def validate_audio(audio) when is_binary(audio) do
    if byte_size(audio) > 0 and byte_size(audio) <= @maximum_audio_bytes and
         rem(byte_size(audio), 2) == 0,
       do: {:audio, audio},
       else: {:error, :invalid_message}
  end

  def validate_audio(_audio), do: {:error, :invalid_message}
end
