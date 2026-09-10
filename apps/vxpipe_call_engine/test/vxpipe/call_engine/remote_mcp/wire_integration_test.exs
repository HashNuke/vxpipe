defmodule Vxpipe.CallEngine.RemoteMCP.WireIntegrationTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.RemoteMCP.{
    CatalogLoader,
    ConfiguredIntegration,
    IntegrationCatalog,
    IntegrationOwner
  }

  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.CallEngine.{RemoteMCPWireConnectionProvider, RemoteMCPWireServer}
  alias Vxpipe.MCP.Connections

  @authorization "Bearer controlled-tenant-credential"

  test "discovers and invokes the pinned operation through the real protocol client" do
    %{binding: binding, catalog: catalog, key: key} = start_runtime!()
    on_exit(fn -> Connections.close(key) end)

    owner = start_owner!(catalog, binding, "wire-success")
    arguments = %{"customer_id" => "customer-42"}

    assert {:ok,
            %{
              "content" => [
                %{"text" => "found customer-42", "type" => "text"}
              ]
            }} = IntegrationOwner.execute(owner, "customer_lookup", arguments)

    assert_receive {:remote_mcp_wire_request, "tools/call", @authorization,
                    %{
                      "params" => %{
                        "arguments" => ^arguments,
                        "name" => "lookup_customer"
                      }
                    }}
  end

  test "rejects invalid arguments before sending the tool request" do
    %{binding: binding, catalog: catalog, key: key} = start_runtime!()
    on_exit(fn -> Connections.close(key) end)

    owner = start_owner!(catalog, binding, "wire-invalid-arguments")

    assert {:error, :invalid_arguments} =
             IntegrationOwner.execute(owner, "customer_lookup", %{"customer_id" => 42})

    refute_receive {:remote_mcp_wire_request, "tools/call", _authorization, _request}, 100
  end

  test "reports submitted timeout and oversized wire response as unknown without retry" do
    for {scenario, deadline_ms, maximum_result_bytes} <- [
          {"slow", 100, 4_096},
          {"oversized", 1_000, 512}
        ] do
      %{binding: binding, catalog: catalog, key: key} =
        start_runtime!(
          invocation_deadline_ms: deadline_ms,
          maximum_result_bytes: maximum_result_bytes
        )

      owner = start_owner!(catalog, binding, "wire-#{scenario}")

      assert {:error, :unknown} =
               IntegrationOwner.execute(owner, "customer_lookup", %{"customer_id" => scenario})

      assert_receive {:remote_mcp_wire_request, "tools/call", @authorization,
                      %{"params" => %{"arguments" => %{"customer_id" => ^scenario}}}}

      refute_receive {:remote_mcp_wire_request, "tools/call", _authorization, _request}, 100
      :ok = stop_supervised({IntegrationOwner, "activation-wire-#{scenario}"})
      :ok = Connections.close(key)
    end
  end

  test "fails discovery when the configured authentication is rejected" do
    server =
      start_supervised!({RemoteMCPWireServer, owner: self(), authorization: @authorization})

    endpoint = RemoteMCPWireServer.endpoint(server)

    configured =
      configured!(endpoint,
        client_config: [
          endpoint: endpoint,
          authentication: [type: :bearer, token: "rejected-credential"],
          use_sse: false
        ]
      )

    on_exit(fn -> Connections.close(configured.connection_key) end)

    assert {:error, :connection_failed} =
             CatalogLoader.load(configured,
               connection_provider: RemoteMCPWireConnectionProvider
             )

    assert_receive {:remote_mcp_wire_request, "initialize", "Bearer rejected-credential",
                    _request}
  end

  test "refuses a redirect without forwarding credentials to its target" do
    target =
      start_supervised!({RemoteMCPWireServer, owner: self(), request_label: "redirect_target"})

    redirect =
      start_supervised!(
        {RemoteMCPWireServer, owner: self(), redirect_to: RemoteMCPWireServer.endpoint(target)}
      )

    configured = configured!(RemoteMCPWireServer.endpoint(redirect))
    on_exit(fn -> Connections.close(configured.connection_key) end)

    assert {:error, :connection_failed} =
             CatalogLoader.load(configured,
               connection_provider: RemoteMCPWireConnectionProvider
             )

    assert_receive {:remote_mcp_wire_request, "initialize", @authorization, _request}
    refute_receive {:remote_mcp_wire_request, "redirect_target", _authorization, _request}, 100
  end

  defp start_runtime!(overrides \\ []) do
    server =
      start_supervised!({RemoteMCPWireServer, owner: self(), authorization: @authorization})

    configured = configured!(RemoteMCPWireServer.endpoint(server), overrides)

    {:ok, integration} =
      CatalogLoader.load(configured, connection_provider: RemoteMCPWireConnectionProvider)

    {:ok, catalog} =
      IntegrationCatalog.new(
        application: %{},
        tenants: %{"tenant-wire" => %{"records" => integration}}
      )

    {:ok, remote} =
      IntegrationCatalog.resolve(catalog, "tenant-wire", "records", "lookup_customer")

    binding = %ToolBinding{
      name: "customer_lookup",
      type: :mcp,
      conversation_mode: :blocking,
      action: nil,
      remote: remote
    }

    %{binding: binding, catalog: catalog, key: configured.connection_key}
  end

  defp configured!(endpoint, overrides \\ []) do
    suffix = System.unique_integer([:positive, :monotonic])

    options =
      [
        scope: {:tenant, "tenant-wire"},
        integration_id: "records",
        configuration_generation: "configuration-#{suffix}",
        credential_generation: "credential-#{suffix}",
        catalog_generation: "catalog-#{suffix}",
        allowed_tools: ["lookup_customer"],
        client_config: [
          endpoint: endpoint,
          authentication: [type: :bearer, token: "controlled-tenant-credential"],
          use_sse: false
        ]
      ]
      |> Keyword.merge(overrides)

    {:ok, configured} = ConfiguredIntegration.new(options)
    configured
  end

  defp start_owner!(catalog, binding, suffix) do
    start_supervised!(
      {IntegrationOwner,
       activation_id: "activation-#{suffix}",
       tools: %{"customer_lookup" => binding},
       integrations: catalog,
       connection_provider: RemoteMCPWireConnectionProvider}
    )
  end
end
