defmodule Vxpipe.Providers.ElevenLabs.Scribe do
  @moduledoc false
  @endpoint "wss://api.elevenlabs.io/v1/speech-to-text/realtime"
  @model "scribe_v2_realtime"
  @vad_profile [
    vad_silence_threshold_secs: 1.5,
    vad_threshold: 0.4,
    min_speech_duration_ms: 100,
    min_silence_duration_ms: 100
  ]
  @errors ~w(auth_error quota_exceeded transcriber_error input_error invalid_request error
    commit_throttled unaccepted_terms rate_limited queue_overflow resource_exhausted
    session_time_limit_exceeded chunk_size_exceeded insufficient_audio_activity)
  @enforce_keys [:api_key, :model, :encoding, :sample_rate, :language_code, :commit_strategy]
  @derive {Inspect, only: [:model, :encoding, :sample_rate, :language_code, :commit_strategy]}
  defstruct @enforce_keys ++ [endpoint: @endpoint]

  def new(options) when is_list(options) do
    with true <- Keyword.keyword?(options) and unique_options?(options),
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
    with true <- Keyword.keyword?(options) and unique_options?(options),
         {:ok, options} <-
           Keyword.validate(options,
             model: @model,
             encoding: :linear16,
             sample_rate: 16_000,
             language_code: nil,
             commit_strategy: :manual
           ),
         @model <- Keyword.fetch!(options, :model),
         :linear16 <- Keyword.fetch!(options, :encoding),
         16_000 <- Keyword.fetch!(options, :sample_rate),
         strategy when strategy in [:manual, :vad] <- Keyword.fetch!(options, :commit_strategy),
         language <- Keyword.fetch!(options, :language_code),
         true <- valid_language?(language) do
      {:ok,
       %{
         model: @model,
         encoding: :linear16,
         sample_rate: 16_000,
         language_code: language,
         commit_strategy: strategy
       }}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def public_options(_options), do: {:error, :invalid_configuration}

  def connection_options(%__MODULE__{} = config) do
    query =
      [
        model_id: config.model,
        audio_format: "pcm_16000",
        commit_strategy: wire_strategy(config.commit_strategy)
      ] ++ vad_options(config.commit_strategy)

    query =
      if config.language_code,
        do: Keyword.put(query, :language_code, config.language_code),
        else: query

    %{
      url: config.endpoint <> "?" <> URI.encode_query(query),
      headers: [{"xi-api-key", config.api_key}]
    }
  end

  def encode_audio(audio)
      when is_binary(audio) and byte_size(audio) in 2..32_000 and rem(byte_size(audio), 2) == 0,
      do: {:ok, input_message(audio, false)}

  def encode_audio(_audio), do: {:error, :invalid_audio}

  def commit, do: input_message("", true)

  def keepalive, do: input_message("", false)

  def decode(payload, commit_strategy \\ :manual)

  def decode(payload, commit_strategy)
      when is_binary(payload) and byte_size(payload) <= 262_144 and
             commit_strategy in [:manual, :vad] do
    case JSON.decode(payload) do
      {:ok, %{"message_type" => type} = message} -> decode_message(type, message, commit_strategy)
      _invalid -> {:error, :invalid_message}
    end
  end

  def decode(_payload, _strategy), do: {:error, :invalid_message}

  defp decode_message(
         "session_started",
         %{"session_id" => session_id, "config" => config},
         strategy
       )
       when is_binary(session_id) and byte_size(session_id) in 1..256 and is_map(config) do
    if String.valid?(session_id) and matching_configuration?(config, strategy),
      do: {:ok, {:ready, session_id}},
      else: {:error, :invalid_message}
  end

  defp decode_message(type, %{"text" => text}, _strategy)
       when type in ["partial_transcript", "committed_transcript"] and is_binary(text) and
              byte_size(text) <= 65_536 do
    if String.valid?(text) do
      kind = if type == "partial_transcript", do: :partial, else: :segment
      {:ok, {kind, text}}
    else
      {:error, :invalid_message}
    end
  end

  defp decode_message(type, _message, _strategy) when type in @errors,
    do: {:error, :provider_failure}

  defp decode_message(_type, _message, _strategy), do: {:error, :invalid_message}

  defp input_message(audio, commit?) do
    JSON.encode!(%{
      "message_type" => "input_audio_chunk",
      "audio_base_64" => Base.encode64(audio),
      "commit" => commit?,
      "sample_rate" => 16_000
    })
  end

  defp unique_options?(options),
    do: length(options) == length(Enum.uniq(Keyword.keys(options)))

  defp matching_configuration?(config, strategy) do
    expected =
      [
        {"model_id", @model},
        {"sample_rate", 16_000},
        {"audio_format", "pcm_16000"},
        {"commit_strategy", wire_strategy(strategy)}
      ] ++
        Enum.map(vad_options(strategy), fn {field, value} -> {Atom.to_string(field), value} end)

    Enum.all?(
      expected,
      fn {field, expected} ->
        case Map.fetch(config, field) do
          {:ok, ^expected} -> true
          :error -> true
          _mismatch -> false
        end
      end
    )
  end

  defp wire_strategy(:manual), do: "manual"
  defp wire_strategy(:vad), do: "vad"

  defp vad_options(:manual), do: []
  defp vad_options(:vad), do: @vad_profile

  defp valid_language?(nil), do: true

  defp valid_language?(language) when is_binary(language),
    do: Regex.match?(~r/\A[a-z]{2,3}\z/, language)

  defp valid_language?(_language), do: false
end
