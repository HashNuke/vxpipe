defmodule Vxpipe.Providers.MorseCodeApi.STTTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Providers.MorseCodeApi.{Endpoint, STT}

  test "one private origin requests the fixed Morse PCM and silence profile" do
    assert {:ok, endpoint} = Endpoint.new("http://morse-local:9876/", allow_http?: true)
    assert {:ok, config} = STT.new([api_key: "arbitrary compatibility key"], endpoint)
    assert [%{id: "morse_stt_v1", name: "MorseCodeApiSTT"}] = STT.models()
    assert config.sample_rate == 16_000
    refute inspect(config) =~ "compatibility key"
    refute inspect(config) =~ "morse-local"

    connection = STT.connection_options(config)
    uri = URI.new!(connection.url)

    assert {uri.scheme, uri.host, uri.port, uri.path} ==
             {"ws", "morse-local", 9876, "/v1/speech-to-text/realtime"}

    assert connection.headers == [{"xi-api-key", "arbitrary compatibility key"}]

    assert URI.decode_query(uri.query) == %{
             "model_id" => "morse_stt_v1",
             "audio_format" => "pcm_16000",
             "commit_strategy" => "vad",
             "vad_silence_threshold_secs" => "0.84",
             "include_timestamps" => "false",
             "enable_logging" => "false"
           }

    refute connection.url =~ "compatibility"
  end

  test "public options cannot alter private routing or the tone endpoint profile" do
    assert {:ok, %{model: "morse_stt_v1", encoding: :linear16, sample_rate: 16_000}} =
             STT.public_options([])

    for options <- [
          [model: "scribe_v2_realtime"],
          [sample_rate: 8_000],
          [encoding: :opus],
          [commit_strategy: :manual],
          [vad_silence_threshold_secs: 0.42],
          [endpoint: "wss://elsewhere.test"],
          [api_key: "x"],
          [model: "morse_stt_v1", model: "morse_stt_v1"],
          [:invalid]
        ] do
      assert {:error, :invalid_configuration} = STT.public_options(options)
    end

    assert {:ok, endpoint} = Endpoint.new("https://morse.example.test")
    assert {:error, :invalid_configuration} = STT.new([], endpoint)
    assert {:error, :invalid_configuration} = STT.new([api_key: "x\ny"], endpoint)
    assert {:ok, config} = STT.new([api_key: "synthetic"], endpoint)
    assert String.starts_with?(STT.connection_options(config).url, "wss://morse.example.test/")
  end

  test "readiness requires the server to acknowledge the actual Morse endpoint profile" do
    ready = %{
      "message_type" => "session_started",
      "session_id" => "morse-session",
      "config" => %{
        "model_id" => "morse_stt_v1",
        "sample_rate" => 16_000,
        "audio_format" => "pcm_16000",
        "commit_strategy" => "vad",
        "vad_silence_threshold_secs" => 0.84
      }
    }

    assert {:ok, {:ready, "morse-session"}} = STT.decode(JSON.encode!(ready))

    for key <- Map.keys(ready["config"]) do
      assert {:error, :invalid_message} =
               STT.decode(JSON.encode!(update_in(ready, ["config"], &Map.delete(&1, key))))

      assert {:error, :invalid_message} =
               STT.decode(JSON.encode!(put_in(ready, ["config", key], "wrong")))
    end

    assert {:error, :invalid_message} =
             STT.decode(
               JSON.encode!(put_in(ready, ["config", "vad_silence_threshold_secs"], 0.42))
             )
  end

  test "wire messages preserve partial and segment evidence and never synthesize readiness" do
    assert {:ok, payload} = STT.encode_audio(<<1, 0, 2, 0>>)

    assert JSON.decode!(payload) == %{
             "message_type" => "input_audio_chunk",
             "audio_base_64" => "AQACAA==",
             "commit" => false,
             "sample_rate" => 16_000
           }

    assert JSON.decode!(STT.keepalive())["audio_base_64"] == ""
    assert JSON.decode!(STT.keepalive())["commit"] == false

    for audio <- ["", <<1>>, :binary.copy(<<0>>, 32_002), nil] do
      assert {:error, :invalid_audio} = STT.encode_audio(audio)
    end

    for {type, event} <- [{"partial_transcript", :partial}, {"committed_transcript", :segment}] do
      assert {:ok, {^event, "SOS"}} =
               STT.decode(JSON.encode!(%{"message_type" => type, "text" => "SOS"}))
    end

    assert {:error, :provider_failure} =
             STT.decode(~s({"message_type":"input_error","error":"private-input"}))

    assert {:error, :invalid_message} = STT.decode(~s({"message_type":"unknown"}))
    assert {:error, :invalid_message} = STT.decode(<<255>>)
  end
end
