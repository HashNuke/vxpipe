defmodule Vxpipe.CallEngine.ModelInferenceTurnTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.{AttachConnection, CreateRoom, JoinParticipant, SendText}

  alias Vxpipe.CallEngine.Event.{
    AgentTurnCompleted,
    AgentTurnFailed,
    AgentTurnInterrupted,
    ParticipantTurnCompleted,
    ParticipantTurnStarted,
    ToolCallCompleted,
    ToolCallCancelled,
    ToolCallStarted,
    TextOutput
  }

  alias Vxpipe.CallEngine.Provider.ModelInference.Message
  alias Vxpipe.CallEngine.TestModelInferenceProvider
  alias Vxpipe.CallEngine.TestBlockingTool
  alias Vxpipe.CallEngine.Tool.Call
  alias Vxpipe.CallEngine.Tool.CurrentTime

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    model_inference = [
      enabled: true,
      provider: TestModelInferenceProvider,
      provider_options: [observer: self()],
      system_prompt: "Answer as a compact test assistant.",
      maximum_context_turns: 4,
      maximum_pending_requests: 2,
      maximum_output_bytes: 65_536,
      request_timeout_ms: 1_000
    ]

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(original, :model_inference, model_inference)
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

    assert_receive {:test_model_inference_request, first_request,
                    [
                      %Message{role: :system, content: "Answer as a compact test assistant."},
                      %Message{role: :user, content: "My name is River."}
                    ]}

    send(first_request, {:test_model_inference_reply, {:ok, "Nice to meet you, River."}})

    assert_receive {:vxpipe_event, %TextOutput{sequence: 3, text: "Nice to meet you, River."}}
    assert_receive {:vxpipe_event, %AgentTurnCompleted{sequence: 4}}

    second = send_command(room, participant, "turn-two", "What is my name?")
    assert :ok = CallEngine.send_text(second)
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{sequence: 5}}
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{sequence: 6}}

    assert_receive {:test_model_inference_request, second_request,
                    [
                      %Message{role: :system, content: "Answer as a compact test assistant."},
                      %Message{role: :user, content: "My name is River."},
                      %Message{role: :assistant, content: "Nice to meet you, River."},
                      %Message{role: :user, content: "What is my name?"}
                    ]}

    send(second_request, {:test_model_inference_reply, {:ok, "Your name is River."}})

    assert_receive {:vxpipe_event, %TextOutput{sequence: 7, text: "Your name is River."}}
    assert_receive {:vxpipe_event, %AgentTurnCompleted{sequence: 8}}
  end

  test "keeps one text turn open across streamed sentence segments" do
    enable_streaming_provider()
    room_id = unique_id("room")
    {room, participant} = start_attached_room(room_id)
    command = send_command(room, participant, "turn-streamed", "Tell me two things.")

    assert :ok = CallEngine.send_text(command)
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{sequence: 1}}
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{sequence: 2}}
    assert_receive {:test_stream_model_inference_request, request, _messages}

    emit_chunk(request, "First thing. Sec")
    assert_receive {:vxpipe_event, %TextOutput{sequence: 3, text: "First thing."}}
    refute_receive {:vxpipe_event, %AgentTurnCompleted{}}

    emit_chunk(request, "ond thing!")
    send(request, {:test_model_inference_reply, :ok})

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
    assert_receive {:test_model_inference_request, request, _messages}
    send(request, {:test_model_inference_reply, {:error, :upstream_unavailable}})

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
    assert_receive {:test_model_inference_request, recovered_request, _messages}
    send(recovered_request, {:test_model_inference_reply, {:ok, "Continuing."}})

    assert_receive {:vxpipe_event, %TextOutput{sequence: 6, text: "Continuing."}}
    assert_receive {:vxpipe_event, %AgentTurnCompleted{sequence: 7}}
  end

  test "projects a tool lifecycle and model continuation in the originating turn" do
    enable_tools()
    room_id = unique_id("room")
    {room, participant} = start_attached_room(room_id)
    command = send_command(room, participant, "turn-tool", "What time is it?")
    call = %Call{id: "tool-1", name: "get_current_time", arguments: %{}}

    assert :ok = CallEngine.send_text(command)
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{sequence: 1}}
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{sequence: 2}}
    assert_receive {:test_model_inference_request, request, _messages, [definition]}
    assert definition.name == "get_current_time"

    send(request, {:test_model_inference_reply, {:tool_calls, [call]}})

    assert_receive {:vxpipe_event,
                    %ToolCallStarted{
                      sequence: 3,
                      correlation_id: "turn-tool",
                      tool_call_id: "tool-1",
                      name: "get_current_time",
                      arguments: %{}
                    }}

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{
                      sequence: 4,
                      tool_call_id: "tool-1",
                      result: %{"timezone" => "UTC"}
                    }}

    assert_receive {:test_model_inference_request, continuation, messages, [_definition]}
    assert Enum.at(messages, -1).role == :tool
    send(continuation, {:test_model_inference_reply, {:ok, "It is currently noon UTC."}})

    assert_receive {:vxpipe_event, %TextOutput{sequence: 5, text: "It is currently noon UTC."}}
    assert_receive {:vxpipe_event, %AgentTurnCompleted{sequence: 6}}
  end

  test "keeps non-immediate typed input queued behind the active model turn" do
    room_id = unique_id("room")
    {room, participant} = start_attached_room(room_id)
    current = send_command(room, participant, "turn-current", "first")

    assert :ok = CallEngine.send_text(current)
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{sequence: 1}}
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{sequence: 2}}
    assert_receive {:test_model_inference_request, current_request, _messages}

    queued =
      send_command(room, participant, "turn-queued", "second", run_immediately: false)

    assert :ok = CallEngine.send_text(queued)
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{sequence: 3}}
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{sequence: 4}}
    refute_receive {:vxpipe_event, %AgentTurnInterrupted{}}
    refute_receive {:test_model_inference_request, _request, _messages}

    send(current_request, {:test_model_inference_reply, {:ok, "first answer"}})
    assert_receive {:vxpipe_event, %TextOutput{sequence: 5, correlation_id: "turn-current"}}
    assert_receive {:vxpipe_event, %AgentTurnCompleted{sequence: 6}}

    assert_receive {:test_model_inference_request, _queued_request,
                    [
                      %Message{role: :system},
                      %Message{role: :user, content: "first"},
                      %Message{role: :assistant, content: "first answer"},
                      %Message{role: :user, content: "second"}
                    ]}
  end

  test "interrupts an executing tool and settles its public lifecycle" do
    Application.put_env(:vxpipe_call_engine, :blocking_tool_observer, self())
    on_exit(fn -> Application.delete_env(:vxpipe_call_engine, :blocking_tool_observer) end)
    enable_tools([TestBlockingTool])

    room_id = unique_id("room")
    {room, participant} = start_attached_room(room_id)
    current = send_command(room, participant, "turn-tool", "Wait for me.")
    call = %Call{id: "tool-wait", name: "wait_for_test", arguments: %{}}

    assert :ok = CallEngine.send_text(current)
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{sequence: 1}}
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{sequence: 2}}
    assert_receive {:test_model_inference_request, provider, _messages, [_definition]}
    send(provider, {:test_model_inference_reply, {:tool_calls, [call]}})
    assert_receive {:vxpipe_event, %ToolCallStarted{sequence: 3, tool_call_id: "tool-wait"}}
    assert_receive {:test_blocking_tool_started, tool_task}
    monitor = Process.monitor(tool_task)

    replacement = send_command(room, participant, "turn-replacement", "Continue.")
    assert :ok = CallEngine.send_text(replacement)
    assert_receive {:DOWN, ^monitor, :process, ^tool_task, _reason}
    assert_receive {:vxpipe_event, %ToolCallCancelled{sequence: 4, tool_call_id: "tool-wait"}}

    assert_receive {:vxpipe_event,
                    %AgentTurnInterrupted{sequence: 5, correlation_id: "turn-tool"}}

    assert_receive {:vxpipe_event, %ParticipantTurnStarted{sequence: 6}}
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{sequence: 7}}
    assert_receive {:test_model_inference_request, next_provider, _messages, [_definition]}
    send(next_provider, {:test_model_inference_reply, {:ok, "Continuing."}})
    assert_receive {:vxpipe_event, %TextOutput{sequence: 8, text: "Continuing."}}
    assert_receive {:vxpipe_event, %AgentTurnCompleted{sequence: 9}}
  end

  defp start_attached_room(room_id) do
    assert {:ok, create} =
             CreateRoom.new(
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               room_id: room_id,
               agent: :model_inference,
               deadline: future_deadline()
             )

    assert {:ok, room} = CallEngine.create_room(create)

    assert {:ok, join} =
             JoinParticipant.new(
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               room_id: room_id,
               role: :human,
               deadline: future_deadline()
             )

    assert {:ok, participant} = CallEngine.join_participant(join)

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

    assert {:ok, _attachment} = CallEngine.attach_connection(attach)
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

  defp enable_streaming_provider do
    settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    model_inference =
      settings
      |> Keyword.fetch!(:model_inference)
      |> Keyword.update!(:provider_options, &Keyword.put(&1, :streaming, true))

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(settings, :model_inference, model_inference)
    )
  end

  defp enable_tools(tools \\ [CurrentTime]) do
    settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    model_inference =
      settings
      |> Keyword.fetch!(:model_inference)
      |> Keyword.put(:tools, tools)
      |> Keyword.put(:maximum_tool_result_bytes, 4_096)
      |> Keyword.put(:maximum_tool_rounds, 2)

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(settings, :model_inference, model_inference)
    )
  end

  defp emit_chunk(request, chunk) do
    send(request, {:test_model_inference_chunk, chunk, self()})
    assert_receive {:test_model_inference_chunk_result, :ok}
  end

  defp future_deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
