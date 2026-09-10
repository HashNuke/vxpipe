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
    TestSelectiveAgentRuntimeModelProvider
  }

  alias Vxpipe.CallEngine.Command.{AttachConnection, SendText}

  alias Vxpipe.CallEngine.Event.{
    AgentTurnCompleted,
    TextOutput,
    ToolCallCompleted,
    ToolCallFailed
  }

  alias Vxpipe.CallEngine.Tool.Context
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    agent_runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:implementation, :agent_runtime)
      |> Keyword.put(:model_provider, TestSelectiveAgentRuntimeModelProvider)
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
    _ = RoomAuthority.snapshot(plan.tenant_id, plan.room_id)

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

    assert {:ok, room} = CallEngine.start_call(plan)
    attach_caller(plan, room, caller)

    request = transfer_request(plan, room, caller, reception, "tool-stale-transfer")

    stale_request = %{request | source_activation_id: "act_stale"}

    assert {:error, :rejected} = RoomAuthority.transfer(stale_request)
    assert is_pid(AgentActivationSupervisor.whereis_child(reception.activation_id, :session))
    assert AgentActivationSupervisor.whereis_child(billing.activation_id, :session) == nil

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_not_found}} =
             CallEngine.participant_snapshot(plan.tenant_id, plan.room_id, billing.participant_id)
  end

  test "failed destination preparation leaves the source responsible" do
    plan = compile_plan(billing_model: "test:unavailable")
    caller = Map.fetch!(plan.participants, "caller")
    reception = Map.fetch!(plan.participants, "reception")
    billing = Map.fetch!(plan.participants, "billing")

    assert {:ok, room} = CallEngine.start_call(plan)
    attach_caller(plan, room, caller)

    first = send_command(plan, room, caller, "Please try billing.")
    assert :ok = CallEngine.send_text(first)
    assert_receive {:test_agent_runtime_stream, source_provider, _source_request}

    assert {:ok, transfer_call} =
             ToolCall.new(
               id: "failed-transfer-to-billing",
               name: "transfer",
               arguments: %{"destination" => "billing"}
             )

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [transfer_call])
    send(source_provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:vxpipe_event,
                    %ToolCallFailed{
                      tool_call_id: "failed-transfer-to-billing",
                      name: "transfer",
                      reason: :tool_failed
                    }},
                   2_000

    reply_to_next_request("The transfer could not be completed.")
    reply_to_next_request("I am still available to help.")

    assert_receive {:vxpipe_event, %TextOutput{text: "I am still available to help."}}, 2_000
    assert_receive {:vxpipe_event, %AgentTurnCompleted{}}, 2_000

    assert is_pid(AgentActivationSupervisor.whereis_child(reception.activation_id, :session))
    assert AgentActivationSupervisor.whereis_child(billing.activation_id, :session) == nil

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_not_found}} =
             CallEngine.participant_snapshot(plan.tenant_id, plan.room_id, billing.participant_id)

    next = send_command(plan, room, caller, "Are you still there?")
    assert :ok = CallEngine.send_text(next)

    assert_receive {:test_agent_runtime_stream, next_provider, next_request}, 2_000

    assert [%Message{role: :system, content: "Route callers safely."} | _history] =
             next_request.messages

    assert Enum.any?(next_request.messages, fn message ->
             message.role == :user and message.content == "Are you still there?"
           end)

    assert {:ok, next_response} = ModelResponse.new(text: "Yes.")
    send(next_provider, {:test_agent_runtime_response, {:ok, next_response}})
  end

  test "a total attempt deadline rejects blocked preparation and preserves the source" do
    plan =
      compile_plan(
        billing_model: "test:blocked",
        transfer_timeout_ms: 2_000
      )

    caller = Map.fetch!(plan.participants, "caller")
    reception = Map.fetch!(plan.participants, "reception")
    billing = Map.fetch!(plan.participants, "billing")

    assert {:ok, room} = CallEngine.start_call(plan)
    attach_caller(plan, room, caller)

    initial = send_command(plan, room, caller, "Please try billing.")
    assert :ok = CallEngine.send_text(initial)

    assert_receive {:test_agent_runtime_stream, source_provider, _source_request}

    assert {:ok, transfer_call} =
             ToolCall.new(
               id: "timed-transfer-to-billing",
               name: "transfer",
               arguments: %{"destination" => "billing"}
             )

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [transfer_call])
    send(source_provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:test_agent_runtime_model_preparing, blocked_preparer}, 2_000

    on_exit(fn ->
      send(blocked_preparer, :release_test_agent_runtime_model)
    end)

    duplicate = transfer_request(plan, room, caller, reception, "duplicate-transfer")
    assert {:error, :rejected} = RoomAuthority.transfer(duplicate)

    reply_to_next_request("I am trying that transfer now.")

    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: initial_correlation}},
                   2_000

    assert initial_correlation == initial.correlation_id

    held = send_command(plan, room, caller, "Can you answer something else?")
    assert :ok = CallEngine.send_text(held)

    assert_receive {:vxpipe_event,
                    %TextOutput{
                      correlation_id: held_correlation,
                      text: "Please hold while I finish the current request."
                    }},
                   2_000

    assert held_correlation == held.correlation_id

    assert_receive {:vxpipe_event,
                    %ToolCallFailed{
                      tool_call_id: "timed-transfer-to-billing",
                      name: "transfer",
                      reason: :tool_failed
                    }},
                   3_000

    reply_to_next_request("The transfer could not be completed.")

    assert is_pid(AgentActivationSupervisor.whereis_child(reception.activation_id, :session))
    assert AgentActivationSupervisor.whereis_child(billing.activation_id, :session) == nil

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_not_found}} =
             CallEngine.participant_snapshot(plan.tenant_id, plan.room_id, billing.participant_id)

    send(blocked_preparer, :release_test_agent_runtime_model)

    refute_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "timed-transfer-to-billing"}},
                   100

    assert :ok = CallEngine.send_text(send_command(plan, room, caller, "Are you still there?"))

    assert_receive {:test_agent_runtime_stream, next_provider, next_request}, 2_000

    assert [%Message{role: :system, content: "Route callers safely."} | _history] =
             next_request.messages

    assert {:ok, next_response} = ModelResponse.new(text: "Yes.")
    send(next_provider, {:test_agent_runtime_response, {:ok, next_response}})
  end

  defp compile_plan(options \\ []) do
    billing_model = Keyword.get(options, :billing_model, "test:scripted")
    transfer_timeout_ms = Keyword.get(options, :transfer_timeout_ms, 30_000)

    assert {:ok, definition} =
             CallDefinition.new(
               %{
                 schema_version: CallDefinition.schema_version(),
                 entry_caller: "caller",
                 entry_receiver: "reception",
                 defaults: %{capabilities: %{}},
                 call_variables: %{sections: %{}},
                 transfer_policy: %{attempt_timeout_ms: transfer_timeout_ms},
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
                     capabilities: %{model_inference: "billing-model"},
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
                 },
                 "billing-model" => %{
                   kind: :model_inference,
                   provider: :req_llm,
                   options: %{model: billing_model}
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

  defp transfer_request(plan, room, caller, source, tool_call_id) do
    context = %Context{
      tenant_id: plan.tenant_id,
      room_id: plan.room_id,
      incarnation_id: room.incarnation_id,
      agent_participant_id: source.participant_id,
      source_participant_id: caller.participant_id,
      connection_id: "connection-transfer",
      command_id: "command-#{tool_call_id}",
      correlation_id: "turn-#{tool_call_id}",
      agent_request_id: "request-#{tool_call_id}",
      tool_call_id: tool_call_id,
      audio_response: false
    }

    binding = Map.fetch!(source.tools, "transfer").transfer

    assert {:ok, request} =
             Request.new(binding, %{"destination" => "billing"}, context)

    request
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

  defp reply_to_next_request(text) do
    assert_receive {:test_agent_runtime_stream, provider, _request}, 2_000
    assert {:ok, response} = ModelResponse.new(text: text)
    send(provider, {:test_agent_runtime_response, {:ok, response}})
  end

  defp unique_id(prefix),
    do: "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
end
