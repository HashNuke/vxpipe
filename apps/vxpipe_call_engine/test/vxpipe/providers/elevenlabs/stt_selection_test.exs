defmodule Vxpipe.Providers.ElevenLabs.STTSelectionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{CapabilityCatalog, SpeechToTextRuntime}
  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.Providers.ElevenLabs.{Scribe, STTSession}
  alias Vxpipe.Providers.Registry

  test "inline Scribe selection resolves a private manual recognizer with local gap authority" do
    assert {:ok, STTSession} = Registry.fetch_capability("elevenlabs", :stt)

    assert {:ok, selection} =
             CapabilitySelection.new(
               %{
                 provider: "elevenlabs",
                 model: "scribe_v2_realtime",
                 options: %{language_code: "en"}
               },
               :speech_to_text,
               ["speech_to_text"]
             )

    assert :ok = CapabilityCatalog.validate(selection)
    assert {:ok, STTSession} = CapabilityCatalog.adapter(selection)
    assert {:ok, public} = CapabilityCatalog.speech_options(selection)
    assert {:ok, config} = Scribe.new(Keyword.put(public, :api_key, "synthetic-private-key"))
    assert config.language_code == "en"
    assert config.commit_strategy == :manual

    assert {:ok, {STTSession, ^public}, private} =
             SpeechToTextRuntime.provider({STTSession, config}, enabled: true, media_ingress: [])

    assert Keyword.fetch!(private, :config) == config
    refute inspect(private) =~ "synthetic-private-key"
    assert {:ok, descriptor} = STTSession.configure(public)
    assert descriptor.endpointing == :local_gap
    refute descriptor.finite_input?

    assert {:ok, [name: "elevenlabs", model: "scribe_v2_realtime"]} =
             SpeechToTextRuntime.usage_identity(STTSession, config)
  end

  test "call authoring rejects unsupported models, segmentation modes and private hooks" do
    for input <- [
          %{model: "scribe_v1"},
          %{options: %{api_key: "secret"}},
          %{options: %{endpoint: "wss://todo"}},
          %{options: %{wire_module: __MODULE__}},
          %{options: %{activity_options: []}},
          %{options: %{commit_strategy: "vad"}},
          %{options: %{sample_rate: 48_000}}
        ] do
      assert {:error, _reason} =
               CapabilitySelection.new(
                 Map.merge(%{provider: "elevenlabs", model: "scribe_v2_realtime"}, input),
                 :speech_to_text,
                 ["speech_to_text"]
               )
    end
  end
end
