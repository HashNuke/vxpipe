defmodule Vxpipe.Providers.Google.TTS do
  @moduledoc false

  @endpoint "https://generativelanguage.googleapis.com/v1beta/interactions"
  @model "gemini-3.1-flash-tts-preview"

  @enforce_keys [:api_key, :model, :voice, :sample_rate]
  @derive {Inspect, only: [:model, :voice, :sample_rate]}
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
    with {:ok, options} <- Keyword.validate(options, model: @model, voice: "Kore"),
         @model <- Keyword.fetch!(options, :model),
         voice when is_binary(voice) <- Keyword.fetch!(options, :voice),
         true <- byte_size(voice) in 1..128,
         true <- Regex.match?(~r/\A[A-Za-z][A-Za-z0-9_-]*\z/, voice) do
      {:ok, %{model: @model, voice: voice, sample_rate: 24_000}}
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

  def request_body(%__MODULE__{} = config, text) do
    %{
      model: config.model,
      input: text,
      response_format: %{type: "audio"},
      generation_config: %{speech_config: [%{voice: config.voice}]},
      stream: true
    }
  end

  def request_options(%__MODULE__{} = config, text, into) do
    [
      headers: [
        {"x-goog-api-key", config.api_key},
        {"Api-Revision", "2026-05-20"},
        {"accept", "text/event-stream"}
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
