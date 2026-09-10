defmodule Vxpipe.CallEngine.RemoteMCP.IntegrationOwnerTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.RemoteMCP.IntegrationOwner
  alias Vxpipe.CallEngine.RemoteMCPFixture

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
         tools: %{"customer_lookup" => binding},
         integrations: catalog,
         connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
         protocol: Vxpipe.CallEngine.TestRemoteMCPProtocolClient}
      )

    assert_receive {:test_remote_mcp_opened, _key, _config}
    client_monitor = Process.monitor(client)
    owner_monitor = Process.monitor(owner)

    assert :ok = stop_supervised(Agent)
    assert_receive {:DOWN, ^client_monitor, :process, ^client, _reason}
    assert_receive {:DOWN, ^owner_monitor, :process, ^owner, :connection_lost}
  end

  defp client!(responses) do
    start_supervised!({Agent, fn -> %{responses: responses, invocations: []} end})
  end

  defp invocations(client), do: Agent.get(client, & &1.invocations)
end
