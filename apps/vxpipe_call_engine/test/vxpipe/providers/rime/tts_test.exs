defmodule Vxpipe.Providers.Rime.TTSTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.Rime.{TTS, TTSSession}
  alias Vxpipe.CallEngine.{CapabilityCatalog, TextToSpeechRuntime}
  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.Providers.Registry

  test "configures TTS as raw mono PCM and rejects unsupported models" do
    assert {:ok, config} =
             TTS.new(
               api_key: "fixture-key",
               model: "coda",
               speaker: "astra",
               sample_rate: 24_000
             )

    assert {:ok, descriptor} =
             TTSSession.configure(model: "coda", speaker: "astra", sample_rate: 24_000)

    assert descriptor.kind == :tts

    assert descriptor.format == %{
             encoding: :linear16,
             container: :raw,
             channels: 1,
             byte_order: :little,
             signed?: true,
             sample_rate: 24_000
           }

    assert TTS.connection_options(config).headers == [
             {"Authorization", "Bearer fixture-key"}
           ]

    assert {:error, :invalid_configuration} = TTS.new(api_key: "fixture-key", model: "mistv3")
  end

  test "decodes bounded PCM chunks and a batch terminal" do
    pcm = <<1, 0, 2, 0>>

    assert {:audio, ^pcm} =
             TTS.decode(JSON.encode!(%{"type" => "chunk", "data" => Base.encode64(pcm)}))

    assert :done = TTS.decode(~s({"type":"done"}))

    assert {:error, :invalid_message} =
             TTS.decode(JSON.encode!(%{"type" => "chunk", "data" => Base.encode64(<<1>>)}))

    assert {:error, :provider_failure} =
             TTS.decode(~s({"type":"error","message":"synthetic secret"}))
  end

  test "the declared TTS capability accepts a call selection and keeps credentials private" do
    assert {:ok, TTSSession} = Registry.fetch_capability("rime", :tts)

    assert {:ok, selection} =
             CapabilitySelection.new(
               %{provider: "rime", model: "coda", options: %{"speaker" => "astra"}},
               :text_to_speech,
               ["text_to_speech"]
             )

    assert {:ok, TTSSession} = CapabilityCatalog.adapter(selection)
    assert {:ok, public} = CapabilityCatalog.speech_options(selection)
    assert public[:speaker] == "astra"
    assert public[:model] == "coda"

    assert {:ok, config} = TTS.new(Keyword.put(public, :api_key, "synthetic-key"))

    assert {:ok, {TTSSession, options}, private, descriptor} =
             TextToSpeechRuntime.provider({TTSSession, config},
               enabled: true,
               maximum_requests: 2
             )

    assert options[:model] == "coda"
    assert private[:config] == config
    assert descriptor.usage_identity.provider == :rime
    refute inspect(private) =~ "synthetic-key"
  end
end
