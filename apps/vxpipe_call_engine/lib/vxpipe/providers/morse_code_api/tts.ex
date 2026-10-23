defmodule Vxpipe.Providers.MorseCodeApi.TTS do
  @moduledoc false
  alias Vxpipe.CallEngine.Speech.Model
  alias Vxpipe.Providers.MorseCodeApi.{Credential, Endpoint}

  @rates [8_000, 16_000, 24_000, 48_000]
  @enforce_keys [:api_key, :endpoint, :model, :voice, :sample_rate]
  @derive {Inspect, only: [:model, :voice, :sample_rate]}
  defstruct @enforce_keys

  def models do
    voices = %{
      type: :list,
      parameter: "voice",
      values: [%{id: "morse", name: "Morse 700 Hz", default: true}]
    }

    [Model.new("morse_v1", "MorseCodeApiTTS", true, voices)]
  end

  def new(options) do
    with {:ok, endpoint} <- Endpoint.configured(), do: new(options, endpoint)
  end

  # The second argument is a privately resolved origin, never a call-spec option.
  def new(options, %Endpoint{} = endpoint) when is_list(options) do
    with true <- Keyword.keyword?(options),
         true <- unique_options?(options),
         {:ok, public} <- public_options(Keyword.drop(options, [:api_key])),
         key <- Keyword.get(options, :api_key),
         :ok <- Credential.validate("api_key", %{"api_key" => key}) do
      {:ok, struct(__MODULE__, Map.merge(public, %{api_key: key, endpoint: endpoint.http}))}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def new(_options, _endpoint), do: {:error, :invalid_configuration}

  def public_options(options) when is_list(options) do
    with true <- Keyword.keyword?(options),
         true <- unique_options?(options),
         {:ok, options} <-
           Keyword.validate(options, model: "morse_v1", voice: "morse", sample_rate: 16_000),
         "morse_v1" <- Keyword.fetch!(options, :model),
         "morse" <- Keyword.fetch!(options, :voice),
         rate <- Keyword.fetch!(options, :sample_rate),
         true <- rate in @rates do
      {:ok, %{model: "morse_v1", voice: "morse", sample_rate: rate}}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def public_options(_options), do: {:error, :invalid_configuration}

  def validate_text(text) when is_binary(text) do
    if String.valid?(text) and String.trim(text) != "" and byte_size(text) <= 4_096,
      do: :ok,
      else: {:error, :invalid_text}
  end

  def validate_text(_text), do: {:error, :invalid_text}

  def connection_options(%__MODULE__{} = config) do
    uri = URI.new!(config.endpoint)
    scheme = if uri.scheme == "https", do: "wss", else: "ws"

    url =
      %{
        uri
        | scheme: scheme,
          path: "/v1/text-to-speech/#{config.voice}/multi-stream-input",
          query:
            URI.encode_query(%{
              model_id: config.model,
              output_format: "pcm_#{config.sample_rate}",
              auto_mode: true,
              inactivity_timeout: 180
            })
      }
      |> URI.to_string()

    %{url: url, headers: []}
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

  defp unique_options?(options),
    do: length(options) == length(Enum.uniq(Keyword.keys(options)))
end
