defmodule Vxpipe.CallEngine.Speech.ModelLanguagesTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.CallEngine.CapabilityCatalog
  alias Vxpipe.Providers.ElevenLabs.Realtime
  alias Vxpipe.Providers.Google.STT

  test "language errors identify the field and reject incompatible selections" do
    for {kind, provider, model, codes} <- [
          {:speech_to_text, "deepgram", "flux", ["es", "es"]},
          {:speech_to_text, "deepgram", "flux", ["zz"]},
          {:speech_to_text, "deepgram", "flux-general-en", ["fr"]},
          {:speech_to_text, "elevenlabs", "scribe_v2_realtime", ["en", "es"]},
          {:speech_to_text, "elevenlabs", "scribe_v3_live", "en"},
          {:text_to_speech, "elevenlabs", "eleven_multilingual_v2", ["en"]},
          {:model_inference, "fixture", "test", []}
        ] do
      input = %{provider: provider, model: model, languages: codes}

      assert {:error, %{details: %{"path" => ["selection", "languages"]}}} =
               CapabilitySelection.new(input, kind, ["selection"])
    end
  end

  test "empty and omitted selections retain historical identity and old Scribe options" do
    source = %{
      provider: "elevenlabs",
      model: "scribe_v2_realtime",
      options: %{language_code: "fr"}
    }

    assert {:ok, old} = CapabilitySelection.new(source, :speech_to_text, [])
    historical = Map.delete(old, :languages)
    assert :ok = CapabilitySelection.validate(historical, [])
    assert {:ok, public} = CapabilityCatalog.speech_options(historical)
    assert public[:language_code] == "fr"

    assert CapabilitySelection.identity(old, "tenant") ==
             CapabilitySelection.identity(historical, "tenant")

    assert {:error, _} =
             CapabilitySelection.new(Map.put(source, :languages, ["es"]), :speech_to_text, [])

    assert {:error, _} =
             CapabilitySelection.new(Map.put(source, :languages, []), :speech_to_text, [])

    for kind <- [:speech_to_text, :output_speech_to_text] do
      automatic = Map.delete(source, :options)
      assert {:ok, omitted} = CapabilitySelection.new(automatic, kind, [])

      assert {:ok, ^omitted} =
               CapabilitySelection.new(Map.put(automatic, :languages, []), kind, [])
    end
  end

  test "language on a synthesis model reaches its audio request" do
    for {provider, model, voice, module} <- [
          {"cartesia", "sonic-3.6", "db6b0ed5-d5d3-463d-ae85-518a07d3c2b4",
           Vxpipe.Providers.Cartesia.TTS},
          {"elevenlabs", "eleven_flash_v2_5", "JBFqnCBsd6RMkjVDRZzb",
           Vxpipe.Providers.ElevenLabs.TTS}
        ] do
      input = %{provider: provider, model: model, languages: ["es"], options: %{voice: voice}}
      assert {:ok, selection} = CapabilitySelection.new(input, :text_to_speech, [])
      assert {:ok, opts} = CapabilityCatalog.speech_options(selection)
      assert {:ok, config} = module.new(Keyword.put(opts, :api_key, "synthetic"))

      case provider do
        "cartesia" ->
          assert [payload] = module.open_utterance(config, "example", "Hola")
          assert JSON.decode!(payload)["locale"] == "es"

        "elevenlabs" ->
          assert module.connection_options(config).url
                 |> URI.parse()
                 |> Map.fetch!(:query)
                 |> URI.decode_query()
                 |> Map.fetch!("language_code") == "es"
      end
    end
  end

  test "the model catalog describes the Flux family language options" do
    {:ok, models} = Vxpipe.CallEngine.ModelCatalog.models("deepgram", "speech_to_text")
    model = Enum.find(models, &(&1.id == "flux"))
    assert %{multiple: true, default: "automatic", values: codes} = model.languages
    assert "es" in codes
  end

  test "Google synthesis passes a locale to the selected speaker" do
    input = %{provider: "google", model: "gemini-3.1-flash-tts-preview", languages: ["en-GB"]}
    assert {:ok, selection} = CapabilitySelection.new(input, :text_to_speech, [])
    assert {:ok, opts} = CapabilityCatalog.speech_options(selection)

    assert {:ok, config} =
             Vxpipe.Providers.Google.TTS.new(Keyword.put(opts, :api_key, "synthetic"))

    body = Vxpipe.Providers.Google.TTS.request_body(config, "Good morning")
    assert body.generation_config.speech_config == [%{voice: "Kore", language: "en-GB"}]
  end

  test "Rime includes the selected language alongside its speaker" do
    input = %{provider: "rime", model: "coda", languages: ["en"], options: %{speaker: "astra"}}
    assert {:ok, selection} = CapabilitySelection.new(input, :text_to_speech, [])
    assert {:ok, opts} = CapabilityCatalog.speech_options(selection)
    assert {:ok, config} = Vxpipe.Providers.Rime.TTS.new(Keyword.put(opts, :api_key, "synthetic"))

    assert config
           |> Vxpipe.Providers.Rime.TTS.connection_options()
           |> Map.fetch!(:url)
           |> URI.parse()
           |> Map.fetch!(:query)
           |> URI.decode_query()
           |> Map.fetch!("lang") == "en"
  end

  test "Google recognition hints use the transcription setup" do
    input = %{
      provider: "google",
      model: "gemini-3.5-transcribe-live",
      languages: ["en-US", "es-ES"]
    }

    assert {:ok, selection} = CapabilitySelection.new(input, :speech_to_text, [])
    assert {:ok, opts} = CapabilityCatalog.speech_options(selection)
    assert {:ok, config} = STT.new(Keyword.put(opts, :api_key, "synthetic"))

    assert STT.setup(config)["setup"]["inputAudioTranscription"] == %{
             "languageCodes" => ["en-US", "es-ES"]
           }
  end

  test "Eleven Realtime sends the conversation language at session creation" do
    input = %{provider: "elevenlabs", model: "eleven_realtime_v1_mini", languages: ["pt-br"]}
    assert {:ok, selection} = CapabilitySelection.new(input, :speech_to_speech, [])
    assert {:ok, opts} = CapabilityCatalog.speech_options(selection)
    assert {:ok, config} = Realtime.new(Keyword.put(opts, :api_key, "synthetic"))
    assert Realtime.session(config)["audio"]["input"]["transcription"] == %{"language" => "pt-br"}
  end
end
