defmodule Vxpipe.Console.Integration.SavedMCPCatalogAudioTest do
  use Vxpipe.Console.Test.SavedMCPRuntimeCase, async: false

  alias Vxpipe.Calls
  alias Vxpipe.Console.Test.SavedMCPTelephonyCase, as: Phone
  alias Vxpipe.MCP.CheckHTTPFixture
  alias Vxpipe.Persistence.Repo
  alias Vxpipe.Persistence.MCP.CatalogRefreshStore
  alias Vxpipe.Persistence.Schema.MCPConnection
  alias Vxpipe.Persistence.Test.CatalogDiscoveryProtocol

  @oban Vxpipe.Console.TestAudioCatalogJobs

  test "carrier audio continues while catalog discovery is held", c do
    c = Phone.configure(c)
    active = Phone.incoming(c, Phone.publish(c, :incoming))
    server = start_supervised!({CheckHTTPFixture, owner: self(), pause_catalog: true})
    context = Keyword.put(c.context, :oban, @oban)
    previous = Application.get_env(:vxpipe_calls, :mcp_catalog_protocol)

    Application.put_env(
      :vxpipe_calls,
      :mcp_catalog_protocol,
      {CatalogDiscoveryProtocol, [owner: self(), endpoint: CheckHTTPFixture.endpoint(server)]}
    )

    on_exit(fn -> Application.put_env(:vxpipe_calls, :mcp_catalog_protocol, previous) end)
    configured = Application.fetch_env!(:vxpipe_calls, Calls)

    Application.put_env(
      :vxpipe_calls,
      Calls,
      Keyword.put(configured, :mcp_catalog_refresh_repository, {CatalogRefreshStore, context})
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
    record = Repo.get_by!(MCPConnection, public_id: c.connection.id)
    Repo.update!(Ecto.Changeset.change(record, refreshed_at: nil))

    assert {:ok, 1} =
             CatalogRefreshStore.enqueue_due(context,
               expiry_seconds: 3_600,
               reschedule_after_seconds: 1_800,
               batch_size: 100
             )

    assert_receive {:check_catalog_paused, peer, reference}, 3_000
    {provider, _} = Phone.model_input(c, active, 0, "Speak during maintenance.")
    Phone.finish_speech(c, active, provider, "Audio continues during maintenance.")
    send(peer, {:resume_check_catalog, reference})
    assert_receive {:catalog_job_finished, _, _}, 3_000
    assert Repo.get_by!(MCPConnection, public_id: c.connection.id).refreshed_at != nil
    close_admitted_call(c, active.call)
  end
end
