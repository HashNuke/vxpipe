defmodule Vxpipe.Providers.Google.TTSTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.Google.{TTS, TTSStream}
  alias Vxpipe.CallEngine.{CapabilityCatalog, TextToSpeechRuntime}
  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.Providers.Registry

  test "a voice selection yields the dedicated streaming TTS request and fixed PCM format" do
    assert {:ok, config} = TTS.new(api_key: "synthetic-key", voice: "Kore")
    refute inspect(config) =~ "synthetic-key"

    assert {:ok, public} =
             TTS.public_options(model: "gemini-3.1-flash-tts-preview", voice: "Kore")

    assert public.sample_rate == 24_000

    assert TTS.request_body(config, "Hello") == %{
             model: "gemini-3.1-flash-tts-preview",
             input: "Hello",
             response_format: %{type: "audio"},
             generation_config: %{speech_config: [%{voice: "Kore"}]},
             stream: true
           }

    assert {:error, :invalid_configuration} = TTS.new(api_key: "synthetic-key", model: "gemini")
    assert {:error, :invalid_configuration} = TTS.new(api_key: "synthetic-key", voice: "")
    assert {:error, :invalid_text} = TTS.validate_text(" ")
  end

  test "fragmented SSE yields bounded PCM and requires a completed interaction" do
    pcm = <<1, 0, 2, 0>>

    audio =
      JSON.encode!(%{
        "event_type" => "step.delta",
        "delta" => %{"type" => "audio", "data" => Base.encode64(pcm), "mime_type" => "audio/l16"}
      })

    completed =
      JSON.encode!(%{
        "event_type" => "interaction.completed",
        "interaction" => %{"status" => "completed"}
      })

    stream = "data: #{audio}\n\ndata: #{completed}\n\n"
    {first, second} = :erlang.split_binary(stream, 17)

    assert {:ok, state, []} = TTSStream.feed(TTSStream.new(), first)
    assert {:ok, state, [{:audio, ^pcm}, :completed]} = TTSStream.feed(state, second)
    assert :ok = TTSStream.finish(state)
    assert {:error, :incomplete_stream} = TTSStream.finish(TTSStream.new())

    assert {:error, :invalid_stream} =
             TTSStream.feed(
               TTSStream.new(),
               "data: " <>
                 JSON.encode!(%{
                   "event_type" => "step.delta",
                   "delta" => %{"type" => "audio", "data" => "bad", "mime_type" => "audio/l16"}
                 }) <> "\n\n"
             )
  end

  test "the declared TTS capability accepts a call selection without exposing credentials" do
    assert {:ok, Vxpipe.Providers.Google.TTSSession} =
             Registry.fetch_capability("google", :tts)

    assert {:ok, selection} =
             CapabilitySelection.new(
               %{
                 provider: "google",
                 model: "gemini-3.1-flash-tts-preview",
                 options: %{"voice" => "Kore"}
               },
               :text_to_speech,
               ["text_to_speech"]
             )

    assert {:ok, Vxpipe.Providers.Google.TTSSession} = CapabilityCatalog.adapter(selection)
    assert {:ok, public} = CapabilityCatalog.speech_options(selection)
    assert public[:voice] == "Kore"
    assert {:ok, config} = TTS.new(Keyword.put(public, :api_key, "synthetic-key"))

    assert {:ok, {Vxpipe.Providers.Google.TTSSession, options}, private, descriptor} =
             TextToSpeechRuntime.provider(
               {Vxpipe.Providers.Google.TTSSession, config},
               enabled: true,
               maximum_requests: 2
             )

    assert options[:voice] == "Kore"
    assert private[:config] == config
    assert descriptor.usage_identity.provider == :google
    refute inspect(private) =~ "synthetic-key"
  end
end
