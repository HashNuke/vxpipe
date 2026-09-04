defmodule Vxpipe.Gateway.RTVI.CodecTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Gateway.RTVI.Codec
  alias Vxpipe.CallEngine.Event.{AgentSpeechStarted, ParticipantTranscription, TextOutput}

  test "answers a current RTVI 2.x client-ready message with bot-ready" do
    client_ready =
      JSON.encode!(%{
        "id" => "ready-1",
        "label" => "rtvi-ai",
        "type" => "client-ready",
        "data" => %{
          "version" => "2.1.0",
          "about" => %{"library" => "@pipecat-ai/client-js", "library_version" => "1.13.0"}
        }
      })

    assert {:reply, reply} = Codec.handle(client_ready)

    assert %{
             "id" => "ready-1",
             "label" => "rtvi-ai",
             "type" => "bot-ready",
             "data" => %{
               "version" => "2.1.0",
               "about" => %{"library" => "vxpipe", "library_version" => "0.1.0"}
             }
           } = JSON.decode!(reply)
  end

  test "rejects unsupported protocol majors without closing the transport" do
    client_ready =
      JSON.encode!(%{
        "id" => "ready-future",
        "label" => "rtvi-ai",
        "type" => "client-ready",
        "data" => %{
          "version" => "3.0.0",
          "about" => %{"library" => "future-client"}
        }
      })

    assert {:reply, reply} = Codec.handle(client_ready)

    assert %{
             "id" => "ready-future",
             "label" => "rtvi-ai",
             "type" => "error-response",
             "data" => %{"error" => error}
           } = JSON.decode!(reply)

    assert error =~ "not compatible"
  end

  test "rejects malformed semantic versions" do
    client_ready =
      JSON.encode!(%{
        "id" => "ready-malformed",
        "label" => "rtvi-ai",
        "type" => "client-ready",
        "data" => %{"version" => "2.-1.0"}
      })

    assert {:reply, reply} = Codec.handle(client_ready)

    assert %{
             "id" => "ready-malformed",
             "type" => "error-response"
           } = JSON.decode!(reply)
  end

  test "decodes a send-text command and projects protocol-neutral output" do
    payload =
      JSON.encode!(%{
        "id" => "client-text-1",
        "label" => "rtvi-ai",
        "type" => "send-text",
        "data" => %{
          "content" => "hello",
          "options" => %{"run_immediately" => true, "audio_response" => true}
        }
      })

    assert {:command,
            {:send_text,
             %{
               id: "client-text-1",
               content: "hello",
               run_immediately: true,
               audio_response: true
             }}} = Codec.handle(payload)

    event = %TextOutput{
      id: "evt_output",
      sequence: 1,
      tenant_id: "tenant-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      participant_id: "part-agent",
      source_participant_id: "part-human",
      connection_id: "conn-demo",
      command_id: "cmd-text",
      correlation_id: "client-text-1",
      text: "Echo: hello",
      aggregated_by: :sentence,
      will_be_spoken: false,
      occurred_at: ~U[2026-09-03 18:30:00.000Z]
    }

    assert {:ok, encoded} = Codec.encode_event(event)

    assert %{
             "id" => "evt_output",
             "label" => "rtvi-ai",
             "type" => "bot-output",
             "data" => %{
               "text" => "Echo: hello",
               "aggregated_by" => "sentence",
               "segment_id" => 1,
               "will_be_spoken" => false
             }
           } = JSON.decode!(encoded)
  end

  test "correlates invalid send-text options without emitting an engine command" do
    payload =
      JSON.encode!(%{
        "id" => "client-text-invalid",
        "label" => "rtvi-ai",
        "type" => "send-text",
        "data" => %{
          "content" => "hello",
          "options" => %{"audio_response" => "yes"}
        }
      })

    assert {:reply, reply} = Codec.handle(payload)

    assert %{
             "id" => "client-text-invalid",
             "type" => "error-response",
             "data" => %{"error" => "The send-text options are invalid."}
           } = JSON.decode!(reply)
  end

  test "projects replacement user transcription with the RTVI final boundary" do
    event = %ParticipantTranscription{
      id: "evt_transcription",
      sequence: 7,
      tenant_id: "tenant-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      participant_id: "part-human",
      connection_id: "conn-demo",
      command_id: "cmd-audio",
      correlation_id: "turn-audio",
      text: "hello there",
      final: false,
      provider_turn_index: 2,
      occurred_at: ~U[2026-09-04 12:00:00.000Z]
    }

    assert {:ok, partial} = Codec.encode_event(event)

    assert %{
             "id" => "evt_transcription",
             "label" => "rtvi-ai",
             "type" => "user-transcription",
             "data" => %{
               "text" => "hello there",
               "final" => false,
               "timestamp" => "2026-09-04T12:00:00.000Z",
               "user_id" => "part-human"
             }
           } = JSON.decode!(partial)

    assert {:ok, final} = Codec.encode_event(%{event | id: "evt_final", final: true})
    assert %{"data" => %{"final" => true}} = JSON.decode!(final)
  end

  test "projects actual output playout as bot-started-speaking" do
    event = %AgentSpeechStarted{
      id: "evt_speech",
      sequence: 8,
      tenant_id: "tenant-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      participant_id: "part-agent",
      source_participant_id: "part-human",
      connection_id: "conn-demo",
      command_id: "cmd-audio",
      correlation_id: "turn-audio",
      occurred_at: ~U[2026-09-04 12:00:00.000Z]
    }

    assert {:ok, encoded} = Codec.encode_event(event)

    assert %{
             "id" => "evt_speech",
             "label" => "rtvi-ai",
             "type" => "bot-started-speaking",
             "data" => nil
           } = JSON.decode!(encoded)
  end

  test "applies RTVI defaults when send-text options are omitted" do
    payload =
      JSON.encode!(%{
        "id" => "client-text-defaults",
        "label" => "rtvi-ai",
        "type" => "send-text",
        "data" => %{"content" => "hello"}
      })

    assert {:command,
            {:send_text,
             %{
               id: "client-text-defaults",
               content: "hello",
               run_immediately: true,
               audio_response: true
             }}} = Codec.handle(payload)
  end

  test "ignores Small WebRTC signalling and keepalive messages" do
    assert :ignore =
             Codec.handle(
               JSON.encode!(%{
                 "type" => "signalling",
                 "message" => %{"type" => "trackStatus", "receiver_index" => 0, "enabled" => true}
               })
             )

    assert :ignore = Codec.handle("ping: 1788470000000")
  end
end
