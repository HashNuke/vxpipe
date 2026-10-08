defmodule Vxpipe.Providers.Cartesia.STT do
  @moduledoc false
  @endpoint "wss://api.cartesia.ai/stt/turns/websocket"
  @types %{
    "connected" => :ready,
    "turn.start" => :speech_started,
    "turn.update" => :transcript,
    "turn.eager_end" => :eager_turn_ended,
    "turn.resume" => :turn_resumed,
    "turn.end" => :turn_ended
  }
  @enforce_keys [:api_key, :model, :encoding, :sample_rate]
  @derive {Inspect, only: [:model, :encoding, :sample_rate]}
  defstruct @enforce_keys ++ [endpoint: @endpoint]

  alias Vxpipe.CallEngine.Speech.Model

  def models do
    [
      Model.new("ink-2", "Ink 2", true)
    ]
  end

  def new(options) when is_list(options) do
    with true <- Keyword.keyword?(options),
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
         true <- length(options) == length(Enum.uniq(Keyword.keys(options))),
         {:ok, options} <-
           Keyword.validate(options, model: "ink-2", encoding: :linear16, sample_rate: 16_000),
         model <- Keyword.fetch!(options, :model),
         true <- Model.supported?(models(), model),
         :linear16 <- Keyword.fetch!(options, :encoding),
         16_000 <- Keyword.fetch!(options, :sample_rate) do
      {:ok, %{model: model, encoding: :linear16, sample_rate: 16_000}}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def public_options(_options), do: {:error, :invalid_configuration}

  def connection_options(%__MODULE__{} = config) do
    query =
      URI.encode_query(
        model: config.model,
        encoding: "pcm_s16le",
        sample_rate: config.sample_rate
      )

    %{
      url: config.endpoint <> "?" <> query,
      headers: [
        {"authorization", "Bearer " <> config.api_key},
        {"cartesia-version", "2026-08-14"}
      ]
    }
  end

  def validate_audio(audio)
      when is_binary(audio) and byte_size(audio) in 1..32_000 and rem(byte_size(audio), 2) == 0,
      do: :ok

  def validate_audio(_audio), do: {:error, :invalid_audio}

  def decode(payload) when is_binary(payload) and byte_size(payload) <= 262_144 do
    case JSON.decode(payload) do
      {:ok, %{"type" => "error"}} ->
        {:error, :provider_failure}

      {:ok, %{"type" => type, "request_id" => request_id} = message} ->
        with {:ok, kind} <- Map.fetch(@types, type),
             true <- valid_id?(request_id),
             {:ok, text} <- transcript(kind, message) do
          {:ok, {kind, request_id, text}}
        else
          _invalid -> {:error, :invalid_message}
        end

      _invalid ->
        {:error, :invalid_message}
    end
  end

  def decode(_payload), do: {:error, :invalid_message}

  defp valid_id?(id), do: is_binary(id) and byte_size(id) in 1..256 and String.valid?(id)

  defp transcript(kind, message) when kind in [:transcript, :eager_turn_ended, :turn_ended] do
    case message do
      %{"transcript" => text} when is_binary(text) and byte_size(text) <= 65_536 ->
        if String.valid?(text), do: {:ok, text}, else: {:error, :invalid_message}

      _invalid ->
        {:error, :invalid_message}
    end
  end

  defp transcript(_kind, _message), do: {:ok, nil}
end
