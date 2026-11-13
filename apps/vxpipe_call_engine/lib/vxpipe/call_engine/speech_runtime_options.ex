defmodule Vxpipe.CallEngine.SpeechRuntimeOptions do
  @moduledoc "Internal speech transport defaults and explicit per-call test overrides."

  alias Vxpipe.CallEngine.Speech.ContextTTSSocket
  alias Vxpipe.Providers.MorseCode.DuplexSTSSession
  alias Vxpipe.Providers.Deepgram
  alias Vxpipe.Providers.Google.STTSession, as: GoogleSTTSession
  alias Vxpipe.Providers.Google.TTSSession, as: GoogleTTSSession
  alias Vxpipe.Providers.Google.STSSession, as: GoogleSTSSession
  alias Vxpipe.Providers.Cartesia.STTSession, as: CartesiaSTTSession
  alias Vxpipe.Providers.Cartesia.TTSSession, as: CartesiaTTSSession
  alias Vxpipe.Providers.ElevenLabs.TTSSession, as: ElevenLabsTTSSession
  alias Vxpipe.Providers.ElevenLabs.{STTSession, RealtimeSession}
  alias Vxpipe.Providers.MorseCodeApi.STTSession, as: MorseCodeApiSTTSession
  alias Vxpipe.Providers.MorseCodeApi.TTSSession, as: MorseCodeApiTTSSession
  alias Vxpipe.Providers.OpenAI.GPTLiveSession
  alias Vxpipe.Providers.Rime.TTSSession

  @media_ingress [
    maximum_frames: 50,
    maximum_bytes: 262_144,
    maximum_age_ms: 2_000,
    maximum_consecutive_overflows: 5
  ]

  def resolve(overrides, provider, :output_speech_to_text),
    do: resolve(overrides, provider, :speech_to_text)

  def resolve(nil, provider, kind), do: resolve([], provider, kind)

  def resolve(overrides, provider, kind) when is_list(overrides) do
    with {:ok, overrides} <- Keyword.validate(overrides, providers: %{}),
         providers when is_map(providers) <- Keyword.fetch!(overrides, :providers),
         settings when is_list(settings) <- Map.get(providers, provider, []),
         true <- Keyword.keyword?(settings) do
      # Retired enablement flags in old test overrides have no authority.
      settings = settings |> Keyword.delete(:enabled) |> defaults(kind)
      validate_options(provider, kind, settings)
    else
      _invalid -> {:error, :invalid_speech_runtime_options}
    end
  end

  def resolve(_overrides, _provider, _kind), do: {:error, :invalid_speech_runtime_options}

  defp defaults(settings, :speech_to_text),
    do: Keyword.put_new(settings, :media_ingress, @media_ingress)

  defp defaults(settings, :text_to_speech),
    do: Keyword.put_new(settings, :maximum_requests, 4)

  defp defaults(settings, _kind), do: settings

  defp validate_options(Deepgram.STTSession, :speech_to_text, settings) do
    Keyword.validate(settings,
      media_ingress: nil,
      wire_module: Deepgram.STTSocket,
      wire_options: []
    )
  end

  defp validate_options(GoogleSTTSession, :speech_to_text, settings) do
    Keyword.validate(settings,
      media_ingress: nil,
      wire_module: Vxpipe.Providers.Google.STTSocket,
      wire_options: []
    )
  end

  defp validate_options(CartesiaSTTSession, :speech_to_text, settings) do
    Keyword.validate(settings,
      media_ingress: nil,
      wire_module: Vxpipe.Providers.Cartesia.STTSocket,
      wire_options: []
    )
  end

  defp validate_options(STTSession, :speech_to_text, settings) do
    Keyword.validate(settings,
      media_ingress: nil,
      wire_module: Vxpipe.Providers.ElevenLabs.ScribeSocket,
      wire_options: [],
      activity_options: []
    )
  end

  defp validate_options(MorseCodeApiSTTSession, :speech_to_text, settings) do
    Keyword.validate(settings,
      media_ingress: nil,
      wire_module: Vxpipe.Providers.MorseCodeApi.STTSocket,
      wire_options: []
    )
  end

  defp validate_options(
         Vxpipe.CallEngine.Provider.MorseCodeSTT.Session,
         :speech_to_text,
         settings
       ),
       do: Keyword.validate(settings, media_ingress: nil)

  defp validate_options(
         Vxpipe.Providers.MorseCode.STTSession,
         :speech_to_text,
         settings
       ),
       do: Keyword.validate(settings, media_ingress: nil)

  defp validate_options(Deepgram.TTSSession, :text_to_speech, settings) do
    Keyword.validate(settings,
      maximum_requests: nil,
      wire_module: Deepgram.TTSSocket,
      wire_options: []
    )
  end

  defp validate_options(TTSSession, :text_to_speech, settings),
    do: Keyword.validate(settings, maximum_requests: nil)

  defp validate_options(GoogleTTSSession, :text_to_speech, settings),
    do:
      Keyword.validate(settings,
        maximum_requests: nil,
        request_module: Vxpipe.Providers.Google.TTSRequest
      )

  defp validate_options(CartesiaTTSSession, :text_to_speech, settings),
    do:
      Keyword.validate(settings,
        maximum_requests: nil,
        wire_module: ContextTTSSocket,
        wire_options: []
      )

  defp validate_options(ElevenLabsTTSSession, :text_to_speech, settings),
    do:
      Keyword.validate(settings,
        maximum_requests: nil,
        wire_module: ContextTTSSocket,
        wire_options: []
      )

  defp validate_options(MorseCodeApiTTSSession, :text_to_speech, settings),
    do:
      Keyword.validate(settings,
        maximum_requests: nil,
        wire_module: ContextTTSSocket,
        wire_options: []
      )

  defp validate_options(
         Vxpipe.CallEngine.Provider.MorseCodeTTS.Session,
         :text_to_speech,
         settings
       ),
       do: Keyword.validate(settings, maximum_requests: nil)

  defp validate_options(
         Vxpipe.Providers.MorseCode.TTSSession,
         :text_to_speech,
         settings
       ),
       do: Keyword.validate(settings, maximum_requests: nil)

  defp validate_options(
         Vxpipe.Providers.MorseCode.STSSession,
         :speech_to_speech,
         settings
       ),
       do: Keyword.validate(settings, [])

  defp validate_options(DuplexSTSSession, :speech_to_speech, settings),
    do: Keyword.validate(settings, [])

  defp validate_options(GPTLiveSession, :speech_to_speech, settings),
    do: Keyword.validate(settings, [])

  defp validate_options(GoogleSTSSession, :speech_to_speech, settings),
    do: Keyword.validate(settings, [])

  defp validate_options(RealtimeSession, :speech_to_speech, settings),
    do: Keyword.validate(settings, [])

  defp validate_options(_provider, _kind, _settings),
    do: {:error, :invalid_speech_runtime_options}
end
