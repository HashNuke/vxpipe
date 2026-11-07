defmodule Vxpipe.Console.Integration.SavedMCPRuntimeTest do
  use Vxpipe.Console.Test.SavedMCPRuntimeCase, async: false

  alias Vxpipe.Calls
  alias Vxpipe.Calls.EditorToolCatalog
  alias Vxpipe.Calls.MCPConnections
  alias Vxpipe.CallEngine.RemoteMCP.IntegrationOwner
  alias Vxpipe.Console.Test.FakeUserIdentity
  alias Vxpipe.Console.Test.SavedMCPWireConnectionProvider
  alias Vxpipe.Gateway.CallAdmission.CallEngineOptions
  alias Vxpipe.MCP.{ConnectionKey, Connections}
  alias Vxpipe.Persistence.MCP.ConnectionStore

  @token "synthetic-saved-runtime-token"
  @header "synthetic-saved-runtime-header"
  @key "saved-runtime-keyring-marker-123"

  test "an admitted web call executes its saved MCP tool and observes tenant disconnect", c do
    configure_admission(c.options)
    assert {:ok, draft} = Calls.save_call_spec(c.tenant, source(c.connection.id), c.options)
    assert draft.validation_errors == []

    assert {:ok, published} =
             Calls.publish_call_spec(c.tenant, draft.call_spec_id, draft.revision, c.options)

    created =
      api(
        c.secret,
        :post,
        "/api/tenants/#{c.tenant}/call-specs/#{published.call_spec_id}/calls",
        %{}
      )
      |> json_response(201)

    id = created["call"]["id"]
    base = "/api/tenants/#{c.tenant}/calls/#{id}"
    token = api(c.secret, :post, base <> "/join-tokens", %{}) |> json_response(201)
    join_path = base <> "/participants/#{token["participant_key"]}/sessions"
    join_secret = token["join_token"]["token"]

    # Reject browser-supplied adapters before consuming the single-use join token.
    assert %{"error" => %{"code" => "invalid_request"}} =
             api(join_secret, :post, join_path, %{
               "remote_mcp_connection_provider" => "untrusted"
             })
             |> json_response(400)

    admitted = api(join_secret, :post, join_path, %{}) |> json_response(201)
    assert {:ok, call} = Calls.fetch_call(c.tenant, id, c.options)
    assert call.state == :running
    assert admitted["call"]["state"] == "running"
    assert_private_absent(c, [created, token, admitted, call.plan])
    on_exit(fn -> close_admitted_call(c, call) end)

    {peer, channel} = connect_web(c, admitted["session"]["session_id"])

    send_web(peer, channel, "send-text", %{
      content: "Find customer-42.",
      options: %{run_immediately: true, audio_response: false}
    })

    assert_receive {:test_agent_runtime_stream, provider, request}, 5_000
    assert Enum.map(request.tools, & &1.name) == ["records__lookup_customer"]
    assert_private_absent(c, request)
    reply_tool(provider, "saved-first", "customer-42")

    assert_receive {:remote_mcp_wire_request, "tools/call", "Bearer " <> @token,
                    %{
                      "params" => %{
                        "name" => "lookup_customer",
                        "arguments" => %{"customer_id" => "customer-42"}
                      }
                    }},
                   5_000

    {completion, result} = await_tool_result(c, "saved-first", peer, channel)
    assert_private_absent(c, result)

    assert %{
             "status" => "completed",
             "result" => %{"content" => [%{"type" => "text", "text" => "found customer-42"}]}
           } = tool_outcome(result, "saved-first")

    reply_text(completion, "I found customer-42.")
    assert await_web(c, peer, channel, "bot-output")["data"]["text"] == "I found customer-42."
    await_web(c, peer, channel, "bot-stopped-speaking")

    disconnected = disconnect(c) |> json_response(200)
    assert disconnected["connection"]["status"] == "revoked"
    assert_secret_absent(disconnected)

    send_web(peer, channel, "send-text", %{
      content: "Now find customer-43.",
      options: %{run_immediately: true, audio_response: false}
    })

    assert_receive {:test_agent_runtime_stream, next_provider, next_request}, 5_000
    assert_private_absent(c, next_request)
    reply_tool(next_provider, "saved-after-disconnect", "customer-43")
    {failed_provider, failure} = await_tool_result(c, "saved-after-disconnect", peer, channel)
    assert_private_absent(c, failure)
    assert tool_outcome(failure, "saved-after-disconnect") == %{"status" => "failed"}
    refute_received {:remote_mcp_wire_request, "tools/call", _, _}
    reply_text(failed_provider, "The records connection is unavailable.")

    assert await_web(c, peer, channel, "bot-output")["data"]["text"] ==
             "The records connection is unavailable."

    await_web(c, peer, channel, "bot-stopped-speaking")
    assert {:ok, still_running} = Calls.fetch_call(c.tenant, id, c.options)
    assert still_running.state == :running
    assert still_running.incarnation_id == call.incarnation_id
    close_admitted_call(c, call)
    refute_received {:remote_mcp_wire_request, "tools/call", _, _}
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

  test "an unchanged published call spec works after explicit reconnect with a fresh generation",
       c do
    principal = FakeUserIdentity.principal()

    options =
      Keyword.put(c.options, :refresh_authority, fn ->
        FakeUserIdentity.authenticate(FakeUserIdentity.token())
      end)

    {old_call, route} = published_call(c, c.options)

    assert {:ok, before} =
             Calls.fetch_call_spec(
               c.tenant,
               route.call_spec_id,
               route.call_spec_revision,
               c.options
             )

    assert {:ok, revoked} =
             MCPConnections.disconnect(principal, c.tenant, c.connection.id, 1, options)

    assert revoked.generation == 2

    assert {:error, :mcp_connection_revoked} =
             ConnectionStore.resolve(c.context, c.tenant, c.connection.id)

    assert {:error, _} = Calls.prepare_call(c.principal, route.key, %{}, c.options)
    assert {:error, :mcp_connection_unavailable} = CallEngineOptions.build(c.options, old_call)

    check = fn tenant, configuration ->
      %URI{port: port} = URI.parse(configuration.endpoint)

      Vxpipe.MCP.ConnectionCheck.run_loopback_test(tenant, %{
        configuration
        | endpoint: "http://127.0.0.1:#{port}/mcp"
      })
    end

    options =
      Keyword.put(
        options,
        :mcp_connection_probe,
        {Vxpipe.Console.MCPConnectionProbe, connection_check: check}
      )

    assert {:ok, reconnected} =
             MCPConnections.reconnect(
               principal,
               c.tenant,
               c.connection.id,
               2,
               %{
                 "endpoint" => c.connection.endpoint,
                 "auth_method" => "bearer",
                 "credentials" => %{
                   "token" => @token,
                   "headers" => [%{"name" => "X-Workspace", "value" => @header}]
                 }
               },
               options
             )

    assert reconnected.id == c.connection.id
    assert reconnected.namespace == c.connection.namespace
    assert reconnected.generation == 3

    assert {:ok, ^before} =
             Calls.fetch_call_spec(
               c.tenant,
               route.call_spec_id,
               route.call_spec_revision,
               c.options
             )

    assert {:ok, fresh, _} = Calls.prepare_call(c.principal, route.key, %{}, c.options)

    assert %{"records__lookup_customer" => fresh_tool} =
             fresh.plan.participants["assistant"].tools

    assert map_size(fresh.plan.participants["assistant"].tools) == 1
    old_tool = old_call.plan.participants["assistant"].tools["records__lookup_customer"]
    assert fresh_tool.remote.integration_id == old_tool.remote.integration_id
    assert fresh_tool.remote.remote_name == old_tool.remote.remote_name
    assert fresh_tool.remote.credential_generation == "3"
    assert old_tool.remote.credential_generation == "1"

    assert {:error, :mcp_connection_unavailable} = CallEngineOptions.build(c.options, old_call)
    assert {:ok, runtime} = CallEngineOptions.build(c.options, fresh)
    assert_private_absent(c, [before, fresh.plan])

    {:ok, key} =
      ConnectionKey.new(
        scope: :tenant,
        tenant_id: c.tenant,
        integration_id: c.connection.id,
        credential_generation: "3"
      )

    on_exit(fn -> Connections.close(key) end)

    owner =
      start_supervised!(
        {IntegrationOwner,
         activation_id: fresh.id,
         tools: fresh.plan.participants["assistant"].tools,
         integrations: Keyword.fetch!(runtime, :mcp_catalog_store),
         connection_provider: SavedMCPWireConnectionProvider}
      )

    assert {:ok, %{"content" => [%{"text" => "found customer-42"}]}} =
             IntegrationOwner.execute(owner, "records__lookup_customer", %{
               "customer_id" => "customer-42"
             })

    assert_receive {:remote_mcp_wire_request, "tools/call", "Bearer " <> @token, _}, 2_000
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
end
