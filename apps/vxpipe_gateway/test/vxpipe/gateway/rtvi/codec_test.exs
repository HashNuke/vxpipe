defmodule Vxpipe.Gateway.RTVI.CodecTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Gateway.RTVI.Codec

  alias Vxpipe.CallEngine.Event.{
    AgentSpeechStarted,
    AgentTurnFailed,
    AgentTurnInterrupted,
    ParticipantTranscription,
    TextOutput,
    ToolCallCancelled,
    ToolCallCompleted,
    ToolCallStarted
  }

  test "defers a compatible client-ready reply to the owning connection" do
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

    assert {:command, {:client_ready, "ready-1"}} = Codec.handle(client_ready)
    reply = Codec.encode_bot_ready("ready-1")

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

  test "projects the RTVI 2.x lifecycle for spoken bot output" do
    output = text_output(will_be_spoken: true)

    assert {:ok, announced} = Codec.encode_event(output)

    assert %{
             "id" => "evt_output",
             "type" => "bot-output",
             "data" => %{
               "text" => "Echo: hello",
               "segment_id" => 1,
               "will_be_spoken" => true,
               "spoken_status" => "new"
             }
           } = JSON.decode!(announced)

    assert {:ok, started} =
             Codec.encode_spoken_progress(output, "evt_speech", :in_progress)

    assert %{
             "id" => "evt_speech-progress",
             "type" => "bot-output",
             "data" => %{
               "text" => "Echo: hello",
               "segment_id" => 1,
               "will_be_spoken" => true,
               "spoken_status" => "in-progress",
               "spoken_progress" => %{
                 "accumulated_text" => "",
                 "remaining_text" => "Echo: hello"
               }
             }
           } = JSON.decode!(started)

    assert {:ok, completed} =
             Codec.encode_spoken_progress(output, "evt_completed", :completed)

    assert %{
             "id" => "evt_completed-progress",
             "type" => "bot-output",
             "data" => %{
               "text" => "Echo: hello",
               "segment_id" => 1,
               "will_be_spoken" => true,
               "spoken_status" => "completed",
               "spoken_progress" => %{
                 "accumulated_text" => "Echo: hello",
                 "remaining_text" => ""
               }
             }
           } = JSON.decode!(completed)
  end

  test "projects a failed model turn as a correlated retryable response" do
    event = %AgentTurnFailed{
      id: "evt_failed",
      sequence: 9,
      tenant_id: "tenant-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      participant_id: "part-agent",
      source_participant_id: "part-human",
      connection_id: "conn-demo",
      command_id: "cmd-text",
      correlation_id: "client-text-failed",
      reason: :provider_timeout,
      retryable: true,
      occurred_at: ~U[2026-09-04 21:00:00.000Z]
    }

    assert {:ok, encoded} = Codec.encode_event(event)

    assert %{
             "id" => "client-text-failed",
             "label" => "rtvi-ai",
             "type" => "error-response",
             "data" => %{"error" => "The agent could not generate a response. Please try again."}
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

  test "projects a standard bot interruption and separately preserves room attribution" do
    event = %AgentTurnInterrupted{
      id: "evt_interrupted",
      sequence: 9,
      tenant_id: "tenant-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      participant_id: "part-agent",
      source_participant_id: "part-originator",
      connection_id: "conn-originator",
      command_id: "cmd-original",
      correlation_id: "turn-original",
      interrupted_by_participant_id: "part-interrupter",
      interrupted_by_connection_id: "conn-interrupter",
      interruption_command_id: "cmd-interrupter",
      interruption_correlation_id: "turn-interrupter",
      played_ms: 320,
      occurred_at: ~U[2026-09-05 02:30:00.000Z]
    }

    assert {:ok, standard} = Codec.encode_event(event)

    assert %{
             "id" => "evt_interrupted",
             "label" => "rtvi-ai",
             "type" => "bot-interrupted",
             "data" => nil
           } = JSON.decode!(standard)

    assert {:ok, attributed} = Codec.encode_interruption_context(event)

    assert %{
             "id" => "evt_interrupted-context",
             "label" => "rtvi-ai",
             "type" => "server-message",
             "data" => %{
               "t" => "vxpipe.turn",
               "v" => 1,
               "d" => %{
                 "kind" => "interrupted",
                 "turn" => %{
                   "agent_participant_id" => "part-agent",
                   "source_participant_id" => "part-originator",
                   "connection_id" => "conn-originator",
                   "command_id" => "cmd-original",
                   "correlation_id" => "turn-original",
                   "played_ms" => 320
                 },
                 "interrupted_by" => %{
                   "participant_id" => "part-interrupter",
                   "connection_id" => "conn-interrupter",
                   "command_id" => "cmd-interrupter",
                   "correlation_id" => "turn-interrupter"
                 }
               }
             }
           } = JSON.decode!(attributed)
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

  test "projects tool execution through the RTVI function-call lifecycle" do
    fields = %{
      id: "evt-tool-started",
      sequence: 3,
      tenant_id: "tenant-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      participant_id: "part-agent",
      source_participant_id: "part-human",
      connection_id: "conn-demo",
      command_id: "cmd-text",
      correlation_id: "turn-tool",
      tool_call_id: "tool-1",
      name: "get_current_time",
      occurred_at: ~U[2026-09-05 11:00:00.000Z]
    }

    started = struct!(ToolCallStarted, Map.put(fields, :arguments, %{}))
    assert {:ok, encoded} = Codec.encode_event(started)

    assert %{
             "type" => "llm-function-call-in-progress",
             "data" => %{
               "tool_call_id" => "tool-1",
               "function_name" => "get_current_time",
               "arguments" => %{}
             }
           } = JSON.decode!(encoded)

    completed =
      fields
      |> Map.put(:id, "evt-tool-completed")
      |> Map.put(:result, %{"timezone" => "UTC"})
      |> then(&struct!(ToolCallCompleted, &1))

    assert {:ok, encoded} = Codec.encode_event(completed)

    assert %{
             "type" => "llm-function-call-stopped",
             "data" => %{
               "tool_call_id" => "tool-1",
               "function_name" => "get_current_time",
               "cancelled" => false,
               "result" => %{"timezone" => "UTC"}
             }
           } = JSON.decode!(encoded)

    cancelled =
      fields
      |> Map.put(:id, "evt-tool-cancelled")
      |> then(&struct!(ToolCallCancelled, &1))

    assert {:ok, encoded} = Codec.encode_event(cancelled)

    assert %{
             "type" => "llm-function-call-stopped",
             "data" => %{"tool_call_id" => "tool-1", "cancelled" => true}
           } = JSON.decode!(encoded)
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

  defp text_output(options) do
    %TextOutput{
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
      will_be_spoken: Keyword.fetch!(options, :will_be_spoken),
      occurred_at: ~U[2026-09-03 18:30:00.000Z]
    }
  end
end
