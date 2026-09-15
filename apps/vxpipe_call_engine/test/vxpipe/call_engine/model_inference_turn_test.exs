defmodule Vxpipe.CallEngine.ModelInferenceTurnTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.{AttachConnection, SendText}

  alias Vxpipe.CallEngine.Event.{
    AgentTurnCompleted,
    AgentTurnFailed,
    AgentTurnInterrupted,
    ParticipantTurnCompleted,
    ParticipantTurnStarted,
    ToolCallStarted,
    TextOutput
  }

  alias Vxpipe.AgentRuntime.{Message, ModelRequest, ModelResponse, ToolCall}
  alias Vxpipe.CallEngine.{TestAgentRuntimeModelProvider, TestCallStartup, TestTurnCall}

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    agent_runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:fixture, {TestAgentRuntimeModelProvider, [owner: self()]})
      |> Keyword.put(:maximum_pending_requests, 2)
      |> Keyword.put(:request_timeout_ms, 1_000)

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(original, :agent_runtime, agent_runtime)
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    :ok
  end

  test "routes consecutive participant turns through one room-scoped model context" do
    room_id = unique_id("room")
    {room, participant} = start_attached_room(room_id)

    first = send_command(room, participant, "turn-one", "My name is River.")
    assert :ok = CallEngine.send_text(first)
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{sequence: 1}}
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{sequence: 2}}

    assert_receive {:test_agent_runtime_stream, first_request,
                    %ModelRequest{
                      messages: [
                        %Message{role: :system, content: "Answer as a compact test assistant."},
                        %Message{role: :user, content: "My name is River."}
                      ]
                    }}

    reply(first_request, "Nice to meet you, River.")

    assert_receive {:vxpipe_event, %TextOutput{sequence: 3, text: "Nice to meet you, River."}}
    assert_receive {:vxpipe_event, %AgentTurnCompleted{sequence: 4}}

    second = send_command(room, participant, "turn-two", "What is my name?")
    assert :ok = CallEngine.send_text(second)
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{sequence: 5}}
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{sequence: 6}}

    assert_receive {:test_agent_runtime_stream, second_request,
                    %ModelRequest{
                      messages: [
                        %Message{role: :system, content: "Answer as a compact test assistant."},
                        %Message{role: :user, content: "My name is River."},
                        %Message{role: :assistant, content: "Nice to meet you, River."},
                        %Message{role: :user, content: "What is my name?"}
                      ]
                    }}

    reply(second_request, "Your name is River.")

    assert_receive {:vxpipe_event, %TextOutput{sequence: 7, text: "Your name is River."}}
    assert_receive {:vxpipe_event, %AgentTurnCompleted{sequence: 8}}
  end

  test "keeps one text turn open across streamed sentence segments" do
    room_id = unique_id("room")
    {room, participant} = start_attached_room(room_id)
    command = send_command(room, participant, "turn-streamed", "Tell me two things.")

    assert :ok = CallEngine.send_text(command)
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{sequence: 1}}
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{sequence: 2}}
    assert_receive {:test_agent_runtime_stream, request, _messages}

    emit_chunk(request, "First thing. Sec")
    assert_receive {:vxpipe_event, %TextOutput{sequence: 3, text: "First thing."}}
    refute_receive {:vxpipe_event, %AgentTurnCompleted{}}

    emit_chunk(request, "ond thing!")
    reply(request, "First thing. Second thing!")

    assert_receive {:vxpipe_event, %TextOutput{sequence: 4, text: "Second thing!"}}
    assert_receive {:vxpipe_event, %AgentTurnCompleted{sequence: 5}}
  end

  test "reports a generation failure without ending the room or its model capability" do
    room_id = unique_id("room")
    {room, participant} = start_attached_room(room_id)
    failed = send_command(room, participant, "turn-failed", "Please fail once.")

    assert :ok = CallEngine.send_text(failed)
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{sequence: 1}}
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{sequence: 2}}
    assert_receive {:test_agent_runtime_stream, request, _messages}
    send(request, {:test_agent_runtime_response, {:error, :provider_unavailable}})

    assert_receive {:vxpipe_event,
                    %AgentTurnFailed{
                      sequence: 3,
                      correlation_id: "turn-failed",
                      reason: :provider_unavailable,
                      retryable: true
                    }}

    recovered = send_command(room, participant, "turn-recovered", "Please continue.")
    assert :ok = CallEngine.send_text(recovered)
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{sequence: 4}}
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{sequence: 5}}
    assert_receive {:test_agent_runtime_stream, recovered_request, _messages}
    reply(recovered_request, "Continuing.")

    assert_receive {:vxpipe_event, %TextOutput{sequence: 6, text: "Continuing."}}
    assert_receive {:vxpipe_event, %AgentTurnCompleted{sequence: 7}}
  end

  test "rejects an unsolicited tool call without projecting a public tool lifecycle" do
    room_id = unique_id("room")
    {room, participant} = start_attached_room(room_id)
    command = send_command(room, participant, "turn-tool", "What time is it?")
    call = %ToolCall{id: "tool-1", name: "get_current_time", arguments: %{}}

    assert :ok = CallEngine.send_text(command)
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{sequence: 1}}
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{sequence: 2}}
    assert_receive {:test_agent_runtime_stream, request, _messages}

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [call])
    send(request, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:vxpipe_event,
                    %AgentTurnFailed{
                      sequence: 3,
                      correlation_id: "turn-tool",
                      reason: :invalid_response
                    }}

    refute_receive {:vxpipe_event, %ToolCallStarted{}}
  end

  test "keeps non-immediate typed input queued behind the active model turn" do
    room_id = unique_id("room")
    {room, participant} = start_attached_room(room_id)
    current = send_command(room, participant, "turn-current", "first")

    assert :ok = CallEngine.send_text(current)
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{sequence: 1}}
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{sequence: 2}}
    assert_receive {:test_agent_runtime_stream, current_request, _messages}

    queued =
      send_command(room, participant, "turn-queued", "second", run_immediately: false)

    assert :ok = CallEngine.send_text(queued)
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{sequence: 3}}
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{sequence: 4}}
    refute_receive {:vxpipe_event, %AgentTurnInterrupted{}}
    refute_receive {:test_agent_runtime_stream, _request, _messages}

    reply(current_request, "first answer")
    assert_receive {:vxpipe_event, %TextOutput{sequence: 5, correlation_id: "turn-current"}}
    assert_receive {:vxpipe_event, %AgentTurnCompleted{sequence: 6}}

    assert_receive {:test_agent_runtime_stream, _queued_request,
                    %ModelRequest{
                      messages: [
                        %Message{role: :system},
                        %Message{role: :user, content: "first"},
                        %Message{role: :assistant, content: "first answer"},
                        %Message{role: :user, content: "second"}
                      ]
                    }}
  end

  defp start_attached_room(room_id) do
    {_plan, room, participant} = TestTurnCall.start(room_id)

    assert {:ok, attach} =
             AttachConnection.new(
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               room_id: room_id,
               incarnation_id: room.incarnation_id,
               participant_id: participant.participant_id,
               connection_id: "conn-model",
               deadline: future_deadline()
             )

    assert {:ok, attachment} = CallEngine.attach_connection(attach)
    TestCallStartup.await_ready(attachment)
    {room, participant}
  end

  defp send_command(room, participant, correlation_id, content, options \\ []) do
    assert {:ok, command} =
             SendText.new(
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               room_id: room.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: participant.participant_id,
               connection_id: "conn-model",
               correlation_id: correlation_id,
               content: content,
               run_immediately: Keyword.get(options, :run_immediately, true),
               audio_response: false,
               deadline: future_deadline()
             )

    command
  end

  defp reply(request, text) do
    assert {:ok, response} = ModelResponse.new(text: text)
    send(request, {:test_agent_runtime_response, {:ok, response}})
  end

  defp emit_chunk(request, chunk) do
    send(request, {:test_agent_runtime_delta, chunk, self()})
    assert_receive {:test_agent_runtime_delta_result, :ok}
  end

  defp future_deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
