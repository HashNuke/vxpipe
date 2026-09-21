defmodule Vxpipe.CallEngine.CapabilityCatalog do
  @moduledoc "Closed mapping from inline capability selections to internal adapters."

  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.Providers.Deepgram
  alias Vxpipe.Providers.Registry

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

  def validate(%CapabilitySelection{kind: :model_inference, provider: provider} = selection)
      when provider in ["google", "zenmux"] do
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
      when provider in ["google", "zenmux"],
      do: {:ok, Vxpipe.AgentRuntime.Provider.ReqLLM}

  def adapter(%CapabilitySelection{kind: :speech_to_text, provider: "deepgram"}),
    do: Registry.resolve_capability("deepgram", :stt)

  def adapter(%CapabilitySelection{kind: :text_to_speech, provider: "deepgram"}),
    do: Registry.resolve_capability("deepgram", :tts)

  def adapter(%CapabilitySelection{kind: :speech_to_text, provider: "morse"}),
    do: {:ok, Vxpipe.CallEngine.Provider.MorseCodeSTT.Session}

  def adapter(%CapabilitySelection{kind: :text_to_speech, provider: "morse"}),
    do: {:ok, Vxpipe.CallEngine.Provider.MorseCodeTTS.Session}

  def adapter(_selection), do: {:error, :unsupported_capability}

  @doc false
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
    [deepgram, Vxpipe.CallEngine.Provider.MorseCodeSTT.Session]
  end

  defp speech_adapters(:text_to_speech) do
    {:ok, deepgram} = Registry.fetch_capability("deepgram", :tts)
    [deepgram, Vxpipe.CallEngine.Provider.MorseCodeTTS.Session]
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

  defp validate_provider_settings(Deepgram.Flux.Session, :speech_to_text, settings) do
    Deepgram.Speech.settings(:speech_to_text, settings)
  end

  defp validate_provider_settings(
         Vxpipe.CallEngine.Provider.MorseCodeSTT.Session,
         :speech_to_text,
         settings
       ),
       do: Keyword.validate(settings, enabled: false, media_ingress: nil)

  defp validate_provider_settings(Deepgram.FluxTextToSpeech.Session, :text_to_speech, settings) do
    Deepgram.Speech.settings(:text_to_speech, settings)
  end

  defp validate_provider_settings(
         Vxpipe.CallEngine.Provider.MorseCodeTTS.Session,
         :text_to_speech,
         settings
       ),
       do: Keyword.validate(settings, enabled: false, maximum_requests: nil)

  defp validate_provider_settings(_provider, _kind, _settings),
    do: {:error, :provider_not_configured}

  def speech_options(%CapabilitySelection{provider: "deepgram", model: model, options: input}) do
    Deepgram.Speech.selection_options(model, input)
  end

  def speech_options(%CapabilitySelection{provider: "morse", model: "morse", options: input}),
    do: normalize(input, @morse_keys)

  def speech_options(_selection), do: {:error, :unsupported_capability}

  defp validate_speech(%{provider: "morse", credential_name: nil, kind: kind}, options)
       when kind in [:speech_to_text, :text_to_speech] do
    provider =
      if kind == :speech_to_text,
        do: Vxpipe.CallEngine.Provider.MorseCodeSTT.Session,
        else: Vxpipe.CallEngine.Provider.MorseCodeTTS.Session

    validate_provider(provider, options)
  end

  defp validate_speech(%{provider: "deepgram", kind: :speech_to_text}, options),
    do: Deepgram.Flux.validate_options(options)

  defp validate_speech(%{provider: "deepgram", kind: :text_to_speech}, options),
    do: validate_provider(Deepgram.FluxTextToSpeech.Session, options)

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
