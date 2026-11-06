defmodule Vxpipe.Console.Integration.SavedMCPRuntimeTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Calls
  alias Vxpipe.Calls.{Administration, EditorToolCatalog}
  alias Vxpipe.CallEngine.RemoteMCP.IntegrationOwner
  alias Vxpipe.CallEngine.RemoteMCPWireServer
  alias Vxpipe.Console.Test.SavedMCPWireConnectionProvider
  alias Vxpipe.Gateway.CallAdmission.CallEngineOptions
  alias Vxpipe.MCP.{ConnectionKey, Connections}
  alias Vxpipe.Persistence.{CallSpecStore, CallStore, CredentialKeyring, CredentialStore, Repo}
  alias Vxpipe.Persistence.MCP.ConnectionStore

  @moduletag :integration
  @moduletag :capture_log
  @token "synthetic-saved-runtime-token"
  @header "synthetic-saved-runtime-header"
  @key "saved-runtime-keyring-marker-123"

  setup do
    if is_nil(Process.whereis(Repo)), do: start_supervised!(Repo)
    sandbox = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(sandbox) end)

    {:ok, keyring} =
      CredentialKeyring.new("fixture", %{"fixture" => @key})

    context = [repo: Repo, keyring: keyring]

    server =
      start_supervised!({RemoteMCPWireServer, owner: self(), authorization: "Bearer " <> @token})

    %URI{port: port} = URI.parse(RemoteMCPWireServer.endpoint(server))
    endpoint = "https://mcp.example.test:#{port}/mcp"

    options = [
      credential_repository: {CredentialStore, Repo},
      call_spec_repository: {CallSpecStore, Repo},
      call_repository: {CallStore, Repo},
      mcp_connection_repository: {ConnectionStore, context},
      registries: %{host_tools: %{}}
    ]

    configured = Application.get_env(:vxpipe_calls, Calls, [])
    Application.put_env(:vxpipe_calls, Calls, Keyword.merge(configured, options))
    on_exit(fn -> Application.put_env(:vxpipe_calls, Calls, configured) end)

    {:ok, tenant, key} = Administration.bootstrap_tenant("Saved MCP runtime", [:calls], options)
    {:ok, principal} = Administration.authenticate(tenant.key, key.secret, :calls, options)
    {:ok, other, _} = Administration.bootstrap_tenant("Other MCP runtime", [:calls], options)

    attributes = %{
      endpoint: endpoint,
      endpoint_identity: endpoint,
      server_name: "Records",
      auth_method: "bearer",
      catalog: [tool("lookup_customer")]
    }

    {:ok, connection} =
      ConnectionStore.create(context, tenant.key, attributes, %{
        "token" => @token,
        "headers" => [%{"name" => "X-Workspace", "value" => @header}]
      })

    %{
      tenant: tenant.key,
      other: other.key,
      principal: principal,
      options: options,
      context: context,
      connection: connection,
      attributes: attributes
    }
  end

  test "saved publication and preparation stay secret-free, then wire execution rechecks revocation",
       c do
    # Authoring can read metadata even when no decryption key is available.
    metadata_options =
      Keyword.put(
        c.options,
        :mcp_connection_repository,
        {ConnectionStore, Keyword.put(c.context, :keyring, :unconfigured)}
      )

    assert Enum.any?(
             EditorToolCatalog.list(c.tenant, metadata_options).tools,
             &(&1.type == "mcp" and &1.integration == c.connection.id)
           )

    refute Enum.any?(EditorToolCatalog.list(c.other, metadata_options).tools, &(&1.type == "mcp"))
    {call, route} = published_call(c, metadata_options)
    assert {:ok, stored} = Calls.fetch_call(c.tenant, call.id, c.options)

    for private <- [@token, c.connection.endpoint, "runtime_authentication", "client_config"] do
      refute :erlang.term_to_binary(stored.plan) =~ private
    end

    assert {:ok, runtime} = CallEngineOptions.build(c.options, stored)

    {:ok, key} =
      ConnectionKey.new(
        scope: :tenant,
        tenant_id: c.tenant,
        integration_id: c.connection.id,
        credential_generation: "1"
      )

    on_exit(fn -> Connections.close(key) end)

    owner =
      start_supervised!(
        {IntegrationOwner,
         activation_id: call.id,
         tools: call.plan.participants["assistant"].tools,
         integrations: Keyword.fetch!(runtime, :mcp_catalog_store),
         connection_provider: SavedMCPWireConnectionProvider}
      )

    assert {:ok, %{"content" => [%{"text" => "found customer-42"}]}} =
             IntegrationOwner.execute(owner, "records__lookup_customer", %{
               "customer_id" => "customer-42"
             })

    assert_receive {:remote_mcp_wire_request, "tools/call", "Bearer " <> @token, _}, 2_000
    assert {:ok, _} = ConnectionStore.revoke(c.context, c.tenant, c.connection.id, 1)

    assert {:error, :tool_failed} =
             IntegrationOwner.execute(owner, "records__lookup_customer", %{
               "customer_id" => "customer-43"
             })

    refute_received {:remote_mcp_wire_request, "tools/call", _, _}
    assert {:error, :mcp_connection_unavailable} = CallEngineOptions.build(c.options, stored)
    assert {:error, _} = Calls.prepare_call(c.principal, route.key, %{}, c.options)
  end

  test "schema refresh and credential replacement invalidate prepared pins without granting new tools",
       c do
    {call, route} = published_call(c, c.options)

    assert {:ok, _} =
             ConnectionStore.refresh_catalog(c.context, c.tenant, c.connection.id, 1, %{
               catalog: [tool("lookup_customer"), tool("new_tool")],
               server_name: "Renamed records"
             })

    assert {:error, :mcp_connection_unavailable} = CallEngineOptions.build(c.options, call)
    assert {:ok, refreshed, _} = Calls.prepare_call(c.principal, route.key, %{}, c.options)

    assert Map.keys(refreshed.plan.participants["assistant"].tools) == [
             "records__lookup_customer"
           ]

    assert {:ok, _} = CallEngineOptions.build(c.options, refreshed)

    assert {:ok, _} =
             ConnectionStore.replace(c.context, c.tenant, c.connection.id, 1, c.attributes, %{
               "token" => "replacement-token"
             })

    assert {:error, :mcp_connection_unavailable} = CallEngineOptions.build(c.options, refreshed)

    assert {:error, :mcp_connection_unavailable} =
             CallEngineOptions.build(c.options, %{call | tenant_key: c.other})
  end

  defp published_call(c, options) do
    assert {:ok, draft} = Calls.save_call_spec(c.tenant, source(c.connection.id), options)
    assert draft.validation_errors == []

    assert {:ok, published} =
             Calls.publish_call_spec(c.tenant, draft.call_spec_id, draft.revision, options)

    route = Enum.find(published.routes, &(&1.participant_ref == "caller"))
    assert {:ok, call, _token} = Calls.prepare_call(c.principal, route.key, %{}, options)
    {call, route}
  end

  test "supervised saved connection retirement keeps credentials out of OTP reports", c do
    :ok =
      :logger.add_primary_filter(
        :saved_mcp_runtime_capture,
        {fn event, owner ->
           send(owner, {:check_log, event})
           event
         end, self()}
      )

    on_exit(fn -> :logger.remove_primary_filter(:saved_mcp_runtime_capture) end)
    {call, _} = published_call(c, c.options)
    {:ok, runtime} = CallEngineOptions.build(c.options, call)

    {:ok, key} =
      ConnectionKey.new(
        scope: :tenant,
        tenant_id: c.tenant,
        integration_id: c.connection.id,
        credential_generation: "1"
      )

    on_exit(fn -> Connections.close(key) end)

    options = [
      activation_id: call.id,
      tools: call.plan.participants["assistant"].tools,
      integrations: Keyword.fetch!(runtime, :mcp_catalog_store),
      connection_provider: SavedMCPWireConnectionProvider
    ]

    spec = Supervisor.child_spec({IntegrationOwner, options}, restart: :permanent)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        supervisor =
          start_supervised!(%{
            id: :saved_mcp_owner_supervisor,
            start: {Supervisor, :start_link, [[spec], [strategy: :one_for_one]]}
          })

        [{_, owner, _, _}] = Supervisor.which_children(supervisor)
        monitor = Process.monitor(owner)
        send(owner, {:vxpipe_mcp_credential_revoked, key})
        assert_receive {:DOWN, ^monitor, :process, ^owner, :credential_revoked}, 2_000
        [{_, replacement, _, _}] = Supervisor.which_children(supervisor)
        replacement_monitor = Process.monitor(replacement)
        {:ok, connection} = Connections.lookup(key)
        client = Vxpipe.MCP.Connection.client(connection)
        :ok = GenServer.stop(client, :fixture_connection_lost)

        assert_receive {:DOWN, ^replacement_monitor, :process, ^replacement, :connection_lost},
                       2_000

        _ = Supervisor.which_children(supervisor)
      end)

    Logger.flush()
    reports = collect_reports()

    assert Enum.any?(reports, fn event ->
             case event do
               %{msg: {:report, %{label: {:supervisor, _}}}} -> true
               _ -> false
             end
           end)

    for marker <- [@token, @header, @key] do
      refute log =~ marker
      refute :erlang.term_to_binary(reports) =~ marker
    end
  end

  defp collect_reports do
    receive do
      {:check_log, event} -> [event | collect_reports()]
    after
      0 -> []
    end
  end

  defp tool(name),
    do: %{
      "name" => name,
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{"customer_id" => %{"type" => "string"}},
        "required" => ["customer_id"]
      }
    }

  defp source(id),
    do: %{
      schema_version: "20260915.01",
      wait_sounds: %{call_setup: nil},
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Use the records tool.",
          first_message: %{mode: "wait_for_input"},
          capabilities: %{model_inference: %{provider: "fixture", model: "test"}},
          tools: %{
            "records__lookup_customer" => %{type: "mcp", integration: id, tool: "lookup_customer"}
          },
          transfers: []
        }
      }
    }
end
