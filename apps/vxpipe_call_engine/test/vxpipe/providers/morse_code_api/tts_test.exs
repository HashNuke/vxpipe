defmodule Vxpipe.Providers.MorseCodeApi.TTSTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.MorseCodeApi.{Endpoint, TTS, TTSSession}
  alias Vxpipe.CallEngine.TextToSpeechRuntime

  test "runtime keeps the origin private and separates opening-audio caches across hosts" do
    assert {:ok, first} = Endpoint.new("https://first.morse.example")
    assert {:ok, second} = Endpoint.new("https://second.morse.example")
    assert {:ok, a} = TTS.new([api_key: "synthetic"], first)
    assert {:ok, b} = TTS.new([api_key: "synthetic"], second)

    assert {:ok, {TTSSession, public}, private, descriptor} =
             TextToSpeechRuntime.provider({TTSSession, a}, [])

    refute Keyword.has_key?(public, :endpoint)
    refute Keyword.has_key?(public, :api_key)
    assert Keyword.fetch!(private, :config) == a
    assert {:ok, ^descriptor} = TTSSession.configure(public)

    refute TextToSpeechRuntime.descriptor_cache_identity({TTSSession, a}, descriptor) ==
             TextToSpeechRuntime.descriptor_cache_identity({TTSSession, b}, descriptor)

    for key <- [:transport, :transport_options, :wire_module, :wire_options] do
      assert {:error, :invalid_configuration} =
               TextToSpeechRuntime.provider({TTSSession, a}, [{key, :unexpected}])
    end
  end

  test "publishes only the Morse model and voice without resolving runtime credentials or origin" do
    assert [model] = TTS.models()
    assert model.id == "morse_v1"
    assert model.name == "MorseCodeApiTTS"
    assert {:ok, descriptor} = TTSSession.configure([])
    assert descriptor.settings == %{model: "morse_v1", voice: "morse", sample_rate: 16_000}
    assert descriptor.readiness == :initialized

    assert descriptor.usage_identity == %{
             provider: :morse_code_api,
             model: "morse_v1",
             provenance: :locally_measured
           }

    for options <- [
          [model: "eleven_v3"],
          [voice: "other"],
          [sample_rate: 123],
          [api_key: "key"],
          [endpoint: "http://localhost"],
          [base_url: "http://localhost"],
          [voice: "morse", voice: "morse"],
          [:bad]
        ] do
      assert {:error, :invalid_configuration} = TTS.public_options(options)
    end
  end

  test "a private resolved origin controls authenticated PCM requests without redirects or fallback" do
    assert {:ok, endpoint} = Endpoint.new("http://morse-local:9876", allow_http?: true)

    assert {:ok, config} =
             TTS.new([api_key: "my compatibility key", sample_rate: 24_000], endpoint)

    refute inspect(config) =~ "compatibility key"
    refute inspect(config) =~ "morse-local"
    assert TTS.request_url(config) == "http://morse-local:9876/v1/text-to-speech/morse/stream"
    options = TTS.request_options(config, "SOS", :sink)
    assert {"xi-api-key", "my compatibility key"} in Keyword.fetch!(options, :headers)
    assert Keyword.fetch!(options, :params) == [output_format: "pcm_24000"]
    assert Keyword.fetch!(options, :json) == %{model_id: "morse_v1", text: "SOS"}
    assert Keyword.fetch!(options, :max_redirects) == 0
    assert Keyword.fetch!(options, :retry) == false
    assert Keyword.fetch!(options, :decode_body) == false

    assert {:ok, expected, Vxpipe.Providers.MorseCodeApi.TTSRequest} =
             TTSSession.request_configuration(config)

    assert {:ok, ^expected} = TTSSession.configure(sample_rate: 24_000)
  end

  test "rejects invalid text and private configuration without returning inputs" do
    assert {:ok, endpoint} = Endpoint.new("https://morse.example")

    for options <- [
          [],
          [api_key: ""],
          [api_key: "x\ny"],
          [api_key: "key", endpoint: "https://other.example"]
        ] do
      assert {:error, :invalid_configuration} = TTS.new(options, endpoint)
    end

    assert :ok = TTS.validate_text("SOS")

    for text <- ["", "  ", <<255>>, String.duplicate("E", 4_097), nil] do
      assert {:error, :invalid_text} = TTS.validate_text(text)
    end
  end
end
