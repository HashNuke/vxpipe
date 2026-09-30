defmodule Vxpipe.Providers.ElevenLabs.AgentProtocolTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.ElevenLabs.AgentProtocol

  test "readiness requires the negotiated input and output PCM formats" do
    metadata = %{
      "conversation_id" => "conversation-synthetic",
      "agent_output_audio_format" => "pcm_16000",
      "user_input_audio_format" => "pcm_16000"
    }

    assert {:ok, {:ready, "conversation-synthetic"}} =
             decode(
               "conversation_initiation_metadata",
               "conversation_initiation_metadata_event",
               metadata
             )

    for field <- ["agent_output_audio_format", "user_input_audio_format"] do
      assert {:error, :invalid_message} =
               decode(
                 "conversation_initiation_metadata",
                 "conversation_initiation_metadata_event",
                 Map.put(metadata, field, "ulaw_8000")
               )
    end
  end

  test "preserves transcript, response and correction identities without inventing room turns" do
    assert {:ok, {:user_transcript, 4, "Hello"}} =
             decode("user_transcript", "user_transcription_event", %{
               "event_id" => 4,
               "user_transcript" => "Hello"
             })

    assert {:ok, {:agent_response, 5, "response-synthetic", "Welcome"}} =
             decode("agent_response", "agent_response_event", %{
               "event_id" => 5,
               "response_id" => "response-synthetic",
               "agent_response" => "Welcome"
             })

    assert {:ok, {:agent_response_correction, 5, "response-synthetic", "Wel"}} =
             decode("agent_response_correction", "agent_response_correction_event", %{
               "event_id" => 5,
               "response_id" => "response-synthetic",
               "original_agent_response" => "Welcome",
               "corrected_agent_response" => "Wel"
             })

    assert {:error, :invalid_message} =
             decode("agent_response", "agent_response_event", %{
               "event_id" => 5,
               "agent_response" => "Missing identity"
             })
  end

  test "decodes bounded aligned PCM with its native final marker and optional character timing" do
    pcm = <<1, 0, 2, 0>>
    audio = %{"event_id" => 7, "audio_base_64" => Base.encode64(pcm)}
    assert {:ok, {:audio, 7, ^pcm, false, nil}} = decode("audio", "audio_event", audio)

    alignment = %{
      "chars" => ["H", "i"],
      "char_start_times_ms" => [0, 10],
      "char_durations_ms" => [10, 15]
    }

    assert {:ok, {:audio, 7, ^pcm, true, ^alignment}} =
             decode(
               "audio",
               "audio_event",
               Map.merge(audio, %{"is_final" => true, "alignment" => alignment})
             )

    for invalid <- [
          "invalid base64!",
          Base.encode64(<<1>>),
          Base.encode64(:binary.copy(<<0>>, 65_538))
        ] do
      assert {:error, :invalid_message} =
               decode("audio", "audio_event", Map.put(audio, "audio_base_64", invalid))
    end

    assert {:error, :invalid_message} =
             decode("audio", "audio_event", Map.put(audio, "is_final", "true"))

    assert {:error, :invalid_message} =
             decode(
               "audio",
               "audio_event",
               Map.put(audio, "alignment", Map.put(alignment, "char_durations_ms", []))
             )
  end

  test "completion and interruption are distinct native events, not inferred audio gaps" do
    assert {:ok, {:response_complete, 8}} =
             decode("agent_response_complete", "agent_response_complete_event", %{"event_id" => 8})

    assert {:ok, {:interrupted, 9}} =
             decode("interruption", "interruption_event", %{"event_id" => 9})

    assert {:ok, {:audio, 7, "", true, nil}} =
             decode("audio", "audio_event", %{
               "event_id" => 7,
               "audio_base_64" => "",
               "is_final" => true
             })

    assert {:error, :invalid_message} =
             decode("agent_response_complete", "agent_response_complete_event", %{})
  end

  test "forwards only character timing fields from optional audio alignment" do
    alignment = %{"chars" => ["H"], "char_start_times_ms" => [0], "char_durations_ms" => [10]}

    assert {:ok, {:audio, 7, <<1, 0>>, true, ^alignment}} =
             decode("audio", "audio_event", %{
               "event_id" => 7,
               "audio_base_64" => Base.encode64(<<1, 0>>),
               "is_final" => true,
               "alignment" => Map.put(alignment, "private", "synthetic-private-provider-detail")
             })
  end

  test "tool calls retain provider IDs, arguments and response expectations" do
    arguments = %{"city" => "Oslo"}

    assert {:ok,
            {:tool_call, 10,
             %{
               id: "tool-synthetic",
               name: "weather",
               arguments: ^arguments,
               expects_response?: true
             }}} =
             decode("client_tool_call", "client_tool_call", %{
               "event_id" => 10,
               "tool_call_id" => "tool-synthetic",
               "tool_name" => "weather",
               "parameters" => arguments,
               "expects_response" => true
             })

    assert {:error, :invalid_message} =
             decode("client_tool_call", "client_tool_call", %{
               "event_id" => 10,
               "tool_call_id" => "tool-synthetic",
               "tool_name" => "weather",
               "parameters" => [],
               "expects_response" => true
             })
  end

  test "validates voice scores, opaque ping identity and concurrency admission separately" do
    assert {:ok, {:vad, 0.9}} = decode("vad_score", "vad_score_event", %{"vad_score" => 0.9})

    assert {:error, :invalid_message} =
             decode("vad_score", "vad_score_event", %{"vad_score" => 1.1})

    assert {:ok, {:ping, 11}} =
             decode("ping", "ping_event", %{"event_id" => 11, "ping_ms" => 20})

    assert {:ok, {:ping, 12}} = decode("ping", "ping_event", %{"event_id" => 12})

    for estimate <- [nil, 20.5, -1, "synthetic-private-detail"] do
      assert {:ok, {:ping, 12}} =
               decode("ping", "ping_event", %{"event_id" => 12, "ping_ms" => estimate})
    end

    assert {:ok, {:ping, -1}} = decode("ping", "ping_event", %{"event_id" => -1})

    assert {:error, :invalid_message} =
             decode("ping", "ping_event", %{"event_id" => "synthetic-private-id"})

    for status <- ["waiting", "admitted", "timed_out"] do
      assert {:ok, {:queue_status, ^status}} =
               decode("queue_status", "queue_status_event", %{"status" => status})
    end

    assert {:error, :invalid_message} =
             decode("queue_status", "queue_status_event", %{"status" => "invented"})
  end

  test "encodes input PCM, initiation, ping acknowledgement and delegated tool results" do
    assert AgentProtocol.initiation() |> JSON.decode!() == %{
             "type" => "conversation_initiation_client_data"
           }

    assert {:ok, payload} = AgentProtocol.audio(<<1, 0>>)
    assert JSON.decode!(payload) == %{"user_audio_chunk" => Base.encode64(<<1, 0>>)}
    assert {:error, :invalid_audio} = AgentProtocol.audio(<<1>>)
    assert {:ok, payload} = AgentProtocol.pong(11)
    assert JSON.decode!(payload) == %{"type" => "pong", "event_id" => 11}
    assert {:ok, negative} = AgentProtocol.pong(-1)
    assert JSON.decode!(negative) == %{"type" => "pong", "event_id" => -1}

    assert {:ok, payload} = AgentProtocol.tool_result("tool-synthetic", "sunny", false)

    assert JSON.decode!(payload) == %{
             "type" => "client_tool_result",
             "tool_call_id" => "tool-synthetic",
             "result" => "sunny",
             "is_error" => false
           }

    assert {:error, :invalid_message} = AgentProtocol.tool_result("", "sunny", false)
  end

  test "distinguishes response-triggering user text from a background contextual update" do
    assert {:ok, user} = AgentProtocol.user_message("Hello")
    assert JSON.decode!(user) == %{"type" => "user_message", "text" => "Hello"}
    assert {:ok, context} = AgentProtocol.contextual_update("Room instruction")
    assert JSON.decode!(context) == %{"type" => "contextual_update", "text" => "Room instruction"}
    assert {:error, :invalid_message} = AgentProtocol.user_message(String.duplicate("a", 65_537))
  end

  test "fails closed on malformed messages without returning raw private provider payloads" do
    for payload <- [
          <<255>>,
          "[]",
          "null",
          JSON.encode!(%{"type" => "unknown", "private" => "synthetic-secret"}),
          String.duplicate("a", 262_145)
        ] do
      assert {:error, :invalid_message} = AgentProtocol.decode(payload)
    end

    assert {:error, :invalid_message} =
             decode("user_transcript", "user_transcription_event", %{
               "event_id" => "synthetic-private-id",
               "user_transcript" => "Hello"
             })
  end

  test "preserves only the numeric provider failure code from a native client error" do
    assert {:ok, {:provider_error, 501}} =
             decode("client_error", "error_event", %{
               "code" => 501,
               "error_name" => "synthetic-private-name",
               "message" => "synthetic-private-message"
             })
  end

  defp decode(type, field, event),
    do: AgentProtocol.decode(JSON.encode!(%{"type" => type, field => event}))
end
