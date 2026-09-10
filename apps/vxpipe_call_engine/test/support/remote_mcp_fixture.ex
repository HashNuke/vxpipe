defmodule Vxpipe.CallEngine.RemoteMCPFixture do
  @moduledoc false

  alias Vxpipe.CallEngine.RemoteMCP.{Integration, IntegrationCatalog}
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.MCP.Catalog

  def binding!(client, observer, private_value, overrides \\ []) do
    {:ok, remote_catalog} = Catalog.new([tool_descriptor()])

    defaults = [
      integration_id: "records",
      configuration_generation: "configuration-1",
      credential_generation: "credential-1",
      catalog_generation: "catalog-1",
      catalog: remote_catalog,
      allowed_tools: ["lookup_customer"],
      client_config: [test_client: client, test_observer: observer, private: private_value],
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

  defp tool_descriptor do
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
  end
end
