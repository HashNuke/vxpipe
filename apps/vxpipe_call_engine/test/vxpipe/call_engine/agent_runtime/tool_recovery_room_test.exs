defmodule Vxpipe.CallEngine.AgentRuntime.ToolRecoveryRoomTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{ModelResponse, ToolCall}
  alias Vxpipe.CallEngine.{Event, TestBlockingTool, TestVoiceToolRoom}

  setup do
    TestVoiceToolRoom.configure()
    Application.put_env(:vxpipe_call_engine, :blocking_tool_observer, self())
    on_exit(fn -> Application.delete_env(:vxpipe_call_engine, :blocking_tool_observer) end)
    :ok
  end

  test "a failed streamed follow-up retains only the segment the caller heard" do
    {room, caller, voice, sink, worker} = start_lookup(agent_protocol: nil)
    assert_receive {:test_agent_runtime_stream, acknowledgement, _}
    {:ok, response} = ModelResponse.new(text: "Checking.")
    send(acknowledgement, {:test_agent_runtime_response, {:ok, response}})
    assert_receive {:test_tts_control, ^voice, _speak}
    TestVoiceToolRoom.settle(voice, sink, "checking", "service-turn")
    assert_receive {:vxpipe_event, %Event.AgentTurnCompleted{correlation_id: "service-turn"}}

    send(worker, :release_test_tool)
    assert_receive {:test_agent_runtime_stream, followup, request}
    correlation = request.correlation.correlation_id
    send(followup, {:test_agent_runtime_delta, "Your service is available. Unfinished"})
    assert_receive {:test_tts_control, ^voice, speak}
    assert JSON.decode!(speak)["text"] == "Your service is available."
    send(followup, {:test_agent_runtime_response, {:error, :provider_unavailable}})
    TestVoiceToolRoom.settle(voice, sink, "available", correlation)
    assert_receive {:vxpipe_event, %Event.AgentTurnFailed{correlation_id: ^correlation}}

    TestVoiceToolRoom.submit(room, caller, "Florida", "response-turn")
    assert_receive {:test_agent_runtime_stream, next, request}

    assert Enum.any?(
             request.messages,
             &(&1.role == :assistant and &1.content =~ "Your service is available.")
           )

    refute Enum.any?(request.messages, &(&1.content =~ "Unfinished"))
    assert JSON.decode!(List.last(request.messages).content)["message"] == "Florida"
    {:ok, response} = ModelResponse.new(text: "Thanks.")
    send(next, {:test_agent_runtime_response, {:ok, response}})
    assert_receive {:test_tts_control, ^voice, _speak}
    TestVoiceToolRoom.settle(voice, sink, "thanks", "response-turn")
    assert_receive {:vxpipe_event, %Event.AgentTurnCompleted{correlation_id: "response-turn"}}
    refute_receive {:test_agent_runtime_stream, _, _}
  end

  test "caller interruption cancels a tool-result retry and admits the answer" do
    {room, caller, voice, sink, worker} = start_lookup()
    assert_receive {:test_agent_runtime_stream, acknowledgement, _}
    TestVoiceToolRoom.reply(acknowledgement, :listener, nil)
    assert_receive {:vxpipe_event, %Event.AgentTurnCompleted{correlation_id: "service-turn"}}
    send(worker, :release_test_tool)
    assert_receive {:test_agent_runtime_stream, first, _}
    send(first, {:test_agent_runtime_response, {:error, :provider_unavailable}})
    assert_receive {:test_agent_runtime_stream, retry, retry_request}, 1_000
    monitor = Process.monitor(retry)
    correlation = retry_request.correlation.correlation_id

    TestVoiceToolRoom.submit(room, caller, "Florida", "interrupting-turn")
    assert_receive {:DOWN, ^monitor, :process, ^retry, _}
    assert_receive {:vxpipe_event, %Event.AgentTurnInterrupted{correlation_id: ^correlation}}
    assert_receive {:test_agent_runtime_stream, next, request}
    assert JSON.decode!(List.last(request.messages).content)["message"] == "Florida"
    assert Enum.count(request.messages, &(&1.origin == :engine)) == 1

    TestVoiceToolRoom.reply(next, :speaker, "Thank you.")
    assert_receive {:test_tts_control, ^voice, _speak}
    TestVoiceToolRoom.settle(voice, sink, "thanks", "interrupting-turn")
    assert_receive {:vxpipe_event, %Event.AgentTurnCompleted{correlation_id: "interrupting-turn"}}
    refute_receive {:test_agent_runtime_stream, _, _}
  end

  test "a departing caller's draining connection cannot receive late retry output" do
    {room, caller, voice, _, worker} = start_lookup()
    assert_receive {:test_agent_runtime_stream, acknowledgement, _}
    TestVoiceToolRoom.reply(acknowledgement, :listener, nil)
    assert_receive {:vxpipe_event, %Event.AgentTurnCompleted{correlation_id: "service-turn"}}
    send(worker, :release_test_tool)
    assert_receive {:test_agent_runtime_stream, first, _}
    send(first, {:test_agent_runtime_response, {:error, :provider_unavailable}})
    assert_receive {:test_agent_runtime_stream, retry, request}, 1_000
    turn = request.correlation.correlation_id
    monitor = Process.monitor(retry)

    [{authority, _}] =
      Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {room.tenant_id, room.room_id})

    state = :sys.get_state(authority)
    participant = Map.fetch!(state.participant_supervisors, caller.participant_id)

    assert :ok =
             Vxpipe.CallEngine.RoomParticipantSupervisor.stop_participant(
               room.incarnation_id,
               participant
             )

    assert_receive {:vxpipe_connection_unavailable, :participant_unavailable}
    assert_receive {:DOWN, ^monitor, :process, ^retry, _reason}
    TestVoiceToolRoom.reply(retry, :speaker, "Stale answer.")
    refute_receive {:test_tts_control, ^voice, _speak}
    refute_receive {:vxpipe_event, %Event.TextOutput{correlation_id: ^turn}}
  end

  test "exhausting a tool follow-up settles playback and answers the caller on the same connection" do
    {room, caller, voice, sink, worker} = start_lookup()
    assert_receive {:test_agent_runtime_stream, acknowledgement, _}

    TestVoiceToolRoom.reply(acknowledgement, :speaker, "Where are you located?")
    assert_receive {:test_tts_control, ^voice, speak}
    assert JSON.decode!(speak)["text"] == "Where are you located?"
    TestVoiceToolRoom.settle(voice, sink, "where", "service-turn")
    assert_receive {:vxpipe_event, %Event.AgentTurnCompleted{connection_id: connection_id}}

    send(worker, :release_test_tool)
    assert_receive {:vxpipe_event, %Event.ToolCallCompleted{tool_call_id: "intake-tool"}}
    assert_receive {:test_agent_runtime_stream, first, _}
    send(first, {:test_agent_runtime_response, {:error, :provider_unavailable}})
    assert_receive {:test_agent_runtime_stream, retry, _}, 1_000
    send(retry, {:test_agent_runtime_response, {:error, :provider_unavailable}})

    assert_receive {:vxpipe_event, %Event.AgentTurnFailed{connection_id: ^connection_id}}
    TestVoiceToolRoom.submit(room, caller, "Florida", "answer-turn")
    assert_receive {:vxpipe_event, %Event.ParticipantTurnCompleted{correlation_id: "answer-turn"}}
    assert_receive {:test_agent_runtime_stream, next, request}
    assert JSON.decode!(List.last(request.messages).content)["message"] == "Florida"

    assert Enum.any?(
             request.messages,
             &(&1.role == :assistant and &1.content =~ "Where are you located?")
           )

    assert [fact] = Enum.filter(request.messages, &(&1.origin == :engine))
    assert fact.content =~ ~s("invocation_id":"intake-tool")
    TestVoiceToolRoom.reply(next, :speaker, "Thank you for confirming Florida.")
    assert_receive {:test_tts_control, ^voice, speak}
    assert JSON.decode!(speak)["text"] == "Thank you for confirming Florida."
    TestVoiceToolRoom.settle(voice, sink, "thanks", "answer-turn")

    assert_receive {:vxpipe_event,
                    %Event.AgentTurnCompleted{
                      correlation_id: "answer-turn",
                      connection_id: ^connection_id
                    }}

    refute_receive {:test_blocking_tool_started, _}
    refute_receive {:test_agent_runtime_stream, _, _}
  end

  defp start_lookup(options \\ []) do
    {_, room, caller, voice, sink} =
      TestVoiceToolRoom.start_call(
        options ++
          [
            tools: %{"wait_for_test" => %{type: "host", tool: "wait_for_test"}},
            host_tools: %{"wait_for_test" => TestBlockingTool}
          ]
      )

    TestVoiceToolRoom.submit(room, caller, "Commercial landscaping", "service-turn")
    assert_receive {:test_agent_runtime_stream, provider, _}
    {:ok, call} = ToolCall.new(id: "intake-tool", name: "wait_for_test", arguments: %{})
    {:ok, response} = ModelResponse.new(text: "", tool_calls: [call])
    send(provider, {:test_agent_runtime_response, {:ok, response}})
    assert_receive {:test_blocking_tool_started, worker}
    {room, caller, voice, sink, worker}
  end
end
