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
          [voice: @voice, model: "eleven_v3"],
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

    for model <- ["eleven_flash_v2_5", "eleven_multilingual_v2"] do
      assert {:ok, %{model: ^model}} = TTS.public_options(model: model, voice: @voice)
    end

    # eleven_v3 is a separate text-to-dialogue websocket product, not multi-stream TTS.
    assert {:error, :invalid_configuration} =
             TTS.public_options(model: "eleven_v3", voice: @voice)

    assert {:error, :invalid_configuration} =
             TTS.new(api_key: "synthetic", voice: @voice, model: "eleven_v3")

    assert {:error, :invalid_configuration} =
             TTSSession.configure(model: "eleven_v3", voice: @voice)
  end

  test "builds the multi-stream websocket connection with header authentication" do
    assert {:ok, config} = TTS.new(api_key: "synthetic", voice: @voice, sample_rate: 24_000)

    assert TTS.connection_options(config) == %{
             url:
               "wss://api.elevenlabs.io/v1/text-to-speech/#{@voice}/multi-stream-input?inactivity_timeout=180&model_id=eleven_flash_v2_5&output_format=pcm_24000",
             headers: [{"xi-api-key", "synthetic"}]
           }

    refute inspect(config) =~ "synthetic"
  end

  test "derives the websocket route from an endpoint override without leaking credentials" do
    config = %TTS{
      api_key: "synthetic",
      model: "eleven_flash_v2_5",
      voice: @voice,
      sample_rate: 16_000,
      endpoint: "https://gateway.example/eleven/v1/text-to-speech"
    }

    connection = TTS.connection_options(config)
    uri = URI.new!(connection.url)
    assert uri.scheme == "wss"
    assert uri.host == "gateway.example"
    assert uri.path == "/eleven/v1/text-to-speech/#{@voice}/multi-stream-input"
    assert URI.decode_query(uri.query)["model_id"] == "eleven_flash_v2_5"
    assert connection.headers == [{"xi-api-key", "synthetic"}]
    refute connection.url =~ "synthetic"
  end

  test "selects only websocket-compatible models" do
    assert Enum.sort(TTS.websocket_models()) ==
             TTS.models() |> Enum.map(& &1.id) |> Enum.sort()

    for model <- TTS.websocket_models() do
      assert TTS.websocket_compatible?(model)
      assert {:ok, %{model: ^model}} = TTS.public_options(model: model, voice: @voice)
      assert {:ok, _descriptor} = TTSSession.configure(model: model, voice: @voice)
    end

    refute TTS.websocket_compatible?("eleven_v3")
    refute TTS.websocket_compatible?("unknown")

    assert {:error, :invalid_configuration} = TTS.public_options(model: "unknown", voice: @voice)

    assert {:error, :invalid_configuration} =
             TTSSession.configure(model: "unknown", voice: @voice)

    # v3 selection must fail through actual configuration, not just the mirror list.
    assert {:error, :invalid_configuration} =
             TTS.public_options(model: "eleven_v3", voice: @voice)

    assert {:error, :invalid_configuration} =
             TTSSession.configure(model: "eleven_v3", voice: @voice)
  end

  test "frames one context per utterance with correlated completion" do
    assert {:ok, config} = TTS.new(api_key: "synthetic", voice: @voice)
    assert {:ok, context} = TTS.new_context_id()
    assert is_binary(context) and byte_size(context) > 0

    assert [init, body, flush, close] = TTS.open_utterance(config, context, "Hello")
    assert JSON.decode!(init) == %{"text" => " ", "context_id" => context}
    assert JSON.decode!(body) == %{"text" => "Hello", "context_id" => context}
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

    pcm = <<1, 0, 2, 0>>

    assert TTS.decode_frame(
             JSON.encode!(%{"audio" => Base.encode64(pcm), "contextId" => context})
           ) == {:ok, {:audio, context, pcm}}

    assert TTS.decode_frame(JSON.encode!(%{"isFinal" => true, "contextId" => context})) ==
             {:ok, {:final, context}}

    # Live multi-context traffic can carry final audio in the same frame.
    assert TTS.decode_frame(
             JSON.encode!(%{
               "audio" => Base.encode64(pcm),
               "isFinal" => true,
               "contextId" => context
             })
           ) == {:ok, {:audio_final, context, pcm}}

    # Normal generation chunks exceed the old arbitrary 65_536 JSON bound.
    large_pcm = :binary.copy(<<1, 0>>, 40_000)
    large_payload = JSON.encode!(%{"audio" => Base.encode64(large_pcm), "contextId" => context})
    assert byte_size(large_payload) > 65_536

    assert TTS.decode_frame(large_payload) == {:ok, {:audio, context, large_pcm}}

    large_final_payload =
      JSON.encode!(%{"audio" => Base.encode64(pcm), "isFinal" => true, "contextId" => context})

    assert TTS.decode_frame(large_final_payload) == {:ok, {:audio_final, context, pcm}}

    for bad <- [
          ~s({"audio":"!!!","contextId":"c"}),
          ~s({"audio":"AQ=="}),
          ~s({"isFinal":true}),
          ~s({"isFinal":false,"contextId":"c"}),
          "not json"
        ] do
      assert {:error, :invalid_message} = TTS.decode_frame(bad)
    end

    assert {:error, :invalid_message} = TTS.validate_audio(<<1>>)
    assert {:error, :invalid_message} = TTS.validate_audio(<<>>)
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
