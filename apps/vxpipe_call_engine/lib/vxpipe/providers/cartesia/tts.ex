defmodule Vxpipe.Providers.Cartesia.TTS do
  @moduledoc false
  @endpoint "https://api.cartesia.ai/tts/bytes"
  @websocket_endpoint "wss://api.cartesia.ai/tts/websocket"
  @cartesia_version "2026-08-14"
  @rates [8_000, 16_000, 24_000, 48_000]
  @enforce_keys [:api_key, :model, :voice, :sample_rate]
  @derive {Inspect, only: [:model, :voice, :sample_rate]}
  defstruct @enforce_keys ++ [endpoint: @endpoint]

  alias Vxpipe.CallEngine.Speech.Model

  def models do
    [
      Model.new(
        "sonic-3.6",
        "Sonic 3.6",
        true,
        Model.free_voice("db6b0ed5-d5d3-463d-ae85-518a07d3c2b4")
      ),
      Model.new(
        "sonic-3.6-2026-08-27",
        "Sonic 3.6 (2026-08-27)",
        false,
        Model.free_voice("db6b0ed5-d5d3-463d-ae85-518a07d3c2b4")
      ),
      Model.new(
        "sonic-3.5",
        "Sonic 3.5",
        false,
        Model.free_voice("db6b0ed5-d5d3-463d-ae85-518a07d3c2b4")
      ),
      Model.new(
        "sonic-3",
        "Sonic 3",
        false,
        Model.free_voice("db6b0ed5-d5d3-463d-ae85-518a07d3c2b4")
      )
    ]
  end

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
         true <- Model.supported?(models(), model),
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

  def cartesia_version, do: @cartesia_version

  def connection_options(%__MODULE__{} = config) do
    %{
      url: websocket_url(config) <> "?cartesia_version=" <> @cartesia_version,
      headers: [
        {"authorization", "Bearer " <> config.api_key},
        {"cartesia-version", @cartesia_version}
      ]
    }
  end

  def new_context_id,
    do: {:ok, "ctx_" <> Base.encode16(:crypto.strong_rand_bytes(9), case: :lower)}

  def open_utterance(%__MODULE__{} = config, context, text)
      when is_binary(context) and is_binary(text) do
    [
      JSON.encode!(%{
        "model_id" => config.model,
        "transcript" => text,
        "voice" => %{"id" => config.voice},
        "output_format" => %{
          "container" => "raw",
          "encoding" => "pcm_s16le",
          "sample_rate" => config.sample_rate
        },
        "context_id" => context,
        "continue" => false
      })
    ]
  end

  def close_utterance(%__MODULE__{}, context) when is_binary(context),
    do: JSON.encode!(%{"context_id" => context, "cancel" => true})

  def close_socket(%__MODULE__{}), do: nil
  def keepalive_payload(%__MODULE__{}, _context), do: nil

  def decode_frame(payload) when is_binary(payload) and byte_size(payload) <= 65_536 do
    case JSON.decode(payload) do
      {:ok, %{"type" => "chunk", "data" => encoded, "done" => done, "context_id" => context}}
      when is_binary(encoded) and is_binary(context) and is_boolean(done) ->
        with {:ok, pcm} <- Base.decode64(encoded),
             {:audio, pcm} <- validate_audio(pcm) do
          if done,
            do: {:ok, {:audio_final, context, pcm}},
            else: {:ok, {:audio, context, pcm}}
        else
          _invalid -> {:error, :invalid_message}
        end

      {:ok, %{"type" => "done", "done" => true, "context_id" => context}}
      when is_binary(context) ->
        {:ok, {:final, context}}

      {:ok, %{"type" => type}} when type in ["timestamps", "phoneme_timestamps", "flush_done"] ->
        {:ok, :ignore}

      {:ok, %{"type" => "error"}} ->
        {:error, :provider_failure}

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

  defp websocket_url(%__MODULE__{endpoint: @endpoint}), do: @websocket_endpoint

  defp websocket_url(%__MODULE__{endpoint: endpoint}) do
    uri = URI.new!(endpoint)
    scheme = if uri.scheme == "https", do: "wss", else: "ws"

    %{uri | scheme: scheme, path: "/tts/websocket", userinfo: nil, fragment: nil, query: nil}
    |> URI.to_string()
  end
end
