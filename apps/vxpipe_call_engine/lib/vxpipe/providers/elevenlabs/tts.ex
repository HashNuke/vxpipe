defmodule Vxpipe.Providers.ElevenLabs.TTS do
  @moduledoc false
  @endpoint "https://api.elevenlabs.io/v1/text-to-speech"
  @rates [8_000, 16_000, 24_000, 48_000]
  @enforce_keys [:api_key, :model, :voice, :sample_rate]
  @derive {Inspect, only: [:model, :voice, :sample_rate]}
  defstruct @enforce_keys ++ [endpoint: @endpoint]

  alias Vxpipe.CallEngine.Speech.Model

  def models do
    [
      Model.new(
        "eleven_flash_v2_5",
        "Eleven Flash v2.5",
        true,
        Model.free_voice("JBFqnCBsd6RMkjVDRZzb")
      ),
      Model.new(
        "eleven_multilingual_v2",
        "Eleven Multilingual v2",
        false,
        Model.free_voice("JBFqnCBsd6RMkjVDRZzb")
      )
    ]
  end

  def new(options) when is_list(options) do
    with true <- Keyword.keyword?(options),
         true <- unique_options?(options),
         {:ok, public} <- public_options(Keyword.drop(options, [:api_key])),
         key <- Keyword.get(options, :api_key),
         :ok <- Vxpipe.Providers.APIKeyCredential.validate("api_key", %{"api_key" => key}) do
      {:ok, struct(__MODULE__, Map.put(public, :api_key, key))}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def new(_options), do: {:error, :invalid_configuration}

  def public_options(options) when is_list(options) do
    with true <- Keyword.keyword?(options),
         true <- unique_options?(options),
         {:ok, options} <-
           Keyword.validate(options, model: "eleven_flash_v2_5", voice: nil, sample_rate: 16_000),
         model <- Keyword.fetch!(options, :model),
         true <- Model.supported?(models(), model),
         true <- websocket_compatible?(model),
         voice when is_binary(voice) <- Keyword.fetch!(options, :voice),
         true <- Regex.match?(~r/\A[A-Za-z0-9_-]{1,128}\z/, voice),
         rate <- Keyword.fetch!(options, :sample_rate),
         true <- rate in @rates do
      {:ok, %{model: model, voice: voice, sample_rate: rate}}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def public_options(_options), do: {:error, :invalid_configuration}

  def validate_text(text) when is_binary(text) do
    if String.valid?(text) and String.trim(text) != "" and byte_size(text) <= 4_000 and
         String.length(text) <= 1_000,
       do: :ok,
       else: {:error, :invalid_text}
  end

  def validate_text(_text), do: {:error, :invalid_text}

  @websocket_models ["eleven_flash_v2_5", "eleven_multilingual_v2"]

  def websocket_models, do: @websocket_models

  def websocket_compatible?(model) when is_binary(model), do: model in @websocket_models
  def websocket_compatible?(_model), do: false

  def connection_options(%__MODULE__{} = config) do
    uri = URI.new!(config.endpoint)
    scheme = if uri.scheme == "https", do: "wss", else: "ws"
    path = String.trim_trailing(uri.path || "", "/") <> "/#{config.voice}/multi-stream-input"

    url =
      %{uri | scheme: scheme, path: path, userinfo: nil, fragment: nil, query: query(config)}
      |> URI.to_string()

    %{url: url, headers: [{"xi-api-key", config.api_key}]}
  end

  def new_context_id,
    do: {:ok, "ctx_" <> Base.encode16(:crypto.strong_rand_bytes(9), case: :lower)}

  def open_utterance(%__MODULE__{}, context, text)
      when is_binary(context) and is_binary(text) do
    [
      JSON.encode!(%{"text" => " ", "context_id" => context}),
      JSON.encode!(%{"text" => text, "context_id" => context}),
      JSON.encode!(%{"context_id" => context, "flush" => true}),
      JSON.encode!(%{"context_id" => context, "close_context" => true})
    ]
  end

  def close_utterance(%__MODULE__{}, context) when is_binary(context),
    do: JSON.encode!(%{"context_id" => context, "close_context" => true})

  def close_socket(%__MODULE__{}), do: JSON.encode!(%{"close_socket" => true})

  def keepalive_payload(%__MODULE__{}, context) when is_binary(context),
    do: JSON.encode!(%{"text" => "", "context_id" => context})

  def decode_frame(payload) when is_binary(payload) and byte_size(payload) <= 2_097_152 do
    case JSON.decode(payload) do
      {:ok, %{"audio" => encoded, "contextId" => context} = frame}
      when is_binary(encoded) and is_binary(context) ->
        with {:ok, pcm} <- Base.decode64(encoded),
             {:audio, pcm} <- validate_audio(pcm) do
          if Map.get(frame, "isFinal") == true,
            do: {:ok, {:audio_final, context, pcm}},
            else: {:ok, {:audio, context, pcm}}
        else
          _invalid -> {:error, :invalid_message}
        end

      {:ok, %{"isFinal" => true, "contextId" => context}} when is_binary(context) ->
        {:ok, {:final, context}}

      _other ->
        {:error, :invalid_message}
    end
  end

  def decode_frame(_payload), do: {:error, :invalid_message}

  def validate_audio(audio) when is_binary(audio) do
    if byte_size(audio) > 0 and byte_size(audio) <= 1_048_576 and rem(byte_size(audio), 2) == 0,
      do: {:audio, audio},
      else: {:error, :invalid_message}
  end

  def validate_audio(_audio), do: {:error, :invalid_message}

  defp query(config) do
    URI.encode_query(%{
      "model_id" => config.model,
      "output_format" => "pcm_#{config.sample_rate}",
      "inactivity_timeout" => "180"
    })
  end

  defp unique_options?(options),
    do: length(options) == length(Enum.uniq(Keyword.keys(options)))
end
