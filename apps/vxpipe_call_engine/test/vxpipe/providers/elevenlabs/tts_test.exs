defmodule Vxpipe.Providers.ElevenLabs.TTSTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.ElevenLabs.{TTS, TTSSession}
  @voice "JBFqnCBsd6RMkjVDRZzb"

  test "admits reviewed phrase models and PCM options without credential or route hooks" do
    assert {:ok, config} = TTS.new(api_key: "synthetic-elevenlabs", voice: @voice)
    assert config.model == "eleven_flash_v2_5"
    assert config.sample_rate == 16_000
    refute inspect(config) =~ "synthetic-elevenlabs"

    for invalid <- [
          [voice: "../other"],
          [voice: "https://todo"],
          [voice: @voice, voice: "other"],
          [voice: @voice, model: "unknown"],
          [voice: @voice, sample_rate: 1],
          [voice: @voice, endpoint: "https://todo"],
          [voice: @voice, api_key: "synthetic"],
          [voice: @voice, request_module: __MODULE__],
          [voice: @voice, output_format: "mp3_44100_128"],
          [:invalid]
        ] do
      assert {:error, :invalid_configuration} = TTS.public_options(invalid)
    end

    assert {:error, :invalid_configuration} = TTS.new(api_key: "bad key", voice: @voice)
    assert {:error, :invalid_configuration} = TTS.new(api_key: "synthetic")
    assert {:error, :invalid_configuration} = TTS.new([:invalid])

    for model <- ["eleven_flash_v2_5", "eleven_multilingual_v2", "eleven_v3"] do
      assert {:ok, %{model: ^model}} = TTS.public_options(model: model, voice: @voice)
    end
  end

  test "builds a path-safe voice request with private header authentication and raw PCM query" do
    assert {:ok, config} = TTS.new(api_key: "synthetic", voice: @voice, sample_rate: 24_000)

    assert TTS.request_url(config) ==
             "https://api.elevenlabs.io/v1/text-to-speech/#{@voice}/stream"

    assert TTS.request_body(config, "Hello") == %{model_id: "eleven_flash_v2_5", text: "Hello"}
    options = TTS.request_options(config, "Hello", :sink)
    assert {"xi-api-key", "synthetic"} in Keyword.fetch!(options, :headers)
    assert Keyword.fetch!(options, :params) == [output_format: "pcm_24000"]
    assert Keyword.fetch!(options, :retry) == false
    assert Keyword.fetch!(options, :max_redirects) == 0
    assert Keyword.fetch!(options, :decode_body) == false
    assert :ok = TTS.validate_text("Hello")

    for invalid <- ["", " ", <<255>>, String.duplicate("x", 1_001)] do
      assert {:error, :invalid_text} = TTS.validate_text(invalid)
    end
  end

  test "declares initialized readiness and measured provider/model usage without private settings" do
    assert {:ok, descriptor} = TTSSession.configure(voice: @voice)
    assert descriptor.kind == :tts
    assert descriptor.readiness == :initialized
    assert descriptor.format.encoding == :linear16
    assert descriptor.format.sample_rate == 16_000
    assert descriptor.format.channels == 1
    assert descriptor.format.byte_order == :little
    assert descriptor.format.signed?

    assert descriptor.usage_identity == %{
             provider: :elevenlabs,
             model: "eleven_flash_v2_5",
             provenance: :locally_measured
           }

    refute Map.has_key?(descriptor.settings, :api_key)
  end
end
