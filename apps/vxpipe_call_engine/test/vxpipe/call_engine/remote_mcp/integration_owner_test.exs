defmodule Vxpipe.CallEngine.RemoteMCP.IntegrationOwnerTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.RemoteMCP.IntegrationOwner
  alias Vxpipe.CallEngine.RemoteMCPFixture
  alias Vxpipe.MCP.{Connections, CredentialLeases}

  test "withholds readiness until scoped connection initialization finishes without invoking tools" do
    client = client!([])

    {catalog, binding} =
      RemoteMCPFixture.binding!(client, self(), "private",
        client_config: [
          test_client: client,
          test_observer: self(),
          test_gate_initialization: true,
          private: "private-readiness-sentinel"
        ]
      )

    supervisor =
      start_supervised!({DynamicSupervisor, name: unique_name(), strategy: :one_for_one})

    tasks = start_supervised!({Task.Supervisor, name: unique_name()})
    name = unique_name()

    starter =
      Task.Supervisor.async_nolink(tasks, fn ->
        DynamicSupervisor.start_child(
          supervisor,
          {IntegrationOwner,
           activation_id: "readiness-activation",
           participant_id: "support-agent",
           tools: %{"customer_lookup" => binding},
           integrations: catalog,
           name: name,
           connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
           protocol: Vxpipe.CallEngine.TestRemoteMCPProtocolClient}
        )
      end)

    assert_receive {:test_remote_mcp_initializing, owner}
    observer = self()

    query =
      Task.Supervisor.async_nolink(tasks, fn ->
        result = IntegrationOwner.readiness(name)
        send(observer, {:readiness_result, result})
        result
      end)

    refute_receive {:readiness_result, _result}
    send(owner, :test_remote_mcp_initialized)
    assert {:ok, ^owner} = Task.await(starter)
    assert {:ok, resource, :ready} = Task.await(query)
    assert resource.instance == owner
    assert resource.scope == {:participant, "support-agent"}
    assert resource.binding == "readiness-activation"
    assert resource.kind == :remote_tools
    assert is_reference(resource.generation)
    assert byte_size(resource.configuration) == 32
    refute inspect(resource) =~ "private-readiness-sentinel"
    assert {:ok, ^resource, :ready} = IntegrationOwner.readiness(owner)
    assert invocations(client) == []
  end

  test "opens the scoped generation and invokes the pinned remote operation" do
    client = client!([{:ok, %{"content" => [%{"type" => "text", "text" => "found"}]}}])
    private_value = "private-runtime-sentinel"

    {catalog, binding} =
      RemoteMCPFixture.binding!(client, self(), private_value, maximum_result_bytes: 65_536)

    owner =
      start_supervised!(
        {IntegrationOwner,
         activation_id: "activation-one",
         tools: %{"customer_lookup" => binding},
         integrations: catalog,
         connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
         protocol: Vxpipe.CallEngine.TestRemoteMCPProtocolClient}
      )

    assert_receive {:test_remote_mcp_opened, key, opened_config}
    assert key.scope == {:tenant, "tenant-demo"}
    assert key.integration_id == "records"
    assert key.credential_generation == "credential-1"
    assert opened_config[:private] == private_value

    limits = Keyword.fetch!(opened_config, :limits)
    assert limits[:max_response_bytes] == 65_536
    assert limits[:max_stream_buffer_bytes] == 65_536
    refute inspect(:sys.get_state(owner)) =~ private_value

    assert {:error, :invalid_arguments} =
             IntegrationOwner.execute(owner, "customer_lookup", %{"customer_id" => 42})

    assert invocations(client) == []

    arguments = %{"customer_id" => "customer-42"}

    assert {:ok, %{"content" => [%{"text" => "found", "type" => "text"}]}} =
             IntegrationOwner.execute(owner, "customer_lookup", arguments)

    assert [%{name: "lookup_customer", arguments: ^arguments, timeout: timeout}] =
             invocations(client)

    assert timeout in 1..12_000
    assert {:error, :unknown_tool} = IntegrationOwner.execute(owner, "not_enabled", %{})
  end

  test "withholds a remote response beyond the pinned result limit" do
    client = client!([{:ok, %{"content" => [String.duplicate("x", 100)]}}])

    {catalog, binding} =
      RemoteMCPFixture.binding!(client, self(), "private", maximum_result_bytes: 32)

    owner =
      start_supervised!(
        {IntegrationOwner,
         activation_id: "activation-limit",
         tools: %{"customer_lookup" => binding},
         integrations: catalog,
         connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
         protocol: Vxpipe.CallEngine.TestRemoteMCPProtocolClient}
      )

    assert_receive {:test_remote_mcp_opened, _key, _config}

    assert {:error, :invalid_result} =
             IntegrationOwner.execute(
               owner,
               "customer_lookup",
               %{"customer_id" => "customer-42"}
             )

    assert length(invocations(client)) == 1
  end

  test "fails the binding owner closed when its protocol client exits" do
    client = client!([])
    {catalog, binding} = RemoteMCPFixture.binding!(client, self(), "private")

    owner =
      start_supervised!(
        {IntegrationOwner,
         activation_id: "activation-connection-loss",
         participant_id: "support-agent",
         tools: %{"customer_lookup" => binding},
         integrations: catalog,
         connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
         protocol: Vxpipe.CallEngine.TestRemoteMCPProtocolClient}
      )

    assert_receive {:test_remote_mcp_opened, _key, _config}
    client_monitor = Process.monitor(client)
    owner_monitor = Process.monitor(owner)
    assert {:ok, _resource, :ready} = IntegrationOwner.readiness(owner)

    assert :ok = stop_supervised(Agent)
    assert_receive {:DOWN, ^client_monitor, :process, ^client, _reason}, 1_000
    assert_receive {:DOWN, ^owner_monitor, :process, ^owner, :connection_lost}, 1_000
    assert {:error, :unavailable} = IntegrationOwner.readiness(owner)
  end

  test "ends a revoked credential lease with its binding owner" do
    generation = "credential-revoked-#{System.unique_integer([:positive, :monotonic])}"
    client = client!([])

    {catalog, binding} =
      RemoteMCPFixture.binding!(client, self(), "private", credential_generation: generation)

    owner =
      start_supervised!(
        {IntegrationOwner,
         activation_id: "activation-revoked-credential",
         participant_id: "support-agent",
         tools: %{"customer_lookup" => binding},
         integrations: catalog,
         connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
         protocol: Vxpipe.CallEngine.TestRemoteMCPProtocolClient}
      )

    assert_receive {:test_remote_mcp_opened, key, _config}
    assert CredentialLeases.active_count(key) == 1
    assert {:ok, _resource, :ready} = IntegrationOwner.readiness(owner)

    owner_monitor = Process.monitor(owner)
    assert :ok = Connections.revoke(key)
    assert_receive {:DOWN, ^owner_monitor, :process, ^owner, :credential_revoked}, 1_000
    assert CredentialLeases.active_count(key) == 0
    assert {:error, :unavailable} = IntegrationOwner.readiness(owner)

    assert {:error, {:credential_revoked, _child}} =
             start_supervised(
               {IntegrationOwner,
                activation_id: "activation-revoked-credential-reuse",
                tools: %{"customer_lookup" => binding},
                integrations: catalog,
                connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
                protocol: Vxpipe.CallEngine.TestRemoteMCPProtocolClient}
             )

    refute_receive {:test_remote_mcp_opened, ^key, _config}
  end

  defp client!(responses) do
    start_supervised!({Agent, fn -> %{responses: responses, invocations: []} end})
  end

  defp invocations(client), do: Agent.get(client, & &1.invocations)

  defp unique_name, do: {:global, {__MODULE__, make_ref()}}
end
