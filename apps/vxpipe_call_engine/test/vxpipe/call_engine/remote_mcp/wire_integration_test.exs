defmodule Vxpipe.CallEngine.RemoteMCP.WireIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

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
    %{binding: binding, catalog: catalog, key: key, configured: configured} = start_runtime!()

    assert_receive {:remote_mcp_wire_initialized, first_discovery}
    assert_receive {:remote_mcp_wire_delete, [^first_discovery]}
    assert :error = Connections.lookup(key)

    owner = start_owner!(catalog, binding, "wire-success")
    assert_receive {:remote_mcp_wire_initialized, call_session}

    assert {:ok, _integration} =
             CatalogLoader.load(configured, connection_provider: RemoteMCPWireConnectionProvider)

    assert_receive {:remote_mcp_wire_initialized, second_discovery}
    assert second_discovery != call_session
    assert first_discovery != second_discovery
    assert_receive {:remote_mcp_wire_delete, [^second_discovery]}
    refute_receive {:remote_mcp_wire_delete, [^call_session]}, 0

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

    assert_receive {:remote_mcp_wire_session_request, "tools/call", [^call_session]}
  end

  test "rejects invalid arguments before sending the tool request" do
    %{binding: binding, catalog: catalog} = start_runtime!()

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
      %{binding: binding, catalog: catalog} =
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

    assert {:error, :connection_failed} =
             CatalogLoader.load(configured,
               connection_provider: RemoteMCPWireConnectionProvider
             )

    assert_receive {:remote_mcp_wire_request, "initialize", @authorization, _request}
    refute_receive {:remote_mcp_wire_request, "redirect_target", _authorization, _request}, 100
  end

  for method <- ["initialize", "tools/list"], cancellation <- [:caller_death, :deadline] do
    @tag capture_log: true
    test "#{cancellation} closes the catalog #{method} POST socket" do
      server =
        start_supervised!({Vxpipe.MCP.CheckHTTPFixture, owner: self(), hold: unquote(method)})

      endpoint = Vxpipe.MCP.CheckHTTPFixture.endpoint(server)
      timeout = if unquote(cancellation) == :deadline, do: 500, else: 5_000

      configured =
        configured!(endpoint,
          client_config: [endpoint: endpoint, use_sse: false],
          discovery_deadline_ms: timeout
        )

      tasks = start_supervised!({Task.Supervisor, name: __MODULE__.CatalogTasks})

      task =
        Task.Supervisor.async_nolink(tasks, fn ->
          CatalogLoader.load(configured, connection_provider: RemoteMCPWireConnectionProvider)
        end)

      assert_receive {:check_http_held, unquote(method)}, 1_000

      if unquote(cancellation) == :caller_death do
        Task.shutdown(task, :brutal_kill)
      else
        assert {:error, _reason} = Task.await(task, 2_000)
      end

      assert_receive {:check_http_closed, unquote(method), {:error, :closed}}, 1_000
    end
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

    %{binding: binding, catalog: catalog, key: configured.connection_key, configured: configured}
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
       session_supervisor: Vxpipe.CallEngine.RemoteMCPFixture.session_supervisor!(),
       activation_id: "activation-#{suffix}",
       tools: %{"customer_lookup" => binding},
       integrations: Vxpipe.CallEngine.RemoteMCPFixture.source!(catalog),
       connection_provider: RemoteMCPWireConnectionProvider}
    )
  end
end
