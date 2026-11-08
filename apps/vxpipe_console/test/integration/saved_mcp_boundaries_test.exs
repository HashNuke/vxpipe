defmodule Vxpipe.Console.Integration.SavedMCPBoundariesTest do
  use Vxpipe.Console.Test.SavedMCPRuntimeCase, async: false

  alias Vxpipe.Calls
  alias Vxpipe.Calls.{EditorToolCatalog, SavedMCPCatalog}
  alias Vxpipe.Console.Test.SavedMCPRepository
  alias Vxpipe.Persistence.MCP.ConnectionStore

  test "foreign saved selections fail publication while that tenant's own connection executes",
       c do
    foreign = %{c | tenant: c.other, secret: c.other_secret}
    assert {:ok, draft} = Calls.save_call_spec(foreign.tenant, source(c.connection.id), c.options)
    refute draft.validation_errors == []

    assert {:error, _} =
             Calls.publish_call_spec(
               foreign.tenant,
               draft.call_spec_id,
               draft.revision,
               c.options
             )

    refute_received {:remote_mcp_wire_request, _, _, _}

    token = "synthetic-other-tenant-token"
    header = "synthetic-other-tenant-header"

    server =
      start_supervised!(
        {Vxpipe.CallEngine.RemoteMCPWireServer,
         owner: self(), authorization: "Bearer " <> token, headers: [{"x-workspace", header}]}
      )

    %URI{port: port} = URI.parse(Vxpipe.CallEngine.RemoteMCPWireServer.endpoint(server))
    endpoint = "https://mcp.example.test:#{port}/mcp"
    attributes = %{c.attributes | endpoint: endpoint, endpoint_identity: endpoint}

    assert {:ok, connection} =
             ConnectionStore.create(c.context, foreign.tenant, attributes, %{
               "token" => token,
               "headers" => [%{"name" => "X-Workspace", "value" => header}]
             })

    own =
      Map.merge(foreign, %{connection: connection, token: token, private_values: [token, header]})

    configure_admission(own.options)
    prepared = prepare_web_call(own, source(connection.id))
    active = admit_web_call(own, prepared)
    complete_lookup(own, active, "tenant-owned", "customer-42")
    close_admitted_call(own, active.call)
    refute_received {:remote_mcp_wire_request, "tools/call", _, _}
  end

  test "an empty saved connection remains visible without a selectable or phantom tool", c do
    assert {:ok, _} =
             ConnectionStore.refresh_catalog(
               c.context,
               c.tenant,
               c.connection.id,
               1,
               Map.take(c.connection, [:refreshed_at, :refresh_scheduled_at]),
               %{
                 catalog: [],
                 server_name: "Empty records"
               }
             )

    assert {:ok, [id]} = SavedMCPCatalog.names(c.tenant, c.options)
    assert id == c.connection.id
    refute Enum.any?(EditorToolCatalog.list(c.tenant, c.options).tools, &(&1.type == "mcp"))
    assert {:ok, draft} = Calls.save_call_spec(c.tenant, source(id), c.options)
    refute draft.validation_errors == []

    assert {:error, _} =
             Calls.publish_call_spec(c.tenant, draft.call_spec_id, draft.revision, c.options)

    refute_received {:remote_mcp_wire_request, _, _, _}

    configure_admission(c.options)
    active = admit_web_call(c, prepare_web_call(c, native_source(c)))
    {provider, request} = model_input(c, active, "Hello.")
    assert request.tools == []
    finish_text(c, active, provider, "The native model still works.")
    refute_received {:remote_mcp_wire_request, _, _, _}
    close_admitted_call(c, active.call)
  end

  test "changed schemas reject stale admission and constrain fresh model-selected arguments", c do
    configure_admission(c.options)
    prepared = prepare_web_call(c, source(c.connection.id))

    changed =
      put_in(tool("lookup_customer"), ["inputSchema", "properties", "customer_id", "enum"], [
        "customer-43"
      ])

    assert {:ok, _} =
             ConnectionStore.refresh_catalog(
               c.context,
               c.tenant,
               c.connection.id,
               1,
               Map.take(c.connection, [:refreshed_at, :refresh_scheduled_at]),
               %{
                 catalog: [changed, tool("new_tool")],
                 server_name: "Records"
               }
             )

    failed_admission(c, prepared)

    active = admit_web_call(c, prepare_existing_web_call(c, prepared.create_path))
    {provider, request} = model_input(c, active, "Find the customer.")
    assert [descriptor] = request.tools
    assert descriptor.name == "records__lookup_customer"
    assert descriptor.input_schema["properties"]["customer_id"]["enum"] == ["customer-43"]
    reply_tool(provider, "old-arguments", "customer-42")

    assert await_web(c, active.peer, active.channel, "error-response")["data"] == %{
             "error" => "The agent could not generate a response. Please try again."
           }

    refute_received {:remote_mcp_wire_request, "tools/call", _, _}
    complete_lookup(c, active, "new-arguments", "customer-43")
    close_admitted_call(c, active.call)
    refute_received {:remote_mcp_wire_request, "tools/call", _, _}
  end

  test "deleted selected tools reject stale admission and fresh preparation without initialization",
       c do
    configure_admission(c.options)
    prepared = prepare_web_call(c, source(c.connection.id))

    assert {:ok, _} =
             ConnectionStore.refresh_catalog(
               c.context,
               c.tenant,
               c.connection.id,
               1,
               Map.take(c.connection, [:refreshed_at, :refresh_scheduled_at]),
               %{
                 catalog: [],
                 server_name: "Records"
               }
             )

    failed_admission(c, prepared)
    failed = api(c.secret, :post, prepared.create_path, %{})
    rejected = json_response(failed, 422)
    assert rejected["error"]["code"] == "call_spec_resolution_failed"
    assert_private_absent(c, rejected)
    refute_received {:remote_mcp_wire_request, _, _, _}
  end

  test "MCP storage outage fails preparation while native-only admission never queries it", c do
    {c, repository} = observed_repository(c)
    configure_admission(c.options)
    prepared = prepare_web_call(c, source(c.connection.id))
    SavedMCPRepository.operations(repository)
    :ok = SavedMCPRepository.available(repository, false)
    failed = api(c.secret, :post, prepared.create_path, %{})
    assert failed.status == 503
    assert_private_absent(c, json_response(failed, 503))
    assert {:list, [c.tenant]} in SavedMCPRepository.operations(repository)
    refute_received {:remote_mcp_wire_request, _, _, _}

    active = admit_web_call(c, prepare_web_call(c, native_source(c)))
    {provider, request} = model_input(c, active, "Hello.")
    assert request.tools == []
    finish_text(c, active, provider, "The native model remains available.")
    assert SavedMCPRepository.operations(repository) == []
    refute_received {:remote_mcp_wire_request, _, _, _}
    close_admitted_call(c, active.call)
  end

  test "MCP storage outage after preparation rejects startup before any protocol request", c do
    {c, repository} = observed_repository(c)
    configure_admission(c.options)
    prepared = prepare_web_call(c, source(c.connection.id))
    SavedMCPRepository.operations(repository)
    :ok = SavedMCPRepository.available(repository, false)
    failed_admission(c, prepared)
    assert SavedMCPRepository.operations(repository) == [{:resolve, [c.tenant, c.connection.id]}]
  end

  test "an admitted room observes storage outage at its next credential resolution", c do
    {c, repository} = observed_repository(c)
    configure_admission(c.options)
    active = admit_web_call(c, prepare_web_call(c, source(c.connection.id)))
    complete_lookup(c, active, "before-outage", "customer-42")
    SavedMCPRepository.operations(repository)
    :ok = SavedMCPRepository.available(repository, false)
    {provider, _request} = model_input(c, active, "Find another customer.")
    reply_tool(provider, "during-outage", "customer-43")
    {completion, failure} = await_tool_result(c, "during-outage", active.peer, active.channel)
    assert_private_absent(c, failure)
    assert tool_outcome(failure, "during-outage") == %{"status" => "failed"}
    assert {:resolve, [c.tenant, c.connection.id]} in SavedMCPRepository.operations(repository)
    finish_text(c, active, completion, "Records are temporarily unavailable.")
    assert {:ok, current} = Calls.fetch_call(c.tenant, active.call.id, c.options)
    assert current.state == :running
    assert current.incarnation_id == active.call.incarnation_id
    close_admitted_call(c, active.call)
    refute_received {:remote_mcp_wire_request, "tools/call", _, _}
  end

  defp complete_lookup(c, active, id, customer) do
    {provider, request} = model_input(c, active, "Find #{customer}.")
    assert Enum.map(request.tools, & &1.name) == ["records__lookup_customer"]
    reply_tool(provider, id, customer)
    authorization = "Bearer " <> Map.get(c, :token, "synthetic-saved-runtime-token")

    assert_receive {:remote_mcp_wire_request, "tools/call", ^authorization,
                    %{
                      "params" => %{
                        "name" => "lookup_customer",
                        "arguments" => %{"customer_id" => ^customer}
                      }
                    }},
                   5_000

    {completion, result} = await_tool_result(c, id, active.peer, active.channel)
    assert_private_absent(c, result)

    assert tool_outcome(result, id) == %{
             "status" => "completed",
             "result" => %{
               "content" => [%{"type" => "text", "text" => "found #{customer}"}]
             }
           }

    finish_text(c, active, completion, "Found #{customer}.")
  end

  defp native_source(c),
    do: put_in(source(c.connection.id), [:participants, "assistant", :tools], %{})

  defp observed_repository(c) do
    repository =
      start_supervised!({Agent, fn -> %{available: true, context: c.context, operations: []} end})

    options = Keyword.put(c.options, :mcp_connection_repository, {SavedMCPRepository, repository})
    configured = Application.get_env(:vxpipe_calls, Calls, [])
    Application.put_env(:vxpipe_calls, Calls, Keyword.merge(configured, options))
    {%{c | options: options}, repository}
  end
end
