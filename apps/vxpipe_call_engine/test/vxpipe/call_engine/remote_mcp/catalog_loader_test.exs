defmodule Vxpipe.CallEngine.RemoteMCP.CatalogLoaderTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.RemoteMCP.{CatalogLoader, ConfiguredIntegration}
  alias Vxpipe.MCP.Catalog

  test "loads one tenant-scoped discovered integration without exposing private configuration" do
    client = discovery_client([{:ok, %{"tools" => [tool("lookup_customer")]}}])
    private_value = "private-catalog-loader-value"

    assert {:ok, configured} =
             ConfiguredIntegration.new(
               scope: {:tenant, "tenant-demo"},
               integration_id: "records",
               configuration_generation: "configuration-1",
               credential_generation: "credential-1",
               catalog_generation: "catalog-1",
               allowed_tools: ["lookup_customer"],
               client_config: [
                 test_client: client,
                 test_observer: self(),
                 private: private_value
               ],
               discovery_deadline_ms: 1_000,
               maximum_discovery_pages: 2,
               maximum_discovery_bytes: 10_000
             )

    refute inspect(configured) =~ private_value

    assert {:ok, integration} =
             CatalogLoader.load(configured,
               connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
               protocol: Vxpipe.CallEngine.TestRemoteMCPCatalogProtocolClient
             )

    assert_receive {:test_remote_mcp_opened, key, opened_config}
    assert key.scope == {:tenant, "tenant-demo"}
    assert key.integration_id == "records"
    assert key.credential_generation == "credential-1"
    assert opened_config[:private] == private_value
    assert opened_config[:limits][:max_response_bytes] == 1_048_576
    assert opened_config[:limits][:max_stream_buffer_bytes] == 1_048_576

    assert [%{cursor: nil, timeout: timeout}] = discovery_calls(client)
    assert timeout in 1..1_000

    assert {:ok, %{"name" => "lookup_customer"}} =
             Catalog.fetch(integration.catalog, "lookup_customer")

    assert integration.allowed_tools == MapSet.new(["lookup_customer"])
    refute inspect(integration) =~ private_value
  end

  test "rejects a configured allowed tool that is absent from complete discovery" do
    client = discovery_client([{:ok, %{"tools" => [tool("different_tool")]}}])

    assert {:ok, configured} = configured_integration(client)

    assert {:error, :invalid_discovered_catalog} =
             CatalogLoader.load(configured,
               connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
               protocol: Vxpipe.CallEngine.TestRemoteMCPCatalogProtocolClient
             )

    assert_receive {:test_remote_mcp_opened, _key, _opened_config}
    assert length(discovery_calls(client)) == 1
  end

  test "rejects malformed private configuration before discovery" do
    assert {:error, :invalid_configured_integration} =
             ConfiguredIntegration.new(
               scope: :application,
               integration_id: "records",
               configuration_generation: "configuration-1",
               credential_generation: "credential-1",
               catalog_generation: "catalog-1",
               allowed_tools: ["lookup_customer", "lookup_customer"],
               client_config: [limits: :unbounded]
             )

    assert {:error, :invalid_configured_integration} =
             ConfiguredIntegration.new(
               scope: :application,
               integration_id: "records",
               configuration_generation: "configuration-1",
               credential_generation: "credential-1",
               catalog_generation: "catalog-1",
               allowed_tools: ["lookup_customer"],
               client_config: [:not_a_keyword_entry]
             )
  end

  defp configured_integration(client) do
    ConfiguredIntegration.new(
      scope: :application,
      integration_id: "records",
      configuration_generation: "configuration-1",
      credential_generation: "credential-1",
      catalog_generation: "catalog-1",
      allowed_tools: ["lookup_customer"],
      client_config: [test_client: client, test_observer: self()]
    )
  end

  defp discovery_client(responses) do
    start_supervised!(
      {Agent,
       fn ->
         %{
           discovery_calls: [],
           discovery_responses: responses
         }
       end},
      id: {Agent, make_ref()}
    )
  end

  defp discovery_calls(client), do: Agent.get(client, & &1.discovery_calls)

  defp tool(name) do
    %{
      "name" => name,
      "description" => "Looks up one customer.",
      "inputSchema" => %{
        "$schema" => "https://json-schema.org/draft/2020-12/schema",
        "type" => "object",
        "properties" => %{"customer_id" => %{"type" => "string"}},
        "required" => ["customer_id"],
        "additionalProperties" => false
      }
    }
  end
end
