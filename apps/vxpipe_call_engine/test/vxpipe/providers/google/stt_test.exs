defmodule Vxpipe.Providers.Google.STTTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.Google.STT
  alias Vxpipe.CallEngine.{CapabilityCatalog, SpeechToTextRuntime}
  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.Providers.Registry

  test "the Live transcription wire contract accepts only 16 kHz mono PCM" do
    assert {:ok, config} = STT.new(api_key: "synthetic-key")
    refute inspect(config) =~ "synthetic-key"

    assert STT.setup(config) == %{
             "setup" => %{
               "model" => "models/gemini-3.5-transcribe-live",
               "generationConfig" => %{"responseModalities" => ["TEXT"]},
               "inputAudioTranscription" => %{}
             }
           }

    assert STT.connection_options(config).headers == [{"x-goog-api-key", "synthetic-key"}]
    refute STT.connection_options(config).url =~ "synthetic-key"
    assert {:ok, _message} = STT.encode_audio(<<1, 0, 2, 0>>)
    assert {:error, :invalid_audio} = STT.encode_audio(<<1>>)

    assert {:error, :invalid_configuration} =
             STT.new(api_key: "synthetic-key", sample_rate: 48_000)

    assert {:error, :invalid_configuration} = STT.new(api_key: "synthetic-key", encoding: :opus)
  end

  test "decodes speech activity, interim and final transcriptions without leaking provider errors" do
    assert {:ok, [:ready]} = STT.decode(~s({"setupComplete":{}}))

    assert {:ok, [:activity_start, {:interim, "hello"}]} =
             STT.decode(
               JSON.encode!(%{
                 "voiceActivity" => %{"type" => "ACTIVITY_START", "audioOffset" => "1.0s"},
                 "serverContent" => %{"interimInputTranscription" => %{"text" => "hello"}}
               })
             )

    assert {:ok, [:activity_end, {:final, "hello there"}]} =
             STT.decode(
               JSON.encode!(%{
                 "voiceActivity" => %{"type" => "ACTIVITY_END"},
                 "serverContent" => %{"inputTranscription" => %{"text" => "hello there"}}
               })
             )

    assert {:ok, [:go_away]} = STT.decode(~s({"goAway":{"timeLeft":"30s"}}))
    assert {:error, :provider_failure} = STT.decode(~s({"error":{"message":"secret"}}))
    assert {:error, :invalid_message} = STT.decode("not json")
  end

  test "the call catalog resolves a private Google STT runtime" do
    assert {:ok, Vxpipe.Providers.Google.STTSession} = Registry.fetch_capability("google", :stt)

    assert {:ok, selection} =
             CapabilitySelection.new(
               %{provider: "google", model: "gemini-3.5-transcribe-live"},
               :speech_to_text,
               ["speech_to_text"]
             )

    assert {:ok, Vxpipe.Providers.Google.STTSession} = CapabilityCatalog.adapter(selection)
    assert {:ok, public} = CapabilityCatalog.speech_options(selection)
    assert public[:encoding] == :linear16
    assert public[:sample_rate] == 16_000
    assert {:ok, config} = STT.new(Keyword.put(public, :api_key, "synthetic-key"))

    assert {:ok, {Vxpipe.Providers.Google.STTSession, options}, private} =
             SpeechToTextRuntime.provider(
               {Vxpipe.Providers.Google.STTSession, config},
               enabled: true,
               media_ingress: []
             )

    assert options[:model] == "gemini-3.5-transcribe-live"
    assert private[:config] == config
    refute inspect(private) =~ "synthetic-key"
  end
end
