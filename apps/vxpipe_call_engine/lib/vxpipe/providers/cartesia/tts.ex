defmodule Vxpipe.Providers.Cartesia.TTS do
  @moduledoc false
  @endpoint "https://api.cartesia.ai/tts/bytes"
  @models ~w(sonic-3.6 sonic-3.6-2026-08-27 sonic-3.5 sonic-3)
  @rates [8_000, 16_000, 24_000, 48_000]
  @enforce_keys [:api_key, :model, :voice, :sample_rate]
  @derive {Inspect, only: [:model, :voice, :sample_rate]}
  defstruct @enforce_keys ++ [endpoint: @endpoint]

  def new(options) when is_list(options) do
    with {:ok, public} <- public_options(Keyword.drop(options, [:api_key])),
         key <- Keyword.get(options, :api_key),
         :ok <- Vxpipe.Providers.APIKeyCredential.validate("api_key", %{"api_key" => key}) do
      {:ok, struct(__MODULE__, Map.put(public, :api_key, key))}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def new(_options), do: {:error, :invalid_configuration}

  def public_options(options) when is_list(options) do
    with {:ok, options} <-
           Keyword.validate(options, model: "sonic-3.6", voice: nil, sample_rate: 24_000),
         model <- Keyword.fetch!(options, :model),
         true <- model in @models,
         voice when is_binary(voice) <- Keyword.fetch!(options, :voice),
         true <- Regex.match?(~r/\A[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\z/, voice),
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
         String.length(text) <= 1_000, do: :ok, else: {:error, :invalid_text}
  end

  def validate_text(_text), do: {:error, :invalid_text}

  def request_body(%__MODULE__{} = config, text) do
    %{
      model_id: config.model,
      transcript: text,
      voice: config.voice,
      output_format: %{container: "raw", encoding: "pcm_s16le", sample_rate: config.sample_rate}
    }
  end

  def request_options(%__MODULE__{} = config, text, into) do
    [
      headers: [
        {"authorization", "Bearer " <> config.api_key},
        {"cartesia-version", "2026-08-14"},
        {"accept", "application/octet-stream, audio/*"}
      ],
      json: request_body(config, text),
      into: into,
      receive_timeout: 60_000,
      retry: false,
      max_redirects: 0,
      decode_body: false
    ]
  end
end
