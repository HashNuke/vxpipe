defmodule Vxpipe.Console.Integration.SavedMCPCatalogJobsTest do
  use Vxpipe.Console.Test.SavedMCPRuntimeCase, async: false

  alias Vxpipe.Calls
  alias Vxpipe.MCP.{CheckHTTPFixture, Connection}
  alias Vxpipe.Persistence.Repo
  alias Vxpipe.Persistence.MCP.CatalogRefreshStore
  alias Vxpipe.Persistence.Schema.MCPConnection
  alias Vxpipe.Persistence.Test.CatalogDiscoveryProtocol

  @oban Vxpipe.Console.TestCatalogJobs
  @policy [expiry_seconds: 3_600, reschedule_after_seconds: 1_800, batch_size: 100]

  test "catalog maintenance preserves active pins and survives the call ending", c do
    configure_admission(Keyword.put(c.options, :managed_cleanup, true))
    active = admit_web_call(c, prepare_web_call(c, source(c.connection.id)))
    assert_receive {:remote_mcp_wire_initialized, call_session}, 2_000
    original_connection = owned_mcp(c, active.call)

    changed_tool = put_in(tool("lookup_customer"), ["inputSchema", "required"], [])
    catalog = [changed_tool, tool("new_tool")]

    server =
      start_supervised!(
        {CheckHTTPFixture,
         owner: self(),
         pause_catalog: true,
         catalogs_by_authorization: %{"Bearer synthetic-saved-runtime-token" => catalog}}
      )

    context = Keyword.put(c.context, :oban, @oban)
    configured = Application.fetch_env!(:vxpipe_calls, Calls)

    configure(
      :vxpipe_calls,
      Calls,
      Keyword.merge(configured,
        mcp_catalog_refresh_repository: {CatalogRefreshStore, context}
      )
    )

    configure(
      :vxpipe_calls,
      :mcp_catalog_protocol,
      {CatalogDiscoveryProtocol, [owner: self(), endpoint: CheckHTTPFixture.endpoint(server)]}
    )

    start_supervised!(
      {Oban,
       name: @oban,
       repo: Repo,
       testing: :disabled,
       notifier: {Oban.Notifiers.PG, []},
       peer: {Oban.Peers.Isolated, [leader?: false]},
       queues: [mcp_catalog: 1]}
    )

    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:oban, :job, :stop],
        &CatalogDiscoveryProtocol.job_finished/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    stale!(c.connection.id)
    assert {:ok, 1} = CatalogRefreshStore.enqueue_due(context, @policy)
    assert_receive {:check_catalog_paused, first_handler, first_reference}, 3_000
    {provider, before} = model_input(c, active, "Find customer-42 during maintenance.")
    reply_tool(provider, "during-maintenance", "customer-42")
    {completion, result} = await_tool_result(c, "during-maintenance", active.peer, active.channel)
    assert %{"status" => "completed"} = tool_outcome(result, "during-maintenance")
    finish_text(c, active, completion, "Found customer-42.")
    assert_receive {:remote_mcp_wire_session_request, "tools/call", [^call_session]}
    send(first_handler, {:resume_check_catalog, first_reference})
    assert_receive {:catalog_job_finished, _, first_id}, 3_000

    assert Repo.get_by!(MCPConnection, public_id: c.connection.id).catalog == %{
             "tools" => catalog
           }

    {provider, after_refresh} = model_input(c, active, "Continue with the original tools.")
    assert after_refresh.tools == before.tools
    assert Enum.map(after_refresh.tools, & &1.name) == ["records__lookup_customer"]
    assert owned_mcp(c, active.call) == original_connection
    finish_text(c, active, provider, "Still connected.")

    stale!(c.connection.id)
    assert {:ok, 1} = CatalogRefreshStore.enqueue_due(context, @policy)
    assert_receive {:check_catalog_paused, second_handler, second_reference}, 3_000
    [{_, maintenance, _, _}] = DynamicSupervisor.which_children(Vxpipe.MCP.CheckSupervisor)
    maintenance_monitor = Process.monitor(maintenance)
    client = Connection.client(original_connection)
    client_monitor = Process.monitor(client)

    {:ok, cleanup} =
      Vxpipe.Gateway.CallCleanupSupervisor.lookup(%{
        tenant_key: c.tenant,
        call_id: active.call.id,
        room_id: active.call.room_id,
        incarnation_id: active.call.incarnation_id
      })

    cleanup_monitor = Process.monitor(cleanup)

    {:ok, room_monitor} =
      Vxpipe.CallEngine.monitor_room_completion(
        c.tenant,
        active.call.room_id,
        active.call.incarnation_id
      )

    assert api(c.secret, :post, "/api/tenants/#{c.tenant}/calls/#{active.call.id}/hangup", %{}).status ==
             200

    assert_receive {:DOWN, ^room_monitor, :process, _, _}, 1_000
    assert_receive {:DOWN, ^cleanup_monitor, :process, ^cleanup, :normal}, 3_000
    assert_receive {:DOWN, ^client_monitor, :process, ^client, _}, 1_000
    assert_receive {:remote_mcp_wire_delete, [^call_session]}, 1_000
    assert {:ok, %{state: :ended}} = Calls.fetch_call(c.tenant, active.call.id, c.options)
    _ = :sys.get_state(maintenance)
    refute_received {:DOWN, ^maintenance_monitor, :process, ^maintenance, _}
    send(second_handler, {:resume_check_catalog, second_reference})
    assert_receive {:catalog_job_finished, _, second_id}, 3_000
    refute first_id == second_id
    assert_receive {:DOWN, ^maintenance_monitor, :process, ^maintenance, _}, 1_000
    assert Repo.get_by!(MCPConnection, public_id: c.connection.id).refreshed_at != nil
  end

  defp stale!(id) do
    Repo.get_by!(MCPConnection, public_id: id)
    |> Ecto.Changeset.change(refreshed_at: nil, refresh_scheduled_at: nil)
    |> Repo.update!()
  end

  defp configure(application, key, value) do
    previous = Application.fetch_env(application, key)
    Application.put_env(application, key, value)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(application, key, value)
        :error -> Application.delete_env(application, key)
      end
    end)
  end
end
