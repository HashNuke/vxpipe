defmodule Vxpipe.Providers.ElevenLabs.ScribeTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.ElevenLabs.Scribe

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
