defmodule Vxpipe.CallEngine.AgentActivationSupervisorTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.AgentActivationSupervisor
  alias Vxpipe.CallEngine.TestAgentTool

  test "starts a configured activation before readiness and restarts it only once" do
    activation_id = unique_activation_id()
    activation = start_supervised!({AgentActivationSupervisor, options(activation_id)})

    first = AgentActivationSupervisor.children(activation)

    assert Map.keys(first) |> Enum.sort() == [
             :agent_server,
             :background_tools,
             :coordinator,
             :tool_dispatcher
           ]

    assert Enum.all?(first, fn {_role, pid} -> is_pid(pid) end)

    assert {:ok, state} = Jido.AgentServer.state(Map.fetch!(first, :agent_server))
    config = Jido.AI.get_strategy_config(state.agent)
    assert config.system_prompt == "Use only the selected action."
    assert Enum.map(config.tools, & &1.name()) == ["test_agent_tool"]

    monitors = monitor_children(first)
    Process.exit(Map.fetch!(first, :agent_server), :kill)
    assert_children_stopped(monitors)

    _ = :sys.get_state(activation)
    second = AgentActivationSupervisor.children(activation)

    assert Enum.all?(second, fn {role, pid} ->
             is_pid(pid) and pid != Map.fetch!(first, role)
           end)

    assert {:ok, restarted_state} =
             Jido.AgentServer.state(Map.fetch!(second, :agent_server))

    restarted_config = Jido.AI.get_strategy_config(restarted_state.agent)
    assert restarted_config.system_prompt == "Use only the selected action."
    assert Enum.map(restarted_config.tools, & &1.name()) == ["test_agent_tool"]

    restarted_monitors = monitor_children(second)
    activation_monitor = Process.monitor(activation)
    Process.exit(Map.fetch!(second, :agent_server), :kill)

    assert_receive {:DOWN, ^activation_monitor, :process, ^activation, _reason}, 1_000
    assert_children_stopped(restarted_monitors)
  end

  test "a failed readiness configuration leaves no registered activation children" do
    activation_id = unique_activation_id()
    invalid = Keyword.put(options(activation_id), :tools, [String])

    assert {:error, _reason} = start_supervised({AgentActivationSupervisor, invalid})

    assert AgentActivationSupervisor.whereis_child(activation_id, :agent_server) == nil
    assert AgentActivationSupervisor.whereis_child(activation_id, :coordinator) == nil
    assert AgentActivationSupervisor.whereis_child(activation_id, :tool_dispatcher) == nil
  end

  defp options(activation_id) do
    [
      activation_id: activation_id,
      agent_participant_id: "agent-test",
      owner: self(),
      system_prompt: "Use only the selected action.",
      tools: [TestAgentTool],
      background_tool_timeout_ms: 1_000,
      maximum_completed_requests: 4,
      maximum_background_tools: 2,
      maximum_output_bytes: 65_536,
      maximum_pending_requests: 2,
      maximum_tool_result_bytes: 4_096,
      request_options: [],
      request_timeout_ms: 1_000
    ]
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
