defmodule Vxpipe.Providers.Cartesia.TTSTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Providers.Cartesia.{TTS, TTSSession}

  @voice "db6b0ed5-d5d3-463d-ae85-518a07d3c2b4"

  test "validates explicit public model, voice and raw PCM settings without private hooks" do
    assert {:ok, config} = TTS.new(api_key: "synthetic-cartesia", voice: @voice)
    assert config.model == "sonic-3.6"
    assert config.sample_rate == 24_000
    refute inspect(config) =~ "synthetic-cartesia"

    for invalid <- [
          [voice: "invalid"],
          [voice: @voice, model: "unknown"],
          [voice: @voice, sample_rate: 1],
          [voice: @voice, endpoint: "https://todo"],
          [voice: @voice, api_key: "synthetic"],
          [voice: @voice, request_module: __MODULE__]
        ] do
      assert {:error, :invalid_configuration} = TTS.public_options(invalid)
    end

    assert {:error, :invalid_configuration} = TTS.new(api_key: "bad key", voice: @voice)
    assert {:error, :invalid_configuration} = TTS.new(api_key: "synthetic")
  end

  test "constructs the versioned raw PCM request and bounds the complete transcript" do
    assert {:ok, config} = TTS.new(api_key: "synthetic", voice: @voice, sample_rate: 48_000)

    assert TTS.request_body(config, "Hello") == %{
             model_id: "sonic-3.6",
             transcript: "Hello",
             voice: @voice,
             output_format: %{container: "raw", encoding: "pcm_s16le", sample_rate: 48_000}
           }

    options = TTS.request_options(config, "Hello", :sink)
    assert {"authorization", "Bearer synthetic"} in Keyword.fetch!(options, :headers)
    assert {"cartesia-version", "2026-08-14"} in Keyword.fetch!(options, :headers)
    assert Keyword.fetch!(options, :retry) == false
    assert Keyword.fetch!(options, :max_redirects) == 0
    assert Keyword.fetch!(options, :decode_body) == false
    assert :ok = TTS.validate_text("Hello")

    for invalid <- ["", " ", <<255>>, String.duplicate("x", 1_001)] do
      assert {:error, :invalid_text} = TTS.validate_text(invalid)
    end
  end

  test "declares a privately authenticated request session with measured usage identity" do
    assert {:ok, descriptor} = TTSSession.configure(voice: @voice, sample_rate: 16_000)
    assert descriptor.kind == :tts
    assert descriptor.readiness == :initialized
    assert descriptor.format.encoding == :linear16
    assert descriptor.format.sample_rate == 16_000

    assert descriptor.usage_identity == %{
             provider: :cartesia,
             model: "sonic-3.6",
             provenance: :locally_measured
           }

    refute Map.has_key?(descriptor.settings, :api_key)
  end
end
