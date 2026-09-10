defmodule Vxpipe.CallEngine.AgentRuntime.ToolConversationRoomTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{Message, ModelResponse, PendingInvocation, ToolCall}
  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    CallDefinition,
    CallInvocation,
    DefinitionCompiler,
    TestAgentRuntimeModelProvider,
    TestBlockingTool
  }

  alias Vxpipe.CallEngine.Command.{AttachConnection, SendText}

  alias Vxpipe.CallEngine.Event.{
    AgentTurnCompleted,
    TextOutput,
    ToolCallCompleted,
    ToolCallStarted
  }

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

    Application.put_env(:vxpipe_call_engine, :blocking_tool_observer, self())

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
      Application.delete_env(:vxpipe_call_engine, :blocking_tool_observer)
    end)

    :ok
  end

  test "defaults a room tool to blocking while its supervised invocation remains pending" do
    plan = compile_plan()
    {room, caller} = start_room(plan, "conn-agent-runtime-blocking")

    initial =
      send_text(
        plan,
        room,
        caller,
        "conn-agent-runtime-blocking",
        "Check the balance."
      )

    assert_receive {:test_agent_runtime_stream, provider, request}
    assert Enum.map(request.tools, & &1.name) == ["wait_for_test"]
    reply_with_tool(provider, "blocking-tool-call")

    assert_receive {:test_blocking_tool_started, invocation}
    refute invocation == provider
    assert_receive {:vxpipe_event, %ToolCallStarted{tool_call_id: "blocking-tool-call"}}
    assert_receive {:test_agent_runtime_stream, acknowledgement_provider, acknowledgement_request}
    assert acknowledgement_request.tools == []
    assert_running_invocation(acknowledgement_request, "blocking-tool-call", :blocking)
    reply_with_text(acknowledgement_provider, "I am checking now.")
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: initial_correlation}}
    assert initial_correlation == initial.correlation_id

    held =
      send_text(
        plan,
        room,
        caller,
        "conn-agent-runtime-blocking",
        "What are the usage rules?"
      )

    assert_receive {:vxpipe_event,
                    %TextOutput{
                      correlation_id: held_correlation,
                      text: "Please hold while I finish the current request."
                    }}

    assert held_correlation == held.correlation_id
    refute_receive {:test_agent_runtime_stream, _provider, _request}

    send(invocation, :release_test_tool)

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{
                      tool_call_id: "blocking-tool-call",
                      result: %{"released" => true}
                    }}

    assert_receive {:test_agent_runtime_stream, completion_provider, completion_request}
    assert List.last(completion_request.messages).origin == :engine
    completion_correlation = completion_request.correlation.correlation_id
    reply_with_text(completion_provider, "The balance check completed.")

    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: ^completion_correlation}}

    resumed =
      send_text(
        plan,
        room,
        caller,
        "conn-agent-runtime-blocking",
        "Can we continue?"
      )

    assert_receive {:test_agent_runtime_stream, resumed_provider, resumed_request}
    assert List.last(resumed_request.messages).content == resumed.content
    reply_with_text(resumed_provider, "Yes.")
  end

  test "admits later room turns only for a tool explicitly marked non-blocking" do
    plan = compile_plan("non_blocking")
    {room, caller} = start_room(plan, "conn-agent-runtime-non-blocking")

    initial =
      send_text(
        plan,
        room,
        caller,
        "conn-agent-runtime-non-blocking",
        "Start the balance check."
      )

    assert_receive {:test_agent_runtime_stream, provider, _request}
    reply_with_tool(provider, "non-blocking-tool-call")

    assert_receive {:test_blocking_tool_started, invocation}
    refute invocation == provider
    assert_receive {:vxpipe_event, %ToolCallStarted{tool_call_id: "non-blocking-tool-call"}}
    assert_receive {:test_agent_runtime_stream, acknowledgement_provider, acknowledgement_request}
    assert Enum.map(acknowledgement_request.tools, & &1.name) == ["wait_for_test"]
    assert_running_invocation(acknowledgement_request, "non-blocking-tool-call", :non_blocking)
    reply_with_text(acknowledgement_provider, "I am checking now.")
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: initial_correlation}}
    assert initial_correlation == initial.correlation_id

    unrelated =
      send_text(
        plan,
        room,
        caller,
        "conn-agent-runtime-non-blocking",
        "What are the usage rules?"
      )

    assert_receive {:test_agent_runtime_stream, unrelated_provider, unrelated_request}
    assert List.last(unrelated_request.messages).content == unrelated.content
    assert_running_invocation(unrelated_request, "non-blocking-tool-call", :non_blocking)
    reply_with_text(unrelated_provider, "The usual rules apply.")

    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: unrelated_correlation}}

    assert unrelated_correlation == unrelated.correlation_id

    send(invocation, :release_test_tool)

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{
                      tool_call_id: "non-blocking-tool-call",
                      result: %{"released" => true}
                    }}

    assert_receive {:test_agent_runtime_stream, completion_provider, completion_request}
    assert List.last(completion_request.messages).origin == :engine
    completion_correlation = completion_request.correlation.correlation_id
    reply_with_text(completion_provider, "The balance check completed.")

    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: ^completion_correlation}}
  end

  test "delivers mixed tool text once and consumes its private completion once" do
    plan = compile_plan("non_blocking")
    connection_id = "conn-agent-runtime-mixed-tool"
    {room, caller} = start_room(plan, connection_id)

    initial = send_text(plan, room, caller, connection_id, "Start the check.")

    assert_receive {:test_agent_runtime_stream, provider, _request}
    send(provider, {:test_agent_runtime_delta, "I will check now. "})

    assert_receive {:vxpipe_event,
                    %TextOutput{
                      correlation_id: initial_correlation,
                      text: "I will check now."
                    }}

    assert initial_correlation == initial.correlation_id
    reply_with_tool(provider, "mixed-tool-call", "I will check now. ")

    assert_receive {:test_blocking_tool_started, invocation}
    assert_receive {:vxpipe_event, %ToolCallStarted{tool_call_id: "mixed-tool-call"}}

    assert_receive {:test_agent_runtime_stream, acknowledgement_provider, acknowledgement_request}
    assert_running_invocation(acknowledgement_request, "mixed-tool-call", :non_blocking)
    reply_with_text(acknowledgement_provider, "The check is running.")

    assert_receive {:vxpipe_event,
                    %TextOutput{
                      correlation_id: ^initial_correlation,
                      text: "The check is running."
                    }}

    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: ^initial_correlation}}

    refute_receive {:vxpipe_event,
                    %TextOutput{
                      correlation_id: ^initial_correlation,
                      text: "I will check now."
                    }}

    send(invocation, :release_test_tool)

    assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "mixed-tool-call"}}
    assert_receive {:test_agent_runtime_stream, completion_provider, completion_request}
    completion_correlation = completion_request.correlation.correlation_id

    send(completion_provider, {:test_agent_runtime_delta, "The check completed. "})

    assert_receive {:vxpipe_event,
                    %TextOutput{
                      correlation_id: ^completion_correlation,
                      text: "The check completed."
                    }}

    reply_with_text(completion_provider, "The check completed. ")
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: ^completion_correlation}}

    refute_receive {:vxpipe_event,
                    %TextOutput{
                      correlation_id: ^completion_correlation,
                      text: "The check completed."
                    }}
  end

  defp compile_plan(conversation_mode \\ nil) do
    tool = %{type: "host", tool: "wait_for_test"}

    tool =
      if conversation_mode, do: Map.put(tool, :conversation_mode, conversation_mode), else: tool

    input = %{
      schema_version: "20260910.02",
      entry_caller: "caller",
      entry_receiver: "receiver",
      defaults: %{capabilities: %{}},
      call_variables: %{sections: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"},
          capabilities: %{}
        },
        "receiver" => %{
          type: "agent",
          prompt: "Use the available tool.",
          first_message: %{mode: "wait_for_input"},
          capabilities: %{model_inference: "test-model"},
          tools: %{"wait_for_test" => tool},
          transfers: []
        }
      },
      limits: %{max_duration_ms: 60_000}
    }

    assert {:ok, definition} =
             CallDefinition.new(input, resource_id: "tool-mode-definition", revision: 1)

    room_id = unique_id("room-agent-runtime-tool-mode")

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: "tool-mode-definition", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-test",
               actor_id: "actor-test",
               call_id: unique_id("call"),
               room_id: room_id
             )

    registries = %{
      capability_profiles: %{
        "test-model" => %{
          kind: :model_inference,
          provider: :req_llm,
          options: %{model: "test:scripted"}
        }
      },
      host_tools: %{"wait_for_test" => TestBlockingTool}
    }

    assert {:ok, plan} = DefinitionCompiler.compile(definition, invocation, registries)
    plan
  end

  defp start_room(plan, connection_id) do
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    assert {:ok, room} = CallEngine.start_call(plan)

    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: connection_id,
               deadline: future_deadline()
             )

    assert {:ok, _attachment} = CallEngine.attach_connection(command)
    {room, caller}
  end

  defp send_text(plan, room, caller, connection_id, content) do
    assert {:ok, command} =
             SendText.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: connection_id,
               correlation_id: unique_id("turn"),
               content: content,
               deadline: future_deadline()
             )

    assert :ok = CallEngine.send_text(command)
    command
  end

  defp reply_with_tool(provider, id, text \\ "") do
    assert {:ok, call} = ToolCall.new(id: id, name: "wait_for_test", arguments: %{})
    assert {:ok, response} = ModelResponse.new(text: text, tool_calls: [call])
    send(provider, {:test_agent_runtime_response, {:ok, response}})
  end

  defp reply_with_text(provider, text) do
    assert {:ok, response} = ModelResponse.new(text: text)
    send(provider, {:test_agent_runtime_response, {:ok, response}})
  end

  defp assert_running_invocation(request, invocation_id, conversation_mode) do
    assert [
             %PendingInvocation{
               invocation_id: ^invocation_id,
               conversation_mode: ^conversation_mode,
               status: :running
             }
           ] = request.pending_invocations

    assert Enum.count(request.messages, fn
             %Message{role: :tool, tool_call_id: ^invocation_id, content: content} ->
               JSON.decode!(content) == %{
                 "invocation_id" => invocation_id,
                 "status" => "running"
               }

             _other ->
               false
           end) == 1
  end

  defp future_deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)
  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
