defmodule Vxpipe.CallEngine.TerminalAdmissionTest do
  use ExUnit.Case, async: false

  import Vxpipe.CallEngine.TestVoiceToolRoom

  alias Vxpipe.AgentRuntime.{Executor, ModelResponse, ToolCall}
  alias Vxpipe.CallEngine.AgentActivationSupervisor
  alias Vxpipe.CallEngine.AgentRuntime.{Correlation, InvocationExecutor}
  alias Vxpipe.CallEngine.Event.AgentTurnCompleted
  alias Vxpipe.CallEngine.RoomAuthority
  alias Vxpipe.CallEngine.RoomAuthority.EndCall
  alias Vxpipe.CallEngine.Tool.{Context, Hangup, InvocationBinding}
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Binding, as: TransferBinding
  alias Vxpipe.CallEngine.{Error}

  @question "Where do you need the landscaping?"

  setup do
    configure()
  end

  test "engine terminal preflight is rejected while the answer is outstanding" do
    {plan, room, caller, voice, sink} = start_hangup_call()
    receiver = Map.fetch!(plan.participants, "receiver")

    registry =
      AgentActivationSupervisor.whereis_child(receiver.activation_id, :invocation_registry)

    assert is_pid(registry)

    submit(room, caller, "I need help.", "t1")
    assert_receive {:test_agent_runtime_stream, model, _}
    reply(model, :speaker, @question)
    assert_receive {:test_tts_control, ^voice, speak}
    assert JSON.decode!(speak)["text"] == @question
    settle(voice, sink, "q1", "t1")
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: "t1"}}

    context = engine_context(room, caller, receiver, "cmd-engine-1", "turn-engine-1")

    correlation = %Correlation{
      command_id: context.command_id,
      correlation_id: context.correlation_id,
      invocation_registry: registry,
      tool_context: context
    }

    assert {:error, :caller_answer_pending} =
             RoomAuthority.terminal_submission_admission(context)

    hangup = %InvocationBinding{
      name: "end_call",
      conversation_mode: :blocking,
      handler: {:platform, Hangup}
    }

    assert {:error, :caller_answer_pending} =
             InvocationExecutor.preflight(hangup, %{}, correlation, "hangup-engine-1")

    assert {:error, :caller_answer_pending} =
             InvocationExecutor.preflight(
               hangup,
               %{"announcement" => "Goodbye."},
               correlation,
               "hangup-engine-2"
             )

    aliased = %InvocationBinding{
      name: "goodbye_alias",
      conversation_mode: :blocking,
      handler: {:platform, Hangup}
    }

    assert {:error, :caller_answer_pending} =
             InvocationExecutor.preflight(
               aliased,
               %{"announcement" => "Goodbye."},
               correlation,
               "hangup-alias-1"
             )

    transfer = %InvocationBinding{
      name: "transfer",
      conversation_mode: :blocking,
      handler: {:participant_transfer, struct(TransferBinding, transfer_binding_fields())}
    }

    assert {:error, :caller_answer_pending} =
             InvocationExecutor.preflight(
               transfer,
               %{"destination" => "billing"},
               correlation,
               "xfer-1"
             )

    # Submission itself never queries the room: it must not return the floor
    # reason even while the answer is outstanding. Effect-time revalidation
    # still guards the terminal effect.
    refute match?(
             {:error, :caller_answer_pending},
             InvocationExecutor.submit(hangup, %{}, correlation, "hangup-submit-probe")
           )

    assert %_{} = RoomAuthority.snapshot(room.tenant_id, room.room_id)
    refute_received {:test_tts_control, ^voice, _}
  end

  test "engine greeting and idle origins do not bypass the floor" do
    {plan, room, caller, voice, sink} = start_hangup_call()
    receiver = Map.fetch!(plan.participants, "receiver")

    registry =
      AgentActivationSupervisor.whereis_child(receiver.activation_id, :invocation_registry)

    submit(room, caller, "I need help.", "t1")
    assert_receive {:test_agent_runtime_stream, model, _}
    reply(model, :speaker, @question)
    assert_receive {:test_tts_control, ^voice, speak}
    assert JSON.decode!(speak)["text"] == @question
    settle(voice, sink, "q1", "t1")
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: "t1"}}

    hangup = %InvocationBinding{
      name: "end_call",
      conversation_mode: :blocking,
      handler: {:platform, Hangup}
    }

    for {command_id, correlation_id} <- [{"cmd-greet", "turn-greet"}, {"cmd-idle", "turn-idle"}] do
      context = engine_context(room, caller, receiver, command_id, correlation_id)

      correlation = %Correlation{
        command_id: context.command_id,
        correlation_id: context.correlation_id,
        invocation_registry: registry,
        tool_context: context
      }

      assert {:error, :caller_answer_pending} =
               InvocationExecutor.preflight(hangup, %{}, correlation, "pre-#{command_id}")
    end
  end

  test "native STS origin stays isolated from the ReqLLM floor" do
    {plan, room, caller, voice, sink} = start_hangup_call()
    receiver = Map.fetch!(plan.participants, "receiver")

    registry =
      AgentActivationSupervisor.whereis_child(receiver.activation_id, :invocation_registry)

    submit(room, caller, "I need help.", "t1")
    assert_receive {:test_agent_runtime_stream, model, _}
    reply(model, :speaker, @question)
    assert_receive {:test_tts_control, ^voice, speak}
    assert JSON.decode!(speak)["text"] == @question
    settle(voice, sink, "q1", "t1")
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: "t1"}}

    sts_context = %{
      engine_context(room, caller, receiver, "cmd-sts", "turn-sts")
      | request_origin: :sts
    }

    assert :ok = RoomAuthority.terminal_submission_admission(sts_context)

    correlation = %Correlation{
      command_id: sts_context.command_id,
      correlation_id: sts_context.correlation_id,
      invocation_registry: registry,
      tool_context: sts_context
    }

    hangup = %InvocationBinding{
      name: "end_call",
      conversation_mode: :blocking,
      handler: {:platform, Hangup}
    }

    assert :ok = InvocationExecutor.preflight(hangup, %{}, correlation, "sts-pre-1")
  end

  test "preflight before submission is bounded when the room is gone" do
    {plan, room, caller, _voice, _sink} = start_hangup_call()
    receiver = Map.fetch!(plan.participants, "receiver")

    registry =
      AgentActivationSupervisor.whereis_child(receiver.activation_id, :invocation_registry)

    gone_context = %{
      engine_context(room, caller, receiver, "cmd-gone", "turn-gone")
      | tenant_id: "gone-tenant",
        room_id: "gone-room"
    }

    gone_correlation = %Correlation{
      command_id: gone_context.command_id,
      correlation_id: gone_context.correlation_id,
      invocation_registry: registry,
      tool_context: gone_context
    }

    hangup = %InvocationBinding{
      name: "end_call",
      conversation_mode: :blocking,
      handler: {:platform, Hangup}
    }

    assert {:error, :unavailable} =
             InvocationExecutor.preflight(hangup, %{}, gone_correlation, "gone-pre-1")
  end

  test "the room revalidates terminal effects while the answer is outstanding" do
    {plan, room, caller, voice, sink} = start_hangup_call()
    receiver = Map.fetch!(plan.participants, "receiver")

    submit(room, caller, "I need help.", "t1")
    assert_receive {:test_agent_runtime_stream, model, _}
    reply(model, :speaker, @question)
    assert_receive {:test_tts_control, ^voice, speak}
    assert JSON.decode!(speak)["text"] == @question
    settle(voice, sink, "q1", "t1")
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: "t1"}}

    authority = room_authority(room)
    state = :sys.get_state(authority)
    refute is_nil(state.text_capability)
    capability = GenServer.whereis(state.text_capability.pid)
    assert is_pid(capability)
    context = engine_context(room, caller, receiver, "cmd-engine-1", "turn-engine-1")

    assert {:error, %Error{code: :caller_answer_pending}} =
             EndCall.authorize(capability, context, state)

    answer = submit(room, caller, "Florida.", "t2")
    assert_receive {:test_agent_runtime_stream, _answer_model, _}
    state = :sys.get_state(authority)
    caller_context = answered_context(room, caller, receiver, answer)

    assert :ok =
             EndCall.authorize(
               GenServer.whereis(state.text_capability.pid),
               caller_context,
               state
             )
  end

  test "a caller-authorized goodbye still ends the call" do
    {_plan, room, caller, voice, sink} = start_hangup_call()

    submit(room, caller, "I need help.", "t1")
    assert_receive {:test_agent_runtime_stream, model, _}
    reply(model, :speaker, @question)
    assert_receive {:test_tts_control, ^voice, speak}
    assert JSON.decode!(speak)["text"] == @question
    settle(voice, sink, "q1", "t1")
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: "t1"}}

    submit(room, caller, "Florida.", "t2")
    assert_receive {:test_agent_runtime_stream, answer_model, _}
    reply(answer_model, :speaker, "Thanks.")
    assert_receive {:test_tts_control, ^voice, _thanks}

    authority = room_authority(room)
    monitor = Process.monitor(authority)

    submit(room, caller, "Goodbye.", "t3")
    assert_receive {:test_agent_runtime_stream, goodbye_model, _}
    assert {:ok, call} = ToolCall.new(id: "hangup-caller-1", name: "end_call", arguments: %{})
    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [call])
    send(goodbye_model, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:DOWN, ^monitor, :process, ^authority, _reason}, 5_000
  end

  test "the executor preserves the caller_answer_pending reason" do
    assert {:error, :caller_answer_pending} =
             Executor.submit(__MODULE__.StubCallerPendingExecutor, %{}, %{}, %{}, "call-1")
  end

  defp start_hangup_call do
    start_call(tools: %{"end_call" => %{type: "platform", tool: "hangup"}})
  end

  defp engine_context(room, caller, receiver, command_id, correlation_id) do
    %Context{
      tenant_id: room.tenant_id,
      room_id: room.room_id,
      incarnation_id: room.incarnation_id,
      agent_participant_id: receiver.participant_id,
      source_participant_id: caller.participant_id,
      connection_id: "idle-human",
      command_id: command_id,
      correlation_id: correlation_id,
      request_origin: :engine
    }
  end

  defp answered_context(room, caller, receiver, answer) do
    %Context{
      tenant_id: room.tenant_id,
      room_id: room.room_id,
      incarnation_id: room.incarnation_id,
      agent_participant_id: receiver.participant_id,
      source_participant_id: caller.participant_id,
      connection_id: "idle-human",
      command_id: answer.id,
      correlation_id: answer.correlation_id,
      request_origin: :caller
    }
  end

  defp room_authority(room) do
    [{authority, _}] =
      Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {room.tenant_id, room.room_id})

    authority
  end

  defp transfer_binding_fields do
    [
      source_call_spec_key: "reception",
      source_participant_id: "agent-reception",
      source_activation_id: "act_reception",
      targets: %{}
    ]
  end
end

defmodule Vxpipe.CallEngine.TerminalAdmissionTest.StubCallerPendingExecutor do
  @moduledoc false

  @behaviour Vxpipe.AgentRuntime.Executor

  @impl true
  def submit(_binding, _arguments, _context, _invocation_id),
    do: {:error, :caller_answer_pending}
end
