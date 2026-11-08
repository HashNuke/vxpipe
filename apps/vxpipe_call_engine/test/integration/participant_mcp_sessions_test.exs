defmodule Vxpipe.CallEngine.ParticipantMCPSessionsTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.{
    AgentActivationSupervisor,
    ForeignMCPConnectionProvider,
    RemoteMCPFixture,
    RemoteMCPWireConnectionProvider,
    RemoteMCPWireServer,
    TestAgentRuntimeModelProvider
  }

  alias Vxpipe.CallEngine.RemoteMCP.IntegrationOwner
  alias Vxpipe.CallEngine.Usage.ProviderContext
  alias Vxpipe.MCP.{Connection, ConnectionKey, Connections, ExMCPClient}

  @moduletag :integration
  @moduletag :capture_log

  test "equal tenant grants in two activations have separate session descendants and lifetimes" do
    {catalog, binding, key} = catalog()
    first_id = unique("first")
    second_id = unique("second")
    first = start_supervised!({AgentActivationSupervisor, options(first_id, catalog, binding)})
    second = start_supervised!({AgentActivationSupervisor, options(second_id, catalog, binding)})
    first_children = AgentActivationSupervisor.children(first)
    second_children = AgentActivationSupervisor.children(second)

    assert {:ok, first_host} = Map.fetch(first_children, :remote_mcp_sessions)
    assert {:ok, second_host} = Map.fetch(second_children, :remote_mcp_sessions)
    refute first_host == second_host
    assert {:ok, first_connection} = Connections.lookup(key, owner: first_host)
    assert {:ok, second_connection} = Connections.lookup(key, owner: second_host)
    refute Connection.client(first_connection) == Connection.client(second_connection)

    for {host, connection} <- [{first_host, first_connection}, {second_host, second_connection}] do
      assert Enum.any?(DynamicSupervisor.which_children(host), fn {_id, pid, _, _} ->
               pid == Connection.owner(connection)
             end)
    end

    assert {:ok, _} = invoke(Map.fetch!(first_children, :remote_mcp_owner))
    assert {:ok, _} = invoke(Map.fetch!(second_children, :remote_mcp_owner))
    client = Connection.client(first_connection)
    reference = Process.monitor(client)
    assert :ok = stop_supervised({AgentActivationSupervisor, first_id})
    assert_receive {:DOWN, ^reference, :process, ^client, _reason}, 1_000
    assert {:ok, _} = invoke(Map.fetch!(second_children, :remote_mcp_owner))
    assert {:ok, ^second_connection} = Connections.lookup(key, owner: second_host)
  end

  test "activation recovery replaces session ownership without disturbing another activation" do
    {catalog, binding, key} = catalog()
    first_id = unique("recovery")
    first = start_supervised!({AgentActivationSupervisor, options(first_id, catalog, binding)})

    second =
      start_supervised!({AgentActivationSupervisor, options(unique("other"), catalog, binding)})

    original = AgentActivationSupervisor.children(first)
    other = AgentActivationSupervisor.children(second)
    assert {:ok, host} = Map.fetch(original, :remote_mcp_sessions)
    assert {:ok, connection} = Connections.lookup(key, owner: host)
    monitors = Map.new(original, fn {_role, pid} -> {pid, Process.monitor(pid)} end)
    Process.exit(Connection.client(connection), :kill)

    for {pid, reference} <- monitors do
      assert_receive {:DOWN, ^reference, :process, ^pid, _reason}, 1_000
    end

    _ = :sys.get_state(first)
    replacement = AgentActivationSupervisor.children(first)
    replacement_host = Map.fetch!(replacement, :remote_mcp_sessions)
    refute host == replacement_host
    assert {:ok, replaced} = Connections.lookup(key, owner: replacement_host)
    refute Connection.client(replaced) == Connection.client(connection)
    assert :ok = Connections.close(connection)
    assert {:ok, _} = invoke(Map.fetch!(replacement, :remote_mcp_owner))
    assert {:ok, _} = invoke(Map.fetch!(other, :remote_mcp_owner))
  end

  test "a provider's foreign handle is rejected without retiring its actual owner" do
    {catalog, binding, key} = catalog()
    remote = binding.remote
    {:ok, integration} = Vxpipe.CallEngine.RemoteMCP.IntegrationCatalog.checkout(catalog, remote)
    name = {:via, Registry, {Vxpipe.MCP.ConnectionRegistry, {:foreign_host, make_ref()}}}
    host = start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: name})

    assert {:ok, foreign} =
             Connections.open_loopback_test(key, integration.client_config, owner: host)

    {foreign_catalog, foreign_binding} =
      RemoteMCPFixture.binding!(nil, self(), "unused",
        credential_generation: key.credential_generation,
        client_config: [foreign_connection: foreign]
      )

    activation_id = unique("foreign")

    options =
      options(activation_id, foreign_catalog, foreign_binding)
      |> Keyword.put(:remote_mcp_connection_provider, ForeignMCPConnectionProvider)

    assert {:error, _reason} = start_supervised({AgentActivationSupervisor, options})

    assert {:ok, _} =
             ExMCPClient.call_tool(
               Connection.client(foreign),
               "lookup_customer",
               %{"customer_id" => "kept"},
               1_000
             )

    assert {:ok, ^foreign} = Connections.lookup(key, owner: host)
  end

  defp catalog do
    server = start_supervised!({RemoteMCPWireServer, owner: self()})
    generation = unique("credential")

    {catalog, binding} =
      RemoteMCPFixture.binding!(nil, self(), "unused",
        credential_generation: generation,
        client_config: [endpoint: RemoteMCPWireServer.endpoint(server), use_sse: false]
      )

    {:ok, key} =
      ConnectionKey.new(
        scope: :tenant,
        tenant_id: "tenant-demo",
        integration_id: "records",
        credential_generation: generation
      )

    on_exit(fn -> Connections.close(key) end)
    {catalog, binding, key}
  end

  defp options(activation_id, catalog, binding) do
    {:ok, provider} =
      ProviderContext.new(name: "test", integration_id: "test-model", model: "test:scripted")

    [
      activation_id: activation_id,
      agent_participant_id: unique("participant"),
      call_id: unique("call"),
      owner: self(),
      system_prompt: "Use the selected tool.",
      tools: %{"customer_lookup" => binding},
      mcp_integrations: catalog,
      remote_mcp_connection_provider: RemoteMCPWireConnectionProvider,
      model_provider: TestAgentRuntimeModelProvider,
      model: %{owner: self()},
      usage_provider: provider,
      maximum_completed_requests: 4,
      maximum_tool_invocations: 2,
      maximum_output_bytes: 65_536,
      maximum_pending_requests: 2,
      maximum_tool_result_bytes: 4_096,
      tool_invocation_timeout_ms: 1_000,
      request_timeout_ms: 1_000
    ]
  end

  defp invoke(owner),
    do: IntegrationOwner.execute(owner, "customer_lookup", %{"customer_id" => "one"})

  defp unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
