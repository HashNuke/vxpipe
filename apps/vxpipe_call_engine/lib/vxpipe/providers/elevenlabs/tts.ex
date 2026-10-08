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
      ),
      Model.new("eleven_v3", "Eleven v3", false, Model.free_voice("JBFqnCBsd6RMkjVDRZzb"))
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

  def request_url(%__MODULE__{} = config), do: config.endpoint <> "/" <> config.voice <> "/stream"

  def request_body(%__MODULE__{} = config, text), do: %{model_id: config.model, text: text}

  def request_options(%__MODULE__{} = config, text, into) do
    [
      headers: [
        {"xi-api-key", config.api_key},
        {"accept", "application/octet-stream, audio/pcm"}
      ],
      params: [output_format: "pcm_#{config.sample_rate}"],
      json: request_body(config, text),
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
