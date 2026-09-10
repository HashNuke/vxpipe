defmodule Vxpipe.CallEngine.AgentTransferRoomTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{Message, ModelResponse, ToolCall}

  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    AgentActivationSupervisor,
    CallDefinition,
    CallInvocation,
    CallVariables,
    DefinitionCompiler,
    RoomAuthority,
    TestAgentRuntimeModelProvider
  }

  alias Vxpipe.CallEngine.Command.{AttachConnection, SendText}
  alias Vxpipe.CallEngine.Event.ToolCallCompleted
  alias Vxpipe.CallEngine.Tool.Context
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    agent_runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:implementation, :agent_runtime)
      |> Keyword.put(:model_provider, TestAgentRuntimeModelProvider)
      |> Keyword.put(:model_provider_options, owner: self())

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

  test "an allowlisted tool call commits control to the destination agent" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, "caller")
    reception = Map.fetch!(plan.participants, "reception")
    billing = Map.fetch!(plan.participants, "billing")

    assert {:ok, room} = CallEngine.start_call(plan)
    variables = CallVariables.whereis(room.incarnation_id)

    assert [{source_activation, _value}] =
             Registry.lookup(
               Vxpipe.CallEngine.RoomRegistry,
               {:agent_activation, reception.activation_id, :supervisor}
             )

    source_monitor = Process.monitor(source_activation)
    attach_caller(plan, room, caller)

    assert :ok = CallEngine.send_text(send_command(plan, room, caller, "Please transfer me."))

    assert_receive {:test_agent_runtime_stream, source_provider, source_request}

    assert [%Message{role: :system, content: "Route callers safely."} | _history] =
             source_request.messages

    assert Enum.map(source_request.tools, & &1.name) == ["transfer"]

    assert {:ok, transfer_call} =
             ToolCall.new(
               id: "transfer-to-billing",
               name: "transfer",
               arguments: %{"destination" => "billing"}
             )

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [transfer_call])
    send(source_provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:DOWN, ^source_monitor, :process, ^source_activation, _reason}, 2_000

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{
                      tool_call_id: "transfer-to-billing",
                      name: "transfer",
                      result: %{
                        "destination" => "billing",
                        "status" => "completed"
                      }
                    }},
                   2_000

    assert is_pid(AgentActivationSupervisor.whereis_child(billing.activation_id, :session))
    assert CallVariables.whereis(room.incarnation_id) == variables

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_not_found}} =
             CallEngine.participant_snapshot(
               plan.tenant_id,
               plan.room_id,
               reception.participant_id
             )

    assert {:ok, destination_snapshot} =
             CallEngine.participant_snapshot(plan.tenant_id, plan.room_id, billing.participant_id)

    assert destination_snapshot.participant_id == billing.participant_id

    assert :ok =
             CallEngine.send_text(send_command(plan, room, caller, "Can you help with billing?"))

    {destination_provider, _destination_request} =
      receive_request_for_prompt("Handle billing requests.")

    assert {:ok, destination_response} = ModelResponse.new(text: "I can help with billing.")
    send(destination_provider, {:test_agent_runtime_response, {:ok, destination_response}})
  end

  test "room authority rejects a stale source activation before destination startup" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, "caller")
    reception = Map.fetch!(plan.participants, "reception")
    billing = Map.fetch!(plan.participants, "billing")
    binding = Map.fetch!(reception.tools, "transfer").transfer

    assert {:ok, room} = CallEngine.start_call(plan)
    attach_caller(plan, room, caller)

    context = %Context{
      tenant_id: plan.tenant_id,
      room_id: plan.room_id,
      incarnation_id: room.incarnation_id,
      agent_participant_id: reception.participant_id,
      source_participant_id: caller.participant_id,
      connection_id: "connection-transfer",
      command_id: "command-stale-transfer",
      correlation_id: "turn-stale-transfer",
      agent_request_id: "request-stale-transfer",
      tool_call_id: "tool-stale-transfer",
      audio_response: false
    }

    assert {:ok, request} =
             Request.new(binding, %{"destination" => "billing"}, context)

    stale_request = %{request | source_activation_id: "act_stale"}

    assert {:error, :rejected} = RoomAuthority.transfer(stale_request)
    assert is_pid(AgentActivationSupervisor.whereis_child(reception.activation_id, :session))
    assert AgentActivationSupervisor.whereis_child(billing.activation_id, :session) == nil

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_not_found}} =
             CallEngine.participant_snapshot(plan.tenant_id, plan.room_id, billing.participant_id)
  end

  defp compile_plan do
    assert {:ok, definition} =
             CallDefinition.new(
               %{
                 schema_version: CallDefinition.schema_version(),
                 entry_caller: "caller",
                 entry_receiver: "reception",
                 defaults: %{capabilities: %{}},
                 call_variables: %{sections: %{}},
                 participants: %{
                   "caller" => %{
                     type: "human",
                     connection: %{
                       service: "web",
                       mode: "receive",
                       admission: "start_call"
                     }
                   },
                   "reception" => %{
                     type: "agent",
                     prompt: "Route callers safely.",
                     first_message: %{mode: "wait_for_input"},
                     capabilities: %{model_inference: "test-model"},
                     tools: %{},
                     transfers: ["billing"]
                   },
                   "billing" => %{
                     type: "agent",
                     description: "A billing specialist",
                     prompt: "Handle billing requests.",
                     first_message: %{mode: "wait_for_input"},
                     capabilities: %{model_inference: "test-model"},
                     tools: %{},
                     transfers: []
                   }
                 },
                 limits: %{max_duration_ms: 60_000}
               },
               resource_id: "transfer-definition",
               revision: 1
             )

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: "transfer-definition", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-transfer",
               actor_id: "actor-transfer",
               call_id: unique_id("call"),
               room_id: unique_id("room")
             )

    assert {:ok, plan} =
             DefinitionCompiler.compile(definition, invocation, %{
               capability_profiles: %{
                 "test-model" => %{
                   kind: :model_inference,
                   provider: :req_llm,
                   options: %{model: "test:scripted"}
                 }
               },
               host_tools: %{}
             })

    plan
  end

  defp attach_caller(plan, room, caller) do
    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: "connection-transfer",
               deadline: future_deadline()
             )

    assert {:ok, _attachment} = CallEngine.attach_connection(command)
  end

  defp send_command(plan, room, caller, content) do
    assert {:ok, command} =
             SendText.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: "connection-transfer",
               correlation_id: unique_id("turn"),
               content: content,
               deadline: future_deadline()
             )

    command
  end

  defp future_deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)

  defp receive_request_for_prompt(prompt) do
    receive do
      {:test_agent_runtime_stream, provider,
       %{messages: [%Message{role: :system, content: ^prompt} | _history]} = request} ->
        {provider, request}

      {:test_agent_runtime_stream, provider, _stale_source_request} ->
        assert {:ok, response} = ModelResponse.new(text: "Transfer in progress.")
        send(provider, {:test_agent_runtime_response, {:ok, response}})
        receive_request_for_prompt(prompt)
    after
      2_000 -> flunk("timed out waiting for agent prompt #{inspect(prompt)}")
    end
  end

  defp unique_id(prefix),
    do: "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
end
