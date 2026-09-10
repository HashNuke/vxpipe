defmodule Vxpipe.CallEngine.RemoteMCP.IntegrationOwnerTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.RemoteMCP.{Integration, IntegrationCatalog, IntegrationOwner}
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.MCP.Catalog

  test "opens the scoped generation and invokes the pinned remote operation" do
    client = client!([{:ok, %{"content" => [%{"type" => "text", "text" => "found"}]}}])
    private_value = "private-runtime-sentinel"
    {catalog, binding} = binding!(client, private_value, maximum_result_bytes: 65_536)

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
    {catalog, binding} = binding!(client, "private", maximum_result_bytes: 32)

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

  defp binding!(client, private_value, overrides) do
    {:ok, remote_catalog} =
      Catalog.new([
        %{
          "name" => "lookup_customer",
          "description" => "Looks up one customer.",
          "inputSchema" => %{
            "type" => "object",
            "properties" => %{"customer_id" => %{"type" => "string"}},
            "required" => ["customer_id"],
            "additionalProperties" => false
          }
        }
      ])

    defaults = [
      integration_id: "records",
      configuration_generation: "configuration-1",
      credential_generation: "credential-1",
      catalog_generation: "catalog-1",
      catalog: remote_catalog,
      allowed_tools: ["lookup_customer"],
      client_config: [test_client: client, test_observer: self(), private: private_value],
      invocation_deadline_ms: 12_000
    ]

    {:ok, integration} = Integration.new(Keyword.merge(defaults, overrides))

    {:ok, integrations} =
      IntegrationCatalog.new(
        application: %{},
        tenants: %{"tenant-demo" => %{"records" => integration}}
      )

    {:ok, remote} =
      IntegrationCatalog.resolve(
        integrations,
        "tenant-demo",
        "records",
        "lookup_customer"
      )

    binding = %ToolBinding{
      name: "customer_lookup",
      type: :mcp,
      action: nil,
      remote: remote
    }

    {integrations, binding}
  end

  defp client!(responses) do
    start_supervised!({Agent, fn -> %{responses: responses, invocations: []} end})
  end

  defp invocations(client), do: Agent.get(client, & &1.invocations)
end
