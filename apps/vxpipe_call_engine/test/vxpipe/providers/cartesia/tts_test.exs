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

  test "builds the versioned websocket connection with bearer authentication" do
    assert {:ok, config} = TTS.new(api_key: "synthetic", voice: @voice, sample_rate: 48_000)
    connection = TTS.connection_options(config)
    uri = URI.new!(connection.url)
    assert uri.scheme == "wss"
    assert uri.host == "api.cartesia.ai"
    assert uri.path == "/tts/websocket"
    assert URI.decode_query(uri.query) == %{"cartesia_version" => "2026-08-14"}
    assert {"authorization", "Bearer synthetic"} in connection.headers
    assert {"cartesia-version", "2026-08-14"} in connection.headers
    refute inspect(config) =~ "synthetic"
    assert :ok = TTS.validate_text("Hello")

    for invalid <- ["", " ", <<255>>, String.duplicate("x", 1_001)] do
      assert {:error, :invalid_text} = TTS.validate_text(invalid)
    end
  end

  test "frames one generation context per utterance with done completion" do
    assert {:ok, config} = TTS.new(api_key: "synthetic", voice: @voice, sample_rate: 24_000)
    assert {:ok, context} = TTS.new_context_id()

    assert [generation] = TTS.open_utterance(config, context, "Hello")

    assert JSON.decode!(generation) == %{
             "model_id" => "sonic-3.6",
             "transcript" => "Hello",
             "voice" => %{"id" => @voice},
             "output_format" => %{
               "container" => "raw",
               "encoding" => "pcm_s16le",
               "sample_rate" => 24_000
             },
             "context_id" => context,
             "continue" => false
           }

    assert JSON.decode!(TTS.close_utterance(config, context)) == %{
             "context_id" => context,
             "cancel" => true
           }

    assert TTS.close_socket(config) == nil
    assert TTS.keepalive_payload(config, context) == nil

    pcm = <<1, 0, 2, 0>>

    assert TTS.decode_frame(
             JSON.encode!(%{
               "type" => "chunk",
               "data" => Base.encode64(pcm),
               "done" => false,
               "status_code" => 206,
               "step_time" => 1,
               "context_id" => context
             })
           ) == {:ok, {:audio, context, pcm}}

    assert TTS.decode_frame(
             JSON.encode!(%{
               "type" => "chunk",
               "data" => Base.encode64(pcm),
               "done" => true,
               "status_code" => 206,
               "step_time" => 1,
               "context_id" => context
             })
           ) == {:ok, {:audio_final, context, pcm}}

    assert TTS.decode_frame(
             JSON.encode!(%{
               "type" => "done",
               "done" => true,
               "status_code" => 206,
               "context_id" => context
             })
           ) == {:ok, {:final, context}}

    for ignored <- ["timestamps", "phoneme_timestamps", "flush_done"] do
      assert TTS.decode_frame(
               JSON.encode!(%{"type" => ignored, "done" => false, "context_id" => context})
             ) == {:ok, :ignore}
    end

    assert {:error, :provider_failure} =
             TTS.decode_frame(JSON.encode!(%{"type" => "error", "context_id" => context}))

    for bad <- [
          ~s({"type":"chunk","data":"!!!","done":false,"context_id":"c"}),
          ~s({"type":"chunk","data":"AQ==","context_id":"c"}),
          ~s({"type":"done","done":true}),
          "not json"
        ] do
      assert {:error, :invalid_message} = TTS.decode_frame(bad)
    end

    assert {:error, :invalid_message} = TTS.validate_audio(<<1>>)
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
