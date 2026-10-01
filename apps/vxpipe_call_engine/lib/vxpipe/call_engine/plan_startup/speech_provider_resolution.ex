defmodule Vxpipe.CallEngine.PlanStartup.SpeechProviderResolution do
  @moduledoc "Resolves pinned speech selections into privately authenticated provider configuration."

  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.CallEngine.{CapabilityCatalog, CredentialSource}

  def resolve_provider(nil, _tenant_id, _options, _kind), do: {:ok, nil}

  def resolve_provider(
        %CapabilitySelection{} = selection,
        tenant_id,
        options,
        kind
      ) do
    with {:ok, provider} <- CapabilityCatalog.adapter(selection),
         {:ok, settings} <-
           CapabilityCatalog.provider_settings(Keyword.get(options, kind), provider, kind),
         true <- Keyword.get(settings, :enabled) == true,
         {:ok, credential} <- CredentialSource.resolve(tenant_id, selection, options),
         {:ok, selected_options} <- CapabilityCatalog.speech_options(selection),
         {:ok, selected_options} <- authenticate_speech(selected_options, credential),
         true <- Code.ensure_loaded?(provider),
         {:ok, provider_config} <- configure_provider(provider, selected_options, kind) do
      settings =
        if credential do
          identity =
            credential
            |> Vxpipe.CallEngine.ProviderCredential.binding_identity()
            |> Map.put("version", credential.version)

          Keyword.put(settings, :credential_identity, identity)
        else
          settings
        end

      {:ok, {provider, provider_config}, settings}
    else
      _unsupported -> {:error, unsupported_speech_configuration_reason(kind)}
    end
  rescue
    _exception -> {:error, unsupported_speech_configuration_reason(kind)}
  end

  defp configure_provider(provider, options, :speech_to_text) do
    case provider do
      Vxpipe.Providers.Deepgram.STTSession ->
        Vxpipe.Providers.Deepgram.Flux.new(options)

      Vxpipe.Providers.Google.STTSession ->
        Vxpipe.Providers.Google.STT.new(options)

      Vxpipe.Providers.Cartesia.STTSession ->
        Vxpipe.Providers.Cartesia.STT.new(options)

      Vxpipe.Providers.ElevenLabs.STTSession ->
        Vxpipe.Providers.ElevenLabs.Scribe.new(options)

      _other ->
        case provider.configure(options) do
          {:ok, _descriptor} -> {:ok, options}
          {:error, _reason} = error -> error
        end
    end
  end

  defp configure_provider(
         Vxpipe.Providers.Deepgram.TTSSession,
         options,
         :text_to_speech
       ),
       do: Vxpipe.Providers.Deepgram.FluxTextToSpeech.new(options)

  defp configure_provider(Vxpipe.Providers.Rime.TTSSession, options, :text_to_speech),
    do: Vxpipe.Providers.Rime.TTS.new(options)

  defp configure_provider(Vxpipe.Providers.Google.TTSSession, options, :text_to_speech),
    do: Vxpipe.Providers.Google.TTS.new(options)

  defp configure_provider(Vxpipe.Providers.Cartesia.TTSSession, options, :text_to_speech),
    do: Vxpipe.Providers.Cartesia.TTS.new(options)

  defp configure_provider(Vxpipe.Providers.ElevenLabs.TTSSession, options, :text_to_speech),
    do: Vxpipe.Providers.ElevenLabs.TTS.new(options)

  defp configure_provider(provider, options, :text_to_speech) do
    case provider.configure(options) do
      {:ok, _descriptor} -> {:ok, options}
      {:error, _reason} = error -> error
    end
  end

  defp configure_provider(provider, options, :speech_to_speech) do
    Vxpipe.CallEngine.SpeechToSpeechRuntime.configure(provider, options)
  end

  defp configure_provider(provider, options, _kind),
    do: configure_provider_struct(provider, options)

  defp configure_provider_struct(provider, options) do
    if function_exported?(provider, :new, 1),
      do: provider.new(options),
      else: {:error, :invalid_configuration}
  end

  defp authenticate_speech(options, nil), do: {:ok, options}

  defp authenticate_speech(options, %Vxpipe.CallEngine.ProviderCredential{
         auth_kind: "api_key",
         payload: %{"api_key" => api_key}
       }),
       do: {:ok, Keyword.put(options, :api_key, api_key)}

  defp authenticate_speech(_options, _credential), do: {:error, :unsupported_provider_auth}

  def unsupported_speech_configuration_reason(:speech_to_text),
    do: :unsupported_speech_to_text_configuration

  def unsupported_speech_configuration_reason(:speech_to_speech),
    do: :unsupported_speech_to_speech_configuration

  def unsupported_speech_configuration_reason(:output_speech_to_text),
    do: :unsupported_speech_to_text_configuration

  def unsupported_speech_configuration_reason(:text_to_speech),
    do: :unsupported_text_to_speech_configuration
end
