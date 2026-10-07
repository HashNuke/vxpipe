defmodule Vxpipe.CallEngine.CapabilityCatalog do
  @moduledoc "Closed mapping from inline capability selections to internal adapters."

  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.Providers.Deepgram
  alias Vxpipe.Providers.Google.TTS, as: GoogleTTS
  alias Vxpipe.Providers.Google.TTSSession, as: GoogleTTSSession
  alias Vxpipe.Providers.Google.STT, as: GoogleSTT
  alias Vxpipe.Providers.Google.STTSession, as: GoogleSTTSession
  alias Vxpipe.Providers.Google.STS, as: GoogleSTS
  alias Vxpipe.Providers.Google.STSSession, as: GoogleSTSSession
  alias Vxpipe.Providers.Cartesia.TTS, as: CartesiaTTS
  alias Vxpipe.Providers.Cartesia.TTSSession, as: CartesiaTTSSession
  alias Vxpipe.Providers.Cartesia.STT, as: CartesiaSTT
  alias Vxpipe.Providers.Cartesia.STTSession, as: CartesiaSTTSession
  alias Vxpipe.Providers.ElevenLabs.TTS, as: ElevenLabsTTS
  alias Vxpipe.Providers.ElevenLabs.TTSSession, as: ElevenLabsTTSSession
  alias Vxpipe.Providers.ElevenLabs.{Scribe, STTSession}
  alias Vxpipe.Providers.Rime.{TTS, TTSSession}
  alias Vxpipe.Providers.Registry
  alias Vxpipe.Providers.MorseCode.DuplexSTSSession
  alias Vxpipe.Providers.OpenAI.{GPTLive, GPTLiveSession}

  @morse_keys [
    :amplitude,
    :detection_threshold,
    :end_gap_units,
    :frequency_hz,
    :frequency_tolerance_hz,
    :maximum_audio_bytes,
    :maximum_text_bytes,
    :maximum_utterance_ms,
    :sample_rate,
    :unit_duration_ms,
    :window_duration_ms
  ]

  def validate(%CapabilitySelection{kind: :output_speech_to_text} = selection),
    do: validate(%{selection | kind: :speech_to_text})

  def validate(%CapabilitySelection{kind: :model_inference, provider: provider} = selection)
      when provider in ["google", "zenmux", "openai", "deepseek", "openrouter", "fireworks"] do
    case Vxpipe.AgentRuntime.ProviderSelection.translate(
           selection.provider,
           selection.model,
           selection.options,
           selection.provider_options
         ) do
      {:ok, _options} -> :ok
      {:error, _reason} -> {:error, :unsupported_capability}
    end
  end

  def validate(%CapabilitySelection{
        kind: :model_inference,
        provider: "fixture",
        credential_name: nil,
        options: options,
        provider_options: specific
      })
      when map_size(options) == 0 and map_size(specific) == 0, do: :ok

  def validate(%CapabilitySelection{provider_options: specific} = selection)
      when map_size(specific) == 0 do
    with {:ok, options} <- speech_options(selection) do
      validate_speech(selection, options)
    end
  end

  def validate(_selection), do: {:error, :unsupported_capability}

  def adapter(%CapabilitySelection{kind: :model_inference, provider: provider})
      when provider in ["google", "zenmux", "openai", "deepseek", "openrouter", "fireworks"],
      do: {:ok, Vxpipe.AgentRuntime.Provider.ReqLLM}

  def adapter(%CapabilitySelection{kind: :speech_to_text, provider: "deepgram"}),
    do: Registry.resolve_capability("deepgram", :stt)

  def adapter(%CapabilitySelection{kind: :speech_to_text, provider: "google"}),
    do: Registry.resolve_capability("google", :stt)

  def adapter(%CapabilitySelection{kind: :speech_to_text, provider: "cartesia"}),
    do: Registry.resolve_capability("cartesia", :stt)

  def adapter(%CapabilitySelection{kind: :speech_to_text, provider: "elevenlabs"}),
    do: Registry.resolve_capability("elevenlabs", :stt)

  def adapter(%CapabilitySelection{kind: :text_to_speech, provider: "deepgram"}),
    do: Registry.resolve_capability("deepgram", :tts)

  def adapter(%CapabilitySelection{kind: :text_to_speech, provider: "rime"}),
    do: Registry.resolve_capability("rime", :tts)

  def adapter(%CapabilitySelection{kind: :text_to_speech, provider: "google"}),
    do: Registry.resolve_capability("google", :tts)

  def adapter(%CapabilitySelection{kind: :text_to_speech, provider: "cartesia"}),
    do: Registry.resolve_capability("cartesia", :tts)

  def adapter(%CapabilitySelection{kind: :text_to_speech, provider: "elevenlabs"}),
    do: Registry.resolve_capability("elevenlabs", :tts)

  def adapter(%CapabilitySelection{kind: :speech_to_text, provider: "morse"}),
    do: Registry.resolve_capability("morse", :stt)

  def adapter(%CapabilitySelection{kind: :speech_to_speech, provider: "deepgram"}),
    do: Registry.resolve_capability("deepgram", :sts)

  def adapter(%CapabilitySelection{kind: :speech_to_speech, provider: "google"}),
    do: Registry.resolve_capability("google", :sts)

  def adapter(%CapabilitySelection{kind: :speech_to_speech, provider: "rime"}),
    do: Registry.resolve_capability("rime", :sts)

  def adapter(%CapabilitySelection{kind: :speech_to_speech, provider: "openai"}),
    do: Registry.resolve_capability("openai", :sts)

  def adapter(%CapabilitySelection{
        kind: :speech_to_speech,
        provider: "morse",
        model: "morse-duplex"
      }),
      do: {:ok, DuplexSTSSession}

  def adapter(%CapabilitySelection{kind: :speech_to_speech, provider: "morse"}),
    do: Registry.resolve_capability("morse", :sts)

  def adapter(%CapabilitySelection{kind: :output_speech_to_text} = selection),
    do: adapter(%{selection | kind: :speech_to_text})

  def adapter(%CapabilitySelection{kind: :text_to_speech, provider: "morse"}),
    do: Registry.resolve_capability("morse", :tts)

  def adapter(_selection), do: {:error, :unsupported_capability}

  @doc false
  def provider_settings(settings, provider, :output_speech_to_text),
    do: provider_settings(settings, provider, :speech_to_text)

  def provider_settings(settings, provider, kind) when is_list(settings) do
    with {:ok, settings} <- Keyword.validate(settings, providers: %{}),
         providers when is_map(providers) <- Keyword.fetch!(settings, :providers),
         {:ok, providers} <- validate_provider_registry(providers, kind),
         {:ok, provider_settings} when is_list(provider_settings) <-
           Map.fetch(providers, provider) do
      {:ok, provider_settings}
    else
      _missing_or_invalid -> {:error, :provider_not_configured}
    end
  end

  def provider_settings(_settings, _provider, _kind), do: {:error, :provider_not_configured}

  def credential_required?(%CapabilitySelection{provider: provider}),
    do: provider not in ["fixture", "morse"]

  defp speech_adapters(:speech_to_text) do
    {:ok, deepgram} = Registry.fetch_capability("deepgram", :stt)
    {:ok, google} = Registry.fetch_capability("google", :stt)
    {:ok, cartesia} = Registry.fetch_capability("cartesia", :stt)
    {:ok, elevenlabs} = Registry.fetch_capability("elevenlabs", :stt)
    {:ok, morse} = Registry.fetch_capability("morse", :stt)

    [
      deepgram,
      google,
      cartesia,
      elevenlabs,
      morse,
      Vxpipe.CallEngine.Provider.MorseCodeSTT.Session
    ]
  end

  defp speech_adapters(:text_to_speech) do
    {:ok, deepgram} = Registry.fetch_capability("deepgram", :tts)
    {:ok, rime} = Registry.fetch_capability("rime", :tts)
    {:ok, google} = Registry.fetch_capability("google", :tts)
    {:ok, cartesia} = Registry.fetch_capability("cartesia", :tts)
    {:ok, elevenlabs} = Registry.fetch_capability("elevenlabs", :tts)
    {:ok, morse} = Registry.fetch_capability("morse", :tts)

    [
      deepgram,
      rime,
      google,
      cartesia,
      elevenlabs,
      morse,
      Vxpipe.CallEngine.Provider.MorseCodeTTS.Session
    ]
  end

  defp speech_adapters(:speech_to_speech) do
    {:ok, morse} = Registry.fetch_capability("morse", :sts)
    {:ok, openai} = Registry.fetch_capability("openai", :sts)
    {:ok, google} = Registry.fetch_capability("google", :sts)
    [morse, DuplexSTSSession, openai, google]
  end

  defp speech_adapters(_kind), do: []

  defp validate_provider_registry(providers, kind) do
    Enum.reduce_while(providers, {:ok, %{}}, fn {provider, settings}, {:ok, validated} ->
      with true <- provider in speech_adapters(kind),
           true <- is_list(settings),
           {:ok, settings} <- validate_provider_settings(provider, kind, settings) do
        {:cont, {:ok, Map.put(validated, provider, settings)}}
      else
        _invalid -> {:halt, {:error, :provider_not_configured}}
      end
    end)
  end

  defp validate_provider_settings(Deepgram.STTSession, :speech_to_text, settings) do
    Deepgram.Speech.settings(:speech_to_text, settings)
  end

  defp validate_provider_settings(GoogleSTTSession, :speech_to_text, settings) do
    Keyword.validate(settings,
      enabled: false,
      media_ingress: nil,
      wire_module: Vxpipe.Providers.Google.STTSocket,
      wire_options: []
    )
  end

  defp validate_provider_settings(CartesiaSTTSession, :speech_to_text, settings) do
    Keyword.validate(settings,
      enabled: false,
      media_ingress: nil,
      wire_module: Vxpipe.Providers.Cartesia.STTSocket,
      wire_options: []
    )
  end

  defp validate_provider_settings(STTSession, :speech_to_text, settings) do
    Keyword.validate(settings,
      enabled: false,
      media_ingress: nil,
      wire_module: Vxpipe.Providers.ElevenLabs.ScribeSocket,
      wire_options: [],
      activity_options: []
    )
  end

  defp validate_provider_settings(
         Vxpipe.CallEngine.Provider.MorseCodeSTT.Session,
         :speech_to_text,
         settings
       ),
       do: Keyword.validate(settings, enabled: false, media_ingress: nil)

  defp validate_provider_settings(
         Vxpipe.Providers.MorseCode.STTSession,
         :speech_to_text,
         settings
       ),
       do: Keyword.validate(settings, enabled: false, media_ingress: nil)

  defp validate_provider_settings(Deepgram.TTSSession, :text_to_speech, settings) do
    Deepgram.Speech.settings(:text_to_speech, settings)
  end

  defp validate_provider_settings(TTSSession, :text_to_speech, settings),
    do: Keyword.validate(settings, enabled: false, maximum_requests: nil)

  defp validate_provider_settings(GoogleTTSSession, :text_to_speech, settings),
    do:
      Keyword.validate(settings,
        enabled: false,
        maximum_requests: nil,
        request_module: Vxpipe.Providers.Google.TTSRequest
      )

  defp validate_provider_settings(CartesiaTTSSession, :text_to_speech, settings),
    do:
      Keyword.validate(settings,
        enabled: false,
        maximum_requests: nil,
        request_module: Vxpipe.Providers.Cartesia.TTSRequest
      )

  defp validate_provider_settings(ElevenLabsTTSSession, :text_to_speech, settings),
    do:
      Keyword.validate(settings,
        enabled: false,
        maximum_requests: nil,
        request_module: Vxpipe.Providers.ElevenLabs.TTSRequest
      )

  defp validate_provider_settings(
         Vxpipe.CallEngine.Provider.MorseCodeTTS.Session,
         :text_to_speech,
         settings
       ),
       do: Keyword.validate(settings, enabled: false, maximum_requests: nil)

  defp validate_provider_settings(
         Vxpipe.Providers.MorseCode.TTSSession,
         :text_to_speech,
         settings
       ),
       do: Keyword.validate(settings, enabled: false, maximum_requests: nil)

  defp validate_provider_settings(
         Vxpipe.Providers.MorseCode.STSSession,
         :speech_to_speech,
         settings
       ),
       do: Keyword.validate(settings, enabled: false)

  defp validate_provider_settings(DuplexSTSSession, :speech_to_speech, settings),
    do: Keyword.validate(settings, enabled: false)

  defp validate_provider_settings(GPTLiveSession, :speech_to_speech, settings),
    do: Keyword.validate(settings, enabled: false)

  defp validate_provider_settings(GoogleSTSSession, :speech_to_speech, settings),
    do: Keyword.validate(settings, enabled: false)

  defp validate_provider_settings(_provider, _kind, _settings),
    do: {:error, :provider_not_configured}

  def speech_options(%CapabilitySelection{kind: :output_speech_to_text} = selection),
    do: speech_options(%{selection | kind: :speech_to_text})

  def speech_options(%CapabilitySelection{
        provider: "deepgram",
        kind: kind,
        model: model,
        options: input
      }) do
    Deepgram.Speech.selection_options(kind, model, input)
  end

  def speech_options(%CapabilitySelection{
        provider: "google",
        kind: :speech_to_text,
        model: "gemini-3.5-transcribe-live",
        options: input
      }) do
    with {:ok, options} <- normalize(input, [:encoding, :sample_rate]),
         {:ok, public} <-
           GoogleSTT.public_options(Keyword.put(options, :model, "gemini-3.5-transcribe-live")) do
      {:ok, [model: public.model, encoding: public.encoding, sample_rate: public.sample_rate]}
    end
  end

  def speech_options(%CapabilitySelection{
        provider: "rime",
        kind: :text_to_speech,
        model: "coda",
        options: input
      }) do
    with {:ok, options} <- normalize(input, [:speaker, :sample_rate]),
         {:ok, public} <- TTS.public_options(Keyword.put(options, :model, "coda")) do
      {:ok, [model: public.model, speaker: public.speaker, sample_rate: public.sample_rate]}
    end
  end

  def speech_options(%CapabilitySelection{
        provider: "cartesia",
        kind: :speech_to_text,
        model: model,
        options: input
      }) do
    with {:ok, options} <- normalize(input, [:encoding, :sample_rate]),
         {:ok, public} <- CartesiaSTT.public_options(Keyword.put(options, :model, model)) do
      {:ok, [model: public.model, encoding: public.encoding, sample_rate: public.sample_rate]}
    end
  end

  def speech_options(%CapabilitySelection{
        provider: "elevenlabs",
        kind: :speech_to_text,
        model: model,
        options: input
      }) do
    with {:ok, options} <- normalize(input, [:language_code]),
         {:ok, public} <- Scribe.public_options(Keyword.put(options, :model, model)) do
      {:ok,
       [
         model: public.model,
         encoding: public.encoding,
         sample_rate: public.sample_rate,
         language_code: public.language_code,
         commit_strategy: public.commit_strategy
       ]}
    end
  end

  def speech_options(%CapabilitySelection{
        provider: "google",
        kind: :text_to_speech,
        model: "gemini-3.1-flash-tts-preview",
        options: input
      }) do
    with {:ok, options} <- normalize(input, [:voice]),
         {:ok, public} <-
           GoogleTTS.public_options(Keyword.put(options, :model, "gemini-3.1-flash-tts-preview")) do
      {:ok, [model: public.model, voice: public.voice]}
    end
  end

  def speech_options(%CapabilitySelection{
        provider: "cartesia",
        kind: :text_to_speech,
        model: model,
        options: input
      }) do
    with {:ok, options} <- normalize(input, [:voice, :sample_rate]),
         {:ok, public} <- CartesiaTTS.public_options(Keyword.put(options, :model, model)) do
      {:ok, [model: public.model, voice: public.voice, sample_rate: public.sample_rate]}
    end
  end

  def speech_options(%CapabilitySelection{
        provider: "elevenlabs",
        kind: :text_to_speech,
        model: model,
        options: input
      }) do
    with {:ok, options} <- normalize(input, [:voice, :sample_rate]),
         {:ok, public} <- ElevenLabsTTS.public_options(Keyword.put(options, :model, model)) do
      {:ok, [model: public.model, voice: public.voice, sample_rate: public.sample_rate]}
    end
  end

  def speech_options(%CapabilitySelection{
        kind: :speech_to_speech,
        provider: "google",
        model: "gemini-3.8-live",
        options: input
      }) do
    with {:ok, options} <- normalize(input, [:voice, :turn_control]),
         {:ok, public} <-
           GoogleSTS.public_options(Keyword.put(options, :model, "gemini-3.8-live")) do
      {:ok, [model: public.model, voice: public.voice, turn_control: public.turn_control]}
    end
  end

  def speech_options(%CapabilitySelection{
        kind: :speech_to_speech,
        provider: "openai",
        model: "gpt-live-1",
        options: input
      }) do
    with {:ok, options} <- normalize(input, [:voice, :backend_model]),
         {:ok, public} <- GPTLive.public_options(Keyword.put(options, :model, "gpt-live-1")) do
      {:ok, [model: public.model, voice: public.voice, backend_model: public.backend_model]}
    end
  end

  def speech_options(%CapabilitySelection{
        kind: :speech_to_speech,
        provider: "morse",
        model: "morse-duplex",
        options: input
      }) do
    with {:ok, options} <- normalize(input, @morse_keys ++ [:output_transcript]),
         :ok <- validate_output_transcript(options) do
      {:ok, options}
    end
  end

  def speech_options(%CapabilitySelection{
        kind: :speech_to_speech,
        provider: "morse",
        model: "morse",
        options: input
      }) do
    with {:ok, options} <- normalize(input, @morse_keys ++ [:turn_control, :output_transcript]),
         :ok <- validate_turn_control(options),
         :ok <- validate_output_transcript(options) do
      {:ok, options}
    end
  end

  def speech_options(%CapabilitySelection{provider: "morse", model: "morse", options: input}),
    do: normalize(input, @morse_keys)

  def speech_options(%CapabilitySelection{kind: kind, provider: "morse"})
      when kind in [:speech_to_speech, :output_speech_to_text] do
    {:error, :unsupported_capability}
  end

  def speech_options(_selection), do: {:error, :unsupported_capability}

  defp validate_output_transcript(options) do
    case Keyword.fetch(options, :output_transcript) do
      {:ok, value} when is_boolean(value) -> :ok
      {:ok, _value} -> {:error, :unsupported_capability}
      :error -> :ok
    end
  end

  defp validate_turn_control(options) do
    case Keyword.fetch(options, :turn_control) do
      {:ok, mode} when mode in ["provider", "external", "hybrid"] -> :ok
      {:ok, _mode} -> {:error, :unsupported_capability}
      :error -> :ok
    end
  end

  defp validate_speech(%{provider: "morse", credential_name: nil, kind: kind}, options)
       when kind in [:speech_to_text, :output_speech_to_text] do
    validate_provider(Vxpipe.Providers.MorseCode.STTSession, options)
  end

  defp validate_speech(
         %{
           provider: "morse",
           credential_name: nil,
           kind: :speech_to_speech,
           model: "morse-duplex"
         },
         options
       ) do
    validate_provider(DuplexSTSSession, options)
  end

  defp validate_speech(
         %{provider: "morse", credential_name: nil, kind: :speech_to_speech},
         options
       ) do
    validate_provider(Vxpipe.Providers.MorseCode.STSSession, options)
  end

  defp validate_speech(%{provider: "morse", credential_name: nil, kind: :text_to_speech}, options) do
    validate_provider(Vxpipe.Providers.MorseCode.TTSSession, options)
  end

  defp validate_speech(%{provider: "deepgram", kind: :speech_to_text}, options),
    do: Deepgram.Flux.validate_options(options)

  defp validate_speech(%{provider: "google", kind: :speech_to_text}, options),
    do: validate_provider(GoogleSTTSession, options)

  defp validate_speech(%{provider: "cartesia", kind: :speech_to_text}, options),
    do: validate_provider(CartesiaSTTSession, options)

  defp validate_speech(%{provider: "elevenlabs", kind: :speech_to_text}, options),
    do: validate_provider(STTSession, options)

  defp validate_speech(%{provider: "deepgram", kind: :text_to_speech}, options),
    do: validate_provider(Deepgram.TTSSession, options)

  defp validate_speech(%{provider: "rime", kind: :text_to_speech}, options),
    do: validate_provider(TTSSession, options)

  defp validate_speech(%{provider: "google", kind: :text_to_speech}, options),
    do: validate_provider(GoogleTTSSession, options)

  defp validate_speech(%{provider: "cartesia", kind: :text_to_speech}, options),
    do: validate_provider(CartesiaTTSSession, options)

  defp validate_speech(%{provider: "elevenlabs", kind: :text_to_speech}, options),
    do: validate_provider(ElevenLabsTTSSession, options)

  defp validate_speech(%{provider: "openai", kind: :speech_to_speech}, options) do
    case GPTLive.public_options(options) do
      {:ok, _public} -> :ok
      {:error, _reason} -> {:error, :unsupported_capability}
    end
  end

  defp validate_speech(%{provider: "google", kind: :speech_to_speech}, options),
    do: validate_provider(GoogleSTSSession, options)

  defp validate_speech(_selection, _options), do: {:error, :unsupported_capability}

  defp validate_provider(provider, options) do
    case provider.configure(options) do
      {:ok, _descriptor} -> :ok
      {:error, _reason} -> {:error, :unsupported_capability}
    end
  end

  defp normalize(input, allowed) when is_map(input) do
    Enum.reduce_while(input, {:ok, []}, fn {key, value}, {:ok, acc} ->
      case Enum.find(allowed, &(Atom.to_string(&1) == key)) do
        nil -> {:halt, {:error, :unsupported_capability}}
        key -> {:cont, {:ok, [{key, value} | acc]}}
      end
    end)
  end

  defp normalize(_input, _allowed), do: {:error, :unsupported_capability}
end
