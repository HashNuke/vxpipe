defmodule Vxpipe.CallEngine.CallDefinition.RemoteMCPCompilerTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.{CallDefinition, CallInvocation}

  alias Vxpipe.CallEngine.RemoteMCP.{
    CatalogStore,
    Integration,
    IntegrationCatalog,
    ResolvedTool
  }

  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.MCP.Catalog

  test "pins a tenant MCP descriptor without its private connection configuration" do
    private_value = "private-authorization-sentinel"

    {:ok, integration} =
      Integration.new(
        integration_id: "records",
        configuration_generation: "config-12",
        credential_generation: "credential-7",
        catalog_generation: "catalog-4",
        catalog: catalog("lookup_customer"),
        allowed_tools: ["lookup_customer"],
        client_config: [
          endpoint: "https://records.example.test/mcp",
          authentication: [
            type: :custom_headers,
            headers: [{"authorization", private_value}]
          ]
        ],
        invocation_deadline_ms: 12_000,
        maximum_result_bytes: 65_536
      )

    {:ok, integrations} =
      IntegrationCatalog.new(
        application: %{},
        tenants: %{"tenant-demo" => %{"records" => integration}}
      )

    assert {:ok, definition} =
             CallDefinition.new(definition_input(), resource_id: "support", revision: 7)

    assert {:ok, invocation} =
             CallInvocation.new(invocation_input(),
               tenant_id: "tenant-demo",
               actor_id: "actor-demo"
             )

    store = start_supervised!({CatalogStore, catalog: integrations})

    assert {:ok, plan} =
             CallEngine.compile_definition(
               definition,
               invocation,
               Map.delete(registries(integrations), :mcp_integrations),
               mcp_catalog_store: store
             )

    assert %ToolBinding{
             name: "customer_lookup",
             type: :mcp,
             conversation_mode: :non_blocking,
             remote: %ResolvedTool{
               scope: {:tenant, "tenant-demo"},
               integration_id: "records",
               configuration_generation: "config-12",
               credential_generation: "credential-7",
               catalog_generation: "catalog-4",
               remote_name: "lookup_customer",
               description: "Looks up one customer.",
               input_schema: %{
                 "type" => "object",
                 "properties" => %{"customer_id" => %{"type" => "string"}},
                 "required" => ["customer_id"],
                 "additionalProperties" => false
               },
               invocation_deadline_ms: 12_000,
               maximum_result_bytes: 65_536
             }
           } = plan.participants["reception"].tools["customer_lookup"]

    refute inspect(plan) =~ private_value
    refute inspect(plan) =~ "authorization"
    refute inspect(plan) =~ "records.example.test"
  end

  defp catalog(name) do
    {:ok, catalog} =
      Catalog.new([
        %{
          "name" => name,
          "description" => "Looks up one customer.",
          "inputSchema" => %{
            "type" => "object",
            "properties" => %{"customer_id" => %{"type" => "string"}},
            "required" => ["customer_id"],
            "additionalProperties" => false
          }
        }
      ])

    catalog
  end

  defp definition_input do
    %{
      schema_version: CallDefinition.schema_version(),
      entry_caller: "caller",
      entry_receiver: "reception",
      defaults: %{
        capabilities: %{
          speech_to_text: %{provider: "morse", model: "morse"},
          model_inference: %{provider: "fixture", model: "test:scripted"},
          text_to_speech: %{provider: "morse", model: "morse"}
        }
      },
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "reception" => %{
          type: "agent",
          prompt: "Answer clearly.",
          tools: %{
            "customer_lookup" => %{
              type: "mcp",
              integration: "records",
              conversation_mode: "non_blocking",
              tool: "lookup_customer"
            }
          }
        }
      }
    }
  end

  defp invocation_input do
    %{
      call_definition: %{id: "support", revision: 7},
      initial_variables: %{},
      transport: %{type: "web"}
    }
  end

  defp registries(integrations) do
    %{
      host_tools: %{},
      mcp_integrations: integrations
    }
  end
end
