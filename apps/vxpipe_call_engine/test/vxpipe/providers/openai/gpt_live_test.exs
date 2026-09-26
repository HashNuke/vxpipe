defmodule Vxpipe.Providers.OpenAI.GPTLiveTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.OpenAI.{GPTLive, GPTLiveSession}

  test "configures one fixed duplex model and a private credential" do
    assert {:ok, descriptor} = GPTLiveSession.configure(backend_model: "gpt-5.6")
    assert descriptor.kind == :sts
    assert descriptor.settings.model == "gpt-live-1"
    assert descriptor.settings.voice == "marin"
    assert descriptor.settings.backend_model == "gpt-5.6"
    assert descriptor.turn_control == "provider"
    assert descriptor.endpointing == :inferred_gap
    assert descriptor.output_shape == :continuous
    assert descriptor.barge_in == :provider
    assert descriptor.continuity == :history_reseed
    assert descriptor.hold == :mute
    assert descriptor.input_format.sample_rate == 24_000
    assert descriptor.format.sample_rate == 24_000

    for options <- [
          [model: "other", backend_model: "gpt-5.6"],
          [backend_model: "gpt-5.6", voice: "bad voice"],
          [backend_model: "gpt-5.6", input_sample_rate: 8_000],
          [backend_model: "gpt-5.6", output_sample_rate: 16_000],
          [backend_model: "gpt-5.6", unknown: true]
        ] do
      assert {:error, :invalid_configuration} = GPTLiveSession.configure(options)
    end

    assert {:ok, config} = GPTLive.new(api_key: "synthetic-secret", backend_model: "gpt-5.6")
    refute inspect(config) =~ "synthetic-secret"

    assert GPTLive.connection_options(config) == %{
             url: "wss://api.openai.com/v1/live/sessions",
             headers: [{"authorization", "Bearer synthetic-secret"}]
           }
  end

  test "startup and audio commands use the documented JSON protocol" do
    assert {:ok, config} = GPTLive.new(api_key: "synthetic", backend_model: "gpt-5.6")

    assert GPTLive.start(config, []) == %{
             "type" => "session.start",
             "session" => %{
               "model" => "gpt-live-1",
               "instructions" => "",
               "input" => [],
               "audio" => %{
                 "format" => %{"type" => "audio/pcm", "rate" => 24_000},
                 "output" => %{"voice" => "marin"}
               },
               "delegation" => %{
                 "type" => "responses",
                 "responses" => %{"model" => "gpt-5.6", "tools" => []}
               },
               "store" => false
             }
           }

    assert {:ok, %{"type" => "session.input_audio.append", "audio" => "AQA="}} =
             GPTLive.audio_append(<<1, 0>>)

    assert {:error, :invalid_audio} = GPTLive.audio_append(<<1>>)
    assert {:error, :invalid_audio} = GPTLive.audio_append("")
  end

  test "decodes typed events and rejects malformed or unknown events" do
    assert {:ok, {:started, "session_1"}} =
             GPTLive.decode(~s({"type":"session.started","session":{"id":"session_1"}}))

    assert {:ok, {:input_fragment, %{text: "Hi", start_ms: 10, end_ms: 80}}} =
             GPTLive.decode(
               ~s({"type":"session.input_transcript.delta","delta":"Hi","start_ms":10,"end_ms":80})
             )

    assert {:ok, {:output_fragment, %{text: "Hello", start_ms: 100, end_ms: 350}}} =
             GPTLive.decode(
               ~s({"type":"session.output_transcript.delta","delta":"Hello","start_ms":100,"end_ms":350})
             )

    assert {:ok, {:output_audio, <<1, 0>>}} =
             GPTLive.decode(~s({"type":"session.output_audio.delta","delta":"AQA="}))

    assert {:error, :invalid_message} = GPTLive.decode("{")
    assert {:error, :invalid_message} = GPTLive.decode(~s({"type":"unknown.event"}))

    assert {:error, :invalid_message} =
             GPTLive.decode(~s({"type":"session.output_audio.delta","delta":"AQ=="}))
  end
end
