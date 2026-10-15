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

    for key <- [:transport, :transport_options] do
      assert {:error, :invalid_configuration} =
               TextToSpeechRuntime.provider({TTSSession, a}, [{key, :unexpected}])
    end

    assert {:ok, {TTSSession, overridden_public}, overridden_private, ^descriptor} =
             TextToSpeechRuntime.provider({TTSSession, a},
               wire_module: __MODULE__,
               wire_options: [observer: self()]
             )

    assert overridden_public == public
    assert Keyword.fetch!(overridden_private, :wire_module) == __MODULE__
    assert Keyword.fetch!(overridden_private, :wire_options) == [observer: self()]
    assert {:ok, ^descriptor} = TTSSession.configure(overridden_public)
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

  test "a private resolved origin controls the realtime PCM WebSocket without credentials" do
    assert {:ok, endpoint} = Endpoint.new("http://morse-local:9876", allow_http?: true)

    assert {:ok, config} =
             TTS.new([api_key: "my compatibility key", sample_rate: 24_000], endpoint)

    refute inspect(config) =~ "compatibility key"
    refute inspect(config) =~ "morse-local"
    connection = TTS.connection_options(config)
    uri = URI.new!(connection.url)
    assert uri.scheme == "ws"
    assert uri.host == "morse-local"
    assert uri.port == 9876
    assert uri.path == "/v1/text-to-speech/morse/multi-stream-input"

    assert URI.decode_query(uri.query) == %{
             "model_id" => "morse_v1",
             "output_format" => "pcm_24000",
             "auto_mode" => "true",
             "inactivity_timeout" => "180"
           }

    assert connection.headers == []

    assert {:ok, expected} = TTSSession.request_configuration(config)

    assert {:ok, ^expected} = TTSSession.configure(sample_rate: 24_000)
  end

  test "frames one context per utterance with correlated completion" do
    assert {:ok, endpoint} = Endpoint.new("http://morse-local:9876", allow_http?: true)
    assert {:ok, config} = TTS.new([api_key: "synthetic"], endpoint)
    assert {:ok, context} = TTS.new_context_id()

    assert [init, body, flush, close] = TTS.open_utterance(config, context, "SOS")
    assert JSON.decode!(init) == %{"text" => " ", "context_id" => context}
    assert JSON.decode!(body) == %{"text" => "SOS", "context_id" => context}
    assert JSON.decode!(flush) == %{"context_id" => context, "flush" => true}
    assert JSON.decode!(close) == %{"context_id" => context, "close_context" => true}

    assert JSON.decode!(TTS.close_utterance(config, context)) == %{
             "context_id" => context,
             "close_context" => true
           }

    assert JSON.decode!(TTS.close_socket(config)) == %{"close_socket" => true}

    assert JSON.decode!(TTS.keepalive_payload(config, "keep")) == %{
             "text" => "",
             "context_id" => "keep"
           }

    pcm = <<1, 0>>

    assert TTS.decode_frame(
             JSON.encode!(%{
               "audio" => Base.encode64(pcm),
               "isFinal" => false,
               "contextId" => context
             })
           ) == {:ok, {:audio, context, pcm}}

    assert TTS.decode_frame(
             JSON.encode!(%{"audio" => nil, "isFinal" => true, "contextId" => context})
           ) ==
             {:ok, {:final, context}}

    # Same drain contract as ElevenLabs: flush then close_context, final may carry audio.
    assert TTS.decode_frame(
             JSON.encode!(%{
               "audio" => Base.encode64(pcm),
               "isFinal" => true,
               "contextId" => context
             })
           ) == {:ok, {:audio_final, context, pcm}}

    large_pcm = :binary.copy(<<1, 0>>, 40_000)
    large_payload = JSON.encode!(%{"audio" => Base.encode64(large_pcm), "contextId" => context})
    assert byte_size(large_payload) > 65_536
    assert TTS.decode_frame(large_payload) == {:ok, {:audio, context, large_pcm}}

    for bad <- [
          ~s({"audio":"!!!","contextId":"c"}),
          ~s({"audio":"AQ=="}),
          ~s({"isFinal":true}),
          "not json"
        ] do
      assert {:error, :invalid_message} = TTS.decode_frame(bad)
    end
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
