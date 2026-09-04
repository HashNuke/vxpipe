defmodule Vxpipe.CallEngine.Provider.Deepgram.FluxTextToSpeechTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Provider.Deepgram.FluxTextToSpeech
  alias Vxpipe.CallEngine.Provider.TextToSpeech.Signal

  test "builds a redacted streaming linear16 connection" do
    assert {:ok, provider} =
             FluxTextToSpeech.new(
               api_key: "secret-value",
               model: "flux-haley-en",
               encoding: :linear16,
               sample_rate: 48_000
             )

    assert inspect(provider) =~ "flux-haley-en"
    refute inspect(provider) =~ "secret-value"

    connection = FluxTextToSpeech.connection_options(provider)
    uri = URI.parse(connection.url)
    query = URI.decode_query(uri.query)

    assert uri.scheme == "wss"
    assert uri.host == "api.deepgram.com"
    assert uri.path == "/v2/speak"

    assert query == %{
             "encoding" => "linear16",
             "model" => "flux-haley-en",
             "sample_rate" => "48000"
           }

    assert connection.headers == [{"Authorization", "Token secret-value"}]

    assert FluxTextToSpeech.media_format(provider) ==
             %{codec: :linear16, sample_rate: 48_000, channels: 1, byte_order: :little}
  end

  test "rejects unsupported streaming configurations" do
    refute match?({:ok, _provider}, FluxTextToSpeech.new(api_key: "key", encoding: :opus))
    refute match?({:ok, _provider}, FluxTextToSpeech.new(api_key: "", encoding: :linear16))

    refute match?(
             {:ok, _provider},
             FluxTextToSpeech.new(api_key: "key", encoding: :linear16, sample_rate: 44_000)
           )
  end

  test "encodes text and flush controls exactly" do
    assert JSON.decode!(FluxTextToSpeech.encode_speak("Hello ")) ==
             %{"type" => "Speak", "text" => "Hello "}

    assert JSON.decode!(FluxTextToSpeech.encode_flush()) == %{"type" => "Flush"}
  end

  test "decodes speech boundaries, warnings, errors, and binary audio" do
    assert {:ok, %Signal{kind: :connected, request_id: "req_1"}} =
             FluxTextToSpeech.decode(~s({"type":"Connected","request_id":"req_1"}))

    assert {:ok, %Signal{kind: :speech_started, provider_speech_id: "dg_sp_123abc"}} =
             FluxTextToSpeech.decode(~s({"type":"SpeechStarted","speech_id":"dg_sp_123abc"}))

    assert {:ok, %Signal{kind: :flushed, provider_speech_id: "dg_sp_123abc"}} =
             FluxTextToSpeech.decode(~s({"type":"Flushed","speech_id":"dg_sp_123abc"}))

    assert {:ok, %Signal{kind: :speech_completed, provider_speech_id: "dg_sp_123abc"}} =
             FluxTextToSpeech.decode(
               ~s({"type":"SpeechMetadata","speech_id":"dg_sp_123abc","audio_duration_ms":42})
             )

    assert {:ok, %Signal{kind: :warning, provider_code: "NO_ACTIVE_SPEECH"}} =
             FluxTextToSpeech.decode(
               ~s({"type":"Warning","request_id":"req_1","code":"NO_ACTIVE_SPEECH","description":"ignored"})
             )

    assert {:ok, %Signal{kind: :failed, provider_code: "MESSAGE_INVALID"}} =
             FluxTextToSpeech.decode(
               ~s({"type":"Error","request_id":"req_1","code":"MESSAGE_INVALID","description":"ignored"})
             )

    assert {:audio, <<1, 2, 3, 4>>} = FluxTextToSpeech.decode_audio(<<1, 2, 3, 4>>)
  end

  test "rejects malformed known controls and bounded input violations" do
    assert {:error, :invalid_message} = FluxTextToSpeech.decode(~s({"type":"SpeechStarted"}))
    assert {:ignore, :unknown_message} = FluxTextToSpeech.decode(~s({"type":"FutureMessage"}))

    oversized = String.duplicate("x", FluxTextToSpeech.maximum_message_bytes() + 1)
    assert {:error, :message_too_large} = FluxTextToSpeech.decode(oversized)

    assert {:error, :audio_too_large} =
             FluxTextToSpeech.decode_audio(
               :binary.copy(<<0>>, FluxTextToSpeech.maximum_audio_bytes() + 1)
             )
  end
end
