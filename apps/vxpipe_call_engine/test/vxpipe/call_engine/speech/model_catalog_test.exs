defmodule Vxpipe.CallEngine.Speech.ModelCatalogTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.Registry

  for {provider, capabilities} <- Registry.catalog(),
      capability <- capabilities,
      capability in [:stt, :tts, :sts] do
    test "#{provider} #{capability} declares runnable models and one recommended default" do
      assert {:ok, adapter} = Registry.resolve_capability(unquote(provider), unquote(capability))
      assert_models(adapter)
    end
  end

  test "the guide, native Morse and duplex implementations share the model contract" do
    for adapter <- [
          Vxpipe.CallEngine.SpeechGuideTTSProvider,
          Vxpipe.CallEngine.Provider.MorseCodeSTT.Session,
          Vxpipe.CallEngine.Provider.MorseCodeTTS.Session,
          Vxpipe.CallEngine.Provider.MorseCodeSTS.Session,
          Vxpipe.CallEngine.Provider.MorseCodeDuplex.Session,
          Vxpipe.Providers.MorseCode.DuplexSTSSession
        ] do
      assert_models(adapter)
    end
  end

  test "recommended models retain onboarding choices, with Flux and its voice separate" do
    for {provider, capability, id} <- [
          {"deepgram", :stt, "flux-general-multi"},
          {"deepgram", :tts, "flux"},
          {"cartesia", :stt, "ink-2"},
          {"cartesia", :tts, "sonic-3.6"},
          {"elevenlabs", :stt, "scribe_v2_realtime"},
          {"elevenlabs", :tts, "eleven_flash_v2_5"},
          {"google", :stt, "gemini-3.5-transcribe-live"},
          {"google", :tts, "gemini-3.1-flash-tts-preview"},
          {"google", :sts, "gemini-3.8-live"},
          {"openai", :sts, "gpt-live-1"},
          {"rime", :tts, "coda"}
        ] do
      assert {:ok, adapter} = Registry.resolve_capability(provider, capability)
      assert Enum.find(adapter.models(), & &1.default).id == id
    end

    assert [flux] = Vxpipe.Providers.Deepgram.TTSSession.models()
    assert flux.voices.default == "hannah"
    assert flux.voices.parameter == "voice"
  end

  test "Flux accepts its public model and constructs the wire model while preserving legacy IDs" do
    adapter = Vxpipe.Providers.Deepgram.TTSSession
    assert {:ok, descriptor} = adapter.configure(model: "flux", voice: "hannah")
    assert descriptor.settings.model == "flux-hannah-en"
    assert {:ok, other} = adapter.configure(model: "flux", voice: "haley")
    assert other.settings.model == "flux-haley-en"
    assert {:ok, legacy} = adapter.configure(model: "flux-haley-en")
    assert legacy.settings.model == "flux-haley-en"
    assert {:error, :invalid_configuration} = adapter.configure(model: "flux", voice: "../secret")
  end

  test "public recommendations include the options required by portable speech selections" do
    kinds = %{stt: :speech_to_text, tts: :text_to_speech, sts: :speech_to_speech}

    for {provider, capabilities} <- Registry.catalog(),
        capability <- capabilities,
        capability in [:stt, :tts, :sts] do
      {:ok, adapter} = Registry.resolve_capability(provider, capability)

      for model <- adapter.models() do
        options = Map.get(model, :options, %{})

        options =
          case model.voices do
            nil ->
              options

            %{type: :free_text, default: voice, parameter: parameter} ->
              Map.put(options, parameter, voice)

            %{type: :list, values: voices, parameter: parameter} ->
              Map.put(options, parameter, Enum.find(voices, & &1.default).id)
          end

        source = %{"provider" => provider, "model" => model.id, "options" => options}

        assert {:ok, _selection} =
                 Vxpipe.CallEngine.CallSpec.CapabilitySelection.new(
                   source,
                   Map.fetch!(kinds, capability),
                   ["selection"]
                 )
      end
    end
  end

  defp assert_models(adapter) do
    Code.ensure_loaded!(adapter)
    assert function_exported?(adapter, :models, 0), "#{inspect(adapter)} must declare models/0"
    models = adapter.models()
    assert models != []
    assert Enum.count(models, & &1.default) == 1
    assert Enum.uniq_by(models, & &1.id) == models

    for model <- models do
      assert is_binary(model.id) and model.id != ""
      assert is_binary(model.name) and model.name != ""
      assert is_boolean(model.default)
      options = configure_options(adapter, model)
      assert {:ok, _descriptor} = adapter.configure(options)

      assert {:error, :invalid_configuration} =
               adapter.configure(Keyword.put(options, :model, "unlisted-model"))
    end
  end

  defp configure_options(adapter, model) do
    options = [model: model.id]

    options =
      if adapter == Vxpipe.Providers.Deepgram.STTSession,
        do: options ++ [encoding: :linear16, sample_rate: 16_000],
        else: options

    case model.voices do
      nil ->
        options

      %{type: :free_text, default: voice, parameter: parameter} ->
        assert is_binary(voice) and voice != ""
        Keyword.put(options, voice_parameter(parameter), voice)

      %{type: :list, values: voices, parameter: parameter} ->
        assert Enum.count(voices, & &1.default) == 1
        Keyword.put(options, voice_parameter(parameter), Enum.find(voices, & &1.default).id)
    end
  end

  defp voice_parameter("voice"), do: :voice
  defp voice_parameter("speaker"), do: :speaker
end
