defmodule Vxpipe.CallEngine.AgentActivationSupervisorTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.AgentActivationSupervisor
  alias Vxpipe.CallEngine.AgentRuntime.Coordinator
  alias Vxpipe.CallEngine.Command.SendText
  alias Vxpipe.CallEngine.RemoteMCPFixture
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.CallEngine.TestAgentTool
  alias Vxpipe.CallEngine.TestAgentRuntimeModelProvider
  alias Vxpipe.MCP.CredentialLeases

  alias Vxpipe.AgentRuntime.{Message, ModelResponse}

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

  test "owns remote MCP authorization for exactly the activation subtree" do
    activation_id = unique_activation_id()
    observer = self()
    private_value = "private-activation-sentinel"

    client =
      start_supervised!(
        {Agent, fn -> %{responses: [], invocations: []} end},
        id: {:remote_mcp_client, activation_id}
      )

    {integrations, binding} =
      RemoteMCPFixture.binding!(client, observer, private_value)

    activation_options =
      Keyword.merge(options(activation_id),
        remote_tools: %{"customer_lookup" => binding},
        mcp_integrations: integrations,
        remote_mcp_connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
        remote_mcp_protocol: Vxpipe.CallEngine.TestRemoteMCPProtocolClient
      )

    activation = start_supervised!({AgentActivationSupervisor, activation_options})
    assert_receive {:test_remote_mcp_opened, key, _config}
    assert CredentialLeases.active_count(key) == 1

    first = AgentActivationSupervisor.children(activation)
    first_owner = Map.fetch!(first, :remote_mcp)

    assert AgentActivationSupervisor.whereis_child(activation_id, :remote_mcp) == first_owner
    refute inspect(:sys.get_state(first_owner)) =~ private_value
    refute inspect(:sys.get_state(activation)) =~ private_value

    first_monitors = monitor_children(first)
    Process.exit(first_owner, :kill)
    assert_children_stopped(first_monitors)

    _ = :sys.get_state(activation)
    assert_receive {:test_remote_mcp_opened, _key, _config}
    assert CredentialLeases.active_count(key) == 1

    second = AgentActivationSupervisor.children(activation)

    assert Enum.all?(second, fn {role, pid} ->
             is_pid(pid) and pid != Map.fetch!(first, role)
           end)

    second_monitors = monitor_children(second)
    assert :ok = stop_supervised({AgentActivationSupervisor, activation_id})
    assert_children_stopped(second_monitors)
    assert AgentActivationSupervisor.whereis_child(activation_id, :remote_mcp) == nil
    assert CredentialLeases.active_count(key) == 0
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
      background_tool_timeout_ms: 1_000,
      maximum_completed_requests: 4,
      maximum_background_tools: 2,
      maximum_output_bytes: 65_536,
      maximum_pending_requests: 2,
      maximum_tool_result_bytes: 4_096,
      request_timeout_ms: 1_000
    ]
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
