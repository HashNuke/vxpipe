defmodule Vxpipe.Providers.ElevenLabs.ScribeTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.ElevenLabs.Scribe

  test "VAD configuration requests provider silence commits without exposing the key" do
    assert {:ok, config} =
             Scribe.new(api_key: "synthetic-scribe-private", commit_strategy: :vad)

    assert config.commit_strategy == :vad
    connection = Scribe.connection_options(config)

    assert URI.decode_query(URI.parse(connection.url).query) == %{
             "model_id" => "scribe_v2_realtime",
             "audio_format" => "pcm_16000",
             "commit_strategy" => "vad",
             "vad_silence_threshold_secs" => "1.5",
             "vad_threshold" => "0.4",
             "min_speech_duration_ms" => "100",
             "min_silence_duration_ms" => "100"
           }

    refute connection.url =~ "synthetic-scribe-private"
    refute inspect(config) =~ "synthetic-scribe-private"

    for invalid <- [nil, :invented, "vad"] do
      assert {:error, :invalid_configuration} = Scribe.public_options(commit_strategy: invalid)
    end
  end

  test "VAD readiness rejects changed detection settings while optional echoes may be absent" do
    profile = %{
      "commit_strategy" => "vad",
      "vad_silence_threshold_secs" => 1.5,
      "vad_threshold" => 0.4,
      "min_speech_duration_ms" => 100,
      "min_silence_duration_ms" => 100
    }

    ready = %{
      "message_type" => "session_started",
      "session_id" => "session-scribe-vad",
      "config" => profile
    }

    assert {:ok, {:ready, "session-scribe-vad"}} = Scribe.decode(JSON.encode!(ready), :vad)

    for field <- Map.keys(profile) do
      message = update_in(ready, ["config"], &Map.delete(&1, field))
      assert {:ok, {:ready, "session-scribe-vad"}} = Scribe.decode(JSON.encode!(message), :vad)
    end

    for {field, value} <- [
          {"vad_silence_threshold_secs", 3.0},
          {"vad_threshold", 0.8},
          {"min_speech_duration_ms", 250},
          {"min_silence_duration_ms", 250},
          {"vad_threshold", "0.4"},
          {"min_speech_duration_ms", nil}
        ] do
      message = put_in(ready, ["config", field], value)
      assert {:error, :invalid_message} = Scribe.decode(JSON.encode!(message), :vad)
    end
  end

  test "session acknowledgement is checked against the requested commit strategy" do
    ready = %{
      "message_type" => "session_started",
      "session_id" => "session-scribe-vad",
      "config" => %{"commit_strategy" => "vad"}
    }

    assert {:ok, {:ready, "session-scribe-vad"}} = Scribe.decode(JSON.encode!(ready), :vad)
    assert {:error, :invalid_message} = Scribe.decode(JSON.encode!(ready), :manual)

    manual = put_in(ready, ["config", "commit_strategy"], "manual")
    assert {:error, :invalid_message} = Scribe.decode(JSON.encode!(manual), :vad)

    absent = put_in(ready, ["config"], %{})
    assert {:ok, {:ready, "session-scribe-vad"}} = Scribe.decode(JSON.encode!(absent), :vad)

    segment = JSON.encode!(%{"message_type" => "committed_transcript", "text" => "Hello"})
    assert {:ok, {:segment, "Hello"}} = Scribe.decode(segment, :vad)
    assert {:error, :invalid_message} = Scribe.decode(segment, :invented)
  end

  test "keeps Scribe's scoped credential private and public configuration closed" do
    assert {:ok, config} = Scribe.new(api_key: "synthetic-scribe-private", language_code: "en")
    assert config.model == "scribe_v2_realtime"
    assert config.sample_rate == 16_000
    assert config.language_code == "en"
    refute inspect(config) =~ "synthetic-scribe-private"

    for options <- [
          [model: "invented"],
          [sample_rate: 8_000],
          [encoding: :opus],
          [language_code: "en-US"],
          [language_code: "en", language_code: "eng"],
          [commit_strategy: "vad"],
          [api_key: "synthetic"],
          [endpoint: "https://todo"],
          [wire_module: __MODULE__],
          [:invalid]
        ] do
      assert {:error, :invalid_configuration} = Scribe.public_options(options)
    end

    assert {:error, :invalid_configuration} = Scribe.new(api_key: "bad key")
    assert {:error, :invalid_configuration} = Scribe.new(api_key: "first", api_key: "second")
  end

  test "authenticates in headers and leaves segment finalization to an explicit boundary owner" do
    assert {:ok, config} = Scribe.new(api_key: "synthetic-scribe-private")
    connection = Scribe.connection_options(config)
    uri = URI.parse(connection.url)
    assert uri.scheme == "wss"
    assert uri.host == "api.elevenlabs.io"
    assert uri.path == "/v1/speech-to-text/realtime"

    assert URI.decode_query(uri.query) == %{
             "model_id" => "scribe_v2_realtime",
             "audio_format" => "pcm_16000",
             "commit_strategy" => "manual"
           }

    assert connection.headers == [{"xi-api-key", "synthetic-scribe-private"}]
    refute connection.url =~ "synthetic-scribe-private"
  end

  test "sends bounded aligned PCM separately from a transcript-segment commit" do
    assert {:ok, payload} = Scribe.encode_audio(<<1, 0, 2, 0>>)

    assert JSON.decode!(payload) == %{
             "message_type" => "input_audio_chunk",
             "audio_base_64" => Base.encode64(<<1, 0, 2, 0>>),
             "commit" => false,
             "sample_rate" => 16_000
           }

    assert JSON.decode!(Scribe.commit()) == %{
             "message_type" => "input_audio_chunk",
             "audio_base_64" => "",
             "commit" => true,
             "sample_rate" => 16_000
           }

    for invalid <- ["", <<1>>, :binary.copy(<<0, 0>>, 16_001), nil] do
      assert {:error, :invalid_audio} = Scribe.encode_audio(invalid)
    end
  end

  test "requires a matching session acknowledgement and preserves segment semantics" do
    ready = %{
      "message_type" => "session_started",
      "session_id" => "session-scribe",
      "config" => %{
        "model_id" => "scribe_v2_realtime",
        "sample_rate" => 16_000,
        "audio_format" => "pcm_16000",
        "commit_strategy" => "manual"
      }
    }

    assert {:ok, {:ready, "session-scribe"}} = Scribe.decode(JSON.encode!(ready))

    # The wire schema makes individual configuration fields optional.
    for field <- ["model_id", "sample_rate", "audio_format", "commit_strategy"] do
      message = update_in(ready, ["config"], &Map.delete(&1, field))
      assert {:ok, {:ready, "session-scribe"}} = Scribe.decode(JSON.encode!(message))
    end

    for {field, value} <- [
          {"model_id", "invented"},
          {"sample_rate", 8_000},
          {"audio_format", "ulaw_8000"},
          {"commit_strategy", "vad"}
        ] do
      message = put_in(ready, ["config", field], value)
      assert {:error, :invalid_message} = Scribe.decode(JSON.encode!(message))
    end

    for text <- ["", "Hello", "Hello again"] do
      assert {:ok, {:partial, ^text}} =
               Scribe.decode(
                 JSON.encode!(%{"message_type" => "partial_transcript", "text" => text})
               )
    end

    assert {:ok, {:segment, "Hello again"}} =
             Scribe.decode(
               JSON.encode!(%{"message_type" => "committed_transcript", "text" => "Hello again"})
             )

    # Neither a partial nor a stable segment is a speech-start or turn-end event.
    for message <- [
          %{"message_type" => "speech_started"},
          %{"message_type" => "turn_ended", "text" => "invented"},
          %{"message_type" => "partial_transcript", "text" => 1},
          %{"message_type" => "committed_transcript", "text" => String.duplicate("a", 65_537)},
          %{"message_type" => "session_started", "session_id" => "missing-config"}
        ] do
      assert {:error, :invalid_message} = Scribe.decode(JSON.encode!(message))
    end

    assert {:error, :invalid_message} = Scribe.decode(<<255>>)
    assert {:error, :invalid_message} = Scribe.decode(String.duplicate("a", 262_145))
  end

  test "sanitizes provider failures without exposing error text or credentials" do
    for type <- ["auth_error", "quota_exceeded", "error", "commit_throttled", "unaccepted_terms"] do
      assert {:error, :provider_failure} =
               Scribe.decode(
                 JSON.encode!(%{
                   "message_type" => type,
                   "error" => "synthetic-private-provider-detail"
                 })
               )
    end
  end
end
