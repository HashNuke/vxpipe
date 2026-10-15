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

  def request_url(%__MODULE__{} = config),
    do: config.endpoint <> "/v1/text-to-speech/" <> config.voice <> "/stream"

  def request_options(%__MODULE__{} = config, text, into) do
    [
      headers: [{"xi-api-key", config.api_key}, {"accept", "application/octet-stream, audio/pcm"}],
      params: [output_format: "pcm_#{config.sample_rate}"],
      json: %{model_id: config.model, text: text},
      into: into,
      receive_timeout: 60_000,
      retry: false,
      max_redirects: 0,
      decode_body: false
    ]
  end

  defp unique_options?(options),
    do: length(options) == length(Enum.uniq(Keyword.keys(options)))
end
