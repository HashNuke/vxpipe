defmodule Vxpipe.CallEngine.RemoteMCP.IntegrationCatalogTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.RemoteMCP.{Integration, IntegrationCatalog}
  alias Vxpipe.MCP.Catalog

  test "uses the application record only when the tenant record is absent" do
    application = integration!("records", "application_lookup", "application-secret")

    {:ok, without_override} =
      IntegrationCatalog.new(application: %{"records" => application}, tenants: %{})

    assert {:ok, %{scope: :application, remote_name: "application_lookup"}} =
             IntegrationCatalog.resolve(
               without_override,
               "tenant-demo",
               "records",
               "application_lookup"
             )

    tenant = integration!("records", "tenant_lookup", "tenant-secret")

    {:ok, with_override} =
      IntegrationCatalog.new(
        application: %{"records" => application},
        tenants: %{"tenant-demo" => %{"records" => tenant}}
      )

    assert {:error, :tool_not_allowed} =
             IntegrationCatalog.resolve(
               with_override,
               "tenant-demo",
               "records",
               "application_lookup"
             )
  end

  test "checks out only the exact private generation pinned for its scope" do
    tenant = integration!("records", "lookup", "tenant-secret")
    application = integration!("records", "lookup", "application-secret")

    {:ok, original} =
      IntegrationCatalog.new(
        application: %{"records" => application},
        tenants: %{"tenant-demo" => %{"records" => tenant}}
      )

    assert {:ok, resolved} =
             IntegrationCatalog.resolve(original, "tenant-demo", "records", "lookup")

    assert {:ok, checked_out} = IntegrationCatalog.checkout(original, resolved)
    assert checked_out.client_config == [private: "tenant-secret"]

    {:ok, missing_tenant_record} =
      IntegrationCatalog.new(application: %{"records" => application}, tenants: %{})

    assert {:error, :stale_integration} =
             IntegrationCatalog.checkout(missing_tenant_record, resolved)

    changed =
      integration!("records", "lookup", "replacement-secret",
        credential_generation: "credential-2"
      )

    {:ok, replaced_generation} =
      IntegrationCatalog.new(
        application: %{"records" => application},
        tenants: %{"tenant-demo" => %{"records" => changed}}
      )

    assert {:error, :stale_integration} =
             IntegrationCatalog.checkout(replaced_generation, resolved)
  end

  defp integration!(integration_id, tool_name, private_value, overrides \\ []) do
    defaults = [
      integration_id: integration_id,
      configuration_generation: "configuration-1",
      credential_generation: "credential-1",
      catalog_generation: "catalog-1",
      catalog: catalog!(tool_name),
      allowed_tools: [tool_name],
      client_config: [private: private_value]
    ]

    {:ok, integration} = Integration.new(Keyword.merge(defaults, overrides))
    integration
  end

  defp catalog!(name) do
    {:ok, catalog} =
      Catalog.new([
        %{
          "name" => name,
          "description" => "Looks up one record.",
          "inputSchema" => %{
            "type" => "object",
            "properties" => %{"record_id" => %{"type" => "string"}},
            "required" => ["record_id"],
            "additionalProperties" => false
          }
        }
      ])

    catalog
  end
end
