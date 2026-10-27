defmodule Vxpipe.Providers.ElevenLabs.RealtimeTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.ElevenLabs.{Realtime, RealtimeSession}

  test "both standalone models use native turn detection and no local detector" do
    for model <- ["eleven_realtime_v1_mini", "eleven_realtime_v1_max"] do
      assert {:ok, descriptor} = RealtimeSession.configure(model: model)
      assert descriptor.kind == :sts
      assert descriptor.endpointing == :provider_semantic
      assert descriptor.turn_control == "provider"
      assert descriptor.turn_control_supported == ["provider"]
      assert descriptor.speech_start?
      assert descriptor.input_transcript? and descriptor.output_transcript?
      assert descriptor.response_start?
      assert descriptor.input_format.sample_rate == 24_000
      assert descriptor.format.sample_rate == 24_000
      assert descriptor.usage_identity.provider == :elevenlabs
      assert descriptor.usage_identity.model == model

      assert {:ok, config} = Realtime.new(api_key: "synthetic-key", model: model)
      session = Realtime.session(config)
      assert session["model"] == model
      assert session["audio"]["input"]["turn_detection"]["type"] == "semantic_vad"
      assert session["audio"]["input"]["turn_detection"]["create_response"] == true
      assert session["audio"]["input"]["turn_detection"]["interrupt_response"] == false
      refute Map.has_key?(session, "agent_id")
      refute inspect(config) =~ "synthetic-key"
    end
  end

  test "configuration rejects agents, unrecognized models, secrets and external VAD options" do
    for options <- [
          [model: "eleven_flash_v2_5"],
          [agent_id: "agent_x"],
          [api_key: "private"],
          [turn_control: "external"],
          [model: "eleven_realtime_v1_mini", model: "eleven_realtime_v1_max"],
          [voice: "\ninvalid"],
          [vad: "silero"]
        ] do
      assert {:error, :invalid_configuration} = RealtimeSession.configure(options)
    end
  end

  test "audio encoding rejects malformed or oversized PCM" do
    assert {:ok, %{"type" => "input_audio_buffer.append", "audio" => "AQACAA=="}} =
             Realtime.audio(<<1, 0, 2, 0>>)

    for pcm <- [<<>>, <<1>>, :binary.copy(<<0>>, 65_538)] do
      assert {:error, :invalid_audio} = Realtime.audio(pcm)
    end
  end

  test "decoding bounds audio, text and provider error details" do
    assert {:ok, {:audio, "resp_1", <<1, 0>>}} =
             decode(%{
               "type" => "response.output_audio.delta",
               "response_id" => "resp_1",
               "delta" => "AQA="
             })

    assert {:error, :invalid_message} =
             decode(%{
               "type" => "response.output_audio.delta",
               "response_id" => "resp_1",
               "delta" => "AQ=="
             })

    assert {:error, :provider_error} =
             decode(%{"type" => "error", "error" => %{"message" => "private"}})

    assert {:error, :invalid_message} = Realtime.decode(:binary.copy("x", 262_145))

    assert {:error, :invalid_message} =
             decode(%{
               "type" => "response.created",
               "response" => %{"id" => "resp_1", "metadata" => "malformed-private-data"}
             })

    assert {:ok, :ignored} = decode(%{"type" => "rate_limits.updated", "rate_limits" => []})
  end

  defp decode(message), do: Realtime.decode(JSON.encode!(message))
end
