defmodule Vxpipe.Providers.MorseCodeApi.STT do
  @moduledoc false
  alias Vxpipe.CallEngine.Speech.Model
  alias Vxpipe.Providers.ElevenLabs.STTProtocol
  alias Vxpipe.Providers.MorseCodeApi.{Credential, Endpoint}

  @enforce_keys [:api_key, :endpoint, :model, :encoding, :sample_rate]
  @derive {Inspect, only: [:model, :encoding, :sample_rate]}
  defstruct @enforce_keys

  @profile %{
    "model_id" => "morse_stt_v1",
    "sample_rate" => 16_000,
    "audio_format" => "pcm_16000",
    "commit_strategy" => "vad",
    "vad_silence_threshold_secs" => 0.84
  }

  def models, do: [Model.new("morse_stt_v1", "MorseCodeApiSTT", true)]

  def new(options) do
    with {:ok, endpoint} <- Endpoint.configured(), do: new(options, endpoint)
  end

  def new(options, %Endpoint{} = endpoint) when is_list(options) do
    with true <- Keyword.keyword?(options) and unique_options?(options),
         {:ok, public} <- public_options(Keyword.drop(options, [:api_key])),
         key <- Keyword.get(options, :api_key),
         :ok <- Credential.validate("api_key", %{"api_key" => key}) do
      {:ok, struct(__MODULE__, Map.merge(public, %{api_key: key, endpoint: endpoint.websocket}))}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def new(_options, _endpoint), do: {:error, :invalid_configuration}

  def public_options(options) when is_list(options) do
    with true <- Keyword.keyword?(options) and unique_options?(options),
         {:ok, options} <-
           Keyword.validate(options,
             model: "morse_stt_v1",
             encoding: :linear16,
             sample_rate: 16_000
           ),
         "morse_stt_v1" <- Keyword.fetch!(options, :model),
         :linear16 <- Keyword.fetch!(options, :encoding),
         16_000 <- Keyword.fetch!(options, :sample_rate) do
      {:ok, Map.new(options)}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def public_options(_options), do: {:error, :invalid_configuration}

  def connection_options(%__MODULE__{} = config) do
    query =
      @profile
      |> Map.delete("sample_rate")
      |> Map.merge(%{"include_timestamps" => false, "enable_logging" => false})
      |> URI.encode_query()

    %{
      url: config.endpoint <> "/v1/speech-to-text/realtime?" <> query,
      headers: [{"xi-api-key", config.api_key}]
    }
  end

  defdelegate encode_audio(audio), to: STTProtocol
  defdelegate keepalive(), to: STTProtocol

  def decode(payload) do
    case STTProtocol.decode(payload) do
      {:ok, {:ready, session_id, config}} ->
        if Enum.all?(@profile, fn {key, value} -> Map.fetch(config, key) == {:ok, value} end),
          do: {:ok, {:ready, session_id}},
          else: {:error, :invalid_message}

      event ->
        event
    end
  end

  defp unique_options?(options),
    do: length(options) == length(Enum.uniq(Keyword.keys(options)))
end
