defmodule Vxpipe.CallEngine.AgentActivationSupervisorTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.AgentActivationSupervisor
  alias Vxpipe.CallEngine.AgentRuntime.Coordinator
  alias Vxpipe.CallEngine.Command.SendText
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.CallEngine.{TestAgentRuntimeModelProvider, TestAgentTool, TestBlockingTool}
  alias Vxpipe.CallEngine.Tool.{Context, InvocationCompletion, InvocationRegistry}

  alias Vxpipe.AgentRuntime.{Message, ModelResponse, ToolCall}

  setup do
    Application.put_env(:vxpipe_call_engine, :blocking_tool_observer, self())

    on_exit(fn ->
      Application.delete_env(:vxpipe_call_engine, :blocking_tool_observer)
    end)
  end

  test "owns one complete Agent Runtime activation graph" do
    activation_id = unique_activation_id()

    activation =
      start_supervised!({AgentActivationSupervisor, agent_runtime_options(activation_id)})

    first = AgentActivationSupervisor.children(activation)

    assert Map.keys(first) |> Enum.sort() == [
             :coordinator,
             :invocation_registry,
             :invocation_supervisor,
             :request_supervisor,
             :session
           ]

    assert Enum.all?(first, fn {_role, pid} -> is_pid(pid) end)

    assert :ok =
             Coordinator.respond(
               Map.fetch!(first, :coordinator),
               send_text("agent-runtime-activation")
             )

    assert_receive {:test_agent_runtime_stream, provider, request}

    assert [%Message{role: :system, content: "Use only the selected action."} | _history] =
             request.messages

    assert Enum.map(request.tools, & &1.name) == ["test_agent_tool"]

    assert {:ok, response} = ModelResponse.new(text: "Ready from Agent Runtime.")
    send(provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:vxpipe_capability_text, coordinator, command, "Ready from Agent Runtime."}
    assert coordinator == Map.fetch!(first, :coordinator)
    assert command.correlation_id == "agent-runtime-activation"
    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^command}

    monitors = monitor_children(first)
    Process.exit(Map.fetch!(first, :session), :kill)
    assert_children_stopped(monitors)

    _ = :sys.get_state(activation)
    second = AgentActivationSupervisor.children(activation)

    assert Enum.all?(second, fn {role, pid} ->
             is_pid(pid) and pid != Map.fetch!(first, role)
           end)

    restarted_monitors = monitor_children(second)
    activation_monitor = Process.monitor(activation)
    Process.exit(Map.fetch!(second, :session), :kill)

    assert_receive {:DOWN, ^activation_monitor, :process, ^activation, _reason}, 1_000
    assert_children_stopped(restarted_monitors)
  end

  test "a failed readiness configuration leaves no registered activation children" do
    activation_id = unique_activation_id()

    invalid_tool = %ToolBinding{
      name: "test_agent_tool",
      type: :host,
      conversation_mode: :blocking,
      action: String,
      remote: nil
    }

    invalid =
      Keyword.put(agent_runtime_options(activation_id), :tools, %{
        "test_agent_tool" => invalid_tool
      })

    assert {:error, _reason} = start_supervised({AgentActivationSupervisor, invalid})

    assert AgentActivationSupervisor.whereis_child(activation_id, :coordinator) == nil
    assert AgentActivationSupervisor.whereis_child(activation_id, :session) == nil
    assert AgentActivationSupervisor.whereis_child(activation_id, :invocation_supervisor) == nil
  end

  test "replacement discards an in-flight worker and ignores its stale completion" do
    activation_id = unique_activation_id()

    activation =
      start_supervised!({AgentActivationSupervisor, blocking_tool_options(activation_id)})

    first = AgentActivationSupervisor.children(activation)
    coordinator = Map.fetch!(first, :coordinator)

    assert :ok = Coordinator.respond(coordinator, send_text("stale-tool-activation"))
    assert_receive {:test_agent_runtime_stream, provider, _request}

    assert {:ok, call} =
             ToolCall.new(id: "stale-tool-call", name: "wait_for_test", arguments: %{})

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [call])
    send(provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:test_blocking_tool_started, execution}

    assert [{_id, invocation_worker, :worker, _modules}] =
             DynamicSupervisor.which_children(Map.fetch!(first, :invocation_supervisor))

    first_monitors = monitor_children(first)
    execution_monitor = Process.monitor(execution)
    Process.exit(Map.fetch!(first, :session), :kill)

    assert_children_stopped(first_monitors)
    assert_receive {:DOWN, ^execution_monitor, :process, ^execution, _reason}, 1_000

    _ = :sys.get_state(activation)
    second = AgentActivationSupervisor.children(activation)
    replacement_registry = Map.fetch!(second, :invocation_registry)

    stale_completion = %InvocationCompletion{
      invocation_id: "stale-tool-call",
      tool_name: "wait_for_test",
      conversation_mode: :blocking,
      context: stale_context(),
      outcome: {:ok, %{"released" => true}}
    }

    send(
      replacement_registry,
      {:vxpipe_tool_invocation_finished, invocation_worker, stale_completion}
    )

    _ = :sys.get_state(replacement_registry)
    assert {:ok, []} = InvocationRegistry.snapshot(replacement_registry)
  end

  defp agent_runtime_options(activation_id) do
    [
      runtime: :agent_runtime,
      activation_id: activation_id,
      agent_participant_id: "agent-test",
      owner: self(),
      system_prompt: "Use only the selected action.",
      tools: %{
        "test_agent_tool" => %ToolBinding{
          name: "test_agent_tool",
          type: :host,
          conversation_mode: :blocking,
          action: TestAgentTool,
          remote: nil
        }
      },
      variable_binding: nil,
      model_provider: TestAgentRuntimeModelProvider,
      model: %{owner: self()},
      provider: :test,
      tool_invocation_timeout_ms: 1_000,
      maximum_completed_requests: 4,
      maximum_tool_invocations: 2,
      maximum_output_bytes: 65_536,
      maximum_pending_requests: 2,
      maximum_tool_result_bytes: 4_096,
      request_timeout_ms: 1_000
    ]
  end

  defp blocking_tool_options(activation_id) do
    Keyword.put(agent_runtime_options(activation_id), :tools, %{
      "wait_for_test" => %ToolBinding{
        name: "wait_for_test",
        type: :host,
        conversation_mode: :blocking,
        action: TestBlockingTool,
        remote: nil
      }
    })
  end

  defp stale_context do
    %Context{
      tenant_id: "tenant-test",
      room_id: "room-test",
      incarnation_id: "incarnation-test",
      agent_participant_id: "agent-test",
      source_participant_id: "caller-test",
      connection_id: "connection-test",
      command_id: "command-test",
      correlation_id: "stale-tool-activation",
      agent_request_id: "request-test",
      tool_call_id: "stale-tool-call"
    }
  end

  defp send_text(correlation_id) do
    assert {:ok, command} =
             SendText.new(
               tenant_id: "tenant-test",
               actor_id: "actor-test",
               room_id: "room-test",
               incarnation_id: "incarnation-test",
               participant_id: "caller-test",
               connection_id: "connection-test",
               correlation_id: correlation_id,
               content: "Hello",
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    command
  end

  defp monitor_children(children) do
    Map.new(children, fn {role, pid} -> {role, {pid, Process.monitor(pid)}} end)
  end

  defp assert_children_stopped(monitors) do
    Enum.each(monitors, fn {_role, {pid, monitor}} ->
      assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}, 1_000
    end)
  end

  defp unique_activation_id do
    "act-supervised-#{System.unique_integer([:positive])}"
  end
end
